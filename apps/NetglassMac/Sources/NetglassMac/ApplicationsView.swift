import SwiftUI

/// All observed applications — real aggregates from the live flow set.
struct ApplicationsView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var rateTracker: AppRateTracker
    @State private var selectedID: String?
    @State private var detailPresented = false

    private var apps: [AppAgg] { RealAgg.apps(from: liveModel.flows) }

    var body: some View {
        Table(apps, selection: $selectedID) {
            TableColumn("Application") { app in
                HStack(spacing: 6) {
                    Image(nsImage: AppIcon.image(forProcessPath: app.processPath))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(app.name).font(.system(size: 13))
                }
                .padding(.vertical, appVM.rowPadding)
            }
            .width(min: 160, ideal: 200)
            TableColumn("Active") { app in
                Text("\(app.activeConnections)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(60)
            TableColumn("Sent") { app in
                MonoCell(text: app.bytesSent.formatted(.byteCount(style: .decimal)), width: 80)
            }
            .width(min: 84, ideal: 92, max: 120)
            TableColumn("Received") { app in
                MonoCell(text: app.bytesReceived.formatted(.byteCount(style: .decimal)), width: 80)
            }
            .width(min: 84, ideal: 92, max: 120)
            TableColumn("Rate") { app in
                let rate = rateTracker.rates[app.processPath] ?? (0, 0)
                Text("↑\(ByteRate.string(rate.up)) ↓\(ByteRate.string(rate.down))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 110, ideal: 130, max: 150)
            TableColumn("Domains") { app in
                Text("\(app.domains.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 55, ideal: 60, max: 70)
            TableColumn("IPs") { app in
                Text("\(app.ips.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 48, ideal: 54, max: 62)
            TableColumn("Last active") { app in
                Text(app.lastActive, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .width(110)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Open Application Detail") { detailPresented = true }
            Button("Copy Bundle Path") {
                if let id = ids.first, let app = apps.first(where: { $0.id == id }) {
                    copyText(app.processPath)
                }
            }
        } primaryAction: { _ in
            detailPresented = true
        }
        .sheet(isPresented: $detailPresented) {
            if let selectedID, let app = apps.first(where: { $0.id == selectedID }) {
                ApplicationDetailView(app: app)
            }
        }
        .overlay {
            if apps.isEmpty {
                EmptyStateView(symbol: "app",
                               title: "No traffic yet",
                               message: "Applications appear here as soon as they make network connections")
            }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
