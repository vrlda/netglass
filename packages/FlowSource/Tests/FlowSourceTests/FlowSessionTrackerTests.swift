import Foundation
import FlowModel
import Testing
@testable import FlowSource

@Suite struct FlowSessionTrackerTests {
    private let now = Date(timeIntervalSince1970: 1_752_800_000)
    private let local = NetworkEndpoint(
        address: IPAddress(text: "192.168.1.42")!, port: 51234)
    private let remote = NetworkEndpoint(
        address: IPAddress(text: "149.154.167.51")!, port: 443)

    private func row(pid: Int32 = 9217, bytesIn: UInt64, bytesOut: UInt64,
                     processName: String = "Telegram") -> NettopRow {
        NettopRow(processName: processName, pid: pid, connID: nil,
                  state: "established", interface: "en0",
                  bytesIn: bytesIn, bytesOut: bytesOut,
                  local: local, remote: remote, transport: .tcp)
    }

    private func identity(pid: Int32, path: String = "/Applications/Telegram.app/Contents/MacOS/Telegram") -> ProcessIdentity {
        ProcessIdentity(pid: pid, startTime: nil, executablePath: path,
                        bundleIdentifier: "org.telegram.desktop", parentPID: nil)
    }

    @Test func newRowEmitsFlowOpened() throws {
        let tracker = FlowSessionTracker()
        let events = tracker.ingest([row(bytesIn: 100, bytesOut: 200)],
                                    identityForPID: { identity(pid: $0) })
        #expect(events.count == 1)
        guard case .flowOpened(let opened) = events[0] else {
            Issue.record("expected flowOpened, got \(events[0])"); return
        }
        #expect(opened.pid == 9217)
        #expect(opened.bytesSent == 200)
        #expect(opened.bytesReceived == 100)
        #expect(opened.process?.bundleIdentifier == "org.telegram.desktop")
    }

    @Test func changedCountersEmitFlowUpdated() throws {
        let tracker = FlowSessionTracker()
        let first = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        let second = tracker.ingest([row(bytesIn: 150, bytesOut: 250)], identityForPID: { identity(pid: $0) })
        #expect(first.count == 1)
        #expect(second.count == 1)
        guard case .flowUpdated(let counters) = second[0] else {
            Issue.record("expected flowUpdated, got \(second[0])"); return
        }
        #expect(counters.bytesSent == 250)
        #expect(counters.bytesReceived == 150)
    }

    @Test func unchangedCountersEmitNothing() {
        let tracker = FlowSessionTracker()
        _ = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        let second = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        #expect(second.isEmpty)
    }

    @Test func absentRowClosesAfterThreeMisses() throws {
        let fixed = Date(timeIntervalSince1970: 1_752_800_000)
        let tracker = FlowSessionTracker(now: { fixed })
        _ = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        _ = tracker.ingest([], identityForPID: { identity(pid: $0) })   // miss 1
        _ = tracker.ingest([], identityForPID: { identity(pid: $0) })   // miss 2
        let third = tracker.ingest([], identityForPID: { identity(pid: $0) })  // miss 3
        #expect(third.count == 1)
        guard case .flowClosed(let closed) = third[0] else {
            Issue.record("expected flowClosed, got \(third[0])"); return
        }
        #expect(closed.endedAt == fixed)
    }

    @Test func silentSessionClosesOnTimeBasedTTL() throws {
        let clock = MockClock()
        // TTL 30s: after one silent tick the session survives (misses 1);
        // advancing the clock past the TTL closes it on the next ingest even
        // though the miss budget (3) is far from spent.
        let tracker = FlowSessionTracker(now: { clock.now }, inactivityTTL: 30)
        _ = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        clock.advance(10)
        _ = tracker.ingest([], identityForPID: { identity(pid: $0) })
        #expect(tracker.sessionCount == 1)
        clock.advance(40)   // 50s since last seen
        let events = tracker.ingest([], identityForPID: { identity(pid: $0) })
        #expect(events.count == 1)
        guard case .flowClosed = events[0] else {
            Issue.record("expected flowClosed, got \(events[0])"); return
        }
        #expect(tracker.sessionCount == 0)
    }

    @Test func injectedClockDrivesTimestamps() throws {
        let fixed = Date(timeIntervalSince1970: 1_752_800_000)
        let tracker = FlowSessionTracker(now: { fixed })
        let events = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        guard case .flowOpened(let opened) = events[0] else { Issue.record("expected flowOpened"); return }
        #expect(opened.startedAt == fixed)
    }

    @Test func counterResetReopensSession() throws {
        let tracker = FlowSessionTracker()
        _ = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        let reset = tracker.ingest([row(bytesIn: 50, bytesOut: 100)], identityForPID: { identity(pid: $0) })
        #expect(reset.count == 2)
        guard case .flowClosed = reset[0] else { Issue.record("expected close first"); return }
        guard case .flowOpened = reset[1] else { Issue.record("expected reopen"); return }
    }

    @Test func identityChangeReopensSession() throws {
        let tracker = FlowSessionTracker()
        _ = tracker.ingest([row(bytesIn: 100, bytesOut: 200)],
                           identityForPID: { identity(pid: $0) })
        let changed = tracker.ingest([row(bytesIn: 100, bytesOut: 200)],
                                     identityForPID: { identity(pid: $0, path: "/usr/bin/other") })
        #expect(changed.count == 2)
        guard case .flowClosed = changed[0] else { Issue.record("expected close"); return }
        guard case .flowOpened(let reopened) = changed[1] else { Issue.record("expected reopen"); return }
        #expect(reopened.pid == 9217)
        #expect(reopened.process?.executablePath == "/usr/bin/other")
    }

