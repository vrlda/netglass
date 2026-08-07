import Foundation

/// Evidence that a remote IP belongs to a domain, with a confidence score.
/// Only the strongest available source is exposed per candidate.
public struct DomainCandidate: Equatable, Sendable, Codable {
    public let domain: String
    public let confidence: Double
    public let source: EvidenceSource

    public init(domain: String, confidence: Double, source: EvidenceSource) {
        self.domain = domain
        self.confidence = confidence
        self.source = source
    }

    public enum EvidenceSource: String, Codable, Sendable {
        /// Reverse lookup whose result round-trips: resolving the hostname
        /// again yields this IP (forward-confirmed reverse DNS).
        case forwardConfirmedPTR
        /// Reverse lookup only — the name may be stale or misconfigured.
        case ptrOnly
    }
}

extension DomainCandidate {
    /// Confidence floor for a bare PTR name.
    public static let ptrOnlyConfidence: Double = 0.25
    /// Confidence for a forward-confirmed PTR (FCrDNS) name.
    public static let forwardConfirmedConfidence: Double = 0.6
}
