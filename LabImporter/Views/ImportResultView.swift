import SwiftUI

struct ImportResultView: View {
    let result: ImportResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !result.imported.isEmpty {
                    Section {
                        ForEach(result.imported) { value in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(value.name)
                                Spacer()
                                Text("\(value.displayValue) \(value.unit)")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        }
                    } header: {
                        Text("Imported to Apple Health")
                    }
                }

                if !result.failed.isEmpty {
                    Section {
                        ForEach(result.failed, id: \.value.id) { entry in
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading) {
                                    Text(entry.value.name)
                                    if let err = entry.error {
                                        Text(err.localizedDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Could Not Import")
                    }
                }
            }
            .navigationTitle("Import Complete")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
