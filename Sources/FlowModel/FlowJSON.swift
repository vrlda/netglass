import Foundation

public enum FlowJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, container in
            var c = container.singleValueContainer()
            try c.encode(date.timeIntervalSince1970)
        }
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let seconds = try container.decode(Double.self)
            return Date(timeIntervalSince1970: seconds)
        }
        return decoder
    }
}
