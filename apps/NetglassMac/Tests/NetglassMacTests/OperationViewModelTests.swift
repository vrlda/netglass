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
        #expect(bundle.operation.endedAt != nil)
        #expect(bundle.operation.cleanupReport != nil)
        #expect(bundle.snapshotOut != nil)
        #expect(!bundle.events.isEmpty)
        #expect(!bundle.warnings.isEmpty)   // preTunnelDNS fires: utun4 + DNS within grace
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

    @MainActor
    @Test func periodicStateResetsBetweenOperations() {
        let vm = OperationViewModel(snapshotProvider: { OperationSnapshot(date: Date()) })
        let t0 = Date(timeIntervalSince1970: 1_752_800_000)
        let endpoint = NetworkEndpoint(address: IPAddress(text: "198.51.100.24")!, port: 443)
        func beacon(_ i: Int) -> OperationEvent {
            .connection(opened: true, date: t0.addingTimeInterval(TimeInterval(i) * 60),
                        process: "helper", executablePath: "/bin/helper",
                        remote: endpoint, interface: "utun4", transport: .tcp, bytes: 100)
        }
        vm.start(name: "Op 1", expectedTunnel: "utun4", scope: OperationScope())
        vm.ingest((0..<4).map(beacon))
        #expect(vm.periodic.count == 1)
        vm.stop(liveFlows: [])
        vm.discard()
        vm.start(name: "Op 2", expectedTunnel: "utun4", scope: OperationScope())
        #expect(vm.periodic.isEmpty)
        vm.ingest((0..<3).map(beacon))
        #expect(vm.periodic.isEmpty)   // old keys must not re-emit early
        vm.ingest([beacon(3)])
        #expect(vm.periodic.count == 1)   // 4 fresh observations in the new session
    }
}
