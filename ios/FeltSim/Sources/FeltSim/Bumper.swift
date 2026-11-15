/* index.html's sim 1g, the rules half: bumper pool's balls, rack, spots and judgeBumper, line for line
   (rules.json's bumper games, by the page's judge). The table (posts, cups, the octagon) is in Physics.swift. */
import Foundation

private typealias M = JSMath

/* the balls: red 21-25 for player 0, white 31-35 for player 1; 21 and 31 are the marked balls */
public let B_BALLS = [[21, 22, 23, 24, 25], [31, 32, 33, 34, 35]], B_MARK = [21, 31]
public func bOwner(_ n: Int) -> Int { n >= 30 ? 1 : 0 }

extension RulesEngine {
  /* where a player's five start, marked ball first */
  public func bStart(_ p: Int) -> [[Double]] {
    let TW = sim.TW, TL = sim.TL
    let pts: [[Double]] = sim.BED_LINES != nil
      ? [[0.26, TW / 2], [0.09, TW / 2 - 0.17], [0.09, TW / 2 + 0.17], [0.25, TW / 2 - 0.24], [0.25, TW / 2 + 0.24]]
      : [[0.31, TW / 2], [0.1, TW / 2 - 0.17], [0.1, TW / 2 + 0.17], [0.26, TW / 2 - 0.22], [0.26, TW / 2 + 0.22]]
    return pts.map { [p != 0 ? TL - $0[0] : $0[0], $0[1]] }
  }
  public func bumperRack() -> [GBall] {
    var out: [GBall] = []
    for p in [0, 1] { for (i, q) in bStart(p).enumerated() { out.append(GBall(n: B_BALLS[p][i], x: q[0], y: q[1])) } }
    return out
  }
  public func bumperGame() -> Game {
    if sim.TABLE != "bumper" { sim.setTable("bumper") }
    var g = Game(kind: "bumper", balls: bumperRack(), turn: 0, groups: [nil, nil], open: false, breakShot: false, inHand: nil, fouls: [0, 0], rules: makeRules("bumper"))
    g.opening = 1; g.openPot = [false, false]; g.striker = B_MARK[0]
    return g
  }
  public func bMarkUp(_ balls: [GBall], _ p: Int) -> Bool { balls.contains { $0.n == B_MARK[p] && $0.on } }
  public func bumperStrikers(_ g: Game, _ p: Int? = nil) -> [Int] {
    let p = p ?? g.turn
    if (g.opening ?? 0) != 0 && bMarkUp(g.balls, p) { return [B_MARK[p]] }
    return g.balls.filter { $0.on && bOwner($0.n) == p }.map { $0.n }
  }
  /* a ball may stand at (x, y): on the bed, clear of the posts and the cups, touching no ball but skip */
  public func bumperFree(_ balls: [GBall], _ x: Double, _ y: Double, _ skip: Int) -> Bool {
    let R = sim.BALL_R
    if sim.BED_LINES != nil ? !sim.bedIn(x, y, R) : !(x >= R && x <= sim.TL - R && y >= R && y <= sim.TW - R) { return false }
    if sim.BUMPERS.contains(where: { M.hypot($0[0] - x, $0[1] - y) < R + BUMPER_R + 0.002 }) { return false }
    for (k, p) in sim.POCKETS.enumerated() where M.hypot(p[0] - x, p[1] - y) < sim.POCKET_R[k] + R { return false }
    return balls.allSatisfy { $0.n == skip || !$0.on || M.hypot($0.x - x, $0.y - y) >= 2 * R }
  }
  /* a ball returned: on its owner's marked spot, or the nearest free point to it (rings 1 cm apart) */
  func bumperSpot(_ balls: inout [GBall], _ n: Int) {
    guard let bi = balls.firstIndex(where: { $0.n == n }) else { return }
    let s0 = bStart(bOwner(n))[0], sx = s0[0], sy = s0[1]
    var at: [Double]? = nil
    var r = 0.0
    while at == nil && r < 0.5 {
      let m = r != 0 ? Int((2 * Double.pi * r / 0.01).rounded(.up)) : 1
      for i in 0..<m {
        let x = sx + r * M.cos(Double(i) * 2 * Double.pi / Double(m)), y = sy + r * M.sin(Double(i) * 2 * Double.pi / Double(m))
        if bumperFree(balls, x, y, n) { at = [x, y]; break }
      }
      r += 0.01
    }
    if let at { balls[bi].x = at[0]; balls[bi].y = at[1]; balls[bi].vx = 0; balls[bi].vy = 0; balls[bi].wx = 0; balls[bi].wy = 0; balls[bi].wz = 0; balls[bi].on = true }
  }
  /* the foul's penalty: one of player p's balls down for them, the marked ball while up, else the furthest from their cup */
  func bumperBonus(_ balls: inout [GBall], _ p: Int) -> Int? {
    let T = sim.POCKETS[1 - p], mine = balls.filter { $0.on && bOwner($0.n) == p }
    guard let first = mine.first else { return nil }
    let d = { (o: GBall) in M.hypot(o.x - T[0], o.y - T[1]) }
    let b = mine.first { $0.n == B_MARK[p] } ?? mine.dropFirst().reduce(first) { a, o in d(o) > d(a) ? o : a }
    let i = balls.firstIndex { $0.n == b.n }!
    balls[i].on = false; balls[i].vx = 0; balls[i].vy = 0
    return b.n
  }
  /* the ball a player strikes by default: the marked ball while it is on, else the one nearest the cup */
  public func bumperStriker(_ g: Game, _ p: Int) -> Int? {
    let T = sim.POCKETS[1 - p], mine = g.balls.filter { $0.on && bOwner($0.n) == p }
    guard let first = mine.first else { return nil }
    let d = { (o: GBall) in M.hypot(o.x - T[0], o.y - T[1]) }
    return (mine.first { $0.n == B_MARK[p] } ?? mine.dropFirst().reduce(first) { a, b in d(b) < d(a) ? b : a }).n
  }
  func judgeBumper(_ g: Game, _ r: RuleShot) -> Game {
    var n = g
    let me = g.turn, op = 1 - me, mark = B_MARK[me], pk = r.pocketOf
    n.balls = r.balls.map { var b = $0; b.vx = 0; b.vy = 0; return b }
    n.shots += 1
    let struck = r.cue ?? g.striker
    var kept: [Int] = [], back: [Int] = [], gave: [Int] = []
    var foul: String? = nil, markDown = !g.balls.contains { $0.n == mark && $0.on }
    let opening = g.opening ?? 0
    if struck == nil || bOwner(struck!) != me || !g.balls.contains(where: { $0.n == struck! && $0.on }) { foul = "struck a ball not your own" }
    else if opening != 0 && struck! != mark && !markDown { foul = "the opening shot is the marked ball" }
    for x in r.potted {
      let k = pk[x]
      if k == nil || k! < 0 { foul = foul ?? "a ball left the table"; back.append(x) }
      else if bOwner(x) == op { foul = foul ?? "potted the opponent's ball"; gave.append(x) }
      else if k! == me { foul = foul ?? "into your own cup"; back.append(x) }
      else if x != mark && !markDown { foul = foul ?? "an unmarked ball before the marked one"; back.append(x) }
      else { if x == mark { markDown = true }; kept.append(x) }
    }
    if foul != nil { back.append(contentsOf: kept); kept = [] }
    for x in back { bumperSpot(&n.balls, x) }
    let dropped = foul != nil ? bumperBonus(&n.balls, op) : nil
    let left = { (p: Int) in n.balls.filter { $0.on && bOwner($0.n) == p }.count }
    var win: Int? = nil, why = "", turn = foul == nil && !kept.isEmpty ? me : op
    if left(op) == 0 { win = op; why = "all five balls down" } else if foul == nil && left(me) == 0 { win = me; why = "all five balls down" }
    if opening == 1 { turn = 1; n.opening = 2; n.openPot = [kept.contains(B_MARK[0]), false] }
    else if opening == 2 {
      n.opening = 0
      let pot = [g.openPot?[0] ?? false, kept.contains(B_MARK[1])]
      if foul != nil || pot[0] { turn = 0 }
      else if pot[1] { turn = 1 }
      else {
        let d = { (p: Int) -> Double in let b = n.balls.first { $0.n == B_MARK[p] }!, T = self.sim.POCKETS[1 - p]; return b.on ? M.hypot(b.x - T[0], b.y - T[1]) : 9 }
        turn = d(1) < d(0) ? 1 : 0
      }
    }
    n.fouls[me] = foul != nil ? n.fouls[me] + 1 : 0
    n.winner = win; n.inHand = nil
    n.turn = win != nil ? me : turn
    n.striker = win != nil ? nil : (n.opening ?? 0) != 0 && bMarkUp(n.balls, n.turn) ? B_MARK[n.turn] : bumperStriker(n, n.turn)
    n.dry = !kept.isEmpty || !gave.isEmpty || dropped != nil ? 0 : g.dry + 1
    var v = Verdict(foul: foul, keep: win == nil && n.turn == me, win: win, why: why, potted: kept, scratch: false, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: nil, scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    v.bumper = BumperVerdict(gave: gave, back: back, dropped: dropped, opening: opening)
    n.verdict = v
    return n
  }
}

/* the CPU at bumper pool (cpuBumper): geometry proposes (the straight line and the banks to the far cup, at a ladder
   of powers, and a fan all round), the physics decides (bRun, judged and scored by bValue), the best refined, the
   finalists re-run mis-hit and scored on the mean. Every draw in the page's order. */
public struct BumperProfile: Sendable {
  public let sims: Int, fan: Int, ladder: [Double], refine: Int, robust: Int
  public var noise: Double, pnoise: Double
  public let strikers: Int
  public static func level(_ lv: String) -> BumperProfile {
    switch lv {
    case "easy": return BumperProfile(sims: 26, fan: 8, ladder: [1.1, 1.7], refine: 6, robust: 0, noise: 0.03, pnoise: 0.08, strikers: 1)
    case "hard": return BumperProfile(sims: 150, fan: 20, ladder: [0.85, 1.2, 1.7, 2.4], refine: 50, robust: 3, noise: 0.004, pnoise: 0.015, strikers: 3)
    case "hint": return BumperProfile(sims: 30, fan: 12, ladder: [1.2, 1.8], refine: 6, robust: 0, noise: 0, pnoise: 0, strikers: 1)
    default: return BumperProfile(sims: 70, fan: 14, ladder: [0.9, 1.3, 1.9], refine: 20, robust: 2, noise: 0.011, pnoise: 0.04, strikers: 2)
    }
  }
}
let CPU_BT = 5.0

extension CPU {
  /* the cue speed that rolls a ball about d metres, as a power */
  func bPowerFor(_ d: Double) -> Double { s.powerFor((2 * s.MU_ROLL * G * M.max(0.05, d)).squareRoot() * 1.4) }
  func bRun(_ g: Game, _ shot: BShot) -> (r: ShotResult, minD: Double) {
    let tab = s.strike(s.newTable(toBalls(g.balls), cue: shot.ball), shot.angle, shot.power, Spin(x: 0, y: 0)), T = s.POCKETS[1 - g.turn]
    let b = tab.balls.first { $0.n == shot.ball }!, cap = Int((CPU_BT / SIM_DT).rounded())
    var minD = M.hypot(b.x - T[0], b.y - T[1]), live = true, i = 0
    while live && i < cap {
      live = s.stepTable(tab)
      if b.on { minD = M.min(minD, M.hypot(b.x - T[0], b.y - T[1])) }
      tab.hits.removeAll(keepingCapacity: true)
      i += 1
    }
    if live { for o in tab.balls { o.vx = 0; o.vy = 0; o.wx = 0; o.wy = 0; o.wz = 0 }; tab.end = "rest" }
    return (s.resultOf(tab), b.on ? minD : 0)
  }
  /* in the shadow of cup k's guard pair: near by distance, but no straight line in */
  func bShadow(_ b: GBall, _ k: Int) -> Bool {
    let T = s.POCKETS[k], N = s.CPU_MOUTH_N[k], u = (b.x - T[0]) * N[0] + (b.y - T[1]) * N[1], w = abs((b.x - T[0]) * N[1] - (b.y - T[1]) * N[0])
    return u > 0.05 && u < 0.22 && w < 0.07
  }
  func bValue(_ g: Game, _ j: Game, _ minD: Double) -> Double {
    let me = g.turn
    if let w = j.winner { return w == me ? 10000 : -10000 }
    let vd = j.verdict!
    var v = (vd.foul != nil ? -500.0 : 0) + 400 * Double(vd.potted.count) + (j.turn == me ? 150 : 0)
    for b in j.balls {
      if !b.on { continue }
      let p = bOwner(b.n), T = s.POCKETS[1 - p], d = M.min(1, M.hypot(b.x - T[0], b.y - T[1]))
      if p == me { v -= (b.n == B_MARK[me] ? 120 : 60) * d + (s.BED_LINES != nil && bShadow(b, 1 - p) ? 90 : 0) }
      else { v += 60 * d - (d < 0.2 ? 120 : 0) }
    }
    return v - (vd.potted.isEmpty ? 300 * M.min(minD, 0.5) : 0)
  }
  struct BShot { var angle: Double, power: Double, ball: Int }
  final class BRec { let shot: BShot; let value: Double; var mean = 0.0; init(_ s: BShot, _ v: Double) { shot = s; value = v } }

