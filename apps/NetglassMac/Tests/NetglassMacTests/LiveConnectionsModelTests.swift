import Foundation
import Testing
@testable import FlowModel
@testable import FlowSource
@testable import NetglassMac

@Suite struct LiveConnectionsModelTests {
    private func fixtureSampler() throws -> Sampler {
        let base = try FixtureLocator.repoRoot()
        return Sampler(
            nettopClient: FileNettopClient(url: base.appendingPathComponent("Fixtures/nettop/synthetic.txt")),
            lsofClient: FileLsofClient(url: base.appendingPathComponent("Fixtures/lsof/synthetic.txt")),
            resolver: TestResolver())
    }

    @MainActor
    @Test func appliesOpenedEvents() async throws {
        let model = LiveConnectionsModel(sampler: try fixtureSampler())
        await model.runOnce()
        #expect(model.flows.count == 2)
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

        let model = LiveConnectionsModel(sampler: Sampler(
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
        let model = LiveConnectionsModel(sampler: try fixtureSampler())
        await model.runOnce()
        model.searchText = "Telegram"
        #expect(model.visibleFlows.count == 1)
        #expect(model.visibleFlows[0].pid == 9217)
        model.searchText = "149.154"
        #expect(model.visibleFlows.count == 1)
        model.searchText = "zzz"
        #expect(model.visibleFlows.isEmpty)
    }

    // MARK: - Fixtures

    /// Writes tick-1 and tick-2 nettop/lsof files to `dir`. Tick 2 raises
    /// Telegram's counters by exactly 100/100; everything else stays identical.
    private func writeTicks(to dir: URL, telegramBytesIn: UInt64, telegramBytesOut: UInt64) throws {
        let lsof = """
        COMMAND  PID USER FD  TYPE DEVICE SIZE/OFF NODE NAME
        Telegram 9217 dan 10u IPv4 0x1 0t0 0 TCP 192.168.1.42:51234->149.154.167.51:443 (ESTABLISHED)
        Safari   8810 dan 11u IPv4 0x2 0t0 0 TCP 192.168.1.42:51235->17.253.144.10:443 (ESTABLISHED)
        """
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
