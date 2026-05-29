import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Shared driver for the "known" import methods — scan, file, paste — that turn a
/// document or clipboard content into parsed `LabValue`s via OCR + the on-device AI.
///
/// Both the home screen (creating a brand-new report) and the review/edit sheet
/// (adding more values to an already-open report) use this. Callers hold one as
/// `@State`, set `onParsed`, attach `.labImport(engine:)`, and call `scan()` /
/// `pickFile()` / `paste()` from their own buttons. The engine owns the scanner,
/// file importer, error alert and processing HUD so each call site stays small.
@MainActor
@Observable
final class LabImportEngine {
    /// Invoked on the main actor with the parsed result of a successful import.
    /// Home replaces its working set with `result.values`; review appends to it.
    var onParsed: ((ParseResult) -> Void)?

    /// Shown when an import yields no usable values.
    var emptyMessage = String(
        localized: "No lab values were found in this document. Make sure the report is clearly visible."
    )

    private(set) var isProcessing = false

    fileprivate var errorMessage: String?
    fileprivate var showScanner = false
    fileprivate var showFileImporter = false

    private let ocrService = OCRService()
    private let parserService = LabParserService()

    // MARK: - Method entry points

    func scan() {
        guard VNDocumentCameraViewController.isSupported else {
            errorMessage = String(localized: "Document scanning isn't available on this device.")
            return
        }
        showScanner = true
    }

    func pickFile() {
        showFileImporter = true
    }

    func paste() {
        let pasteboard = UIPasteboard.general
        if let image = pasteboard.image {
            Task { await processImages([image]) }
        } else if let text = pasteboard.string, !text.isEmpty {
            Task { await processText(text) }
        }
    }

    // MARK: - Processing

    func processFile(at url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let isPDF = url.pathExtension.lowercased() == "pdf"
            || (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true

        if isPDF {
            await processPDF(at: url)
        } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            await processImages([image])
        } else {
            errorMessage = String(localized: "Could not load the selected file.")
        }
    }

    func processImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let text = try await ocrService.extractText(from: images)
            try await handleExtractedText(text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func processText(_ text: String) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await handleExtractedText(text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processPDF(at url: URL) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let text = try await ocrService.extractText(fromPDFAt: url)
            try await handleExtractedText(text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleExtractedText(_ text: String) async throws {
        let result = try await parserService.parseLabValues(from: text)
        if result.values.isEmpty {
            errorMessage = emptyMessage
            return
        }
        onParsed?(result)
    }

    fileprivate func reportError(_ message: String) {
        errorMessage = message
    }
}

// MARK: - View wiring

private struct LabImportModifier: ViewModifier {
    @Bindable var engine: LabImportEngine

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $engine.showScanner) {
                DocumentScannerView(
                    onComplete: { images in
                        Task { await engine.processImages(images) }
                    },
                    onError: { error in
                        engine.reportError(error.localizedDescription)
                    }
                )
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $engine.showFileImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await engine.processFile(at: url) }
                case .failure:
                    engine.reportError(String(localized: "Could not load the selected file."))
                }
            }
            .alert("Error", isPresented: Binding(
                get: { engine.errorMessage != nil },
                set: { if !$0 { engine.errorMessage = nil } }
            )) {
                Button("OK") { engine.errorMessage = nil }
            } message: {
                Text(engine.errorMessage ?? "")
            }
            .overlay {
                if engine.isProcessing { ProcessingHUD() }
            }
    }
}

extension View {
    /// Wires up the scanner, file importer, error alert and processing HUD that
    /// back a `LabImportEngine`. Pair with `engine.scan()` / `pickFile()` /
    /// `paste()` from your own controls.
    func labImport(engine: LabImportEngine) -> some View {
        modifier(LabImportModifier(engine: engine))
    }
}

// MARK: - Processing HUD

struct ProcessingHUD: View {
    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Analyzing lab report…")
                        .font(.headline)
                    Text("Using on-device AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }
}
