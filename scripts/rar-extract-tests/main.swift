import Foundation
import Unrar

// S179 — see run.sh. Exit code = number of failures.
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok    \(what)" : "  FAIL  \(what)")
    if !ok { failures += 1 }
}

let args = CommandLine.arguments.dropFirst()
let fast = args.contains("--fast")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rar-extract-\(ProcessInfo.processInfo.processIdentifier)")

for path in args where !path.hasPrefix("--") {
    let url = URL(fileURLWithPath: path)
    print("== \(url.lastPathComponent)")
    do {
        let archive = try Archive(fileURL: url)
        let entries = try archive.entries().filter { !$0.directory }
        let out = tmp.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        for (i, e) in entries.enumerated() { files[e.fileName] = out.appendingPathComponent("\(i)") }

        var start = Date()
        try RarExtract.write(archive: url, files: files)
        let onePass = Date().timeIntervalSince(start)
        print(String(format: "  one pass: %d entries in %.2f s", entries.count, onePass))

        // Per-entry extract = what Yomi did before S179. --fast compares the first 10 only.
        let compared = fast ? Array(entries.prefix(10)) : entries
        start = Date()
        var same = 0
        for e in compared {
            let data = try archive.extract(e)
            if let mine = try? Data(contentsOf: files[e.fileName]!), mine == data { same += 1 }
        }
        let perEntry = Date().timeIntervalSince(start)
        check(same == compared.count, "\(same)/\(compared.count) entries byte-identical to Unrar.swift's extract")
        print(String(format: "  per entry (old way): %d entries in %.2f s", compared.count, perEntry))

        // A subset: only pages 3 and the last, the rest skipped.
        let pick = [entries[min(2, entries.count - 1)], entries[entries.count - 1]]
        let sub = out.appendingPathComponent("subset", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        var subFiles: [String: URL] = [:]
        for (i, e) in pick.enumerated() { subFiles[e.fileName] = sub.appendingPathComponent("\(i)") }
        try RarExtract.write(archive: url, files: subFiles)
        check(pick.allSatisfy { (try? Data(contentsOf: subFiles[$0.fileName]!)) == (try? archive.extract($0)) },
              "a subset (entry 3 + last) matches")

        // A name that isn't there fails instead of writing nothing quietly.
        do {
            try RarExtract.write(archive: url, files: ["no such page.jpg": sub.appendingPathComponent("x")])
            check(false, "missing entry throws")
        } catch RarExtract.Failure.read(let name) {
            check(name == "no such page.jpg", "missing entry throws read(\(name))")
        }
        try? FileManager.default.removeItem(at: out)
    } catch RarExtract.Failure.encrypted {
        check(url.lastPathComponent.contains("encrypted"), "encrypted → Failure.encrypted")
    } catch {
        check(false, "\(url.lastPathComponent): \(error)")
    }
}
print(failures == 0 ? "All passed." : "\(failures) failed.")
exit(Int32(failures))
