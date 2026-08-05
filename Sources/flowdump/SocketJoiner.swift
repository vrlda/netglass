import Foundation
import FlowModel

/// Joins nettop connection rows (endpoints + bytes, no process) with lsof sockets
/// (process + pid, no bytes) on (protocol group, local, remote). QUIC rows join
/// the UDP group (QUIC runs over UDP) but keep their `.quic` transport.
public struct SocketJoiner: Sendable {
    public init() {}

    public func join(connections: [NettopConnection], sockets: [LsofSocket]) -> [NettopRow] {
        var index: [JoinKey: [LsofSocket]] = [:]
        for socket in sockets {
            index[JoinKey(group: socket.transport, local: socket.local, remote: socket.remote), default: []].append(socket)
        }
        var rows: [NettopRow] = []
        for connection in connections {
            let group: TransportProtocol = connection.transport == .quic ? .udp : connection.transport
            guard let matches = index[JoinKey(group: group, local: connection.local, remote: connection.remote)],
                  let socket = matches.first else { continue }
            // matches.first attribution is arbitrary when multiple processes hold the same
            // UDP tuple (kernel discovery order), accepted for M1.
            rows.append(NettopRow(
                processName: socket.processName,
                pid: socket.pid,
                connID: nil,
                state: connection.state,
                interface: connection.interface,
                bytesIn: connection.bytesIn,
                bytesOut: connection.bytesOut,
                local: connection.local,
                remote: connection.remote,
                transport: connection.transport))
        }
        return rows
    }

    private struct JoinKey: Hashable {
        let group: TransportProtocol
        let local: NetworkEndpoint
        let remote: NetworkEndpoint
    }
}
