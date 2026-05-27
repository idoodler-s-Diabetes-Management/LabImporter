import SwiftUI

struct ProcessingView: View {
    var message: String = "Analyzing lab report…"

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.85)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.extraLarge)
                    .tint(.blue)

                Text(message)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Using on-device AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
        }
    }
}

#Preview {
    ProcessingView()
}
