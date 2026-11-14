/* index.html 4d's geometry and shot preview (aimSweep, aimTrace, previewStart, previewRun), DOM-free,
   line for line. The preview runs the same newTable, strike and stepTable a shot runs, so its paths are
   the shot's own. The page runs it in slices of a few ms a frame; here it runs whole (Swift does
   PV_CAP steps in well under a frame). GuideTests compares both against the page's own functions. */
import Foundation

private typealias M = JSMath

public let PV_CAP = 4800, PV_SLOW = 0.03, PV_GAP = 0.01
public let PV_FULL = [0.7, 2.0], PV_SHORT = [0.2, 0.2], PV_CAROM = [12.0, 0.6], PV_TAIL = 0.25
public let PV_CAROM_CAP = 3 * PV_CAP

public struct AimHit {
  public var t: Double, kind: String, ball: Ball?, nx = 0.0, ny = 0.0, k = -1
}

public final class Preview {
  public let lens: [Double]
  let full: Tab, solo: Tab, others: [Ball]
  var tab: Tab, ball: Ball, safe = 0
  public var s = 0
  var ev = false, cueDone = false, cl = 0.0
  var o: Ball? = nil
  var objDone = true, ol = 0.0, odx = 0.0, ody = 0.0
  public var cue: [[Double]] = [], obj: [[Double]]? = nil, first: Int? = nil, crossed: Bool
  public var cuePot = -1, objPot = -1, objHit = false, cueStop = false, done = false
  public var air: [[Double]] = [], airDone = false
  public var carom = 0, cc = 0, tail = 0.0, bounces: [[Double]]? = nil
  init(lens: [Double], full: Tab, solo: Tab, crossed: Bool) {
    self.lens = lens; self.full = full; self.solo = solo; tab = solo; ball = solo.balls[0]; self.crossed = crossed
    others = full.balls.filter { $0.n != full.cue }
  }
}

extension Sim {
  /* the first point at which cushion segment s stops a ball sent from (x, y) along unit (dx, dy) */
  public func aimSweep(_ s: [Double], _ x: Double, _ y: Double, _ dx: Double, _ dy: Double) -> (t: Double, nx: Double, ny: Double)? {
    let R = BALL_R, ex = s[2] - s[0], ey = s[3] - s[1], L = M.hypot(ex, ey)
    var best: (t: Double, nx: Double, ny: Double)? = nil
    if L > 1e-9 {
      let ux = ex / L, uy = ey / L, mx = -uy, my = ux, dm = dx * mx + dy * my, pm = (x - s[0]) * mx + (y - s[1]) * my, side: Double = pm > 0 ? 1 : -1
      if abs(dm) > 1e-9 && pm * side >= R - 1e-9 {
        let t = (side * R - pm) / dm, a = (x + dx * t - s[0]) * ux + (y + dy * t - s[1]) * uy
        if t >= 0 && a >= 0 && a <= L { best = (t, mx * side, my * side) }
      }
    }
    for (cx, cy) in [(s[0], s[1]), (s[2], s[3])] {
      let ox = cx - x, oy = cy - y, p = ox * dx + oy * dy, q = ox * ox + oy * oy - p * p
      if p > 0 && q < R * R {
        let t = p - M.sqrt(R * R - q)
        if t >= 0 && (best == nil || t < best!.t) { best = (t, (x + dx * t - cx) / R, (y + dy * t - cy) / R) }
      }
    }
    return best
  }
  /* where a ball sent from (x, y) along (dx, dy) goes first: a ball, a cushion or a pocket */
  public func aimTrace(_ balls: [Ball], _ x: Double, _ y: Double, _ dx: Double, _ dy: Double, skip: [Int], far: Double) -> AimHit {
    var out = AimHit(t: far, kind: "none", ball: nil)
    for b in balls {
      if !b.on || skip.contains(b.n) { continue }
      let ox = b.x - x, oy = b.y - y, p = ox * dx + oy * dy, q = ox * ox + oy * oy - p * p, rr = 4 * BALL_R * BALL_R
      if p > 0 && q < rr { let t = p - M.sqrt(rr - q); if t >= 0 && t < out.t { out.t = t; out.kind = "ball"; out.ball = b } }
    }
    for s in CUSH { if let h = aimSweep(s, x, y, dx, dy), h.t < out.t { out = AimHit(t: h.t, kind: "rail", ball: nil, nx: h.nx, ny: h.ny, k: out.k) } }
    var te = Double.infinity
    if dx > 1e-9 { te = Swift.min(te, (TL - x) / dx) } else if dx < -1e-9 { te = Swift.min(te, -x / dx) }
    if dy > 1e-9 { te = Swift.min(te, (TW - y) / dy) } else if dy < -1e-9 { te = Swift.min(te, -y / dy) }
    if te < out.t {
      var best = Double.infinity, k = -1
      for (i, P) in POCKETS.enumerated() {
        let tc = (P[0] - x) * dx + (P[1] - y) * dy, d = M.hypot(x + dx * tc - P[0], y + dy * tc - P[1])
        if tc > te - 2 * BALL_R && tc - POCKET_R[i] * 0.5 < out.t && d < POCKET_R[i] * 0.9 && tc < best { best = tc; k = i }
      }
      if k >= 0 { out.t = best; out.kind = "pocket"; out.ball = nil; out.k = k }
    }
    return out
  }

