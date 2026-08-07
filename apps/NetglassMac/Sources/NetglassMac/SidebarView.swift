import SwiftUI

/// Left sidebar: native source-list navigation + real active applications
/// with expandable destinations.
struct SidebarView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var rateTracker: AppRateTracker

    @State private var expandedApps: Set<String> = []

    private var apps: [AppAgg] { RealAgg.apps(from: liveModel.flows) }

    var body: some View {
        List(selection: $appVM.selectedSection) {
            Section("Netglass") {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .font(.system(size: 13))
                        .padding(.vertical, 4)
                        .tag(section)
                        .keyboardShortcut(section.shortcut, modifiers: .command)
                }
            }

            Section("Active Applications") {
                if apps.isEmpty {
                    Text("No active applications")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
                ForEach(apps.prefix(8)) { app in
                    ExpandableRow(isExpanded: expandedBinding(for: app.processPath)) {
                        appRow(app)
                    } content: {
                        ForEach(app.destinations.prefix(6)) { destination in
                            HStack(spacing: 5) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(destination.active ? Color.green : Color.gray)
                                Text(destination.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(destination.transport.rawValue.uppercased()) :\(destination.port)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .contextMenu {
                        Button("Inspect") { appVM.selectedSection = .applications }
                        Divider()
                        Button("Copy App Name") { copyText(app.name) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: NetglassMetrics.sidebarWidth)
    }

    private func appRow(_ app: AppAgg) -> some View {
        let rate = rateTracker.rates[app.processPath] ?? (0, 0)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(nsImage: AppIcon.image(forProcessPath: app.processPath))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(app.name)
                    .font(.system(size: 13))
                Spacer()
                Text("\(app.activeConnections)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Text("↑ \(ByteRate.string(rate.up))")
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NetglassColors.upload)
                Text("↓ \(ByteRate.string(rate.down))")
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NetglassColors.download)
            }
            .padding(.leading, 22)
        }
        .padding(.vertical, 3)
    }

    private func expandedBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedApps.contains(key) },
            set: { isExpanded in
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expandedApps.insert(key) } else { expandedApps.remove(key) }
                }
            })
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
