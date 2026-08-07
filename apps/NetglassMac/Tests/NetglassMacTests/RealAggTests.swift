import Foundation
import Persistence
import Testing
@testable import FlowModel
@testable import NetglassMac

@Suite struct RealAggTests {
    private func flow(process: String, remoteText: String, domain: String?,
                      bytesSent: UInt64 = 100, bytesReceived: UInt64 = 200,
                      active: Bool = true) throws -> LiveFlow {
        LiveFlow(
            flowID: UUID(), pid: Int32(remoteText.hashValue % 9999 + 1),
            processName: process,
            executablePath: "/Applications/\(process).app/Contents/MacOS/\(process)",
            bundleIdentifier: nil,
            transport: .tcp,
            local: NetworkEndpoint(address: try #require(IPAddress(text: "192.168.1.42")), port: 51234),
            remote: NetworkEndpoint(address: try #require(IPAddress(text: remoteText)), port: 443),
            startedAt: Date(timeIntervalSince1970: 1_752_800_000),
            bytesSent: bytesSent, bytesReceived: bytesReceived,
            isActive: active, endedAt: nil,
            remoteDomain: domain, remoteDomainConfidence: domain == nil ? nil : 0.6)
    }

    @Test func appsAggregateByPath() throws {
        let flows = [
            try flow(process: "Telegram", remoteText: "149.154.167.51", domain: "telegram.example", bytesReceived: 300),
            try flow(process: "Telegram", remoteText: "149.154.167.52", domain: "telegram.example", bytesReceived: 100),
            try flow(process: "Safari", remoteText: "17.253.144.10", domain: "apple.example", bytesReceived: 500),
        ]
        let apps = RealAgg.apps(from: flows)
        #expect(apps.count == 2)
        let telegram = try #require(apps.first { $0.name == "Telegram" })
        #expect(telegram.bytesReceived == 400)
        #expect(telegram.activeConnections == 2)
        #expect(telegram.domains == ["telegram.example"])
        #expect(telegram.destinations.count == 2)
        let safari = try #require(apps.first { $0.name == "Safari" })
        #expect(safari.bytesReceived == 500)
    }

    @Test func domainsAggregateAcrossApps() throws {
        let flows = [
            try flow(process: "Telegram", remoteText: "149.154.167.51", domain: "telegram.example", bytesReceived: 300),
            try flow(process: "Safari", remoteText: "17.253.144.10", domain: "apple.example", bytesReceived: 500),
            try flow(process: "Terminal", remoteText: "8.8.8.8", domain: nil, bytesReceived: 50),
        ]
        let domains = RealAgg.domains(from: flows)
        #expect(domains.count == 3)
        let apple = try #require(domains.first { $0.name == "apple.example" })
        #expect(apple.applications == ["Safari"])
        #expect(apple.connections == 1)
        let unresolved = try #require(domains.first { $0.name == "8.8.8.8" })
        #expect(unresolved.confidence == nil)
    }

    @Test func unresolvedIPsListed() throws {
        let flows = [
            try flow(process: "Terminal", remoteText: "8.8.8.8", domain: nil),
            try flow(process: "Terminal", remoteText: "1.1.1.1", domain: nil),
            try flow(process: "Telegram", remoteText: "149.154.167.51", domain: "telegram.example"),
        ]
        let unresolved = RealAgg.unresolvedIPs(from: flows)
        #expect(unresolved == ["1.1.1.1", "8.8.8.8"])
    }

    @MainActor
    @Test func rateTrackerComputesDeltas() throws {
        let tracker = AppRateTracker()
        let flows1 = [
            try flow(process: "Telegram", remoteText: "149.154.167.51", domain: "telegram.example",
                     bytesSent: 1_000, bytesReceived: 2_000),
        ]
        let t0 = Date(timeIntervalSince1970: 1_752_800_000)
        tracker.update(apps: RealAgg.apps(from: flows1), now: t0)
        #expect(tracker.rates.isEmpty)   // no baseline yet

        let flows2 = [
            try flow(process: "Telegram", remoteText: "149.154.167.51", domain: "telegram.example",
                     bytesSent: 1_100, bytesReceived: 2_200),
        ]
        tracker.update(apps: RealAgg.apps(from: flows2), now: t0.addingTimeInterval(10))
        let rate = try #require(tracker.rates["/Applications/Telegram.app/Contents/MacOS/Telegram"])
        #expect(rate.up == 10)     // 100 bytes / 10 s
        #expect(rate.down == 20)   // 200 bytes / 10 s
    }

    @Test func samplesPerBucketFollowsInterval() {
        // the live bar grows once per sample: 10 samples per 5s bucket at
        // 0.5s sampling, fewer at slower cadences
        #expect(TrafficHistory.samplesPerBucket(interval: 0.25) == 20)
        #expect(TrafficHistory.samplesPerBucket(interval: 0.5) == 10)
        #expect(TrafficHistory.samplesPerBucket(interval: 1.0) == 5)
        #expect(TrafficHistory.samplesPerBucket(interval: 2.0) == 2)
        #expect(TrafficHistory.samplesPerBucket(interval: 5.0) == 1)
        #expect(TrafficHistory.samplesPerBucket(interval: 0.1) >= 10)
    }

    @Test func liveSamplesMapHistory() {
        let history = [
            ThroughputSample(date: Date(), bytesPerSecondDown: 100, bytesPerSecondUp: 50),
            ThroughputSample(date: Date(), bytesPerSecondDown: 200, bytesPerSecondUp: 150),
        ]
        let samples = TrafficHistory.liveSamples(history)
        #expect(samples.count == 2)
        #expect(samples[0].up == 50)
        #expect(samples[0].down == 100)
        #expect(samples[1].up == 150)
        #expect(samples[1].down == 200)
    }

    @Test func aggregateBucketsThreeSecondWindows() {
        // 6 seconds of 1s history → 2 buckets of 3s (sums)
        let t = Date(timeIntervalSince1970: 1_752_800_000)
        let history = [
            ThroughputSample(date: t, bytesPerSecondDown: 10, bytesPerSecondUp: 1),
            ThroughputSample(date: t.addingTimeInterval(1), bytesPerSecondDown: 20, bytesPerSecondUp: 2),
            ThroughputSample(date: t.addingTimeInterval(2), bytesPerSecondDown: 30, bytesPerSecondUp: 3),
            ThroughputSample(date: t.addingTimeInterval(3), bytesPerSecondDown: 40, bytesPerSecondUp: 4),
            ThroughputSample(date: t.addingTimeInterval(4), bytesPerSecondDown: 50, bytesPerSecondUp: 5),
            ThroughputSample(date: t.addingTimeInterval(5), bytesPerSecondDown: 60, bytesPerSecondUp: 6),
        ]
        let buckets = TrafficHistory.aggregate(history, bucketSeconds: 3, capacity: 100)
        #expect(buckets.count == 2)
        #expect(buckets[0].up == 6)      // 1+2+3
        #expect(buckets[0].down == 60)   // 10+20+30
        #expect(buckets[1].up == 15)
        #expect(buckets[1].down == 150)
    }

    @Test func aggregateKeepsNewestBucketsAtCapacity() {
        let t = Date(timeIntervalSince1970: 1_752_800_000)
        let history = (0..<9).map { i in
            ThroughputSample(date: t.addingTimeInterval(TimeInterval(i)),
                             bytesPerSecondDown: 10, bytesPerSecondUp: 1)
        }
        let buckets = TrafficHistory.aggregate(history, bucketSeconds: 3, capacity: 2)
        #expect(buckets.count == 2)
        #expect(buckets[0].down == 30)
        #expect(buckets[1].down == 30)
    }

    @Test func aggregateKeepsCandleIdentityWhenWindowRolls() {
        let t = Date(timeIntervalSince1970: 1_752_800_000)
        let history = (0..<9).map { i in
            ThroughputSample(date: t.addingTimeInterval(TimeInterval(i)),
                             bytesPerSecondDown: Double(i), bytesPerSecondUp: 0)
        }
        let rolled = history + (9..<12).map { i in
            ThroughputSample(date: t.addingTimeInterval(TimeInterval(i)),
                             bytesPerSecondDown: Double(i), bytesPerSecondUp: 0)
        }
        let before = TrafficHistory.aggregate(history, bucketSeconds: 3, capacity: 3)
        let after = TrafficHistory.aggregate(rolled, bucketSeconds: 3, capacity: 3)

        #expect(after.map(\.id) == before.dropFirst().map(\.id) + [after.last!.id])
    }

    @Test func aggregateEmitsGrowingPartialBucket() {
        // 7 samples in 3s buckets → 2 complete + 1 partial; the partial is
        // the live bar that grows with traffic inside the current window.
        let t = Date(timeIntervalSince1970: 1_752_800_000)
        let history = (0..<7).map { i in
            ThroughputSample(date: t.addingTimeInterval(TimeInterval(i)),
                             bytesPerSecondDown: 10, bytesPerSecondUp: 1)
        }
        let buckets = TrafficHistory.aggregate(history, bucketSeconds: 3, capacity: 100)
        #expect(buckets.count == 3)
        #expect(buckets[2].down == 10)   // partial holds only the 7th sample
        // the partial GROWS as more samples land inside the window
        let history8 = history + [ThroughputSample(date: t.addingTimeInterval(7),
                                                   bytesPerSecondDown: 10, bytesPerSecondUp: 1)]
        let buckets8 = TrafficHistory.aggregate(history8, bucketSeconds: 3, capacity: 100)
        #expect(buckets8[2].down == 20)
        // a full 5-minute window at 1s ticks yields exactly 60 complete buckets
        let fiveMinutes = (0..<300).map { i in
            ThroughputSample(date: t.addingTimeInterval(TimeInterval(i)),
                             bytesPerSecondDown: 10, bytesPerSecondUp: 1)
        }
        #expect(TrafficHistory.aggregate(fiveMinutes, bucketSeconds: 5, capacity: 60).count == 60)
    }

    @Test func bucketSamplesConvertToRates() {
        let start = Date(timeIntervalSince1970: 1_752_800_000)
        let buckets = [
            TrafficBucket(date: start, bytesSent: 600, bytesReceived: 1_200),
            TrafficBucket(date: start.addingTimeInterval(60), bytesSent: 300, bytesReceived: 600),
        ]
        let samples = TrafficHistory.bucketSamples(buckets, secondsPerBucket: 60)
        #expect(samples[0].up == 10)      // 600 B / 60 s
        #expect(samples[0].down == 20)
        #expect(samples[1].up == 5)
    }
}
