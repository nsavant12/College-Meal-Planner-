import XCTest

final class Recipe_MakerUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["takePhoto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choosePhoto"].exists)
        XCTAssertTrue(app.buttons["Pantry"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Pantry launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
