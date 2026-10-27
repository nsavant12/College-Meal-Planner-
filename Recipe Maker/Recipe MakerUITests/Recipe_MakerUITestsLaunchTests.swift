import XCTest

final class Recipe_MakerUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state"]
        app.launch()
        XCTAssertTrue(app.buttons["takePhoto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choosePhoto"].exists)
        XCTAssertTrue(app.tabBars.buttons["Pantry"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Pantry launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
