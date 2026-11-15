/* index.html sim 1e (the rules engine) for the pocket games: 8-ball, Chinese 8-ball, 9-ball, 10-ball,
   rotation and straight pool, line for line. A game is a value (copyGame is a copy); judge(g, r)
   returns the next game with its verdict and never touches g. RulesTests replays whole games the page
   played (tools/ios-golden.cjs) and compares every judge and chooseOption field by field.
   Snooker, carom and bumper pool have their own modules (not ported yet). */
import Foundation

private typealias M = JSMath

/* a rule option the page writes as false or a string (threeFoul) is nil or the string here */
public struct RuleSet: Sendable {
  public var id: String, game: String, name: String, source: String, ring = false
  public var calls = "none", obvious = true, breakAny = false, breakRails = 0, badBreak: String? = nil, breakScratch = "kitchen"
  public var breakFoul: String? = nil, eightOffBreak = "spot", groupBy = "pot", kitchenSpot = false, tempClaim = false, threeBall = 0
  public var safetyCall = true, gameBallBreak = "spot", earlyGameBall = "win", pushOut = false, threeFoul: String? = nil, stalemate = 0
  public var missed = "end", safetyPots = "stay", foulHand = "table", score: String? = nil, race = 0, players = 2, offSpot = "spot"
  public var call = CallConfig(), locked = false, made = false
}
public struct CallConfig: Sendable, Equatable {
  public var mode = "official", detail = "pocket", safety = true, eight = false, obvious = true, change = true
  public init() {}
}

public let RULESETS: [String: RuleSet] = {
  func r(_ id: String, _ game: String, _ name: String, _ source: String, _ f: (inout RuleSet) -> Void = { _ in }) -> RuleSet {
    var s = RuleSet(id: id, game: game, name: name, source: source); f(&s); return s
  }
  let list = [
    r("8-house", "8", "8-ball, house rules", "felt house rule") { $0.breakAny = true },
    r("8-wpa", "8", "8-ball, WPA", "WPA world standardized rules") {
      $0.breakAny = true; $0.calls = "all"; $0.breakRails = 4; $0.badBreak = "rerack"; $0.breakFoul = "choice"; $0.kitchenSpot = true; $0.tempClaim = true
      $0.gameBallBreak = "option"; $0.offSpot = "stay"
    },
    r("9-house", "9", "9-ball, house rules", "felt house rule") { $0.gameBallBreak = "win"; $0.threeFoul = "loss" },
    r("9-wpa", "9", "9-ball, WPA", "WPA world standardized rules") {
      $0.gameBallBreak = "win"; $0.threeFoul = "loss"; $0.pushOut = true; $0.breakRails = 4; $0.badBreak = "foul"; $0.breakScratch = "table"; $0.threeBall = 3
      $0.kitchenSpot = true; $0.missed = "option"; $0.offSpot = "stay"
    },
    r("10-wpa", "10", "10-ball, WPA", "WPA world standardized rules") {
      $0.calls = "all"; $0.obvious = true; $0.safetyCall = false; $0.breakRails = 4; $0.badBreak = "foul"; $0.breakScratch = "table"; $0.kitchenSpot = true
      $0.gameBallBreak = "spot"; $0.earlyGameBall = "spot"; $0.pushOut = true; $0.threeFoul = "loss"; $0.missed = "option"; $0.offSpot = "stay"
    },
    r("straight-wpa", "straight", "Straight pool (14.1), WPA", "WPA world standardized rules") {
      $0.calls = "all"; $0.obvious = true; $0.breakAny = true; $0.breakRails = 2; $0.badBreak = "option"; $0.kitchenSpot = true
      $0.threeFoul = "minus15"; $0.missed = "spot"; $0.safetyPots = "spot"; $0.foulHand = "position"; $0.score = "count"; $0.race = 50
    },
    r("rotation", "rotation", "Rotation (61)", "felt house rule, after the BCA game") { $0.score = "numbers"; $0.race = 61; $0.missed = "spot"; $0.safetyPots = "spot" },
    r("bumper", "bumper", "Bumper pool", "felt house rule"),
    r("carom", "carom", "Three-cushion", "UMB rules, simplified"),
    r("snooker", "snooker", "Snooker", "WPBSA rules, simplified"),
    r("heyball", "heyball", "Chinese 8-ball", "WPA Rules of Heyball, effective 2025-08-16") {
      $0.breakAny = true; $0.calls = "none"; $0.breakRails = 4; $0.badBreak = "rerack"; $0.breakFoul = "rerack"; $0.eightOffBreak = "loss"; $0.groupBy = "first"
      $0.kitchenSpot = true; $0.gameBallBreak = "option"; $0.offSpot = "stay"
    },
    r("9-ring", "9", "9-ball ring", "ring game, felt house rule") { $0.ring = true; $0.gameBallBreak = "win" },
    r("rotation-ring", "rotation", "Rotation ring", "ring game, felt house rule, after the BCA game") { $0.ring = true; $0.score = "numbers"; $0.race = 61; $0.missed = "spot"; $0.safetyPots = "spot" },
    r("straight-ring", "straight", "Around the table", "straight pool, ring game, felt house rule") {
      $0.ring = true; $0.calls = "all"; $0.obvious = true; $0.breakAny = true; $0.breakRails = 2; $0.badBreak = "option"
      $0.threeFoul = "minus15"; $0.missed = "spot"; $0.safetyPots = "spot"; $0.foulHand = "position"; $0.score = "count"; $0.race = 25
    },
  ]
  return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
}()
public let DEFAULT_RULESET = ["8": "8-house", "9": "9-house", "10": "10-wpa", "straight": "straight-wpa", "rotation": "rotation", "bumper": "bumper", "carom": "carom", "snooker": "snooker", "heyball": "heyball"]
public let POCKET_KINDS = ["8", "9", "10", "straight", "rotation", "heyball"]
public func is8(_ k: String) -> Bool { k == "8" || k == "heyball" }

