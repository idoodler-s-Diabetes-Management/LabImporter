import SwiftUI

struct ReportDetailView: View {
    let report: LabReport

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: report.date.formatted(date: .long, time: .omitted))

                if !report.patientName.isEmpty {
                    LabeledContent("Patient", value: report.patientName)
                }

                if !report.authorName.isEmpty {
                    LabeledContent("Author", value: report.authorName)
                }
            }

            Section("Lab Values") {
                ForEach(report.entries) { entry in
                    entryRow(entry)
                }
            }
        }
        .navigationTitle(report.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.large)
    }

    private func entryRow(_ entry: LabReport.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                Text(entry.code)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }

            Spacer()

            let valueText = entry.displayValue == "-"
                ? "–"
                : "\(entry.displayValue) \(entry.unit)".trimmingCharacters(in: .whitespaces)

            Text(valueText)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
