import Foundation

enum Ingredient {
    // Only explicit equivalents are merged. In particular, dairy and plant milk,
    // fresh and canned tomatoes, and cooked and dry rice stay distinct.
    static let aliases: [String: String] = [
        "apples": "apple", "bananas": "banana", "tomatoes": "tomato",
        "potatoes": "potato", "onions": "onion", "carrots": "carrot",
        "eggs": "egg", "avocados": "avocado", "lemons": "lemon",
        "limes": "lime", "oranges": "orange", "cucumbers": "cucumber",
        "mushrooms": "mushroom", "strawberries": "strawberry",
        "blueberries": "blueberry", "bell peppers": "bell pepper",
        "red bell pepper": "bell pepper", "green bell pepper": "bell pepper",
        "yellow bell pepper": "bell pepper", "capsicum": "bell pepper",
        "garbanzo beans": "chickpea", "chickpeas": "chickpea",
        "canned chickpeas": "chickpea", "canned black beans": "black bean",
        "black beans": "black bean", "scallions": "green onion",
        "spring onions": "green onion", "green onions": "green onion",
        "courgette": "zucchini", "aubergine": "eggplant",
        "sweet potatoes": "sweet potato", "rolled oats": "oats",
        "tortillas": "tortilla", "flour tortillas": "tortilla",
        "cheddar": "cheese", "cheddar cheese": "cheese",
        "plain yogurt": "yogurt", "greek yogurt": "yogurt",
        "canned tuna": "tuna", "extra virgin olive oil": "olive oil",
        "baby spinach": "spinach", "garlic cloves": "garlic",
        "canned tomatoes": "canned tomato", "tinned tomatoes": "canned tomato",
        "white bread": "bread", "pears": "pear", "peaches": "peach",
        "grapes": "grape", "cherries": "cherry", "raspberries": "raspberry"
    ]

    static func normalize(_ text: String) -> String {
        let cleaned = text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return aliases[cleaned] ?? cleaned
    }

    static func parse(_ text: String) -> [String] {
        Array(Set(text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map(normalize).filter { !$0.isEmpty && $0.count <= 60 })).sorted()
    }

    static let suggestions = [
        "tomato", "spinach", "egg", "bread", "cheese", "pasta", "cooked rice",
        "chickpea", "black bean", "tortilla", "banana", "oats", "yogurt",
        "potato", "broccoli", "carrot", "bell pepper", "onion", "garlic", "olive oil"
    ]

    // General labels such as "food", "fruit", and prepared dishes must never
    // become pantry ingredients. Unlisted foods can still be entered manually.
    static let recognizable: Set<String> = [
        "apple", "banana", "tomato", "potato", "sweet potato", "onion",
        "carrot", "avocado", "lemon", "lime", "orange", "cucumber",
        "mushroom", "strawberry", "blueberry", "bell pepper", "broccoli",
        "cauliflower", "spinach", "lettuce", "cabbage", "zucchini", "eggplant",
        "corn", "garlic", "green onion", "pear", "peach", "pineapple",
        "watermelon", "grape", "kiwi", "mango", "cherry", "raspberry",
        "egg", "bread", "cheese", "pasta", "oats", "yogurt", "milk",
        "tofu", "chickpea", "black bean", "tortilla", "peanut butter", "hummus"
    ]
}

struct IngredientCandidate: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let confidence: Float

    static func filtered(_ predictions: [(String, Float)], threshold: Float = 0.2) -> [Self] {
        var best: [String: Float] = [:]
        for (label, confidence) in predictions where confidence.isFinite && confidence >= threshold && confidence <= 1 {
            let name = Ingredient.normalize(label)
            guard Ingredient.recognizable.contains(name) else { continue }
            best[name] = max(best[name] ?? 0, confidence)
        }
        return best.map { Self(name: $0.key, confidence: $0.value) }
            .sorted { $0.confidence == $1.confidence ? $0.name < $1.name : $0.confidence > $1.confidence }
            .prefix(6).map { $0 }
    }
}
