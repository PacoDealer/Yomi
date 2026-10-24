import Foundation

// Usage: main write|read <port> <jar dir>   (run.sh runs both, as two processes)
let args = CommandLine.arguments
let phase = args[1], port = args[2]
PluginCookieJar.directory = URL(fileURLWithPath: args[3], isDirectory: true)
let site = "http://127.0.0.1:\(port)"

var failures = 0, checks = 0
func expect(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !ok { failures += 1; print("✗ \(name) \(detail())") }
}

func get(_ jar: PluginCookieJar, _ path: String) -> (body: String, status: Int, url: URL?) {
    let sem = DispatchSemaphore(value: 0)
    var out = (body: "", status: 0, url: URL?.none)
    let url = URL(string: site + path)!
    jar.session.dataTask(with: url) { data, response, _ in
        out.body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        out.status = (response as? HTTPURLResponse)?.statusCode ?? 0
        out.url = response?.url
        sem.signal()
    }.resume()
    sem.wait()
    jar.didFinishRequest(to: out.url ?? url)
    return out
}

if phase == "write" {
    // MARK: Isolation
    let a = PluginCookieJar.forPlugin("com.test.a"), b = PluginCookieJar.forPlugin("com.test.b")
    expect("same id → same jar", PluginCookieJar.forPlugin("com.test.a") === a)
    _ = get(a, "/set?login=alice&persist=1")
    _ = get(a, "/set?visit=1")                       // session-only cookie
    let seenA = get(a, "/echo").body, seenB = get(b, "/echo").body
    expect("plugin A sends its cookies", seenA.contains("login=alice") && seenA.contains("visit=1"), seenA)
    expect("plugin B doesn't get A's cookies", seenB.isEmpty, seenB)
    // A cookie set during a redirect lands in the jar that made the request (the system follows it).
    _ = get(b, "/redir?to=/set%3Fviaredirect%3D1")
    let shared = HTTPCookieStorage.shared.cookies(for: URL(string: site)!)?.map(\.name) ?? []
    expect("didFinishRequest mirrors into the shared store (covers)", shared.contains("login"), "\(shared)")

    // MARK: Imported cookies (Cloudflare check / Website page)
    let c = PluginCookieJar.forPlugin("com.test.c")
    let clearance = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "cf_clearance", .value: "ok",
                                            .expires: Date().addingTimeInterval(3600)])!
    c.importCookies([clearance])
    expect("imported cookie is sent", get(c, "/echo").body.contains("cf_clearance=ok"))
    expect("imported cookie not in another jar", !get(b, "/echo").body.contains("cf_clearance"))

    // MARK: Host matching
    func cookie(_ domain: String) -> HTTPCookie {
        HTTPCookie(properties: [.domain: domain, .path: "/", .name: "n", .value: domain])!
    }
    let pool = [cookie("example.com"), cookie(".example.com"), cookie("www.example.com"), cookie("other.com"),
                cookie("badexample.com")]
    let forWWW = PluginCookieJar.matching(pool, host: "WWW.example.com").map(\.value)
    expect("www gets its own + parent domain", Set(forWWW) == ["example.com", ".example.com", "www.example.com"], "\(forWWW)")
    let forBare = PluginCookieJar.matching(pool, host: "example.com").map(\.value)
    expect("bare host doesn't get subdomain cookies", Set(forBare) == ["example.com", ".example.com"], "\(forBare)")
    expect("empty host gets nothing", PluginCookieJar.matching(pool, host: "").isEmpty)

    // MARK: Clear
    let d = PluginCookieJar.forPlugin("com.test.d")
    _ = get(d, "/set?gone=1&persist=1")
    let dFile = PluginCookieJar.directory!.appendingPathComponent("com.test.d.plist")
    expect("persistent cookie saved to disk", FileManager.default.fileExists(atPath: dFile.path))
    PluginCookieJar.remove(id: "com.test.d")
    expect("remove forgets cookies", get(d, "/echo").body.isEmpty)
    expect("remove deletes the file", !FileManager.default.fileExists(atPath: dFile.path))

    // MARK: Unsafe ids are never written to disk
    let evil = PluginCookieJar.forPlugin("../escape")
    evil.importCookies([clearance])
    let parent = PluginCookieJar.directory!.deletingLastPathComponent()
    expect("unsafe id writes no file", !FileManager.default.fileExists(atPath: parent.appendingPathComponent("escape.plist").path))

    // MARK: Redirect check
    let guardDelegate = PluginRedirectGuard()
    func follows(_ to: String) -> Bool {
        var followed: URLRequest?
        let response = HTTPURLResponse(url: URL(string: "https://site.example/")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        guardDelegate.urlSession(URLSession.shared, task: URLSession.shared.dataTask(with: URL(string: "https://site.example/")!),
                                 willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: to)!)) { followed = $0 }
        return followed != nil
    }
    expect("redirect to another site followed", follows("https://cdn.example/x"))
    expect("redirect to 127.0.0.1 refused", !follows("http://127.0.0.1:53000/bridge"))
    expect("redirect to localhost refused", !follows("http://localhost/x"))
    expect("redirect to file:// refused", !follows("file:///etc/passwd"))
    // End to end: a loopback redirect isn't followed, the plugin gets the 302 itself.
    let r = get(a, "/redir?to=http://127.0.0.1:\(port)/echo")
    expect("live loopback redirect returns the 302", r.status == 302, "status \(r.status)")

    // MARK: Time limit (fake clock)
    var clock = Date(timeIntervalSince1970: 0)
    let gate = PluginCallGate(limit: 120, now: { clock })
    expect("no limit outside a call", gate.allowsRequest())
    let ok = gate.run([1]) { () -> [Int] in
        clock += 100
        return gate.allowsRequest() ? [1, 2] : []
    }
    expect("call within the limit returns its result", ok == [1, 2], "\(ok)")
    let late = gate.run([Int]()) { () -> [Int] in
        clock += 121
        _ = gate.allowsRequest()
        return [9, 9, 9]                                // the partial result a plugin might assemble
    }
    expect("call over the limit returns empty, not partial", late.isEmpty, "\(late)")
    expect("next call starts fresh", gate.run(false) { gate.allowsRequest() })
    // Nested calls share the outer call's time.
    // 70 s in the outer call + 70 s in an inner one = 140 s > 120: the inner call must not have restarted the clock.
    var innerAllowed = true
    let nested = gate.run("empty") { () -> String in
        clock += 70
        _ = gate.run(0) { () -> Int in clock += 70; innerAllowed = gate.allowsRequest(); return 1 }
        return "partial"
    }
    expect("nested call doesn't get a new limit", !innerAllowed && nested == "empty", nested)
    // restart(): each page of a paged list gets the full limit…
    let paged = gate.run(false) { () -> Bool in
        for _ in 0..<5 { gate.restart(); clock += 100; if !gate.allowsRequest() { return false } }
        return true
    }
    expect("restart gives each page the limit", paged)
    // …but can't undo a timeout that already happened.
    var afterRestart = true
    let undone = gate.run("empty") { () -> String in
        clock += 200; _ = gate.allowsRequest()
        gate.restart()
        afterRestart = gate.allowsRequest()
        return "partial"
    }
    expect("restart doesn't revive a timed-out call", !afterRestart)
    expect("…and the call still returns empty", undone == "empty", undone)
} else {
    // A new process: only what was saved to disk.
    let a = PluginCookieJar.forPlugin("com.test.a")
    let seen = get(a, "/echo").body
    expect("persistent cookie survives a relaunch", seen.contains("login=alice"), seen)
    expect("session cookie doesn't survive a relaunch", !seen.contains("visit=1"), seen)
    expect("imported Cloudflare cookie survives", get(PluginCookieJar.forPlugin("com.test.c"), "/echo").body.contains("cf_clearance=ok"))
    expect("removed jar stays empty", get(PluginCookieJar.forPlugin("com.test.d"), "/echo").body.isEmpty)
    expect("still isolated after relaunch", !get(PluginCookieJar.forPlugin("com.test.b"), "/echo").body.contains("login"))
    PluginCookieJar.clearAll()
    let files = (try? FileManager.default.contentsOfDirectory(atPath: PluginCookieJar.directory!.path)) ?? []
    expect("clearAll deletes every jar file", !files.contains { $0.hasSuffix(".plist") }, "\(files)")
    expect("clearAll empties loaded jars", get(a, "/echo").body.isEmpty)
}

print(failures == 0 ? "\(phase): \(checks) checks passed" : "\(phase): \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
