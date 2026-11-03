import Foundation
import CoreGraphics

/// Coordinates use Vision's normalized, bottom-left origin, after EXIF orientation.
enum RecognitionRegions {
    static let fullImage = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let maximumCount = 13

    static func make(salientObjects: [CGRect]) -> [CGRect] {
        var regions = [fullImage]
        // Overlap avoids losing an ingredient on a tile boundary. Fixed coverage
        // also works when saliency merges a crowded plate into one large object.
        for y in [0.0, 0.25, 0.5] {
            for x in [0.0, 0.25, 0.5] {
                regions.append(CGRect(x: x, y: y, width: 0.5, height: 0.5))
            }
        }
        for bounds in salientObjects {
            guard [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height].allSatisfy(\.isFinite),
                  bounds.width > 0, bounds.height > 0 else { continue }
            let region = bounds.insetBy(dx: -0.04, dy: -0.04).intersection(fullImage)
            guard !region.isNull, region.width >= 0.1, region.height >= 0.1,
                  region.width * region.height < 0.85,
                  !regions.contains(where: { overlap($0, region) > 0.85 }) else { continue }
            regions.append(region)
            if regions.count == maximumCount { break }
        }
        return regions
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let area = intersection.width * intersection.height
        return area / (a.width * a.height + b.width * b.height - area)
    }
}

struct IngredientScan {
    let region: CGRect
    let predictions: [(String, Float)]
}

/// Conservative suggestion gates, not calibrated probabilities of correctness.
/// Never add crop scores together: overlapping crops are correlated evidence.
enum RecognitionPolicy {
    static let maximumCandidates = 12

    static func candidates(from scans: [IngredientScan]) -> [IngredientCandidate] {
        var whole: [String: Float] = [:]
        var regional: [String: Float] = [:]
        for scan in scans {
            for candidate in IngredientCandidate.filtered(scan.predictions, threshold: 0, limit: Ingredient.recognizable.count) {
                if scan.region == RecognitionRegions.fullImage {
                    whole[candidate.name] = max(whole[candidate.name, default: 0], candidate.confidence)
                } else {
                    regional[candidate.name] = max(regional[candidate.name, default: 0], candidate.confidence)
                }
            }
        }
        return Set(whole.keys).union(regional.keys).compactMap { name in
            let full = whole[name, default: 0]
            let crop = regional[name, default: 0]
            // A moderately strong local result needs whole-image corroboration.
            guard full >= 0.5 || crop >= 0.6 || (full >= 0.4 && crop >= 0.5) else { return nil }
            return IngredientCandidate(name: name, confidence: max(full, crop))
        }.sorted {
            $0.confidence == $1.confidence ? $0.name < $1.name : $0.confidence > $1.confidence
        }.prefix(maximumCandidates).map { $0 }
    }
}


/// One detector instance in oriented image coordinates (normalized, bottom-left).
/// Classifier crops must never be converted into instances.
struct IngredientDetection: Equatable {
    let name: String
    let confidence: Float
    let box: CGRect
}

struct VisibleQuantity: Equatable {
    let name: String
    let count: Int
    let confidence: Float
    // Occlusion and unseen items mean this is never a total inventory or mass.
    var summary: String { "About \(count) visible" }
}

enum DetectionPolicy {
    static let maximumDetections = 100
    static let threshold: Float = 0.45
    static let nmsThreshold: CGFloat = 0.45
    static let countable: Set<String> = [
        "apple", "banana", "orange", "carrot", "broccoli", "egg", "potato",
        "tomato", "onion", "avocado", "lemon", "lime", "cucumber", "bell pepper",
        "pear", "peach", "kiwi", "mango", "zucchini", "eggplant", "sweet potato"
    ]

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let area = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - area
        return union > 0 ? min(1, max(0, area / union)) : 0
    }

    static func instances(_ input: [IngredientDetection]) -> [IngredientDetection] {
        let valid = input.compactMap { detection -> IngredientDetection? in
            let name = Ingredient.normalize(detection.name)
            let box = detection.box
            guard Ingredient.recognizable.contains(name), detection.confidence.isFinite,
                  detection.confidence >= threshold, detection.confidence <= 1,
                  [box.origin.x, box.origin.y, box.width, box.height].allSatisfy(\.isFinite),
                  box.width > 0, box.height > 0 else { return nil }
            let clipped = box.intersection(RecognitionRegions.fullImage)
            guard !clipped.isNull, clipped.width >= 0.005, clipped.height >= 0.005 else { return nil }
            return IngredientDetection(name: name, confidence: detection.confidence, box: clipped)
        }.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            if $0.name != $1.name { return $0.name < $1.name }
            if $0.box.minX != $1.box.minX { return $0.box.minX < $1.box.minX }
            return $0.box.minY < $1.box.minY
        }
        var kept: [IngredientDetection] = []
        for detection in valid {
            // Cross-class near-identical proposals are competing identities, not
            // two foods. Moderate overlaps of different foods remain distinct.
            guard !kept.contains(where: {
                iou($0.box, detection.box) > ($0.name == detection.name ? nmsThreshold : 0.85)
            }) else { continue }
            kept.append(detection)
            if kept.count == maximumDetections { break }
        }
        return kept
    }

    static func quantities(_ instances: [IngredientDetection]) -> [VisibleQuantity] {
        Dictionary(grouping: instances.filter { countable.contains($0.name) }, by: \.name)
            .map { name, items in
                VisibleQuantity(name: name, count: items.count, confidence: items.map(\.confidence).min() ?? 0)
            }.sorted { $0.name < $1.name }
    }
}
