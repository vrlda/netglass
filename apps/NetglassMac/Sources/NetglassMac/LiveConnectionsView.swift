import AppKit
import SwiftUI
import FlowModel

struct LiveConnectionsView: View {
    @EnvironmentObject private var model: LiveConnectionsModel
    @State private var selection: LiveFlow.ID?
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
        .onAppear { model.start() }   // no-op guard; loop is app-lifetime (AppDelegate)
        .sheet(isPresented: detailPresented) {
            if let flow = model.flows.first(where: { $0.flowID == selection }) {
                ProcessDetailView(flow: flow)
            }
        }
    }

    /// The sheet is driven off the row selection so any dismissal (Escape,
    /// Cmd-W, Done) clears the selection — re-clicking the same row after a
    /// dismiss sets selection again and reopens the detail.
    private var detailPresented: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { if !$0 { selection = nil } }
        )
    }
}