/* makeRules(kind, { ruleset, call, race, locked, players }) (the options overrides are applied by the caller) */
public func makeRules(_ kind: String, ruleset: String? = nil, call: CallConfig? = nil, race: Int? = nil, locked: Bool = false, players: Int? = nil) -> RuleSet {
  let id = ruleset.flatMap { RULESETS[$0]?.game == kind ? $0 : nil } ?? DEFAULT_RULESET[kind] ?? "8-house"
  var R = RULESETS[id]!
  R.call = call ?? CallConfig(); R.locked = locked; R.made = true
  if R.score != nil, let r = race, r > 0 { R.race = r }
  R.players = R.ring ? max(2, min(4, players ?? R.players)) : 2
  return R
}

/* the game's ball: position, velocity and spin as the result left them */
public struct GBall: Equatable, Sendable {
  public var n: Int, x: Double, y: Double, vx = 0.0, vy = 0.0, on = true, wx = 0.0, wy = 0.0, wz = 0.0
  public init(n: Int, x: Double, y: Double) { self.n = n; self.x = x; self.y = y }
}
public struct ShotCall: Equatable, Sendable {
  public var ball: Int? = nil, pocket: Int? = nil, safety = false, push = false, bank = false, kick = false, combo = false, auto = false
  public init() {}
}
public struct GOption: Equatable, Sendable { public var kind: String, who: Int, choices: [String] }
public struct CallRec: Equatable, Sendable { public var p: Int, ball: Int?, pocket: Int?, safety: Bool, push: Bool, made: Bool?, auto: Bool }
public struct CallOut: Equatable, Sendable {
  public var ball: Int?, pocket: Int?, auto: Bool, need: Bool, made: Bool?, safety: Bool, push: Bool, missing: Bool?, extra: [Int], why: String
  public init(ball: Int?, pocket: Int?, auto: Bool, need: Bool, made: Bool?, safety: Bool, push: Bool, missing: Bool?, extra: [Int], why: String) {
    self.ball = ball; self.pocket = pocket; self.auto = auto; self.need = need; self.made = made; self.safety = safety; self.push = push
    self.missing = missing; self.extra = extra; self.why = why
  }
}
public struct Verdict: Equatable, Sendable {
  public var foul: String?, keep: Bool, win: Int?, why: String, potted: [Int], scratch: Bool, grouped: Bool, twoFouls: Bool
  public var call: CallOut, push: Bool, option: String?, scored: Int, rerack: String?, threeFouls: Bool, illegalBreak: Bool
  public var off: [Int]? = nil, chose: String? = nil, chooser: Int? = nil
}
/* the shot's facts the rules read (resultOf) */
public struct RuleShot: Sendable {
  public var balls: [GBall], first: Int?, railAfter: Bool, crossed: Bool?, potted: [Int], pocketOf: [Int: Int], rails: [Int: Int]?, kick: Int?
  public init(balls: [GBall], first: Int?, railAfter: Bool, crossed: Bool?, potted: [Int], pocketOf: [Int: Int], rails: [Int: Int]?, kick: Int?) {
    self.balls = balls; self.first = first; self.railAfter = railAfter; self.crossed = crossed; self.potted = potted; self.pocketOf = pocketOf; self.rails = rails; self.kick = kick
  }
}

extension RuleShot {
  /* the rules' view of a finished shot (resultOf's fields the judge reads) */
  public init(_ r: ShotResult) {
    self.init(balls: r.balls.map { b in var g = GBall(n: b.n, x: b.x, y: b.y); g.vx = b.vx; g.vy = b.vy; g.on = b.on; g.wx = b.wx; g.wy = b.wy; g.wz = b.wz; return g },
              first: r.first, railAfter: r.railAfter, crossed: r.crossed, potted: r.potted, pocketOf: r.pocketOf, rails: r.rails, kick: r.kick)
  }
}

