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
