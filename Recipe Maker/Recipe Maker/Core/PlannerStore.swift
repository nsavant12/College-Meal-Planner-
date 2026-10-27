import Foundation

struct PlannerState: Codable, Equatable {
    var version = 1
    var pantry: Set<String> = []
    var favorites: Set<String> = []
    var preferences = RecipePreferences()

    mutating func addIngredients(_ text: String) {
        pantry.formUnion(Ingredient.parse(text))
    }
}

struct PlannerStore {
    let url: URL

    enum StoreError: LocalizedError {
        case unsupportedVersion
        var errorDescription: String? { "This saved pantry was created by a newer version of the app." }
    }

    func load() throws -> PlannerState {
        guard FileManager.default.fileExists(atPath: url.path) else { return PlannerState() }
        var state = try JSONDecoder().decode(PlannerState.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw StoreError.unsupportedVersion }
        state.pantry = Set(state.pantry.map(Ingredient.normalize).filter { !$0.isEmpty && $0.count <= 60 })
        if ![0, 15, 30, 45].contains(state.preferences.maximumMinutes) { state.preferences.maximumMinutes = 0 }
        return state
    }

    func save(_ state: PlannerState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    /// Preserve unreadable data before an explicitly requested reset.
    func archive() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backup = url.deletingLastPathComponent().appendingPathComponent("pantry-backup-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: url, to: backup)
    }
}
