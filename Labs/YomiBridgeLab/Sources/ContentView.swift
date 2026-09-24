import SwiftUI

struct ContentView: View {
    @ObservedObject var lab: BridgeLab

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Start JVM") { Task { await lab.startJVM() } }.disabled(lab.busy || lab.port != 0)
                ForEach(BridgeLab.sources, id: \.name) { s in
                    Button(s.name) { lab.run(s) }.disabled(lab.busy || lab.port == 0)
                }
            }
            .buttonStyle(.borderedProminent)
            if lab.busy { ProgressView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lab.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                    if let image = lab.image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .task { await lab.autorunIfRequested() }
    }
}
