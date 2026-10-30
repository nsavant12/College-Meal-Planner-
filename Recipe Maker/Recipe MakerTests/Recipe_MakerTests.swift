import Foundation
import CoreGraphics
import Testing
import SQLite3
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
        #expect(result.map(\.name) == names.sorted())
        #expect(IngredientCandidate.filtered(names.map { ($0, 0.5) }, limit: 3).count == 3)
        #expect(IngredientCandidate.filtered(names.map { ($0, 0.5) }, limit: -1).isEmpty)
    }
}

@Suite struct RecognitionPolicyTests {
    let whole = RecognitionRegions.fullImage
    let crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)

    @Test func scanCoversEdgesAndNeverExceedsItsBudget() {
        let regions = RecognitionRegions.make(salientObjects: (0..<30).map {
            CGRect(x: Double($0 % 5) * 0.2, y: Double($0 / 5) * 0.1, width: 0.15, height: 0.15)
        })
        #expect(regions.first == whole)
        #expect(regions.count == RecognitionRegions.maximumCount)
        for region in regions {
            #expect(whole.contains(region))
            #expect(region.width > 0 && region.height > 0)
            #expect(regions.filter { $0 == region }.count == 1)
        }
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 0.99, y: 0), CGPoint(x: 0, y: 0.99), CGPoint(x: 0.99, y: 0.99)] {
            #expect(regions.dropFirst().contains { $0.contains(point) })
        }
    }

    @Test func malformedTinyAndDuplicateSaliencyCannotCreateInvalidCrops() {
        let regions = RecognitionRegions.make(salientObjects: [
            whole, .null, CGRect(x: .nan, y: 0, width: 0.2, height: 0.2),
            CGRect(x: 2, y: 2, width: 0.2, height: 0.2),
            CGRect(x: 0.1, y: 0.1, width: 0.001, height: 0.001),
            CGRect(x: 0.04, y: 0.04, width: 0.42, height: 0.42)
        ])
        #expect(regions.count == 10)
    }

    @Test func separateRegionsCanSuggestMultipleIngredientsWithoutDuplicates() {
        let candidates = RecognitionPolicy.candidates(from: [
            .init(region: whole, predictions: [("food", 1), ("banana", 0.19)]),
            .init(region: crop, predictions: [("banana", 0.81), ("bananas", 0.79)]),
            .init(region: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), predictions: [("oranges", 0.9)])
        ])
        #expect(candidates.map(\.name) == ["orange", "banana"])
        #expect(candidates.last?.confidence == 0.81)
    }

    @Test func weakOverlappingGuessesNeverAccumulateIntoACertainIngredient() {
        let scans = (0..<100).map { _ in IngredientScan(region: crop, predictions: [("zucchini", 0.3), ("zucchini", 0.3)]) }
        #expect(RecognitionPolicy.candidates(from: scans).isEmpty)
    }

    @Test func moderateCropNeedsIndependentWholeImageSupport() {
        let regional = IngredientScan(region: crop, predictions: [("bell_pepper", 0.51)])
        #expect(RecognitionPolicy.candidates(from: [regional]).isEmpty)
        let corroborated = RecognitionPolicy.candidates(from: [regional, .init(region: whole, predictions: [("bell pepper", 0.42)])])
        #expect(corroborated.map(\.name) == ["bell pepper"])
        #expect(corroborated.first?.confidence == 0.51)
    }

    @Test func nonFoodPreparedDishesAndInvalidScoresAreNotIngredients() {
        let result = RecognitionPolicy.candidates(from: [.init(region: whole, predictions: [
            ("food", 1), ("salad", 1), ("oatmeal", 1), ("fried_egg", 1),
            ("bean", 1), ("citrus_fruit", 1), ("carrot", .nan), ("tomato", .infinity),
            ("apple", -1), ("banana", 1.01), ("cooked rice", 0.9)
        ])])
        #expect(result.isEmpty)
    }

    @Test func outputIsBoundedAndDeterministic() {
        let names = Ingredient.recognizable.sorted()
        let result = RecognitionPolicy.candidates(from: [.init(region: whole, predictions: names.reversed().map { ($0, 0.8) })])
        #expect(result.map(\.name) == Array(names.prefix(RecognitionPolicy.maximumCandidates)))
    }
}

@Suite struct RecipeMatcherTests {
    let recipes: [Recipe]
    init() throws { recipes = try RecipeCatalog.open().recipes() }
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
        #expect(recipes.count >= 20)
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

