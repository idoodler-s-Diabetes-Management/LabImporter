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
