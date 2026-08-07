import Foundation
import Testing
@testable import FlowModel
@testable import FlowSource
@testable import NetglassMac
@testable import Persistence

@Suite struct LiveConnectionsModelTests {
    private func fixtureSampler() throws -> Sampler {
        let base = try FixtureLocator.repoRoot()
        return Sampler(
            nettopClient: FileNettopClient(url: base.appendingPathComponent("Fixtures/nettop/synthetic.txt")),
            lsofClient: FileLsofClient(url: base.appendingPathComponent("Fixtures/lsof/synthetic.txt")),
            resolver: TestResolver())
    }

    /// Tests must never hit the network: every model gets a no-op resolver
    /// unless a test explicitly supplies its own.
    @MainActor
    private func noDomainModel(sampler: Sampler, database: FlowDatabase? = nil,
                               historyCapacity: Int = 120,
                               evictionTTL: TimeInterval = 600) -> LiveConnectionsModel {
        LiveConnectionsModel(sampler: sampler, database: database,
                             historyCapacity: historyCapacity,
                             domainResolver: DomainResolver(lookup: NoopResolver()),
                             evictionTTL: evictionTTL)
    }

    @MainActor
    @Test func appliesOpenedEvents() async throws {
        let model = noDomainModel(sampler: try fixtureSampler())
        await model.runOnce()
        // the fixture's only trackable connection is Telegram: the awdl0
        // fe80:: row is local traffic and is filtered, apsd has no pid, the
        // listen row has no endpoint
        #expect(model.flows.count == 1)
        let telegram = try #require(model.flows.first { $0.pid == 9217 })
        #expect(telegram.remote.address.text == "149.154.167.51")
        #expect(telegram.processName == "Telegram")
        #expect(telegram.bytesSent == 3400)
        #expect(telegram.bytesReceived == 1200)
        #expect(telegram.isActive)
    }

    @MainActor
    @Test func updatesCountersAcrossTicks() async throws {
        // tick 1: synthetic nettop+lsof with Telegram at 1200/3400 bytes
        // tick 2: same endpoints, Telegram counters bumped by exactly 100/100
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)

