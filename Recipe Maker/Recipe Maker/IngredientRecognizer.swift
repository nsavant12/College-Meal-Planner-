import CoreML
import Foundation
import ImageIO
import Vision

struct RecognitionResult {
    let candidates: [IngredientCandidate]
    let source: String
    var scannedRegionCount = 0
    var failedRegionCount = 0
}

/// Cancellation is checked between requests and also cancels the active Vision
/// request. No image, predictions, or diagnostic content is persisted.
final class IngredientRecognitionTask {
    private let lock = NSLock()
    private var cancelled = false
    private var activeRequest: VNRequest?

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let request = activeRequest
        lock.unlock()
        request?.cancel()
    }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }

    func perform(_ request: VNRequest, using handler: VNImageRequestHandler) throws {
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        activeRequest = request
        lock.unlock()
        defer {
            lock.lock(); activeRequest = nil; lock.unlock()
        }
        try handler.perform([request])
        try checkCancellation()
    }
}

struct RegionClassification {
    let predictions: [(String, Float)]
    let source: String
}

/// A session owns the oriented image handler for one scan. The abstraction also
/// lets tests exercise failure/cancellation without depending on simulator ML.
protocol IngredientRecognitionSession {
    func salientObjects(task: IngredientRecognitionTask) throws -> [CGRect]
    func classify(region: CGRect, task: IngredientRecognitionTask) throws -> RegionClassification
}

final class IngredientRecognizer {
    private let queue = DispatchQueue(label: "meal-planner.recognition", qos: .userInitiated)
    private let makeSession: (CGImage, CGImagePropertyOrientation) -> any IngredientRecognitionSession

    init(bundle: Bundle = .main) {
        let model = OptionalIngredientModel(bundle: bundle)
        makeSession = { image, orientation in
            VisionIngredientSession(image: image, orientation: orientation, model: model)
        }
    }

    init(makeSession: @escaping (CGImage, CGImagePropertyOrientation) -> any IngredientRecognitionSession) {
        self.makeSession = makeSession
    }

    @discardableResult
    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation,
                   progress: ((Double) -> Void)? = nil,
                   completion: @escaping (Result<RecognitionResult, Error>) -> Void) -> IngredientRecognitionTask {
        let task = IngredientRecognitionTask()
        queue.async {
            let result = Result { () throws -> RecognitionResult in
                try task.checkCancellation()
                let session = self.makeSession(image, orientation)
                var scans: [IngredientScan] = []
                var sources = Set<String>()
                var failures = 0
                // Fail promptly if inference is unavailable instead of repeating
                // the same simulator/device failure for every tile.
                let first = try session.classify(region: RecognitionRegions.fullImage, task: task)
                scans.append(IngredientScan(region: RecognitionRegions.fullImage, predictions: first.predictions))
                sources.insert(first.source)
                try task.checkCancellation()
                // Saliency is an optional improvement; fixed coverage remains
                // available when it fails or combines all food into one object.
                let objects = (try? session.salientObjects(task: task)) ?? []
                try task.checkCancellation()
                let regions = RecognitionRegions.make(salientObjects: objects)
                for (index, region) in regions.dropFirst().enumerated() {
                    try task.checkCancellation()
                    do {
                        let result = try autoreleasepool { try session.classify(region: region, task: task) }
                        scans.append(IngredientScan(region: region, predictions: result.predictions))
                        sources.insert(result.source)
                    } catch {
                        try task.checkCancellation()
                        failures += 1
                    }
                    let fraction = Double(index + 2) / Double(regions.count)
                    DispatchQueue.main.async {
                        if !task.isCancelled { progress?(fraction) }
                    }
                }
                try task.checkCancellation()
                return RecognitionResult(candidates: RecognitionPolicy.candidates(from: scans),
                                         source: sources.sorted().joined(separator: " + "),
                                         scannedRegionCount: scans.count, failedRegionCount: failures)
            }
            DispatchQueue.main.async {
                completion(task.isCancelled ? .failure(CancellationError()) : result)
            }
        }
        return task
    }
}

/// Accessed only by the recognizer's serial queue, including initial model load.
private final class OptionalIngredientModel {
    private let bundle: Bundle
    private var didLoad = false
    private var model: VNCoreMLModel?

    init(bundle: Bundle) { self.bundle = bundle }

    func load() -> VNCoreMLModel? {
        guard !didLoad else { return model }
        didLoad = true
        guard let url = bundle.url(forResource: "IngredientClassifier", withExtension: "mlmodelc"),
              let classifier = try? MLModel(contentsOf: url),
              classifier.modelDescription.inputDescriptionsByName.values.contains(where: { $0.type == .image }),
              classifier.modelDescription.predictedFeatureName != nil else { return nil }
        model = try? VNCoreMLModel(for: classifier)
        return model
    }
}

private final class VisionIngredientSession: IngredientRecognitionSession {
    private let handler: VNImageRequestHandler
    private let model: OptionalIngredientModel

    init(image: CGImage, orientation: CGImagePropertyOrientation, model: OptionalIngredientModel) {
        handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        self.model = model
    }

    func salientObjects(task: IngredientRecognitionTask) throws -> [CGRect] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        try task.perform(request, using: handler)
        return (request.results?.first?.salientObjects ?? []).map(\.boundingBox)
    }

    func classify(region: CGRect, task: IngredientRecognitionTask) throws -> RegionClassification {
        if let classifier = model.load() {
            let request = VNCoreMLRequest(model: classifier)
            request.regionOfInterest = region
            request.imageCropAndScaleOption = .scaleFit
            if (try? task.perform(request, using: handler)) != nil,
               let observations = request.results as? [VNClassificationObservation] {
                let predictions = observations.map { ($0.identifier, $0.confidence) }
                // A weak custom output must not block the system model.
                if !IngredientCandidate.filtered(predictions, threshold: 0.5).isEmpty {
                    return RegionClassification(predictions: predictions, source: "Ingredient classifier")
                }
            }
            try task.checkCancellation()
        }
        let request = VNClassifyImageRequest()
        request.regionOfInterest = region
        try task.perform(request, using: handler)
        return RegionClassification(predictions: (request.results ?? []).map { ($0.identifier, $0.confidence) },
                                    source: "Apple Vision")
    }
}
