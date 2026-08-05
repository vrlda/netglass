import Foundation
import Testing
@testable import flowdump
@testable import FlowModel
@testable import FlowSource
@testable import Persistence

@Suite struct CLITests {
    @Test func defaultConfig() throws {
        let config = try parseArguments([])
        #expect(config.duration == nil)
        #expect(config.interval == 2.0)
        #expect(config.dbPath == nil)
        #expect(config.processFilter == nil)
    }

    @Test func parsesAllFlags() throws {
        let config = try parseArguments([
            "--duration", "10", "--interval", "1", "--db", "/tmp/x.sqlite", "--process", "Telegram",
        ])
        #expect(config.duration == 10)
        #expect(config.interval == 1)
        #expect(config.dbPath == "/tmp/x.sqlite")
        #expect(config.processFilter == "Telegram")
    }

    @Test func unknownFlagThrows() {
        #expect(throws: ArgumentError.self) {
            try parseArguments(["--bogus"])
        }
    }

    @Test func missingValueThrows() {
        #expect(throws: ArgumentError.self) {
            try parseArguments(["--duration"])
        }
    }

    @Test func invalidNumberThrows() {
        #expect(throws: ArgumentError.self) {
            try parseArguments(["--duration", "abc"])
        }
    }

    @Test func zeroIntervalThrows() {
        #expect(throws: ArgumentError.self) {
            try parseArguments(["--interval", "0"])
        }
    }

    @Test func nonPositiveDurationThrows() {
        #expect(throws: ArgumentError.self) {
            try parseArguments(["--duration", "-5"])
        }
    }

    @Test func runLoopEmitsAndPersists() throws {
        let base = try FixtureLocator.repoRoot()
        let nettopFixture = base.appendingPathComponent("Fixtures/nettop/synthetic.txt")
        let lsofFixture = base.appendingPathComponent("Fixtures/lsof/synthetic.txt")
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-run-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let db = try FlowDatabase(path: dbPath)
        defer { db.close() }

        var emitted: [FlowEvent] = []
        let config = CLIConfig(duration: 0.5, interval: 0.1, dbPath: nil, processFilter: nil)
        try run(config: config,
                nettopClient: FileNettopClient(url: nettopFixture),
                lsofClient: FileLsofClient(url: lsofFixture),
                db: db,
                identityForPID: { pid in
                    pid == 9217 ? ProcessIdentity(
                        pid: pid, startTime: nil,
                        executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                        bundleIdentifier: "ru.keepcoder.Telegram", parentPID: nil) : nil
                }) { event in
            emitted.append(event)
        }

        #expect(emitted.contains { event in
            if case .flowOpened(let opened) = event {
                return opened.pid == 9217
                    && opened.remote.address.text == "149.154.167.51"
            }
            return false
        })
        #expect(try db.flows().count >= 1)
        #expect(try db.flows().first?.processPath.contains("Telegram") == true)
    }
}
