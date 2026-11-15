/* index.html sim 1m, drills: measured practice. A drill is a short ladder of shots on fixed layouts, each shot scored 0
   to 100 from what it did (pots, the pocket, contacts, cushions, where the cue ball stopped), the drill's score the mean
   over its shots (a shot never reached scores 0) or its own total. Layouts are built at call time from table fractions
   and the trick shots' helpers (drillHelpers: cut on whichever side keeps the cue ball on the cloth), so they fit both
   pool sizes and both pocket styles. DRILL_LIB in the page's words; drillJudge, drillOver, drillTotal, drillTier,
   drillRun. Line for line. */
import Foundation

private typealias M = JSMath

/* the shot: its balls (the cue ball first), what it asks, the named pocket, the cue ball's ring, a target line, the
   break's box, the ball on */
public struct DrillShot {
  public var balls: [(Int, [Double])], say: String, pocket: Int? = nil
  public var zone: (at: [Double], full: Double, zero: Double)? = nil
  public var line: (x: Double, full: Double, zero: Double, lag: Bool)? = nil
  public var box: [Double]? = nil, target: Int? = nil
}
/* one shot judged: s 0 to 100, why, n (balls it counts), left (object balls up) */
public struct DrillJ: Equatable, Sendable { public var s: Int, why: String, n: Int, left: Int }
struct DrillScore { var s: Double, why: String, n: Int? = nil }

public struct DrillHelpers {
  public let T: TrickHelpers, s: Sim
  public var TL: Double { s.TL }
  public var TW: Double { s.TW }
  public var R: Double { s.BALL_R }
  public func at(_ fx: Double, _ fy: Double) -> [Double] { T.at(fx, fy) }
  public func lip(_ k: Int, _ d: Double) -> [Double] { T.lip(k, d) }
  public func line(_ p: [Double], _ k: Int, _ d: Double) -> [Double] { T.line(p, k, d) }
  public func along(_ p: [Double], _ q: [Double], _ u: Double, _ d: Double = 0) -> [Double] { T.along(p, q, u, d) }
  /* the cue ball for a cut of deg degrees on ball p into pocket k, dist metres from the ghost ball, on whichever side
     of the pot line keeps it on the cloth */
  public func cut(_ p: [Double], _ k: Int, _ deg: Double, _ dist: Double) -> [Double] {
    let G = T.line(p, k, 2), a0 = M.atan2(p[1] - s.POCKET_AIM[k][1], p[0] - s.POCKET_AIM[k][0])
    for sg in [1.0, -1.0] {
      let a = a0 + sg * deg * Double.pi / 180, c = [G[0] + M.cos(a) * dist, G[1] + M.sin(a) * dist]
      if c[0] > 3 * R && c[0] < TL - 3 * R && c[1] > 3 * R && c[1] < TW - 3 * R { return c }
    }
    return [G[0] + M.cos(a0) * dist, G[1] + M.sin(a0) * dist]
  }
}

/* 1 within full of the target, 0 past zero, a straight line between */
private func nearOf(_ d: Double, _ full: Double, _ zero: Double) -> Double { d <= full ? 1 : d >= zero ? 0 : (zero - d) / (zero - full) }
private func fracPct(_ f: Double) -> Double { (100 * max(0, min(1, f))).jsRound }
private func drillCue(_ r: ShotResult) -> Ball { r.balls.first { $0.n == 0 }! }
private func cmOf(_ m: Double) -> Int { Int((m * 100).jsRound) }
extension Double { var jsRound: Double { (self + 0.5).rounded(.down) } }
/* a pot of ball n into pocket k (any pocket when k is nil) */
private func potScore(_ r: ShotResult, _ n: Int, _ k: Int?) -> DrillScore {
  if r.potted.contains(0) { return DrillScore(s: 0, why: "Scratch.") }
  if !r.potted.contains(n) { return DrillScore(s: 0, why: r.first == nil ? "No contact." : "The \(n) stayed up.") }
  if let k, r.pocketOf[n] != k { return DrillScore(s: 0, why: "The \(n) went in the wrong pocket.") }
  return DrillScore(s: 100, why: "The \(n) is down.")
}
/* the cue ball's edge to the ring's centre, in metres */
private func ringGap(_ r: ShotResult, _ at: [Double], _ R: Double) -> Double { let c = drillCue(r); return max(0, M.hypot(c.x - at[0], c.y - at[1]) - R) }
/* a pot into the marked pocket, then the cue ball to the ring */
private func posScore(_ r: ShotResult, _ S: DrillShot, _ s: Sim) -> DrillScore {
  let p = potScore(r, 1, S.pocket)
  if p.s == 0 { return p }
  let z = S.zone!, d = ringGap(r, z.at, s.BALL_R), sc = fracPct(nearOf(d, z.full, z.zero))
  return DrillScore(s: sc, why: d <= z.full ? "Potted, and the cue ball is in the ring." : "Potted; the cue ball stopped \(cmOf(d)) cm from the ring.")
}

