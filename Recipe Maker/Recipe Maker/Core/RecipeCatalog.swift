import Foundation

/// Resolves the catalog resource in both the app and the independently tested package.
enum RecipeCatalog {
    static var databaseURL: URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "recipes", withExtension: "sqlite")
    }

    static func open() throws -> RecipeRepository {
        guard let url = databaseURL else { throw RecipeRepository.RepositoryError.missingCatalog }
        return try RecipeRepository(url: url)
    }
}