public struct Game: Sendable {
  public var kind: String, balls: [GBall], turn = 0, groups: [String?] = [nil, nil], open = true, breakShot = true, inHand: String? = "kitchen"
  public var fouls: [Int], winner: Int? = nil, shots = 0, dry = 0, verdict: Verdict? = nil, rules: RuleSet, call: ShotCall? = nil, option: GOption? = nil
  public var pushAvail = false, breaker = 0, calls: [CallRec] = []
  public var score: [Int]? = nil, race: Int? = nil, high: [Int]? = nil, run: Int? = nil
  public var mode: String? = nil
  func ball(_ n: Int) -> GBall? { balls.first { $0.n == n } }
}

/* the rules on one table: they read its spots, its string and its balls' size */
public final class RulesEngine {
  public let sim: Sim
  public init(sim: Sim) { self.sim = sim }

  public func newGame(_ kind: String, rules: RuleSet? = nil) -> Game {
    let R = rules.flatMap { $0.made && $0.game == kind ? $0 : nil } ?? makeRules(kind)
    let np = R.players
    let balls = sim.rack(kind).map { b -> GBall in GBall(n: b.n, x: b.x, y: b.y) }
    var g = Game(kind: kind, balls: balls, fouls: Array(repeating: 0, count: np), rules: R)
    if R.score != nil { g.score = Array(repeating: 0, count: np); g.race = R.race; g.high = Array(repeating: 0, count: np); g.run = 0 }
    return g
  }
  func playersOf(_ g: Game) -> Int { g.rules.players > 2 ? g.rules.players : 2 }
  func nextOf(_ g: Game, _ p: Int) -> Int { (p + 1) % playersOf(g) }
  public func gameBallOf(_ g: Game) -> Int? { is8(g.kind) ? 8 : g.kind == "9" ? 9 : g.kind == "10" ? 10 : nil }
  public func groupOf(_ n: Int) -> String? { n == 0 || n == 8 ? nil : n < 8 ? "solids" : "stripes" }
  func otherGroup(_ gr: String?) -> String { gr == "solids" ? "stripes" : "solids" }
  public func onTable(_ g: Game) -> [Int] { g.balls.filter { $0.on && $0.n > 0 }.map { $0.n }.sorted() }
  func aGroupGone(_ on: [Int]) -> Bool { !on.contains { groupOf($0) == "solids" } || !on.contains { groupOf($0) == "stripes" } }

  public func callScope(_ g: Game) -> String {
    let R = g.rules
    if !POCKET_KINDS.contains(g.kind) || g.mode != nil { return "none" }
    let m = R.call.mode
    if g.kind == "heyball" { return m == "all" ? "all" : "none" }
    var s = m == "off" ? "none" : m == "eight" ? (is8(g.kind) ? (R.calls == "none" ? "all" : R.calls) : "none") : m == "all" ? "all" : R.calls
    if s == "none" && R.call.eight && is8(g.kind) { s = "game" }
    return s
  }
  public struct Need { public var pocket, flags, strict, auto, safety, change: Bool }
  public func callNeed(_ g: Game) -> Need? {
    if g.mode != nil || g.winner != nil || g.option != nil || g.breakShot { return nil }
    if let c = g.call, c.push && g.pushAvail { return nil }
    let s = callScope(g)
    if s == "none" || (s == "game" && !legalTargets(g).contains(gameBallOf(g) ?? -1)) { return nil }
    let R = g.rules, d = R.call.detail
    return Need(pocket: d != "ball", flags: d == "rails" || d == "strict", strict: d == "strict", auto: R.call.obvious && R.obvious, safety: R.call.safety, change: R.call.change)
  }
  func callResult(_ g: Game, _ r: RuleShot, _ need: Need?) -> CallOut {
    let c = g.call ?? ShotCall(), pot = r.potted.filter { $0 != 0 }
    var o = CallOut(ball: c.ball, pocket: c.pocket, auto: c.auto, need: false, made: nil, safety: false, push: false, missing: nil, extra: pot, why: "")
    if c.push && g.pushAvail { o.push = true; o.made = false; return o }
    guard let need else { o.safety = c.safety; return o }
    let noSafe = g.rules.safetyCall == false, safe = c.safety && !noSafe, missing = !safe && c.ball == nil
    o.need = true
    if safe || (missing && !need.safety && !noSafe) { o.made = false; o.safety = true; o.missing = missing; return o }
    if missing { o.made = false; o.missing = true; o.why = "no call"; return o }
    let cb = c.ball!, down = pot.contains(cb), at = r.pocketOf[cb], extra = pot.filter { $0 != cb }
    var made = down && (!need.pocket || at == c.pocket)
    var why = !down ? "the \(cb) did not drop" : made ? "" : "the \(cb) missed the called pocket"
    if made && need.flags {
      let bank = (r.rails?[cb] ?? 0) > 0, kick = (r.kick ?? 0) > 0, combo = r.first != cb
      let off = [("bank", bank, c.bank), ("kick", kick, c.kick), ("combination", combo, c.combo)].filter { $0.1 != $0.2 }
      if !off.isEmpty { made = false; why = off.map { ($0.1 ? "an uncalled " : "no ") + $0.0 }.joined(separator: ", ") }
    }
    if made && need.strict && !extra.isEmpty { made = false; why = "the \(extra[0]) dropped too" }
    o.made = made; o.missing = false; o.extra = extra; o.why = why
    return o
  }
  func railBalls(_ r: RuleShot) -> Double { r.rails.map { Double($0.filter { $0.key > 0 && $0.value > 0 }.count) } ?? .infinity }
  func breakLegal(_ R: RuleSet, _ r: RuleShot, _ pot: [Int]) -> Bool { R.breakRails == 0 || !pot.isEmpty || railBalls(r) >= Double(R.breakRails) }

