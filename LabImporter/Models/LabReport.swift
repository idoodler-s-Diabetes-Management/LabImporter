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
        // Reference range printed on the report itself (per-entry). Older reports
        // serialised without this field decode as nil.
        let parsedRange: ReferenceRangeOverrides.StoredRange?

        init(
            id: UUID,
            code: String,
            name: String,
            displayValue: String,
            numericValue: Double?,
            unit: String,
            parsedRange: ReferenceRangeOverrides.StoredRange? = nil
        ) {
            self.id = id
            self.code = code
            self.name = name
            self.displayValue = displayValue
            self.numericValue = numericValue
            self.unit = unit
            self.parsedRange = parsedRange
        }

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
                     unit: $0.unit,
                     parsedRange: $0.parsedRange)
        }
    }
}
