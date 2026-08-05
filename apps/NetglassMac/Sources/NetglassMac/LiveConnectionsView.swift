import AppKit
import SwiftUI
import FlowModel

struct LiveConnectionsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = LiveConnectionsModel(
        sampler: AppState.defaultSampler())
    @State private var selection: LiveFlow.ID?
    @State private var selectedFlow: LiveFlow?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter by app, IP or port", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Text("\(model.visibleFlows.filter(\.isActive).count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("History…") { openWindow(id: "history") }
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(8)

            Table(model.visibleFlows, selection: $selection) {
                TableColumn("Process") { flow in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(flow.isActive ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(flow.processName).font(.system(.body, design: .monospaced))
                            if let bundle = flow.bundleIdentifier {
                                Text(bundle).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                TableColumn("Remote") { flow in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(flow.remote.address.text).font(.system(.body, design: .monospaced))
                        Text("\(flow.remote.port) · \(flow.transport.rawValue)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                TableColumn("Bytes ↓") { flow in
                    Text(flow.bytesReceived.formatted(.byteCount(style: .decimal)))
                        .monospacedDigit()
                }
                TableColumn("Bytes ↑") { flow in
                    Text(flow.bytesSent.formatted(.byteCount(style: .decimal)))
                        .monospacedDigit()
                }
                TableColumn("Started") { flow in
                    Text(flow.startedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 220)
        }
        .frame(width: 520, height: 260)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            selectedFlow = model.flows.first { $0.id == newValue }
        }
        .sheet(item: $selectedFlow) { flow in
            ProcessDetailView(flow: flow)
        }
    }
}