  public func cpuBumper(_ g: Game, seed: Double, level: String) -> CPUShot {
    /* cpuRecord(P, 'bumper'): the level's table, its noise scaled by the person's (exactly the table at a bare level) */
    var L = BumperProfile.level(level); let P = CPUProfile.make(level, arch: arch, hill: hill)
    if !(P.nscale == 1 && P.pscale == 1) { L.noise *= P.nscale; L.pnoise *= P.pscale }
    let rnd = cpuRng(seed * 2654435761 + 7), me = g.turn, T = s.POCKETS[1 - me]
    func gauss() -> Double { (rnd() + rnd() + rnd() - 1.5) * 2 }
    func play(_ sh: BShot, _ intent: (String, Double)) -> CPUShot {
      let a = sh.angle + gauss() * L.noise
      let p = clamp(s.powerFor(s.speedOf(sh.power) * (1 + gauss() * L.pnoise)), 0, 1)
      return CPUShot(angle: a, power: p, spin: Spin(x: 0, y: 0), place: nil, call: nil, intent: intent, ball: sh.ball, first: nil)
    }
    var balls = E.bumperStrikers(g, me).compactMap { n in g.balls.first { $0.n == n } }.filter { $0.on }
    if balls.isEmpty { return CPUShot(angle: 0, power: 0.2, spin: Spin(x: 0, y: 0), place: nil, call: nil, intent: ("bumper", 0), ball: g.striker, first: nil) }
    /* the marked ball first, then the rest nearest the cup first */
    let dT = { (b: GBall) in M.hypot(b.x - T[0], b.y - T[1]) }
    let cmp = { (a: GBall, b: GBall) -> Double in
      let k = Double((b.n == B_MARK[me] ? 1 : 0) - (a.n == B_MARK[me] ? 1 : 0))
      return k != 0 ? k : dT(a) - dT(b)
    }
    balls = stableSorted(balls) { cmp($0, $1) < 0 }
    var recs: [BRec] = []
    var sims = 0
    func sim(_ sh: BShot) -> BRec {
      let o = bRun(g, sh), j = E.judge(g, RuleShot(o.r))
      sims += 1
      let r = BRec(sh, bValue(g, j, o.minD)); recs.append(r); return r
    }
    /* A: lines and fans, the likeliest first */
    var cands: [(pri: Double, shot: BShot)] = []
    for b in balls.prefix(L.strikers) {
      var lines: [[Double]] = [[T[0], T[1], 0]]
      for m in s.bumperBanks(T) { lines.append([m[0], m[1], 1]) }
      for l in lines {
        let x = l[0], y = l[1], bank = l[2], d = M.hypot(x - b.x, y - b.y)
        for f in L.ladder { cands.append((-d - bank * 0.2 - abs(f - 1.2) * 0.1, BShot(angle: M.atan2(y - b.y, x - b.x), power: bPowerFor(d * f + 0.2), ball: b.n))) }
      }
      let off = rnd() * 2 * Double.pi / Double(L.fan)
      for i in 0..<L.fan {
        let pri = -3 - rnd(), pw = bPowerFor(1.4 + rnd() * 1.6)
        cands.append((pri, BShot(angle: off + Double(i) * 2 * Double.pi / Double(L.fan), power: pw, ball: b.n)))
      }
    }
    cands = stableSorted(cands) { $0.pri > $1.pri }
    let mis = s.BED_LINES != nil ? 4 : 2, budgetA = Swift.max(4, L.sims - L.refine - mis * L.robust)
    for c in cands { if sims >= budgetA { break }; _ = sim(c.shot) }
    /* B: refine the best three by keeping what scores better */
    var top = Array(stableSorted(recs) { $0.value > $1.value }.prefix(3))
    var i = 0
    while i < L.refine && !top.isEmpty {
      let j = i % top.count, base = top[j], step = 0.03 / Double(1 + i / top.count)
      let a = base.shot.angle + (rnd() - 0.5) * 2 * step
      let p = clamp(base.shot.power * (1 + (rnd() - 0.5) * 0.3), 0.02, 1)
      let r = sim(BShot(angle: a, power: p, ball: base.shot.ball))
      if r.value > base.value { top[j] = r }
      i += 1
    }
    /* C: the finalists mis-hit, scored on the mean; on the octagon also a little soft and a little firm */
    let best = stableSorted(recs) { $0.value > $1.value }
    for r in best { r.mean = r.value }
    for r in best.prefix(L.robust) {
      var sum = r.value
      for k in [1.0, -1] { var sh = r.shot; sh.angle = r.shot.angle + k * M.max(L.noise, 0.003) * (mis > 2 ? 2.5 : 1.5); sum += sim(sh).value }
      if mis > 2 { for k in [1.0, -1] { var sh = r.shot; sh.power = clamp(s.powerFor(s.speedOf(r.shot.power) * (1 + k * M.max(L.pnoise, 0.01) * 1.5)), 0, 1); sum += sim(sh).value } }
      r.mean = sum / Double(1 + mis)
    }
    let pick = best.prefix(Swift.max(1, L.robust)).reduce(best[0]) { a, b in b.mean > a.mean ? b : a }
    return play(pick.shot, ("bumper", pick.mean >= 400 ? 0.8 : 0.3))
  }

