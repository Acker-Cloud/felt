/* index.html sim 1f (the CPU) for the pocket games, line for line: calibration, ghost-ball pot lines,
   hard's kick pots, jumps and swerves, safeties, ball-in-hand spots, the break, and cpuSearch's phases
   A to D, scored by the real judge. The page runs the search as a generator, a simulation a yield;
   here it runs whole, counting the same yields (`sims`), so the budget falls where the page's does
   and the shot chosen is the page's. A bare level ('easy', 'medium', 'hard') is cpuProfile's: every
   personality knob neutral. CPUTests compares cpuShot and cpuOption with the page's own. */
import Foundation

private typealias M = JSMath

/* a level's record (CPU_LEVELS) with CPU_NEUTRAL's knobs */
public struct CPUProfile: Sendable {
  public var level: String, sims: Int, lines: Int, ladder: [Double], spin: Int, spins: [[Double]], safe: Int, safeBar: Double, robust: Int, place: Int
  public var minCos: Double, position: Bool, look: Bool, retry: Bool, noise: Double, pnoise: Double, brk: Double
  public var plan = 0, kickPot = 0.0, elev = 0.0, special = 0
  public var snoise = 0.0, riskBonus = 0.0, safeBonus = 0.0, posW = 1.0, take = 0.3, push = 4, bank = 0.0, kick = 0.0, combo = 0.0
  /* the bumper and carom searches' noise multipliers (P.nscale, P.pscale), and the visible think time's */
  public var nscale = 1.0, pscale = 1.0, think = 1.0, dsafe = 0, arch: String? = nil
  /* cpuRecord(P, 'snooker'): the profile over SNK_CPU's leaner record (a personality's extra safeties kept), and never the
     raised cue (a jump is a foul there) */
  public static func record(_ P: CPUProfile, kind: String) -> CPUProfile {
    var L = P
    if kind == "snooker" {
      var safe: Int? = nil
      switch L.level { case "easy": L.sims = 10; case "hard": L.sims = 90; L.lines = 10; safe = 14; default: L.sims = 32; L.lines = 7 }
      if let s = safe { L.safe = s; if P.dsafe != 0 { L.safe = Swift.max(1, s + P.dsafe) } }
      L.elev = 0
    }
    return L
  }
  /* CPU_ARCH: each archetype's offsets from the level (index.html 1f) */
  static let ARCH: [String: [String: Double]] = [
    "allround": [:],
    "potter": ["risk": 0.3, "safety": -0.2, "take": -0.08, "push": -2, "think": 0.7, "elev": 0.3],
    "shotmaker": ["risk": 0.4, "safety": -0.15, "minCos": -0.1, "combo": 0.8, "bank": 0.4, "posW": -0.3, "think": 0.8, "elev": 0.6],
    "defender": ["risk": -0.3, "safety": 0.45, "dsafe": 6, "take": 0.12, "push": 3, "kick": 0.6, "think": 1.3],
    "positional": ["depth": 1, "posW": 0.5, "dspin": 2, "think": 1.15],
    "breaker": ["brk": 0.1, "risk": 0.1, "think": 0.85],
    "banker": ["bank": 1, "kick": 1, "think": 1.1],
    "grinder": ["pnoiseK": 0.7, "risk": -0.15, "safety": 0.15, "think": 1.35],
    "clutch": ["hillK": 0.3],
  ]
  static func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, v)) }
  /* cpuProfile({ level, arch }, { hill }): a person at a level. A bare level (arch nil) is CPU_LEVELS exactly, the
     personality knobs neutral; the noise scales computed as the page computes them, (base x hill) / base */
  public static func make(_ lv: String, arch: String?, hill: Bool = false) -> CPUProfile {
    let base = level(lv)
    guard let arch else { return base }
    let a = ARCH[arch] ?? ARCH["allround"]!, g = { (k: String) in a[k] ?? 0 }
    let risk = g("risk"), safety = g("safety"), pos = 0.0, bankW = 0.5
    let h = hill ? 1 + (1.25 - 1) * (a["hillK"] ?? 1) : 1.0
    var P = base
    P.arch = ARCH[arch] != nil ? arch : "allround"
    P.noise = base.noise * h
    P.pnoise = base.pnoise * (a["pnoiseK"] ?? 1) * h
    P.snoise = clampD(P.noise * 10, 0.004, 0.08)
    P.riskBonus = CareerLib.round(150 * risk)
    P.safeBonus = CareerLib.round(150 * safety)
    P.safeBar = base.safeBar + CareerLib.round(200 * safety - 150 * risk)
    P.minCos = clampD(base.minCos + g("minCos") - 0.2 * risk, 0.12, 0.7)
    P.safe = Swift.max(1, base.safe + Int(g("dsafe")))
    if g("dspin") != 0 { P.spin = base.spin + Int(g("dspin")); if base.spins.isEmpty { P.spins = level("medium").spins } }
    let depth = Int(clampD(Double((base.position ? 1 : 0) + (base.look ? 1 : 0)) + g("depth") + (pos > 0.3 ? 1 : 0), 0, 2))
    P.position = depth >= 1; P.look = depth >= 2
    P.plan = P.look ? Swift.max(base.plan, 1) + Int(g("depth")) : 0
    P.kickPot = clampD(base.kickPot + (g("kick") >= 1 ? 1 : 0), 0, 1)
    P.elev = lv == "easy" ? 0 : clampD(base.elev + g("elev"), 0, 1)
    P.special = P.kickPot != 0 || P.elev != 0 ? Swift.max(base.special, 2) : 0
    P.posW = clampD(1 + g("posW") + 0.8 * pos, 0.3, 2)
    P.brk = clampD(base.brk + g("brk"), 0.6, 1)
    P.take = clampD(0.3 + g("take") - 0.15 * risk, 0.1, 0.6)
    P.push = Int(clampD(4 + g("push") + CareerLib.round(4 * safety), 0, 8))
    P.bank = clampD(g("bank") + Swift.max(0, bankW - 0.6) * 2.5, 0, 1)
    P.kick = clampD(g("kick") + Swift.max(0, bankW - 0.6) * 2.5, 0, 1)
    P.combo = clampD(g("combo") + Swift.max(0, risk - 0.15), 0, 1)
    P.think = a["think"] ?? 1
    P.nscale = P.noise / base.noise; P.pscale = P.pnoise / base.pnoise
    P.dsafe = P.safe - base.safe
    return P
  }
  public static func level(_ lv: String) -> CPUProfile {
    switch lv {
    case "easy": return CPUProfile(level: "easy", sims: 10, lines: 3, ladder: [1.3], spin: 0, spins: [], safe: 2, safeBar: 250, robust: 0, place: 2, minCos: 0.5,
                                   position: false, look: false, retry: false, noise: 0.0055, pnoise: 0.06, brk: 0.85)
    case "hard": return CPUProfile(level: "hard", sims: 150, lines: 12, ladder: [0.85, 1.25, 1.8], spin: 5,
                                   spins: [[0, 0.6, 1], [0, -0.6, 1], [0.45, 0, 1], [-0.45, 0, 1], [0, 0, 0.7], [0, 0, 1.4]], safe: 20, safeBar: 250, robust: 4, place: 6, minCos: 0.2,
                                   position: true, look: true, retry: true, noise: 0.0009, pnoise: 0.01, brk: 1, plan: 3, kickPot: 1, elev: 0.5, special: 3)
    default: return CPUProfile(level: "medium", sims: 40, lines: 8, ladder: [1, 1.5], spin: 3, spins: [[0, 0.5, 1], [0, -0.5, 1]], safe: 8, safeBar: 150, robust: 2, place: 4, minCos: 0.3,
                               position: true, look: false, retry: true, noise: 0.004, pnoise: 0.03, brk: 0.95)
    }
  }
}

/* the shot the CPU plays: its stroke, where it places the cue ball, its call and what it is */
public struct CPUShot: Sendable {
  public var angle: Double, power: Double, spin: Spin, place: [Double]?, call: ShotCall?, intent: (type: String, q: Double)
  /* carom: the cue ball struck, and the ball the plan meets first */
  public var ball: Int? = nil, first: Int? = nil
}

/* a pot line (cpuLine and its kin): mutable, as the page's objects are */
final class CPULine {
  var n: Int, k: Int, cx: Double, cy: Double, tx: Double, ty: Double, psi0: Double, psi: Double, angle: Double, cos: Double, d1: Double, d2: Double, q: Double
  var pot: Int? = nil, bank = false, combo = false, kick = false, jump = false, swerve = false, special = false
  var gx = 0.0, gy = 0.0, place: [Double]? = nil
  var aimA: Double? = nil, kOff = 0.0, kHist: [[Double]] = [], plans: [Plan]? = nil
  struct Plan { var f: Double? = nil, p: Double? = nil, spin: Spin? = nil, off: Double? = nil }
  init(n: Int, k: Int, cx: Double, cy: Double, tx: Double, ty: Double, psi0: Double, psi: Double, angle: Double, cos: Double, d1: Double, d2: Double, q: Double) {
    self.n = n; self.k = k; self.cx = cx; self.cy = cy; self.tx = tx; self.ty = ty; self.psi0 = psi0; self.psi = psi; self.angle = angle; self.cos = cos; self.d1 = d1; self.d2 = d2; self.q = q
  }
  func copy() -> CPULine {
    let l = CPULine(n: n, k: k, cx: cx, cy: cy, tx: tx, ty: ty, psi0: psi0, psi: psi, angle: angle, cos: cos, d1: d1, d2: d2, q: q)
    l.pot = pot; l.bank = bank; l.combo = combo; l.kick = kick; l.jump = jump; l.swerve = swerve; l.special = special; l.gx = gx; l.gy = gy; l.place = place
    l.aimA = aimA; l.kOff = kOff; l.kHist = kHist; l.plans = plans
    return l
  }
}