  public func legalTargets(_ g: Game) -> [Int] {
    let on = onTable(g)
    if g.mode != nil || g.kind == "straight" { return on }
    if !is8(g.kind) { return Array(on.prefix(1)) }
    if g.open {
      var t = on.filter { $0 != 8 }
      if !t.isEmpty && on.contains(8) && !g.breakShot && g.rules.tempClaim && aGroupGone(on) { t.append(8) }
      return t.isEmpty ? [8] : t
    }
    let mine = on.filter { groupOf($0) == g.groups[g.turn] }
    return mine.isEmpty ? [8] : mine
  }
  /* the foot spot, or the nearest free point behind it on the long string */
  public func spot(_ balls: inout [GBall], _ n: Int) {
    guard let i = balls.firstIndex(where: { $0.n == n }) else { return }
    let R = sim.BALL_R, fy = sim.FOOT[1]
    func free(_ x: Double) -> Bool { balls.indices.allSatisfy { j in j == i || !balls[j].on || M.hypot(balls[j].x - x, balls[j].y - fy) >= 2 * R } }
    var x = sim.FOOT[0]
    while !free(x) && x < sim.TL - R { x += 0.001 }
    if !free(x) { x = sim.FOOT[0]; while !free(x) && x > R { x -= 0.001 } }
    balls[i].x = x; balls[i].y = fy; balls[i].vx = 0; balls[i].vy = 0; balls[i].on = true
  }
  func spotAll(_ balls: inout [GBall], _ list: [Int]) { for x in list.sorted() { spot(&balls, x) } }
  /* on the cloth, clear of every cushion surface and of the pocket mouths, touching no ball, and behind
     the head string when the hand is the kitchen (the pocket games' canPlace) */
  public func canPlace(_ g: Game, _ x: Double, _ y: Double) -> Bool {
    let R = sim.BALL_R
    if !(x >= R && x <= sim.TL - R && y >= R && y <= sim.TW - R) { return false }
    if g.inHand == "kitchen" && x > sim.HEAD_X { return false }
    if sim.CUSH.contains(where: { sim.segGap($0[0], $0[1], $0[2], $0[3], x, y) < R - 1e-9 }) { return false }
    if sim.POCKET_AIM.contains(where: { M.hypot($0[0] - x, $0[1] - y) < 2 * R }) { return false }
    return g.balls.allSatisfy { $0.n == 0 || !$0.on || M.hypot($0.x - x, $0.y - y) >= 2 * R }
  }
  public func placeCue(_ g: Game, _ x: Double, _ y: Double) -> Game {
    var n = g
    if let i = n.balls.firstIndex(where: { $0.n == 0 }) { n.balls[i].x = x; n.balls[i].y = y; n.balls[i].vx = 0; n.balls[i].vy = 0; n.balls[i].on = true }
    return n
  }

