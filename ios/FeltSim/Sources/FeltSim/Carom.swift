/* index.html sim 1k: three-cushion carom, line for line: the game, its spots (UMB Art 27, 28), the
   count from the struck ball's own contacts, judgeCarom and chooseCarom; and its CPU (cpuCarom: ball-
   first fans and mirrored system shots through the physics, refined by hill climbing). Read the page's
   comments above judgeCarom and CPU_CAROM for the rules and the search. */
import Foundation

private typealias M = JSMath

public let C_CUE = [70, 71], C_RED = 72, CAROM_RACES = [5, 10, 15]

extension RulesEngine {
  public func caromGame(race: Int = 10, cushions: Int = 3, side: Int = 1) -> Game {
    let s: Double = side < 0 ? -1 : 1, need = cushions == 1 ? 1 : 3, rc = CAROM_RACES.contains(race) ? race : 10
    let balls = [GBall(n: C_CUE[0], x: sim.HEAD_X, y: sim.TW / 2 + s * 0.1524), GBall(n: C_CUE[1], x: sim.HEAD_X, y: sim.TW / 2), GBall(n: C_RED, x: sim.FOOT[0], y: sim.FOOT[1])]
    var g = Game(kind: "carom", balls: balls, groups: [nil, nil], open: false, breakShot: true, inHand: nil, fouls: [0, 0], rules: makeRules("carom"))
    g.striker = C_CUE[0]; g.race = rc; g.need = need; g.score = [0, 0]; g.innings = [1, 0]; g.run = 0; g.high = [0, 0]
    return g
  }
  public func caromTargets(_ g: Game) -> [Int] { g.breakShot ? [C_RED] : g.balls.filter { $0.on && $0.n != g.striker }.map { $0.n } }
  public func caromFree(_ balls: [GBall], _ x: Double, _ y: Double, _ skip: Int) -> Bool {
    let R = sim.BALL_R
    if !(x >= R && x <= sim.TL - R && y >= R && y <= sim.TW - R) { return false }
    return balls.allSatisfy { $0.n == skip || !$0.on || M.hypot($0.x - x, $0.y - y) >= 2 * R + RACK_GAP }
  }
  func caromSpot(_ balls: inout [GBall], _ n: Int, _ next: Int) {
    guard let bi = balls.firstIndex(where: { $0.n == n }) else { return }
    func spotOf(_ m: Int) -> [Double] { m == C_RED ? sim.FOOT : m == next ? [sim.HEAD_X, sim.TW / 2] : [sim.TL / 2, sim.TW / 2] }
    let own = spotOf(n)
    var at: [Double]? = nil, p = own
    for _ in 0..<3 {
      if caromFree(balls, p[0], p[1], n) { at = p; break }
      let on = balls.first { $0.n != n && $0.on && M.hypot($0.x - p[0], $0.y - p[1]) < 2 * sim.BALL_R + RACK_GAP }!
      p = spotOf(on.n)
    }
    var r = 0.01
    while at == nil && r < 0.6 {
      let m = Int(ceil(2 * Double.pi * r / 0.01))
      for i in 0..<m {
        let x = own[0] + r * M.cos(Double(i) * 2 * Double.pi / Double(m)), y = own[1] + r * M.sin(Double(i) * 2 * Double.pi / Double(m))
        if caromFree(balls, x, y, n) { at = [x, y]; break }
      }
      r += 0.01
    }
    if let at { balls[bi].x = at[0]; balls[bi].y = at[1]; balls[bi].vx = 0; balls[bi].vy = 0; balls[bi].wx = 0; balls[bi].wy = 0; balls[bi].wz = 0; balls[bi].on = true }
  }
  func caromTouch(_ balls: [GBall], _ n: Int) -> [Int] {
    guard let c = balls.first(where: { $0.n == n }) else { return [] }
    return balls.filter { $0.n != n && $0.on && M.hypot($0.x - c.x, $0.y - c.y) <= 2 * sim.BALL_R + 1e-6 }.map { $0.n }
  }
  public func caromCount(_ seq: [Int], _ need: Int = 3) -> CaromCount {
    var balls: [Int] = [], cushions = 0
    for e in seq {
      if e < 0 { cushions += 1; continue }
      if balls.contains(e) { continue }
      balls.append(e)
      if balls.count == 2 { break }
    }
    return CaromCount(first: balls.first, balls: balls, cushions: cushions, point: balls.count == 2 && cushions >= need)
  }
  func judgeCarom(_ g: Game, _ r: RuleShot) -> Game {
    var n = g
    let me = g.turn, op = 1 - me, need = g.need ?? 3
    n.balls = r.balls.map { var b = $0; b.vx = 0; b.vy = 0; b.wx = 0; b.wy = 0; b.wz = 0; return b }
    n.shots += 1
    let struck = r.cue ?? g.striker!, count = caromCount(r.seq, need), back = r.potted, s0 = r.seq.first
    var foul: String? = nil
    if struck != C_CUE[me] { foul = "struck the wrong cue ball" }
    else if !back.isEmpty { foul = back.contains(struck) ? "the cue ball left the table" : "a ball left the table" }
    else if g.breakShot && ((count.first != nil && count.first != C_RED) || (s0 ?? 0) < 0) { foul = "the red first on the break" }
    else if let s0, s0 >= 0, caromTouch(g.balls, struck).contains(s0) { foul = "played into a touching ball" }
    for x in back { caromSpot(&n.balls, x, C_CUE[op]) }
    let point = foul == nil && count.point
    var win: Int? = nil
    if point {
      n.score![me] += 1; n.run = (g.run ?? 0) + 1; n.high![me] = Swift.max(n.high![me], n.run!)
      if n.score![me] >= g.race! { win = me }
    } else { n.run = 0 }
    n.turn = point ? me : op
    if !point { n.innings![op] += 1 }
    n.winner = win; n.breakShot = false; n.inHand = nil
    n.striker = C_CUE[n.turn]
    n.fouls[me] = foul != nil ? n.fouls[me] + 1 : 0
    n.dry = point ? 0 : g.dry + 1
    n.option = win == nil && !caromTouch(n.balls, n.striker!).isEmpty ? GOption(kind: "respot", who: n.turn, choices: ["play", "respot"]) : nil
    var v = Verdict(foul: foul, keep: point && win == nil, win: win, why: win != nil ? "\(g.race!) points" : "", potted: [], scratch: false, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: n.option?.kind, scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    v.carom = CaromVerdict(point: point, count: count, back: back)
    n.verdict = v
    return n
  }
  func chooseCarom(_ g: Game, _ choice: String) -> Game? {
    guard let o = g.option, o.choices.contains(choice) else { return nil }
    var n = g
    n.option = nil
    if choice == "respot" {
      let move = [n.striker!] + caromTouch(n.balls, n.striker!)
      for x in move { if let i = n.balls.firstIndex(where: { $0.n == x }) { n.balls[i].on = false } }
      for x in move { caromSpot(&n.balls, x, n.striker!) }
    }
    var v = g.verdict
    v?.chose = choice; v?.chooser = o.who; v?.option = nil
    n.verdict = v
    return n
  }
}

/* the CPU at carom (cpuCarom) */
public struct CaromProfile: Sendable {
  public let sims: Int, fan: Int, powers: [Double], english: [Double], refine: Int, top: Int, robust: Int
  public var noise: Double, pnoise: Double
  public let leave: Bool
  public static func level(_ lv: String) -> CaromProfile {
    switch lv {
    case "easy": return CaromProfile(sims: 40, fan: 12, powers: [0.62], english: [0.3], refine: 12, top: 2, robust: 0, noise: 0.035, pnoise: 0.12, leave: false)
    case "hard": return CaromProfile(sims: 230, fan: 28, powers: [0.5, 0.64, 0.8], english: [0.5, -0.5, 0], refine: 120, top: 4, robust: 3, noise: 0.008, pnoise: 0.035, leave: true)
    case "hint": return CaromProfile(sims: 36, fan: 12, powers: [0.62], english: [0.3], refine: 10, top: 2, robust: 0, noise: 0, pnoise: 0, leave: false)
    default: return CaromProfile(sims: 120, fan: 20, powers: [0.55, 0.72], english: [0.4, -0.4], refine: 50, top: 3, robust: 2, noise: 0.016, pnoise: 0.065, leave: true)
    }
  }
}
let CPU_CT = 6.0

extension CPU {
  struct CRun { var r: ShotResult, cush: Int, hit: [Int], minD: Double, early: Bool }
  func cRun(_ g: Game, _ angle: Double, _ power: Double, _ spin: Spin, _ ball: Int, _ full: Bool) -> CRun {
    let tab = s.strike(s.newTable(toBalls(g.balls), cue: ball), angle, power, spin), cap = Int((CPU_CT / SIM_DT).rounded()), need = g.need ?? 3
    let cue = tab.balls.first { $0.n == ball }!
    var hit: [Int] = [], live = true, seen = 0, cush = 0, minD = Double.infinity, early = false, done = false, other: Ball? = nil, i = 0
    while live && i < cap {
      defer { i += 1 }
      live = s.stepTable(tab)
      tab.hits.removeAll(keepingCapacity: true)
      if done { if !full { break }; continue }
      while seen < tab.seq.count && !done {
        let e = tab.seq[seen]
        if e < 0 { cush += 1 } else if !hit.contains(e) { hit.append(e); if hit.count == 2 { done = true; early = cush < need } }
        seen += 1
      }
      if !done && hit.count == 1 && cush >= need && cue.on {
        if other == nil { other = tab.balls.first { $0.n != cue.n && $0.n != hit[0] } }
        minD = M.min(minD, M.hypot(cue.x - other!.x, cue.y - other!.y) - 2 * s.BALL_R)
      }
      if !done && !full && cue.still { break }
    }
    if live { for o in tab.balls { o.vx = 0; o.vy = 0; o.wx = 0; o.wy = 0; o.wz = 0 }; tab.end = "rest" }
    return CRun(r: s.resultOf(tab), cush: cush, hit: hit, minD: minD, early: early)
  }
  func cValue(_ g: Game, _ o: CRun, _ L: CaromProfile) -> Double {
    let need = g.need ?? 3, r = o.r, me = g.striker!, R = s.BALL_R
    if !r.potted.isEmpty || (g.breakShot && ((!o.hit.isEmpty && o.hit[0] != C_RED) || (r.seq.first ?? 0) < 0)) { return -2000 }
    if o.hit.count == 2 && !o.early {
      if !L.leave { return 1000 }
      let c = r.balls.first { $0.n == me }!, ob = r.balls.filter { $0.n != me }
      let rail: Double = M.min(M.min(c.x, s.TL - c.x), M.min(c.y, s.TW - c.y)) < 1.6 * R ? 40 : 0
      let kiss: Double = ob.contains { M.hypot($0.x - c.x, $0.y - c.y) < 2.6 * R } ? 60 : 0
      let pair = M.hypot(ob[0].x - ob[1].x, ob[0].y - ob[1].y)
      return 1000 + 50 * (1 - M.min(1, pair / 1.2)) - rail - kiss
    }
    if o.hit.isEmpty { return -900 - 50 * Double(Swift.max(0, need - o.cush)) }
    if o.early { return -500 - 80 * Double(need - o.cush) }
    if o.minD < Double.infinity { return -100 - 400 * M.min(1, M.max(0, o.minD)) }
    return -520 - 80 * Double(Swift.max(0, need - o.cush))
  }
  func cCut(_ cx: Double, _ cy: Double, _ t: GBall, _ f: Double) -> Double? {
    let D = M.hypot(t.x - cx, t.y - cy), b = f * 2 * s.BALL_R
    if D < 2 * s.BALL_R + 1e-6 || abs(b) >= D { return nil }
    return M.atan2(t.y - cy, t.x - cx) + M.asin(b / D)
  }
  func cMirror(_ x: Double, _ y: Double, _ i: Int, _ j: Int) -> [Double] {
    let R = s.BALL_R, W = s.TL - 2 * R, H = s.TW - 2 * R, u = x - R, v = y - R
    return [R + (i % 2 != 0 ? Double(i + 1) * W - u : Double(i) * W + u), R + (j % 2 != 0 ? Double(j + 1) * H - v : Double(j) * H + v)]
  }
  final class CRec { var angle: Double, power: Double, spin: Spin, first: Int? = nil, value = 0.0, mean = 0.0
    init(_ a: Double, _ p: Double, _ s: Spin) { angle = a; power = p; spin = s } }

