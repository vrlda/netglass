import Foundation
import Testing
@testable import FlowModel
@testable import Persistence
@testable import NetglassMac

@Suite struct HistoryQueryTests {
    private func seed() throws -> FlowDatabase {
        try db(with: [opened(
            executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
            bundleIdentifier: "org.telegram.desktop",
            remoteText: "149.154.167.51", remotePort: 443,
            startedAt: 1_752_800_000)])
    }

    private func opened(executablePath: String, bundleIdentifier: String?,
                        remoteText: String, remotePort: UInt16,
                        startedAt: Double) throws -> FlowEvent {
        let process = ProcessIdentity(pid: 9217, startTime: nil,
                                      executablePath: executablePath,
                                      bundleIdentifier: bundleIdentifier, parentPID: nil)
        let local = NetworkEndpoint(address: try #require(IPAddress(text: "192.168.1.42")), port: 51234)
        let remote = NetworkEndpoint(address: try #require(IPAddress(text: remoteText)), port: remotePort)
        return .flowOpened(FlowEvent.FlowOpened(
            flowID: UUID(), process: process, pid: 9217, transport: .tcp,
            local: local, remote: remote,
            startedAt: Date(timeIntervalSince1970: startedAt),
            bytesSent: 100, bytesReceived: 200))
    }

    private func db(with events: [FlowEvent]) throws -> FlowDatabase {
        let db = try FlowDatabase(path: ":memory:")
        try db.ingest(events)
        return db
    }

    @Test func historySearchByProcessName() throws {
        let db = try seed()
        let results = try HistoryQuery.search(database: db, text: "telegram")
        #expect(results.count == 1)
        #expect(results[0].processPath.contains("Telegram.app"))
    }

    @Test func historySearchByPort() throws {
        let db = try seed()
        let results = try HistoryQuery.search(database: db, text: "443")
        #expect(results.count == 1)
    }

    @Test func historySearchNoMatches() throws {
        let db = try seed()
        #expect(try HistoryQuery.search(database: db, text: "zzz").isEmpty)
    }

    @Test func historySearchByIP() throws {
        let db = try seed()
        let results = try HistoryQuery.search(database: db, text: "149.154.167.51")
        #expect(results.count == 1)
        #expect(results[0].remoteAddress.text == "149.154.167.51")
    }

    @Test func historySearchByIPv6() throws {
        let db = try db(with: [opened(
            executablePath: "/usr/sbin/mDNSResponder",
            bundleIdentifier: nil,
            remoteText: "2001:db8::1", remotePort: 53,
            startedAt: 1_752_800_000)])
        let results = try HistoryQuery.search(database: db, text: "2001:db8::1")
        #expect(results.count == 1)
        #expect(results[0].remoteAddress.text == "2001:db8::1")
    }

    @Test func emptySearchReturnsAll() throws {
        let db = try seed()
        let results = try HistoryQuery.search(database: db, text: "")
        #expect(results.count == 1)
        #expect(results[0].processPath.contains("Telegram.app"))
    }

    @Test func sortNewestFirst() throws {
        let db = try db(with: [
            opened(executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                   bundleIdentifier: "org.telegram.desktop",
                   remoteText: "149.154.167.51", remotePort: 443,
                   startedAt: 1_752_800_000),
            opened(executablePath: "/Applications/Safari.app/Contents/MacOS/Safari",
                   bundleIdentifier: "com.apple.Safari",
                   remoteText: "17.253.144.10", remotePort: 443,
                   startedAt: 1_752_900_000),
        ])
        let results = try HistoryQuery.search(database: db, text: "")
        #expect(results.count == 2)
        #expect(results[0].startedAt == Date(timeIntervalSince1970: 1_752_900_000))
        #expect(results[0].processPath.contains("Safari.app"))
    }
}
