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

print(failures == 0 ? "OK \(checks) checks" : "FAILED \(failures) of \(checks)")

// Every real plugin must pass: Yomi's catalog (Firebase/public) and whatever the simulator has installed (LNReader…).
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
