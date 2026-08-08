import Foundation
import Testing
@testable import FlowModel
@testable import FlowSource
@testable import NetglassMac

@Suite struct OperationViewModelTests {
    @MainActor
    @Test func startStopLifecycle() async throws {
        let vm = OperationViewModel(snapshotProvider: { OperationSnapshot(date: Date()) })
        #expect(vm.session == nil)
        vm.start(name: "Op", expectedTunnel: "utun4",
                 scope: OperationScope(allowedCIDRs: [IPRange(text: "192.168.0.0/16")!]))
        #expect(vm.session != nil)
        #expect(vm.isRunning)
        vm.ingest([.connection(opened: true, date: Date(), process: "nmap", executablePath: "/bin/nmap",
                               remote: NetworkEndpoint(address: IPAddress(text: "10.40.0.1")!, port: 443),
                               interface: "en0", transport: .tcp, bytes: 10)])
        #expect(vm.warnings.contains { $0.rule == .scopeViolation })
        vm.stop(liveFlows: [])
        #expect(!vm.isRunning)
        #expect(vm.session?.endedAt != nil)
        #expect(vm.session?.snapshotOut != nil)
        #expect(vm.session?.cleanupReport != nil)
        vm.discard()
        #expect(vm.session == nil)
    }

    @MainActor
    @Test func exportBundleRoundTrips() throws {
        let vm = OperationViewModel(snapshotProvider: { OperationSnapshot(date: Date()) })
        vm.start(name: "Op", expectedTunnel: "utun4", scope: OperationScope())
        vm.ingest([.dns(date: Date(), process: "curl", domain: "target.example", ip: "1.2.3.4")])
        vm.stop(liveFlows: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("op-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.export(to: url)
        let data = try Data(contentsOf: url)
        let bundle = try FlowJSON.decoder.decode(OperationBundle.self, from: data)
        #expect(bundle.operation.name == "Op")
        #expect(!bundle.events.isEmpty)
    }

    @MainActor
    @Test func listenerPollingEmitsOpenedEvents() {
        let vm = OperationViewModel(snapshotProvider: { OperationSnapshot(date: Date()) })
        vm.start(name: "Op", expectedTunnel: "utun4", scope: OperationScope())
        #expect(vm.session?.snapshotIn.listeners.isEmpty == true)
        let newSnapshot = OperationSnapshot(
            date: Date().addingTimeInterval(2),
            listeners: [LsofListener(pid: 7, processName: "python3", transport: .tcp,
                                     address: "0.0.0.0", port: 8000)])
        vm.pollListenersForTesting(snapshot: newSnapshot)
        #expect(vm.session?.events.contains { event in
            if case .listener(let port) = event, port.action == .opened,
               port.process == "python3", port.port == 8000 { return true }
            return false
        } == true)
        #expect(vm.warnings.contains { $0.rule == .listenerExposure })
    }
}