  /* previewStart: balls the game's (on and off), cueN the struck ball, caromNeed the cushions a carom point needs (0: not carom) */
  public func previewStart(_ gameBalls: [Ball], cueN: Int, _ ang: Double, _ pw: Double, _ sp: Spin, _ h: AimHit, _ lens: [Double], caromNeed: Int = 0) -> Preview {
    let R = BALL_R, c = gameBalls.first { $0.n == cueN }!, dx = M.cos(ang), dy = M.sin(ang)
    var balls = gameBalls.filter { $0.on }
    if h.kind == "ball", let o = h.ball {
      let gx = c.x + dx * h.t, gy = c.y + dy * h.t, nx = (o.x - gx) / (2 * R), ny = (o.y - gy) / (2 * R)
      balls = balls.filter { b in
        if b.n == cueN || b.n == o.n { return true }
        let a = (b.x - c.x) * dx + (b.y - c.y) * dy, d = abs((b.y - c.y) * dx - (b.x - c.x) * dy)
        if a > -2 * R && a < h.t + 2 * R && d < 2 * R + 0.02 + 0.03 * a { return true }
        if M.hypot(b.x - gx, b.y - gy) < lens[0] + 3 * R { return true }
        let oa = (b.x - o.x) * nx + (b.y - o.y) * ny, od = abs((b.y - o.y) * nx - (b.x - o.x) * ny)
        return oa > 0 && oa < lens[1] + 2 * R && od < 2 * R + 0.02 + 0.06 * oa
      }
    }
    let full = newTable(balls, cue: cueN), solo = strike(newTable(balls.filter { $0.n == cueN }, cue: cueN), ang, pw, sp)
    let S = Preview(lens: lens, full: full, solo: solo, crossed: c.x > HEAD_X)
    if caromNeed > 0 && lens == PV_CAROM { S.carom = caromNeed; S.bounces = [] }
    return S
  }

