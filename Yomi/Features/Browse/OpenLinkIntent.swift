import AppIntents
import Foundation

/// "Open Link in Yomi" (S196): a Shortcuts action that opens a manga or novel from its web page. iOS doesn't let a
/// share extension open its app (reports/S196-shared-links.md), so the share sheet route is a personal shortcut:
/// receive Safari web pages / URLs → Open Link in Yomi (Shortcut Input), with "Show in Share Sheet" on.
struct OpenLinkInYomiIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Link in Yomi"
    static let description = IntentDescription(
        "Opens a manga or novel from its web page, using the sources you've installed in Yomi.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Link")
    var link: URL

    @MainActor
    func perform() async throws -> some IntentResult {
        guard SharedLink.url(in: link.absoluteString) != nil else {
            throw $link.needsValueError("Choose a web page link (http or https).")
        }
        appRouter.openSharedLink(link.absoluteString)
        return .result()
    }
}

/// Lists the action in Shortcuts and Spotlight without the user building anything first.
struct YomiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenLinkInYomiIntent(),
                    phrases: ["Open a link in \(.applicationName)"],
                    shortTitle: "Open Link",
                    systemImageName: "link")
    }
}
