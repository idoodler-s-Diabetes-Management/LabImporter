import Vision
import UIKit

actor OCRService {

    enum OCRError: LocalizedError {
        case invalidImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Could not process the selected image."
            case .noTextFound: return "No text was found in the image."
            }
        }
    }

    func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { obs -> String? in
                    obs.topCandidates(1).first?.string
                }

                let text = lines.joined(separator: " ")
                if text.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: text)
                }
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