    @Test func deleteAllDataRemovesStateAndBackupsButPreservesUnrelatedFiles() throws {
        try withStore { store, directory in
            var state = PlannerState()
            state.addIngredients("tomato")
            state.favorites = ["tomato-spinach-pasta"]
            try store.save(state)
            try store.archive()
            try store.save(state)
            let other = directory.appendingPathComponent("unrelated.txt")
            try Data("keep me".utf8).write(to: other)
            try store.deleteAllData()
            let loaded = try store.load()
            #expect(loaded == PlannerState())
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["unrelated.txt"])
            #expect(try String(contentsOf: other) == "keep me")
        }
    }

    @Test func deletingMissingDataIsSafeToRepeat() throws {
        try withStore { store, _ in
            try store.deleteAllData()
            try store.save(PlannerState())
            try store.deleteAllData()
            try store.deleteAllData()
            let loaded = try store.load()
            #expect(loaded == PlannerState())
        }
    }
}

@Suite struct RecipeRepositoryTests {
    @Test func bundledDatabaseLoadsOrderedRecipeContent() throws {
        let repository = try RecipeCatalog.open()
        #expect(repository.catalogVersion > 0)
        let found = try repository.recipe(id: "banana-peanut-oats")
        let recipe = try #require(found)
        #expect(recipe.title == "Banana peanut butter oats")
        #expect(recipe.ingredients.map(\.name) == ["oats", "banana", "peanut butter"])
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps[0].hasPrefix("Combine the oats"))
        #expect(recipe.minutes == 7)
        #expect(recipe.diet == .vegan)
    }

    @Test func databaseSearchNormalizesAliasesAndBindsUserInput() throws {
        let repository = try RecipeCatalog.open()
        let tomatoes = try repository.recipes(matching: "TOMATOES")
        #expect(tomatoes.contains { $0.id == "tomato-spinach-pasta" })
        #expect(!tomatoes.contains { $0.id == "banana-peanut-oats" })
        #expect(try repository.recipes(matching: "' OR 1=1 --").isEmpty)
        #expect(try repository.recipe(id: "' OR 1=1 --") == nil)
        #expect(try repository.recipes().count >= 20)
    }

    @Test func missingDatabaseDoesNotCreateAnEmptyReplacement() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        #expect(throws: (any Error).self) { try RecipeRepository(url: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func futureSchemaAndUnrelatedDatabaseAreRejected() throws {
        try withDatabaseCopy { url in
            try mutate(url, sql: "PRAGMA user_version = 999")
            #expect(throws: (any Error).self) { try RecipeRepository(url: url) }
            try mutate(url, sql: "PRAGMA user_version = 1; PRAGMA application_id = 0")
            #expect(throws: (any Error).self) { try RecipeRepository(url: url) }
        }
    }

    @Test func brokenRelationshipsAndMissingInstructionsAreRejected() throws {
        try withDatabaseCopy { url in
            try mutate(url, sql: "DELETE FROM recipe_steps WHERE recipe_id = 'banana-peanut-oats'")
            let repository = try RecipeRepository(url: url)
            #expect(throws: (any Error).self) { try repository.recipes() }
        }
        try withDatabaseCopy { url in
            try mutate(url, sql: "DELETE FROM recipes WHERE id = 'banana-peanut-oats'")
            #expect(throws: (any Error).self) { try RecipeRepository(url: url) }
        }
    }

    private func withDatabaseCopy(_ body: (URL) throws -> Void) throws {
        let source = try #require(RecipeCatalog.databaseURL)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try FileManager.default.copyItem(at: source, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    private func mutate(_ url: URL, sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw RecipeRepository.RepositoryError.invalidContent
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw RecipeRepository.RepositoryError.invalidContent
        }
    }
}

#if !SWIFT_PACKAGE && canImport(UIKit)
import UIKit

private final class ImageTestBundle: NSObject {}

private final class TestRecognitionSession: IngredientRecognitionSession {
    enum Failure: Error { case unavailable }
    var failWhole = false
    var failRegions = false
    var failSaliency = false
    var cancelFirst = false
    private(set) var calls = 0
    private(set) var saliencyCalls = 0

    func salientObjects(task: IngredientRecognitionTask) throws -> [CGRect] {
        saliencyCalls += 1
        if failSaliency { throw Failure.unavailable }
        return []
    }

    func classify(region: CGRect, task: IngredientRecognitionTask) throws -> RegionClassification {
        calls += 1
        if cancelFirst { task.cancel() }
        if region == RecognitionRegions.fullImage {
            if failWhole { throw Failure.unavailable }
            return RegionClassification(predictions: [("banana", 0.8)], source: "Test")
        }
        if failRegions { throw Failure.unavailable }
        return RegionClassification(predictions: [("oranges", 0.7)], source: "Test")
    }
}

