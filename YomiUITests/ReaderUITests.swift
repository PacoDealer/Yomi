import XCTest

/// Novel reader regressions from Martin's S128 field report (ROADMAP "S128", RESEARCH §23.1).
/// Runs against the Debug app's `-yomiReaderFixture`: a 3-chapter offline novel opened straight in the reader.
final class ReaderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    /// `-key value` launch arguments land in UserDefaults' argument domain, which AppSettings reads. Values are
    /// parsed as plist: "NO" would arrive as a string (and `as? Bool` ignores it), `<false/>` as a boolean.
    private func launch(infiniteScroll: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-yomiReaderFixture", "-novelInfiniteScroll", infiniteScroll ? "<true/>" : "<false/>",
                               "-novelSwipeChapters", "<true/>", "-novelMenuTaps", "<integer>1</integer>"]
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

    /// The web view's accessibility tree can lag a DOM replacement by a moment.
    private func gone(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)],
                       timeout: timeout) == .completed
    }

    private func closeMenu() {
        app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForMenu("closed"), "a tap should close the menu")
    }

    /// Scrolls to the end of the chapter, like reading it: this fills the preload cache (≥70 %) and marks it read.
    private func readToEnd(_ chapter: Int) {
        for _ in 0..<12 where !text("Fixture chapter \(chapter), paragraph 60.").isHittable {
            app.webViews.firstMatch.swipeUp(velocity: .fast)
        }
        sleep(1)
    }

    /// Bug #1: "Next chapter does nothing — has to quit the reader and reopen."
    /// Reads to the end first, as Martin does: at ≥70 % the next chapter is preloaded, so Next is a cache hit.
    func testNextChapterShowsNewText() {
        launch(infiniteScroll: false)
        readToEnd(1)
        if menuState != "open" { app.webViews.firstMatch.tap() }
        XCTAssertTrue(waitForMenu("open"))
        nextButton.tap()
        XCTAssertTrue(text("Fixture chapter 2, paragraph 1.").waitForExistence(timeout: 5),
                      "Next left chapter 1 on screen")
        XCTAssertTrue(gone(text("Fixture chapter 1, paragraph 1.")), "chapter 1 is still in the page after Next")

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
        launch(infiniteScroll: true)
        let web = app.webViews.firstMatch
        closeMenu()

        // A short drag, like nudging the page or stopping a fling.
        let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)))
        sleep(1)
        XCTAssertEqual(menuState, "closed", "a short drag opened the menu")

        // A real tap still opens it.
        web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForMenu("open"), "a tap should open the menu")
    }

    /// Request #2: scrolling past the end of a chapter continues into the next one.
    func testInfiniteScrollContinuesIntoNextChapter() {
        launch(infiniteScroll: true)
        closeMenu()
        readToEnd(1)
        for _ in 0..<6 where !text("Fixture chapter 2, paragraph 1.").exists {
            app.webViews.firstMatch.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(text("Fixture chapter 2, paragraph 1.").waitForExistence(timeout: 5),
                      "chapter 2 was never appended below chapter 1")
        XCTAssertEqual(menuState, "closed", "scrolling opened the menu")
    }

    /// Request #4: swipe left = next chapter, swipe right = previous.
    func testSwipeChangesChapter() {
        launch(infiniteScroll: false)
        closeMenu()
        app.webViews.firstMatch.swipeLeft()
        XCTAssertTrue(text("Fixture chapter 2, paragraph 1.").waitForExistence(timeout: 5), "swipe left didn't open chapter 2")
        XCTAssertTrue(gone(text("Fixture chapter 1, paragraph 1.")), "chapter 1 is still in the page after the swipe")
        app.webViews.firstMatch.swipeRight()
        XCTAssertTrue(text("Fixture chapter 1, paragraph 1.").waitForExistence(timeout: 5), "swipe right didn't go back")
        XCTAssertEqual(menuState, "closed", "a swipe opened the menu")
    }

    /// S129 a11y bug: the hidden menu's controls stayed in the accessibility tree.
    func testHiddenMenuLeavesAccessibilityTree() {
        launch(infiniteScroll: true)
        XCTAssertTrue(nextButton.exists)
        closeMenu()
        XCTAssertFalse(nextButton.exists, "hidden menu is still reachable by VoiceOver")
    }
}
