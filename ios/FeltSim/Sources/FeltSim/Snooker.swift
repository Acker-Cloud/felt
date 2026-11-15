/* index.html sim 1j: snooker's rules, line for line (WPBSA; read the page's comment above judgeSnooker
   for the rules themselves). The referee's eye (snookered, any part, full ball) is pure geometry on the
   balls at rest. RulesTests replays whole frames the page's judge played. */
import Foundation

private typealias M = JSMath

public let S_COLS = [57, 58, 59, 60, 61, 62], S_BLACK = 62
public func isRed(_ n: Int) -> Bool { n >= 41 && n <= 55 }
public func snkValue(_ n: Int?) -> Int { guard let n else { return 0 }; return isRed(n) ? 1 : n >= 57 && n <= 62 ? n - 55 : 0 }
let SNK_NAME = [57: "yellow", 58: "green", 59: "brown", 60: "blue", 61: "pink", 62: "black"]
public func snkName(_ n: Int) -> String { isRed(n) ? "red" : SNK_NAME[n] ?? "cue ball" }

extension RulesEngine {
  public func inD(_ x: Double, _ y: Double) -> Bool { x <= sim.HEAD_X + 1e-9 && M.hypot(x - sim.HEAD_X, y - sim.TW / 2) <= sim.D_R + 1e-9 }

  public func snookerGame(frames: Int = 1, first: Int = 0, won: [Int] = [0, 0], high: [Int] = [0, 0]) -> Game {
    let balls = sim.snookerRack().map { GBall(n: $0.n, x: $0.x, y: $0.y) }
    var g = Game(kind: "snooker", balls: balls, turn: first, groups: [nil, nil], open: false, breakShot: true, inHand: "D", fouls: [0, 0], rules: makeRules("snooker"))
    g.score = [0, 0]; g.high = high; g.breaker = first
    g.snk = SnkState(on: .red, brk: 0, frames: frames == 3 ? 3 : 1, won: won, frame: won[0] + won[1] + 1)
    return g
  }
  public func snookerOn(_ g: Game) -> [Int] {
    let on = onTable(g), S = g.snk!, f = S.free.flatMap { on.contains($0) ? $0 : nil }
    switch S.on {
    case .red: return f.map { [$0] } ?? on.filter(isRed)
    case .colour: return on.filter { snkValue($0) > 1 }
    case .ball(let b): if let f { return [f] }; return on.contains(b) ? [b] : []
    case .none: if let f { return [f] }; return []
    }
  }
  func snookerSpot(_ balls: inout [GBall], _ n: Int) {
    guard let i = balls.firstIndex(where: { $0.n == n }) else { return }
    let R = sim.BALL_R
    func free(_ x: Double, _ y: Double) -> Bool { balls.indices.allSatisfy { j in j == i || !balls[j].on || M.hypot(balls[j].x - x, balls[j].y - y) >= 2 * R } }
    let sp = sim.SPOTS[n]!
    var at: [Double]? = free(sp[0], sp[1]) ? sp : nil
    var c = S_COLS.count - 1
    while at == nil && c >= 0 { let q = sim.SPOTS[S_COLS[c]]!; if free(q[0], q[1]) { at = q }; c -= 1 }
    var x = sp[0]
    while at == nil && x <= sim.TL - R { if free(x, sp[1]) { at = [x, sp[1]] }; x += 0.0005 }
    x = sp[0]
    while at == nil && x >= R { if free(x, sp[1]) { at = [x, sp[1]] }; x -= 0.0005 }
    if let at { balls[i].x = at[0]; balls[i].y = at[1]; balls[i].vx = 0; balls[i].vy = 0; balls[i].wx = 0; balls[i].wy = 0; balls[i].wz = 0; balls[i].on = true }
  }
  public func snookerLeft(_ g: Game) -> Int {
    let reds = g.balls.filter { $0.on && isRed($0.n) }.count, cols = S_COLS.filter { c in g.balls.contains { $0.n == c && $0.on } }
    if reds > 0 || g.snk!.on == .colour { return reds * 8 + (g.snk!.on == .colour ? 7 : 0) + 27 }
    return cols.reduce(0) { $0 + snkValue($1) }
  }
  public func snookersNeeded(_ g: Game, _ p: Int) -> Bool { g.score![1 - p] - g.score![p] > snookerLeft(g) }

