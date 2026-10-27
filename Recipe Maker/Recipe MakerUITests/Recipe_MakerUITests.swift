import XCTest

final class Recipe_MakerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state"]
        app.launch()
        return app
    }

    private func add(_ ingredients: String, to app: XCUIApplication) {
        let input = app.textFields["ingredientInput"].exists
            ? app.textFields["ingredientInput"] : app.textViews["ingredientInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(ingredients)
        app.buttons["addIngredients"].tap()
    }

    func testPantryToRecipeSaveAndRelaunch() {
        let app = launch()
        add("banana, oats, peanut butter", to: app)
        app.swipeUp()
        app.buttons["findRecipes"].tap()
        let recipe = app.buttons["recipe-banana-peanut-oats"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()
        app.buttons["saveRecipe"].tap()
        XCTAssertEqual(app.buttons["saveRecipe"].label, "Unsave recipe")
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["recipe-banana-peanut-oats"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Pantry"].tap()
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["pantry-banana"].exists)
    }

    func testEmptyReadyFilterAndReset() {
        let app = launch()
        app.tabBars.buttons["Recipes"].tap()
        app.buttons["recipeFilters"].tap()
        app.switches["readyOnlyFilter"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["No recipes found"].waitForExistence(timeout: 5))
        app.buttons["Reset filters"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recipe-'")).firstMatch.exists)
    }

    func testCookingChecklistAndUnsave() {
        let app = launch()
        add("banana, oats, peanut butter", to: app)
        app.tabBars.buttons["Recipes"].tap()
        app.buttons["recipe-banana-peanut-oats"].tap()
        app.buttons["saveRecipe"].tap()
        app.buttons["saveRecipe"].tap()
        XCTAssertEqual(app.buttons["saveRecipe"].label, "Save recipe")
        for index in 0..<3 {
            let step = app.buttons["cookingStep-\(index)"]
            for _ in 0..<5 where !step.isHittable { app.swipeUp() }
            XCTAssertTrue(step.isHittable)
            step.tap()
        }
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["cookingComplete"].exists)
        app.buttons["Reset cooking checklist"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["cookingComplete"].exists)
    }
}
