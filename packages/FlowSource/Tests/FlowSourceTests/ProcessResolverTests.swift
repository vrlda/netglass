import Foundation
import Testing
@testable import FlowSource

@Suite struct ProcessResolverTests {
    private let resolver = ProcessResolver()

    @Test func resolvesLaunchD() throws {
        let identity = try #require(resolver.identity(for: 1))
        #expect(identity.executablePath == "/sbin/launchd")
    }

    @Test func resolvesCurrentProcess() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let identity = try #require(resolver.identity(for: pid))
        #expect(!identity.executablePath.isEmpty)
        #expect(identity.pid == pid)
    }

    @Test func missingProcessReturnsNil() {
        #expect(resolver.identity(for: 999_999) == nil)
    }

    @Test func invalidPidReturnsNil() {
        #expect(resolver.identity(for: 0) == nil)
        #expect(resolver.identity(for: -1) == nil)
    }

    @Test func bundleIdentifierFoundInFakeAppBundle() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-test-\(UUID().uuidString)")
        let appDir = dir.appendingPathComponent("FakeApp.app")
        try FileManager.default.createDirectory(
            at: appDir.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fakeapp"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml, options: 0)
        try data.write(to: appDir.appendingPathComponent("Contents/Info.plist"))
        defer { try? FileManager.default.removeItem(at: dir) }

        let path = appDir.appendingPathComponent("Contents/MacOS/FakeApp").path
        let bundleID = resolver.bundleIdentifier(forExecutable: path)
        #expect(bundleID == "com.example.fakeapp")
    }

    @Test func noBundleIdentifierForPlainExecutable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("binary").path
        #expect(resolver.bundleIdentifier(forExecutable: path) == nil)
    }

    @Test func resolvesParentPID() {
        let pid = Int32(getpid())
        let parent = ProcessResolver().parentPID(for: pid)
        #expect(parent != nil)
        #expect(parent! > 0)
        #expect(parent! != pid)
    }

    @Test func ancestryReachesRootOrCap() {
        let chain = ProcessAncestry.chain(for: Int32(getpid()))
        #expect(!chain.isEmpty)
        #expect(chain.count <= ProcessAncestry.maxDepth)
        #expect(chain.first?.pid == 1 || chain.count == ProcessAncestry.maxDepth)
        // each link is the parent of the next
        for i in 0..<(chain.count - 1) {
            #expect(chain[i].pid == chain[i + 1].parentPID)
        }
    }
}