  func snkClear(_ balls: [GBall], _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ pass: Set<Int>, _ noCush: Bool = false) -> Bool {
    let ex = bx - ax, ey = by - ay, L = M.hypot(ex, ey), Ld = L == 0 ? 1 : L, ux = ex / Ld, uy = ey / Ld, R2 = 2 * sim.BALL_R - 1e-9
    for o in balls {
      if !o.on || o.n == 0 || pass.contains(o.n) { continue }
      let s = (o.x - ax) * ux + (o.y - ay) * uy
      if s <= 0 { continue }
      let t = M.min(s, L)
      if M.hypot(o.x - ax - ux * t, o.y - ay - uy * t) < R2 { return false }
    }
    if noCush { return true }
    let rim = sim.BALL_R - 5e-4
    for c in sim.CUSH where segSeg(ax, ay, bx, by, c[0], c[1], c[2], c[3]) < rim { return false }
    for q in sim.JAW_ARCS where sim.segGap(ax, ay, bx, by, q[0], q[1]) < q[2] + rim { return false }
    return true
  }
  func segSeg(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double, _ dx: Double, _ dy: Double) -> Double {
    func side(_ px: Double, _ py: Double, _ qx: Double, _ qy: Double, _ rx: Double, _ ry: Double) -> Double {
      let v = (qx - px) * (ry - py) - (qy - py) * (rx - px); return v > 0 ? 1 : v < 0 ? -1 : v
    }
    let s1 = side(ax, ay, bx, by, cx, cy), s2 = side(ax, ay, bx, by, dx, dy), s3 = side(cx, cy, dx, dy, ax, ay), s4 = side(cx, cy, dx, dy, bx, by)
    if s1 * s2 < 0 && s3 * s4 < 0 { return 0 }
    return M.min(M.min(sim.segGap(ax, ay, bx, by, cx, cy), sim.segGap(ax, ay, bx, by, dx, dy)), M.min(sim.segGap(cx, cy, dx, dy, ax, ay), sim.segGap(cx, cy, dx, dy, bx, by)))
  }
  func snkEdges(_ balls: [GBall], _ x: Double, _ y: Double, _ t: GBall, _ pass: Set<Int>) -> Bool {
    let d = M.hypot(t.x - x, t.y - y), R2 = 2 * sim.BALL_R
    if d <= R2 + 1e-6 { return true }
    let a = M.atan2(t.y - y, t.x - x), w = M.asin(R2 / d), L = M.sqrt(d * d - R2 * R2)
    return [-1.0, 1].allSatisfy { s in snkClear(balls, x, y, x + L * M.cos(a + s * w), y + L * M.sin(a + s * w), pass, true) }
  }
  func snkPart(_ balls: [GBall], _ x: Double, _ y: Double, _ t: GBall, _ pass: Set<Int>) -> Bool {
    let d = M.hypot(t.x - x, t.y - y), R2 = 2 * sim.BALL_R
    if d <= R2 + 1e-6 { return true }
    let a = M.atan2(t.y - y, t.x - x)
    for i in -8...8 {
      let w = M.asin(Double(i) / 8 * R2 / d), sw = M.sin(w), L = d * M.cos(w) - M.sqrt(M.max(0, R2 * R2 - d * d * (sw * sw)))
      if snkClear(balls, x, y, x + L * M.cos(a + w), y + L * M.sin(a + w), pass) { return true }
    }
    return false
  }
  func snkAnyPart(_ g: Game) -> Bool {
    let on = snookerOn(g), pass = Set(on), ts = on.map { g.ball($0)! }
    return snkFrom(g).contains { p in ts.contains { snkPart(g.balls, p[0], p[1], $0, pass) } }
  }
  func snkFull(_ balls: [GBall], _ x: Double, _ y: Double, _ t: GBall, _ pass: Set<Int>) -> Bool {
    let d = M.hypot(t.x - x, t.y - y), R2 = 2 * sim.BALL_R
    if d <= R2 + 1e-6 { return true }
    let k = (d - R2) / d
    return snkClear(balls, x, y, x + (t.x - x) * k, y + (t.y - y) * k, pass)
  }
  func snkFrom(_ g: Game) -> [[Double]] {
    if g.inHand == nil, let c = g.ball(0), c.on { return [[c.x, c.y]] }
    var out = [[sim.HEAD_X, sim.TW / 2]]
    for r in [0.25, 0.5, 0.75, 0.98] {
      for i in 0...8 { let a = Double.pi / 2 + Double(i) * Double.pi / 8; out.append([sim.HEAD_X + r * sim.D_R * M.cos(a), sim.TW / 2 + r * sim.D_R * M.sin(a)]) }
    }
    var h = g; h.inHand = "D"
    return out.filter { canPlace(h, $0[0], $0[1]) }
  }
  func snkSnookered(_ g: Game) -> Bool {
    let on = snookerOn(g), pass = Set(on), ts = on.map { g.ball($0)! }
    if ts.isEmpty { return false }
    let from = snkFrom(g)
    return !from.isEmpty && from.allSatisfy { p in !ts.contains { snkEdges(g.balls, p[0], p[1], $0, pass) } }
  }
  func snkFullBall(_ g: Game) -> Bool {
    let on = snookerOn(g), pass = Set(on), ts = on.map { g.ball($0)! }
    return snkFrom(g).contains { p in ts.contains { snkFull(g.balls, p[0], p[1], $0, pass) } }
  }
  public func snkFreeBalls(_ g: Game) -> [Int] {
    let on = onTable(g), cur = g.snk!.on
    return S_COLS.filter { c in on.contains(c) && cur != .ball(c) && cur != .colour }
  }

