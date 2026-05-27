import HealthKit

// Maps German lab report codes to human-readable names and HealthKit types.
//
// HealthKit only exposes a small set of writable clinical quantity types.
// Blood glucose (HKQuantityTypeIdentifier.bloodGlucose) is the primary one
// relevant to lab reports. As Apple expands HealthKit, add new cases below.
enum LabMapping {

    static func healthKitMapping(for code: String) -> HealthKitMapping? {
        switch code.uppercased() {

        // Blood glucose (mg/dL) — HKQuantityTypeIdentifier.bloodGlucose
        case "BZ", "GLUCOSE", "GLU", "BLOOD-GLUCOSE":
            return HealthKitMapping(identifier: .bloodGlucose, unit: HKUnit(from: "mg/dL"))

        // Add further mappings here once Apple adds the corresponding
        // HKQuantityTypeIdentifier entries (e.g. HbA1c, cholesterol, TSH).
        default:
            return nil
        }
    }

    static func displayName(for code: String) -> String {
        switch code.uppercased() {
        case "DIABOL", "DIAB0L":        return "Diabetes Screening"
        case "KREA", "CREATININE":      return "Creatinine"
        case "MDRD", "EGFR":            return "eGFR (MDRD)"
        case "CHOL", "TC":              return "Total Cholesterol"
        case "HDL":                     return "HDL Cholesterol"
        case "NONHDL", "NON-HDL":       return "Non-HDL Cholesterol"
        case "LDL":                     return "LDL Cholesterol"
        case "TRIG", "TG":              return "Triglycerides"
        case "GPT", "ALT":              return "GPT (ALT)"
        case "G-GT", "GGT", "GGTP":    return "Gamma-GT (GGT)"
        case "HB-A1C", "HBAIC", "HBA1C", "HBA1C%": return "HbA1c (%)"
        case "HB-A1", "HBA1":          return "HbA1 (mmol/mol)"
        case "TSH-0", "TSH":           return "TSH (Thyroid)"
        case "BZ", "GLUCOSE", "GLU":   return "Blood Glucose"
        case "KREA-GFR", "CKD-EPI":    return "eGFR (CKD-EPI)"
        default:                        return code
        }
    }

    // Values without HealthKit support — shown read-only with info badge
    static let unsupportedCodes: Set<String> = [
        "KREA", "MDRD", "HDL", "NONHDL", "NON-HDL", "LDL", "TRIG", "TG",
        "GPT", "ALT", "G-GT", "GGT", "GGTP",
        "HB-A1C", "HBAIC", "HBA1C", "HBA1C%",
        "HB-A1", "HBA1",
        "TSH-0", "TSH",
        "DIABOL", "DIAB0L",
        "KREA-GFR", "CKD-EPI"
    ]
}
