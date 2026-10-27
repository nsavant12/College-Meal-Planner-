import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MealPlannerCore
#else
@testable import Recipe_Maker
#endif

@Suite struct IngredientTests {
    @Test func testNormalizesCaseWhitespacePluralsAndKnownAliases() {
        #expect(Ingredient.parse(" Tomatoes,  eggs,\nTOMATO, garbanzo beans, bell_peppers ") == ["bell pepper", "chickpea", "egg", "tomato"])
        #expect(Ingredient.normalize("  GREEN   ONIONS ") == "green onion")
    }

    @Test func testPreservesMeaningfulIngredientDistinctions() {
        #expect(Ingredient.normalize("rice") != Ingredient.normalize("cooked rice"))
        #expect(Ingredient.normalize("canned tomato") != Ingredient.normalize("tomato"))
        #expect(Ingredient.normalize("almond milk") != Ingredient.normalize("milk"))
        #expect(Ingredient.normalize("sweet potato") != Ingredient.normalize("potato"))
        #expect(Ingredient.normalize("oatmeal") != Ingredient.normalize("oats"))
    }

    @Test func testBlankDuplicateAndLongEntries() {
        #expect(Ingredient.parse(" , \n ,") == [])
        #expect(Ingredient.parse("egg, eggs, Egg") == ["egg"])
        #expect(Ingredient.parse(String(repeating: "a", count: 61)) == [])
    }

    @Test func testPredictionsRequireSpecificKnownFoodAndFiniteConfidence() {
        let result = IngredientCandidate.filtered([
            ("food", 0.99), ("fruit", 0.95), ("banana", 0.8), ("bananas", 0.7),
            ("apple", 0.19), ("bell_pepper", 0.6), ("pizza", 0.99), ("carrot", .nan),
            ("egg", .infinity), ("tomato", 1.1), ("oatmeal", 0.9)
        ])
        #expect(result.map(\.name) == ["banana", "bell pepper"])
        #expect(result.first?.confidence == 0.8)
    }

    @Test func testPredictionLimitAndTiesAreDeterministic() {
        let names = ["tomato", "banana", "apple", "carrot", "cucumber", "egg", "broccoli"]
        let result = IngredientCandidate.filtered(names.map { ($0, 0.5) })
        #expect(result.map(\.name) == Array(names.sorted().prefix(6)))
    }
}

@Suite struct RecipeMatcherTests {
    let recipes = RecipeCatalog.all
    var oats: Recipe { recipes.first { $0.id == "banana-peanut-oats" }! }

    @Test func testExactMatchRanksFirstAndDuplicatePantryDoesNotInflateCoverage() {
        let pantry = Set(["bananas", "oats", "peanut butter", "banana"])
        let matches = RecipeMatcher.recommendations(in: recipes, pantry: pantry)
        #expect(matches.first?.id == oats.id)
        #expect(matches.first?.isReady == true)
        #expect(matches.first?.coverage == 1)
        #expect(matches.first?.available.count == 3)
    }

    @Test func testMissingIngredientsPreserveRecipeOrder() {
        let match = RecipeMatcher.match(oats, pantry: ["banana"])
        #expect(match.missing.map(\.name) == ["oats", "peanut butter"])
        #expect(match.coverage == 1.0 / 3.0)
        #expect(!(match.isReady))
    }

    @Test func testStaplesAreOnlyAssumedWhenExplicitlyEnabled() {
        let recipe = recipes.first { $0.id == "avocado-tomato-toast" }!
        let pantry = Set(["bread", "avocado", "tomato", "lemon"])
        #expect(RecipeMatcher.match(recipe, pantry: pantry).missing.map(\.name) == ["salt"])
        #expect(RecipeMatcher.match(recipe, pantry: pantry, assumeStaples: true).isReady)
    }

    @Test func testVeganVegetarianTimeAndReadyFiltersCombine() {
        var p = RecipePreferences()
        p.diet = .vegan
        p.maximumMinutes = 15
        p.readyOnly = true
        let results = RecipeMatcher.recommendations(in: recipes, pantry: ["banana", "oats", "peanut butter", "egg"], preferences: p)
        #expect(results.map(\.id) == [oats.id])
        p.diet = .vegetarian
        p.readyOnly = false
        let vegetarian = RecipeMatcher.recommendations(in: recipes, pantry: [], preferences: p)
        #expect(vegetarian.contains { $0.recipe.diet == .vegan })
        #expect(vegetarian.contains { $0.recipe.diet == .vegetarian })
        #expect(!(vegetarian.contains { $0.recipe.diet == .any || $0.recipe.minutes > 15 }))
    }

    @Test func testEmptyPantryCanBrowseButReadyFilterReturnsNoRecipes() {
        #expect(RecipeMatcher.recommendations(in: recipes, pantry: []).count == recipes.count)
        var p = RecipePreferences()
        p.readyOnly = true
        p.assumeStaples = true
        #expect(RecipeMatcher.recommendations(in: recipes, pantry: [], preferences: p).isEmpty)
    }

