#if os(tvOS)
import XCTest

// MARK: - TVShortsDownNavigationUITests
//
// Regression test: pressing DOWN from the Shorts row must reach the video grid.
//
// Navigation path (Home tab, Shorts visible):
//   tab-bar  →(↓1)→  shorts-row  →(↓2)→  video-grid
//
// Run:
//   xcodebuild test -workspace SmartTube.xcworkspace -scheme "Smart Tube" \
//     -destination "id=<simulator-udid>" \
//     -only-testing:SmartTubeTVUITests/TVShortsDownNavigationUITests

final class TVShortsDownNavigationUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    // MARK: - Helpers

    private func focusedIdentifier() -> String? {
        let pred = NSPredicate(format: "hasFocus == true")
        return app.descendants(matching: .any).matching(pred).firstMatch.identifier.nilIfEmpty
    }

    private func anyFocused(prefix: String) -> Bool {
        let pred = NSPredicate(format: "identifier BEGINSWITH '\(prefix)' AND hasFocus == true")
        return app.descendants(matching: .any).matching(pred).count > 0
    }

    private func snap(_ label: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = label
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func treeSnapshot(_ label: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = label
        tree.lifetime = .keepAlways
        add(tree)
    }

    // MARK: - Test

    /// Presses DOWN twice from the tab bar and verifies focus reaches the video grid.
    /// The Home chip bar is gone, so the first press lands on Shorts and the second on the grid.
    func test_TwoDownPresses_LandOnVideoGrid() throws {
        // Wait for home feed to be ready.
        let chipBar = app.descendants(matching: .any)["home.feed"]
        guard chipBar.waitForExistence(timeout: 20) else {
            try captureAndSkip("home.feed did not appear — Home tab not loaded", in: app)
        }

        // On tvOS the outer HStack's .accessibilityIdentifier("home.shortsRow")
        // propagates to each Button child — so we look for that, not "shorts.card.*".
        let shortsPred = NSPredicate(format: "identifier == 'home.shortsRow' AND elementType == 9")
        let shortsCards = app.descendants(matching: .any).matching(shortsPred)
        let shortsResult = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: shortsCards)],
            timeout: 30
        )

        // Capture initial state and accessibility tree before attempting navigation.
        snap("0-initial")
        treeSnapshot("accessibility-tree-initial")

        let shortsPresent = shortsResult == .completed
        XCTContext.runActivity(named: "Shorts present: \(shortsPresent) (waiter=\(shortsResult.rawValue))") { _ in }

        guard shortsPresent else {
            try captureAndSkip(
                "No 'home.shortsRow' buttons found after 30s — Shorts not in feed; captured initial state above",
                in: app)
        }

        // ── DOWN 1 ── tab bar → Shorts row
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.8)
        snap("1-after-first-down")
        let focused1 = focusedIdentifier() ?? "<nothing>"
        XCTContext.runActivity(named: "After DOWN 1 — focused: \(focused1)") { _ in }

        // ── DOWN 2 ── Shorts row → video grid
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.8)
        snap("2-after-second-down")
        let focused2 = focusedIdentifier() ?? "<nothing>"
        XCTContext.runActivity(named: "After DOWN 2 — focused: \(focused2)") { _ in }

        treeSnapshot("accessibility-tree-after-2-downs")

        let shortsStillFocused: Bool = {
            let pred = NSPredicate(format: "identifier == 'home.shortsRow' AND hasFocus == true")
            return app.descendants(matching: .any).matching(pred).count > 0
        }()
        XCTAssertFalse(
            shortsStillFocused,
            "A Shorts button (home.shortsRow) still has focus after 2 DOWNs. "
                + "focused1=\(focused1) focused2=\(focused2)"
        )
        XCTAssertTrue(
            anyFocused(prefix: "video.card."),
            "No video.card.* gained focus after 2 DOWNs. "
                + "focused1=\(focused1) focused2=\(focused2)"
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
