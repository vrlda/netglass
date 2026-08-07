import SwiftUI

/// Command-K palette: searchable actions, keyboard navigable.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var monitoring: MonitoringViewModel
    @EnvironmentObject private var capture: PacketCaptureViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel

    @State private var query = ""

    private func exportCurrentView() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "netglass-export.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var rows = ["application,remote_ip,remote_port,protocol,bytes_sent,bytes_received,domain"]
        rows += liveModel.flows.map { flow in
            "\(flow.processName),\(flow.remote.address.text),\(flow.remote.port),"
                + "\(flow.transport.rawValue),\(flow.bytesSent),\(flow.bytesReceived),\(flow.remoteDomain ?? "")"
        }
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    @State private var selection = 0
    @FocusState private var focused: Bool

    private struct Action: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let run: () -> Void
    }

    private var actions: [Action] {
        var list: [Action] = [
            Action(id: "overview", title: "Go to Overview", symbol: "waveform.path.ecg") {
                appVM.selectedSection = .overview
            },
            Action(id: "live", title: "Go to Live Connections", symbol: "point.3.connected.trianglepath.dotted") {
                appVM.selectedSection = .liveConnections
            },
            Action(id: "apps", title: "Go to Applications", symbol: "app") {
                appVM.selectedSection = .applications
            },
            Action(id: "domains", title: "Go to Domains", symbol: "globe") {
                appVM.selectedSection = .domains
            },
            Action(id: "dns", title: "Go to DNS Activity", symbol: "magnifyingglass.circle") {
                appVM.selectedSection = .dnsActivity
            },
            Action(id: "captures", title: "Go to Captures", symbol: "record.circle") {
                appVM.selectedSection = .captures
            },
            Action(id: "inspector", title: "Go to Packet Inspector", symbol: "rectangle.3.group") {
                appVM.selectedSection = .packetInspector
            },
            Action(id: "history", title: "Go to History", symbol: "clock.arrow.circlepath") {
                appVM.selectedSection = .history
            },
            Action(id: "pause", title: monitoring.isPaused ? "Resume Monitoring" : "Pause Monitoring",
                   symbol: monitoring.isPaused ? "play.fill" : "pause.fill") {
                monitoring.toggle()
            },
            Action(id: "capture", title: capture.isRecording ? "Stop Capture" : "Start Capture",
                   symbol: capture.isRecording ? "stop.fill" : "record.circle") {
                if capture.isRecording { capture.stop() } else { capture.start(scope: .allTraffic) }
            },
            Action(id: "inspectorToggle", title: "Toggle Inspector", symbol: "sidebar.right") {
                appVM.inspectorVisible.toggle()
            },
            Action(id: "filter", title: "Filter by Application…", symbol: "line.3.horizontal.decrease.circle") {
                appVM.selectedSection = .liveConnections
            },
            Action(id: "settings", title: "Open Settings", symbol: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            Action(id: "export", title: "Export Current View", symbol: "square.and.arrow.up") {
                exportCurrentView()
            },
            Action(id: "quit", title: "Quit Netglass", symbol: "power") {
                NSApp.terminate(nil)
            },
        ]
        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command").font(.system(size: 12)).foregroundStyle(.tertiary)
                TextField("Command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
            }
            .padding(10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            Button {
                                action.run()
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: action.symbol)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    Text(action.title).font(.system(size: 12))
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .background(selection == index ? Color.accentColor.opacity(0.18)
                                          : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .id(action.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selection) { _, newValue in
                    if actions.indices.contains(newValue) {
                        proxy.scrollTo(actions[newValue].id, anchor: .center)
                    }
                }
            }
            .frame(height: 260)
        }
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear {
            selection = 0
            query = ""
            focused = true
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selection < actions.count - 1 { selection += 1 }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selection > 0 { selection -= 1 }
            return .handled
        }
        .onKeyPress(.return) {
            guard actions.indices.contains(selection) else { return .handled }
            actions[selection].run()
            isPresented = false
            return .handled
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .padding(40)
    }
}
