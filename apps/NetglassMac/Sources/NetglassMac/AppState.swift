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
        // Sampling cadence, clamped to >= 1 s: one-shot nettop at `-L 1`
        // snapshots fresh data per tick; sub-second ticks only burn CPU
        // Migrate any stored sub-second value once.
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: "updateFrequency")
        let interval = max(1.0, stored > 0 ? stored : 1.0)
        if stored > 0, stored < 1.0 {
            defaults.set(1.0, forKey: "updateFrequency")
        }
        self.liveModel = LiveConnectionsModel(
            sampler: Self.defaultSampler(), database: db,
            interval: interval)
    }

    public static nonisolated func databaseURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Netglass").appendingPathComponent("history.sqlite")
    }

    /// The app's sampling pipeline: real nettop/lsof subprocesses plus a
    /// process resolver walking proc_pidpath.
    public static nonisolated func defaultSampler() -> Sampler {
        // One-shot nettop per tick: on a pipe, `nettop -L 1` writes a single
        // snapshot and exits (~170 ms), so each tick gets fresh counters at
        // ~1/6 of the streaming client's CPU cost (nettop burns ~136% CPU
        // with sub-second `-L` intervals).
        Sampler(nettopClient: ProcessNettopClient(),
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
