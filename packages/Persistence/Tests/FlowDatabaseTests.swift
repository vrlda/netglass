import Foundation
import Testing
@testable import FlowModel
@testable import Persistence

@Suite struct FlowDatabaseTests {
    private func opened(remotePort: UInt16 = 443, remote: NetworkEndpoint? = nil) throws -> FlowEvent.FlowOpened {
        let remoteEndpoint: NetworkEndpoint
        if let remote {
            remoteEndpoint = remote
        } else {
            remoteEndpoint = try Self.defaultRemote(port: remotePort)
        }
        return FlowEvent.FlowOpened(
            flowID: UUID(),
            process: ProcessIdentity(pid: 9217, startTime: nil,
                                     executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                                     bundleIdentifier: "org.telegram.desktop",
                                     parentPID: nil),
            pid: 9217,
            transport: .tcp,
            local: NetworkEndpoint(address: try #require(IPAddress(text: "192.168.1.42")), port: 51234),
            remote: remoteEndpoint,
            startedAt: Date(timeIntervalSince1970: 1_752_800_000),
            bytesSent: 3400,
            bytesReceived: 1200)
    }

    private static func defaultRemote(port: UInt16) throws -> NetworkEndpoint {
        NetworkEndpoint(address: try #require(IPAddress(text: "149.154.167.51")), port: port)
    }

    @Test func openedFlowIsStored() throws {
        let db = try FlowDatabase(path: ":memory:")
        try db.ingest([.flowOpened(try opened())])
        let flows = try db.flows()
        #expect(flows.count == 1)
        let flow = try #require(flows.first)
        #expect(flow.processPath == "/Applications/Telegram.app/Contents/MacOS/Telegram")
        #expect(flow.bundleIdentifier == "org.telegram.desktop")
        #expect(flow.remoteAddress.text == "149.154.167.51")
        #expect(flow.remotePort == 443)
        #expect(flow.bytesSent == 3400)
        #expect(flow.bytesReceived == 1200)
        #expect(flow.endedAt == nil)
    }

    @Test func updatedCountersPersist() throws {
        let db = try FlowDatabase(path: ":memory:")
        let opened = try opened()
        let id = opened.flowID
        try db.ingest([.flowOpened(opened)])
        try db.ingest([.flowUpdated(.init(flowID: id, bytesSent: 5000, bytesReceived: 2000,
                                          observedAt: Date(timeIntervalSince1970: 1_752_800_010)))])
        let flows = try db.flows()
        #expect(flows[0].bytesSent == 5000)
        #expect(flows[0].bytesReceived == 2000)
    }

    @Test func closedFlowGetsEndDateAndIgnoresLaterUpdates() throws {
        let db = try FlowDatabase(path: ":memory:")
        let opened = try opened()
        let id = opened.flowID
        try db.ingest([.flowOpened(opened)])
        try db.ingest([.flowClosed(.init(flowID: id, endedAt: Date(timeIntervalSince1970: 1_752_800_020)))])
        try db.ingest([.flowUpdated(.init(flowID: id, bytesSent: 9999, bytesReceived: 1,
                                          observedAt: Date(timeIntervalSince1970: 1_752_800_030)))])
        let flows = try db.flows()
        #expect(flows[0].endedAt == Date(timeIntervalSince1970: 1_752_800_020))
        #expect(flows[0].bytesSent == 3400)   // update after close ignored
    }

    @Test func processRowsAreDeduplicated() throws {
        let db = try FlowDatabase(path: ":memory:")
        let first = try opened()
        let second = try opened()
        try db.ingest([.flowOpened(first), .flowOpened(second)])
        #expect(try db.processCount() == 1)
    }

    @Test func queryByRemoteAddressAndPort() throws {
        let db = try FlowDatabase(path: ":memory:")
        let to443 = try opened(remotePort: 443)
        let to53 = try opened(remotePort: 53)
        try db.ingest([.flowOpened(to443), .flowOpened(to53)])

        let byAddress = try db.flows(remoteAddress: IPAddress(text: "149.154.167.51")!)
        #expect(byAddress.count == 2)

        let byPort = try db.flows(remotePort: 53)
        #expect(byPort.count == 1)
        #expect(byPort[0].remotePort == 53)
    }

    @Test func ipv6BlobRoundTrip() throws {
        let db = try FlowDatabase(path: ":memory:")
        let opened = try opened(remote: NetworkEndpoint(
            address: try #require(IPAddress(text: "2001:db8::1")), port: 443))
        try db.ingest([.flowOpened(opened)])
        let flows = try db.flows()
        #expect(flows[0].remoteAddress.text == "2001:db8::1")
    }

    @Test func historySurvivesReopen() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-db-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        var db = try FlowDatabase(path: path)
        try db.ingest([.flowOpened(try opened())])
        db.close()

        db = try FlowDatabase(path: path)
        #expect(try db.flows().count == 1)
        db.close()
    }

    @Test func ingestAfterCloseThrows() throws {
        let db = try FlowDatabase(path: ":memory:")
        db.close()
        #expect(throws: (any Error).self) {
            try db.ingest([.flowOpened(try opened())])
        }
    }
}

@Suite struct DatabaseTests {
    @Test func multiStatementExecWithMismatchedBindingsThrows() throws {
        let db = try Database(path: ":memory:")
        defer { db.close() }
        #expect(throws: DatabaseError.self) {
            try db.exec("SELECT ?; SELECT 1;", [.text("x")])
        }
    }

    @Test func multiStatementExecWithNoBindingsExecutesAll() throws {
        let db = try Database(path: ":memory:")
        defer { db.close() }
        try db.exec("CREATE TABLE a (x INTEGER); CREATE TABLE b (y INTEGER);")
        let statement = try db.prepare(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('a', 'b')")
        var names: [String] = []
        while try statement.step() {
            names.append(statement.text(0))
        }
        #expect(names.count == 2)
    }
}