  public func cpuCarom(_ g: Game, seed: Double, level: String) -> CPUShot {
    var L = CaromProfile.level(level); let P = CPUProfile.make(level, arch: arch, hill: hill)
    if !(P.nscale == 1 && P.pscale == 1) { L.noise *= P.nscale; L.pnoise *= P.pscale }
    let rnd = cpuRng(seed * 2654435761 + 11), me = g.striker!
    func gauss() -> Double { (rnd() + rnd() + rnd() - 1.5) * 2 }
    func play(_ r: CRec, _ intent: (String, Double)) -> CPUShot {
      let a = r.angle + gauss() * L.noise
      let p = clamp(s.powerFor(s.speedOf(r.power) * (1 + gauss() * L.pnoise)), 0, 1)
      return CPUShot(angle: a, power: p, spin: Spin(x: r.spin.x, y: r.spin.y), place: nil, call: nil, intent: intent, ball: me, first: r.first)
    }
    guard let c = g.ball(me), c.on, g.winner == nil else { return CPUShot(angle: 0, power: 0.3, spin: Spin(), place: nil, call: nil, intent: ("carom", 0), ball: me, first: nil) }
    let targets = E.caromTargets(g), firsts = g.balls.filter { $0.on && targets.contains($0.n) }
    var recs: [CRec] = []
    var sims = 0
    func sim(_ r: CRec) -> CRec {
      let o = cRun(g, r.angle, r.power, r.spin, me, L.leave)
      sims += 1
      r.first = o.hit.first; r.value = cValue(g, o, L); recs.append(r); return r
    }
    var cands: [(pri: Double, shot: CRec)] = []
    for t in firsts {
      for i in 0..<L.fan {
        let f = -0.92 + 1.84 * (Double(i) + 0.5) / Double(L.fan)
        guard let a = cCut(c.x, c.y, t, f) else { continue }
        let side: Double = f > 0 ? -1 : 1
        for p in L.powers { for e in L.english { cands.append((rnd() - abs(abs(f) - 0.5), CRec(a, p, Spin(x: side * e, y: 0.25)))) } }
      }
      for i in -3...3 {
        for j in -3...3 {
          let k = abs(i) + abs(j)
          if k < 2 || k > 3 { continue }
          let m = cMirror(t.x, t.y, i, j), d = M.hypot(m[0] - c.x, m[1] - c.y)
          cands.append((0.4 - d * 0.08 + rnd() * 0.3, CRec(M.atan2(m[1] - c.y, m[0] - c.x), clamp(L.powers[L.powers.count - 1] + 0.05 * (d - 4), 0.35, 0.95), Spin(x: 0, y: 0.2))))
        }
      }
    }
    cands = stableSorted(cands) { $0.pri > $1.pri }
    let budgetA = Swift.max(6, L.sims - L.refine - 2 * L.robust)
    for cd in cands { if sims >= budgetA { break }; _ = sim(cd.shot) }
    var top = Array(stableSorted(recs) { $0.value > $1.value }.prefix(L.top))
    var i = 0
    while i < L.refine && !top.isEmpty {
      defer { i += 1 }
      let j = i % top.count, base = top[j], k = 1 + i / top.count
      if base.value >= 1000 && !L.leave { continue }
      let a = base.angle + (rnd() - 0.5) * 0.05 / Double(k)
      let p = clamp(base.power * (1 + (rnd() - 0.5) * 0.24 / M.sqrt(Double(k))), 0.15, 1)
      let sx = clamp(base.spin.x + (rnd() < 0.4 ? (rnd() - 0.5) * 0.4 : 0), -0.8, 0.8)
      let r = sim(CRec(a, p, Spin(x: sx, y: base.spin.y)))
      if r.value > base.value { top[j] = r }
    }
    let best = stableSorted(recs) { $0.value > $1.value }
    for r in best { r.mean = r.value }
    for r in best.prefix(L.robust) {
      var sum = r.value
      for k in [1.0, -1] {
        let o = CRec(r.angle + k * M.max(L.noise, 0.0015) * 1.5, r.power, r.spin); o.first = r.first
        sum += sim(o).value
      }
      r.mean = sum / 3
    }
    let pick = best.prefix(Swift.max(1, L.robust)).reduce(best[0]) { a, b in b.mean > a.mean ? b : a }
    return play(pick, ("carom", pick.mean >= 1000 ? 0.85 : pick.mean > -200 ? 0.4 : 0.1))
  }
}
