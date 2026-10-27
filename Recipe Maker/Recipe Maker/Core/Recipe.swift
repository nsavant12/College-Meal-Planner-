import Foundation

enum Diet: String, Codable, CaseIterable, Identifiable {
    case any, vegetarian, vegan
    var id: Self { self }
    var title: String {
        switch self {
        case .any: return "Everything"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        }
    }
}

struct RecipeIngredient: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let amount: String

    init(_ name: String, _ amount: String) {
        self.name = Ingredient.normalize(name)
        self.amount = amount
    }
}

struct Recipe: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let minutes: Int
    let servings: Int
    let diet: Diet
    let equipment: String
    let ingredients: [RecipeIngredient]
    let steps: [String]
    let tip: String

    func supports(_ preference: Diet) -> Bool {
        preference == .any || diet == preference || (preference == .vegetarian && diet == .vegan)
    }
}

struct RecipePreferences: Codable, Equatable {
    var diet: Diet = .any
    var maximumMinutes: Int = 0 // Zero means no limit.
    var readyOnly: Bool = false
    var assumeStaples: Bool = false
}

struct RecipeMatch: Identifiable {
    var id: String { recipe.id }
    let recipe: Recipe
    let available: [RecipeIngredient]
    let missing: [RecipeIngredient]
    var isReady: Bool { missing.isEmpty }
    var coverage: Double { Double(available.count) / Double(max(recipe.ingredients.count, 1)) }
}

enum RecipeMatcher {
    static let staples: Set<String> = ["olive oil", "salt", "black pepper"]

    static func match(_ recipe: Recipe, pantry: Set<String>, assumeStaples: Bool = false) -> RecipeMatch {
        let available = Set(pantry.map(Ingredient.normalize)).union(assumeStaples ? staples : [])
        return RecipeMatch(recipe: recipe,
                           available: recipe.ingredients.filter { available.contains($0.name) },
                           missing: recipe.ingredients.filter { !available.contains($0.name) })
    }

    static func recommendations(in recipes: [Recipe], pantry: Set<String>,
                                preferences: RecipePreferences = .init(), query: String = "") -> [RecipeMatch] {
        let search = Ingredient.normalize(query)
        return recipes.filter { recipe in
            recipe.supports(preferences.diet)
                && (preferences.maximumMinutes == 0 || recipe.minutes <= preferences.maximumMinutes)
                && (search.isEmpty || recipe.title.localizedCaseInsensitiveContains(search)
                    || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(search) })
        }.map { match($0, pantry: pantry, assumeStaples: preferences.assumeStaples) }
            .filter { !preferences.readyOnly || $0.isReady }
            .sorted { lhs, rhs in
                if lhs.isReady != rhs.isReady { return lhs.isReady }
                if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
                if lhs.missing.count != rhs.missing.count { return lhs.missing.count < rhs.missing.count }
                if lhs.recipe.minutes != rhs.recipe.minutes { return lhs.recipe.minutes < rhs.recipe.minutes }
                return lhs.recipe.id < rhs.recipe.id
            }
    }
}
