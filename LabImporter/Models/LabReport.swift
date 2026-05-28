import Foundation

struct LabReport: Codable, Identifiable {
    let id: UUID
    let date: Date
    let patientName: String
    let authorName: String
    let entries: [Entry]

    struct Entry: Codable, Identifiable {
        let id: UUID
        let code: String
        let name: String
        let displayValue: String
        let numericValue: Double?
        let unit: String

        var resolvedName: String {
            let mapped = LabMapping.displayName(for: code)
            return mapped == code ? name : mapped
        }
    }
}

extension LabReport {
    var asLabValues: [LabValue] {
        entries.map {
            LabValue(code: $0.code, name: $0.resolvedName,
                     displayValue: $0.displayValue,
                     numericValue: $0.numericValue,
                     unit: $0.unit)
        }
    }
}
