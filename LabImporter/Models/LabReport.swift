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
    }
}

extension LabReport {
    var asLabValues: [LabValue] {
        entries.map {
            LabValue(code: $0.code, name: $0.name,
                     displayValue: $0.displayValue,
                     numericValue: $0.numericValue,
                     unit: $0.unit)
        }
    }
}
