import Foundation
import Testing
@testable import FlowModel
@testable import FlowSource
@testable import NetglassMac

@Suite struct OperationSinkTests {
    @MainActor
    @Test func sinkReceivesOpenedEvents() async throws {
        let base = try FixtureLocator.repoRoot()
        let model = LiveConnectionsModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: base.appendingPathComponent("Fixtures/nettop/synthetic.txt")),
            lsofClient: FileLsofClient(url: base.appendingPathComponent("Fixtures/lsof/synthetic.txt")),
            resolver: TestResolver()),
            domainResolver: DomainResolver(lookup: NoopResolver()))
        var received: [OperationEvent] = []
        model.operationSink = { received.append(contentsOf: $0) }
        await model.runOnce()
        let opened = received.filter { event in
            guard case .connection(true, _, _, _, _, _, _, _) = event else { return false }
            return true
        }
        #expect(!opened.isEmpty)
        // the fixture's Telegram row carries interface en0
        let telegram = received.first { event in
            guard case .connection(true, _, let process, _, _, let interface, _, _) = event else { return false }
            return process == "Telegram" && interface == "en0"
        }
        #expect(telegram != nil)
    }

    @MainActor
    @Test func sinkReceivesDnsEventsWhenResolutionCapTrims() async throws {
        // The operation feed slices resolutionEvents by the number of events
        // appended this tick. Once the 200-entry cap trims the head
        // (removeFirst), a slice anchored at the pre-tick count is empty and
        // the tick's DNS events would be silently dropped.
        // Seeding: resolutionEvents is private(set), so fill the cap through
        // the public path — each tick enriches one event per NEW connection,
        // so a 200-row fixture saturates the cap in one tick.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-opcap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeConnections(count: 200, name: "seed", offset: 0, to: dir)
        try writeConnections(count: 2, name: "final", offset: 200, to: dir)

        let model = LiveConnectionsModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("seed-nettop.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("seed-lsof.txt")),
            resolver: TestResolver()),
            domainResolver: DomainResolver(lookup: NoopResolver()))
        var received: [OperationEvent] = []
        model.operationSink = { received.append(contentsOf: $0) }
        await model.runOnce()
        #expect(model.resolutionEvents.count == 200)
        received.removeAll()

        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("final-nettop.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("final-lsof.txt"))
        await model.runOnce()

        let dns = received.filter { event in
            guard case .dns = event else { return false }
            return true
        }
        // the final tick's 2 resolutions survive the cap trim (200 + 2 → 200)
        #expect(dns.count == 2)
    }

    struct TestResolver: ProcessIdentityProviding {
        func identity(for pid: Int32) -> ProcessIdentity? {
            ProcessIdentity(pid: pid, startTime: nil,
                            executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                            bundleIdentifier: "org.telegram.desktop", parentPID: nil)
        }
    }

    struct NoopResolver: ReverseDNSResolving {
        func hostname(for ip: String) -> String? { nil }
        func ipAddresses(for hostname: String) -> [String] { [] }
    }

    /// Writes nettop/lsof fixtures with `count` unique public-IP connections.
    /// Each row pair is a NEW session for the sampler's tracker, so one tick
    /// opens `count` flows and enrichment appends `count` resolution events.
    /// `offset` shifts the endpoint range so consecutive fixtures don't
    /// collide with earlier sessions (same key = update, not a new open).
    private func writeConnections(count: Int, name: String, offset: Int, to dir: URL) throws {
        var nettop = "time,,interface,state,bytes_in,bytes_out,\n"
        var lsof = "COMMAND  PID USER FD  TYPE DEVICE SIZE/OFF NODE NAME\n"
        for i in (offset + 1)...(offset + count) {
            let remote = "203.0.113.\(i)"
            let localPort = 50000 + i
            nettop += "00:00:00.000001,tcp4 192.168.1.42:\(localPort)<->\(remote):443,en0,Established,100,200,\n"
            lsof += "Telegram 9217 dan 10u IPv4 0x1 0t0 0 TCP 192.168.1.42:\(localPort)->\(remote):443 (ESTABLISHED)\n"
        }
        try nettop.write(to: dir.appendingPathComponent("\(name)-nettop.txt"),
                         atomically: true, encoding: .utf8)
        try lsof.write(to: dir.appendingPathComponent("\(name)-lsof.txt"),
                       atomically: true, encoding: .utf8)
    }
}
