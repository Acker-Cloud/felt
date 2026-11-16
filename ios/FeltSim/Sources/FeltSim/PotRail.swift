/* index.html 6b3's geometry, line for line: potPlan (the windows' slots: top-down through the fitted view, in 3D the
   long rails laid out as upright), potPlace (in 3D a slot on the rail top projected: the largest circle it holds) and
   potCovered in 3D (the cue, the loupe or a ball over a window). DOM-free: the caller gives the band (cushionDepth,
   RAIL), the sights (railSights) and the view; screen px are the box's. */
import Foundation

private typealias M = JSMath

public enum PotRail {
  public static let GAP = 3.0, SIGHT_PAD = 3.0, PER_RAIL = 8, RAIL_PAD = 4.0
  /* a slot: its place (CSS px of the plan's view), its spot on the table and the half length along the rail a window
     may take in 3D (room, metres) */
  public struct Slot: Sendable { public let x, y: Double, t: [Double], room: Double }
  /* per side (0 the screen's left, 1 its right) bottom to top; s the window, ball the ball in it (px), up the rail's up
     as a table direction, half the band's half width (metres) */
  public struct Plan: Sendable { public let sides: [[Slot]], s, ball: Double, up: [Double], k, half: Double }

  /* potPlan: live (3D) lays the long rails out upright at the fitted scale k from (0, 0); top-down the view (k, ox, oy,
     portrait). screen: top-down, only the slots wholly on it (nil: every one) */
  public static func plan(_ s: Sim, k: Double, ox: Double, oy: Double, portrait: Bool, live: Bool, rail: Double, co: Double, sights: [[Double]], screen: (w: Double, h: Double)? = nil) -> Plan {
    let td = !live, Bk = k, Bp = td ? portrait : true, Bx = td ? ox : 0, By = td ? oy : 0, TL = s.TL, TW = s.TW
    let wk = (rail - co) * Bk, mid = (co + rail) / 2
    func at(_ x: Double, _ y: Double) -> [Double] { Bp ? [Bx + y * Bk, By + (TL - x) * Bk] : [Bx + x * Bk, By + y * Bk] }
    let a = at(0, 0), b = at(TL, TW), left = M.min(a[0], b[0]), right = M.max(a[0], b[0]), top = M.min(a[1], b[1]), bottom = M.max(a[1], b[1])
    let sz = M.max(9, (wk - 2).rounded(.down)), ball = sz - 3
    /* railHoles: each pocket's hole and jaws (RAIL_PAD), each sight (POT_SIGHT_PAD) */
    var holes: [[Double]] = []
    func box(_ pts: [[Double]], _ pad: Double) {
      let q = pts.map { at($0[0], $0[1]) }, xs = q.map { $0[0] }, ys = q.map { $0[1] }
      holes.append([xs.min()!, xs.max()!, ys.min()!, ys.max()!, pad])
    }
    for (i, p) in s.POCKETS.enumerated() {
      let r = s.POCKET_R[i]
      var pts = [[p[0] - r, p[1]], [p[0] + r, p[1]], [p[0], p[1] - r], [p[0], p[1] + r]]
      if s.MOUTHS.indices.contains(i) { for j in s.MOUTHS[i] { pts.append(j.p); pts.append(j.e) } }
      box(pts, RAIL_PAD)
    }
    for q in sights { box([[q[0] - q[2], q[1] - q[3]], [q[0] + q[2], q[1] - q[3]], [q[0] + q[2], q[1] + q[3]], [q[0] - q[2], q[1] + q[3]]], SIGHT_PAD) }
    func toT(_ sx: Double, _ sy: Double) -> [Double] { Bp ? [TL - (sy - By) / Bk, (sx - Bx) / Bk] : [(sx - Bx) / Bk, (sy - By) / Bk] }
    let up: [Double] = Bp ? [1, 0] : [0, -1]
    let sides: [[Slot]] = [left - mid * Bk, right + mid * Bk].map { cx in
      /* the gaps along the band, bottom first */
      var gaps = [[top, bottom]]
      for h in holes {
        if h[1] < cx - wk / 2 || h[0] > cx + wk / 2 { continue }
        gaps = gaps.flatMap { [[$0[0], M.min($0[1], h[2] - h[4])], [M.max($0[0], h[3] + h[4]), $0[1]]] }.filter { $0[1] - $0[0] >= sz }
      }
      gaps.sort { $0[0] > $1[0] }
      let cap = gaps.map { Int((($0[1] - $0[0] + GAP) / (sz + GAP)).rounded(.down)) }
      var m = 1
      while m < Swift.max(1, cap.max() ?? 1) && cap.reduce(0, { $0 + Swift.min(m, $1) }) < PER_RAIL { m += 1 }
      var slots: [Slot] = []
      for (i, g) in gaps.enumerated() {
        let kk = Swift.min(m, cap[i]), run = Double(kk) * sz + Double(kk - 1) * GAP
        /* room: the half length along the rail a window may take in 3D (its gap's, or its share of a packed gap) */
        let room = (kk > 1 ? (sz + GAP) / 2 : (g[1] - g[0]) / 2) / Bk
        for j in 0..<Swift.max(0, kk) {
          let y = (g[0] + g[1]) / 2 + run / 2 - sz / 2 - Double(j) * (sz + GAP)
          if !td || screen.map({ cx - sz / 2 >= 0 && cx + sz / 2 <= $0.w && y - sz / 2 >= 0 && y + sz / 2 <= $0.h }) ?? true { slots.append(Slot(x: cx, y: y, t: toT(cx, y), room: room)) }
        }
      }
      return slots
    }
    return Plan(sides: sides, s: sz, ball: ball, up: up, k: Bk, half: M.max(0.3, wk / 2 - 1) / Bk)
  }