    @Test func testSearchUsesTitleAndCanonicalIngredients() {
        let byAlias = RecipeMatcher.recommendations(in: recipes, pantry: [], query: "tomatoes")
        #expect(!(byAlias.isEmpty))
        #expect(byAlias.contains { $0.id == "tomato-spinach-pasta" })
        #expect(byAlias.contains { $0.id == "chickpea-spinach-curry" })
        #expect(!byAlias.contains { $0.id == "banana-peanut-oats" })
        #expect(byAlias.map(\.id) == RecipeMatcher.recommendations(in: recipes, pantry: [], query: "tomato").map(\.id))
        #expect(RecipeMatcher.recommendations(in: recipes, pantry: [], query: "sesame rice").map(\.id) == ["broccoli-rice-bowl"])
        #expect(RecipeMatcher.recommendations(in: recipes, pantry: [], query: "unknownfood").isEmpty)
    }

    @Test func testResultsDoNotDependOnCatalogOrder() {
        let forward = RecipeMatcher.recommendations(in: recipes, pantry: ["tomato", "egg"]).map(\.id)
        let reverse = RecipeMatcher.recommendations(in: recipes.reversed(), pantry: ["tomato", "egg"]).map(\.id)
        #expect(forward == reverse)
    }

    @Test func testCatalogHasCompleteUniqueRecipesAndCanonicalIngredients() {
        #expect(recipes.count == 20)
        #expect(Set(recipes.map(\.id)).count == recipes.count)
        for recipe in recipes {
            #expect(!(recipe.title.isEmpty))
            #expect(!(recipe.summary.isEmpty))
            #expect(!(recipe.equipment.isEmpty))
            #expect(!(recipe.tip.isEmpty))
            #expect(recipe.minutes > 0)
            #expect(recipe.servings > 0)
            #expect(recipe.steps.count >= 3)
            #expect(!(recipe.steps.contains(where: { $0.isEmpty })))
            #expect(recipe.ingredients.count >= 3)
            #expect(Set(recipe.ingredients.map(\.name)).count == recipe.ingredients.count)
            for item in recipe.ingredients {
                #expect(item.name == Ingredient.normalize(item.name))
                #expect(!(item.amount.isEmpty))
            }
        }
    }
}

@Suite struct PlannerStoreTests {
    private func withStore(_ body: (PlannerStore, URL) throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(PlannerStore(url: directory.appendingPathComponent("state.json")), directory)
    }

    @Test func missingFileStartsWithEmptyState() throws {
        try withStore { store, _ in
            let loaded = try store.load()
            #expect(loaded == PlannerState())
        }
    }

    @Test func stateSurvivesRelaunchIncludingPreferencesAndFavorites() throws {
        try withStore { store, _ in
            var state = PlannerState()
            state.addIngredients("Eggs, TOMATO, eggs")
            state.favorites = ["banana-peanut-oats"]
            state.preferences = RecipePreferences(diet: .vegan, maximumMinutes: 15, readyOnly: true, assumeStaples: true)
            try store.save(state)
            #expect(try PlannerStore(url: store.url).load() == state)
            state.pantry.remove("egg")
            try store.save(state)
            #expect(try store.load().pantry == ["tomato"])
        }
    }

    @Test func corruptFileIsNotSilentlyErased() throws {
        try withStore { store, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let invalid = Data("not json".utf8)
            try invalid.write(to: store.url)
            #expect(throws: (any Error).self) { try store.load() }
            #expect(try Data(contentsOf: store.url) == invalid)
        }
    }

    @Test func futureVersionIsRejectedAndArchivedWithoutDataLoss() throws {
        try withStore { store, directory in
            var state = PlannerState()
            state.version = 999
            try store.save(state)
            let original = try Data(contentsOf: store.url)
            #expect(throws: (any Error).self) { try store.load() }
            try store.archive()
            #expect(!FileManager.default.fileExists(atPath: store.url.path))
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            #expect(backups.count == 1)
            let backup = try #require(backups.first)
            #expect(try Data(contentsOf: backup) == original)
            #expect(try store.load() == PlannerState())
        }
    }

    @Test func loadedNamesAndInvalidTimePreferenceAreNormalized() throws {
        try withStore { store, _ in
            var state = PlannerState()
            state.pantry = [" Eggs ", "egg", "", "  "]
            state.preferences.maximumMinutes = -1
            try store.save(state)
            let loaded = try store.load()
            #expect(loaded.pantry == ["egg"])
            #expect(loaded.preferences.maximumMinutes == 0)
        }
    }

    @Test func saveFailureIsReportedWithoutReplacingUnrelatedFile() throws {
        try withStore { _, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let blocker = directory.appendingPathComponent("blocker")
            try Data("keep me".utf8).write(to: blocker)
            let brokenStore = PlannerStore(url: blocker.appendingPathComponent("state.json"))
            #expect(throws: (any Error).self) { try brokenStore.save(PlannerState()) }
            #expect(try String(contentsOf: blocker) == "keep me")
        }
    }
}
