import SwiftUI

/// Real packet capture sessions.
struct CapturesView: View {
    @EnvironmentObject private var capture: PacketCaptureViewModel
    @EnvironmentObject private var appVM: AppViewModel
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            recordingBanner
            if capture.sessions.isEmpty {
                EmptyStateView(symbol: "record.circle",
                               title: "No captures yet",
                               message: "Raw packet capture is explicit and optional. "
                                   + "Start a capture to record raw packets for the Packet Inspector.")
            } else {
                Table(capture.sessions, selection: $selectedID) {
                    TableColumn("Capture") { session in
                        HStack(spacing: 6) {
                            Image(systemName: session.status == .recording
                                  ? "record.circle" : "doc.zipper")
                                .font(.system(size: 12))
                                .foregroundStyle(session.status == .recording
                                                 ? NetglassColors.error : Color.secondary)
                            Text(session.name)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.vertical, appVM.rowPadding)
                    }
                    .width(min: 200, ideal: 240)
                    TableColumn("Start") {
                        Text($0.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .width(150)
                    TableColumn("Duration") {
                        Text(Duration.seconds($0.duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .width(80)
                    TableColumn("Scope") {
                        Text($0.scope.rawValue + ($0.scopeValue.map { " · \($0)" } ?? ""))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    TableColumn("Interface") {
                        Text($0.interface).font(.system(size: 11, design: .monospaced))
                    }
                    .width(70)
                    TableColumn("Packets") {
                        Text($0.packetCount.formatted())
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .width(80)
                    TableColumn("Size") {
                        Text($0.fileSize.formatted(.byteCount(style: .decimal)))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Status") { CaptureStatusBadge(status: $0.status) }
                        .width(100)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("Open in Packet Inspector") {
                        if let id = ids.first,
                           let session = capture.sessions.first(where: { $0.id == id }) {
                            openInspector(session.fileURL)
                        }
                    }
                    Button("Reveal in Finder") {
                        if let id = ids.first,
                           let session = capture.sessions.first(where: { $0.id == id }) {
                            NSWorkspace.shared.activateFileViewerSelecting([session.fileURL])
                        }
                    }
                    Divider()
                    Button("Export PCAPNG") {
                        if let id = ids.first,
                           let session = capture.sessions.first(where: { $0.id == id }) {
                            export(session)
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        if let id = ids.first,
                           let session = capture.sessions.first(where: { $0.id == id }) {
                            delete(session)
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first,
                       let session = capture.sessions.first(where: { $0.id == id }) {
                        openInspector(session.fileURL)
                    }
                }
            }
        }
    }

    private func openInspector(_ url: URL) {
        appVM.openCaptureURL = url
        appVM.selectedSection = .packetInspector
    }

    private func export(_ session: CaptureSession) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = session.id.replacingOccurrences(of: ".pcap", with: ".pcapng")
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.copyItem(at: session.fileURL, to: url)
    }

    private func delete(_ session: CaptureSession) {
        try? FileManager.default.removeItem(at: session.fileURL)
        capture.deleteSession(session)
    }

    @ViewBuilder
    private var recordingBanner: some View {
        if capture.isRecording {
            HStack(spacing: 8) {
                Circle().fill(NetglassColors.error).frame(width: 8, height: 8)
                Text("Recording · \(capture.currentScope.rawValue)\(capture.scopeValue.map { " · \($0)" } ?? "")"
                    + " · \(capture.activeInterface) · \(Int(capture.elapsed))s"
                    + " · \(capture.capturedBytes.formatted(.byteCount(style: .decimal)))")
                    .font(.system(size: 11, design: .monospaced))
                Spacer()
                Button("Stop Capture") { capture.stop() }
                    .controlSize(.small)
                    .tint(NetglassColors.error)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(NetglassColors.error.opacity(0.08))
        } else {
            EmptyView()
        }
    }
}
