import SwiftUI

/// DNS Activity: real reverse-DNS resolution evidence observed this session.
/// Rows are the actual lookups the live loop performed per flow.
struct DNSActivityView: View {
    @EnvironmentObject private var monitoring: MonitoringViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @State private var groupBy: GroupBy = .none

    enum GroupBy: String, CaseIterable, Identifiable {
        case none = "None"
        case application = "Application"
        case domain = "Domain"
        var id: String { rawValue }
    }

    private var events: [ResolutionEvent] {
        Array(liveModel.resolutionEvents.reversed())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Group by", selection: $groupBy) {
                    ForEach(GroupBy.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 11))
                .frame(maxWidth: 300)
                Spacer()
                Text("\(events.count) lookups")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(8)

            Group {
                switch groupBy {
                case .none:
                    eventsTable(events)
                case .application:
                    groupedTable { $0.processName }
                case .domain:
                    groupedTable { $0.domain ?? "Unresolved" }
                }
            }
        }
        .opacity(monitoring.isPaused ? 0.55 : 1)
        .overlay {
            if events.isEmpty {
                EmptyStateView(symbol: "magnifyingglass.circle",
                               title: "No lookups yet",
                               message: "Reverse DNS evidence appears here as flows are observed")
            }
        }
    }

    private func groupedTable(key: @escaping (ResolutionEvent) -> String) -> some View {
        let grouped = Dictionary(grouping: events) { key($0) }
        return List {
            ForEach(grouped.keys.sorted(), id: \.self) { key in
                Section(key) {
                    ForEach(grouped[key] ?? []) { event in
                        EventRow(event: event)
                            .contextMenu {
                                Button("Copy IP") { copyText(event.ip) }
                                Button("Copy Result") { copyText(event.domain ?? "No domain") }
                            }
                    }
                }
            }
        }
    }

    private func eventsTable(_ events: [ResolutionEvent]) -> some View {
        Table(events) {
            TableColumn("Time") {
                Text($0.date.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, design: .monospaced))
            }
            .width(100)
            TableColumn("Application") { Text($0.processName).font(.system(size: 12)) }
            TableColumn("IP") { Text($0.ip).font(.system(size: 11, design: .monospaced)) }
            TableColumn("Result") {
                Text($0.domain ?? "No domain observed")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle($0.domain != nil ? Color.primary : NetglassColors.warning)
            }
            TableColumn("Evidence") { EvidenceBadge(text: $0.source ?? "Unknown") }
            TableColumn("Confidence") {
                Text($0.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    .font(.system(size: 11, design: .monospaced))
            }
            .width(90)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let event = events.first(where: { $0.id == id }) {
                Button("Copy IP") { copyText(event.ip) }
                Button("Copy Result") { copyText(event.domain ?? "No domain") }
                Button("Open Domain Detail") {}
            }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct EventRow: View {
    let event: ResolutionEvent
    var body: some View {
        HStack(spacing: 10) {
            Text(event.date.formatted(date: .omitted, time: .standard))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(event.ip).font(.system(size: 11, design: .monospaced))
                .frame(width: 140, alignment: .leading)
            Text(event.domain ?? "No domain observed")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(event.domain != nil ? Color.primary : NetglassColors.warning)
            Spacer()
            EvidenceBadge(text: event.source ?? "Unknown")
        }
    }
}
