import Foundation
import Testing
@testable import NetglassMac

@Suite struct AppStateTests {
    @Test func resolvesHistoryDatabasePath() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("netglass-appstate-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let url = AppState.databaseURL(in: dir)
        #expect(url.lastPathComponent == "history.sqlite")
        #expect(url.deletingLastPathComponent().path == dir.appendingPathComponent("Netglass").path)
    }
}
