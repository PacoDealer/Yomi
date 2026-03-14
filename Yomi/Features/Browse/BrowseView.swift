import SwiftUI

struct BrowseView: View {
    @State private var extensionManager = ExtensionManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if extensionManager.installed.isEmpty {
                    ContentUnavailableView {
                        Label("No sources installed", systemImage: "puzzlepiece")
                    } description: {
                        Text("Go to More → Plugins to install your first extension.")
                    } actions: {
                        Button("Browse extensions") {
                            // navigate to plugins — coming soon
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(extensionManager.installed) { ext in
                        HStack(spacing: 12) {
                            AsyncImage(url: ext.iconURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fit)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.2))
                            }
                            .frame(width: 44, height: 44)
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ext.name)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(ext.language.uppercased())
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundStyle(.tint)
                                        .clipShape(Capsule())
                                    Text("v\(ext.version)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Browse")
        }
    }
}

#Preview {
    BrowseView()
}
