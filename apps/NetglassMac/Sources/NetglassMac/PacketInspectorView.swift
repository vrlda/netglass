import SwiftUI

/// Advanced packet analysis workspace: packet list / protocol tree / hex
/// viewer. All data is real — parsed from pcap/pcapng capture files.
struct PacketInspectorView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var capture: PacketCaptureViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @State private var packets: [PacketRecord] = []
    @State private var credentialHits: [CredentialHit] = []
    @State private var selectedPacketID: Int?
    @State private var selectedFieldID: String?
    @State private var displayFilter = ""
    @State private var showFollowStream = false
    @State private var showStatistics = false
    @State private var fileName = ""

    private var filteredPackets: [PacketRecord] {
        guard !displayFilter.isEmpty else { return packets }
        return packets.filter { packet in
            packet.protocolName.localizedCaseInsensitiveContains(displayFilter)
                || packet.source.localizedCaseInsensitiveContains(displayFilter)
                || packet.destination.localizedCaseInsensitiveContains(displayFilter)
                || packet.info.localizedCaseInsensitiveContains(displayFilter)
        }
    }

    private var selectedPacket: PacketRecord? {
        guard let selectedPacketID else { return nil }
        return packets.first { $0.id == selectedPacketID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            sensitiveSection
            if packets.isEmpty {
                EmptyStateView(symbol: "rectangle.3.group",
                               title: "No capture open",
                               message: "Start a capture or open a pcap/pcapng file to inspect packets")
            } else {
                packetList
                Divider()
                protocolTree
                Divider()
                hexViewer
            }
        }
        .sheet(isPresented: $showFollowStream) {
            if let packet = selectedPacket {
                FollowStreamView(stream: StreamReassembler.reassemble(packets: packets,
                                                                      for: packet),
                                 packet: packet)
            }
        }
        .sheet(isPresented: $showStatistics) {
            StatisticsView(packets: filteredPackets)
        }
        .onChange(of: appVM.openCaptureURL) { _, url in
            guard let url else { return }
            load(url)
        }
        .onAppear {
            if packets.isEmpty, let url = appVM.openCaptureURL {
                load(url)
            }
        }
    }

    private func load(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let raw = try? PcapParser.parse(data) else { return }
        var records: [PacketRecord] = []
        for (index, packet) in raw.enumerated() {
            records.append(PacketDecoders.decode(
                packet, number: index + 1,
                previous: index > 0 ? raw[index - 1] : nil))
        }
        packets = records
        credentialHits = CredentialScan.scan(records)
        fileName = url.lastPathComponent
        selectedPacketID = nil
        selectedFieldID = nil
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(InterfaceStore.interfaces()) { iface in
                    Button(iface.display) { capture.activeInterface = iface.name }
                }
            } label: {
                Label(capture.activeInterface, systemImage: "network")
            }
            .controlSize(.small)
            Divider()
            Button {
                if capture.isRecording {
                    capture.stop()
                } else {
                    capture.start(scope: .allTraffic, interface: capture.activeInterface)
                }
            } label: {
                Label(capture.isRecording ? "Stop" : "Capture",
                      systemImage: capture.isRecording ? "stop.fill" : "record.circle")
                    .foregroundStyle(capture.isRecording ? NetglassColors.error : Color.primary)
            }
            .controlSize(.small)
            .help("Command-R — start or stop packet capture")
            TextField("Display filter (e.g. tcp, dns, host 8.8.8.8)", text: $displayFilter)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 260)
            Spacer()
            if !fileName.isEmpty {
                Text(fileName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text("\(filteredPackets.count) packets")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button("Follow Stream") { showFollowStream = true }
                .controlSize(.small)
                .disabled(selectedPacket == nil)
            Button("Statistics") { showStatistics = true }
                .controlSize(.small)
            Menu {
                Button("Open Capture File…") { openFile() }
                Button("Export Selected Packets") { exportSelected() }
                Button("Copy Packet Summary") {
                    if let packet = selectedPacket { copySummary(packet) }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .controlSize(.small)
        }
        .padding(8)
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func exportSelected() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "netglass-selected.pcap"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PcapWriter.write(packets: filteredPackets, to: url)
        } catch {
            // silent: save panel already confirmed; nothing else to surface
        }
    }

    private func copySummary(_ packet: PacketRecord) {
        let text = "\(packet.id)\t\(packet.timestamp.formatted(date: .omitted, time: .standard))\t"
            + "\(packet.source):\(packet.sourcePort.map(String.init) ?? "?")\t"
            + "\(packet.destination):\(packet.destinationPort.map(String.init) ?? "?")\t"
            + "\(packet.protocolName)\t\(packet.length)\t\(packet.info)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Sensitive data

    private var sensitiveSection: some View {
        Group {
            if !credentialHits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sensitive data (\(credentialHits.count))")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                    ForEach(credentialHits) { hit in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9)).foregroundStyle(.orange)
                            Text("#\(hit.packetID) \(hit.kind) — \(hit.detail)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Top pane: packet list

    private var packetList: some View {
        Table(filteredPackets, selection: $selectedPacketID) {
            TableColumn("No.") {
                Text("\($0.id)").font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(48)
            TableColumn("Timestamp") {
                Text($0.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 10, design: .monospaced))
            }
            .width(96)
            TableColumn("Delta") {
                Text(String(format: "%.1f ms", $0.deltaMs))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            .width(66)
            TableColumn("Source") {
                Text("\($0.source)\($0.sourcePort.map { ":\($0)" } ?? "")")
                    .font(.system(size: 10, design: .monospaced))
            }
            TableColumn("Destination") {
                Text("\($0.destination)\($0.destinationPort.map { ":\($0)" } ?? "")")
                    .font(.system(size: 10, design: .monospaced))
            }
            TableColumn("Protocol") {
                Text($0.protocolName).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(protocolColor($0.protocolName))
            }
            .width(64)
            TableColumn("Length") {
                Text("\($0.length)").font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(60)
            TableColumn("Info") {
                Text($0.info).font(.system(size: 10, design: .monospaced))
            }
        }
        .frame(minHeight: 160, maxHeight: 260)
    }

    private static func endpoint(_ address: String, _ port: UInt16?) -> String {
        guard let port else { return address }
        return "\(address):\(port)"
    }

    private func protocolColor(_ name: String) -> Color {
        switch name {
        case "TLS": .green
        case "QUIC": .purple
        case "DNS": .orange
        case "HTTP": .teal
        case "TCP": .blue
        case "UDP": .indigo
        default: .secondary
        }
    }

    // MARK: - Middle pane: protocol tree

    private var protocolTree: some View {
        Group {
            if let packet = selectedPacket {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(packet.layers, id: \.id) { layer in
                            ExpandableRow(isExpanded: layerExpandedBinding(layer.id)) {
                                Text(layer.name).font(.system(size: 11, weight: .semibold))
                            } content: {
                                ForEach(layer.fields) { field in
                                    Button {
                                        selectedFieldID = field.id
                                    } label: {
                                        HStack(alignment: .top, spacing: 6) {
                                            Text(field.name).font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 150, alignment: .leading)
                                            Text(field.value).font(.system(size: 11, design: .monospaced))
                                                .textSelection(.enabled)
                                            Spacer(minLength: 0)
                                            if field.length > 0 {
                                                Text("offset \(field.offset) · \(field.length) bytes")
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        .padding(.vertical, 1)
                                        .contentShape(Rectangle())
                                        .background(selectedFieldID == field.id
                                                    ? Color.blue.opacity(0.12) : Color.clear)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 170)
            } else {
                EmptyStateView(symbol: "doc.text.magnifyingglass",
                               title: "No packet selected",
                               message: "Select a packet to inspect its protocol layers")
                    .frame(maxHeight: 170)
            }
        }
    }

    @State private var expandedLayers: Set<String> = []

    private func layerExpandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedLayers.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedLayers.insert(id) } else { expandedLayers.remove(id) }
            })
    }

    // MARK: - Bottom pane: hex viewer

    private var hexViewer: some View {
        Group {
            if let packet = selectedPacket {
                VStack(spacing: 4) {
                    HStack {
                        Text("Packet \(packet.id) — \(packet.length) bytes")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy Hex") {
                            let hex = packet.rawBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                            copyText(hex)
                        }
                        .controlSize(.small)
                        Button("Copy ASCII") {
                            let ascii = packet.rawBytes
                                .map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }
                                .joined()
                            copyText(ascii)
                        }
                        .controlSize(.small)
                    }
                    HexViewerView(bytes: packet.rawBytes, highlight: highlightRange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(6)
            } else {
                EmptyStateView(symbol: "rectangle.split.2x1",
                               title: "Hex viewer idle",
                               message: "Select a packet to inspect its raw bytes")
            }
        }
        .frame(minHeight: 130, maxHeight: 220)
    }

    private var highlightRange: Range<Int>? {
        guard let selectedFieldID,
              let packet = selectedPacket,
              let field = packet.layers.flatMap(\.fields)
                  .first(where: { $0.id == selectedFieldID }),
              field.length > 0, field.offset < packet.rawBytes.count else { return nil }
        return field.offset..<min(field.offset + field.length, packet.rawBytes.count)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Follow TCP stream / UDP flow sheet with real reassembled payloads.
struct FollowStreamView: View {
    let stream: ReassembledStream
    let packet: PacketRecord?
    @State private var mode: Mode = .utf8
    enum Mode: String, CaseIterable, Identifiable {
        case utf8 = "UTF-8"
        case hex = "Hex"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Follow \(packet?.protocolName ?? "stream")")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(stream.totalBytes.formatted(.byteCount(style: .decimal))) reassembled")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                Spacer()
                Button("Copy Stream") { copyStream() }
                    .controlSize(.small)
                Button("Save…") { saveStream() }
                    .controlSize(.small)
            }
            directionPane(title: "Client → Server", color: .blue,
                          direction: stream.clientToServer)
            directionPane(title: "Server → Client", color: .purple,
                          direction: stream.serverToClient)
            Spacer()
        }
        .padding(14)
        .frame(width: 640, height: 400)
    }

    private func directionPane(title: String, color: Color,
                               direction: StreamDirection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                Text("\(direction.bytes.count.formatted(.byteCount(style: .decimal)))"
                    + " · \(direction.packets.count) packets")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            Text(rendered(direction.bytes))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func rendered(_ bytes: [UInt8]) -> String {
        switch mode {
        case .utf8:
            String(bytes: bytes, encoding: .utf8) ?? "—"
        case .hex:
            bytes.prefix(4096).map { String(format: "%02x", $0) }.joined(separator: " ")
        }
    }

    private func copyStream() {
        let text = "CLIENT → SERVER\n" + rendered(stream.clientToServer.bytes)
            + "\n\nSERVER → CLIENT\n" + rendered(stream.serverToClient.bytes)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveStream() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "netglass-stream.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "CLIENT → SERVER\n" + rendered(stream.clientToServer.bytes)
            + "\n\nSERVER → CLIENT\n" + rendered(stream.serverToClient.bytes)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Protocol statistics sheet computed from the real packet list.
struct StatisticsView: View {
    let packets: [PacketRecord]
    @State private var tab: Tab = .protocols
    enum Tab: String, CaseIterable, Identifiable {
        case protocols = "Protocol Hierarchy"
        case endpoints = "Endpoints"
        case talkers = "Protocols by Volume"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            switch tab {
            case .protocols:
                let rows = Dictionary(grouping: packets) { $0.protocolName }
                    .map { StatRow(id: $0.key, value: "\($0.value.count)") }
                    .sorted { $0.value > $1.value }
                statsTable(rows, first: "Protocol")
            case .endpoints:
                let rows = Dictionary(grouping: packets) { $0.source }
                    .map { StatRow(id: $0.key, value: "\($0.value.count)") }
                    .sorted { $0.value > $1.value }
                statsTable(rows, first: "Endpoint")
            case .talkers:
                let rows = Dictionary(grouping: packets) { $0.protocolName }
                    .map { StatRow(id: $0.key,
                                   value: $0.value.reduce(0) { $0 + $1.length }
                                       .formatted(.byteCount(style: .decimal))) }
                    .sorted { $0.value > $1.value }
                statsTable(rows, first: "Protocol")
            }
            Spacer(minLength: 0)
        }
        .frame(width: 520, height: 380)
    }

    private func statsTable(_ rows: [StatRow], first: String) -> some View {
        Table(rows) {
            TableColumn(first) { Text($0.id).font(.system(size: 11, design: .monospaced)) }
            TableColumn("Value") {
                Text($0.value).font(.system(size: 11, design: .monospaced))
            }
        }
    }
}

private struct StatRow: Identifiable {
    let id: String
    let value: String
}