  /* auto aim's suggestion (suggestBumper): the ball to strike and a clear line for it to the far cup, straight or off
     one cushion, the shortest, the marked ball first while it is up; with none clear, the 'hint' search's shot */
  public func suggestBumper(_ g: Game) -> (angle: Double, n: Int?, k: Int)? {
    if g.winner != nil { return nil }
    let me = g.turn, k = 1 - me, T = s.POCKETS[k], R = s.BALL_R
    let balls = E.bumperStrikers(g, me).compactMap { n in g.balls.first { $0.n == n } }.filter { $0.on }
    if balls.isEmpty { return nil }
    func clear(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ skip: Int) -> Bool {
      s.BUMPERS.allSatisfy { s.segGap(ax, ay, bx, by, $0[0], $0[1]) >= R + BUMPER_R }
        && g.balls.allSatisfy { !$0.on || $0.n == skip || s.segGap(ax, ay, bx, by, $0.x, $0.y) >= 2 * R }
    }
    let markOn = balls.contains { $0.n == B_MARK[me] }
    var best: (len: Double, angle: Double, n: Int)? = nil
    for b in balls {
      let extra: Double = markOn && b.n != B_MARK[me] ? 2 : 0
      var paths: [(Double, Double, [Double]?)] = [(T[0], T[1], nil)]
      if let BL = s.BED_LINES {
        for m in s.bumperBanks(T) {
          let mx = m[0], my = m[1], j = Int(m[2]), l = BL[j], nx = l[0], ny = l[1], c = l[2], sg = s.CUSH[j]
          let den = nx * (mx - b.x) + ny * (my - b.y), u = den != 0 ? (c + R - nx * b.x - ny * b.y) / den : -1
          let px = b.x + (mx - b.x) * u, py = b.y + (my - b.y) * u, sl = M.hypot(sg[2] - sg[0], sg[3] - sg[1])
          let along = ((px - sg[0]) * (sg[2] - sg[0]) + (py - sg[1]) * (sg[3] - sg[1])) / (sl * sl)
          if u > 0 && u < 1 && along > R / sl && along < 1 - R / sl { paths.append((mx, my, [px, py])) }
        }
      } else {
        for q in [(2 * R - T[0], T[1], 0, R), (2 * (s.TL - R) - T[0], T[1], 0, s.TL - R), (T[0], 2 * R - T[1], 1, R), (T[0], 2 * (s.TW - R) - T[1], 1, s.TW - R)] {
          let (mx, my, ax, at) = q, u = ax != 0 ? (at - b.y) / (my - b.y) : (at - b.x) / (mx - b.x)
          if u > 0 && u < 1 { paths.append((mx, my, [b.x + (mx - b.x) * u, b.y + (my - b.y) * u])) }
        }
      }
      for (x, y, bounce) in paths {
        let ok = bounce.map { clear(b.x, b.y, $0[0], $0[1], b.n) && clear($0[0], $0[1], T[0], T[1], b.n) } ?? clear(b.x, b.y, T[0], T[1], b.n)
        let len = M.hypot(x - b.x, y - b.y) + (bounce != nil ? 0.3 : 0) + extra
        if ok && (best == nil || len < best!.len) { best = (len, M.atan2(y - b.y, x - b.x), b.n) }
      }
    }
    if let b = best { return (b.angle, b.n, k) }
    let sh = cpuShot(g, seed: 1, level: "hint")
    return (sh.angle, sh.ball, k)
  }
}
