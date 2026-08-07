import Foundation
import FlowSource
import Persistence

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var database: FlowDatabase?
    @Published public private(set) var bootstrapError: String?
    @Published public var currentTab: MainTab = .monitor
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
        let interval = UserDefaults.standard.double(forKey: "updateFrequency")
        self.liveModel = LiveConnectionsModel(
            sampler: Self.defaultSampler(), database: db,
            interval: interval > 0 ? interval : 0.25)
    }

    public static nonisolated func databaseURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Netglass").appendingPathComponent("history.sqlite")
    }

    /// The app's sampling pipeline: real nettop/lsof subprocesses plus a
    /// process resolver walking proc_pidpath.
    public static nonisolated func defaultSampler() -> Sampler {
        // long-lived nettop stream: one subprocess, no per-tick spawn
        Sampler(nettopClient: StreamingNettopClient(interval: 0.25),
                lsofClient: ProcessLsofClient(),
                resolver: ProcessResolver())
    }
}

/// Sidebar tabs of the main window.
public enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case monitor
    case history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monitor: "Monitor"
        case .history: "History"
        }
    }

    public var symbol: String {
        switch self {
        case .monitor: "waveform.path.ecg"
        case .history: "clock.arrow.circlepath"
        }
    }
}
