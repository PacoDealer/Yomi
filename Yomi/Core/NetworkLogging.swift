import Foundation
#if DEBUG
import Pulse
#endif

/// Records a completed network request into Pulse's debug console (DEBUG builds only, no-op
/// in Release). Deliberately a plain nonisolated function, not routed through Pulse's
/// `URLSessionProxy` — that type is `@MainActor`, which would force an actor hop at every call
/// site. Several of Yomi's real fetch paths can't take that hop: `JSBridge`'s plugin fetch is
/// `nonisolated`/`Task.detached` by design (see CLAUDE.md's Swift 6 rules), and some services
/// here are custom actors (`AniListService`) or unstructured `TaskGroup` children
/// (`PluginCatalogService`). `LoggerStore.storeRequest` has no actor affinity, so this is safe
/// to call from any of them without changing isolation anywhere.
nonisolated func yomiLogNetwork(_ request: URLRequest, response: URLResponse?, data: Data?, error: Error? = nil) {
    #if DEBUG
    LoggerStore.shared.storeRequest(request, response: response, error: error, data: data)
    #endif
}
