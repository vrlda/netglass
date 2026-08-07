import Foundation
import SwiftUI

/// Sections of the main window's primary navigation.
public enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case liveConnections
    case applications
    case domains
    case dnsActivity
    case captures
    case packetInspector
    case history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .liveConnections: "Live Connections"
        case .applications: "Applications"
        case .domains: "Domains"
        case .dnsActivity: "DNS Activity"
        case .captures: "Captures"
        case .packetInspector: "Packet Inspector"
        case .history: "History"
        }
    }

    public var symbol: String {
        switch self {
        case .overview: "waveform.path.ecg"
        case .liveConnections: "point.3.connected.trianglepath.dotted"
        case .applications: "app"
        case .domains: "globe"
        case .dnsActivity: "magnifyingglass.circle"
        case .captures: "record.circle"
        case .packetInspector: "rectangle.3.group"
        case .history: "clock.arrow.circlepath"
        }
    }

    public var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .liveConnections: "2"
        case .applications: "3"
        case .domains: "4"
        case .dnsActivity: "5"
        case .captures: "6"
        case .packetInspector: "7"
        case .history: "8"
        }
    }
}

/// Time ranges for the traffic timeline.
public enum TimeRange: String, CaseIterable, Identifiable, Hashable {
    case live, fiveMinutes, hour, day

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .live: "Live"
        case .fiveMinutes: "5 min"
        case .hour: "1 hour"
        case .day: "24 hours"
        }
    }
}

/// App-wide UI state. View preferences persist in UserDefaults.
@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var selectedSection: AppSection {
        didSet { defaults.set(selectedSection.rawValue, forKey: Keys.section) }
    }
    @Published public var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: Keys.sidebar) }
    }
    @Published public var inspectorVisible: Bool {
        didSet { defaults.set(inspectorVisible, forKey: Keys.inspector) }
    }
    @Published public var timeRange: TimeRange {
        didSet { defaults.set(timeRange.rawValue, forKey: Keys.timeRange) }
    }
    @Published public var compactDensity: Bool {
        didSet { defaults.set(compactDensity, forKey: Keys.density) }
    }
    @Published public var searchText = ""
    /// Live Connections columns the user enabled (persisted).
    @Published public var enabledColumns: Set<String> {
        didSet { defaults.set(Array(enabledColumns), forKey: Keys.columns) }
    }

    public static let availableColumns = ["Application", "Remote", "Local", "Protocol",
                                          "Direction", "Sent", "Received", "State", "PID"]
    /// Capture file to load in the Packet Inspector (set by the Captures
    /// screen, observed by the inspector).
    @Published public var openCaptureURL: URL? {
        didSet { defaults.set(openCaptureURL?.path, forKey: Keys.lastCapture) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedSection = AppSection(rawValue: defaults.string(forKey: Keys.section) ?? "")
            ?? .overview
        self.sidebarVisible = defaults.object(forKey: Keys.sidebar) == nil
            ? true : defaults.bool(forKey: Keys.sidebar)
        self.inspectorVisible = defaults.object(forKey: Keys.inspector) == nil
            ? true : defaults.bool(forKey: Keys.inspector)
        self.timeRange = TimeRange(rawValue: defaults.string(forKey: Keys.timeRange) ?? "")
            ?? .fiveMinutes
        self.compactDensity = defaults.bool(forKey: Keys.density)
        let saved = defaults.stringArray(forKey: Keys.columns) ?? []
        self.enabledColumns = saved.isEmpty ? Set(Self.availableColumns) : Set(saved)
    }

    public var rowPadding: CGFloat { compactDensity ? 2 : 5 }

    private enum Keys {
        static let section = "netglass.ui.section"
        static let sidebar = "netglass.ui.sidebar"
        static let inspector = "netglass.ui.inspector"
        static let timeRange = "netglass.ui.timeRange"
        static let density = "netglass.ui.density"
        static let lastCapture = "netglass.ui.lastCapture"
        static let columns = "netglass.ui.columns"
    }
}

/// Monitoring pause/resume + live status.
@MainActor
public final class MonitoringViewModel: ObservableObject {
    @Published public private(set) var isPaused = false

    public func toggle() { isPaused.toggle() }
    public func pause() { isPaused = true }
    public func resume() { isPaused = false }
}