/* JS's ToUint32 of an integer-valued double (rng's seed >>> 0) */
func toUint32(_ x: Double) -> UInt32 {
  let m = x.truncatingRemainder(dividingBy: 4294967296)
  return UInt32(m < 0 ? m + 4294967296 : m)
}
public func cpuRng(_ seed: Double) -> () -> Double {
  var a = toUint32(seed)
  return {
    a = a &+ 0x6d2b79f5
    var t = a
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4294967296
  }
}
/* JS's Array.prototype.sort: stable */
func stableSorted<T>(_ a: [T], by less: (T, T) -> Bool) -> [T] {
  a.enumerated().sorted { less($0.element, $1.element) || (!less($1.element, $0.element) && $0.offset < $1.offset) }.map { $0.element }
}
func wrapAngle(_ a: Double) -> Double { M.atan2(M.sin(a), M.cos(a)) }
func jsSign(_ x: Double) -> Double { x > 0 ? 1 : x < 0 ? -1 : x }

let CPU_T = 4.0, CPU_MOUTH = 0.05, CPU_DRY = 4, CPU_DRY_COST = 30.0, CPU_DRY_MAX = 100.0, CPU_STILL = 0.15, CPU_MISS = -200.0
let CPU_JUMP_E = [0.75, 0.95], CPU_SWERVE_E = 0.35

public final class CPU {
  let E: RulesEngine
  /* the person searching (cpuProfile's { level, arch } and the hill): nil arch is a bare level */
  public var arch: String? = nil, hill = false
  var s: Sim { E.sim }
  struct Cal { var key: [Double], speed: [Double], roll: Double, keep: Double }
  var cal: Cal? = nil
  public init(engine: RulesEngine) { E = engine }

  func toBalls(_ gb: [GBall]) -> [Ball] { gb.map { g in let b = Ball(g.n, g.x, g.y); b.vx = g.vx; b.vy = g.vy; b.on = g.on; b.wx = g.wx; b.wy = g.wy; b.wz = g.wz; return b } }

  // MARK: calibration

  @discardableResult func cpuCalibrate() -> Cal {
    let key = [s.BALL_R, s.MU_ROLL, s.CUE_RATIO]
    if let c = cal, c.key == key { return c }
    let proto = s.rack("9")[0]
    func lone(_ x: Double, _ y: Double) -> [Ball] { let b = proto.copy(); b.x = x; b.y = y; b.vx = 0; b.vy = 0; return [b] }
    var speed: [Double] = []
    for i in 0...20 {
      let c = s.strike(s.newTable(lone(s.TL / 2, s.TW / 2)), 0, Double(i) / 20, Spin()).balls[0]
      speed.append(M.hypot(c.vx, c.vy))
    }
    cal = Cal(key: key, speed: speed, roll: 0.16, keep: 5.0 / 7)
    let tab = s.strike(s.newTable(lone(0.25, s.TW / 2)), 0, cpuPower(1.2), Spin()), x0 = tab.balls[0].x
    let v0 = M.hypot(tab.balls[0].vx, tab.balls[0].vy)
    var va: Double? = nil, xa = 0.0, vb = 0.0, xb = 0.0
    var i = 0
    while i < 20000 && s.stepTable(tab) {
      let b = tab.balls[0], d = b.x - x0, v = M.hypot(b.vx, b.vy)
      xb = d; vb = v
      if va == nil && d >= 0.3 { va = v; xa = d }
      if d >= 1.2 { break }
      i += 1
    }
    if tab.balls[0].vx == 0 { vb = 0 }
    if let va, xb - xa > 0.1 {
      cal!.roll = clamp((va * va - vb * vb) / (2 * (xb - xa)), 0.02, 3)
      cal!.keep = clamp(M.sqrt(va * va + 2 * cal!.roll * xa) / v0, 0.3, 1)
    } else if xb > 0.05 { cal!.roll = clamp(v0 * v0 / (2 * xb), 0.02, 3) }
    return cal!
  }
  func cpuSpeedFor(_ d: Double) -> Double { M.sqrt(2 * cal!.roll * M.max(0, d)) / cal!.keep }
  func cpuSpeedAt(_ p: Double) -> Double {
    let sp = cal!.speed, u = clamp(p, 0, 1) * Double(sp.count - 1), i = Swift.min(sp.count - 2, Int(u.rounded(.down)))
    return sp[i] + (sp[i + 1] - sp[i]) * (u - Double(i))
  }
  func cpuPower(_ v: Double) -> Double {
    let sp = cal!.speed
    if v <= sp[0] { return 0 }
    for i in 1..<sp.count where v <= sp[i] { return (Double(i - 1) + (v - sp[i - 1]) / M.max(1e-9, sp[i] - sp[i - 1])) / Double(sp.count - 1) }
    return 1
  }
  func cpuPotPower(_ l: CPULine, _ f: Double) -> Double {
    let c = cal!, vObj = cpuSpeedFor(l.d2 + 0.3) * f, vHit = vObj / (0.95 * M.max(l.cos, 0.25))
    return cpuPower(M.sqrt(vHit * vHit * c.keep * c.keep + 2 * c.roll * l.d1) / c.keep)
  }

  // MARK: the run

  func cpuRun(_ balls: [GBall], _ angle: Double, _ power: Double, _ spin: Spin) -> (r: ShotResult, dir: Double?) {
    let tab = s.strike(s.newTable(toBalls(balls)), angle, power, spin)
    let cap = Int((CPU_T / SIM_DT).rounded())
    var dir: Double? = nil, live = true, i = 0
    while live && i < cap {
      live = s.stepTable(tab)
      if dir == nil, let f = tab.first {
        let o = tab.balls.first { $0.n == f }!
        if o.on && (o.vx != 0 || o.vy != 0) { dir = M.atan2(o.vy, o.vx) }
      }
      tab.hits.removeAll(keepingCapacity: true)
      i += 1
    }
    if live { cpuCoast(tab) }
    return (s.resultOf(tab), dir)
  }
  func cpuCoast(_ tab: Tab) {
    let a = cal!.roll, lo = s.BALL_R, hx = s.TL - s.BALL_R, hy = s.TW - s.BALL_R
    for b in tab.balls {
      if !b.on || !(b.vx != 0 || b.vy != 0) { continue }
      var v = M.hypot(b.vx, b.vy), ux = b.vx / v, uy = b.vy / v, x = b.x, y = b.y
      var i = 0
      while v > 0.01 && i < 3000 {
        defer { i += 1 }
        let ds = M.min(0.02, v * v / (2 * a))
        let nx = x + ux * ds, ny = y + uy * ds
        if tab.balls.contains(where: { $0 !== b && $0.on && M.hypot($0.x - nx, $0.y - ny) < 2 * s.BALL_R }) { break }
        x = nx; y = ny; v = M.sqrt(M.max(0, v * v - 2 * a * ds))
        if x >= lo && x <= hx && y >= lo && y <= hy { continue }
        if let k = s.POCKET_AIM.firstIndex(where: { M.hypot($0[0] - x, $0[1] - y) < CPU_MOUTH }) { b.on = false; tab.potted.append(b.n); tab.pocketOf[b.n] = k; break }
        if x < lo || x > hx { ux = -ux; x = clamp(x, lo, hx) }
        if y < lo || y > hy { uy = -uy; y = clamp(y, lo, hy) }
        v *= 0.75
        if tab.first != nil { tab.railAfter = true }
      }
      if b.on { b.x = clamp(x, lo, hx); b.y = clamp(y, lo, hy) }
      b.vx = 0; b.vy = 0
      if b.vz != nil { b.z = nil; b.vz = nil }
    }
    tab.end = "rest"
  }

  // MARK: lines

