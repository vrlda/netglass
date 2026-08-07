import SwiftUI

/// Main window: three columns — sidebar, content, inspector. Persisted
/// visibility for sidebar/inspector; the toolbar handles the rest.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var liveModel: LiveConnectionsModel
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var monitoring: MonitoringViewModel
    @EnvironmentObject private var capture: PacketCaptureViewModel

    @State private var inspectorFlow: LiveFlow?
    @State private var showPalette = false

    var body: some View {
        NavigationSplitView {
            if appVM.sidebarVisible {
                SidebarView()
                    .environmentObject(appVM)
                    .environmentObject(liveModel)
            }
        } detail: {
            VStack(spacing: 0) {
                MainToolbarView()
                content
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appVM.sidebarVisible.toggle()
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle sidebar")
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .overlay {
            if showPalette {
                CommandPaletteView(isPresented: $showPalette)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            appVM.inspectorVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPalette)) { _ in
            showPalette = true
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 0) {
            Group {
                switch appVM.selectedSection {
                case .overview:
                    OverviewView()
                case .liveConnections:
                    LiveConnectionsView(selectedFlow: $inspectorFlow)
                case .applications:
                    ApplicationsView()
                case .domains:
                    DomainsView()
                case .dnsActivity:
                    DNSActivityView()
                case .captures:
                    CapturesView()
                case .packetInspector:
                    PacketInspectorView()
                case .history:
                    HistoryTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(appVM)
            .environmentObject(monitoring)
            .environmentObject(capture)

            if appVM.inspectorVisible {
                Divider()
                if let inspectorFlow {
                    ConnectionInspectorView(flow: inspectorFlow)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    EmptyStateView(symbol: "sidebar.right",
                                   title: "No connection selected",
                                   message: "Select a row in Live Connections to inspect its details")
                        .frame(width: NetglassMetrics.inspectorWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(animated ? .easeInOut(duration: 0.2) : nil, value: appVM.inspectorVisible)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animated: Bool { !reduceMotion }
}

extension Notification.Name {
    static let toggleInspector = Notification.Name("netglass.toggleInspector")
    static let openPalette = Notification.Name("netglass.openPalette")
}
