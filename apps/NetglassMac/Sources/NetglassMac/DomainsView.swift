import SwiftUI

/// All observed domains — real aggregates from the live flow set.
struct DomainsView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @State private var selectedID: String?
    @State private var detailPresented = false

    private var domains: [DomainAgg] { RealAgg.domains(from: liveModel.flows) }

    var body: some View {
        Table(domains, selection: $selectedID) {
            TableColumn("Domain") { domain in
                HStack(spacing: 6) {
                    Image(systemName: domain.confidence != nil ? "globe" : "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(domain.confidence != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    Text(domain.name).font(.system(size: 13))
                }
                .padding(.vertical, appVM.rowPadding)
            }
            TableColumn("Evidence") { EvidenceBadge(text: $0.evidence) }
            TableColumn("Confidence") {
                Text($0.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    .font(.system(size: 11, design: .monospaced))
            }
            .width(80)
            TableColumn("Applications") {
                Text($0.applications.sorted().joined(separator: ", ")).font(.system(size: 11))
            }
            TableColumn("IPs") {
                Text("\($0.ipAddresses.count)").font(.system(size: 11, design: .monospaced))
            }
            .width(50)
            TableColumn("Connections") {
                Text("\($0.connections)").font(.system(size: 11, design: .monospaced))
            }
            .width(90)
            TableColumn("Sent") {
                Text($0.bytesSent.formatted(.byteCount(style: .decimal)))
                    .font(.system(size: 11, design: .monospaced)).monospacedDigit()
            }
            TableColumn("Received") {
                Text($0.bytesReceived.formatted(.byteCount(style: .decimal)))
                    .font(.system(size: 11, design: .monospaced)).monospacedDigit()
            }
            TableColumn("ASN") {
                Text(GeoIP.lookup($0.ipAddresses.sorted().first ?? "")?.asn ?? "—")
                    .font(.system(size: 10, design: .monospaced))
            }
            .width(110)
            TableColumn("Country") {
                Text(GeoIP.lookup($0.ipAddresses.sorted().first ?? "")?.country ?? "—")
                    .font(.system(size: 10, design: .monospaced))
            }
            .width(70)
        }
        .contextMenu(forSelectionType: String.self) { _ in
            Button("Open Domain Detail") { detailPresented = true }
            Button("Copy Domain") {
                if let selectedID, let domain = domains.first(where: { $0.id == selectedID }) {
                    copyText(domain.name)
                }
            }
        } primaryAction: { _ in
            detailPresented = true
        }
        .sheet(isPresented: $detailPresented) {
            if let selectedID, let domain = domains.first(where: { $0.id == selectedID }) {
                DomainDetailView(domain: domain)
            }
        }
        .overlay {
            if domains.isEmpty {
                EmptyStateView(symbol: "globe",
                               title: "No domains yet",
                               message: "Domains appear here as connections are observed")
            }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Domain detail for a real domain aggregate.
struct DomainDetailView: View {
    let domain: DomainAgg
    @EnvironmentObject private var liveModel: LiveConnectionsModel

    private var relatedResolutions: [ResolutionEvent] {
        liveModel.resolutionEvents.filter { $0.domain == domain.name || $0.ip == domain.name }
            .suffix(10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "globe").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.name).font(.system(size: 18, weight: .semibold))
                    HStack(spacing: 8) {
                        EvidenceBadge(text: domain.evidence)
                        Text("Confidence \(domain.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 16) {
                MetricGroup(label: "Connections", value: "\(domain.connections)")
                MetricGroup(label: "Sent", value: domain.bytesSent.formatted(.byteCount(style: .decimal)))
                MetricGroup(label: "Received", value: domain.bytesReceived.formatted(.byteCount(style: .decimal)))
                MetricGroup(label: "First seen", value: domain.firstSeen.formatted(date: .abbreviated, time: .omitted))
                MetricGroup(label: "Last seen", value: domain.lastSeen.formatted(date: .abbreviated, time: .shortened))
                Spacer()
            }

            Divider()

            if let geo = GeoIP.lookup(domain.ipAddresses.sorted().first ?? "") {
                HStack(spacing: 8) {
                    MetricGroup(label: "ASN", value: geo.asn)
                    MetricGroup(label: "Organization", value: geo.organization)
                    MetricGroup(label: "Country", value: geo.country)
                    Spacer()
                }
            }

            Text("Associated IP addresses").font(.system(size: 12, weight: .semibold))
            ForEach(domain.ipAddresses.sorted(), id: \.self) { ip in
                HStack(spacing: 6) {
                    Text(ip).font(.system(size: 11, design: .monospaced))
                    if domain.evidence == "Unknown" {
                        Text("No verified domain observed").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 1)
            }

            Text("Applications contacting this domain").font(.system(size: 12, weight: .semibold))
                .padding(.top, 6)
            ForEach(domain.applications.sorted(), id: \.self) { app in
                HStack(spacing: 6) {
                    Image(systemName: "app").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(app).font(.system(size: 11))
                    Spacer()
                }
                .padding(.vertical, 1)
            }

            Text("Recent resolution evidence").font(.system(size: 12, weight: .semibold))
                .padding(.top, 6)
            if relatedResolutions.isEmpty {
                Text("No lookups observed this session")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(relatedResolutions)) { event in
                    HStack(spacing: 6) {
                        Text(event.date.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Text(event.ip).font(.system(size: 10, design: .monospaced))
                        EvidenceBadge(text: event.source ?? "Unknown")
                        Spacer()
                    }
                    .padding(.vertical, 1)
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 440)
    }
}
