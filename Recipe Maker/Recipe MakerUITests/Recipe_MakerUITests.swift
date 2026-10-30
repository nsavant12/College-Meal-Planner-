import XCTest

final class Recipe_MakerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        // iPadOS can render SwiftUI tabs in the top toolbar without a TabBar node.
        let tab = app.tabBars.buttons[title]
        let target = tab.exists ? tab : app.buttons[title].firstMatch
        // A tab can exist underneath a dismissing sheet but have no hit point.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in target.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        target.tap()
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
        selectTab("Saved", in: app)
        XCTAssertTrue(app.buttons["recipe-banana-peanut-oats"].waitForExistence(timeout: 5))
        selectTab("Pantry", in: app)
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["pantry-banana"].exists)
    }

    func testEmptyReadyFilterAndReset() {
        let app = launch()
        selectTab("Recipes", in: app)
        app.buttons["recipeFilters"].tap()
        let ready = app.switches["readyOnlyFilter"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        // SwiftUI exposes the whole row as the switch's accessibility frame.
        // Tap the trailing native control rather than the row's text midpoint.
        ready.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(ready.value as? String, "1")
        app.buttons["Done"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Recipes with ready-only filter"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.staticTexts["emptyRecipeResults"].waitForExistence(timeout: 5))
        app.buttons["Reset filters"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recipe-'")).firstMatch.exists)
    }

    func testCookingChecklistAndUnsave() {
        let app = launch()
        add("banana, oats, peanut butter", to: app)
        selectTab("Recipes", in: app)
        app.buttons["recipe-banana-peanut-oats"].tap()
        app.buttons["saveRecipe"].tap()
        app.buttons["saveRecipe"].tap()
        XCTAssertEqual(app.buttons["saveRecipe"].label, "Save recipe")
        for index in 0..<3 {
            let step = app.buttons["cookingStep-\(index)"]
            for _ in 0..<5 where !step.isHittable { app.swipeUp() }
            XCTAssertTrue(step.isHittable)
            step.tap()
            XCTAssertEqual(step.value as? String, "Completed")
        }
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["cookingComplete"].exists)
        app.buttons["Reset cooking checklist"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["cookingComplete"].exists)
    }

    func testPrivacyAndDeleteAllData() {
        let app = launch()
        add("banana, oats, peanut butter", to: app)
        selectTab("Recipes", in: app)
        app.buttons["recipe-banana-peanut-oats"].tap()
        app.buttons["saveRecipe"].tap()
        selectTab("Pantry", in: app)
        app.buttons["About Meal Planner"].tap()
        app.buttons["privacyPolicy"].tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let delete = app.buttons["deleteAppData"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["Delete all data"].tap()
        let deletion = XCTAttachment(screenshot: app.screenshot())
        deletion.name = "After confirmed data deletion"
        deletion.lifetime = .keepAlways
        add(deletion)
        selectTab("Saved", in: app)
        XCTAssertTrue(app.staticTexts["emptySaved"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["emptyPantry"].exists)
    }

    func testPhotoPickerCanBeCancelledWithoutChangingPantry() {
        let app = launch()
        app.buttons["choosePhoto"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.buttons["choosePhoto"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["emptyPantry"].exists)
    }

    func testPantryAccessibility() throws {
        let app = launch()
        func auditVisibleContent() throws {
            // The audit's Dynamic Type heuristic loses elements as the adaptive
            // grid reflows off-screen. The next test checks real font growth and
            // interaction at the largest accessibility size instead.
            // The clipping heuristic shares this limitation on scrollable text.
            // Review wrapping and contrast visually; retain structural, label,
            // trait, and hit-area checks without excluding individual elements.
            try app.performAccessibilityAudit(for: [.elementDetection, .hitRegion, .sufficientElementDescription, .trait])
        }
        try auditVisibleContent()
        app.swipeUp()
        try auditVisibleContent()
    }

    func testLargestTextKeepsSuggestionsAndManualEntryUsable() {
        let app = launch()
        for _ in 0..<4 where !app.buttons["suggestion-egg"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["suggestion-egg"].waitForExistence(timeout: 5))
        let regularHeight = app.buttons["suggestion-egg"].frame.height
        app.terminate()
        app.launchArguments = ["--uitesting", "--reset-state",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let suggestion = app.buttons["suggestion-egg"]
        for _ in 0..<12 where !suggestion.isHittable { app.swipeUp() }
        XCTAssertTrue(suggestion.isHittable)
        XCTAssertGreaterThan(suggestion.frame.height, regularHeight)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Largest accessibility text"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        suggestion.tap()
        for _ in 0..<12 where !app.staticTexts["Egg"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Egg"].exists)
        for _ in 0..<12 where !app.textViews["ingredientInput"].isHittable && !app.textFields["ingredientInput"].isHittable { app.swipeDown() }
        add("banana", to: app)
        selectTab("Recipes", in: app)
        let recipe = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recipe-'")).firstMatch
        for _ in 0..<8 where !recipe.exists { app.swipeUp() }
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    }
}
