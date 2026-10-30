import Foundation
import ImageIO
import Vision

/// Real model evaluation using the app's recognizer, not mocked predictions.
/// The small fixture set is regression evidence, not a general accuracy claim.
@main
struct RecognitionSmoke {
    struct Fixture: Decodable {
        let file: String
        let expected: [String]
        let minimumCorrect: Int
        let split: String
    }
    struct Evaluation: Codable {
        let file: String
        let split: String
        let expected: [String]
        let baseline: [String]
        let detected: [String]
        let missed: [String]
        let unexpected: [String]
        let regions: Int
        let failedRegions: Int
        let milliseconds: Int
    }

    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(domain: "RecognitionSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pass Fixtures/Recognition/cases.json; optionally pass an output JSON path."])
        }
        let manifest = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest))
        let recognizer = IngredientRecognizer()
        var evaluations: [Evaluation] = []
        var failures: [String] = []
        for fixture in fixtures {
            let url = manifest.deletingLastPathComponent().appendingPathComponent(fixture.file)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_600
                  ] as CFDictionary) else { throw NSError(domain: "RecognitionSmoke", code: 2) }
            let whole = VNClassifyImageRequest()
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([whole])
            // Reproduce the previous app's exact whole-image gate for comparison.
            let baseline = IngredientCandidate.filtered((whole.results ?? []).map { ($0.identifier, $0.confidence) }, threshold: 0.2, limit: 6).map(\.name).sorted()
            let start = Date()
            let result: RecognitionResult = try await withCheckedThrowingContinuation { continuation in
                recognizer.recognize(image, orientation: .up) { continuation.resume(with: $0) }
            }
            let detected = Set(result.candidates.map(\.name))
            let expected = Set(fixture.expected)
            let correct = detected.intersection(expected).count
            let extra = detected.subtracting(expected).sorted()
            let evaluation = Evaluation(file: fixture.file, split: fixture.split, expected: fixture.expected,
                                        baseline: baseline, detected: detected.sorted(),
                                        missed: expected.subtracting(detected).sorted(), unexpected: extra,
                                        regions: result.scannedRegionCount, failedRegions: result.failedRegionCount,
                                        milliseconds: Int(Date().timeIntervalSince(start) * 1_000))
            evaluations.append(evaluation)
            print("\(fixture.file): \(correct)/\(expected.count) visible ingredients, \(extra.count) unexpected; \(evaluation.milliseconds) ms, \(evaluation.regions) regions")
            print("  baseline: \(baseline); regional: \(evaluation.detected); missed: \(evaluation.missed)")
            if correct < fixture.minimumCorrect || !extra.isEmpty || result.failedRegionCount > 0 {
                failures.append(fixture.file)
            }
        }
        if CommandLine.arguments.count >= 3 {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(evaluations).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        }
        guard failures.isEmpty else {
            throw NSError(domain: "RecognitionSmoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "Recognition regression: \(failures.joined(separator: ", "))"])
        }
        print("PASS: \(fixtures.count) real-photo regressions. Inspect missed/unexpected labels; this is not a representative accuracy benchmark.")
    }
}
