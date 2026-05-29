import Foundation

// LOINC is the canonical identity for every lab value in the app: the parser
// resolves printed report codes to LOINC, and storage, reference ranges and
// display names all key off the LOINC code. The German abbreviations that lab
// reports actually print (KREA, HB-A1C, …) only appear here as *import-time*
// resolver inputs — see `loinc(forPrinted:)`.
//
// For the handful of curated "favorite" metrics we keep hand-tuned localized
// names and clinical reference ranges; everything else is resolved against the
// full bundled catalog via `LoincDirectory`.
enum LabMapping {

    // MARK: - Curated common metrics (LOINC-keyed)

    struct Metric {
        let loinc: String
        let name: String
        let range: ReferenceRange?
    }

    // Single source of truth for the app's favorite metrics.
    static let commonMetrics: [Metric] = [
        Metric(loinc: "2345-7", name: String(localized: "Blood Glucose"),
               range: ReferenceRange(normalLow: 70, normalHigh: 100, borderlineLow: nil, borderlineHigh: 125)),
        Metric(loinc: "2160-0", name: String(localized: "Creatinine"),
               range: ReferenceRange(normalLow: 0.5, normalHigh: 1.2, borderlineLow: nil, borderlineHigh: nil)),
        Metric(loinc: "33914-3", name: String(localized: "eGFR (MDRD)"),
               range: ReferenceRange(normalLow: 90, normalHigh: nil, borderlineLow: 60, borderlineHigh: nil)),
        Metric(loinc: "62238-1", name: String(localized: "eGFR (CKD-EPI)"),
               range: ReferenceRange(normalLow: 90, normalHigh: nil, borderlineLow: 60, borderlineHigh: nil)),
        Metric(loinc: "2093-3", name: String(localized: "Total Cholesterol"),
               range: ReferenceRange(normalLow: nil, normalHigh: 200, borderlineLow: nil, borderlineHigh: 239)),
        Metric(loinc: "2085-9", name: String(localized: "HDL Cholesterol"),
               range: ReferenceRange(normalLow: 40, normalHigh: nil, borderlineLow: nil, borderlineHigh: nil)),
        Metric(loinc: "43396-1", name: String(localized: "Non-HDL Cholesterol"), range: nil),
        Metric(loinc: "2089-1", name: String(localized: "LDL Cholesterol"),
               range: ReferenceRange(normalLow: nil, normalHigh: 100, borderlineLow: nil, borderlineHigh: 159)),
        Metric(loinc: "2571-8", name: String(localized: "Triglycerides"),
               range: ReferenceRange(normalLow: nil, normalHigh: 150, borderlineLow: nil, borderlineHigh: 199)),
        Metric(loinc: "1742-6", name: String(localized: "GPT (ALT)"),
               range: ReferenceRange(normalLow: nil, normalHigh: 40, borderlineLow: nil, borderlineHigh: nil)),
        Metric(loinc: "2324-2", name: String(localized: "Gamma-GT (GGT)"),
               range: ReferenceRange(normalLow: nil, normalHigh: 55, borderlineLow: nil, borderlineHigh: nil)),
        Metric(loinc: "4548-4", name: String(localized: "HbA1c (%)"),
               range: ReferenceRange(normalLow: nil, normalHigh: 5.7, borderlineLow: nil, borderlineHigh: 6.4)),
        Metric(loinc: "59261-8", name: String(localized: "HbA1 (mmol/mol)"), range: nil),
        Metric(loinc: "3016-3", name: String(localized: "TSH (Thyroid)"),
               range: ReferenceRange(normalLow: 0.4, normalHigh: 4.0, borderlineLow: nil, borderlineHigh: nil)),
        Metric(loinc: "14647-2", name: String(localized: "Diabetes Screening"), range: nil),
    ]

    private static let metricsByLoinc: [String: Metric] =
        Dictionary(commonMetrics.map { ($0.loinc, $0) }, uniquingKeysWith: { first, _ in first })

