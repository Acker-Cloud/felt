/* index.html sim 1i, shot moments: what a finished shot was, for the callouts and the game-over sheet. shotMoments(g, r,
   n, run) reads the game before the shot, its result, the judged game and the shooter's visit so far (legal pots in it
   before this shot, and whether it began with the break). Pure. Returns the shooter's legal pots and the moments, best
   first (MOMENTS order). Line for line. */
import Foundation

private typealias M = JSMath
public let MOMENTS = ["golden", "breakRun", "runOut", "triple", "combo", "kick", "bank", "cleanBreak", "double", "long", "point"]
public let MOMENT_WORDS = ["golden": "Golden break", "breakRun": "Break and run", "runOut": "Run out", "triple": "Triple", "combo": "Combo", "kick": "Kick shot",
  "bank": "Bank shot", "cleanBreak": "Clean break", "double": "Double", "long": "Long pot", "point": "Point"]
public let SNOOKER_WORDS = ["bank": "Double", "double": "Two reds", "triple": "Three reds"]
public func momentWord(_ k: String, _ kind: String) -> String { (kind == "snooker" ? SNOOKER_WORDS[k] : nil) ?? MOMENT_WORDS[k] ?? k }
public let NOTABLE_MOMENTS = ["triple", "combo", "kick", "bank", "double", "long", "point"]
public let LONG_POT = 0.65, RUN_MIN = 4, BANK_FROM = 0.08, BANK_OUT = 0.2

extension RulesEngine {
  public func shotMoments(_ g: Game, _ r: ShotResult, _ n: Game, run: (pots: Int, fromBreak: Bool) = (0, false)) -> (legal: Int, keys: [String]) {
    let s = sim, me = g.turn
    var keys: [String] = []
    let order = { (ks: [String]) in MOMENTS.filter { ks.contains($0) } }
    guard let v = n.verdict else { return (0, []) }
    if g.kind == "carom" { return (0, v.carom?.point == true && v.foul == nil ? ["point"] : []) }
    let down = (g.kind == "snooker" ? r.potted : v.potted).filter { $0 != 0 }
    var legal: [Int]
    /* a foul, a push-out, a safety or a missed call earns no moment */
    if v.foul != nil || v.call.push || v.call.safety || (v.call.need && v.call.made != true) { legal = [] }
    else if g.kind == "bumper" { legal = down }
    else if (g.kind == "8" || g.kind == "heyball") && g.mode == nil {
      let mine = g.groups[me]
      legal = down.filter { $0 == 8 ? v.win == me : g.open || groupOf($0) == mine }
    } else { legal = down }
    let at = { (x: Int) in g.balls.first { $0.n == x } }
    /* a bank: the ball went to a cushion away from where it lay and came off it to the pocket from a way out */
    let banked = { (x: Int) -> Bool in
      guard let p = r.railAt[x], let b = at(x), let k = r.pocketOf[x], k >= 0, k < s.POCKETS.count else { return false }
      let q = s.POCKETS[k]
      return M.hypot(p[0] - b.x, p[1] - b.y) > BANK_FROM && M.hypot(p[0] - q[0], p[1] - q[1]) > BANK_OUT
    }
    if g.kind == "bumper" {
      if legal.contains(where: banked) { keys.append("bank") }
      if legal.count >= 2 { keys.append("double") }
      return (legal.count, order(keys))
    }
    if g.breakShot {
      if g.kind == "9" && v.win == me && legal.contains(9) { keys.append("golden") }
      else if v.foul == nil && down.count >= 2 { keys.append("cleanBreak") }
      return (legal.count, order(keys))
    }
    if !legal.isEmpty {
      let cue = r.cue, cs = r.contacts
      let idx = { (a: Int, b: Int) in cs.firstIndex { $0[0] == min(a, b) && $0[1] == max(a, b) } ?? -1 }
      if legal.contains(where: banked) { keys.append("bank") }
      if (r.kick ?? 0) > 0 { keys.append("kick") }
      /* combo: sent in by an object ball before (or without) the cue ball touching it */
      let combo = { (x: Int) -> Bool in
        guard let first = r.first, x != first else { return false }
        let byBall = cs.enumerated().filter { ($0.element[0] == x || $0.element[1] == x) && $0.element[0] != cue && $0.element[1] != cue }.map(\.offset)
        if byBall.isEmpty { return false }
        let byCue = idx(cue, x)
        return byCue < 0 || byBall.min()! < byCue
      }
      if legal.contains(where: combo) { keys.append("combo") }
      let far = { (x: Int) -> Bool in
        guard let b = at(x), let k = r.pocketOf[x], k >= 0, k < s.POCKETS.count else { return false }
        return M.hypot(b.x - s.POCKETS[k][0], b.y - s.POCKETS[k][1]) > LONG_POT * s.TL
      }
      if legal.contains(where: far) { keys.append("long") }
      if legal.count >= 3 { keys.append("triple") } else if legal.count == 2 { keys.append("double") }
    }
    if g.mode == nil && g.kind != "snooker" && v.win == me && v.foul == nil {
      let total = run.pots + legal.count, clear = g.kind != "9" || onTable(n).isEmpty
      if total >= RUN_MIN && clear { keys.append(run.fromBreak ? "breakRun" : "runOut") }
    }
    return (legal.count, order(keys))
  }
}
