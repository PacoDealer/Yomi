import SwiftUI

// MARK: - CustomizeTabsView
//
// iPhone gets zero built-in tab-customization affordance from Apple's own API — the system's
// drag/hide editing UI for `.tabViewStyle(.sidebarAdaptable)` only exists inside the sidebar,
// which only renders in regular-width contexts (iPad/Mac). This screen is the real substitute for
// iPhone: reorder via drag handle, hide/show via toggle. "More" can't be hidden — it's the only
// way back to this screen. Backed by AppSettings.tabOrder/hiddenTabIDs, read live by ContentView.

struct CustomizeTabsView: View {
    @Bindable private var router = appRouter
    @State private var settings = AppSettings.shared

    private var orderedIDs: [YomiTabID] {
        settings.tabOrder.compactMap { YomiTabID(rawValue: $0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(orderedIDs, id: \.self) { id in
                    row(for: id)
                }
                .onMove(perform: move)
            } footer: {
                Text("Drag to reorder. \u{201C}More\u{201D} always stays visible so Settings is never hidden.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize Tabs")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(for id: YomiTabID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: id.systemImage)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(id.title)
            Spacer()
            if id == .more {
                Text("Always shown")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Toggle("", isOn: visibilityBinding(for: id)).labelsHidden()
            }
        }
    }

    private func visibilityBinding(for id: YomiTabID) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenTabIDs.contains(id.rawValue) },
            set: { isVisible in
                if isVisible {
                    settings.hiddenTabIDs.removeAll { $0 == id.rawValue }
                } else {
                    guard !settings.hiddenTabIDs.contains(id.rawValue) else { return }
                    settings.hiddenTabIDs.append(id.rawValue)
                    // A hidden tab can't stay selected or be the launch tab.
                    if router.selectedTab == id.routerValue {
                        router.selectedTab = AppRouter.tabLibrary
                    }
                    if settings.defaultTab == id.routerValue {
                        settings.defaultTab = AppRouter.tabLibrary
                    }
                }
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var order = settings.tabOrder
        order.move(fromOffsets: source, toOffset: destination)
        settings.tabOrder = order
    }
}

#Preview {
    NavigationStack {
        CustomizeTabsView()
    }
}