  public func cpuClear(_ balls: [GBall], _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ skip: Int) -> Bool {
    let ex = bx - ax, ey = by - ay, L2 = ex * ex + ey * ey
    for o in balls {
      if !o.on || o.n == 0 || o.n == skip { continue }
      if M.hypot(o.x - bx, o.y - by) < 2 * s.BALL_R { return false }
      let t = L2 != 0 ? ((o.x - ax) * ex + (o.y - ay) * ey) / L2 : 0
      if t > 0 && t < 1 && M.hypot(o.x - ax - ex * t, o.y - ay - ey * t) < 2 * s.BALL_R { return false }
    }
    return true
  }
  func cpuHangs(_ t: GBall, _ k: Int) -> Bool {
    let a = s.POCKET_AIM[k], m = s.CPU_MOUTH_N[k], side = k == 1 || k == 4
    return (t.x - a[0]) * m[0] + (t.y - a[1]) * m[1] < s.BALL_R && M.hypot(t.x - a[0], t.y - a[1]) < (side ? s.SIDE_W : s.CORNER_W) / 2 + s.BALL_R
  }
  func cpuLine(_ balls: [GBall], _ cx: Double, _ cy: Double, _ t: GBall, _ k: Int, _ psi: Double, minCos: Double, noise: Double) -> CPULine? {
    let R = s.BALL_R, hang = cpuHangs(t, k), p = hang ? s.POCKETS[k] : s.POCKET_AIM[k], m = s.CPU_MOUTH_N[k], side = k == 1 || k == 4
    let psi0 = hang ? psi : M.atan2(p[1] - t.y, p[0] - t.x), ux = M.cos(psi0), uy = M.sin(psi0)
    let entry = hang ? 1 : -(ux * m[0] + uy * m[1])
    if entry < (side ? 0.55 : 0.5) { return nil }
    let d2 = M.hypot(p[0] - t.x, p[1] - t.y), gx = t.x - 2 * R * M.cos(psi), gy = t.y - 2 * R * M.sin(psi)
    if hang ? s.CUSH.contains(where: { s.segGap($0[0], $0[1], $0[2], $0[3], gx, gy) < R - 1e-4 })
        : gx < R - 1e-4 || gx > s.TL - R + 1e-4 || gy < R - 1e-4 || gy > s.TW - R + 1e-4 { return nil }
    let ax = gx - cx, ay = gy - cy, d1 = M.hypot(ax, ay)
    if d1 < 1e-6 { return nil }
    let cos = (ax * M.cos(psi) + ay * M.sin(psi)) / d1
    if cos < minCos { return nil }
    if !cpuClear(balls, cx, cy, gx, gy, t.n) || !cpuClear(balls, t.x, t.y, p[0], p[1], t.n) { return nil }
    let reg = POCKET_STYLES["regulation"]!, grow = (side ? s.SIDE_W - reg.side : s.CORNER_W - reg.corner) / 2
    let w = (0.03 + grow) * (side ? entry : M.sqrt(entry))
    let tol = w * 2 * R * cos / (M.max(d1, 0.1) * M.max(d2, 0.05))
    return CPULine(n: t.n, k: k, cx: cx, cy: cy, tx: t.x, ty: t.y, psi0: psi0, psi: psi, angle: M.atan2(ay, ax), cos: cos, d1: d1, d2: d2, q: M.tanh(0.8 * tol / noise))
  }
  func cpuLines(_ balls: [GBall], _ cx: Double, _ cy: Double, _ targets: [Int], minCos: Double, noise: Double) -> [CPULine] {
    var out: [CPULine] = []
    for n in targets {
      guard let t = balls.first(where: { $0.n == n }), t.on else { continue }
      for k in 0..<s.POCKET_AIM.count {
        let hang = cpuHangs(t, k), p = hang ? s.POCKETS[k] : s.POCKET_AIM[k], psi = M.atan2(p[1] - t.y, p[0] - t.x)
        for off in hang ? [0, 0.35, -0.35] : [0.0] {
          if let l = cpuLine(balls, cx, cy, t, k, psi + off, minCos: minCos, noise: noise) { if hang && off == 0 { l.q *= 0.85 }; out.append(l) }
        }
      }
    }
    return stableSorted(out) { $0.q > $1.q }
  }
  func cpuAim(_ l: CPULine, _ psi: Double) -> Double { M.atan2(l.ty - 2 * s.BALL_R * M.sin(psi) - l.cy, l.tx - 2 * s.BALL_R * M.cos(psi) - l.cx) }
  func cpuPotBall(_ l: CPULine) -> Int { l.pot ?? l.n }
  /* cpuGhost: the cue angle that sends ball t along psi from (cx, cy), or nil (the ghost off the bed, too thin, blocked) */
  func cpuGhost(_ balls: [GBall], _ cx: Double, _ cy: Double, _ t: GBall, _ psi: Double, minCos: Double) -> (angle: Double, cos: Double, d1: Double)? {
    let R = s.BALL_R, gx = t.x - 2 * R * M.cos(psi), gy = t.y - 2 * R * M.sin(psi)
    if gx < R || gx > s.TL - R || gy < R || gy > s.TW - R { return nil }
    let ax = gx - cx, ay = gy - cy, d1 = M.hypot(ax, ay)
    if d1 < 1e-6 { return nil }
    let cos = (ax * M.cos(psi) + ay * M.sin(psi)) / d1
    if cos < minCos || !cpuClear(balls, cx, cy, gx, gy, t.n) { return nil }
    return (M.atan2(ay, ax), cos, d1)
  }
  /* cpuBankLines (a personality's, L.bank > 0): ball t off a cushion into pocket k, the pocket mirrored across the
     ball's centre line at that cushion, its depth over the rubber's restitution at about 1 m/s */
  func cpuBankLines(_ balls: [GBall], _ cx: Double, _ cy: Double, _ targets: [Int], _ L: CPUProfile) -> [CPULine] {
    var out: [CPULine] = []
    let R = s.BALL_R, lo = R, hx = s.TL - R, hy = s.TW - R, RE = s.RAIL_E, e = Swift.max(RE[2], Swift.min(RE[0], RE[0] - RE[1]))
    for n in targets {
      guard let t = balls.first(where: { $0.n == n }), t.on else { continue }
      for k in s.POCKET_AIM.indices {
        let p = s.POCKET_AIM[k], m = s.CPU_MOUTH_N[k], side = k == 1 || k == 4
        for (axis, at) in [(0, lo), (0, hx), (1, lo), (1, hy)] {
          let dp = axis != 0 ? p[1] - at : p[0] - at, dt = axis != 0 ? t.y - at : t.x - at
          if dp * dt <= 0 { continue }
          let mx = axis != 0 ? p[0] : at - dp / e, my = axis != 0 ? at - dp / e : p[1]
          let ex = mx - t.x, ey = my - t.y, u = axis != 0 ? (at - t.y) / ey : (at - t.x) / ex
          if !(u > 0.02 && u < 0.98) { continue }
          let rx = t.x + ex * u, ry = t.y + ey * u
          if s.POCKET_AIM.enumerated().contains(where: { j, q in M.hypot(q[0] - rx, q[1] - ry) < (j == 1 || j == 4 ? s.SIDE_W : s.CORNER_W) / 2 + 1.5 * R }) { continue }
          let l2 = M.hypot(p[0] - rx, p[1] - ry), entry = -((p[0] - rx) * m[0] + (p[1] - ry) * m[1]) / Swift.max(l2, 1e-6)
          if entry < (side ? 0.6 : 0.5) { continue }
          if !cpuClear(balls, t.x, t.y, rx, ry, n) || !cpuClear(balls, rx, ry, p[0], p[1], n) { continue }
          let psi = M.atan2(ey, ex)
          guard let c = cpuGhost(balls, cx, cy, t, psi, minCos: L.minCos) else { continue }
          let d2 = M.hypot(rx - t.x, ry - t.y) + l2, w = 0.03 * (side ? entry : entry.squareRoot())
          let tol = 0.5 * w * 2 * R * c.cos / (Swift.max(c.d1, 0.1) * Swift.max(d2, 0.05))
          let l = CPULine(n: n, k: k, cx: cx, cy: cy, tx: t.x, ty: t.y, psi0: psi, psi: psi, angle: c.angle, cos: c.cos, d1: c.d1, d2: d2 * 1.3, q: M.tanh(0.8 * tol / L.noise) * L.bank)
          l.bank = true; out.append(l)
        }
      }
    }
    return out
  }
  /* cpuComboLines (L.combo > 0): legal ball t into ball u (within a metre) into pocket k; the second leg cpuLine from t
     (its tolerance at unit noise), the first t to u's ghost */
  func cpuComboLines(_ balls: [GBall], _ cx: Double, _ cy: Double, _ targets: [Int], _ L: CPUProfile) -> [CPULine] {
    var out: [CPULine] = []
    let R = s.BALL_R
    for n in targets {
      guard let t = balls.first(where: { $0.n == n }), t.on else { continue }
      for u in balls {
        if !u.on || u.n == 0 || u.n == n || M.hypot(u.x - t.x, u.y - t.y) > 1 { continue }
        for k in s.POCKET_AIM.indices {
          let p = s.POCKET_AIM[k]
          guard let l2 = cpuLine(balls, t.x, t.y, u, k, M.atan2(p[1] - u.y, p[0] - u.x), minCos: L.minCos, noise: 1), cpuClear(balls, cx, cy, t.x, t.y, n) else { continue }
          let gx = u.x - 2 * R * M.cos(l2.psi), gy = u.y - 2 * R * M.sin(l2.psi), psi = M.atan2(gy - t.y, gx - t.x)
          guard let c = cpuGhost(balls, cx, cy, t, psi, minCos: L.minCos) else { continue }
          let tol = M.atanh(Swift.min(l2.q, 0.999)) / 0.8 * 2 * R * c.cos / Swift.max(c.d1, 0.1)
          let l = CPULine(n: n, k: k, cx: cx, cy: cy, tx: t.x, ty: t.y, psi0: psi, psi: psi, angle: c.angle, cos: c.cos * l2.cos, d1: c.d1, d2: l2.d1 + 1.4 * l2.d2 + 0.1,
                          q: 0.7 * M.tanh(0.8 * tol / L.noise) * L.combo)
          l.pot = u.n; l.combo = true; out.append(l)
        }
      }
    }
    return out
  }