public struct Drill: Sendable {
  public let id: String, name: String, sub: String, shots: Int, tiers: [Int], goal: String, how: String
  let setup: @Sendable (DrillHelpers, Int, [Ball]?, Sim) -> DrillShot
  let score: @Sendable (ShotResult, DrillShot, Sim) -> DrillScore
  var end: (@Sendable (DrillJ) -> Bool)? = nil
  var total: (@Sendable ([DrillJ]) -> Int)? = nil
}

public let DRILL_LIB: [Drill] = [
  Drill(id: "long-pot", name: "Long Pots", sub: "Four pots from the far end", shots: 4, tiers: [50, 75, 100],
    goal: "Pot the 1 in the marked corner from the other end of the table.", how: "Each pot in the marked pocket scores 100; a miss, the wrong pocket or a scratch scores 0.",
    setup: { T, i, _, _ in
      let L: ([Double], [Double], Int) = [([0.22, 0.5], [0.78, 0.28], 2), ([0.2, 0.3], [0.76, 0.7], 5), ([0.12, 0.72], [0.84, 0.32], 2), ([0.15, 0.22], [0.8, 0.66], 5)][i]
      return DrillShot(balls: [(0, T.at(L.0[0], L.0[1])), (1, T.at(L.1[0], L.1[1]))], say: "Pot the 1 in the marked corner.", pocket: L.2)
    },
    score: { r, S, _ in potScore(r, 1, S.pocket) }),
  Drill(id: "cut-ladder", name: "Cut Ladder", sub: "Cuts from 15 to 75 degrees", shots: 5, tiers: [60, 80, 100],
    goal: "Cut the 1 into the marked corner at 15, 30, 45, 60 and 75 degrees.", how: "Each pot in the marked pocket scores 100; a miss scores 0.",
    setup: { T, i, _, _ in
      let b = T.at(0.74, 0.3), deg = 15 * (i + 1)
      return DrillShot(balls: [(0, T.cut(b, 2, Double(deg), 0.2 * T.TL)), (1, b)], say: "A \(deg) degree cut: pot the 1 in the marked corner.", pocket: 2)
    },
    score: { r, S, _ in potScore(r, 1, S.pocket) }),
  Drill(id: "power-ladder", name: "Power Ladder", sub: "Speed to a line, then the lag", shots: 5, tiers: [50, 75, 90],
    goal: "Stop the cue ball on each line, then lag it to the foot rail and back to the head rail.", how: "Full marks within a ball of the line (touching the head rail on a lag), none 12 balls away. A lag must reach the foot rail and come back.",
    setup: { T, i, _, _ in
      i < 3 ? DrillShot(balls: [(0, T.at(0.1, 0.5))], say: "Stop the cue ball on the line.", line: ([0.35, 0.55, 0.8][i] * T.TL, T.R, 12 * T.R, false))
        : DrillShot(balls: [(0, T.at(0.25, i == 3 ? 0.5 : 0.3))], say: "Lag: to the foot rail and back to the head rail.", line: (T.R, T.R, 12 * T.R, true))
    },
    score: { r, S, s in
      let c = drillCue(r), L = S.line!
      if !c.on { return DrillScore(s: 0, why: "Scratch.") }
      if L.lag && !((r.rails[0] ?? 0) >= 1 && c.x < s.TL / 2) { return DrillScore(s: 0, why: (r.rails[0] ?? 0) >= 1 ? "Too hard: it went back up the table." : "Short: a lag goes to the foot rail and back.") }
      let d = abs(c.x - L.x), sc = fracPct(nearOf(d, L.full, L.zero))
      return DrillScore(s: sc, why: d <= L.full ? (L.lag ? "Dead on the rail." : "On the line.") : L.lag ? "\(cmOf(d)) cm off the rail." : "\(cmOf(d)) cm \(c.x > L.x ? "long" : "short").")
    }),
  Drill(id: "break-box", name: "Break Box", sub: "Open the rack, cue ball in the box", shots: 3, tiers: [45, 65, 85],
    goal: "Break the 9-ball rack: hit the 1 first, open the rack, pot what you can and keep the cue ball in the box.",
    how: "Out of 100: 40 for the spread (how far the balls moved), 20 for two balls down, 40 for the cue ball in the box. A scratch loses the pots and the box.",
    setup: { T, _, _, s in DrillShot(balls: s.rack("9").map { ($0.n, [$0.x, $0.y]) }, say: "Break: open the rack and keep the cue ball in the box.", box: [0.38 * T.TL, 0.22 * T.TW, 0.62 * T.TL, 0.78 * T.TW]) },
    score: { r, S, s in
      if r.first != 1 { return DrillScore(s: 0, why: r.first == nil ? "No contact." : "Hit the 1 first.") }
      var at: [Int: [Double]] = [:]; for (n, p) in S.balls { at[n] = p }
      let obj = r.balls.filter { $0.n > 0 }, scr = r.potted.contains(0)
      let spread = obj.reduce(0.0) { a, b in a + (b.on ? min(1, M.hypot(b.x - at[b.n]![0], b.y - at[b.n]![1]) / (0.35 * s.TW)) : 1) } / Double(obj.count)
      let down = r.potted.filter { $0 > 0 }.count, c = drillCue(r), B = S.box!
      let out = c.on ? M.hypot(max(B[0] - c.x, 0, c.x - B[2]), max(B[1] - c.y, 0, c.y - B[3])) : Double.infinity
      let sc = (40 * spread + (scr ? 0 : 20 * min(1, Double(down) / 2) + 40 * nearOf(out, 0, 0.25 * s.TW))).jsRound
      return DrillScore(s: sc, why: "Spread \(Int(fracPct(spread)))%, \(down) down, " + (scr ? "scratch." : out == 0 ? "cue ball in the box." : "cue ball \(cmOf(out)) cm out."))
    }),
  Drill(id: "stop-shot", name: "Stop Shot Ladder", sub: "Pot it and stop dead", shots: 4, tiers: [50, 75, 90],
    goal: "Pot the 1 straight in and stop the cue ball where it hit, from further back each time.", how: "A pot is needed. Full marks with the cue ball in the ring, none a quarter of a metre away.",
    setup: { T, i, _, _ in
      let b = T.lip(2, 9)
      return DrillShot(balls: [(0, T.line(b, 2, 2 + [6, 12, 18, 24][i])), (1, b)], say: "Pot the 1 and stop the cue ball in the ring.", pocket: 2, zone: (T.line(b, 2, 2), T.R, 10 * T.R))
    },
    score: { r, S, s in posScore(r, S, s) }),
  Drill(id: "spin-control", name: "Follow and Draw", sub: "Pot it, roll or draw to the ring", shots: 4, tiers: [50, 75, 90],
    goal: "Pot the 1 and send the cue ball forward or back into the ring: follow, draw, a longer follow, a longer draw.", how: "A pot is needed. Full marks with the cue ball in the ring, none a third of a metre away.",
    setup: { T, i, _, _ in
      let L: (Double, Double, String, Double) = [(16, 12, "lip", 8), (10, 10, "line", 14), (22, 10, "lip", 11), (10, 16, "line", 24)][i], b = T.lip(2, L.0), fol = L.2 == "lip"
      return DrillShot(balls: [(0, T.line(b, 2, 2 + L.1)), (1, b)], say: fol ? "Follow: pot the 1 and roll the cue ball into the ring." : "Draw: pot the 1 and draw the cue ball back into the ring.",
                       pocket: 2, zone: (fol ? T.lip(2, L.3) : T.line(b, 2, L.3), 1.5 * T.R, 12 * T.R))
    },
    score: { r, S, s in posScore(r, S, s) }),
  Drill(id: "bank-ladder", name: "Bank Ladder", sub: "Off one rail into the pocket", shots: 4, tiers: [50, 75, 100],
    goal: "Bank the 1 off a rail into the marked pocket.", how: "A bank that drops in the marked pocket scores 100; no rail, the wrong pocket or a miss scores 0.",
    setup: { T, i, _, _ in
      let L: ([Double], [Double], Int) = [([0.4, 0.35], [0.5, 0.72], 1), ([0.3, 0.38], [0.44, 0.7], 1), ([0.6, 0.42], [0.76, 0.76], 2), ([0.74, 0.4], [0.6, 0.7], 0)][i]
      return DrillShot(balls: [(0, T.at(L.0[0], L.0[1])), (1, T.at(L.1[0], L.1[1]))], say: "Bank the 1 off the rail into the marked pocket.", pocket: L.2)
    },
    score: { r, S, _ in
      let p = potScore(r, 1, S.pocket)
      if p.s != 0 && !((r.rails[1] ?? 0) >= 1) { return DrillScore(s: 0, why: "No bank: the 1 went straight in.") }
      return p.s != 0 ? DrillScore(s: 100, why: "Banked in.") : p
    }),
  Drill(id: "kick-ladder", name: "Kick Ladder", sub: "A rail first, then the 1", shots: 3, tiers: [45, 70, 90],
    goal: "The 2 is in the way. Kick off a rail and hit the 1 first; pot it for full marks.", how: "A rail and then the 1 scores 70, the 1 down 30 more. The 2 first, no rail first or a scratch scores 0.",
    setup: { T, i, _, _ in
      let L: ([Double], [Double], Double) = [([0.3, 0.5], [0.7, 0.5], 0.5), ([0.25, 0.3], [0.75, 0.38], 0.5), ([0.2, 0.7], [0.78, 0.3], 0.6)][i], c = T.at(L.0[0], L.0[1]), b = T.at(L.1[0], L.1[1])
      return DrillShot(balls: [(0, c), (1, b), (2, T.along(c, b, L.2))], say: "Kick: a rail first, then the 1.")
    },
    score: { r, _, _ in
      if r.potted.contains(0) { return DrillScore(s: 0, why: "Scratch.") }
      if r.first != 1 { return DrillScore(s: 0, why: r.first == nil ? "No contact." : "The \(r.first!) was hit first.") }
      if !((r.kick ?? 0) >= 1) { return DrillScore(s: 0, why: "No rail before the 1.") }
      return r.potted.contains(1) ? DrillScore(s: 100, why: "Kicked in.") : DrillScore(s: 70, why: "A good hit; the 1 stayed up.")
    }),
  Drill(id: "safety-ladder", name: "Safety Ladder", sub: "Contact, a rail, cue ball to the ring", shots: 3, tiers: [50, 75, 90],
    goal: "Hit the 1, get a ball to a rail after contact, and leave the cue ball in the ring.", how: "Contact and a rail after it are needed. Full marks in the ring, none 40 cm away; potting the 1 halves it.",
    setup: { T, i, _, _ in
      let L: [[Double]] = [[[0.3, 0.5], [0.62, 0.42], [0.08, 0.5]], [[0.25, 0.3], [0.55, 0.55], [0.9, 0.12]], [[0.7, 0.3], [0.45, 0.6], [0.08, 0.86]]][i]
      return DrillShot(balls: [(0, T.at(L[0][0], L[0][1])), (1, T.at(L[1][0], L[1][1]))], say: "Safety: hit the 1, a rail after, cue ball to the ring.", zone: (T.at(L[2][0], L[2][1]), 2 * T.R, 14 * T.R))
    },
    score: { r, S, s in
      if r.potted.contains(0) { return DrillScore(s: 0, why: "Scratch.") }
      if r.first != 1 { return DrillScore(s: 0, why: "No contact with the 1.") }
      if !r.railAfter { return DrillScore(s: 0, why: "No rail after contact: a foul.") }
      let z = S.zone!, d = ringGap(r, z.at, s.BALL_R), up = !r.potted.contains(1), f = nearOf(d, z.full, z.zero) * (up ? 1 : 0.5)
      return DrillScore(s: fracPct(f), why: (up ? "" : "The 1 dropped: a safety leaves it up. ") + (d <= z.full ? "In the ring." : "\(cmOf(d)) cm from the ring."))
    }),
  Drill(id: "pattern-play", name: "Three-Ball Run", sub: "The 1, 2 and 3 in order", shots: 3, tiers: [33, 66, 100],
    goal: "Run out the 1, the 2 and the 3 in order from where they lie. A miss ends the run.", how: "Each ball potted in order scores a third. Hit the lowest ball first and pot it; a miss or a scratch ends the run.",
    setup: { T, _, prev, _ in
      let balls: [(Int, [Double])] = prev.map { $0.filter(\.on).map { ($0.n, [$0.x, $0.y]) } } ?? [(0, T.at(0.3, 0.6)), (1, T.at(0.55, 0.3)), (2, T.at(0.78, 0.62)), (3, T.at(0.35, 0.18))]
      let t = balls.map(\.0).filter { $0 > 0 }.min()!
      return DrillShot(balls: balls, say: "Pot the \(t).", target: t)
    },
    score: { r, S, _ in
      let p = potScore(r, S.target!, nil)
      if p.s != 0 && r.first != S.target { return DrillScore(s: 0, why: "Hit the \(S.target!) first.") }
      return p.s != 0 ? DrillScore(s: 100, why: p.why, n: r.potted.filter { $0 > 0 }.count) : p
    },
    end: { j in j.s == 0 || j.left == 0 },
    total: { js in Int(fracPct(Double(js.reduce(0) { $0 + $1.n }) / 3)) }),
  Drill(id: "pressure-nine", name: "Pressure 9", sub: "Five 9-balls, one miss ends it", shots: 5, tiers: [40, 60, 100],
    goal: "Pot the 9 in any pocket, five times, each harder than the last. One miss ends the drill.", how: "Each make scores 20. A miss or a scratch ends it.",
    setup: { T, i, _, _ in
      let b = [T.lip(5, 8), T.at(0.7, 0.66), T.lip(2, 14), T.at(0.56, 0.13), T.at(0.85, 0.52)][i]
      let c = [T.line(b, 5, 14), T.at(0.48, 0.48), T.line(b, 2, 30), T.at(0.36, 0.5), T.at(0.25, 0.25)][i]
      return DrillShot(balls: [(0, c), (9, b)], say: "Pot the 9 in any pocket.")
    },
    score: { r, _, _ in potScore(r, 9, nil) },
    end: { j in j.s == 0 }),
]
public let DRILL_TIERS = ["", "Bronze", "Silver", "Gold"]
public func drillById(_ id: String) -> Drill? { DRILL_LIB.first { $0.id == id } }
/* the drill is over: every shot played, or its end rule after the last one */
public func drillOver(_ d: Drill, _ js: [DrillJ]) -> Bool { js.count >= d.shots || (d.end != nil && !js.isEmpty && d.end!(js.last!)) }
/* the drill's score: the mean over every shot (those not reached score 0), or its own total */
public func drillTotal(_ d: Drill, _ js: [DrillJ]) -> Int { d.total?(js) ?? Int((Double(js.reduce(0) { $0 + $1.s }) / Double(d.shots)).jsRound) }
/* 0 none, 1 bronze, 2 silver, 3 gold */
public func drillTier(_ d: Drill, _ score: Int) -> Int { d.tiers.filter { score >= $0 }.count }

