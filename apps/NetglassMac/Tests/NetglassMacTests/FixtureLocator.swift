import Foundation

/// Walks up from this test file until it finds the repo root (a directory
/// containing `Fixtures/`). Duplicated in NetglassMacTests so test targets stay
/// decoupled (FlowSourceTests has its own copy).
enum FixtureLocator {
    static func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            var isDir: ObjCBool = false
            let candidate = url.appendingPathComponent("Fixtures")
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        throw FixtureLocatorError.notFound
    }

    enum FixtureLocatorError: Error { case notFound }
}
