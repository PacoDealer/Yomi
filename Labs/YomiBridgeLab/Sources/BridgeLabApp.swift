import SwiftUI

@main
struct BridgeLabApp: App {
    @StateObject private var lab = BridgeLab()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup { ContentView(lab: lab) }
            .onChange(of: phase) { _, new in
                if new == .background, lab.port != 0 { JVMHost.shared.pauseBridge(); lab.port = 0 }
            }
    }
}
