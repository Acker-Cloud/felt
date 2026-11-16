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

  /* 5c at 10-ball past the break: the bar says Call your shot and does not arm; a tap on it opens the call's menu with
     the six pockets, a tap outside closes it, and a pull with no call opens it on the let-go instead of shooting */
  @MainActor func testCallMenu() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-felt-game", "10-Ball", "-felt-pots", "2,5"]
    app.launch()
    let bar = app.otherElements["power"]
    XCTAssertTrue(bar.waitForExistence(timeout: 10))
    XCTAssertEqual(bar.value as? String, "Call your shot, 0 percent")
    bar.tap()
    let pk = app.buttons["pocket-0"]
    XCTAssertTrue(pk.waitForExistence(timeout: 3), "a tap on the bar opens the call's menu")
    XCTAssertEqual((0..<6).filter { app.buttons["pocket-\($0)"].exists }.count, 6)
    let open = XCTAttachment(screenshot: app.screenshot()); open.name = "call-menu"; open.lifetime = .keepAlways; add(open)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    XCTAssertTrue(pk.waitForNonExistence(timeout: 3), "a tap outside closes it")
    bar.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).press(forDuration: 0.1, thenDragTo: bar.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
    XCTAssertTrue(pk.waitForExistence(timeout: 3), "a pull the call refuses opens the menu")
    XCTAssertEqual(bar.value as? String, "Call your shot, 0 percent", "and never shoots")
  }

  /* real touch through the table's gesture, logged (-felt-touchlog): a slow aiming drag, then one carrying the cue
     ball in hand on the break. The log is read from the app's tmp by the harness */
  @MainActor func testTouchLog() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-felt-game", "8-Ball", "-felt-touchlog"] + (ProcessInfo.processInfo.environment["FELT_ARGS"].map { $0.split(separator: " ").map(String.init) } ?? [])
    app.launch()
    let table = app.otherElements["table"]
    XCTAssertTrue(table.waitForExistence(timeout: 10))
    sleep(1)
    table.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(forDuration: 0.05, thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35)), withVelocity: 150, thenHoldForDuration: 0.3)
    sleep(1)
    if (ProcessInfo.processInfo.environment["FELT_ARGS"] ?? "").contains("3d") { table.pinch(withScale: 0.6, velocity: -0.8); sleep(1) }
  }
}