  /* potGame: the windows (and #potSay) at all: 8, 9, 10-ball and Chinese 8-ball, a game with no mode or practice; never
     a trick shot, a drill, the lesson or a tutorial */
  public static let KINDS = ["8", "9", "10", "heyball"]
  public static func on(kind: String, mode: String?, tutorial: Bool, lesson: Bool) -> Bool {
    KINDS.contains(kind) && !tutorial && !lesson && (mode == nil || mode == "practice")
  }
  /* potTick's pw.order: the balls down (off) in pot order: one back on the table leaves it, the new ones join at the end
     (two in one look by number) */
  public static func order(_ prev: [Int], off: [Int]) -> [Int] {
    var o = prev.filter { off.contains($0) }
    for n in off.filter({ !o.contains($0) }).sorted() { o.append(n) }
    return o
  }
  /* potSeats: which window each ball down goes in, (n, side, index) in pot order. counts: each side's slots. 8-ball
     (is8): solids up the left, stripes up the right, the 8 up its potter's group's side (eightRight: stripes); else
     in pot order up the left, then the right. A ball with no slot left has no window (its number is still read) */
  public static func seats(_ order: [Int], eight: Bool, eightRight: Bool, counts: [Int]) -> [(n: Int, side: Int, i: Int)] {
    var out: [(n: Int, side: Int, i: Int)] = []
    if eight {
      var n8 = [0, 0]
      for n in order {
        let side = n == 8 ? (eightRight ? 1 : 0) : n > 8 ? 1 : 0
        if n8[side] < counts[side] { out.append((n, side, n8[side])); n8[side] += 1 }
      }
    } else {
      for (i, n) in order.enumerated() {
        if i < counts[0] { out.append((n, 0, i)) } else if i - counts[0] < counts[1] { out.append((n, 1, i - counts[0])) }
      }
    }
    return out
  }
  /* potTick's vis: the windows show in 3D, or top-down while the 2D camera is not zoomed (cam.z > 1.02: the rails are off
     its window). #potSay's words are written before this and hold either way */
  public static func windows(live: Bool, z: Double) -> Bool { live || !(z > 1.02) }
  /* top-down: where each seated ball's window stands in the plan's view, per side ([x0, y0, x1, y1]) */
  public static func planned(_ P: Plan, _ seats: [(n: Int, side: Int, i: Int)]) -> [[[Double]]] {
    var out: [[[Double]]] = [[], []]
    for q in seats { let sl = P.sides[q.side][q.i]; out[q.side].append([sl.x - P.s / 2, sl.y - P.s / 2, sl.x + P.s / 2, sl.y + P.s / 2]) }
    return out
  }
  /* #potSay's place for VoiceOver ([x0, y0, x1, y1], nil: nowhere to put it). The page's is visually hidden and holds
     every ball down whatever the windows show (zoomed, a ball still dropping, a window faded or off the stage); here an
     element needs a frame: the windows shown on the first side showing any (never across the table between the rails),
     else where the balls' windows are planned (the fitted view's slots: zoomed, still dropping) */
  public static func sayBox(shown: [[[Double]]], planned: [[[Double]]]) -> [Double]? {
    for list in [shown[0], shown[1], planned[0], planned[1]] where !list.isEmpty {
      return list.dropFirst().reduce(list[0]) { [M.min($0[0], $1[0]), M.min($0[1], $1[1]), M.max($0[2], $1[2]), M.max($0[3], $1[3])] }
    }
    return nil
  }

