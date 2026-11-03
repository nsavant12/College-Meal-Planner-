import Foundation
import CoreGraphics
import ImageIO

private final class Session: IngredientRecognitionSession {
    enum Failure: Error { case inference }
    var failsDetector = false
    var failsCrops = false
    var task: IngredientRecognitionTask?
    func salientObjects(task: IngredientRecognitionTask) throws -> [CGRect] { [] }
    func classify(region: CGRect, task: IngredientRecognitionTask) throws -> RegionClassification {
        self.task = task
        if failsCrops && region != RecognitionRegions.fullImage { throw Failure.inference }
        return .init(predictions: [("apple", 0.9)], source: "injected")
    }
    func detect(task: IngredientRecognitionTask) throws -> [IngredientDetection]? {
        if failsDetector { throw Failure.inference }
        return [.init(name: "apple", confidence: 0.8, box: CGRect(x: 0, y: 0, width: 0.2, height: 0.2)),
                .init(name: "apple", confidence: 0.7, box: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2))]
    }
}

@main struct RecognitionPipelineTests {
    @MainActor static func main() async throws {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        for scenario in ["success", "detector failure", "crop failure", "cancel"] {
            let session = Session()
            session.failsDetector = scenario == "detector failure"
            session.failsCrops = scenario == "crop failure"
            let recognizer = IngredientRecognizer(makeSession: { _, _ in session })
            var receivedInitial = false
            do {
                let result: RecognitionResult = try await withCheckedThrowingContinuation { continuation in
                    recognizer.recognize(image, orientation: .up, preliminary: { initial in
                        precondition(Thread.isMainThread)
                        precondition(initial.candidates.map(\.name) == ["apple"])
                        precondition(initial.detections.isEmpty)
                        receivedInitial = true
                        if scenario == "cancel" { session.task?.cancel() }
                    }) { continuation.resume(with: $0) }
                }
                precondition(scenario != "cancel")
                precondition(receivedInitial)
                precondition(result.candidates.map(\.name) == ["apple"])
                precondition(result.detectorStatus == (session.failsDetector ? "failed" : "available"))
                precondition(result.quantities.first?.count == (session.failsDetector ? nil : 2))
                precondition(result.failedRegionCount == (session.failsCrops ? 9 : 0))
                precondition(result.totalMilliseconds >= result.initialMilliseconds)
            } catch is CancellationError {
                precondition(scenario == "cancel")
            }
        }
        print("PASS: early delivery, distinct counts, detector failure, crop failure, cancellation")
    }
}
