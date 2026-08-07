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

    private func db(with events: [FlowEvent],
                    domains: [UUID: DomainCandidate] = [:]) throws -> FlowDatabase {
        let db = try FlowDatabase(path: ":memory:")
        try db.ingest(events, domains: domains)
        return db
    }

    private func flowID(_ event: FlowEvent) -> UUID {
        guard case .flowOpened(let opened) = event else { fatalError("expected opened") }
        return opened.flowID
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

    // MARK: - Grouping

    @Test func groupsFlowsByApp() throws {
        let db = try db(with: [
            opened(executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                   bundleIdentifier: "org.telegram.desktop",
                   remoteText: "149.154.167.51", remotePort: 443,
                   startedAt: 1_752_800_000),
            opened(executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                   bundleIdentifier: "org.telegram.desktop",
                   remoteText: "149.154.167.52", remotePort: 443,
                   startedAt: 1_752_820_000),
            opened(executablePath: "/usr/sbin/mDNSResponder",
                   bundleIdentifier: nil,
                   remoteText: "8.8.8.8", remotePort: 53,
                   startedAt: 1_752_810_000),
        ])
        let groups = try HistoryQuery.grouped(database: db, text: "")
        #expect(groups.count == 2)
        let telegram = try #require(groups.first { $0.title == "Telegram" })
        #expect(telegram.flows.count == 2)
        #expect(telegram.totalBytesReceived == 400)
        #expect(telegram.totalBytesSent == 200)
        // newest first within the group
        #expect(telegram.flows[0].startedAt == Date(timeIntervalSince1970: 1_752_820_000))
    }

    @Test func groupsSortedByTotalBytesDescending() throws {
        let db = try db(with: [
            opened(executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                   bundleIdentifier: "org.telegram.desktop",
                   remoteText: "149.154.167.51", remotePort: 443,
                   startedAt: 1_752_800_000),   // 300 bytes total
            opened(executablePath: "/usr/sbin/mDNSResponder",
                   bundleIdentifier: nil,
                   remoteText: "8.8.8.8", remotePort: 53,
                   startedAt: 1_752_810_000),   // 300 bytes total
            opened(executablePath: "/usr/sbin/mDNSResponder",
                   bundleIdentifier: nil,
                   remoteText: "8.8.4.4", remotePort: 53,
                   startedAt: 1_752_820_000),   // +300 → 600 total
        ])
        let groups = try HistoryQuery.grouped(database: db, text: "")
        #expect(groups.count == 2)
        #expect(groups[0].title == "mDNSResponder")   // 600 > 300
        #expect(groups[1].title == "Telegram")
    }

    @Test func groupingRespectsSearchFilter() throws {
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
        let groups = try HistoryQuery.grouped(database: db, text: "telegram")
        #expect(groups.count == 1)
        #expect(groups[0].title == "Telegram")
    }

    @MainActor
    @Test func appIconFindsNearestBundle() {
        #expect(AppIcon.bundlePath(forExecutable: "/Applications/Telegram.app/Contents/MacOS/Telegram")
            == "/Applications/Telegram.app")
        #expect(AppIcon.bundlePath(forExecutable: "/System/Library/CoreServices/Activity Monitor.app/Contents/MacOS/Activity Monitor")
            == "/System/Library/CoreServices/Activity Monitor.app")
        #expect(AppIcon.bundlePath(forExecutable: "/usr/sbin/mDNSResponder") == nil)
        #expect(AppIcon.bundlePath(forExecutable: "/") == nil)
    }

    @Test func groupsFlowsByDomain() throws {
        let telegramEvent = try opened(
            executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
            bundleIdentifier: "org.telegram.desktop",
            remoteText: "149.154.167.51", remotePort: 443,
            startedAt: 1_752_800_000)
        let dnsEvent = try opened(
            executablePath: "/usr/sbin/mDNSResponder",
            bundleIdentifier: nil,
            remoteText: "8.8.8.8", remotePort: 53,
            startedAt: 1_752_810_000)
        let domain = DomainCandidate(domain: "edge.mtproto.telegram.example",
                                     confidence: DomainCandidate.forwardConfirmedConfidence,
                                     source: .forwardConfirmedPTR)
        let db = try db(with: [telegramEvent, dnsEvent], domains: [flowID(telegramEvent): domain])

        let groups = try HistoryQuery.groupedByDomain(database: db, text: "")
        #expect(groups.count == 2)
        let telegram = try #require(groups.first { $0.title == "edge.mtproto.telegram.example" })
        #expect(telegram.flows.count == 1)
        #expect(telegram.totalBytesReceived == 200)
        let unresolved = try #require(groups.first { $0.title == "mDNSResponder" })
        if case .domain(let name) = unresolved.kind {
            #expect(name == "/usr/sbin/mDNSResponder")   // fell back to app path
        } else {
            Issue.record("unresolved flow should fall back to app-path group")
        }
    }

    @Test func domainPersistedThroughIngest() throws {
        let event = try opened(
            executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
            bundleIdentifier: "org.telegram.desktop",
            remoteText: "149.154.167.51", remotePort: 443,
            startedAt: 1_752_800_000)
        let candidate = DomainCandidate(domain: "telegram.example",
                                        confidence: 0.6, source: .forwardConfirmedPTR)
        let db = try db(with: [event], domains: [flowID(event): candidate])
        let flows = try db.flows()
        let stored = try #require(flows.first)
        #expect(stored.domain == "telegram.example")
        #expect(stored.domainConfidence == 0.6)
    }

    @Test func migrationAddsDomainColumnsToOldDatabase() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("old.sqlite")

        // create a database with the pre-M3 schema, then open it through
        // FlowDatabase, which must migrate it in place
        let oldSchema = """
        CREATE TABLE processes (
            id                INTEGER PRIMARY KEY,
            executable_path   TEXT NOT NULL,
            bundle_identifier TEXT NOT NULL DEFAULT '',
            UNIQUE (executable_path, bundle_identifier)
        );
        CREATE TABLE flows (
            id              TEXT PRIMARY KEY,
            process_id      INTEGER NOT NULL REFERENCES processes(id),
            transport       TEXT NOT NULL,
            local_address   BLOB NOT NULL,
            local_port      INTEGER NOT NULL,
            remote_address  BLOB NOT NULL,
            remote_port     INTEGER NOT NULL,
            started_at      REAL NOT NULL,
            ended_at        REAL,
            bytes_sent      INTEGER NOT NULL DEFAULT 0,
            bytes_received  INTEGER NOT NULL DEFAULT 0
        );
        """
        let raw = try Database(path: url.path)
        try raw.exec(oldSchema)
        raw.close()

        let db = try FlowDatabase(path: url.path)
        let event = try opened(
            executablePath: "/usr/sbin/mDNSResponder",
            bundleIdentifier: nil,
            remoteText: "8.8.8.8", remotePort: 53,
            startedAt: 1_752_800_000)
        let candidate = DomainCandidate(domain: "dns.google", confidence: 0.6,
                                        source: .forwardConfirmedPTR)
        try db.ingest([event], domains: [flowID(event): candidate])
        let stored = try #require(try db.flows().first)
        #expect(stored.domain == "dns.google")
        db.close()
    }
}
