/* 6b3's roll in (potTick): POT_SLIDE_MS 250 on the screen's clock, the ball on cubic-bezier(.25, .8, .35, 1), the
   window's opacity 0 to 1 by 35%; the easing against the curve sampled by its parameter, and CSS's own ease */
import Foundation
import Testing
@testable import FeltSim

@Suite struct PotSlideTests {
  @Test func slide() {
    #expect(PotRail.SLIDE_MS == 250)
    let a = PotRail.slide(0)!
    #expect(a.e == 0 && a.a == 0)
    #expect(PotRail.slide(250) == nil && PotRail.slide(400) == nil)
    #expect(PotRail.slide(87.5)!.a == 1 && abs(PotRail.slide(43.75)!.a - 0.5) < 1e-12)
    #expect(PotRail.slide(249.99)!.e > 0.9999)
    var last = -1.0
    for ms in stride(from: 0.0, to: 250, by: 1) { let e = PotRail.slide(ms)!.e; #expect(e >= last, "monotonic at \(ms)"); last = e }
    /* the curve sampled by its parameter u: (x(u), y(u)); every x's y within the sampling's error */
    func bez(_ p1: Double, _ p2: Double, _ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * p1 + 3 * (1 - u) * u * u * p2 + u * u * u }
    for i in 0...20000 {
      let u = Double(i) / 20000, x = bez(0.25, 0.35, u), y = bez(0.8, 1, u)
      if x < 1 { #expect(abs(PotRail.slide(x * 250)!.e - y) < 1e-4, "u \(u)") }
    }
    /* CSS ease (cubic-bezier(.25, .1, .25, 1)) at 0.5, and the linear curve */
    #expect(abs(PotRail.bezier(0.25, 0.1, 0.25, 1, 0.5) - 0.8024033877399112) < 1e-6)
    for x in [0.1, 0.33, 0.5, 0.9] { #expect(abs(PotRail.bezier(0, 0, 1, 1, x) - x) < 1e-7) }
  }
}
