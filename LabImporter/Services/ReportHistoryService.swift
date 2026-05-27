import Foundation

actor ReportHistoryService {
    static let shared = ReportHistoryService()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("lab_reports.json")
    }()

    func save(_ report: LabReport) throws {
        var all = (try? loadAll()) ?? []
        all.insert(report, at: 0)
        let data = try JSONEncoder().encode(all)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadAll() throws -> [LabReport] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([LabReport].self, from: data)
    }

    func delete(id: UUID) throws {
        var all = (try? loadAll()) ?? []
        all.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(all)
        try data.write(to: fileURL, options: .atomic)
    }
}
