import Foundation
import Combine
import FlowModel
import FlowSource

/// Drives one operation session: lifecycle, event ingestion, leak rules,
/// listener/resolver polling, cleanup report, and JSON export.
@MainActor
public final class OperationViewModel: ObservableObject {
    @Published public private(set) var session: OperationSession?
    @Published public private(set) var warnings: [LeakWarning] = []
    @Published public private(set) var listeners: [ListeningPort] = []
    @Published public private(set) var currentResolvers: [ResolverConfig] = []
    @Published public private(set) var periodic: [PeriodicPattern] = []

    private let engine = LeakRuleEngine()
    private var beaconDetector = BeaconDetector()
    private let snapshotProvider: () -> OperationSnapshot
    private var listenerTimer: Timer?
    private var resolverTimer: Timer?
    private var lastListeners: [LsofListener] = []

    public init(snapshotProvider: @escaping () -> OperationSnapshot = SnapshotService.capture) {
        self.snapshotProvider = snapshotProvider
    }

    public var isRunning: Bool {
        guard let session else { return false }
        return session.endedAt == nil
    }

    public func start(name: String, expectedTunnel: String, scope: OperationScope) {
        guard session == nil else { return }
        let snapshot = snapshotProvider()
        session = OperationSession(name: name, expectedTunnel: expectedTunnel,
                                   scope: scope, snapshotIn: snapshot)
        warnings = []
        listeners = []
        lastListeners = snapshot.listeners
        currentResolvers = snapshot.resolvers
        armTimers()
    }

    public func ingest(_ batch: [OperationEvent]) {
        guard var session else { return }
        session.events.append(contentsOf: batch)
        let beacons = batch.compactMap { event -> BeaconObservation? in
            guard case .connection(true, let date, let process, _, let remote, _, _, let bytes) = event
            else { return nil }
            return BeaconObservation(process: process,
                                     destination: "\(remote.address.text):\(remote.port)",
                                     date: date, bytes: bytes)
        }
        if !beacons.isEmpty {
            let newPatterns = beaconDetector.ingest(beacons)
            if !newPatterns.isEmpty {
                session.periodic.append(contentsOf: newPatterns)
                periodic = session.periodic
            }
        }
        let newWarnings = engine.evaluate(batch: batch, session: session,
                                          currentResolvers: currentResolvers, now: Date())
        if !newWarnings.isEmpty {
            session.warnings.append(contentsOf: newWarnings)
            warnings = session.warnings
        }
        self.session = session
    }

    public func stop(liveFlows: [LiveFlow]) {
        guard var session, session.endedAt == nil else { return }
        let snapshotOut = snapshotProvider()
        session.endedAt = snapshotOut.date
        session.snapshotOut = snapshotOut
        session.cleanupReport = CleanupReport(snapshotIn: session.snapshotIn, snapshotOut: snapshotOut,
                                              liveFlows: liveFlows, endedAt: snapshotOut.date)
        self.session = session
        tearDownTimers()
    }

    public func discard() {
        tearDownTimers()
        session = nil
        warnings = []
        listeners = []
    }

    public func export(to url: URL) throws {
        guard let session else { throw OperationExportError.noActiveSession }
        let bundle = OperationBundle(operation: session,
                                     warnings: session.warnings,
                                     events: session.events,
                                     snapshotIn: session.snapshotIn,
                                     snapshotOut: session.snapshotOut,
                                     cleanupReport: session.cleanupReport)
        let data = try FlowJSON.encoder.encode(bundle)
        try data.write(to: url, options: .atomic)
    }

    public enum OperationExportError: Error, Equatable {
        case noActiveSession
    }

    private func armTimers() {
        listenerTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollListeners() }
        }
        resolverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollResolvers() }
        }
    }

    private func tearDownTimers() {
        listenerTimer?.invalidate()
        listenerTimer = nil
        resolverTimer?.invalidate()
        resolverTimer = nil
    }

    private func pollListeners() {
        pollListeners(snapshot: snapshotProvider())
    }

    /// Test hook: runs the listener-poll body against a given snapshot.
    internal func pollListenersForTesting(snapshot: OperationSnapshot) {
        pollListeners(snapshot: snapshot)
    }

    private func pollListeners(snapshot: OperationSnapshot) {
        guard var session else { return }
        let current = snapshot.listeners
        let oldKeys = Set(lastListeners.map(Self.listenerKey))
        let newKeys = Set(current.map(Self.listenerKey))
        var events: [OperationEvent] = []
        for listener in current where !oldKeys.contains(Self.listenerKey(listener)) {
            events.append(.listener(ListeningPort(
                process: listener.processName, pid: listener.pid,
                address: listener.address, port: listener.port,
                proto: listener.transport.rawValue, exposure: exposureText(listener),
                action: .opened)))
        }
        for listener in lastListeners where !newKeys.contains(Self.listenerKey(listener)) {
            events.append(.listener(ListeningPort(
                process: listener.processName, pid: listener.pid,
                address: listener.address, port: listener.port,
                proto: listener.transport.rawValue, exposure: exposureText(listener),
                action: .closed)))
        }
        lastListeners = current
        if events.isEmpty && current.map(Self.listenerKey) == oldKeys.sorted() {
            return   // nothing changed: don't re-publish
        }
        listeners = current.map {
            ListeningPort(process: $0.processName, pid: $0.pid, address: $0.address,
                          port: $0.port, proto: $0.transport.rawValue, exposure: exposureText($0),
                          action: .opened)
        }
        if !events.isEmpty {
            session.events.append(contentsOf: events)
            let newWarnings = engine.evaluate(batch: events, session: session,
                                              currentResolvers: currentResolvers, now: Date())
            session.warnings.append(contentsOf: newWarnings)
            warnings = session.warnings
        }
        self.session = session
    }

    private func pollResolvers() {
        let resolvers = snapshotProvider().resolvers
        guard resolvers != currentResolvers else { return }
        currentResolvers = resolvers
        guard var session else { return }
        let newWarnings = engine.evaluate(batch: [], session: session,
                                          currentResolvers: resolvers, now: Date())
        session.warnings.append(contentsOf: newWarnings)
        warnings = session.warnings
        self.session = session
    }

    private static func listenerKey(_ listener: LsofListener) -> String {
        "\(listener.pid)-\(listener.transport.rawValue)-\(listener.address):\(listener.port)"
    }

    private func exposureText(_ listener: LsofListener) -> String {
        switch listener.exposure {
        case .loopback: return "loopback"
        case .allInterfaces: return "allInterfaces"
        case .specific: return "specific"
        }
    }
}
