import Foundation
import Testing
@testable import NetglassMac

@Suite struct ProcessTrustTests {
    @Test func sha256MatchesKnownDigest() {
        let digest = ProcessTrustInspector.sha256(of: Data("abc".utf8))
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func pathClassification() {
        #expect(ProcessTrustInspector.isTemporary(NSTemporaryDirectory() + "x"))
        #expect(ProcessTrustInspector.isTemporary("/tmp/x"))
        #expect(!ProcessTrustInspector.isTemporary("/Applications/X.app"))
        #expect(ProcessTrustInspector.isDiskImage("/Volumes/Disk/app"))
        #expect(!ProcessTrustInspector.isDiskImage("/usr/bin/ls"))
        #expect(ProcessTrustInspector.isSystemBinary("/usr/bin/ls"))
        #expect(ProcessTrustInspector.isSystemBinary("/System/Library/Foo"))
        #expect(!ProcessTrustInspector.isSystemBinary("/Applications/X.app"))
    }

    @Test func systemBinaryIsSignedByApple() throws {
        // macOS 26 (Tahoe) moved /usr/bin tools to /bin; pick whichever exists.
        let candidate = FileManager.default.fileExists(atPath: "/usr/bin/ls") ? "/usr/bin/ls" : "/bin/ls"
        let trust = ProcessTrustInspector.inspect(path: candidate)
        #expect(trust.signed)
        #expect(trust.authority?.contains("Apple") == true || trust.teamID != nil)
    }

    @Test func unsignedTempFileReportsUnsigned() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-trust-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let trust = ProcessTrustInspector.inspect(path: url.path)
        #expect(!trust.signed)
        #expect(trust.sha256 == ProcessTrustInspector.sha256(of: Data("hello".utf8)))
    }
}
