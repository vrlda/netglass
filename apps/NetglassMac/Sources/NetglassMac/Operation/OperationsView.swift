import SwiftUI

/// Operations: start/stop an OPSEC session, watch the live timeline and
/// leak warnings, review the cleanup report, export evidence.
struct OperationsView: View {
    @EnvironmentObject private var operation: OperationViewModel
    @State private var showStartSheet = false

    var body: some View {
        Group {
            if operation.session == nil {
                emptyState
            } else if operation.isRunning {
                runningState
            } else {
                endedState
            }
        }
        .sheet(isPresented: $showStartSheet) {
            StartOperationSheet()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No operation running")
                .font(.system(size: 15, weight: .semibold))
            Text("Start a session to track connections, DNS, listeners, and OPSEC leaks.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Start Operation") { showStartSheet = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningState: some View {
        OperationRunningView()
    }

    private var endedState: some View {
        Text("Operation ended — reviewing")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StartOperationSheet: View {
    @EnvironmentObject private var operation: OperationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tunnel = InterfaceStore.primary()
    @State private var scopeText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start Operation").font(.system(size: 14, weight: .semibold))
            TextField("Operation name", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Expected tunnel interface", selection: $tunnel) {
                ForEach(InterfaceStore.interfaces()) { iface in
                    Text(iface.display).tag(iface.name)
                }
            }
            .pickerStyle(.menu)
            Text("Scope — CIDRs (10.20.0.0/16), domains (*.lab.example), exclusions (excluded: 10.20.10.50), one per line")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            TextEditor(text: $scopeText)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start") {
                    let scope = OperationScope.parse(lines: scopeText.split(separator: "\n").map(String.init))
                    operation.start(name: name.isEmpty ? "Operation \(Date().formatted(date: .abbreviated, time: .shortened))" : name,
                                    expectedTunnel: tunnel, scope: scope)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct OperationRunningView: View {
    @EnvironmentObject private var operation: OperationViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $selectedTab) {
                Text("Timeline").tag(0)
                Text("Warnings").tag(1)
                Text("Listeners").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(8)
            switch selectedTab {
            case 0: timeline
            case 1: warnings
            default: listeners
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.session?.name ?? "Operation")
                    .font(.system(size: 14, weight: .semibold))
                Text(operation.session?.startedAt.formatted(date: .abbreviated, time: .standard) ?? "")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Stop") {
                operation.stop(liveFlows: liveModel.flows)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(12)
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(Array((operation.session?.events ?? []).reversed().enumerated()), id: \.offset) { _, event in
                    timelineRow(event)
                }
            }
            .padding(10)
        }
    }

    private func timelineRow(_ event: OperationEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(eventDate(event).formatted(date: .omitted, time: .standard))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: symbol(for: event)).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(line(for: event)).font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Spacer()
        }
    }

    private func eventDate(_ event: OperationEvent) -> Date {
        switch event {
        case .connection(_, let date, _, _, _, _, _, _): return date
        case .dns(let date, _, _, _): return date
        case .listener:
            return operation.session?.startedAt ?? Date()
        }
    }

    private func symbol(for event: OperationEvent) -> String {
        switch event {
        case .connection(let opened, _, _, _, _, _, _, _): return opened ? "arrow.up.right.circle" : "xmark.circle"
        case .dns: return "magnifyingglass.circle"
        case .listener(let listener): return listener.action == .opened ? "dot.circle" : "xmark.circle"
        }
    }

    private func line(for event: OperationEvent) -> String {
        switch event {
        case .connection(let opened, _, let process, _, let remote, let interface, _, _):
            return opened
                ? "\(process) → \(remote.address.text):\(remote.port) [\(interface)]"
                : "\(process) closed \(remote.address.text):\(remote.port)"
        case .dns(_, let process, let domain, _):
            return "\(process) resolved \(domain)"
        case .listener(let listener):
            let action = listener.action == .opened ? "opened" : "closed"
            return "\(listener.process) \(action) listener on \(listener.address):\(listener.port)"
        }
    }

    private var warnings: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(operation.warnings.reversed()) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: severitySymbol(warning.severity))
                            .foregroundStyle(severityColor(warning.severity))
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(warning.title).font(.system(size: 12, weight: .medium))
                            ForEach(warning.details, id: \.self) { detail in
                                Text(detail).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
        }
    }

    private func severitySymbol(_ severity: Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    private func severityColor(_ severity: Severity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var listeners: some View {
        List(operation.listeners) { listener in
            HStack {
                Text(listener.process).font(.system(size: 11, design: .monospaced))
                Spacer()
                Text(listener.address).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Text(":\(listener.port)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Text(listener.exposure).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }
}
