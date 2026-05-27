import Foundation
import FoundationModels

// MARK: - Generable types for structured AI output

@Generable
struct AILabReport {
    @Guide(description: "All lab test values found in the text")
    var entries: [AILabEntry]
}

@Generable
struct AILabEntry {
    @Guide(description: "Lab test code or abbreviation as printed (e.g. KREA, HB-A1C, G-GT)")
    var code: String

    @Guide(description: "Value exactly as printed — use '-' for negative/not-detected results")
    var rawValue: String

    @Guide(description: "Unit of measurement as printed (e.g. mg/dl, %, mmol/mol, U/l, ml/min/1,73m2KOF). Empty string if none.")
    var unit: String
}

// MARK: - Parser

actor LabParserService {

    func parseLabValues(from text: String) async throws -> [LabValue] {
        let entries: [AILabEntry]

        if SystemLanguageModel.default.isAvailable {
            entries = try await parseWithFoundationModels(text: text)
        } else {
            entries = parseWithRegex(text: text)
        }

        return entries.map { entry in
            let normalizedValue = entry.rawValue
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")

            let numericValue: Double? = entry.rawValue == "-" ? nil : Double(normalizedValue)

            return LabValue(
                code: entry.code,
                name: LabMapping.displayName(for: entry.code),
                displayValue: entry.rawValue,
                numericValue: numericValue,
                unit: entry.unit,
                healthKitMapping: LabMapping.healthKitMapping(for: entry.code)
            )
        }
    }

    // MARK: - Foundation Models path

    private func parseWithFoundationModels(text: String) async throws -> [AILabEntry] {
        let session = LanguageModelSession(
            instructions: """
            You are a medical lab report parser. Extract every lab test entry from the provided text.
            Lab reports follow the pattern: CODE: value unit; CODE2: value2 unit2; ...
            Preserve codes exactly as printed. Use '-' as rawValue when the result is negative or not detected.
            """
        )

        let response = try await session.respond(
            to: "Extract all lab values from this text:\n\n\(text)",
            generating: AILabReport.self
        )

        return response.content.entries
    }

    // MARK: - Regex fallback

    // Handles: "CODE: value unit;" or "CODE: - ;" patterns from semicolon-separated German lab reports
    private func parseWithRegex(text: String) -> [AILabEntry] {
        // Split on semicolons to isolate individual entries
        let segments = text.components(separatedBy: ";")

        // Pattern: one or more UPPERCASE letters/digits/hyphens, colon, then value and optional unit
        let entryPattern = /([A-Z][A-Z0-9\-]+)\s*:\s*(-|[\d]+[,\.]?[\d]*)\s*(.*)/

        return segments.compactMap { segment in
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = trimmed.firstMatch(of: entryPattern) else { return nil }

            let code = String(match.1)
            let rawValue = String(match.2)
            let unit = String(match.3).trimmingCharacters(in: .whitespacesAndNewlines)

            return AILabEntry(code: code, rawValue: rawValue, unit: unit)
        }
    }
}
