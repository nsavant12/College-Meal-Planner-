import Foundation
import SQLite3

/// A read-only, versioned SQLite catalog. User pantry/favorite data lives in a
/// separate store, so replacing the bundled catalog never erases personal data.
final class RecipeRepository {
    enum RepositoryError: LocalizedError {
        case missingCatalog
        case incompatibleCatalog
        case invalidContent
        case database(String)

        var errorDescription: String? {
            switch self {
            case .missingCatalog: return "The recipe database is missing from this installation."
            case .incompatibleCatalog: return "This recipe database uses an unsupported format."
            case .invalidContent: return "The recipe database contains incomplete or damaged content."
            case .database(let message): return "The recipe database could not be read: \(message)"
            }
        }
    }

    private var database: OpaquePointer?
    // Keep the three related reads together, including when callers use the
    // repository from different queues. SQLite itself also uses serialized mode.
    private let lock = NSLock()
    private(set) var catalogVersion = 0

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open file"
            sqlite3_close(database)
            database = nil
            throw RepositoryError.database(detail)
        }
        do {
            guard try integer("PRAGMA application_id") == 0x4D504C4E,
                  try integer("PRAGMA user_version") == 1 else { throw RepositoryError.incompatibleCatalog }
            let integrity = try statement("PRAGMA quick_check")
            guard try integrity.next(), integrity.text(0) == "ok" else { throw RepositoryError.invalidContent }
            let relations = try statement("PRAGMA foreign_key_check")
            guard try !relations.next() else { throw RepositoryError.invalidContent }
            catalogVersion = try integer("SELECT CAST(value AS INTEGER) FROM catalog_metadata WHERE key = 'catalog_version'")
            guard catalogVersion > 0 else { throw RepositoryError.invalidContent }
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    /// Search values are bound parameters, never SQL fragments. SQLite performs
    /// the filtering; all matching recipes and their ordered children load in
    /// three queries rather than one query per ingredient or recipe.
    func recipes(matching query: String = "") throws -> [Recipe] {
        try fetch(predicate: """
            (?1 = '' OR instr(lower(r.title), ?1) > 0 OR EXISTS (
                SELECT 1 FROM recipe_ingredients search
                WHERE search.recipe_id = r.id AND instr(search.name, ?1) > 0
            ))
            """, value: Ingredient.normalize(query))
    }

    func recipe(id: String) throws -> Recipe? {
        try fetch(predicate: "r.id = ?1", value: id).first
    }

    private func fetch(predicate: String, value: String) throws -> [Recipe] {
        lock.lock()
        defer { lock.unlock() }
        let ingredientRows = try statement("""
            SELECT i.recipe_id, i.name, i.amount FROM recipe_ingredients i
            JOIN recipes r ON r.id = i.recipe_id WHERE \(predicate)
            ORDER BY i.recipe_id, i.position
            """, value: value)
        var ingredients: [String: [RecipeIngredient]] = [:]
        while try ingredientRows.next() {
            let name = ingredientRows.text(1)
            let amount = ingredientRows.text(2)
            guard !name.isEmpty, name == Ingredient.normalize(name), !amount.isEmpty else {
                throw RepositoryError.invalidContent
            }
            ingredients[ingredientRows.text(0), default: []].append(RecipeIngredient(name, amount))
        }
        let stepRows = try statement("""
            SELECT s.recipe_id, s.instruction FROM recipe_steps s
            JOIN recipes r ON r.id = s.recipe_id WHERE \(predicate)
            ORDER BY s.recipe_id, s.position
            """, value: value)
        var steps: [String: [String]] = [:]
        while try stepRows.next() {
            let instruction = stepRows.text(1)
            guard !instruction.isEmpty else { throw RepositoryError.invalidContent }
            steps[stepRows.text(0), default: []].append(instruction)
        }
        let rows = try statement("""
            SELECT r.id, r.title, r.summary, r.symbol, r.minutes, r.servings, r.diet, r.equipment, r.tip
            FROM recipes r WHERE \(predicate) ORDER BY r.id
            """, value: value)
        var recipes: [Recipe] = []
        while try rows.next() {
            let id = rows.text(0)
            guard let diet = Diet(rawValue: rows.text(6)),
                  let recipeIngredients = ingredients[id], !recipeIngredients.isEmpty,
                  let recipeSteps = steps[id], !recipeSteps.isEmpty,
                  !id.isEmpty, !rows.text(1).isEmpty, !rows.text(2).isEmpty,
                  rows.integer(4) > 0, rows.integer(5) > 0 else { throw RepositoryError.invalidContent }
            recipes.append(Recipe(id: id, title: rows.text(1), summary: rows.text(2), symbol: rows.text(3),
                                  minutes: rows.integer(4), servings: rows.integer(5), diet: diet,
                                  equipment: rows.text(7), ingredients: recipeIngredients,
                                  steps: recipeSteps, tip: rows.text(8)))
        }
        return recipes
    }

    private func integer(_ sql: String) throws -> Int {
        let result = try statement(sql)
        guard try result.next() else { throw RepositoryError.invalidContent }
        return result.integer(0)
    }

    private func statement(_ sql: String, value: String? = nil) throws -> Statement {
        try Statement(database: database, sql: sql, value: value)
    }

    private final class Statement {
        private let database: OpaquePointer?
        private var handle: OpaquePointer?

        init(database: OpaquePointer?, sql: String, value: String?) throws {
            self.database = database
            guard sqlite3_prepare_v2(database, sql, -1, &handle, nil) == SQLITE_OK else {
                sqlite3_finalize(handle)
                handle = nil
                throw RepositoryError.database(String(cString: sqlite3_errmsg(database)))
            }
            if let value = value {
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                guard sqlite3_bind_text(handle, 1, value, -1, transient) == SQLITE_OK else {
                    sqlite3_finalize(handle)
                    handle = nil
                    throw RepositoryError.database(String(cString: sqlite3_errmsg(database)))
                }
            }
        }

        deinit { sqlite3_finalize(handle) }

        func next() throws -> Bool {
            switch sqlite3_step(handle) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            default: throw RepositoryError.database(String(cString: sqlite3_errmsg(database)))
            }
        }

        func text(_ index: Int32) -> String {
            guard let text = sqlite3_column_text(handle, index) else { return "" }
            return String(cString: text)
        }

        func integer(_ index: Int32) -> Int { Int(sqlite3_column_int64(handle, index)) }
    }
}