@Suite @MainActor struct ImageProcessingTests {
    private func image(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func largeImagesAreBoundedWithoutStretching() throws {
        let result = try #require(image(size: CGSize(width: 2560, height: 1280)).recognitionImage())
        #expect(result.width == 1600)
        #expect(result.height == 800)
    }

    @Test func cameraOrientationIsNormalized() throws {
        let original = try #require(image(size: CGSize(width: 40, height: 80)).cgImage)
        let rotated = UIImage(cgImage: original, scale: 1, orientation: .right)
        let result = try #require(rotated.recognitionImage())
        #expect(result.width == 80)
        #expect(result.height == 40)
    }

    @Test func invalidPhotoFileIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(UIImage.recognitionThumbnail(at: url) == nil)
    }

    @Test func realPhotoIsDownsampledForRecognition() throws {
        let url = try #require(Bundle(for: ImageTestBundle.self).url(forResource: "banana", withExtension: "jpg"))
        let thumbnail = try #require(UIImage.recognitionThumbnail(at: url))
        let image = try #require(thumbnail.recognitionImage())
        #expect(max(image.width, image.height) <= 1600)
        #expect(image.width > 0 && image.height > 0)
    }

    @Test func unavailableSaliencyStillScansMultipleRegionsAndReportsProgressOnMainThread() async throws {
        let session = TestRecognitionSession()
        session.failSaliency = true
        let recognizer = IngredientRecognizer(makeSession: { _, orientation in
            #expect(orientation == .right)
            return session
        })
        let cgImage = try #require(image(size: CGSize(width: 80, height: 80)).cgImage)
        var progress: [Double] = []
        let result: RecognitionResult = try await withCheckedThrowingContinuation { continuation in
            recognizer.recognize(cgImage, orientation: .right, progress: { fraction in
                #expect(Thread.isMainThread)
                progress.append(fraction)
            }) { result in
                #expect(Thread.isMainThread)
                continuation.resume(with: result)
            }
        }
        #expect(result.candidates.map(\.name) == ["banana", "orange"])
        #expect(result.scannedRegionCount == 10)
        #expect(result.failedRegionCount == 0)
        #expect(progress == progress.sorted())
        #expect(progress.last == 1)
    }

    @Test func failingCropsPreserveSuccessfulWholeImageEvidence() async throws {
        let session = TestRecognitionSession()
        session.failRegions = true
        let result = try await recognize(session: session)
        #expect(result.candidates.map(\.name) == ["banana"])
        #expect(result.scannedRegionCount == 1)
        #expect(result.failedRegionCount == 9)
    }

    @Test func unavailableInferenceStopsAfterOneRequest() async throws {
        let session = TestRecognitionSession()
        session.failWhole = true
        do {
            _ = try await recognize(session: session)
            Issue.record("Unavailable inference should throw")
        } catch is TestRecognitionSession.Failure {
            #expect(session.calls == 1)
            #expect(session.saliencyCalls == 0)
        }
    }

    @Test func cancelledScanCannotDeliverCandidatesOrQueueMoreRegions() async throws {
        let session = TestRecognitionSession()
        session.cancelFirst = true
        do {
            _ = try await recognize(session: session)
            Issue.record("Cancelled inference should not return suggestions")
        } catch is CancellationError {
            #expect(session.calls == 1)
            #expect(session.saliencyCalls == 0)
        }
    }

    private func recognize(session: TestRecognitionSession) async throws -> RecognitionResult {
        let recognizer = IngredientRecognizer(makeSession: { _, _ in session })
        let cgImage = try #require(image(size: CGSize(width: 80, height: 80)).cgImage)
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognize(cgImage, orientation: .up) { continuation.resume(with: $0) }
        }
    }

    #if targetEnvironment(simulator)
    @Test(.disabled("Vision classification is unreliable in the iOS 27 simulator; run on a physical device."))
    #else
    @Test
    #endif
    func realPhotosAreRecognizedOnDevice() async throws {
        struct Fixture: Decodable {
            let file: String
            let expected: [String]
            let minimumCorrect: Int
        }
        let manifest = try #require(Bundle(for: ImageTestBundle.self).url(forResource: "cases", withExtension: "json", subdirectory: "Recognition"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest))
        let recognizer = IngredientRecognizer()
        for fixture in fixtures {
            let url = manifest.deletingLastPathComponent().appendingPathComponent(fixture.file)
            let thumbnail = try #require(UIImage.recognitionThumbnail(at: url))
            let image = try #require(thumbnail.recognitionImage())
            let result: RecognitionResult = try await withCheckedThrowingContinuation { continuation in
                recognizer.recognize(image, orientation: .up) { continuation.resume(with: $0) }
            }
            let names = Set(result.candidates.map(\.name))
            #expect(names.intersection(fixture.expected).count >= fixture.minimumCorrect, "\(fixture.file): \(names)")
            #expect(names.subtracting(fixture.expected).isEmpty, "Unexpected ingredients in \(fixture.file): \(names)")
            #expect(result.failedRegionCount == 0)
        }
    }
}
#endif
