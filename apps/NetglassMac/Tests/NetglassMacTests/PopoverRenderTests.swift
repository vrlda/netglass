import SwiftUI
import AppKit
import Testing
@testable import FlowModel
@testable import FlowSource
@testable import NetglassMac

@Suite struct PopoverRenderTests {
    struct R: ProcessIdentityProviding {
        func identity(for pid: Int32) -> ProcessIdentity? { nil }
    }

    @MainActor
    @Test func renderPopoverSizing() throws {
        let model = LiveConnectionsModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: URL(fileURLWithPath: "/dev/null")),
            lsofClient: FileLsofClient(url: URL(fileURLWithPath: "/dev/null")),
            resolver: R()),
            domainResolver: DomainResolver(lookup: NoopDNS()))
        let view = MenuBarPopoverView()
            .environmentObject(model as LiveConnectionsModel)
            .environmentObject(AppState(databaseDirectory: FileManager.default.temporaryDirectory))
            .environmentObject(AppViewModel())
            .environmentObject(MonitoringViewModel())
            .environmentObject(PacketCaptureViewModel())
            .environmentObject(AppRateTracker())
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        print("PROBE_SIZE:", hosting.fittingSize)
        #expect(hosting.fittingSize.width > 300)
        #expect(hosting.fittingSize.height > 300)
    }

    struct NoopDNS: ReverseDNSResolving {
        func hostname(for ip: String) -> String? { nil }
        func ipAddresses(for hostname: String) -> [String] { [] }
    }
}
