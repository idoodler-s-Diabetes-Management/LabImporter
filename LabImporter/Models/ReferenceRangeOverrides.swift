import Foundation

// User-configurable reference range overrides per lab code.
// Mirrors the LabDisplayPreferences pattern: RawRepresentable so it can live in @AppStorage,
// with a separate Codable Payload to avoid the RawRepresentable+Codable encoding cycle.
struct ReferenceRangeOverrides: RawRepresentable, Equatable {
    var ranges: [String: StoredRange] = [:]

    struct StoredRange: Codable, Equatable {
        var normalLow: Double?
        var normalHigh: Double?
        var borderlineLow: Double?
        var borderlineHigh: Double?
    }

    init() {}

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { self = ReferenceRangeOverrides(); return }
        ranges = decoded.ranges
    }

    var rawValue: String {
        let payload = Payload(ranges: ranges)
        return (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func range(for code: String) -> StoredRange? {
        ranges[code.uppercased()]
    }

    mutating func setRange(_ range: StoredRange?, for code: String) {
        let key = code.uppercased()
        if let range {
            ranges[key] = range
        } else {
            ranges.removeValue(forKey: key)
        }
    }

    private struct Payload: Codable {
        var ranges: [String: StoredRange]
    }
}