  public func previewRun(_ S: Preview) {
    let R = BALL_R, lens = S.lens
    func add(_ p: inout [[Double]], _ x: Double, _ y: Double, _ gap: Double) { let q = p[p.count - 1]; if M.hypot(x - q[0], y - q[1]) >= gap { p.append([x, y]) } }
    while !S.done {
      var cue = S.ball
      if S.tab === S.solo && cue.on {
        if S.safe <= 0 {
          var gap = Double.infinity
          for b in S.others { gap = M.min(gap, M.hypot(b.x - cue.x, b.y - cue.y) - 2 * R) }
          let vm = M.hypot(cue.vx, cue.vy) + R * M.hypot(cue.wx, cue.wy)
          /* the page's Math.floor of Infinity (no other ball) stays Infinity: a count that never runs out */
          let q = vm > 0 ? ((gap - 0.002) / (vm * SIM_DT)).rounded(.down) : Double(PV_CAP)
          S.safe = q.isFinite && q < 1e15 ? Int(q) : Int.max / 2
          if S.safe < 1 {
            let fc = S.full.balls.first { $0.n == S.full.cue }!
            fc.x = cue.x; fc.y = cue.y; fc.vx = cue.vx; fc.vy = cue.vy; fc.on = cue.on; fc.wx = cue.wx; fc.wy = cue.wy; fc.wz = cue.wz; fc.z = cue.z; fc.vz = cue.vz
            S.tab = S.full; S.ball = fc; cue = fc
          }
        }
        S.safe -= 1
      }
      let tab = S.tab, o = S.o, was = tab.first, evWas = S.ev, px = cue.x, py = cue.y, ox = o?.x ?? 0, oy = o?.y ?? 0
      let rc = tab.rails[tab.cue] ?? 0, live = stepTable(tab)
      S.s += 1
      if S.carom > 0 && cue.on && (tab.rails[tab.cue] ?? 0) > rc { S.cc += 1; if S.cc <= S.carom { S.bounces!.append([cue.x, cue.y]) } }
      if was == nil && cue.on {
        if cue.x > HEAD_X { S.crossed = true }
        if !S.ev && (tab.first != nil || tab.hits.contains { $0.kind == "rail" || $0.kind == "jaw" }) { S.ev = true; S.cue.append([cue.x, cue.y]) }
        if let f = tab.first {
          S.first = f
          S.o = tab.balls.first { $0.n == f }
          S.obj = [[S.o!.x, S.o!.y]]; S.objDone = false
        }
      }
      tab.hits.removeAll(keepingCapacity: true)
      if !S.airDone {
        if cue.on && cue.vz != nil {
          let q = S.air.last
          if q == nil || cue.z == 0 || M.hypot(cue.x - q![0], cue.y - q![1]) >= PV_GAP { S.air.append([cue.x, cue.y, cue.z!]) }
        } else {
          if !S.air.isEmpty { S.air.append([cue.x, cue.y, cue.on ? 0 : S.air[S.air.count - 1][2]]) }
          if !S.air.isEmpty || S.s > 2 { S.airDone = true }
        }
      }
      if !S.cueDone {
        if !cue.on {
          S.cueDone = true; S.cuePot = tab.pocketOf[tab.cue] ?? -1
          if S.ev && S.cuePot >= 0 && S.cuePot < POCKETS.count { S.cue.append(POCKETS[S.cuePot]) }
        } else if evWas {
          S.cl += M.hypot(cue.x - px, cue.y - py)
          let stop = M.hypot(cue.vx, cue.vy) < PV_SLOW && BALL_R * M.hypot(cue.wx, cue.wy) < PV_SLOW
          if S.carom > 0 && S.cc >= S.carom { S.tail += M.hypot(cue.x - px, cue.y - py) }
          if stop || S.cl >= lens[0] || S.tail >= PV_TAIL { S.cueDone = true; S.cueStop = stop; S.cue.append([cue.x, cue.y]) } else { add(&S.cue, cue.x, cue.y, PV_GAP) }
        }
      }
      if let o = o, !S.objDone {
        if !o.on {
          S.objDone = true; S.objPot = tab.pocketOf[o.n] ?? -1
          if S.objPot >= 0 && S.objPot < POCKETS.count { S.obj!.append(POCKETS[S.objPot]) }
        } else {
          let v = M.hypot(o.vx, o.vy)
          S.ol += M.hypot(o.x - ox, o.y - oy)
          if S.odx == 0 && S.ody == 0 && v > 0 { S.odx = o.vx / v; S.ody = o.vy / v }
          let turned = v > PV_SLOW && (S.odx * o.vx + S.ody * o.vy) / v < 0.94
          if turned || v < PV_SLOW || S.ol >= lens[1] { S.objDone = true; S.objHit = turned; S.obj!.append([o.x, o.y]) } else { add(&S.obj!, o.x, o.y, 3 * PV_GAP) }
        }
      }
      if !live || S.s >= (S.carom > 0 ? PV_CAROM_CAP : PV_CAP) || (S.cueDone && S.objDone && (tab.first != nil || !cue.on || S.carom > 0)) { S.done = true }
    }
  }
}
