import Foundation
import FlowSource
import Persistence

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var database: FlowDatabase?
    @Published public private(set) var bootstrapError: String?
    public let databaseURL: URL
    public let liveModel: LiveConnectionsModel

    public init(databaseDirectory: URL) {
        self.databaseURL = Self.databaseURL(in: databaseDirectory)
        let db: FlowDatabase?
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try FlowDatabase(path: databaseURL.path)
        } catch {
            self.bootstrapError = error.localizedDescription
            db = nil
        }
        self.database = db
        // A fresh observation session re-opens still-alive flows with new IDs;
        // close the previous session's dangling rows so history doesn't show
        // the same physical connection twice as "open".
        if let db {
            try? db.closeOrphanedFlows(endedAt: Date())
        }
        self.liveModel = LiveConnectionsModel(sampler: Self.defaultSampler(), database: db)
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
