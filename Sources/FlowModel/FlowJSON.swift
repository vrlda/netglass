import Foundation

public enum FlowJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, container in
            var c = container.singleValueContainer()
            try c.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "invalid ISO8601 date: \(string)")
            }
            return date
        }
        return decoder
    }
}
