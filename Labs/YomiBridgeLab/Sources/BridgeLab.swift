import Foundation
import UIKit

/// Drives the embedded bridge the way call.py does on the Mac: popular → search → details → chapters → pages →
/// first image, timing each step and sampling the app's memory footprint.
@MainActor
final class BridgeLab: ObservableObject {
    struct Source { let name: String; let apk: String; let query: String }
    static let sources = [
        Source(name: "Asura", apk: "tachiyomi-en.asurascans-v1.6.69", query: "solo"),
        Source(name: "MangaFire", apk: "tachiyomi-all.mangafire-v1.6.34", query: "solo leveling"),
    ]
    // The bridge copies the caller's User-Agent onto the extension's requests; Cloudflare 403s non-browser UAs.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    @Published var log: [String] = []
    @Published var port = 0
    @Published var busy = false
    @Published var image: UIImage?
    private var handles: [String: String] = [:]

    func say(_ line: String) {
        let text = "\(line)  [\(Self.footprintMB()) MB]"
        log.append(text)
        print("[BridgeLab] \(text)")
    }

    func startJVM() async {
        busy = true
        say("Starting JVM…")
        let (port, createMs, bridgeMs, error) = await withCheckedContinuation { cont in
            JVMHost.shared.start { cont.resume(returning: ($0, $1, $2, $3)) }
        }
        self.port = port
        busy = false
        if let error { say("FAILED: \(error)") }
        if createMs > 0 { say("JNI_CreateJavaVM: \(Int(createMs)) ms") }
        say("EmbeddedBridge.start: \(Int(bridgeMs)) ms → port \(port)")
    }

    /// `--autorun` (devicectl launch argument): start the JVM, then walk every source twice (cold, then warm).
    func autorunIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--autorun") else { return }
        await startJVM()
        guard port != 0 else { return }
        for pass in ["cold", "warm"] {
            for s in Self.sources {
                say("pass: \(pass)")
                busy = true
                do { try await walk(s) } catch { say("\(s.name) ✗ \(error.localizedDescription)") }
                busy = false
            }
        }
        say("AUTORUN_DONE")
    }

    func run(_ source: Source) {
        guard port != 0 else { say("Start the JVM first"); return }
        busy = true
        Task {
            defer { busy = false }
            do { try await walk(source) } catch { say("\(source.name) ✗ \(error.localizedDescription)") }
        }
    }

    private func walk(_ s: Source) async throws {
        say("── \(s.name) ──")
        let popular = try await step(s, "getPopularManga", ["page": 1])
        guard let list = Self.firstList(popular), let first = list.first as? [String: Any] else {
            say("no popular list"); return
        }
        _ = try await step(s, "getSearchManga(\(s.query))", ["page": 1, "search": s.query, "filterList": []], method: "getSearchManga")
        let manga = ["url": first["url"] ?? NSNull(), "title": first["title"] ?? NSNull(), "thumbnail_url": first["thumbnail_url"] ?? NSNull()]
        _ = try await step(s, "getDetailsManga", ["mangaData": manga])
        guard let chapters = Self.firstList(try await step(s, "getChapterList", ["mangaData": manga])),
              let chapter = chapters.last as? [String: Any] else { say("no chapters"); return }
        let pagesRes = try await step(s, "getPageList", ["chapterData": ["url": chapter["url"] ?? NSNull(), "name": chapter["name"] ?? NSNull()]], label: "getPageList(\(chapter["name"] ?? "?"))")
        guard let pages = Self.firstList(pagesRes), let page = pages.first as? [String: Any],
              let urlString = (page["imageUrl"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? page["url"] as? String,
              let url = URL(string: urlString) else { say("no page url"); return }
        var req = URLRequest(url: url, timeoutInterval: 600)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let t = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let ms = Int(Date().timeIntervalSince(t) * 1000)
        image = UIImage(data: data)
        let type = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "?"
        say("first image: \(ms) ms, \(data.count / 1024) KB \(type), decoded=\(image != nil)")
    }

    private func step(_ s: Source, _ label: String, _ params: [String: Any], method: String? = nil, label override: String? = nil) async throws -> Any {
        var body = params
        body["method"] = method ?? label
        if let h = handles[s.apk] {
            body["extensionId"] = h
        } else {
            let apk = Bundle.main.url(forResource: "BridgeFiles/\(s.apk)", withExtension: "apk")!
            body["data"] = try Data(contentsOf: apk).base64EncodedString()
        }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/dalvik")!, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let t = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let ms = Int(Date().timeIntervalSince(t) * 1000)
        let http = resp as? HTTPURLResponse
        if let h = http?.value(forHTTPHeaderField: "X-Mangayomi-Extension-Id") { handles[s.apk] = h }
        let json = (try? JSONSerialization.jsonObject(with: data)) ?? String(decoding: data.prefix(300), as: UTF8.self)
        let summary = Self.firstList(json).map { "\($0.count) items" } ?? "object"
        say("\(override ?? label): \(ms) ms, HTTP \(http?.statusCode ?? 0), \(summary)")
        if http?.statusCode != 200 { say("  body: \(String(decoding: data.prefix(400), as: UTF8.self))") }
        return json
    }

    static func firstList(_ any: Any) -> [Any]? {
        if let a = any as? [Any] { return a }
        if let d = any as? [String: Any] { return d.values.first { $0 is [Any] } as? [Any] }
        return nil
    }

    /// The number jetsam judges the app by (same as Xcode's memory gauge).
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
