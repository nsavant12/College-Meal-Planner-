import Foundation
import CoreML
import ImageIO
import Vision

/// Native Vision preprocessing and the app's suggestion filter, without crop refinement.
/// Single-foreground labels cannot score incidental-food false positives.
@main struct NativeClassifierEvaluation {
    struct Sample: Codable { let file: String; let expected: String }
    struct Prediction: Codable {
        let file: String
        let expected: String
        let top1: String?
        let confidence: Float?
        let suggestions: [String]
        let milliseconds: Double
    }
    struct Summary: Codable {
        let images: Int
        let top1Recall: Double
        let appSuggestionRecall: Double
        let supportedImages: Int
        let supportedSuggestionRecall: Double?
        let unsupportedExpectedLabels: [String]
        let predictions: [Prediction]
    }
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw NSError(domain: "NativeEvaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pass model.mlmodelc manifest.json output.json"])
        }
        let model = try VNCoreMLModel(for: MLModel(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        guard !samples.isEmpty else { throw NSError(domain: "NativeEvaluation", code: 2) }
        var predictions: [Prediction] = []
        for (index, sample) in samples.enumerated() {
            let prediction: Prediction = try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sample.file) as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1_600
                      ] as CFDictionary) else { throw NSError(domain: "NativeEvaluation", code: 3) }
                let request = VNCoreMLRequest(model: model)
                request.imageCropAndScaleOption = .scaleFit
                let start = ProcessInfo.processInfo.systemUptime
                try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                guard let observations = request.results as? [VNClassificationObservation] else {
                    throw NSError(domain: "NativeEvaluation", code: 4)
                }
                return Prediction(file: sample.file, expected: sample.expected,
                    top1: observations.first?.identifier, confidence: observations.first?.confidence,
                    suggestions: IngredientCandidate.filtered(observations.map { ($0.identifier, $0.confidence) }).map(\.name),
                    milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000)
            }
            predictions.append(prediction)
            if (index + 1) % 50 == 0 { print("\(index + 1)/\(samples.count)") }
        }
        let supported = predictions.filter { Ingredient.recognizable.contains($0.expected) }
        let summary = Summary(images: predictions.count,
            top1Recall: Double(predictions.filter { $0.top1 == $0.expected }.count) / Double(predictions.count),
            appSuggestionRecall: Double(predictions.filter { $0.suggestions.contains($0.expected) }.count) / Double(predictions.count),
            supportedImages: supported.count,
            supportedSuggestionRecall: supported.isEmpty ? nil : Double(supported.filter { $0.suggestions.contains($0.expected) }.count) / Double(supported.count),
            unsupportedExpectedLabels: Set(predictions.map(\.expected)).subtracting(Ingredient.recognizable).sorted(),
            predictions: predictions)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
        print("\(summary.images) images; native top-1 recall \(summary.top1Recall); app-filtered recall \(summary.appSuggestionRecall)")
    }
}