  func offOf(_ r: RuleShot) -> [Int] { r.potted.filter { $0 != 0 && r.pocketOf[$0] == -1 } }
  func poolFoul(_ g: Game, _ r: RuleShot, _ R: RuleSet, _ targets: [Int], _ push: Bool, _ off: [Int]) -> String? {
    let pot = r.potted.filter { $0 != 0 }
    if r.potted.contains(0) { return r.pocketOf[0] == -1 ? "the cue ball left the table" : "scratch" }
    if !off.isEmpty { return "the \(off[0]) left the table" }
    if push { return nil }
    guard let first = r.first else { return "no ball hit" }
    let firstBall = g.ball(first)!
    if !(g.breakShot && R.breakAny) && !targets.contains(first) { return "hit the \(first) first" }
    if g.inHand == "kitchen" && !g.breakShot && firstBall.x < sim.HEAD_X && r.crossed != true
        && (R.kitchenSpot || targets.contains { g.ball($0)!.x >= sim.HEAD_X }) { return "hit the \(first) behind the head string" }
    if !g.breakShot && pot.isEmpty && !r.railAfter { return "no rail after contact" }
    return nil
  }
  struct Base { var R: RuleSet, n: Game, me: Int, op: Int, pot: [Int], off: [Int], push: Bool, need: Need?, scratch: Bool, foul: String?, call: CallOut }
  func poolBase(_ g: Game, _ r0: RuleShot) -> (Base, RuleShot) {
    let R = g.rules, me = g.turn
    var n = g, r = r0
    n.rules = R
    n.balls = r.balls.map { var b = $0; b.vx = 0; b.vy = 0; return b }
    n.shots += 1
    let off = offOf(r), gb = gameBallOf(g)
    if !off.isEmpty {
      r.potted = r.potted.filter { !off.contains($0) }
      spotAll(&n.balls, off.filter { R.offSpot == "spot" || $0 == gb })
    }
    let pot = r.potted.filter { $0 != 0 }, push = (g.call?.push ?? false) && g.pushAvail && !g.breakShot
    let need = push ? nil : callNeed(g)
    return (Base(R: R, n: n, me: me, op: nextOf(g, me), pot: pot, off: off, push: push, need: need, scratch: r.potted.contains(0),
                 foul: poolFoul(g, r, R, legalTargets(g), push, off), call: callResult(g, r, need)), r)
  }
  public func rerack(_ g: Game, _ breaker: Int) -> Game {
    var f = newGame(g.kind, rules: g.rules)
    if g.score != nil { f.score = g.score }
    if g.high != nil { f.high = g.high }
    f.calls = g.calls; f.shots = g.shots
    f.turn = breaker; f.breaker = breaker
    return f
  }
  func kitchenOption(_ n: Game, _ R: RuleSet) -> GOption? {
    if !R.kitchenSpot || n.inHand != "kitchen" || n.winner != nil || n.breakShot { return nil }
    let t = legalTargets(n)
    return !t.isEmpty && t.allSatisfy({ n.ball($0)!.x < sim.HEAD_X }) ? GOption(kind: "kitchenSpot", who: n.turn, choices: ["spot", "play"]) : nil
  }
  /* poolEnd's o; inHand: .none is the page's undefined (not given), .some(nil) its null */
  struct End {
    var foul: String??, keep = false, win: Int? = nil, why = "", option: GOption? = nil, inHand: String?? = .none, scored = 0, grouped = false
    var rerack: String? = nil, game: Game? = nil, threeFouls = false, illegalBreak = false, potted: [Int]? = nil
  }
  func poolEnd(_ g: Game, _ b: Base, _ o: End) -> Game {
    var n = b.n
    let me = b.me, op = b.op, R = b.R, foul: String? = o.foul ?? b.foul
    if let w = o.win { n.winner = w; n.inHand = nil; n.turn = me; n.option = nil }
    else if let opt = o.option { n.option = opt; n.turn = opt.who; n.inHand = o.inHand.flatMap { $0 } }
    else {
      n.turn = o.keep ? me : op
      if case .some(let h) = o.inHand { n.inHand = h }
      else { n.inHand = foul == nil ? nil : g.breakShot && b.scratch ? R.breakScratch : R.foulHand == "position" ? (b.scratch ? "kitchen" : nil) : "table" }
    }
    if g.breakShot { n.breaker = me }
    n.breakShot = false
    n.pushAvail = g.breakShot && R.pushOut && n.winner == nil && n.option == nil && foul == nil
    if n.option == nil { n.option = kitchenOption(n, R) }
    n.call = nil
    n.dry = b.pot.isEmpty ? g.dry + 1 : 0
    let potted = o.potted ?? b.pot.filter { x in !(n.ball(x)?.on ?? false) }, c = b.call
    if c.need || c.push || c.safety || c.ball != nil {
      n.calls = Array((g.calls + [CallRec(p: me, ball: c.ball, pocket: c.pocket, safety: c.safety, push: c.push, made: c.made, auto: c.auto)]).suffix(40))
    }
    var again = o.rerack
    if var og = o.game { og.calls = n.calls; n = og }
    else if R.stalemate > 0 && n.winner == nil && n.option == nil && n.dry >= 2 * R.stalemate {
      let calls = n.calls
      n = rerack(n, g.breaker); n.calls = calls
      again = "stalemate"
    }
    n.verdict = Verdict(foul: foul, keep: o.keep && o.option == nil, win: o.win, why: o.why, potted: potted, scratch: b.scratch, grouped: o.grouped,
                        twoFouls: o.win == nil && R.threeFoul != nil && n.fouls.indices.contains(n.turn) && n.fouls[n.turn] >= 2, call: c, push: b.push,
                        option: n.option?.kind, scored: o.scored, rerack: again, threeFouls: o.threeFouls, illegalBreak: o.illegalBreak)
    if !b.off.isEmpty { n.verdict!.off = b.off }
    return n
  }

  public func judge(_ g: Game, _ r: RuleShot) -> Game {
    switch g.kind {
    case "9", "10": return judgeLowest(g, r)
    case "rotation": return judgeRotation(g, r)
    case "straight": return judgeStraight(g, r)
    default: return judge8(g, r)
    }
  }

