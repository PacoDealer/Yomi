import XCTest

/// Performance gates (S179, RESEARCH §25.10 #11). Each test only MEASURES — XCTest doesn't hand the numbers back to
/// the test. `scripts/perf-gates.sh` runs this class, reads the metrics from the result bundle and fails when one is
/// over its limit in `scripts/perf-gates.json`. Simulator numbers are noisy and not the phone's: the limits catch
/// regressions (a freeze, a page that decodes on the main thread), they are not the real feel on Martin's iPhone.
/// `XCTHitchMetric` (iOS 26) records nothing in the simulator — on a device it adds the hitch ratio; the scroll
/// signpost metric is the one the simulator fills.
final class PerfUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    // MARK: Novel reader

    private func launchNovel() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-yomiReaderFixture", "-novelInfiniteScroll", "<false/>", "-novelReadingMode", "scroll",
                               "-novelMenuTaps", "<integer>1</integer>"]
        app.launch()
        let first = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
                                                                    "Fixture chapter 1, paragraph 1.")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "novel fixture never showed")
        return app
    }

    /// Fast flicks through a 60-paragraph chapter and back — the scrolling Martin does every day.
    func testNovelReaderScrollHitches() {
        let app = launchNovel()
        let web = app.webViews.firstMatch
        measure(metrics: [XCTHitchMetric(application: app), XCTOSSignpostMetric.scrollingAndDecelerationMetric],
                options: options) {
            web.swipeUp(velocity: .fast)
            web.swipeUp(velocity: .fast)
            web.swipeDown(velocity: .fast)
            web.swipeDown(velocity: .fast)
        }
    }

    // MARK: Manga long strip

    /// Webtoon mode on 8 generated 900×16000 pages — Asura's shape, drawn in strips (#190), the memory case of #209.
    func testMangaStripScrollHitchesAndMemory() {
        let app = XCUIApplication()
        app.launchArguments = ["-yomiReaderFixture", "manga", "-readerMode", "Webtoon"]
        app.launch()
        let marker = app.otherElements["reader.mangaPage"]
        let loaded = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value ENDSWITH %@", "/8"),
                                                      evaluatedWith: marker)], timeout: 60)
        XCTAssertEqual(loaded, .completed, "manga fixture never loaded: \(marker.value as? String ?? "?")")
        let window = app.windows.firstMatch
        measure(metrics: [XCTHitchMetric(application: app), XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                          XCTMemoryMetric(application: app)], options: options) {
            for _ in 0..<8 { window.swipeUp(velocity: .fast) }
            for _ in 0..<8 { window.swipeDown(velocity: .fast) }
        }
    }

    // MARK: Launch

    /// Cold launch straight into the novel reader (fixture), until the app answers touches.
    /// On Martin's iPhone the launch metric records nothing (S182 — Xcode 27.1 can't parse the OS build `24A94232`),
    /// so the wall clock of `launch()` is the device gate: it also counts XCTest's terminate + idle wait, a regression
    /// signal rather than the real launch time.
    func testReaderLaunch() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), XCTClockMetric()], options: options) {
            let app = XCUIApplication()
            app.launchArguments = ["-yomiReaderFixture"]
            app.launch()
        }
    }
}
