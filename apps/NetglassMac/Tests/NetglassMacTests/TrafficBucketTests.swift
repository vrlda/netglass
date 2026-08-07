import Foundation
import Persistence
import Testing
@testable import FlowModel
@testable import NetglassMac

@Suite struct TrafficBucketTests {
    private func opened(executablePath: String, remoteText: String,
                        startedAt: Double, bytesSent: UInt64,
                        bytesReceived: UInt64) throws -> FlowEvent {
        let process = ProcessIdentity(pid: 9217, startTime: nil,
                                      executablePath: executablePath,
                                      bundleIdentifier: nil, parentPID: nil)
        let local = NetworkEndpoint(address: try #require(IPAddress(text: "192.168.1.42")), port: 51234)
        let remote = NetworkEndpoint(address: try #require(IPAddress(text: remoteText)), port: 443)
        let openedEvent = FlowEvent.FlowOpened(
            flowID: UUID(), process: process, pid: 9217, transport: .tcp,
            local: local, remote: remote,
            startedAt: Date(timeIntervalSince1970: startedAt),
            bytesSent: bytesSent, bytesReceived: bytesReceived)
        return .flowOpened(openedEvent)
    }

    /// Ingest a full open→close lifetime so the flow has a real ended_at.
    private func ingestLifetime(_ db: FlowDatabase, flow: FlowEvent,
                                endedAt: Double) throws {
        guard case .flowOpened(let opened) = flow else { fatalError("expected opened") }
        try db.ingest([.flowClosed(FlowEvent.FlowClosed(
            flowID: opened.flowID, endedAt: Date(timeIntervalSince1970: endedAt)))])
    }

    @Test func bucketsDistributeBytesByOverlap() throws {
        let db = try FlowDatabase(path: ":memory:")
        let t0 = 1_752_800_000.0
        // flow 1: 60s lifetime exactly one 60s bucket, 1200 bytes total
        let f1 = try opened(executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                            remoteText: "149.154.167.51",
                            startedAt: t0, bytesSent: 600, bytesReceived: 1_200)
        try db.ingest([f1])
        try ingestLifetime(db, flow: f1, endedAt: t0 + 60)
        // flow 2: spans bucket 1 (30s) and bucket 2 (30s) — half each
        let f2 = try opened(executablePath: "/usr/sbin/mDNSResponder",
                            remoteText: "8.8.8.8",
                            startedAt: t0 + 30, bytesSent: 400, bytesReceived: 800)
        try db.ingest([f2])
        try ingestLifetime(db, flow: f2, endedAt: t0 + 90)

        let buckets = try db.trafficBuckets(secondsPerBucket: 60, buckets: 3,
                                            endingAt: Date(timeIntervalSince1970: t0 + 180))
        #expect(buckets.count == 3)
        // bucket 0: flow1 full + flow2 half → sent 600+200, received 1200+400
        #expect(buckets[0].bytesSent == 800)
        #expect(buckets[0].bytesReceived == 1_600)
        // bucket 1: flow2 half → sent 200, received 400
        #expect(buckets[1].bytesSent == 200)
        #expect(buckets[1].bytesReceived == 400)
        // bucket 2: nothing
        #expect(buckets[2].bytesSent == 0)
        #expect(buckets[2].bytesReceived == 0)
        db.close()
    }

    @Test func openFlowsCountUntilNow() throws {
        let db = try FlowDatabase(path: ":memory:")
        let t0 = 1_752_800_000.0
        try db.ingest([opened(executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                              remoteText: "149.154.167.51",
                              startedAt: t0, bytesSent: 100, bytesReceived: 200)])
        let buckets = try db.trafficBuckets(secondsPerBucket: 60, buckets: 2,
                                            endingAt: Date(timeIntervalSince1970: t0 + 120))
        // open flow spans the whole window: split across both buckets
        #expect(buckets[0].bytesSent == 50)
        #expect(buckets[1].bytesSent == 50)
        #expect(buckets[1].bytesReceived == 100)
        db.close()
    }
}