    // Quick-pick "favorites" list shown in the picker and Settings.
    static var allKnownCodes: [(code: String, name: String)] {
        commonMetrics.map { (code: $0.loinc, name: $0.name) }
    }

    // MARK: - LOINC lookups

    // Localized display name for a LOINC code: curated favorite name first, then
    // the bundled catalog, finally the raw code (e.g. an as-yet-unmapped value).
    static func displayName(for code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if let metric = metricsByLoinc[trimmed] { return metric.name }
        if let term = LoincDirectory.shared.term(for: trimmed) { return term.name }
        return code
    }

    // Clinical reference range, only defined for the curated favorites.
    static func referenceRange(for code: String) -> ReferenceRange? {
        metricsByLoinc[code.trimmingCharacters(in: .whitespaces)]?.range
    }

    // Validates that `code` is a real LOINC code and returns it with an English
    // display name for CDA export. Returns nil for unmapped/unknown codes, which
    // is how the UI decides a value cannot yet be saved to Health.
    static func loincCode(for code: String) -> (loinc: String, display: String)? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if let term = LoincDirectory.shared.term(for: trimmed) {
            return (term.code, term.englishName)
        }
        if let metric = metricsByLoinc[trimmed] {
            // Curated favorite that falls outside the common-lab catalog (e.g. eGFR MDRD).
            return (metric.loinc, metric.name)
        }
        return nil
    }

    // MARK: - Import resolution (printed report code -> LOINC)

    // Maps the codes/abbreviations a lab report actually prints to LOINC, so the
    // rest of the app only ever deals in LOINC. Returns nil when the printed code
    // is neither a known abbreviation nor an existing LOINC code, in which case
    // the user maps it manually in the review sheet.
    // swiftlint:disable:next cyclomatic_complexity
    static func loinc(forPrinted printed: String) -> String? {
        switch printed.uppercased().trimmingCharacters(in: .whitespaces) {
        case "DIABOL", "DIAB0L":            return "14647-2"
        case "KREA", "CREATININE":          return "2160-0"
        case "MDRD", "EGFR":                return "33914-3"
        case "KREA-GFR", "CKD-EPI":         return "62238-1"
        case "CHOL", "TC":                  return "2093-3"
        case "HDL":                          return "2085-9"
        case "NONHDL", "NON-HDL":           return "43396-1"
        case "LDL":                          return "2089-1"
        case "TRIG", "TG":                  return "2571-8"
        case "GPT", "ALT":                  return "1742-6"
        case "G-GT", "GGT", "GGTP":         return "2324-2"
        case "HB-A1C", "HBAIC", "HBA1C", "HBA1C%": return "4548-4"
        case "HB-A1", "HBA1":               return "59261-8"
        case "TSH-0", "TSH":                return "3016-3"
        case "BZ", "GLUCOSE", "GLU":        return "2345-7"
        default:
            // Already a LOINC code (e.g. pasted in, or chosen from the catalog)?
            let trimmed = printed.trimmingCharacters(in: .whitespaces)
            return LoincDirectory.shared.isKnownLoinc(trimmed) ? trimmed : nil
        }
    }
}

// MARK: - Reference range types

enum RangeStatus: Equatable {
    case normal, borderline, abnormal
}

struct ReferenceRange {
    let normalLow: Double?       // nil = no lower bound
    let normalHigh: Double?      // nil = no upper bound
    let borderlineLow: Double?   // low boundary of borderline zone (e.g. eGFR 60–89)
    let borderlineHigh: Double?  // high boundary of borderline zone (e.g. HbA1c 5.7–6.4)

    func status(for value: Double) -> RangeStatus {
        if let low = normalLow, value < low {
            if let bLow = borderlineLow, value >= bLow { return .borderline }
            return .abnormal
        }
        if let high = normalHigh, value > high {
            if let bHigh = borderlineHigh, value <= bHigh { return .borderline }
            return .abnormal
        }
        return .normal
    }
}