  func judge8(_ g: Game, _ r0: RuleShot) -> Game {
    let (b, r) = poolBase(g, r0)
    let R = b.R, me = b.me, op = b.op, pot = b.pot, need = b.need, call = b.call
    var n = b.n
    let mine = g.groups[me]
    let cleared = mine != nil ? !onTable(g).contains { groupOf($0) == mine } : g.open && !g.breakShot && R.tempClaim && aGroupGone(onTable(g))
    var foul = b.foul, win: Int? = nil, why = "", keep = false, option: GOption? = nil, inHand: String?? = .none, illegalBreak = false, grouped = false
    if g.breakShot && foul == nil && !breakLegal(R, r, pot) {
      foul = "illegal break"; illegalBreak = true
      if R.badBreak == "rerack" { option = GOption(kind: "badBreak", who: op, choices: ["take", "rebreak", "break"]) }
    }
    if g.breakShot && R.breakFoul == "choice" && foul == "no ball hit" { foul = "illegal break"; illegalBreak = true; option = GOption(kind: "badBreak", who: op, choices: ["take", "rebreak", "break"]) }
    if b.off.contains(8) && (!g.breakShot || R.eightOffBreak == "loss") { win = op; why = "the 8 left the table" }
    else if pot.contains(8) {
      if g.breakShot { if R.gameBallBreak == "option" && foul == nil { option = GOption(kind: "eightBreak", who: me, choices: ["spot", "rerack"]) } else { spot(&n.balls, 8) } }
      else if foul == nil && cleared && (need == nil || (call.made == true && call.ball == 8)) { win = me; why = "the 8, legally" }
      else { win = op; why = foul != nil ? "the 8 went down on a foul" : !cleared ? "the 8 went down before the group was clear" : call.safety ? "the 8 went down on a safety" : "the 8 went down in an uncalled pocket" }
    }
    if win == nil && g.breakShot && foul != nil && !illegalBreak && R.breakFoul == "rerack" {
      if r.first == nil { option = GOption(kind: "breakMiss", who: op, choices: ["rebreak", "break"]) }
      else { inHand = .some("kitchen"); option = GOption(kind: "breakFoul", who: op, choices: ["take", "rebreak", "break"]) }
    }
    if win == nil && g.breakShot && foul != nil && !illegalBreak && R.breakFoul == "choice" {
      if pot.contains(8) { inHand = .some("kitchen"); option = GOption(kind: "breakFoul", who: op, choices: ["take", "break"]) }
      else if !b.off.isEmpty && !b.scratch { option = GOption(kind: "breakOff", who: op, choices: ["take", "kitchen"]) }
    }
    if win == nil {
      let own = need == nil || g.open || call.ball == nil || groupOf(call.ball!) == mine
      let objs = pot.filter { $0 != 8 }, ok = foul == nil && (need == nil || call.made == true) && !call.safety && own
      if ok && g.open && !g.breakShot && !objs.isEmpty {
        let by: Int? = need != nil && call.ball.flatMap(groupOf) != nil ? call.ball : R.groupBy != "first" ? objs[0]
          : objs.contains { groupOf($0) == r.first.flatMap(groupOf) } ? r.first : nil
        if let by { n.groups[me] = groupOf(by); n.groups[op] = otherGroup(n.groups[me]); n.open = false; grouped = true }
      }
      let openKeep = g.open && (R.groupBy != "first" || g.breakShot || grouped)
      keep = ok && (objs.contains { openKeep || groupOf($0) == mine } || (g.breakShot && pot.contains(8)))
    }
    var b2 = b; b2.n = n
    return poolEnd(g, b2, End(foul: .some(foul), keep: keep, win: win, why: why, option: option, inHand: inHand, grouped: grouped, illegalBreak: illegalBreak))
  }

