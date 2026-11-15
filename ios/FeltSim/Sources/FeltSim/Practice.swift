/* index.html sim 1e+, practice: the racks (newPractice: 8-ball's, 9-ball's, Chinese 8-ball's, a seeded scatter of
   PRACTICE_SCATTER balls, an empty table), its judge (practiceJudge: always the same player's shot, ball in hand anywhere
   after a scratch or with the toggle on, verdict.cleared when no object ball is left) and the free table's editing
   (addBall, removeBall). Line for line; the scatter's draws are rng's (mulberry32), so a seed lays the page's table. */
import Foundation

private typealias M = JSMath
public let PRACTICE_SCATTER = 7

/* rng: mulberry32, the page's seeded generator */
public func rng(_ seed: UInt32) -> () -> Double {
  var a = seed
  return {
    a = a &+ 0x6d2b79f5
    var t = a
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4294967296
  }
}

extension RulesEngine {
  /* canDrop: on the cloth, clear of every cushion surface and the pocket mouths, touching no ball on the table */
  public func canDrop(_ g: Game, _ x: Double, _ y: Double) -> Bool {
    var probe = Game(kind: "8", balls: [], fouls: [0, 0], rules: makeRules("8")); probe.inHand = "table"
    if !canPlace(probe, x, y) { return false }
    return g.balls.allSatisfy { !$0.on || M.hypot($0.x - x, $0.y - y) >= 2 * sim.BALL_R + RACK_GAP }
  }
  /* scatter: the cue ball on the head spot, then balls 1..count at seeded legal spots a ball's width off the cushions */
  public func scatter(_ seed: UInt32, _ count: Int = PRACTICE_SCATTER) -> [GBall] {
    let rnd = rng(seed), m = 3 * sim.BALL_R
    var g = Game(kind: "8", balls: [GBall(n: 0, x: sim.HEAD_X, y: sim.TW / 2)], fouls: [0, 0], rules: makeRules("8"))
    for n in 1...max(1, count) where count > 0 {
      for _ in 0..<400 {
        let x = m + rnd() * (sim.TL - 2 * m), y = m + rnd() * (sim.TW - 2 * m)
        if canDrop(g, x, y) && M.hypot(x - sim.HEAD_X, y - sim.TW / 2) > 0.15 { g.balls.append(GBall(n: n, x: x, y: y)); break }
      }
    }
    return g.balls
  }
  public func newPractice(_ layout: String, seed: UInt32 = 1) -> Game {
    var g = newGame(layout == "9" ? "9" : layout == "heyball" ? "heyball" : "8")
    g.mode = "practice"; g.layout = ["8", "9", "heyball", "scatter", "empty"].contains(layout) ? layout : "8"; g.seed = seed; g.hand = false
    if g.layout == "scatter" { g.balls = scatter(g.seed) }
    if g.layout == "empty" { g.balls = [GBall(n: 0, x: sim.HEAD_X, y: sim.TW / 2)] }
    if g.layout == "scatter" || g.layout == "empty" { g.breakShot = false; g.inHand = "table" }
    return g
  }
  /* practiceJudge: a finished practice shot; g untouched */
  public func practiceJudge(_ g: Game, _ r: RuleShot) -> Game {
    var n = g
    n.balls = r.balls.map { var b = $0; b.vx = 0; b.vy = 0; return b }
    n.shots += 1
    let pot = r.potted.filter { $0 != 0 }, scratch = r.potted.contains(0)
    n.turn = 0; n.winner = nil; n.breakShot = false
    n.inHand = scratch || g.hand ? "table" : nil
    n.dry = pot.isEmpty ? g.dry + 1 : 0
    var v = Verdict(foul: nil, keep: true, win: nil, why: "", potted: pot, scratch: scratch, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: nil, scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    v.cleared = onTable(n).isEmpty
    n.verdict = v
    return n
  }
  /* addBall: the lowest-numbered ball (1 to 15) not on the table dropped at (x, y); nil when the spot is not free or all are out */
  public func addBall(_ g: Game, _ x: Double, _ y: Double) -> Game? {
    if !canDrop(g, x, y) { return nil }
    let on = Set(onTable(g))
    guard let k = (1...15).first(where: { !on.contains($0) }) else { return nil }
    var n = g
    if let i = n.balls.firstIndex(where: { $0.n == k }) { n.balls[i].x = x; n.balls[i].y = y; n.balls[i].vx = 0; n.balls[i].vy = 0; n.balls[i].on = true }
    else { n.balls.append(GBall(n: k, x: x, y: y)) }
    n.balls.sort { $0.n < $1.n }
    return n
  }
  /* removeBall: ball k (not the cue ball) taken off */
  public func removeBall(_ g: Game, _ k: Int) -> Game? {
    if !(k > 0) || !g.balls.contains(where: { $0.n == k && $0.on }) { return nil }
    var n = g
    n.balls = n.balls.filter { $0.n != k }
    return n
  }
}
