import CoreML
import Foundation
import ImageIO
import Vision

struct RecognitionResult {
    let candidates: [IngredientCandidate]
    let source: String
}

/// Runs Vision off the main thread and delivers results on the main thread.
/// The optional model is resolved at runtime; generated model classes are unused.
final class IngredientRecognizer {
    private let queue = DispatchQueue(label: "meal-planner.recognition", qos: .userInitiated)
    private let bundle: Bundle
    private var customModel: VNCoreMLModel?
    private var didLoadModel = false

    init(bundle: Bundle = .main) { self.bundle = bundle }

    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation,
                   completion: @escaping (Result<RecognitionResult, Error>) -> Void) {
        queue.async {
            let result = Result { try self.classify(image, orientation: orientation) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func classify(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> RecognitionResult {
        if !didLoadModel {
            didLoadModel = true
            if let url = bundle.url(forResource: "IngredientClassifier", withExtension: "mlmodelc"),
               let model = try? MLModel(contentsOf: url) {
                customModel = try? VNCoreMLModel(for: model)
            }
        }
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        if let model = customModel {
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            // An incompatible or failed optional model falls back to system Vision.
            if (try? handler.perform([request])) != nil,
               let observations = request.results as? [VNClassificationObservation] {
                let candidates = IngredientCandidate.filtered(observations.map { ($0.identifier, $0.confidence) })
                if !candidates.isEmpty {
                    return RecognitionResult(candidates: candidates, source: "Ingredient classifier")
                }
            }
        }
        let request = VNClassifyImageRequest()
        try handler.perform([request])
        return RecognitionResult(
            candidates: IngredientCandidate.filtered((request.results ?? []).map { ($0.identifier, $0.confidence) }),
            source: "Apple Vision"
        )
    }
}
