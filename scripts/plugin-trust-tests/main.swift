import CryptoKit
import Foundation

var failures = 0, checks = 0
func expect(_ name: String, _ body: String, status: Int = 200, sha: String? = nil, fails: Bool) {
    checks += 1
    let response = HTTPURLResponse(url: URL(string: "https://example.com/p.js")!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!
    var failed = false
    do { try PluginScript.validate(Data(body.utf8), response: response, sha256: sha) } catch {
        failed = true
        if !fails { print("✗ \(name): \(error.localizedDescription)") }
    }
    if failed != fails { failures += 1; print("✗ \(name): expected \(fails ? "refusal" : "acceptance")") }
}
let good = "const BASE_URL = 'https://x.y';\nfunction getPopularManga(page) { return []; }\n"
let hash = SHA256.hash(data: Data(good.utf8)).map { String(format: "%02x", $0) }.joined()

expect("plain plugin", good, fails: false)
expect("matching hash", good, sha: hash, fails: false)
expect("matching hash, upper case", good, sha: hash.uppercased(), fails: false)
expect("empty hash string = no check", good, sha: "", fails: false)
expect("wrong hash", good, sha: String(repeating: "0", count: 64), fails: true)
expect("truncated file vs hash", String(good.dropLast(10)), sha: hash, fails: true)
expect("truncated file, syntax", "function getPopularManga(page) { return [", fails: true)
expect("HTTP 404", good, status: 404, fails: true)
expect("HTTP 503", good, status: 503, fails: true)
expect("empty body", "  \n ", fails: true)
expect("CDN error page as 200", "<!DOCTYPE html><html><body>Site Not Found</body></html>", fails: true)
expect("html without doctype", "<html><head></head></html>", fails: true)
expect("throws at run time is still fine (syntax only)", "throw new Error('x');", fails: false)
expect("bundled IIFE", "(function(){var a=1;globalThis.plugin={id:'x'};})();", fails: false)


// Every real plugin must pass: Yomi's catalog (Firebase/public) and whatever the simulator has installed (LNReader…).
// S190: PluginNetworkPolicy — what SOURCE.fetch may reach, which plugin ids may name a file.
func policy(_ cond: Bool, _ what: String) { checks += 1; if !cond { failures += 1; print("✗ policy: \(what)") } }
for ok in ["https://wetried.com/x", "http://example.org", "https://192.168.1.5:4567/api"] {
    policy(PluginNetworkPolicy.allows(URL(string: ok)!), "allows \(ok)")
}
for bad in ["file:///var/mobile/x.db", "http://127.0.0.1:8080/dalvik", "http://localhost:1/", "http://[::1]:9/",
            "data:text/plain,hi", "ftp://x.org/a", "http://169.254.169.254/", "http://0.0.0.0:80/", "http://a.localhost/"] {
    policy(!PluginNetworkPolicy.allows(URL(string: bad)!), "refuses \(bad)")
}
for ok in ["com.yomi.novelfire", "novelupdates", "FWN.com", "Novel Bin", "12345", "a-b_c"] {
    policy(PluginNetworkPolicy.isSafePluginId(ok), "id \(ok)")
}
for bad in ["", "../evil", "../../Library/x", "a/b", ".hidden", "..", "a\\b", "c:x", "a\u{0}b"] {
    policy(!PluginNetworkPolicy.isSafePluginId(bad), "refuses id \(bad.debugDescription)")
}

func u(_ s: String) -> URL { URL(string: s)! }

// S193: plugin code and repo lists only over https, to a real host.
for ok in ["https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json",
           "https://cdn.jsdelivr.net/gh/LNReader/lnreader-plugins@plugins/v3.0.0/.dist/plugins.min.json",
           "https://yomi-plugins.web.app/index.json"] {
    policy(PluginNetworkPolicy.isSecureDownload(u(ok)), "secure download \(ok)")
}
for bad in ["http://raw.githubusercontent.com/x/y/index.min.json", "HTTP://example.com/p.js", "ftp://example.com/p.js",
            "file:///etc/hosts", "https://127.0.0.1/p.js", "https://localhost/p.js", "data:text/javascript,1"] {
    policy(!PluginNetworkPolicy.isSecureDownload(URL(string: bad)), "insecure download refused \(bad)")
}
policy(!PluginNetworkPolicy.isSecureDownload(nil), "no final URL refused")
policy(PluginNetworkPolicy.sameOrigin(u("https://yomi-plugins.web.app/a.js"), u("https://yomi-plugins.web.app/b/c.js")), "same host")
policy(!PluginNetworkPolicy.sameOrigin(u("https://evil.example/a.js"), u("https://yomi-plugins.web.app/a.js")), "other host")
policy(PluginNetworkPolicy.sameOrigin(u("https://raw.githubusercontent.com/LNReader/plugins/x.js"),
                                      u("https://raw.githubusercontent.com/lnreader/plugins/y.js")), "same GitHub owner")
policy(!PluginNetworkPolicy.sameOrigin(u("https://raw.githubusercontent.com/evil/plugins/x.js"),
                                       u("https://raw.githubusercontent.com/LNReader/plugins/x.js")), "other GitHub owner")
policy(!PluginNetworkPolicy.sameOrigin(u("https://cdn.jsdelivr.net/gh/evil/r@1/x.js"),
                                       u("https://cdn.jsdelivr.net/gh/good/r@1/x.js")), "other jsDelivr owner")
print(failures == 0 ? "OK \(checks) checks" : "FAILED \(failures) of \(checks)")
let roots = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
var real = 0
for root in roots {
    for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    where file.pathExtension == "js" {
        guard let data = try? Data(contentsOf: file) else { continue }
        real += 1
        let ok = HTTPURLResponse(url: file, statusCode: 200, httpVersion: nil, headerFields: nil)!
        do { try PluginScript.validate(data, response: ok, sha256: nil) } catch {
            failures += 1; print("✗ real plugin \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
if real > 0 { print(failures == 0 ? "OK \(real) real plugins" : "FAILED on real plugins") }
exit(failures == 0 ? 0 : 1)
