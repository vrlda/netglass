import Foundation

public enum FlowEvent: Codable, Sendable, Equatable {
    public struct FlowOpened: Codable, Sendable, Equatable {
        public let flowID: UUID
        public let process: ProcessIdentity?   // resolved at observation time
        public let pid: Int32
        public let transport: TransportProtocol
        public let local: NetworkEndpoint
        public let remote: NetworkEndpoint
        public let interface: String
        public let startedAt: Date
        public let bytesSent: UInt64
        public let bytesReceived: UInt64

        public init(flowID: UUID, process: ProcessIdentity?, pid: Int32,
                    transport: TransportProtocol, local: NetworkEndpoint,
                    remote: NetworkEndpoint, interface: String, startedAt: Date,
                    bytesSent: UInt64, bytesReceived: UInt64) {
            self.flowID = flowID
            self.process = process
            self.pid = pid
            self.transport = transport
            self.local = local
            self.remote = remote
            self.interface = interface
            self.startedAt = startedAt
            self.bytesSent = bytesSent
            self.bytesReceived = bytesReceived
        }
    }

    public struct FlowCounters: Codable, Sendable, Equatable {
        public let flowID: UUID
        public let bytesSent: UInt64
        public let bytesReceived: UInt64
        public let observedAt: Date

        public init(flowID: UUID, bytesSent: UInt64, bytesReceived: UInt64, observedAt: Date) {
            self.flowID = flowID
            self.bytesSent = bytesSent
            self.bytesReceived = bytesReceived
            self.observedAt = observedAt
        }
    }

    public struct FlowClosed: Codable, Sendable, Equatable {
        public let flowID: UUID
        public let endedAt: Date

        public init(flowID: UUID, endedAt: Date) {
            self.flowID = flowID
            self.endedAt = endedAt
        }
    }

    case flowOpened(FlowOpened)
    case flowUpdated(FlowCounters)
    case flowClosed(FlowClosed)

    private enum CodingKeys: String, CodingKey {
        case flowOpened, flowUpdated, flowClosed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.flowOpened) {
            self = .flowOpened(try container.decode(FlowOpened.self, forKey: .flowOpened))
        } else if container.contains(.flowUpdated) {
            self = .flowUpdated(try container.decode(FlowCounters.self, forKey: .flowUpdated))
        } else if container.contains(.flowClosed) {
            self = .flowClosed(try container.decode(FlowClosed.self, forKey: .flowClosed))
        } else {
            throw DecodingError.typeMismatch(FlowEvent.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "no flow event case present"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .flowOpened(let payload): try container.encode(payload, forKey: .flowOpened)
        case .flowUpdated(let payload): try container.encode(payload, forKey: .flowUpdated)
        case .flowClosed(let payload): try container.encode(payload, forKey: .flowClosed)
        }
    }
}