  func judgeLowest(_ g: Game, _ r0: RuleShot) -> Game {
    let (b, r) = poolBase(g, r0)
    let R = b.R, me = b.me, op = b.op, pot = b.pot, need = b.need, call = b.call, push = b.push, gb = gameBallOf(g)!, on = legalTargets(g).first
    var n = b.n
    var foul = b.foul, win: Int? = nil, why = "", option: GOption? = nil, illegalBreak = false
    if g.breakShot && foul == nil && !breakLegal(R, r, pot) {
      foul = "illegal break"; illegalBreak = true
      if R.badBreak == "option" { option = GOption(kind: "badBreak", who: op, choices: ["take", "rebreak"]) }
    }
    let short = g.breakShot && foul == nil && R.threeBall > 0 && pot.count + r.balls.filter { $0.on && $0.n > 0 && $0.x < sim.HEAD_X }.count < R.threeBall
    let ok = foul == nil && !push && (need == nil || call.made == true) && !call.safety
    if pot.contains(gb) {
      let wins: Bool
      if foul != nil || push || short { wins = false }
      else if g.breakShot { wins = R.gameBallBreak == "win" }
      else if need != nil { wins = call.made == true && call.ball == gb && (R.earlyGameBall == "win" || on == gb) }
      else { wins = R.earlyGameBall == "win" || on == gb }
      if wins { win = me; why = "the \(gb)" } else { spot(&n.balls, gb) }
    }
    n.fouls[me] = foul != nil && option == nil ? n.fouls[me] + 1 : foul != nil ? n.fouls[me] : 0
    if win == nil && R.threeFoul == "loss" && n.fouls[me] >= 3 { win = op; why = "three fouls in a row" }
    if win == nil && foul == nil && option == nil {
      if short { option = GOption(kind: "threeBall", who: op, choices: ["take", "pass"]) }
      else if push { option = GOption(kind: "push", who: op, choices: ["take", "pass"]) }
      else if need != nil && call.made != true {
        let extra = pot.filter { x in x != gb && !(n.ball(x)?.on ?? false) }
        let rule = call.safety ? R.safetyPots : R.missed
        if rule == "spot" { spotAll(&n.balls, extra) }
        else if rule == "option" && !pot.isEmpty && !call.safety { option = GOption(kind: "uncalled", who: op, choices: ["take", "pass"]) }
      }
    }
    var b2 = b; b2.n = n
    return poolEnd(g, b2, End(foul: .some(foul), keep: ok && !pot.isEmpty, win: win, why: why, option: option, illegalBreak: illegalBreak))
  }

  func judgeRotation(_ g: Game, _ r0: RuleShot) -> Game {
    let (b, _) = poolBase(g, r0)
    let me = b.me, pot = b.pot, need = b.need, call = b.call, foul = b.foul
    var n = b.n
    let ok = foul == nil && (need == nil || call.made == true) && !call.safety
    var scored = 0, win: Int? = nil, why = ""
    if ok { scored = pot.reduce(0, +) } else { spotAll(&n.balls, pot) }
    n.score![me] += scored
    if n.score![me] >= n.race! { win = me; why = "\(n.race!) points" }
    else if onTable(n).isEmpty {
      let top = n.score!.max()!
      win = n.score![me] >= top ? me : n.score!.firstIndex(of: top)!; why = "\(n.race!) points"
    }
    var b2 = b; b2.n = n
    return poolEnd(g, b2, End(foul: .none, keep: ok && !pot.isEmpty, win: win, why: why, scored: scored))
  }

  func rackSpots() -> [[Double]] { sim.rack("straight").filter { $0.n > 0 }.map { [$0.x, $0.y] } }
  func inRackArea(_ b: GBall, _ spots: [[Double]]) -> Bool { b.on && spots.contains { M.hypot($0[0] - b.x, $0[1] - b.y) < 2 * sim.BALL_R } }
  func rackFifteen(_ n: inout Game) -> String? {
    let cue = n.ball(0)!, cIn = !cue.on || inRackArea(cue, rackSpots()), x = cue.x, y = cue.y
    n.balls = sim.rack("straight").map { GBall(n: $0.n, x: $0.x, y: $0.y) }
    if cIn { return "kitchen" }
    let i = n.balls.firstIndex { $0.n == 0 }!
    n.balls[i].x = x; n.balls[i].y = y
    return nil
  }
  func rackFourteen(_ n: inout Game) -> (hand: String?, all: Bool) {
    let spots = rackSpots(), bi = n.balls.firstIndex { $0.n > 0 && $0.on }!, ci = n.balls.firstIndex { $0.n == 0 }!
    let head = [sim.HEAD_X, sim.TW / 2], centre = [sim.TL / 2, sim.TW / 2], R = sim.BALL_R
    func near(_ x: Double, _ y: Double, _ p: [Double]) -> Bool { M.hypot(x - p[0], y - p[1]) < 2 * R }
    let bIn = inRackArea(n.balls[bi], spots), cIn = !n.balls[ci].on || inRackArea(n.balls[ci], spots)
    if bIn && cIn { return (rackFifteen(&n), true) }
    var hand: String? = nil
    if bIn {
      let p = near(n.balls[ci].x, n.balls[ci].y, head) ? centre : head
      n.balls[bi].x = p[0]; n.balls[bi].y = p[1]
    } else if cIn {
      if n.balls[bi].x >= sim.HEAD_X {
        hand = "kitchen"
        let hx = sim.HEAD_X - 0.12
        n.balls[ci].on = true; n.balls[ci].x = hx; n.balls[ci].y = sim.TW / 2 + (near(hx, sim.TW / 2, [n.balls[bi].x, n.balls[bi].y]) ? 0.2 : 0)
      } else {
        let p = near(n.balls[bi].x, n.balls[bi].y, head) ? centre : head
        n.balls[ci].on = true; n.balls[ci].x = p[0]; n.balls[ci].y = p[1]
      }
    }
    var k = 1
    for i in n.balls.indices where n.balls[i].n > 0 && i != bi {
      let p = spots[k]; k += 1
      n.balls[i].on = true; n.balls[i].x = p[0]; n.balls[i].y = p[1]; n.balls[i].vx = 0; n.balls[i].vy = 0
    }
    return (hand, false)
  }

