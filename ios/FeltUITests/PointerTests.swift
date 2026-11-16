/* An iPad's pointer through the real table (page 5's input comment): hover aims, a click on the cloth holds the aim
   (no later hover moves it), a right click lets it go, a pointer sweep let go holds, a finger's tap never holds; the
   first hover shows the tip. Run on an iPad simulator; `-felt-aimprobe` reads the aim and its hold back. */
import XCTest

final class PointerTests: XCTestCase {
  @MainActor func testPointerHoldsItsAim() throws {
    guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("a pointer is an iPad's") }
    let app = XCUIApplication()
    /* felt.mouseTip.v1 unreadable for this launch: the tip unseen */
    app.launchArguments = ["-felt-game", "8-Ball", "-felt-aimprobe", "-felt.mouseTip.v1", "x"]
    app.launch()
    let table = app.otherElements["table"], probe = app.staticTexts["aim-probe"]
    XCTAssertTrue(table.waitForExistence(timeout: 10))
    XCTAssertTrue(probe.waitForExistence(timeout: 5))
    sleep(1)
    func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { table.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
    func state() -> (String, Double) {
      let v = (probe.value as? String ?? "").split(separator: " ")
      return (v.first.map(String.init) ?? "", v.count > 1 ? Double(v[1]) ?? .nan : .nan)
    }
    /* hover aims, free; the tip shows on the first hover */
    at(0.3, 0.25).hover(); sleep(1)
    XCTAssertTrue(app.staticTexts["Aiming With a Mouse"].waitForExistence(timeout: 3), "the first hover shows the tip")
    let tip = XCTAttachment(screenshot: app.screenshot()); tip.name = "pointer-tip"; tip.lifetime = .keepAlways; add(tip)
    let (s1, a1) = state()
    XCTAssertEqual(s1, "free")
    at(0.75, 0.3).hover(); sleep(1)
    let (s2, a2) = state()
    XCTAssertEqual(s2, "free")
    XCTAssertGreaterThan(abs(a2 - a1), 0.05, "hover aims")
    /* a click on the cloth aims there and holds it */
    at(0.6, 0.15).click(); sleep(1)
    let (s3, a3) = state()
    XCTAssertEqual(s3, "held", "a click holds the aim")
    XCTAssertGreaterThan(abs(a3 - a2), 0.01, "the click aims")
    let held = XCTAttachment(screenshot: app.screenshot()); held.name = "pointer-held"; held.lifetime = .keepAlways; add(held)
    /* no later hover breaks it */
    at(0.2, 0.3).hover(); sleep(1)
    at(0.8, 0.2).hover(); sleep(1)
    let (s4, a4) = state()
    XCTAssertEqual(s4, "held")
    XCTAssertEqual(a4, a3, accuracy: 1e-4, "a held aim stays where it was clicked")
    /* a right click lets go; hover aims again */
    at(0.8, 0.2).rightClick(); sleep(1)
    XCTAssertEqual(state().0, "free", "a right click lets go")
    at(0.3, 0.2).hover(); sleep(1)
    XCTAssertGreaterThan(abs(state().1 - a4), 0.01, "hover aims again once let go")
    /* a pointer sweep let go holds too */
    at(0.25, 0.2).click(forDuration: 0.05, thenDragTo: at(0.7, 0.25)); sleep(1)
    XCTAssertEqual(state().0, "held", "a pointer sweep let go holds")
    /* a finger's tap aims and never holds */
    at(0.6, 0.2).tap(); sleep(1)
    XCTAssertEqual(state().0, "free", "a finger's tap never holds")
  }
}
