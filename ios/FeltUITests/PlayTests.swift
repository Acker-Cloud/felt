/* Real input on the simulator: open 8-ball, pull the power bar and let go, and the rack breaks.
   Also pins the page's rule that a drag on the table never shoots. */
import XCTest

final class PlayTests: XCTestCase {
  @MainActor func testBreakFromThePowerBar() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-felt-game", "8-Ball"]
    app.launch()
    let table = app.otherElements["table"], bar = app.otherElements["power"]
    XCTAssertTrue(table.waitForExistence(timeout: 10))
    XCTAssertTrue(bar.waitForExistence(timeout: 5))
    /* a drag across the table aims, it never shoots */
    table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(forDuration: 0.1, thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
    XCTAssertEqual(bar.value as? String, "0 percent")
    
    /* pull the bar most of the way and let go */
    let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: bar.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
    XCTAssertTrue(NSPredicate(format: "value == %@", "Rolling").evaluate(with: bar), "the bar's release shoots: \(String(describing: bar.value))")
    let mid = XCTAttachment(screenshot: app.screenshot()); mid.name = "break-rolling"; mid.lifetime = .keepAlways; add(mid)
    /* the break comes to rest within the sim's 60 s */
    expectation(for: NSPredicate(format: "value == %@", "0 percent"), evaluatedWith: bar)
    waitForExpectations(timeout: 65)
    let end = XCTAttachment(screenshot: app.screenshot()); end.name = "break-rest"; end.lifetime = .keepAlways; add(end)
  }
}
