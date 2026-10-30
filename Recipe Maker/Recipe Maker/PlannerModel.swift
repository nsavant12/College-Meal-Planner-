import Foundation
import SwiftUI

@MainActor
final class PlannerModel: ObservableObject {
    @Published private(set) var state = PlannerState()
    @Published private(set) var storageMessage: String?
    @Published private(set) var needsStorageReset = false
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var catalogMessage: String?
    private let store: PlannerStore

    init(store: PlannerStore) {
        self.store = store
        do { state = try store.load() }
        catch {
            needsStorageReset = true
            storageMessage = "Your saved pantry could not be opened. New changes will not be saved until you reset local storage. Your original file will be backed up."
        }
        reloadCatalog()
    }

    static func live() -> PlannerModel {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = base.appendingPathComponent("MealPlanner", isDirectory: true)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            directory = fileManager.temporaryDirectory.appendingPathComponent("MealPlannerUITests", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-state") {
                try? fileManager.removeItem(at: directory)
            }
        }
        #endif
        return PlannerModel(store: PlannerStore(url: directory.appendingPathComponent("pantry.json")))
    }

    func reloadCatalog() {
        do {
            let catalog = try RecipeCatalog.open()
            let loaded = try catalog.recipes()
            guard !loaded.isEmpty else { throw RecipeRepository.RepositoryError.invalidContent }
            recipes = loaded
            catalogMessage = nil
        } catch {
            catalogMessage = "The recipe library couldn't be opened. Your pantry and saved recipes have been kept. Please try again; if this continues, check for an app update."
        }
    }

    var suggestedIngredients: [String] {
        let counts = recipes.flatMap(\.ingredients).reduce(into: [String: Int]()) { counts, ingredient in
            counts[ingredient.name, default: 0] += 1
        }
        return Array(counts.keys.filter { !state.pantry.contains($0) && !RecipeMatcher.staples.contains($0) }
            .sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0, default: 0] > counts[$1, default: 0] }
            .prefix(4))
    }

    func add(_ text: String) { state.addIngredients(text); persist() }
    func remove(_ name: String) { state.pantry.remove(name); persist() }
    func clearPantry() { state.pantry.removeAll(); persist() }

    func toggleFavorite(_ recipe: Recipe) {
        if state.favorites.contains(recipe.id) { state.favorites.remove(recipe.id) }
        else { state.favorites.insert(recipe.id) }
        persist()
    }

    func updatePreferences(_ value: RecipePreferences) { state.preferences = value; persist() }

    func match(_ recipe: Recipe) -> RecipeMatch {
        RecipeMatcher.match(recipe, pantry: state.pantry, assumeStaples: state.preferences.assumeStaples)
    }

    func retrySave() { persist() }

    @discardableResult
    func deleteAllData() -> Bool {
        do {
            try store.deleteAllData()
            state = PlannerState()
            needsStorageReset = false
            storageMessage = nil
            return true
        } catch {
            storageMessage = "Your saved data could not be fully deleted. Please try again when device storage is available."
            return false
        }
    }

    func resetStorage() {
        do {
            try store.archive()
            needsStorageReset = false
            persist()
        } catch {
            storageMessage = "The original pantry could not be backed up. Your changes are still in memory. Try again when storage is available."
        }
    }

    private func persist() {
        guard !needsStorageReset else { return }
        do { try store.save(state); storageMessage = nil }
        catch {
            storageMessage = "Your latest changes could not be saved. They will remain here while the app is open. Free up device storage and try again."
        }
    }
}
