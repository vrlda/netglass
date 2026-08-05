import Foundation
import Testing
@testable import FlowModel
@testable import NetglassMac
@testable import Persistence

@Suite struct ExporterTests {
    private func sampleFlow() throws -> StoredFlow {
        StoredFlow(
            flowID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            processPath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
            bundleIdentifier: "org.telegram.desktop",
            transport: .tcp,
            localAddress: try #require(IPAddress(text: "192.168.1.42")),
            localPort: 51234,
            remoteAddress: try #require(IPAddress(text: "149.154.167.51")),
            remotePort: 443,
            startedAt: Date(timeIntervalSince1970: 1_752_800_000),
            endedAt: nil,
            bytesSent: 3400, bytesReceived: 1200)
    }

    @Test func exportsJSON() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.exportJSON([try sampleFlow()], to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"processPath\""))
        #expect(text.contains("149.154.167.51"))
        let data = try Data(contentsOf: url)
        let decoded = try FlowJSON.decoder.decode([StoredFlow].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].flowID == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    }

    @Test func exportsCSV() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-export-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.exportCSV([try sampleFlow()], to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)                       // header + 1 row
        #expect(lines[0].contains("flow_id,process_path"))
        #expect(lines[1].contains("Telegram.app"))
        #expect(lines[1].contains("149.154.167.51"))
        #expect(lines[1].contains("443"))
    }
}
