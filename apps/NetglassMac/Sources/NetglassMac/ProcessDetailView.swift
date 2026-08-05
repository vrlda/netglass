import SwiftUI
import FlowModel

struct ProcessDetailView: View {
    let flow: LiveFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(flow.processName).font(.title2).bold()
            if let bundle = flow.bundleIdentifier {
                Text(bundle).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Executable", value: flow.executablePath)
                .font(.system(.body, design: .monospaced))
            LabeledContent("PID", value: String(flow.pid))
            LabeledContent("Transport", value: flow.transport.rawValue)
            LabeledContent("Local", value: "\(flow.local.address.text):\(flow.local.port)")
            LabeledContent("Remote", value: "\(flow.remote.address.text):\(flow.remote.port)")
            LabeledContent("Bytes sent", value: flow.bytesSent.formatted(.byteCount(style: .decimal)))
            LabeledContent("Bytes received", value: flow.bytesReceived.formatted(.byteCount(style: .decimal)))
            LabeledContent("Started", value: flow.startedAt.formatted())
            if let ended = flow.endedAt {
                LabeledContent("Ended", value: ended.formatted())
            }
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
