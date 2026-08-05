import Foundation
import FlowModel

/// One observation tick: nettop + lsof samples → join → lifecycle diff → events.
/// Owns a FlowSessionTracker (stateful across ticks). Not thread-safe; call from
/// one loop at a time.
public final class Sampler {
    public let nettopClient: NettopClient
    public let lsofClient: LsofClient
    public let resolver: ProcessIdentityProviding

    private var tracker: FlowSessionTracker

    public init(nettopClient: NettopClient, lsofClient: LsofClient,
                resolver: ProcessIdentityProviding) {
        self.nettopClient = nettopClient
        self.lsofClient = lsofClient
        self.resolver = resolver
        self.tracker = FlowSessionTracker()
    }

    public func sample() throws -> [FlowEvent] {
        let nettopText = try nettopClient.sample()
        let lsofText = try lsofClient.sample()
        let connections = NettopParser().parse(nettopText)
        let sockets = LsofParser().parse(lsofText)
        let rows = SocketJoiner().join(connections: connections, sockets: sockets)
        return tracker.ingest(rows, identityForPID: { resolver.identity(for: $0) })
    }
}
