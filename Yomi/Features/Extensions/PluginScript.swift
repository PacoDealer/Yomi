import CryptoKit
import Foundation
import JavaScriptCore

// MARK: - PluginScript
//
// The checks a downloaded JS plugin passes before it may replace an installed one (KNOWN_ISSUES #151, #152 — S170).
// Standalone (Foundation + JavaScriptCore only) so scripts/plugin-trust-tests can compile it on macOS.

nonisolated enum PluginScript {
    enum Failure: LocalizedError {
        case http(Int), empty, notJavaScript, syntax(String), checksum
        var errorDescription: String? {
            switch self {
            case .http(let code): "The plugin couldn't be downloaded (HTTP \(code)). Nothing was changed."
            case .empty: "The download was empty. Nothing was changed."
            case .notJavaScript: "The download isn't a plugin (the server sent a web page). Nothing was changed."
            case .syntax(let detail): "The downloaded plugin has an error (\(detail)). Nothing was changed."
            case .checksum: "The downloaded plugin doesn't match its repository (checksum). Nothing was changed."
            }
        }
    }

    /// Refuses a download that can't be a working plugin, before it overwrites one that works: an HTTP error or a CDN
    /// error page served as 200, an empty or non-UTF-8 body, a script JavaScriptCore can't parse (syntax only — no
    /// code runs), or bytes that differ from the catalog's `sha256`.
    static func validate(_ data: Data, response: URLResponse, sha256: String?) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
        if let sha256, !sha256.isEmpty {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == sha256.lowercased() else { throw Failure.checksum }
        }
        guard let source = String(data: data, encoding: .utf8),
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
        let head = source.prefix(512).lowercased()
        if head.contains("<!doctype html") || head.contains("<html") { throw Failure.notJavaScript }
        guard let context = JSContext() else { return }
        let script = JSStringCreateWithCFString(source as CFString)
        defer { JSStringRelease(script) }
        var exception: JSValueRef?
        if !JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception) {
            let detail = exception.flatMap { JSValue(jsValueRef: $0, in: context)?.toString() } ?? "syntax error"
            throw Failure.syntax(detail)
        }
    }
}