  func judgeStraight(_ g: Game, _ r0: RuleShot) -> Game {
    let (b, r) = poolBase(g, r0)
    let R = b.R, me = b.me, op = b.op, pot = b.pot, need = b.need, call = b.call
    var n = b.n
    var foul = b.foul, scored = 0, pen = 0, keep = false, win: Int? = nil, why = "", option: GOption? = nil, again: String? = nil
    var inHand: String?? = .none, threeFouls = false, illegalBreak = false, game: Game? = nil
    if g.breakShot {
      let c = g.call ?? ShotCall(), detail = R.call.detail
      let called = c.ball != nil && pot.contains(c.ball!) && (detail == "ball" || r.pocketOf[c.ball!] == c.pocket)
      var driven = Double.infinity
      if let rails = r.rails {
        let railed: [Int] = rails.filter { $0.key > 0 && $0.value > 0 }.map { $0.key }
        driven = Double(Set(railed + pot).count)
      }
      let cueRail = r.rails == nil || (r.rails![0] ?? -1) > (r.kick ?? 0) || b.scratch
      if !called && (r.first == nil || !(driven >= Double(R.breakRails) && cueRail)) {
        foul = "breaking foul"; illegalBreak = true; pen = 2
        option = GOption(kind: "badBreak", who: op, choices: ["take", "rebreak"])
        if b.scratch { inHand = .some("kitchen") }
      } else if foul == nil && called { scored = pot.count; keep = true }
      if !keep { spotAll(&n.balls, pot) }
      if foul != nil && !illegalBreak { pen = 1 }
    } else if foul != nil {
      pen = 1; spotAll(&n.balls, pot)
      if g.inHand == "kitchen" && !b.scratch && r.crossed != true && r.first == nil { inHand = .some("kitchen") }
    } else if need == nil || call.made == true { scored = pot.count; keep = !pot.isEmpty }
    else { spotAll(&n.balls, pot) }
    if foul != nil && !illegalBreak { n.fouls[me] = g.fouls[me] + 1 } else if foul == nil { n.fouls[me] = 0 }
    if n.fouls[me] >= 3 && R.threeFoul == "minus15" { pen += 15; threeFouls = true; n.fouls[me] = 0 }
    n.score![me] += scored - pen
    let run = (g.run ?? 0) + scored
    n.high![me] = max(n.high![me], run)
    n.run = keep ? run : 0
    let down = pot.filter { x in !(n.ball(x)?.on ?? false) }
    if n.score![me] >= n.race! { win = me; why = "\(n.race!) points" }
    else if threeFouls { var gm = rerack(n, me); gm.fouls = n.fouls; game = gm; again = "fouls" }
    else if keep {
      let left = onTable(n).count
      if left == 1 { let q = rackFourteen(&n); inHand = .some(q.hand); again = q.all ? "fifteen" : "fourteen" }
      else if left == 0 { inHand = .some(rackFifteen(&n)); again = "fifteen" }
    }
    var b2 = b; b2.n = n
    return poolEnd(g, b2, End(foul: .some(foul), keep: keep, win: win, why: why, option: option, inHand: inHand, scored: scored - pen, rerack: again, game: game,
                              threeFouls: threeFouls, illegalBreak: illegalBreak, potted: down))
  }

  /* a pending choice made: a new game, or nil when it is not on offer */
  public func chooseOption(_ g: Game, _ choice: String) -> Game? {
    guard let o = g.option, o.choices.contains(choice) else { return nil }
    var n = g
    n.option = nil; n.call = nil
    let who = o.who, other = (who + playersOf(g) - 1) % playersOf(g)
    if choice == "take" || choice == "pass" {
      n.turn = choice == "take" ? who : other
      if o.kind == "badBreak" { n.pushAvail = g.rules.pushOut }
      if o.kind == "threeBall" { n.pushAvail = choice == "pass" && g.rules.pushOut }
    } else if choice == "kitchen" { n.turn = who; n.inHand = "kitchen" }
    else if o.kind == "kitchenSpot" {
      n.turn = who
      if choice == "spot" {
        let t = legalTargets(n)
        let pick = t.dropFirst().reduce(t[0]) { a, x in n.ball(x)!.x > n.ball(a)!.x ? x : a }
        spot(&n.balls, pick)
      }
    } else if choice == "spot" { spot(&n.balls, 8); n.turn = who; n.pushAvail = g.rules.pushOut }
    else { n = rerack(n, choice == "rebreak" ? other : who) }
    if o.kind != "kitchenSpot" { n.option = kitchenOption(n, n.rules) }
    var v = g.verdict
    v?.chose = choice; v?.chooser = who
    n.verdict = v
    return n
  }
}
