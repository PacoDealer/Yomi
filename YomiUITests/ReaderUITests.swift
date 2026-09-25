import XCTest

/// Novel reader regressions from Martin's S128 field report (ROADMAP "S128", RESEARCH §23.1).
/// Runs against the Debug app's `-yomiReaderFixture`: a 3-chapter offline novel opened straight in the reader.
final class ReaderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-yomiReaderFixture"]
        app.launch()
        XCTAssertTrue(text("Fixture chapter 1, paragraph 1.").waitForExistence(timeout: 10), "fixture chapter 1 never showed")
    }

    private func text(_ s: String) -> XCUIElement {
        app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    private var nextButton: XCUIElement { app.buttons["Next chapter"] }
    /// DEBUG marker in TextReaderView: "open" / "closed".
    private var menuState: String { app.otherElements["reader.menuState"].value as? String ?? "?" }

    private func waitForMenu(_ state: String, timeout: TimeInterval = 3) -> Bool {
        let p = NSPredicate(format: "value == %@", state)
        return XCTWaiter.wait(for: [expectation(for: p, evaluatedWith: app.otherElements["reader.menuState"])],
                              timeout: timeout) == .completed
    }

    /// Scrolls to the end of the chapter, like reading it: this fills the preload cache (≥70 %) and marks it read.
    private func readToEnd(_ chapter: Int) {
        for _ in 0..<12 where !text("Fixture chapter \(chapter), paragraph 60.").isHittable {
            app.webViews.firstMatch.swipeUp(velocity: .fast)
        }
        sleep(1)
    }

    /// Bug #1: "Next chapter does nothing — has to quit the reader and reopen."
    /// Reads to the end first, as Martin does: at ≥70 % the next chapter is preloaded into a cache, and a cache hit
    /// returns from loadContent with no await in between (the suspected path).
    func testNextChapterShowsNewText() {
        readToEnd(1)
        if menuState != "open" { app.webViews.firstMatch.tap() }
        XCTAssertTrue(waitForMenu("open"))
        nextButton.tap()
        XCTAssertTrue(text("Fixture chapter 2, paragraph 1.").waitForExistence(timeout: 5),
                      "Next left chapter 1 on screen")
        XCTAssertFalse(text("Fixture chapter 1, paragraph 1.").exists)

        // And once more from chapter 2, since the first Next can take a different path than later ones.
        readToEnd(2)
        if menuState != "open" { app.webViews.firstMatch.tap() }
        XCTAssertTrue(waitForMenu("open"))
        nextButton.tap()
        XCTAssertTrue(text("Fixture chapter 3, paragraph 1.").waitForExistence(timeout: 5),
                      "second Next left chapter 2 on screen")
    }

    /// Bug #3: "A short scroll opens the menu." A small drag must not count as a tap.
    func testShortDragDoesNotOpenMenu() {
        let web = app.webViews.firstMatch
        // Close the menu (it starts open) with a real tap in the middle of the page.
        web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForMenu("closed"), "a tap should close the menu")

        // A short drag, like nudging the page or stopping a fling.
        let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)))
        sleep(1)
        XCTAssertEqual(menuState, "closed", "a short drag opened the menu")
    }
}
