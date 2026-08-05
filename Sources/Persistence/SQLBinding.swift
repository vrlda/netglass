import Foundation

public enum SQLBinding: Sendable {
    case text(String)
    case blob([UInt8])
    case int(Int64)
    case double(Double)
    case null
}