  /* one-rail kick pots (hard) */
  func cpuKickLines(_ balls: [GBall], _ cx: Double, _ cy: Double, _ targets: [Int], _ L: CPUProfile) -> [CPULine] {
    let R = s.BALL_R, lo = R, hx = s.TL - R, hy = s.TW - R, e = clamp(s.RAIL_E[0] - 2 * s.RAIL_E[1], s.RAIL_E[2], s.RAIL_E[0])
    func mirror(_ gx: Double, _ gy: Double, _ axis: Int, _ at: Double) -> (Double, Double) { axis == 1 ? (gx, at - (gy - at) / e) : (at - (gx - at) / e, gy) }
    var out: [CPULine] = []
    for n in targets {
      guard let t = balls.first(where: { $0.n == n }), t.on else { continue }
      for k in 0..<s.POCKET_AIM.count {
        let p = s.POCKET_AIM[k], m = s.CPU_MOUTH_N[k], side = k == 1 || k == 4, psi = M.atan2(p[1] - t.y, p[0] - t.x)
        let entry = -(M.cos(psi) * m[0] + M.sin(psi) * m[1])
        if entry < (side ? 0.55 : 0.5) || !cpuClear(balls, t.x, t.y, p[0], p[1], n) { continue }
        let gx = t.x - 2 * R * M.cos(psi), gy = t.y - 2 * R * M.sin(psi)
        if gx < lo || gx > hx || gy < lo || gy > hy { continue }
        for (axis, at) in [(0, lo), (0, hx), (1, lo), (1, hy)] {
          let (mx, my) = mirror(gx, gy, axis, at), ex = mx - cx, ey = my - cy, u = axis == 1 ? (at - cy) / ey : (at - cx) / ex
          if !(u > 0.02 && u < 0.98) { continue }
          let rx = cx + ex * u, ry = cy + ey * u
          if s.POCKET_AIM.enumerated().contains(where: { j, q in M.hypot(q[0] - rx, q[1] - ry) < (j == 1 || j == 4 ? s.SIDE_W : s.CORNER_W) / 2 + 1.5 * R }) { continue }
          if !cpuClear(balls, cx, cy, rx, ry, -1) || !cpuClear(balls, rx, ry, gx, gy, n) { continue }
          let l2 = M.hypot(gx - rx, gy - ry), cos = ((gx - rx) * M.cos(psi) + (gy - ry) * M.sin(psi)) / M.max(l2, 1e-6)
          if cos < L.minCos + 0.1 { continue }
          let d1 = M.hypot(rx - cx, ry - cy) + l2, d2 = M.hypot(p[0] - t.x, p[1] - t.y), w = 0.03 * (side ? entry : M.sqrt(entry))
          let tol = w * 2 * R * cos / (M.max(d1, 0.1) * M.max(d2, 0.05)) / 3
          let l = CPULine(n: n, k: k, cx: cx, cy: cy, tx: t.x, ty: t.y, psi0: psi, psi: psi, angle: M.atan2(my - cy, mx - cx), cos: cos, d1: d1 * 1.25, d2: d2,
                          q: M.tanh(0.8 * tol / L.noise) * L.kickPot)
          l.gx = gx; l.gy = gy; l.kick = true; l.special = true
          out.append(l)
        }
      }
    }
    return Array(stableSorted(out) { $0.q > $1.q }.prefix(4))
  }
  /* cpuKickPrep: true when the kick can be made; yields counts the page's yields (a sim each) */
  func cpuKickPrep(_ l: CPULine, _ balls: [GBall], _ L: CPUProfile, _ yields: inout Int) -> Bool {
    let cx = l.cx, cy = l.cy, e = clamp(s.RAIL_E[0] - 2 * s.RAIL_E[1], s.RAIL_E[2], s.RAIL_E[0])
    let C = cal!, vHit = cpuSpeedFor(l.d2 + 0.3) * 1.3 / (0.95 * M.max(l.cos, 0.25)) / e
    var pw = cpuPower(M.sqrt(vHit * vHit * C.keep * C.keep + 2 * C.roll * l.d1) / C.keep)
    let a1 = cpuKickAim(cx, cy, l.angle, pw, l.gx, l.gy, &yields), t0 = balls.first { $0.n == l.n }!
    var sol = a1 == nil ? nil : cpuKickSolve(cx, cy, a1!, pw, t0, l.psi0, &yields)
    let vObj = cpuSpeedFor(l.d2 + 0.3) * 1.3, vGot = sol != nil ? cpuKickErr(cx, cy, sol!.a, pw, t0, l.psi0, speed: true) : nil
    if sol != nil { yields += 1 }
    if let so = sol, let vg = vGot, vg < vObj && pw < 1 {
      pw = cpuPower(cpuSpeedAt(pw) * M.min(2.5, vObj / vg))
      sol = cpuKickSolve(cx, cy, so.a, pw, t0, l.psi0, &yields)
    }
    guard let so = sol else { return false }
    let a = so.a, side = l.k == 1 || l.k == 4, entry = -(M.cos(l.psi0) * s.CPU_MOUTH_N[l.k][0] + M.sin(l.psi0) * s.CPU_MOUTH_N[l.k][1])
    let win = 0.03 * (side ? entry : M.sqrt(entry)) / M.max(l.d2, 0.05)
    var inside = 0
    for (da, dp) in [(1.5 * L.noise, 0.0), (-1.5 * L.noise, 0), (0, 1.5 * L.pnoise), (0, -1.5 * L.pnoise)] {
      if let er = cpuKickErr(cx, cy, a + da, cpuPower(cpuSpeedAt(pw) * (1 + dp)), t0, l.psi0), abs(er) < win { inside += 1 }
      yields += 1
    }
    if inside == 0 { return false }
    l.angle = a; l.aimA = a; l.kOff = 0; l.kHist = []; l.q = 0.8 * Double(inside) / 4 * L.kickPot
    l.plans = [CPULine.Plan(p: pw), CPULine.Plan(p: pw), CPULine.Plan(p: pw)]
    return true
  }
  func cpuKickMiss(_ cx: Double, _ cy: Double, _ a: Double, _ p: Double, _ gx: Double, _ gy: Double) -> Double? {
    let tab = s.strike(s.newTable([Ball(0, cx, cy)]), a, p, Spin()), b = tab.balls[0]
    var best = Double.infinity, miss: Double? = nil, i = 0
    while i < 4800 && s.stepTable(tab) {
      i += 1
      if !b.on { return nil }
      guard let r = tab.rails[0], r > 0 else { continue }
      if r > 1 { break }
      let d = M.hypot(b.x - gx, b.y - gy), v = M.hypot(b.vx, b.vy)
      if d < best { best = d; miss = v > 0.4 ? ((gx - b.x) * b.vy - (gy - b.y) * b.vx) / v : nil }
      else if d > best + 0.05 { break }
    }
    return best < 0.3 ? miss : nil
  }
  func cpuKickAim(_ cx: Double, _ cy: Double, _ a0: Double, _ p: Double, _ gx: Double, _ gy: Double, _ yields: inout Int) -> Double? {
    var a = a0, m = cpuKickMiss(cx, cy, a, p, gx, gy), pa: Double? = nil, pm: Double? = nil
    yields += 1
    var i = 0
    while i < 4, let mm = m, abs(mm) > 0.001 {
      let step = pm != nil && abs(mm - pm!) > 1e-9 ? -mm * (a - pa!) / (mm - pm!) : 0.004 * -jsSign(mm)
      pa = a; pm = mm; a += clamp(step, -0.05, 0.05)
      m = cpuKickMiss(cx, cy, a, p, gx, gy)
      yields += 1
      i += 1
    }
    if let mm = m, abs(mm) < 0.004 { return a }
    return nil
  }
  func cpuKickErr(_ cx: Double, _ cy: Double, _ a: Double, _ p: Double, _ t: GBall, _ psi0: Double, speed: Bool = false) -> Double? {
    let ob = Ball(t.n, t.x, t.y); ob.on = t.on
    let tab = s.strike(s.newTable([Ball(0, cx, cy), ob]), a, p, Spin()), o = tab.balls[1]
    var i = 0
    while i < 4800 && s.stepTable(tab) {
      i += 1
      if tab.first != nil {
        return tab.first == t.n && (tab.rails[0] ?? 0) != 0 && (o.vx != 0 || o.vy != 0) ? (speed ? M.hypot(o.vx, o.vy) : wrapAngle(M.atan2(o.vy, o.vx) - psi0)) : nil
      }
    }
    return nil
  }
  func cpuKickSolve(_ cx: Double, _ cy: Double, _ a0: Double, _ p: Double, _ t: GBall, _ psi0: Double, _ yields: inout Int) -> (a: Double, k: Double)? {
    var a = a0, m = cpuKickErr(cx, cy, a, p, t, psi0), pa: Double? = nil, pm: Double? = nil, k = 0.0
    yields += 1
    var i = 0
    while i < 5, let mm = m, abs(mm) > 0.002 || k == 0 {
      let step = pm != nil && abs(mm - pm!) > 1e-9 ? -mm * (a - pa!) / (mm - pm!) : -mm / 40
      if let pmm = pm, let paa = pa, abs(a - paa) > 1e-9 { k = abs((mm - pmm) / (a - paa)) }
      pa = a; pm = mm; a += clamp(step, -0.02, 0.02)
      m = cpuKickErr(cx, cy, a, p, t, psi0)
      yields += 1
      i += 1
    }
    if let mm = m, abs(mm) < 0.004, k > 0 { return (a, k) }
    return nil
  }
  func cpuFlight(_ p: Double, _ e: Double) -> (vh: Double, vz: Double) {
    let v = s.speedOf(p), vd = v * M.sin(e)
    var vh = v * M.cos(e)
    if vd < V_SLATE { return (vh, 0) }
    vh -= M.min(MU_SLIDE * (1 + E_SLATE) * vd, vh / 3.5)
    return (vh, E_SLATE * vd)
  }
  func cpuJumpPower(_ e: Double, _ db: Double, _ w: Double, _ d1: Double) -> Double? {
    let R = s.BALL_R, R2 = 4 * R * R
    var p = 0.3
    while p <= 1.0001 {
      defer { p += 0.02 }
      let f = cpuFlight(p, e)
      if f.vz == 0 { continue }
      let land = 2 * f.vz * f.vh / G
      if land >= d1 - 2 * R { return nil }
      var ok = land > db + 2 * R
      var sx = -2 * R
      while ok && sx <= 2 * R + 1e-9 {
        let t = (db + sx) / f.vh, z = f.vz * t - G * t * t / 2
        ok = z * z >= M.max(0, R2 - w * w - sx * sx) + 0.006 * 0.006 && z > 0
        sx += R / 4
      }
      if ok { return p }
    }
    return nil
  }
  func cpuBlockLines(_ balls: [GBall], _ cx: Double, _ cy: Double, _ targets: [Int], _ L: CPUProfile) -> [CPULine] {
    let R = s.BALL_R
    var out: [CPULine] = []
    for n in targets {
      guard let t = balls.first(where: { $0.n == n }), t.on else { continue }
      for k in 0..<s.POCKET_AIM.count {
        let p = s.POCKET_AIM[k], m = s.CPU_MOUTH_N[k], side = k == 1 || k == 4, psi = M.atan2(p[1] - t.y, p[0] - t.x)
        let entry = -(M.cos(psi) * m[0] + M.sin(psi) * m[1])
        if entry < (side ? 0.55 : 0.5) || !cpuClear(balls, t.x, t.y, p[0], p[1], n) { continue }
        let gx = t.x - 2 * R * M.cos(psi), gy = t.y - 2 * R * M.sin(psi), ax = gx - cx, ay = gy - cy, d1 = M.hypot(ax, ay)
        if d1 < 0.2 || gx < R || gx > s.TL - R || gy < R || gy > s.TW - R { continue }
        let cos = (ax * M.cos(psi) + ay * M.sin(psi)) / d1
        if cos < L.minCos + 0.1 { continue }
        let ux = ax / d1, uy = ay / d1
        var block: [(a: Double, w: Double)] = []
        for o in balls where o.on && o.n != 0 && o.n != n {
          let a = (o.x - cx) * ux + (o.y - cy) * uy, w = (o.y - cy) * ux - (o.x - cx) * uy
          if a > 0 && a < d1 && abs(w) < 2 * R { block.append((a, w)) }
        }
        if block.count != 1 || M.hypot(t.x - gx, t.y - gy) < 1e-9 { continue }
        let b = block[0], d2 = M.hypot(p[0] - t.x, p[1] - t.y), wm = 0.03 * (side ? entry : M.sqrt(entry))
        let q0 = M.tanh(0.8 * wm * 2 * R * cos / (M.max(d1, 0.1) * M.max(d2, 0.05)) / L.noise)
        func base() -> CPULine {
          let l = CPULine(n: n, k: k, cx: cx, cy: cy, tx: t.x, ty: t.y, psi0: psi, psi: psi, angle: M.atan2(ay, ax), cos: cos, d1: d1, d2: d2, q: 0)
          l.special = true; return l
        }
        var plans: [CPULine.Plan] = []
        if b.a > 0.18 && d1 - b.a > 0.15 { for e in CPU_JUMP_E { if let pw = cpuJumpPower(e, b.a, b.w, d1) { plans.append(CPULine.Plan(p: pw, spin: Spin(x: 0, y: 0, e: e))) } } }
        if !plans.isEmpty { let l = base(); l.q = 0.25 * q0 * L.elev; l.jump = true; l.plans = plans; out.append(l) }
        if abs(b.w) > 0.4 * R && b.a > 0.12 && d1 - b.a > 0.25 {
          let sd: Double = b.w > 0 ? -1 : 1, off = sd * M.asin(clamp((2 * R + 0.004 - abs(b.w)) / b.a, 0, 0.5))
          let pw = cpuPower(1.15 * cpuSpeedFor(d1 + d2 + 0.3))
          let l = base(); l.q = 0.2 * q0 * L.elev; l.swerve = true
          l.plans = [off, 1.5 * off].map { CPULine.Plan(p: pw, spin: Spin(x: -sd * 0.7, y: 0, e: CPU_SWERVE_E), off: $0) }
          out.append(l)
        }
      }
    }
    return Array(stableSorted(out) { $0.q > $1.q }.prefix(4))
  }

