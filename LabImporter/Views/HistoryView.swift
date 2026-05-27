import SwiftUI

struct HistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var reports: [LabReport] = []
    @State private var loadError: String?

    var body: some View {
        ZStack {
            backgroundGradient
            Group {
                if reports.isEmpty {
                    ContentUnavailableView(
                        "No Reports Yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Import a lab report and save it to Apple Health to see it here.")
                    )
                } else {
                    reportList
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            if !reports.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: TrendsView(reports: reports)) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                }
            }
        }
        .task { await loadReports() }
        .alert("Load Error", isPresented: .constant(loadError != nil)) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(hue: 0.65, saturation: 0.60, brightness: 0.35),
                   Color(hue: 0.75, saturation: 0.70, brightness: 0.25)]
                : [Color(hue: 0.65, saturation: 0.20, brightness: 0.95),
                   Color(hue: 0.75, saturation: 0.25, brightness: 0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var reportList: some View {
        List {
            ForEach(reports) { report in
                NavigationLink(destination: ReportDetailView(report: report)) {
                    reportRow(report)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteReports)
        }
        .listStyle(.plain)
        .listRowSpacing(8)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 4)
    }

    private func reportRow(_ report: LabReport) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(report.date.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
                .foregroundStyle(.primary)

            let meta = [report.patientName, report.authorName]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if !meta.isEmpty {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(report.entries.count) value\(report.entries.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func loadReports() async {
        do {
            reports = try await HealthKitService.shared.loadCDADocuments()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteReports(at offsets: IndexSet) {
        let toDelete = offsets.map { reports[$0].id }
        reports.remove(atOffsets: offsets)
        Task {
            for reportId in toDelete {
                try? await HealthKitService.shared.deleteCDADocument(id: reportId)
            }
        }
    }
}