  /* the roll in (potTick's animate): over POT_SLIDE_MS on the screen's clock the ball comes up the rail from the window
     below and its number round to the front, both on cubic-bezier(.25, .8, .35, 1), while the window's opacity goes 0
     to 1 by 35% of the way (linear). ms since the window first showed; e the eased progress (the ball's offset is
     (1 - e) of the way back), a the window's opacity; nil once it is over */
  public static let SLIDE_MS = 250.0
  public static func slide(_ ms: Double) -> (e: Double, a: Double)? {
    guard ms < SLIDE_MS else { return nil }
    let t = M.max(0, ms) / SLIDE_MS
    return (bezier(0.25, 0.8, 0.35, 1, t), M.min(1, t / 0.35))
  }
  /* CSS cubic-bezier(x1, y1, x2, y2) at progress x: the curve's parameter for x (Newton's method, then bisection, as
     the browsers' UnitBezier), its y there */
  public static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
    func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    func sy(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
    let eps = 1e-7
    var t = x, found = false
    for _ in 0..<8 {
      let e = sx(t) - x
      if abs(e) < eps { found = true; break }
      let d = dx(t)
      if abs(d) < 1e-6 { break }
      t = t - e / d
    }
    if !found {
      var lo = 0.0, hi = 1.0
      t = x
      while lo < hi {
        let v = sx(t)
        if abs(v - x) < eps { break }
        if x > v { lo = t } else { hi = t }
        t = (hi - lo) / 2 + lo
        if hi - lo < 1e-12 { break }
      }
    }
    return sy(t)
  }

  /* potPlace in 3D: the slot on the rail's top (z, cushionTop) as the camera projects it, its share of the gap along the
     rail and the wood band across; [x, y, s] the largest circle the quad holds, nil when under 7 px or behind the eye */
  public static func place(_ P: Plan, _ slot: Slot, _ C: V3.Cam, _ box: V3.Box, z: Double) -> [Double]? {
    let ha = slot.room, hc = P.half, ux = P.up[0], uy = P.up[1], vx = -uy, vy = ux, tx = slot.t[0], ty = slot.t[1]
    let q = [[-1.0, -1], [1, -1], [1, 1], [-1, 1]].map { V3.proj(C, box, tx + ux * $0[0] * ha + vx * $0[1] * hc, ty + uy * $0[0] * ha + vy * $0[1] * hc, z) }
    guard let c = V3.proj(C, box, tx, ty, z), q.allSatisfy({ $0 != nil }) else { return nil }
    let p = q.map { $0! }
    var A = 0.0
    for i in 0..<4 { let r = p[(i + 1) % 4]; A = A + p[i][0] * r[1] - r[0] * p[i][1] }
    let area = abs(A) / 2
    let e1 = M.hypot(p[1][0] - p[0][0], p[1][1] - p[0][1]), e2 = M.hypot(p[3][0] - p[0][0], p[3][1] - p[0][1])
    let d = M.min(M.min(area / M.max(e1, 1e-6), area / M.max(e2, 1e-6)), P.s * 1.6) - 1
    return d >= 7 ? [c[0], c[1], d.rounded(.down)] : nil
  }

  /* potCovered in 3D: a window at (x, y), radius r (px) under the loupe (shown), the cue (its tip and axis, len long)
     or a ball on the table (x, y and its bottom's height) */
  public static func covered(_ x: Double, _ y: Double, _ r: Double, loupe: (x: Double, y: Double, r: Double)?, cue: (tip: [Double], ax: [Double])?, cueLen: Double,
                             balls: [(x: Double, y: Double, z: Double)], _ C: V3.Cam, _ box: V3.Box, R: Double) -> Bool {
    if let L = loupe, M.hypot(x - L.x, y - L.y) < L.r + r + 2 { return true }
    func near(_ p: [Double], _ q: [Double], _ w: Double) -> Bool {
      let dx = q[0] - p[0], dy = q[1] - p[1], dd = dx * dx + dy * dy, u = clamp(((x - p[0]) * dx + (y - p[1]) * dy) / (dd != 0 ? dd : 1), 0, 1)
      return M.hypot(x - p[0] - dx * u, y - p[1] - dy * u) < w
    }
    if let cu = cue {
      let tip = cu.tip, ax = cu.ax
      var pts: [[Double]] = []
      for i in 0...8 { let s = cueLen * Double(i) / 8; if let p = V3.proj(C, box, tip[0] + ax[0] * s, tip[1] + ax[1] * s, -(tip[2] + ax[2] * s)) { pts.append(p) } }
      for i in pts.indices.dropFirst() where near(pts[i - 1], pts[i], r + 4 + 0.03 * C.F / M.max(0.2, pts[i][2])) { return true }
    }
    for b in balls {
      guard let c = V3.proj(C, box, b.x, b.y, R + b.z) else { continue }
      let e = V3.proj(C, box, b.x + R, b.y, R + b.z)
      /* the centre can project while the edge does not (a ball right by a low camera): its size from the depth alone */
      if M.hypot(x - c[0], y - c[1]) < r + 2 + M.max(e.map { M.hypot($0[0] - c[0], $0[1] - c[1]) } ?? 0, R * C.F / c[2]) { return true }
    }
    return false
  }
}
