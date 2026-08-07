import Persistence
import SwiftUI

/// Top toolbar: page title left, search center, compact status group right.
/// Secondary actions live in the overflow menu.
struct MainToolbarView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var monitoring: MonitoringViewModel
    @EnvironmentObject private var capture: PacketCaptureViewModel
    @EnvironmentObject private var appState: AppState
    @FocusState private var searchFocused: Bool
    @State private var diagnosticsPresented = false

    var body: some View {
        HStack(spacing: 12) {
            NetglassTypography.pageTitle(appVM.selectedSection.title)
                .frame(minWidth: 120, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("Search", text: $appVM.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !appVM.searchText.isEmpty {
                    Button {
                        appVM.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 280)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(monitoring.isPaused ? NetglassColors.warning : NetglassColors.active)
                    .frame(width: 7, height: 7)
                Text(monitoring.isPaused ? "Paused" : "Live")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(monitoring.isPaused ? NetglassColors.warning : .secondary)
            }
            .help(monitoring.isPaused ? "Monitoring paused — data is not updating"
                  : "Monitoring live")

            TrafficRateView(up: liveModel.throughput.bytesPerSecondUp,
                            down: liveModel.throughput.bytesPerSecondDown)

            Picker("Time range", selection: $appVM.timeRange) {
                ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 120)

            Divider().frame(height: 16)

            Button {
                monitoring.toggle()
            } label: {
                Image(systemName: monitoring.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("Space — pause/resume live updates")

            Button {
                if capture.isRecording {
                    capture.stop()
                } else {
                    capture.start(scope: .allTraffic)
                }
            } label: {
                Image(systemName: capture.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(capture.isRecording ? NetglassColors.error : Color.primary)
            }
            .controlSize(.small)
            .help("Command-R — start or stop packet capture")

            Button {
                NotificationCenter.default.post(name: .toggleInspector, object: nil)
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("Command-I — toggle inspector")

            Menu {
                Button("Open Command Palette") {
                    NotificationCenter.default.post(name: .openPalette, object: nil)
                }
                Button("Reset View") {
                    appVM.searchText = ""
                    appVM.timeRange = .fiveMinutes
                    appVM.selectedSection = .overview
                }
                Divider()
                if appVM.selectedSection == .liveConnections {
                    Menu("Columns") {
                        ForEach(AppViewModel.availableColumns, id: \.self) { column in
                            Toggle(column, isOn: Binding(
                                get: { appVM.enabledColumns.contains(column) },
                                set: { enabled in
                                    if enabled { appVM.enabledColumns.insert(column) }
                                    else { appVM.enabledColumns.remove(column) }
                                }))
                        }
                    }
                }
                Button("Export…") { exportCurrent() }
                Button("Diagnostics…") { diagnosticsPresented = true }
                Divider()
                Button("Start Capture") { capture.start(scope: .allTraffic) }
                    .disabled(capture.isRecording)
                Button("Stop Capture") { capture.stop() }
                    .disabled(!capture.isRecording)
                Button(monitoring.isPaused ? "Resume Monitoring" : "Pause Monitoring") {
                    monitoring.toggle()
                }
                Divider()
                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Button("Quit Netglass") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .help("More")
        }
        .padding(.horizontal, NetglassSpacing.page)
        .padding(.vertical, 7)
        .background(.bar)
        .sheet(isPresented: $diagnosticsPresented) {
            DiagnosticsView()
        }
        .overlay(alignment: .bottom) {
            if capture.isRecording {
                Rectangle().fill(NetglassColors.error.opacity(0.55)).frame(height: 1)
            } else {
                Divider().opacity(0.6)
            }
        }
    }
}


// MARK: - Export + diagnostics

extension MainToolbarView {
    private func exportCurrent() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "netglass-export.csv"
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let csv: String
            switch appVM.selectedSection {
            case .history:
                if let db = appState.database {
                    let flows = (try? HistoryQuery.search(database: db, text: appVM.searchText,
                                                          limit: Int.max)) ?? []
                    if url.pathExtension.lowercased() == "csv" {
                        try Exporter.exportCSV(flows, to: url)
                    } else {
                        try Exporter.exportJSON(flows, to: url)
                    }
                }
                return
            case .applications:
                csv = appsCSV()
            case .domains:
                csv = domainsCSV()
            default:
                csv = flowsCSV()
            }
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // export failures are surfaced by the save panel staying open
        }
    }

    private func flowsCSV() -> String {
        var rows = ["application,remote_ip,remote_port,protocol,bytes_sent,bytes_received,domain"]
        rows += liveModel.flows.map { flow in
            "\(flow.processName),\(flow.remote.address.text),\(flow.remote.port),"
                + "\(flow.transport.rawValue),\(flow.bytesSent),\(flow.bytesReceived),\(flow.remoteDomain ?? "")"
        }
        return rows.joined(separator: "\n")
    }

    private func appsCSV() -> String {
        var rows = ["name,path,active_connections,bytes_sent,bytes_received"]
        rows += RealAgg.apps(from: liveModel.flows).map { app in
            "\(app.name),\(app.processPath),\(app.activeConnections),\(app.bytesSent),\(app.bytesReceived)"
        }
        return rows.joined(separator: "\n")
    }

    private func domainsCSV() -> String {
        var rows = ["domain,evidence,confidence,connections,bytes_sent,bytes_received"]
        let domainRows: [String] = RealAgg.domains(from: liveModel.flows).map { domain in
            let confidence = domain.confidence.map { String($0) } ?? ""
            return "\(domain.name),\(domain.evidence),\(confidence),"
                + "\(domain.connections),\(domain.bytesSent),\(domain.bytesReceived)"
        }
        rows += domainRows
        return rows.joined(separator: "\n")
    }
}

/// Real diagnostics: database stats, interfaces, sampling health, captures.
struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var capture: PacketCaptureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Diagnostics").font(.system(size: 14, weight: .semibold))
            Form {
                LabeledContent("App version",
                               value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                LabeledContent("Live flows", value: "\(liveModel.flows.count)")
                LabeledContent("Active flows", value: "\(liveModel.flows.filter(\.isActive).count)")
                LabeledContent("Throughput history", value: "\(liveModel.throughputHistory.count) samples")
                LabeledContent("Resolutions", value: "\(liveModel.resolutionEvents.count)")
                LabeledContent("Packet rate", value: capture.isRecording
                               ? "\(Int(capture.packetsPerSecond))/s" : "— (no capture)")
                LabeledContent("Capture sessions", value: "\(capture.sessions.count)")
                LabeledContent("Interfaces",
                               value: InterfaceStore.interfaces()
                                   .map { $0.display }.joined(separator: ", "))
            }
            .formStyle(.grouped)

            if let db = appState.database {
                let counts = (try? db.flows().count) ?? 0
                let processes = (try? db.processCount()) ?? 0
                HStack(spacing: 16) {
                    Text("History flows: \(counts)").font(.system(size: 11, design: .monospaced))
                    Text("Processes: \(processes)").font(.system(size: 11, design: .monospaced))
                    Text("DB: \(appState.databaseURL.path)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 560, height: 420)
    }
}
