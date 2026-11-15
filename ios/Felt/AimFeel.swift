/* The aim's feel (index.html section 5's input comment), ported: a tap aims at the spot (a ball's centre within
   tapReach, a full-ball line); a drag anywhere sweeps, the cue turning with the finger round the cue ball (1:1 by
   angle beyond sweepR, about a third of the table's short side, nearer by the tangential motion over sweepR so the gain
   never explodes by the ball), scaled by the finger's smoothed speed (GAIN_SLOW for a slow, deliberate drag up to 1 at
   V_FAST); a finger let go after resting puts back the aim from before its lift jitter (liftAim). The fine wheel turns
   wheelRate(v) per point: 0.005 deg rolled slowly up to 0.024 deg at speed. Speeds in points per ms, as the page's px. */
import Foundation

enum AimFeel {
  static let TAP_SLOP = 10.0, TAP_MAX = 18.0, TAP_MS = 280.0
  static let SWEEP_R = 0.32
  static let GAIN_SLOW = 0.3, V_SLOW = 0.04, V_FAST = 0.35, V_RISE = 20.0, V_TAU = 45.0
  static let HOLD_MS = 300.0, HOLD_SLOP = 3.0
  static let LIFT_MS = 90.0, LIFT_PX = 8.0, PRE_MS = 120.0, PRE_PX = 6.0
  static let WHEEL_SLOW = 0.005 * Double.pi / 180, WHEEL_FAST = 0.024 * Double.pi / 180, WV_SLOW = 0.03, WV_FAST = 0.5
  static let GRAB_SLOP = 3.0

  static func smooth01(_ u0: Double) -> Double { let u = max(0, min(1, u0)); return u * u * (3 - 2 * u) }
  static func sweepGain(_ v: Double) -> Double { GAIN_SLOW + (1 - GAIN_SLOW) * smooth01((v - V_SLOW) / (V_FAST - V_SLOW)) }
  static func wheelRate(_ v: Double) -> Double { WHEEL_SLOW + (WHEEL_FAST - WHEEL_SLOW) * smooth01((v - WV_SLOW) / (WV_FAST - WV_SLOW)) }
  static func wrap(_ a: Double) -> Double { var a = a; while a > .pi { a -= 2 * .pi }; while a < -.pi { a += 2 * .pi }; return a }
  /* the turn for a finger from a to b about the cue ball at c (screen points), before the speed gain */
  static func sweepTurn(_ c: CGPoint, _ a: CGPoint, _ b: CGPoint, R: Double, ballPx: Double) -> Double {
    let ax = Double(a.x - c.x), ay = Double(a.y - c.y), bx = Double(b.x - c.x), by = Double(b.y - c.y)
    if min(hypot(ax, ay), hypot(bx, by)) >= R { return wrap(atan2(by, bx) - atan2(ay, ax)) }
    let mx = (ax + bx) / 2, my = (ay + by) / 2, mr = hypot(mx, my)
    if mr < ballPx { return 0 }
    return (mx * (by - ay) - my * (bx - ax)) / mr / max(mr, R)
  }
  /* the finger's speed, smoothed: up within V_RISE ms, down over V_TAU ms; the first sample as it is */
  static func fingerSpeed(_ s: Double?, _ d: Double, _ dt: Double) -> Double {
    let v = d / max(dt, 4)
    guard let s else { return v }
    return s + (v - s) * (1 - exp(-max(dt, 1) / (v > s ? V_RISE : V_TAU)))
  }
  /* trail: (t ms, aim, x, y), the press first, the last 400 ms kept */
  typealias Trail = [(t: Double, aim: Double, x: Double, y: Double)]
  static func push(_ tr: inout Trail, _ t: Double, _ aim: Double, _ p: CGPoint) {
    tr.append((t, aim, Double(p.x), Double(p.y)))
    while tr.count > 2 && tr[1].t < t - 400 { tr.removeFirst() }
  }
  /* liftAim: a let-go at T after a rest (under PRE_PX in the PRE_MS before the last LIFT_MS) that then moved under
     LIFT_PX: the aim from before the lift */
  static func liftAim(_ tr: Trail, _ T: Double) -> Double? {
    var i = tr.count - 1
    while i >= 0 && tr[i].t > T - LIFT_MS { i -= 1 }
    if i < 0 || i == tr.count - 1 { return nil }
    func path(_ j: Int, _ k: Int) -> Double { var s = 0.0; var n = j; while n < k { s += hypot(tr[n + 1].x - tr[n].x, tr[n + 1].y - tr[n].y); n += 1 }; return s }
    if path(i, tr.count - 1) > LIFT_PX { return nil }
    var j = i + 1
    while j > 0 && tr[j - 1].t >= T - LIFT_MS - PRE_MS { j -= 1 }
    if j <= i && path(max(0, j - 1), i) > PRE_PX { return nil }
    return tr[i].aim
  }
}

/* one table gesture, as the page's gest */
struct AimGesture {
  var t0: Double, p0: CGPoint, last: CGPoint, tLast: Double, at: CGPoint
  var v: Double? = nil, far = 0.0, sweep = false, held = false, shown = false
  var trail: AimFeel.Trail = []
  /* a cue ball in hand grabbed: the offset from the finger to the ball (table metres), live once past GRAB_SLOP */
  var grab: (dx: Double, dy: Double)? = nil, moving = false
  /* the catch-up timer is set (the page's g.wait) */
  var wait = false
  func maybeTap(_ t: Double) -> Bool { !held && !shown && far <= AimFeel.TAP_MAX && t - t0 < AimFeel.TAP_MS }
}
