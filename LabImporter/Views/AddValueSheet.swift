import SwiftUI

/// Manual single-value entry, presented from the review/edit screen's "Add Value"
/// menu. Assembles a `LabValue` from the form and hands it back to the caller; the
/// form resets on its own because SwiftUI recreates the sheet on each presentation.
struct AddValueSheet: View {
    let onAdd: (LabValue) -> Void

    @State private var name = ""
    @State private var code = ""
    @State private var displayValue = ""
    @State private var unit = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                    NavigationLink {
                        AddCodePickerPage(code: $code, name: $name)
                    } label: {
                        HStack {
                            Text("Lab Test")
                            Spacer()
                            Text(code.isEmpty ? "Any" : code)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    TextField("Value", text: $displayValue)
                        .keyboardType(.decimalPad)
                    TextField("Unit (optional)", text: $unit)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { commit() }
                        .fontWeight(.semibold)
                        .disabled(name.isEmpty || displayValue.isEmpty)
                }
            }
        }
    }

    private func commit() {
        let resolvedCode = code.isEmpty
            ? "MANUAL"
            : code.uppercased().trimmingCharacters(in: .whitespaces)
        let normalized = displayValue.replacingOccurrences(of: ",", with: ".")
        let value = LabValue(
            code: resolvedCode,
            name: name.trimmingCharacters(in: .whitespaces),
            displayValue: displayValue,
            numericValue: Double(normalized),
            unit: unit.trimmingCharacters(in: .whitespaces)
        )
        onAdd(value)
        dismiss()
    }
}
