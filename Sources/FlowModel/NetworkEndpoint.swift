import Foundation

public enum TransportProtocol: String, Codable, Sendable, Hashable {
    case tcp, udp, icmp, quic, other
}

public struct NetworkEndpoint: Codable, Hashable, Sendable {
    public let address: IPAddress
    public let port: UInt16

    public init(address: IPAddress, port: UInt16) {
        self.address = address
        self.port = port
    }
}
