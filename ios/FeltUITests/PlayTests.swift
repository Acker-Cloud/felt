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

  /* F8 by real touch: in an exhibition (both players the CPU) a tap on the table during the break's think hurries it (the
     page's cpuSkip): the wait cut, the cue's turn and pull 250 ms, so the break is rolling well inside the unhurried
     think (at least 900 x 0.85 ms) and swing (900 ms). The stroke's think and skip are read from the cpu-probe
     (-felt-aimprobe); the log (-felt-touchlog) records the tap ("cpuskip") and the stroke ("cpustroke think <s> skip 1") */
  @MainActor func testCpuSkip() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-felt-exhibit", "8-Ball", "-felt-touchlog", "-felt-aimprobe"]
    app.launch()
    let table = app.otherElements["table"], probe = app.staticTexts["cpu-probe"]
    XCTAssertTrue(table.waitForExistence(timeout: 10))
    table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
    expectation(for: NSPredicate(format: "value BEGINSWITH %@", "think"), evaluatedWith: probe)
    waitForExpectations(timeout: 10)
    let v = probe.value as? String ?? ""
    let note = XCTAttachment(string: v); note.name = "cpu-skip"; note.lifetime = .keepAlways; add(note)
    XCTAssertTrue(v.contains(" skip 1 "), "the tap hurried the CPU's break: \(v)")
    /* hurried: from the tap the stroke follows within the hurried swing (250 ms, a frame's slack), never the unhurried
       wait and 900 ms swing. The tap's moment is the think clock's at the tap ("tap <s>"), so the harness's own delay in
       delivering it (seconds on a Debug build) does not count */
    let f = v.split(separator: " "), think = Double(f[1]) ?? 9, tap = f.count > 5 ? Double(f[5]) ?? -1 : -1
    XCTAssertGreaterThanOrEqual(tap, 0, "the tap landed in the think: \(v)")
    XCTAssertLessThanOrEqual(think - tap, 0.25 + 0.02, "the stroke followed the tap within the hurried swing: \(v)")
  }

  /* the cue ball in hand carried in 3D (4o, v3Table): the press on the ball as the camera draws it, a carry, the let-go.
     The camera sits behind the ball at the default pitch and distance (forced: a string in the argument domain reads as
     unset), so the ball is at the stage's middle across and, down, at the angle between the pitch and the line to the
     target (v3Pose: T ahead AHEAD x dist x cos pitch at R x (1 - AHEAD)), F the focal length at FOV 21 x 24 degrees.
     The log (-felt-touchlog) records the grab and every placement */
  @MainActor func testHandIn3D() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-felt-game", "8-Ball", "-felt-touchlog", "-felt.settings.view", "3d", "-felt.settings.viewPitch", "x", "-felt.settings.viewDist", "x"]
      + (ProcessInfo.processInfo.environment["FELT_ARGS"].map { $0.split(separator: " ").map(String.init) } ?? [])
    app.launch()
    let table = app.otherElements["table"]
    XCTAssertTrue(table.waitForExistence(timeout: 10))
    sleep(2)
    let W = Double(table.frame.width), H = Double(table.frame.height), R = 0.05715 / 2, p = 24 * Double.pi / 180, d = 1.1
    let eh = max(R + sin(p) * d, R * 1.42 + 0.05), back = cos(p) * d, ahead = 0.8 * d * cos(p)
    let down = atan2(eh - R, back) - atan2(eh - R * 0.2, back + ahead), F = min(W / (2 * tan(21 * Double.pi / 180)), H / (2 * tan(24 * Double.pi / 180)))
    let at = CGVector(dx: W / 2, dy: H / 2 + F * tan(down))
    let o = table.coordinate(withNormalizedOffset: .zero), ball = o.withOffset(at)
    let pre = XCTAttachment(screenshot: app.screenshot()); pre.name = "hand3d-before"; pre.lifetime = .keepAlways; add(pre)
    ball.press(forDuration: 0.15, thenDragTo: o.withOffset(CGVector(dx: at.dx + 50, dy: at.dy - 40)), withVelocity: 120, thenHoldForDuration: 0.4)
    sleep(1)
    let post = XCTAttachment(screenshot: app.screenshot()); post.name = "hand3d-after"; post.lifetime = .keepAlways; add(post)
    /* a tap on the cloth ahead aims there through the camera (v3Table), never shoots */
    o.withOffset(CGVector(dx: W * 0.3, dy: H * 0.35)).tap()
    sleep(1)
    XCTAssertEqual(app.otherElements["power"].value as? String, "0 percent")
  }
}