    @Test func reappearingFlowKeepsSession() throws {
        let tracker = FlowSessionTracker()
        let openedEvents = tracker.ingest([row(bytesIn: 100, bytesOut: 200)],
                                          identityForPID: { identity(pid: $0) })
        guard case .flowOpened(let opened) = openedEvents[0] else {
            Issue.record("expected flowOpened"); return
        }
        _ = tracker.ingest([], identityForPID: { identity(pid: $0) })   // miss 1
        let reappeared = tracker.ingest([row(bytesIn: 100, bytesOut: 200)],
                                        identityForPID: { identity(pid: $0) })
        #expect(reappeared.isEmpty)   // session survives misses, no close/reopen
        let updated = tracker.ingest([row(bytesIn: 150, bytesOut: 250)],
                                     identityForPID: { identity(pid: $0) })
        #expect(updated.count == 1)
        guard case .flowUpdated(let counters) = updated[0] else {
            Issue.record("expected flowUpdated"); return
        }
        #expect(counters.flowID == opened.flowID)
    }

    @Test func transientIdentityFailureDoesNotChurn() throws {
        let tracker = FlowSessionTracker()
        // batch 1: identity resolves
        _ = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        // batch 2: resolver transiently fails (returns nil) — must NOT close+reopen
        let second = tracker.ingest([row(bytesIn: 120, bytesOut: 240)],
                                    identityForPID: { _ in nil })
        #expect(second.count == 1)
        guard case .flowUpdated(let counters) = second[0] else {
            Issue.record("expected single flowUpdated, got \(second)"); return
        }
        #expect(counters.bytesSent == 240)
        // batch 3: identity resolves again — still the same session, no reopen
        let third = tracker.ingest([row(bytesIn: 150, bytesOut: 300)], identityForPID: { identity(pid: $0) })
        #expect(third.count == 1)
        guard case .flowUpdated = third[0] else { Issue.record("expected flowUpdated"); return }
    }

    @Test func nilBytesPreserveCounters() throws {
        let tracker = FlowSessionTracker()
        _ = tracker.ingest([row(bytesIn: 100, bytesOut: 200)], identityForPID: { identity(pid: $0) })
        let nilBytes = NettopRow(processName: "Telegram", pid: 9217, connID: nil,
                                 state: "established", interface: "en0",
                                 bytesIn: nil, bytesOut: nil,
                                 local: local, remote: remote, transport: .tcp)
        #expect(tracker.ingest([nilBytes], identityForPID: { identity(pid: $0) }).isEmpty)
        let after = tracker.ingest([row(bytesIn: 150, bytesOut: 300)], identityForPID: { identity(pid: $0) })
        #expect(after.count == 1)
        guard case .flowUpdated(let counters) = after[0] else { Issue.record("expected flowUpdated"); return }
        #expect(counters.bytesSent == 300)   // not zeroed by the nil sample
    }

    @Test func rowsMissingFieldsSkipped() {        let tracker = FlowSessionTracker()
        let badRows = [
            NettopRow(processName: "A", pid: nil, connID: nil, state: nil, interface: nil,
                      bytesIn: 1, bytesOut: 1, local: local, remote: remote, transport: .tcp),
            NettopRow(processName: "B", pid: 1, connID: nil, state: nil, interface: nil,
                      bytesIn: 1, bytesOut: 1, local: nil, remote: remote, transport: .tcp),
            NettopRow(processName: "C", pid: 2, connID: nil, state: nil, interface: nil,
                      bytesIn: 1, bytesOut: 1, local: local, remote: nil, transport: .tcp),
            NettopRow(processName: "D", pid: 3, connID: nil, state: nil, interface: nil,
                      bytesIn: 1, bytesOut: 1, local: local, remote: remote, transport: nil),
        ]
        let events = tracker.ingest(badRows, identityForPID: { identity(pid: $0) })
        #expect(events.isEmpty)
    }

    @Test func distinctEndpointsAreDistinctSessions() {
        let tracker = FlowSessionTracker()
        let otherRemote = NetworkEndpoint(address: IPAddress(text: "8.8.8.8")!, port: 53)
        let otherRow = NettopRow(processName: "Chrome", pid: 200, connID: nil,
                                 state: "established", interface: "en0",
                                 bytesIn: 1, bytesOut: 1, local: local,
                                 remote: otherRemote, transport: .tcp)
        let events = tracker.ingest([row(bytesIn: 1, bytesOut: 1), otherRow],
                                    identityForPID: { pid in identity(pid: pid) })
        #expect(events.count == 2)
    }

    @Test func openedEventCarriesInterface() {
        let tracker = FlowSessionTracker()
        let row = NettopRow(processName: "curl", pid: 42, connID: nil, state: "Established",
                            interface: "utun4", bytesIn: 100, bytesOut: 200,
                            local: NetworkEndpoint(address: IPAddress(text: "192.168.1.5")!, port: 51234),
                            remote: NetworkEndpoint(address: IPAddress(text: "8.8.8.8")!, port: 443),
                            transport: .tcp)
        let events = tracker.ingest([row], identityForPID: { _ in nil })
        guard case .flowOpened(let opened) = events.first else {
            Issue.record("no opened event"); return
        }
        #expect(opened.interface == "utun4")
    }
}