  // MARK: scoring

  func cpuTargets(_ g: Game) -> [Int] {
    let all = E.legalTargets(g)
    if g.kind == "snooker" { return snkNearest(g, all) }
    if g.inHand != "kitchen" { return all }
    let up = all.filter { n in g.ball(n)!.x >= s.HEAD_X }
    return up.isEmpty ? all : up
  }
  func cpuChance(_ j: Game, _ who: Int, _ L: CPUProfile) -> Double {
    let cue = j.ball(0)!
    if j.inHand != nil || !cue.on { return 0.95 }
    var g2 = j
    if j.turn != who { g2.turn = who }
    let targets = E.legalTargets(g2)
    let ls = cpuLines(j.balls, cue.x, cue.y, targets, minCos: L.minCos, noise: L.noise)
    if !ls.isEmpty {
      let o = L.look ? ls.first { $0.n != ls[0].n } : nil
      return ls[0].q + (o.map { 0.25 * $0.q } ?? 0)
    }
    return targets.contains { n in let t = j.ball(n)!; return cpuClear(j.balls, cue.x, cue.y, t.x, t.y, n) } ? 0.02 : -0.3
  }
  func cpuDryCost(_ g: Game, _ j: Game, _ v: Double) -> Double {
    let dry = g.dry - CPU_DRY + 1
    if dry <= 0 || j.verdict?.foul != nil || j.turn == g.turn { return 0 }
    let still = g.balls.allSatisfy { b in
      guard let c = j.ball(b.n) else { return false }
      return !b.on || b.n == 0 || (c.on && M.hypot(c.x - b.x, c.y - b.y) < CPU_STILL)
    }
    return clamp(still ? 2 * CPU_DRY_COST * Double(dry) : M.min(CPU_DRY_MAX, CPU_DRY_COST * Double(dry)), 0, M.max(0, v + 390))
  }
  func cpuValue(_ g: Game, _ j: Game, _ L: CPUProfile) -> Double {
    if g.kind == "snooker" { return cpuSnookerValue(g, j, L) }
    let me = g.turn, R = g.rules
    if let w = j.winner { return w == me ? 1000 : -1000 }
    var v: Double
    let verdict = j.verdict!
    if verdict.foul != nil && (j.option == nil || j.option!.kind == "kitchenSpot") { v = -400 - (R.threeFoul != nil && j.fouls[me] >= 2 ? 150 : 0) }
    else if let o = j.option, o.who != me {
      var t = j; t.option = nil
      v = L.position ? M.min(-250 * cpuChance(t, 1 - me, L), 250 * cpuChance(t, me, L)) : -100
    } else if j.turn == me { v = 300 + (L.position && j.option == nil ? 250 * L.posW * cpuChance(j, me, L) : 0) }
    else { v = L.position ? -250 * cpuChance(j, j.turn, L) : 0 }
    if R.score != nil { v += (R.score == "numbers" ? 2 : 20) * Double(verdict.scored) }
    v -= cpuDryCost(g, j, v)
    if is8(g.kind), let mine = j.groups[me] { for n in verdict.potted { v += E.groupOf(n) == mine ? 12 : E.groupOf(n) != nil ? -12 : 0 } }
    return v
  }
  func cpuSight(_ balls: [GBall], _ x: Double, _ y: Double, _ targets: [Int]) -> Double {
    var best = 0.0
    for n in targets {
      let t = balls.first { $0.n == n }, D = t.map { M.hypot($0.x - x, $0.y - y) } ?? 0
      guard let t, t.on, D >= 2 * s.BALL_R else { continue }
      let sc = (D - 2 * s.BALL_R) / D
      if (best == 0 || D < best) && cpuClear(balls, x, y, x + (t.x - x) * sc, y + (t.y - y) * sc, n) { best = D }
    }
    return best
  }
  func cpuSpots(_ g: Game, _ targets: [Int], _ L: CPUProfile) -> [[Double]] {
    var keys: [Int] = [], best: [Int: (x: Double, y: Double, q: Double)] = [:], seen: [(x: Double, y: Double, D: Double)] = []
    func add(_ x: Double, _ y: Double) {
      if !E.canPlace(g, x, y) { return }
      let ls = cpuLines(g.balls, x, y, targets, minCos: L.minCos, noise: L.noise)
      if ls.isEmpty { let D = cpuSight(g.balls, x, y, targets); if D != 0 { seen.append((x, y, D)) }; return }
      let key = ls[0].n * 8 + ls[0].k, q = ls[0].q + (ls.count > 1 ? 0.1 * ls[1].q : 0)
      if best[key] == nil { keys.append(key); best[key] = (x, y, q) } else if best[key]!.q < q { best[key] = (x, y, q) }
    }
    let R = s.BALL_R
    if g.inHand == "kitchen" {
      for x in [s.HEAD_X - 0.02, s.HEAD_X - 0.2, s.HEAD_X - 0.4] { var y = 0.12; while y < s.TW - 0.1 { add(x, y); y += 0.1 } }
    } else if g.inHand == "D" {
      for dx in [0.01, 0.1, 0.2] {
        let h = M.sqrt(M.max(0, s.D_R * s.D_R - dx * dx)) - 0.005
        for i in -4...4 { add(s.HEAD_X - dx, s.TW / 2 + h * Double(i) / 4) }
      }
    } else {
      let cue = g.ball(0)!
      if cue.on { add(cue.x, cue.y) }
      for n in targets {
        let t = g.ball(n)!
        for p in s.POCKET_AIM {
          let a = M.atan2(p[1] - t.y, p[0] - t.x)
          for d in [0.2, 0.45, 0.8] { for off in [0, 0.3, -0.3] { add(t.x - M.cos(a + off) * (2 * R + d), t.y - M.sin(a + off) * (2 * R + d)) } }
        }
        for i in 0..<16 { for d in [0.25, 0.55] { add(t.x + M.cos(Double(i) * Double.pi / 8) * (2 * R + d), t.y + M.sin(Double(i) * Double.pi / 8) * (2 * R + d)) } }
      }
    }
    var out = Array(stableSorted(keys.map { best[$0]! }) { $0.q > $1.q }.prefix(L.place)).map { [$0.x, $0.y] }
    if !seen.isEmpty { let sp = seen.dropFirst().reduce(seen[0]) { a, b in b.D < a.D ? b : a }; out.append([sp.x, sp.y]) }
    var x = g.inHand == "kitchen" || g.inHand == "D" ? s.HEAD_X - 0.02 : s.TL / 4
    while out.isEmpty && x >= R {
      var y = s.TW / 2, i = 0
      while y > R && y < s.TW - R {
        if E.canPlace(g, x, y) { out.append([x, y]); break }
        i += 1; y = s.TW / 2 + (i % 2 == 1 ? 1 : -1) * Double((i + 1) / 2) * 0.05
      }
      x -= 0.05
    }
    x = s.TL - R
    while out.isEmpty && x >= R {
      var y = R
      while y <= s.TW - R { if E.canPlace(g, x, y) { out.append([x, y]); break }; y += 0.02 }
      x -= 0.02
    }
    return out
  }
  struct Safe { var angle: Double, power: Double, spin = Spin(), place: [Double]?, pri: Double, kick = false, call: ShotCall? = nil }
  func cpuSafeties(_ g: Game, _ cx: Double, _ cy: Double, _ targets: [Int], _ place: [Double]?) -> [Safe] {
    let R = s.BALL_R, R2 = 2 * R
    var out: [Safe] = []
    for n in targets {
      let t = g.ball(n)!, D = M.hypot(t.x - cx, t.y - cy), base = M.atan2(t.y - cy, t.x - cx)
      if D < R2 { continue }
      for b in [0, 0.5, -0.5, 0.85, -0.85] {
        let off = M.asin(clamp(b * R2 / D, -1, 1)), a = base + off
        let sn = D * M.sin(off), sd = D * M.cos(off) - M.sqrt(M.max(0, R2 * R2 - sn * sn))
        if !cpuClear(g.balls, cx, cy, cx + M.cos(a) * sd, cy + M.sin(a) * sd, n) { continue }
        for extra in [0.6, 1.8, 5] { out.append(Safe(angle: a, power: cpuPower(cpuSpeedFor(D + extra)), place: place, pri: 2 - D - abs(b) * 0.3 - extra * 0.1)) }
      }
      for (mx, my, axis, at) in [(2 * R - t.x, t.y, 0, R), (2 * (s.TL - R) - t.x, t.y, 0, s.TL - R), (t.x, 2 * R - t.y, 1, R), (t.x, 2 * (s.TW - R) - t.y, 1, s.TW - R)] {
        let ex = mx - cx, ey = my - cy, u = axis == 1 ? (at - cy) / ey : (at - cx) / ex
        if !(u > 0 && u < 1) { continue }
        let rx = cx + ex * u, ry = cy + ey * u, len = M.hypot(ex, ey)
        if s.POCKET_AIM.enumerated().contains(where: { k, p in M.hypot(p[0] - rx, p[1] - ry) < (k == 1 || k == 4 ? s.SIDE_W : s.CORNER_W) / 2 + 1.5 * R }) { continue }
        if !cpuClear(g.balls, cx, cy, rx, ry, -1) || !cpuClear(g.balls, rx, ry, t.x, t.y, n) { continue }
        out.append(Safe(angle: M.atan2(ey, ex), power: cpuPower(1.15 * cpuSpeedFor(len + 1)), place: place, pri: -len, kick: true))
      }
    }
    return stableSorted(out) { $0.pri > $1.pri }
  }