        let model = noDomainModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()))
        await model.runOnce()
        let before = try #require(model.flows.first { $0.pid == 9217 })
        #expect(before.bytesReceived == 1200)
        #expect(before.bytesSent == 3400)

        // swap the sampler's clients to the tick-2 files; the FlowSessionTracker
        // inside the sampler survives, so tick 2 is a counter update, not a reopen
        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-2.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-2.txt"))
        await model.runOnce()

        let after = try #require(model.flows.first { $0.pid == 9217 })
        #expect(after.flowID == before.flowID)
        #expect(after.bytesReceived == before.bytesReceived + 100)
        #expect(after.bytesSent == before.bytesSent + 100)
        #expect(model.flows.count == 2)
    }

    @MainActor
    @Test func filtersBySearchText() async throws {
        let model = noDomainModel(sampler: try fixtureSampler())
        await model.runOnce()
        model.searchText = "Telegram"
        #expect(model.visibleFlows.count == 1)
        #expect(model.visibleFlows[0].pid == 9217)
        model.searchText = "149.154"
        #expect(model.visibleFlows.count == 1)
        model.searchText = "zzz"
        #expect(model.visibleFlows.isEmpty)
    }

    @MainActor
    @Test func persistsEventsToDatabase() async throws {
        let database = try FlowDatabase(path: ":memory:")
        let model = noDomainModel(sampler: try fixtureSampler(), database: database)
        await model.runOnce()
        // ingest is detached (off the main actor): poll for the write
        var flows: [StoredFlow] = []
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            flows = try database.flows()
            if !flows.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(flows.count >= 1)
        #expect(flows.contains { $0.processPath.contains("Telegram") })
    }

    @MainActor
    @Test func reportsZeroThroughputBeforeFirstBaseline() async throws {
        let model = noDomainModel(sampler: try fixtureSampler())
        await model.runOnce()
        #expect(model.throughput == .zero)
    }

    @MainActor
    @Test func computesThroughputFromCounterDeltas() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-throughput-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)

        let model = noDomainModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()))
        await model.runOnce()
        #expect(model.throughput == .zero)

        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-2.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-2.txt"))
        await model.runOnce()

        // tick 2 adds exactly 100 bytes in and 100 out; both ran over the same
        // elapsed wall-clock, so the two rates must be identical.
        #expect(model.throughput.bytesPerSecondDown > 0)
        #expect(model.throughput.bytesPerSecondUp > 0)
        #expect(model.throughput.bytesPerSecondDown == model.throughput.bytesPerSecondUp)
    }

    @MainActor
    @Test func emptyStartDoesNotAbsorbCumulativeCounters() async throws {
        // Tick 1 sees no rows (empty start). Tick 2 reveals pre-existing
        // connections with CUMULATIVE counters — the rate must stay zero
        // (baseline only), not report the full cumulative total as traffic.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-first-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let emptyNettop = "time,,interface,state,bytes_in,bytes_out,\n"
        try emptyNettop.write(to: dir.appendingPathComponent("nettop-1.txt"),
                              atomically: true, encoding: .utf8)
        try lsofText().write(to: dir.appendingPathComponent("lsof-1.txt"),
                             atomically: true, encoding: .utf8)
        // Telegram's cumulative counters: 500 MB in / 340 MB out
        try nettopText(bytesIn: 500_000_000, bytesOut: 340_000_000)
            .write(to: dir.appendingPathComponent("nettop-2.txt"), atomically: true, encoding: .utf8)
        try lsofText().write(to: dir.appendingPathComponent("lsof-2.txt"),
                             atomically: true, encoding: .utf8)

        let model = noDomainModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()))
        await model.runOnce()
        #expect(model.flows.isEmpty)

        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-2.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-2.txt"))
        await model.runOnce()
        #expect(model.flows.contains { $0.pid == 9217 })
        // the cumulative 500 MB must NOT read as one tick's rate
        #expect(model.throughput.bytesPerSecondDown < 1_000_000)
        #expect(model.throughput.bytesPerSecondUp < 1_000_000)
    }

    @MainActor
    @Test func reopenDoesNotInflateThroughput() async throws {
        // A long-lived flow closes (missed rows) and reopens with the same
        // CUMULATIVE counters — the reopened flow must not double-count.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)
        let onlySafari = """
        time,,interface,state,bytes_in,bytes_out,
        00:00:00.000002,tcp4 192.168.1.42:51235<->17.253.144.10:443,en0,Established,0,0,
        """
        try onlySafari.write(to: dir.appendingPathComponent("nettop-2.txt"),
                             atomically: true, encoding: .utf8)
        try lsofText().write(to: dir.appendingPathComponent("lsof-2.txt"),
                             atomically: true, encoding: .utf8)

        let model = noDomainModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()))
        await model.runOnce()
        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-2.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-2.txt"))
        // three more ticks: the tracker closes Telegram after 3 misses
        await model.runOnce()
        await model.runOnce()
        await model.runOnce()
        let closed = try #require(model.flows.first { $0.pid == 9217 })
        #expect(!closed.isActive)

        // Telegram reappears with its cumulative counters inflated by 500 MB
        try nettopText(bytesIn: 501_200_000, bytesOut: 340_003_400)
            .write(to: dir.appendingPathComponent("nettop-3.txt"), atomically: true, encoding: .utf8)
        try lsofText().write(to: dir.appendingPathComponent("lsof-3.txt"),
                             atomically: true, encoding: .utf8)
        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-3.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-3.txt"))
        await model.runOnce()

        // the 500 MB cumulative must not appear as traffic
        #expect(model.throughput.bytesPerSecondDown < 1_000_000)
        // and the closed predecessor is gone from the live list
        #expect(model.flows.filter { $0.pid == 9217 && $0.isActive }.count == 1)
    }

    @MainActor
    @Test func recordsThroughputHistoryPerTick() async throws {        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)

        let model = noDomainModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()))
        await model.runOnce()
        #expect(model.throughputHistory.count == 1)
        #expect(model.throughputHistory[0].bytesPerSecondDown == 0)

        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-2.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-2.txt"))
        await model.runOnce()
        #expect(model.throughputHistory.count == 2)
        #expect(model.throughputHistory[1].bytesPerSecondDown == model.throughput.bytesPerSecondDown)
        #expect(model.throughputHistory[1].bytesPerSecondUp == model.throughput.bytesPerSecondUp)
        #expect(model.throughputHistory[0].date <= model.throughputHistory[1].date)
    }

    @MainActor
    @Test func throughputHistoryRespectsCapacity() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)   // overwrites both files

        let model = LiveConnectionsModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()), historyCapacity: 3)
        for _ in 0..<5 {
            await model.runOnce()
        }
        #expect(model.throughputHistory.count == 3)
    }

    @MainActor
    @Test func evictsClosedFlowsAfterTTL() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-evict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)
        // tick 2 drops the Telegram row: tracker closes it after 3 misses
        let nettopOnlySafari = """
        time,,interface,state,bytes_in,bytes_out,
        00:00:00.000002,tcp4 192.168.1.42:51235<->17.253.144.10:443,en0,Established,0,0,
        """
        try nettopOnlySafari.write(to: dir.appendingPathComponent("nettop-2.txt"), atomically: true, encoding: .utf8)
        try lsofText().write(to: dir.appendingPathComponent("lsof-2.txt"), atomically: true, encoding: .utf8)

        // TTL 0: closed flows leave the live table on the same tick
        let model = LiveConnectionsModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()), evictionTTL: 0)
        await model.runOnce()
        #expect(model.flows.count == 2)

        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-2.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-2.txt"))
        for _ in 0..<3 {
            await model.runOnce()
        }
        // Telegram: 3 misses → closed → evicted (TTL 0); Safari remains
        #expect(model.flows.count == 1)
        #expect(model.flows.allSatisfy { $0.isActive })
    }

    @MainActor
    @Test func keepsRateSaneWhenCountersReset() async throws {
        // tick 3 reports LOWER counters than tick 2 (nettop restart): the
        // tracker closes the old flow and reopens a fresh one with its own
        // cumulative baseline. The predecessor is dropped, so the totals
        // shrink and the rate clamps to zero — no wrap-around spike.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-clamp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTicks(to: dir, telegramBytesIn: 1200, telegramBytesOut: 3400)
        try nettopText(bytesIn: 50, bytesOut: 60)
            .write(to: dir.appendingPathComponent("nettop-3.txt"), atomically: true, encoding: .utf8)
        try lsofText().write(to: dir.appendingPathComponent("lsof-3.txt"), atomically: true, encoding: .utf8)

        let model = noDomainModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: dir.appendingPathComponent("nettop-1.txt")),
            lsofClient: FileLsofClient(url: dir.appendingPathComponent("lsof-1.txt")),
            resolver: TestResolver()))
        await model.runOnce()
        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-2.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-2.txt"))
        await model.runOnce()
        #expect(model.throughput.bytesPerSecondDown > 0)

        model.sampler.nettopClient = FileNettopClient(url: dir.appendingPathComponent("nettop-3.txt"))
        model.sampler.lsofClient = FileLsofClient(url: dir.appendingPathComponent("lsof-3.txt"))
        await model.runOnce()
        // the reopened flow carries a fresh cumulative baseline: the old
        // predecessor is dropped, so the delta clamps to zero — no spike
        #expect(model.throughput == .zero)
    }

    // MARK: - Fixtures

    private func lsofText() -> String {
        """
        COMMAND  PID USER FD  TYPE DEVICE SIZE/OFF NODE NAME
        Telegram 9217 dan 10u IPv4 0x1 0t0 0 TCP 192.168.1.42:51234->149.154.167.51:443 (ESTABLISHED)
        Safari   8810 dan 11u IPv4 0x2 0t0 0 TCP 192.168.1.42:51235->17.253.144.10:443 (ESTABLISHED)
        """
    }

    /// Writes tick-1 and tick-2 nettop/lsof files to `dir`. Tick 2 raises
    /// Telegram's counters by exactly 100/100; everything else stays identical.
    private func writeTicks(to dir: URL, telegramBytesIn: UInt64, telegramBytesOut: UInt64) throws {
        let lsof = lsofText()
        try nettopText(bytesIn: telegramBytesIn, bytesOut: telegramBytesOut)
            .write(to: dir.appendingPathComponent("nettop-1.txt"), atomically: true, encoding: .utf8)
        try lsof.write(to: dir.appendingPathComponent("lsof-1.txt"), atomically: true, encoding: .utf8)
        try nettopText(bytesIn: telegramBytesIn + 100, bytesOut: telegramBytesOut + 100)
            .write(to: dir.appendingPathComponent("nettop-2.txt"), atomically: true, encoding: .utf8)
        try lsof.write(to: dir.appendingPathComponent("lsof-2.txt"), atomically: true, encoding: .utf8)
    }

    private func nettopText(bytesIn: UInt64, bytesOut: UInt64) -> String {
        """
        time,,interface,state,bytes_in,bytes_out,
        00:00:00.000001,tcp4 192.168.1.42:51234<->149.154.167.51:443,en0,Established,\(bytesIn),\(bytesOut),
        00:00:00.000002,tcp4 192.168.1.42:51235<->17.253.144.10:443,en0,Established,0,0,
        """
    }

    /// Pid-aware identity stub: the real resolver must map both fixture rows, or
    /// the search filter test would match two rows for "Telegram".
    private struct TestResolver: ProcessIdentityProviding {
        func identity(for pid: Int32) -> ProcessIdentity? {
            switch pid {
            case 9217:
                ProcessIdentity(pid: pid, startTime: nil,
                                executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                                bundleIdentifier: "org.telegram.desktop", parentPID: nil)
            default:
                ProcessIdentity(pid: pid, startTime: nil,
                                executablePath: "/System/Library/CoreServices/mDNSResponder",
                                bundleIdentifier: nil, parentPID: nil)
            }
        }
    }
}


/// Reverse DNS stub: never touches the network, never resolves.
private struct NoopResolver: ReverseDNSResolving {
    func hostname(for ip: String) -> String? { nil }
    func ipAddresses(for hostname: String) -> [String] { [] }
}
