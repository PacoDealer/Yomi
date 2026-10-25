import Foundation

var failures = 0, checks = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !ok { failures += 1; print("FAIL \(name) \(detail())") }
}
func outcome(_ data: Data) -> String {
    do { return "ok:" + (try ApkSignature.verify(data)) } catch { return "\(error)" }
}

// Keiyoushi's published signing key (repo.json → meta.signingKeyFingerprint, read 2026-10-25).
let keiyoushiKey = "9add655a78e96c4ec7a53ef89dccb557cb5d767489fac5e785d671a5a75d4da2"

// File-free: garbage and a plain zip are refused.
check("garbage refused", outcome(Data(repeating: 7, count: 4096)) == "notAZip", outcome(Data(repeating: 7, count: 4096)))
var plainZip = Data([0x50, 0x4b, 0x05, 0x06]) + Data(count: 18)   // an empty zip: just the end record
check("empty zip refused", outcome(plainZip) != "ok", outcome(plainZip))
plainZip = Data([0x50, 0x4b, 0x03, 0x04]) + Data(count: 60) + Data([0x50, 0x4b, 0x05, 0x06]) + Data(count: 18)
check("unsigned zip refused", !outcome(plainZip).hasPrefix("ok"), outcome(plainZip))

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let apks = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
    .filter { $0.pathExtension == "apk" }.sorted { $0.path < $1.path }

for url in apks {
    let name = url.lastPathComponent
    guard let data = try? Data(contentsOf: url) else { continue }
    let real = outcome(data)
    check("\(name): verifies, signed by Keiyoushi's key", real == "ok:" + keiyoushiKey, real)

    // Find the layout to tamper with specific regions.
    let b = [UInt8](data)
    var eocd = b.count - 22
    while eocd > 0, !(b[eocd] == 0x50 && b[eocd + 1] == 0x4b && b[eocd + 2] == 0x05 && b[eocd + 3] == 0x06) { eocd -= 1 }
    let cd = Int(b[eocd + 16]) | Int(b[eocd + 17]) << 8 | Int(b[eocd + 18]) << 16 | Int(b[eocd + 19]) << 24

    var entry = data; entry[100] ^= 0xff                                // inside a zipped file
    check("\(name): changed file content refused", outcome(entry) == "digestMismatch", outcome(entry))
    var dir = data; dir[cd + 30] ^= 0x01                                // inside the central directory
    check("\(name): changed central directory refused", !outcome(dir).hasPrefix("ok"), outcome(dir))
    // Inside the signed data: the bytes right after the block's 8-byte size + first pair header + lengths.
    let blockSize = (0..<8).reduce(0) { $0 | Int(b[cd - 24 + $1]) << (8 * $1) }
    let blockStart = cd - blockSize - 8
    var signed = data; signed[blockStart + 8 + 12 + 4 + 4 + 4 + 4 + 4 + 40] ^= 0x01
    check("\(name): changed signed data refused", !outcome(signed).hasPrefix("ok"), outcome(signed))
    let truncated = data.prefix(data.count - 30)
    check("\(name): truncated file refused", !outcome(truncated).hasPrefix("ok"), outcome(truncated))
}

if apks.isEmpty { print("SKIP real-APK checks: no .apk files in \(folder.path)") }
if failures > 0 { print("\(failures) of \(checks) checks FAILED"); exit(1) }
print("OK \(checks) checks, \(apks.count) real APKs")