  // MARK: the search

  final class Rec {
    var angle: Double, power: Double, spin: Spin, place: [Double]?, call: ShotCall?, kick: Bool
    var j: Game, dir: Double?, first: Int?, value: Double, line: CPULine? = nil, f = 1.0, mean = 0.0
    init(_ s: (Double, Double, Spin, [Double]?, ShotCall?, Bool), j: Game, dir: Double?, first: Int?, value: Double) {
      angle = s.0; power = s.1; spin = s.2; place = s.3; call = s.4; kick = s.5; self.j = j; self.dir = dir; self.first = first; self.value = value
    }
  }

  public func cpuShot(_ g: Game, seed: Double, level: String) -> CPUShot {
    if g.kind == "bumper" { return cpuBumper(g, seed: seed, level: level) }
    if g.kind == "carom" { return cpuCarom(g, seed: seed, level: level) }
    let L = CPUProfile.record(CPUProfile.make(level, arch: arch, hill: hill), kind: g.kind)
    let rnd = cpuRng(seed * 2654435761 + 1), me = g.turn
    cpuCalibrate()
    func gauss() -> Double { (rnd() + rnd() + rnd() - 1.5) * 2 }
    func play(_ angle: Double, _ power: Double, _ spin: Spin, _ place: [Double]?, _ call: ShotCall?, _ intent: (String, Double)) -> CPUShot {
      let a = angle + gauss() * L.noise
      let p = cpuPower(cpuSpeedAt(power) * (1 + gauss() * L.pnoise))
      var sp = Spin(x: spin.x, y: spin.y)
      if L.snoise != 0 {
        var x = spin.x + gauss() * L.snoise, y = spin.y + gauss() * L.snoise
        let h = M.hypot(x, y)
        if h > 1 { x /= h; y /= h }
        sp = Spin(x: x, y: y)
      }
      if spin.e != 0 { sp.e = clamp(spin.e + gauss() * M.max(0.01, 12 * L.noise), 0.05, ELEV_MAX) }
      return CPUShot(angle: a, power: p, spin: sp, place: g.inHand != nil ? place : nil, call: call, intent: intent)
    }
    if g.breakShot && g.kind != "snooker" {
      let objs = g.balls.filter { $0.on && $0.n > 0 }
      let head = (!is8(g.kind) && g.kind != "straight" ? objs.first { $0.n == 1 } : nil) ?? objs.dropFirst().reduce(objs[0]) { a, b in b.x < a.x ? b : a }
      let place = [s.HEAD_X - 0.03, s.TW / 2 + (rnd() - 0.5) * 0.3]
      return play(M.atan2(head.y - place[1], head.x - place[0]), L.brk, Spin(x: 0, y: -0.2), place, nil, ("break", 1))
    }
    let need = E.callNeed(g)
    var safeCall: ShotCall? = nil
    if need != nil {
      if g.rules.safetyCall { var c = ShotCall(); c.safety = true; safeCall = c }
      else {
        let t = g.ball(E.legalTargets(g)[0])!
        var c = ShotCall(); c.ball = t.n
        c.pocket = s.POCKET_AIM.indices.dropFirst().reduce(0) { a, k in M.hypot(s.POCKET_AIM[k][0] - t.x, s.POCKET_AIM[k][1] - t.y) < M.hypot(s.POCKET_AIM[a][0] - t.x, s.POCKET_AIM[a][1] - t.y) ? k : a }
        safeCall = c
      }
    }
    func potCall(_ base: Game, _ l: CPULine) -> ShotCall? {
      guard E.callNeed(base) != nil else { return nil }
      var c = ShotCall(); c.ball = cpuPotBall(l); c.pocket = l.k
      if l.bank { c.bank = true } else if l.combo { c.combo = true } else if l.kick { c.kick = true }
      return c
    }
    func aimOf(_ l: CPULine, _ psi: Double, _ pl: CPULine.Plan?) -> Double { (l.aimA.map { $0 + l.kOff } ?? cpuAim(l, psi)) + (pl?.off ?? 0) }
    func kickLearn(_ l: CPULine, _ o: Rec) {
      guard o.first == l.n, let dir = o.dir else { return }
      let err = wrapAngle(dir - l.psi0)
      l.kHist.append([l.kOff, err])
      let h = l.kHist, a1 = h[h.count - 1][0], e1 = h[h.count - 1][1], prev = h.count > 1 ? h[h.count - 2] : nil
      let step = prev != nil && abs(e1 - prev![1]) > 1e-6 ? -e1 * (a1 - prev![0]) / (e1 - prev![1]) : e1 * 2 * s.BALL_R * l.cos / M.max(l.d1, 0.2)
      l.kOff = a1 + clamp(step, -0.03, 0.03)
    }
    let targets = cpuTargets(g), cue = g.ball(0)!, spots: [[Double]?] = g.inHand != nil ? cpuSpots(g, targets, L).map { Optional($0) } : [nil]
    var recs: [Rec] = []
    var sims = 0
    func sim(_ angle: Double, _ power: Double, _ spin: Spin, _ place: [Double]?, _ call: ShotCall?, kick: Bool = false, base: Game? = nil) -> Rec {
      let b = base ?? g
      var g1 = place != nil && base == nil ? E.placeCue(b, place![0], place![1]) : b
      if let c = call { g1.call = c }
      let o = cpuRun(g1.balls, angle, power, spin), j = E.judge(g1, RuleShot(o.r))
      sims += 1
      return Rec((angle, power, spin, place, call, kick), j: j, dir: o.dir, first: o.r.first, value: cpuValue(g1, j, L))
    }
    func worth(_ r: Rec, _ v: Double) -> Double { if let l = r.line, l.special { return l.q * v + (1 - l.q) * CPU_MISS }; return v }
    func learn(_ l: CPULine, _ o: Rec, _ psi: Double) -> Double {
      if o.first == l.n, let dir = o.dir, abs(wrapAngle(dir - l.psi0)) < 0.2 { return psi - wrapAngle(dir - l.psi0) }
      return psi
    }
    let plan = L.plan, reserve = L.robust * (L.look ? 5 + plan : 2)

    /* A: pot lines over the power ladder */
    var lines: [CPULine] = []
    for place in spots {
      for l in cpuLines(g.balls, place?[0] ?? cue.x, place?[1] ?? cue.y, targets, minCos: L.minCos, noise: L.noise) { l.place = place; lines.append(l) }
    }
    /* a personality's banks and combinations, from the cue ball or the two best spots in hand */
    if L.bank != 0 || L.combo != 0 {
      for place in spots.prefix(2) {
        let cx = place?[0] ?? cue.x, cy = place?[1] ?? cue.y
        if L.bank != 0 { for l in cpuBankLines(g.balls, cx, cy, targets, L) { l.place = place; lines.append(l) } }
        if L.combo != 0 { for l in cpuComboLines(g.balls, cx, cy, targets, L) { l.place = place; lines.append(l) } }
      }
    }
    lines = stableSorted(lines) { $0.q > $1.q }
    var special: [CPULine] = []
    if L.special > 0 && !(!lines.isEmpty && lines[0].q >= 0.35) {
      for place in spots.prefix(1) {
        let cx = place?[0] ?? cue.x, cy = place?[1] ?? cue.y
        if L.kickPot != 0 { for l in cpuKickLines(g.balls, cx, cy, targets, L) { l.place = place; special.append(l) } }
        if L.elev != 0 { for l in cpuBlockLines(g.balls, cx, cy, targets, L) { l.place = place; special.append(l) } }
      }
    }
    special = stableSorted(special) { $0.q > $1.q }
    let ladder = L.ladder.map { CPULine.Plan(f: $0) }
    for l in Array(lines.prefix(L.lines)) + Array(special.prefix(L.special)) {
      var psi = l.psi, potted = false
      if l.kick {
        if sims >= L.sims - reserve { continue }
        var y = 0
        let ok = cpuKickPrep(l, g.balls, L, &y)
        sims += y
        if !ok { continue }
      }
      let plans = l.plans ?? ladder
      for pl in plans {
        if sims >= L.sims - reserve { break }
        let o = sim(aimOf(l, psi, pl), pl.p ?? cpuPotPower(l, pl.f!), pl.spin ?? Spin(), l.place, potCall(g, l))
        o.line = l; o.f = pl.f ?? 1; recs.append(o)
        potted = potted || o.j.verdict!.potted.contains(cpuPotBall(l))
        if l.kick { if potted { break }; kickLearn(l, o) } else { psi = learn(l, o, psi) }
      }
      if L.retry && !potted && abs(psi - l.psi) > 0.0005 && sims < L.sims - reserve {
        let pl = plans[0]
        let o = sim(aimOf(l, psi, pl), pl.p ?? cpuPotPower(l, pl.f!), pl.spin ?? Spin(), l.place, potCall(g, l))
        o.line = l; o.f = pl.f ?? 1; recs.append(o)
      }
      l.psi = psi
    }

    /* B: spin and power variants on the lines that kept the turn or potted and scratched */
    var seenL = Set<ObjectIdentifier>()
    let keepers = stableSorted(recs.filter { r in !(r.line?.special ?? false) && (r.value >= 300 || (r.j.verdict!.scratch && r.j.verdict!.potted.contains(cpuPotBall(r.line!)))) }) { $0.value > $1.value }
      .filter { r in seenL.insert(ObjectIdentifier(r.line!)).inserted }
    for r in keepers.prefix(L.spin) {
      for sp in L.spins {
        if sims >= L.sims - reserve { break }
        let l = r.line!, angle = cpuAim(l, l.psi), power = cpuPotPower(l, r.f * sp[2]), spin = Spin(x: sp[0], y: sp[1]), call = potCall(g, l)
        var o = sim(angle, power, spin, l.place, call)
        o.line = l; o.f = r.f * sp[2]; recs.append(o)
        let psi = learn(l, o, l.psi)
        if sp[0] != 0 && L.retry && !o.j.verdict!.potted.contains(cpuPotBall(l)) && abs(psi - l.psi) > 0.0005 && sims < L.sims - reserve {
          o = sim(cpuAim(l, psi), power, spin, l.place, call)
          o.line = l; o.f = r.f * sp[2]; recs.append(o)
        }
      }
    }

    /* C: finalists mis-hit, scored on the mean; hard's softer stroke and next shot */
    let d = M.max(L.noise, 0.0005)
    var tested: [Rec] = []
    func test(_ r: Rec) {
      var sum = r.value, w = 1.0
      for k in L.look ? [1.0, -1, 2, -2] : [1, -1] {
        if sims >= L.sims { break }
        let o = sim(r.angle + k * d, r.power, r.spin, r.place, r.call, kick: r.kick)
        let wt = abs(k) > 1 ? 0.5 : 1
        sum += wt * o.value; w += wt
      }
      if L.look && sims < L.sims {
        let o = sim(r.angle, cpuPower(cpuSpeedAt(r.power) * (1 - 2 * L.pnoise)), r.spin, r.place, r.call, kick: r.kick)
        sum += o.value; w += 1
      }
      r.mean = sum / w
      if L.look && r.j.turn == me && r.j.winner == nil && sims < L.sims {
        let c = r.j.ball(0)!, nexts = c.on ? cpuLines(r.j.balls, c.x, c.y, cpuTargets(r.j), minCos: L.minCos, noise: L.noise) : []
        if plan > 0 && !nexts.isEmpty {
          var best = -Double.infinity
          outer: for (i, next) in nexts.prefix(plan).enumerated() {
            for f in i > 0 ? [1.25] : [1, 1.6] {
              if sims >= L.sims { break outer }
              let o = sim(next.angle, cpuPotPower(next, f), Spin(), nil, potCall(r.j, next), base: r.j)
              best = M.max(best, o.j.winner == me ? 1000 : o.value)
            }
          }
          if best > -Double.infinity { r.mean += clamp(0.3 * (best - 300), -120, 120) }
        } else if !nexts.isEmpty {
          let next = nexts[0], o = sim(next.angle, cpuPotPower(next, 1.25), Spin(), nil, potCall(r.j, next), base: r.j)
          r.mean += o.value >= 300 || o.j.winner == me ? 40 : -40
        } else if plan > 0 { r.mean -= 60 }
      }
      tested.append(r)
    }
    for r in recs { r.mean = r.value }
    recs = stableSorted(recs) { worth($0, $0.value) > worth($1, $1.value) }
    for r in recs.prefix(L.robust) { test(r) }
    func pool() -> [Rec] { tested.isEmpty ? recs : tested }

    /* D: safeties and kicks */
    if L.safe > 0 && (recs.isEmpty || pool().reduce(-Double.infinity) { M.max($0, worth($1, $1.mean)) } < L.safeBar) {
      var safes: [Safe] = [], got: [Rec] = []
      for place in spots.count > 2 ? [spots[0], spots[spots.count - 1]] : spots { safes += cpuSafeties(g, place?[0] ?? cue.x, place?[1] ?? cue.y, targets, place) }
      if g.kind == "snooker" && g.breakShot { safes += snkBreaks(g) }
      for i in safes.indices { safes[i].call = safeCall; if L.kick != 0 && safes[i].kick { safes[i].pri += 2 * L.kick } }
      if g.pushAvail && g.rules.pushOut {
        var push = ShotCall(); push.push = true
        safes += safes.prefix(L.push).map { var x = $0; x.call = push; x.pri -= 0.01; return x }
      }
      safes = stableSorted(safes) { $0.pri > $1.pri }
      for sf in safes.prefix(L.safe) {
        if sims >= L.sims - (L.robust > 0 ? 8 : 0) { break }
        let o = sim(sf.angle, sf.power, sf.spin, sf.place, sf.call, kick: sf.kick)
        o.mean = o.value; got.append(o); recs.append(o)
      }
      got = stableSorted(got) { $0.value > $1.value }
      if L.robust > 0 { for r in got.prefix(2) { test(r) } }
    }
    if recs.isEmpty {
      let place = spots[0], cx = place?[0] ?? cue.x, cy = place?[1] ?? cue.y, t = g.ball(targets[0])!
      return play(M.atan2(t.y - cy, t.x - cx), cpuPower(cpuSpeedFor(M.hypot(t.x - cx, t.y - cy) + 1.5)), Spin(), place, safeCall, ("blind", 0))
    }
    func legal(_ r: Rec) -> Bool { r.j.verdict!.foul == nil && !(r.j.winner != nil && r.j.winner != me) }
    let pick = [tested.filter(legal), recs.filter(legal), tested, recs].first { !$0.isEmpty }!
    func lean(_ r: Rec) -> Double { r.line != nil ? L.riskBonus : g.dry < CPU_DRY ? L.safeBonus : 0 }
    let best = pick.dropFirst().reduce(pick[0]) { a, b in worth(b, b.mean) + lean(b) > worth(a, a.mean) + lean(a) ? b : a }
    let intent: (String, Double)
    if let l = best.line { intent = (l.bank ? "bank" : l.combo ? "combo" : l.kick ? "kickpot" : l.jump ? "jump" : l.swerve ? "swerve" : "pot", l.q) }
    else { intent = (best.call?.push == true ? "push" : best.kick ? "kick" : "safety", 0) }
    return play(best.angle, best.power, best.spin, best.place, best.call, intent)
  }