  func judgeSnooker(_ g: Game, _ r: RuleShot) -> Game {
    var n = g
    let me = g.turn, op = 1 - me, pk = r.pocketOf, S = g.snk!
    n.balls = r.balls.map { var b = $0; b.vx = 0; b.vy = 0; return b }
    n.shots += 1
    n.option = nil; n.snk!.free = nil; n.snk!.prev = nil; n.snk!.replaced = false
    let pot = r.potted.filter { $0 != 0 }, scratch = r.potted.contains(0), first = r.first, targets = snookerOn(g)
    let F = S.free.flatMap { targets.contains($0) ? $0 : nil }
    let nom: Int? = S.on == .colour && first != nil && targets.contains(first!) ? first : nil
    let onVal: Int
    switch S.on { case .red: onVal = 1; case .colour: onVal = snkValue(nom); case .ball(let b): onVal = snkValue(b); case .none: onVal = 0 }
    func fair(_ x: Int) -> Bool {
      if x == F { return true }
      switch S.on { case .red: return isRed(x); case .colour: return x == nom; case .ball(let b): return x == b; case .none: return false }
    }
    func val(_ x: Int) -> Int { x == F ? onVal : snkValue(x) }
    let colsBefore = S_COLS.filter { c in g.balls.contains { $0.n == c && $0.on } }, redsBefore = g.balls.contains { $0.on && isRed($0.n) }
    var foul: String? = nil, worth = onVal
    func blame(_ why: String, _ x: Int? = nil) { foul = foul ?? why; if let x { worth = Swift.max(worth, val(x)) } }
    let hitOn = first != nil && targets.contains(first!)
    if first == nil { blame("missed every ball") } else if !hitOn { blame("hit the \(snkName(first!)) first", first!) }
    if S.on == .colour, let f = first, isRed(f) { worth = 7 }
    let s0 = r.seq.first ?? 0, cb = g.ball(0)
    if s0 > 0 && g.inHand == nil, let tb = g.balls.first(where: { $0.n == s0 && $0.on }), let cb, M.hypot(tb.x - cb.x, tb.y - cb.y) <= 2 * sim.BALL_R + 1e-6 {
      blame("a push stroke into a touching ball", s0)
    }
    for x in pot {
      if !((pk[x] ?? -1) >= 0) { blame("the \(snkName(x)) left the table", x) } else if !fair(x) { blame("potted the \(snkName(x))", x) }
    }
    if scratch { blame(pk[0] == -1 ? "the cue ball left the table" : "in-off") }
    if let o = r.over, !o.isEmpty { blame("a jump shot") }
    let pinkBlack = !redsBefore && colsBefore == [61, 62]
    if foul == nil, let F, pot.isEmpty, !pinkBlack {
      var next = n; next.turn = op; next.snk!.on = S.on; next.snk!.free = nil; next.inHand = nil
      var without = next; without.balls = next.balls.map { b in var c = b; if b.n == F { c.on = false }; return c }
      if snkSnookered(next) && !snkSnookered(without) { blame("snookered behind the free ball") }
    }
    let pen = foul != nil ? Swift.max(4, Swift.min(7, worth)) : 0
    let pts = foul != nil ? 0 : S.on == .red ? pot.count : !pot.isEmpty ? onVal : 0
    if foul != nil { n.score![op] += pen } else { n.score![me] += pts }
    let back = pot.filter { x in !isRed(x) && (foul != nil || S.on == .colour || x == F) }.sorted(by: >)
    func ownFree(_ x: Int) -> Bool { let sp = sim.SPOTS[x]!; return n.balls.allSatisfy { o in o.n == x || !o.on || M.hypot(o.x - sp[0], o.y - sp[1]) >= 2 * sim.BALL_R } }
    let order = back.filter(ownFree) + back.filter { !ownFree($0) }
    for x in order { snookerSpot(&n.balls, x) }
    func up(_ x: Int) -> Bool { n.balls.contains { $0.n == x && $0.on } }
    let reds = n.balls.contains { $0.on && isRed($0.n) }, cols = S_COLS.filter(up)
    let keep = foul == nil && pts > 0
    n.snk!.on = keep && S.on == .red ? .colour : reds ? .red : !cols.isEmpty ? .ball(cols[0]) : .none
    n.snk!.brk = keep ? S.brk + pts : 0
    n.high![me] = Swift.max(n.high![me], S.brk + pts)
    n.turn = keep ? me : op
    n.inHand = scratch ? "D" : nil
    n.breakShot = false
    n.dry = !pot.isEmpty ? 0 : g.dry + 1
    n.fouls[me] = foul != nil ? n.fouls[me] + 1 : 0
    let blackOnly = !redsBefore && colsBefore.count == 1 && colsBefore[0] == S_BLACK
    let inRun = S.replaced && S.missRun != nil && S.missRun!.p == me
    let missable = foul != nil && !hitOn && !blackOnly && (inRun || (!snookersNeeded(g, me) && !snookersNeeded(n, me)))
    let full = missable && snkFullBall(g), miss = missable && (full || snkAnyPart(g))
    let misses = miss && full ? (S.replaced && S.missRun != nil && S.missRun!.p == me ? S.missRun!.n : 0) + 1 : 0
    n.snk!.missRun = misses > 0 ? (me, misses) : nil
    var v = Verdict(foul: foul, keep: keep, win: nil, why: "", potted: pot.filter { !up($0) }, scratch: scratch, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: nil, scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    v.snk = SnkVerdict(pen: pen, pts: pts, nom: nom, back: back, brk: n.snk!.brk, ended: keep ? 0 : S.brk + pts, frameOver: nil, reblack: false,
                       miss: miss, misses: misses, warn: misses == 2, freeBall: .some(F))
    if misses >= 3 { return snookerEnd(n, v, me, op, how: "misses") }
    if cols.isEmpty || (S.on == .ball(S_BLACK) && (foul != nil || pts > 0)) { return snookerEnd(n, v, me, nil) }
    if foul != nil {
      var t = n; t.turn = op
      let free = snkSnookered(t)
      n.option = GOption(kind: miss ? "snkMiss" : free ? "snkFree" : "snkFoul", who: op, choices: ["play"] + (miss ? ["replace"] : []) + ["again"] + (free ? ["free"] : []), free: free, miss: miss)
      if miss { n.snk!.prev = SnkPrev(balls: g.balls, on: S.on, free: F, inHand: g.inHand) }
      v.option = n.option!.kind
    }
    n.verdict = v
    return n
  }
  /* concedeSnooker: player p concedes the frame (Concede Frame in the pause menu): the frame ends, the other wins it */
  public func concedeSnooker(_ g: Game, _ p: Int) -> Game {
    var n = g
    n.snk!.brk = 0
    var v = Verdict(foul: nil, keep: false, win: nil, why: "", potted: [], scratch: false, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: nil, scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    v.snk = SnkVerdict(pen: 0, pts: 0, nom: nil, back: [], brk: 0, ended: g.snk!.brk, frameOver: nil, reblack: false, miss: nil, misses: nil, warn: nil, freeBall: nil)
    n.verdict = v
    return snookerEnd(n, v, p, 1 - p)
  }
  func snookerEnd(_ n0: Game, _ v0: Verdict, _ ender: Int, _ winner: Int?, how: String? = nil) -> Game {
    var n = n0, v = v0
    n.option = nil; n.snk!.prev = nil; n.snk!.free = nil; n.snk!.missRun = nil; n.snk!.replaced = false
    if winner == nil && n.score![0] == n.score![1] {
      if let i = n.balls.firstIndex(where: { $0.n == 0 }) { n.balls[i].on = false }
      snookerSpot(&n.balls, S_BLACK)
      let lot = cpuRng(Double(n.shots) * 2654435761 + Double(n.score![0]) * 40503)() < 0.5 ? 0 : 1
      n.snk!.on = .ball(S_BLACK); n.turn = lot; n.inHand = "D"; n.snk!.reblack = true; n.snk!.brk = 0
      n.option = GOption(kind: "snkBlack", who: lot, choices: ["play", "pass"])
      v.snk!.reblack = true; v.keep = false; v.option = "snkBlack"
      n.verdict = v
      return n
    }
    let w = winner ?? (n.score![0] > n.score![1] ? 0 : 1)
    n.snk!.won[w] += 1
    v.snk!.frameOver = FrameOver(winner: w, score: n.score!, frame: n.snk!.frame, won: n.snk!.won, conceded: winner != nil && how == nil, forfeit: how != nil ? "three misses" : nil)
    if n.snk!.won[w] * 2 > n.snk!.frames {
      n.winner = w; n.turn = w; n.inHand = nil; n.snk!.on = .none; n.snk!.brk = 0
      v.win = w; v.why = winner == nil ? "the frame" : how != nil ? "three misses" : "conceded"
      n.verdict = v
      return n
    }
    var nx = snookerGame(frames: n.snk!.frames, first: 1 - n.breaker, won: n.snk!.won, high: n.high!)
    nx.verdict = v
    return nx
  }
  func chooseSnooker(_ g: Game, _ choice: String) -> Game? {
    guard let o = g.option else { return nil }
    let parts = choice.split(separator: ":"), c = String(parts[0]), arg = parts.count > 1 ? Int(parts[1]) : nil
    if !o.choices.contains(c) { return nil }
    let who = o.who, off = 1 - who
    if c == "free" && !(arg.map { snkFreeBalls(g).contains($0) } ?? false) { return nil }
    if c == "replace" && g.snk!.prev == nil { return nil }
    var n = g
    n.option = nil; n.snk!.prev = nil; n.snk!.free = nil; n.snk!.replaced = false; n.call = nil
    if c != "replace" { n.snk!.missRun = nil }
    if c == "play" { n.turn = who }
    else if c == "free" { n.turn = who; n.snk!.free = arg }
    else if c == "again" || c == "pass" { n.turn = off }
    else {
      let p = g.snk!.prev!
      n.balls = p.balls; n.snk!.on = p.on; n.snk!.free = p.free; n.inHand = p.inHand; n.turn = off; n.snk!.brk = 0; n.snk!.replaced = true
    }
    var v = g.verdict
    v?.chose = c; v?.chooser = who; v?.snk?.nominated = .some(n.snk!.free); v?.option = nil
    n.verdict = v
    return n
  }
}
