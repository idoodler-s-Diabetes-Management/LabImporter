import Foundation

struct LabDisplayPreferences: Codable, RawRepresentable {
    var pinnedCodes: [String] = []
    var orderedCodes: [String] = []
    var hiddenCodes: [String] = []

    init() {}

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { self = LabDisplayPreferences(); return }
        self = decoded
    }

    var rawValue: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var pinnedSet: Set<String> { Set(pinnedCodes) }
    var hiddenSet: Set<String> { Set(hiddenCodes) }
}