  /* the CPU's answer to a choice pending for it */
  public func cpuOption(_ g: Game, level: String) -> String? {
    guard let o = g.option else { return nil }
    if g.kind == "snooker" { return cpuSnookerOption(g, level: level) }
    if g.kind == "carom" { return "respot" }
    if o.kind == "eightBreak" || o.kind == "kitchenSpot" { return "spot" }
    if o.kind == "breakMiss" { return "break" }
    let L = CPUProfile.make(level, arch: arch, hill: hill)
    var t = g; t.option = nil; t.turn = o.who
    let q = cpuChance(t, o.who, L)
    return q >= L.take ? "take" : o.kind == "badBreak" ? "rebreak" : o.kind == "breakFoul" ? o.choices[1] : o.kind == "breakOff" ? "kitchen" : "pass"
  }

  // MARK: snooker (sim 1j's CPU)

  static let SNK_NEAR = 7
  func snkNearest(_ g: Game, _ all: [Int]) -> [Int] {
    if all.count <= CPU.SNK_NEAR { return all }
    let c = g.ball(0)!
    let from: [[Double]] = g.inHand != nil || !c.on ? [[s.HEAD_X - 0.05, s.TW / 2 - 0.6 * s.D_R], [s.HEAD_X - 0.05, s.TW / 2 + 0.6 * s.D_R]] : [[c.x, c.y]]
    func key(_ n: Int) -> Double {
      let b = g.ball(n)!
      let d = from.dropFirst().reduce(M.hypot(b.x - from[0][0], b.y - from[0][1])) { M.min($0, M.hypot(b.x - $1[0], b.y - $1[1])) }
      return d + (from.contains { cpuClear(g.balls, $0[0], $0[1], b.x, b.y, n) } ? 0 : 10)
    }
    var k: [Int: Double] = [:]
    for n in all { k[n] = key(n) }
    return Array(stableSorted(all) { k[$0]! < k[$1]! }.prefix(CPU.SNK_NEAR))
  }
  func snkBreaks(_ g: Game) -> [Safe] {
    let reds = g.balls.filter { $0.on && isRed($0.n) }, R2 = 2 * s.BALL_R
    var out: [Safe] = []
    if reds.isEmpty { return out }
    for sd in [1.0, -1] {
      let t = reds.dropFirst().reduce(reds[0]) { a, b in sd * b.y * 10 + b.x > sd * a.y * 10 + a.x ? b : a }, place = [s.HEAD_X - 0.01, s.TW / 2 + sd * 0.6 * s.D_R]
      if !E.canPlace(g, place[0], place[1]) { continue }
      let D = M.hypot(t.x - place[0], t.y - place[1]), base = M.atan2(t.y - place[1], t.x - place[0])
      for (i, th) in [0.88, 0.8, 0.94].enumerated() {
        for (j, f) in [2.3, 2, 2.6].enumerated() {
          out.append(Safe(angle: base + sd * M.asin(th * R2 / D), power: cpuPower(cpuSpeedFor(D + f * s.TL)), place: place, pri: 10 - Double(i) - Double(j) - (sd < 0 ? 0.5 : 0)))
        }
      }
    }
    return stableSorted(out) { $0.pri > $1.pri }
  }
  func snkLeave(_ j: Game) -> Double {
    guard let c = j.ball(0), c.on, j.inHand == nil else { return 0 }
    let d = E.snookerOn(j).reduce(9.0) { m, n in let b = j.ball(n)!; return M.min(m, M.hypot(b.x - c.x, b.y - c.y)) }
    return 40 * M.min(1, d / (s.TL / 2)) + (c.x < s.HEAD_X ? 25 * (1 - c.x / s.HEAD_X) : 0)
  }
  func cpuSnookerValue(_ g: Game, _ j: Game, _ L: CPUProfile) -> Double {
    let me = g.turn, v = j.verdict!, sv = v.snk!
    if let w = j.winner { return w == me ? 1000 : -1000 }
    if let fo = sv.frameOver { return fo.winner == me ? 900 : -900 }
    var sc: Double
    if v.foul != nil { sc = -400 - 25 * Double(sv.pen) }
    else if j.turn == me { sc = 300 + 25 * Double(sv.pts) + (L.position ? 250 * L.posW * cpuChance(j, me, L) : 0) }
    else { sc = (L.position ? -250 * cpuChance(j, j.turn, L) : 0) + snkLeave(j) }
    return sc - cpuDryCost(g, j, sc)
  }
  public func cpuSnookerOption(_ g: Game, level: String) -> String {
    let o = g.option!, L = CPUProfile.make(level, arch: arch, hill: hill), who = o.who
    var base = g; base.option = nil; base.turn = who; base.snk!.free = nil
    if o.choices.contains("free") {
      let c = g.ball(0)
      func far(_ n: Int) -> Double { let b = g.ball(n)!; if let c, c.on, g.inHand == nil { return M.hypot(b.x - c.x, b.y - c.y) }; return 0 }
      var best: Int? = nil, bq = -Double.infinity
      for f in E.snkFreeBalls(base) {
        var t = base; t.snk!.free = f
        let q = cpuChance(t, who, L) - far(f) * 1e-3
        if q > bq { bq = q; best = f }
      }
      if let best { return "free:\(best)" }
    }
    if o.choices.contains("replace") && cpuChance(base, who, L) < L.take { return "replace" }
    return "play"
  }
}
