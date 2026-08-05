import Foundation
import Testing
@testable import FlowModel
@testable import Persistence
@testable import NetglassMac

@Suite struct HistoryQueryTests {
    private func seed() throws -> FlowDatabase {
        let db = try FlowDatabase(path: ":memory:")
        let process = ProcessIdentity(pid: 9217, startTime: nil,
                                      executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                                      bundleIdentifier: "org.telegram.desktop", parentPID: nil)
        let local = NetworkEndpoint(address: try #require(IPAddress(text: "192.168.1.42")), port: 51234)
        let remote = NetworkEndpoint(address: try #require(IPAddress(text: "149.154.167.51")), port: 443)
        try db.ingest([.flowOpened(FlowEvent.FlowOpened(
            flowID: UUID(), process: process, pid: 9217, transport: .tcp,
            local: local, remote: remote,
            startedAt: Date(timeIntervalSince1970: 1_752_800_000),
            bytesSent: 100, bytesReceived: 200))])
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
}