extension RulesEngine {
  /* shot i of drill d on the current table; prev: the balls the last shot left (the run-out) */
  public func drillShot(_ d: Drill, _ i: Int, _ prev: [Ball]? = nil) -> DrillShot { d.setup(DrillHelpers(T: TrickHelpers(s: sim), s: sim), i, prev, sim) }
  public func drillBalls(_ S: DrillShot) -> [GBall] { S.balls.map { GBall(n: $0.0, x: $0.1[0], y: $0.1[1]) } }
  /* the shot as a game: mode 'drill' (any ball first, no fouls), no ball in hand */
  public func drillGame(_ d: Drill, _ i: Int, _ prev: [Ball]? = nil) -> Game {
    var g = newGame("9")
    g.mode = "drill"; g.drill = d.id; g.shotN = i; g.balls = drillBalls(drillShot(d, i, prev)); g.breakShot = false; g.inHand = nil
    return g
  }
  public func drillJudge(_ d: Drill, _ S: DrillShot, _ r: ShotResult) -> DrillJ {
    let j = d.score(r, S, sim)
    return DrillJ(s: Int(max(0, min(100, j.s)).jsRound), why: j.why, n: j.n ?? 0, left: r.balls.filter { $0.n > 0 && $0.on }.count)
  }
  /* a whole drill in the sim: shots[i]; (js, total) */
  public func drillRun(_ d: Drill, _ shots: [Sim.Shot]) -> (js: [DrillJ], total: Int) {
    var js: [DrillJ] = [], prev: [Ball]? = nil
    for i in 0..<min(d.shots, shots.count) {
      let S = drillShot(d, i, prev), r = sim.simulateShot(drillBalls(S).map { Ball($0.n, $0.x, $0.y) }, shots[i])
      js.append(drillJudge(d, S, r))
      prev = r.balls
      if drillOver(d, js) { break }
    }
    return (js, drillTotal(d, js))
  }
}
