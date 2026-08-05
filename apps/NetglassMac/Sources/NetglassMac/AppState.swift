import Foundation
import FlowSource
import Persistence

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var database: FlowDatabase?
    public let databaseURL: URL

    public init(databaseDirectory: URL) {
        self.databaseURL = Self.databaseURL(in: databaseDirectory)
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.database = try? FlowDatabase(path: databaseURL.path)
    }

    public static nonisolated func databaseURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Netglass").appendingPathComponent("history.sqlite")
    }

    /// The app's sampling pipeline: real nettop/lsof subprocesses plus a
    /// process resolver walking proc_pidpath.
    public static nonisolated func defaultSampler() -> Sampler {
        Sampler(nettopClient: ProcessNettopClient(),
                lsofClient: ProcessLsofClient(),
                resolver: ProcessResolver())
    }
}
