/* 3b, the camera (Settings > Graphics > Camera, settings.camera: 'auto' Follow, 'off' Fixed, the default): a zoom z >= 1
   about a centre (x, y) in table coordinates, on top of the fitted view (Mapper.cam). Live play: z = 1 while aiming.
   When a shot starts it is predicted with the same strike and stepTable (camPredict, a few ms a frame, 1/60 s samples),
   and camPlan frames the balls moving faster than vmin over the 0.1 s before and 0.4 s after each moment: zoom up to
   CAM_LIVE.zmax, smoothed both ways in time (no lag), zoom and pan speed limited, z = 1 at the start and `tail` before
   the balls stop, so the next turn starts on the whole table. A page-time critically damped spring (CAM_W) rounds off
   what is left (TableModel.camStep). Replays use CAM_REPLAY on the cue ball and the first ball it hits. The camera
   reads the sim and never writes it. */
import FeltSim
import Foundation

enum Cam {
  struct Opts { let zmax, margin, vmin, back, ahead, tau, dz, pan, tail: Double }
  static let DT = 1.0 / 60, STEPS = Int((DT / SIM_DT).rounded())   /* a sample every 20 steps */
  static let W = 9.0                /* spring rate, rad/s of page time (times felt.speed) */
  static let LIVE = Opts(zmax: 1.35, margin: 0.22, vmin: 0.3, back: 0.1, ahead: 0.4, tau: 0.3, dz: 0.45, pan: 0.7, tail: 0.35)
  static let REPLAY = Opts(zmax: 1.8, margin: 0.12, vmin: 0, back: 0.08, ahead: 0.3, tau: 0.18, dz: 1.0, pan: 1.5, tail: 0.3)
  /* rec.track: the samples, the first contact and the pots */
  struct Track { var frames: [[Double]] = [], first: (t: Double, n: Int)? = nil, pots: [(n: Int, i: Int, t: Double, k: Int)] = [], end = 0.0 }
  struct Plan { let t0: Double, z: [Double], x: [Double], y: [Double] }
  /* camPredict's state: the record it predicts (by its id), its table, the track so far */
  final class Pred {
    let id: Int, T: Tab
    var tr = Track(), done = false, plan: Plan? = nil
    init(id: Int, T: Tab) { self.id = id; self.T = T }
  }
  private static func round(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }
  /* one sample of a table in motion: x, y and speed per ball (speed -1: off the table) */
  static func sample(_ T: Tab) -> [Double] {
    var s = [Double](repeating: 0, count: T.balls.count * 3)
    for (i, b) in T.balls.enumerated() { s[3 * i] = b.x; s[3 * i + 1] = b.y; s[3 * i + 2] = b.on ? JSMath.hypot(b.vx, b.vy) : -1 }
    return s
  }
  /* camPredict: a shot record predicted to the end, budget s at a time (camPredStep) */
  static func predict(_ sim: Sim, id: Int, balls: [Ball], ball: Int, angle: Double, power: Double, spin: Spin) -> Pred {
    let T = sim.strike(sim.newTable(balls.map { $0.copy() }, cue: ball), angle, power, spin)
    T.hits.removeAll()
    let P = Pred(id: id, T: T)
    P.tr.frames = [sample(T)]
    return P
  }
  @discardableResult static func step(_ sim: Sim, _ P: Pred, _ budget: Double) -> Bool {
    let t0 = ProcessInfo.processInfo.systemUptime, T = P.T
    while !P.done && ProcessInfo.processInfo.systemUptime - t0 < budget {
      var i = 0
      while i < STEPS && !P.done {
        let np = T.potted.count
        if !sim.stepTable(T) { P.done = true }
        T.hits.removeAll(keepingCapacity: true)
        if P.tr.first == nil, let f = T.first { P.tr.first = (T.t, f) }
        for j in np..<T.potted.count { let n = T.potted[j]; P.tr.pots.append((n, T.balls.firstIndex { $0.n == n } ?? -1, T.t, T.pocketOf[n] ?? -1)) }
        i += 1
      }
      P.tr.frames.append(sample(T))
    }
    if P.done { P.tr.end = T.t }
    return P.done
  }
  /* camPlan: the camera's path through a predicted shot: zoom and centre every CAM_DT from -lead s (the replay's run-up
     holds the first frame). focus: per ball index, follow it whether moving or not (a replay); without it, every ball
     moving faster than o.vmin. RAIL is the view's rail (Mapper.rail) */
  static func plan(_ tr: Track, _ o: Opts, _ focus: [Bool]?, lead: Double = 0, TL: Double, TW: Double, RAIL: Double, POCKETS: [[Double]]) -> Plan {
    let F = tr.frames, N = F.count, nb = F[0].count / 3, L = round(lead / DT), M = N + L
    let back = round(o.back / DT), ahead = round(o.ahead / DT), W = TL + 2 * RAIL, H = TW + 2 * RAIL
    var z = [Double](repeating: 0, count: M), x = z, y = z
    var hx = TL / 2, hy = TW / 2
    for b in 0..<nb where focus.map({ $0[b] }) ?? (F[0][3 * b + 2] > 0) { hx = F[0][3 * b]; hy = F[0][3 * b + 1]; break }
    for i in 0..<M {
      let c = max(0, i - L), t0 = Double(c - back) * DT, t1 = Double(c + ahead) * DT
      var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
      func add(_ px: Double, _ py: Double) { x0 = JSMath.min(x0, px); x1 = JSMath.max(x1, px); y0 = JSMath.min(y0, py); y1 = JSMath.max(y1, py) }
      var j = max(0, c - back)
      while j <= min(N - 1, c + ahead) {
        let f = F[j]
        for b in 0..<nb where f[3 * b + 2] >= 0 && (focus.map { $0[b] } ?? (f[3 * b + 2] > o.vmin)) { add(f[3 * b], f[3 * b + 1]) }
        j += 1
      }
      /* a followed ball that drops inside the window: its pocket is in the shot */
      if let focus { for p in tr.pots where p.i >= 0 && focus[p.i] && p.t >= t0 && p.t <= t1 && p.k >= 0 && p.k < POCKETS.count { add(POCKETS[p.k][0], POCKETS[p.k][1]) } }
      if x0 <= x1 {
        z[i] = clamp(JSMath.min(W / (x1 - x0 + 2 * o.margin), H / (y1 - y0 + 2 * o.margin)), 1, o.zmax)
        hx = (x0 + x1) / 2; hy = (y0 + y1) / 2
      } else { z[i] = 1 }
      x[i] = hx; y[i] = hy
    }
    /* zero-lag smoothing (forward then backward), then the ends and the speed limits */
    let a = 1 - JSMath.exp(-DT / o.tau)
    func smooth(_ s: inout [Double]) {
      if M > 1 { for i in 1..<M { s[i] = s[i - 1] + a * (s[i] - s[i - 1]) } }
      var i = M - 2
      while i >= 0 { s[i] = s[i + 1] + a * (s[i] - s[i + 1]); i -= 1 }
    }
    smooth(&z); smooth(&x); smooth(&y)
    let dz = o.dz * DT, dp = o.pan * DT, tail = max(1, M - round(o.tail / DT))
    z[0] = 1
    if M > 1 { for i in 1..<M { z[i] = clamp(z[i], z[i - 1] - dz, z[i - 1] + dz) } }
    if tail < M { for i in tail..<M { z[i] = 1 } }
    var i = M - 2
    while i >= 0 { z[i] = JSMath.min(z[i], z[i + 1] + dz); i -= 1 }
    if M > 1 {
      for i in 1..<M {
        let ex = x[i] - x[i - 1], ey = y[i] - y[i - 1], d = JSMath.hypot(ex, ey)
        if d > dp { x[i] = x[i - 1] + ex * dp / d; y[i] = y[i - 1] + ey * dp / d }
      }
    }
    return Plan(t0: -Double(L) * DT, z: z, x: x, y: y)
  }
  /* camAt: the plan at time t (s after the strike), interpolated */
  static func at(_ P: Plan, _ t: Double) -> [Double] {
    if P.z.count < 2 { return [P.z[0], P.x[0], P.y[0]] }
    let u = clamp((t - P.t0) / DT, 0, Double(P.z.count - 1)), i = min(P.z.count - 2, Int(u.rounded(.down))), f = u - Double(max(0, i))
    return [P.z[i] + (P.z[i + 1] - P.z[i]) * f, P.x[i] + (P.x[i + 1] - P.x[i]) * f, P.y[i] + (P.y[i + 1] - P.y[i]) * f]
  }
  /* critically damped spring toward `to` over dt, exact for any dt: (position, velocity) */
  static func spring(_ p: Double, _ v: Double, _ to: Double, _ w: Double, _ dt: Double) -> (Double, Double) {
    let e = p - to, k = v + w * e, ex = JSMath.exp(-w * dt)
    return (to + (e + k * dt) * ex, (v - w * k * dt) * ex)
  }
}
