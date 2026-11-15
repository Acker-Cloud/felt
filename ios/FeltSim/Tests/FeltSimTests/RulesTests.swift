/* 1e against the page: whole games its judge played (tools/ios-golden.cjs: rules.json), every shot and
   choice. Each step's game in is the page's game out from the step before, with the cue ball placed and
   the call set as the page set them; the game out is compared field by field (rules apart, which the
   ruleset id rebuilds), null and absent kept apart where the page keeps them apart. */
import Foundation
import Testing
@testable import FeltSim

private func num(_ a: Any?) -> Double { (a as! NSNumber).doubleValue }
private func int(_ a: Any?) -> Int? { a is NSNull || a == nil ? nil : (a as! NSNumber).intValue }
private func str(_ a: Any?) -> String? { a as? String }

func decodeBall(_ o: [String: Any]) -> GBall {
  var b = GBall(n: int(o["n"])!, x: num(o["x"]), y: num(o["y"]))
  b.vx = num(o["vx"]); b.vy = num(o["vy"]); b.on = o["on"] as! Bool
  b.wx = num(o["wx"]); b.wy = num(o["wy"]); b.wz = num(o["wz"])
  return b
}
func decodeCall(_ a: Any?) -> ShotCall? {
  guard let o = a as? [String: Any] else { return nil }
  var c = ShotCall()
  c.ball = int(o["ball"]); c.pocket = int(o["pocket"])
  c.safety = o["safety"] as? Bool ?? false; c.push = o["push"] as? Bool ?? false
  c.bank = o["bank"] as? Bool ?? false; c.kick = o["kick"] as? Bool ?? false; c.combo = o["combo"] as? Bool ?? false; c.auto = o["auto"] as? Bool ?? false
  return c
}
func decodeGame(_ o: [String: Any], rules: RuleSet) -> Game {
  var g = Game(kind: o["kind"] as! String, balls: (o["balls"] as! [[String: Any]]).map(decodeBall), fouls: (o["fouls"] as! [NSNumber]).map { $0.intValue }, rules: rules)
  g.turn = int(o["turn"])!; g.groups = (o["groups"] as! [Any]).map { $0 as? String }; g.open = o["open"] as! Bool; g.breakShot = o["breakShot"] as! Bool
  g.inHand = str(o["inHand"]); g.winner = int(o["winner"]); g.shots = int(o["shots"])!; g.dry = int(o["dry"])!
  g.call = decodeCall(o["call"])
  if let op = o["option"] as? [String: Any] { g.option = GOption(kind: op["kind"] as! String, who: int(op["who"])!, choices: op["choices"] as! [String]) }
  g.pushAvail = o["pushAvail"] as! Bool; g.breaker = int(o["breaker"])!
  g.calls = (o["calls"] as! [[String: Any]]).map { c in
    CallRec(p: int(c["p"])!, ball: int(c["ball"]), pocket: int(c["pocket"]), safety: c["safety"] as! Bool, push: c["push"] as! Bool, made: c["made"] as? Bool, auto: c["auto"] as! Bool)
  }
  if let s = o["score"] as? [NSNumber] { g.score = s.map { $0.intValue } }
  if let r = o["race"] { g.race = int(r) }
  if let h = o["high"] as? [NSNumber] { g.high = h.map { $0.intValue } }
  if let r = o["run"] { g.run = int(r) }
  if let v = o["verdict"] as? [String: Any] { g.verdict = decodeVerdict(v) }
  return g
}
func decodeVerdict(_ v: [String: Any]) -> Verdict {
  let c = v["call"] as! [String: Any]
  let call = CallOut(ball: int(c["ball"]), pocket: int(c["pocket"]), auto: c["auto"] as! Bool, need: c["need"] as! Bool, made: c["made"] as? Bool,
                     safety: c["safety"] as! Bool, push: c["push"] as! Bool, missing: c["missing"] as? Bool, extra: (c["extra"] as! [NSNumber]).map { $0.intValue }, why: c["why"] as! String)
  var o = Verdict(foul: str(v["foul"]), keep: v["keep"] as! Bool, win: int(v["win"]), why: v["why"] as! String, potted: (v["potted"] as! [NSNumber]).map { $0.intValue },
                  scratch: v["scratch"] as! Bool, grouped: v["grouped"] as! Bool, twoFouls: v["twoFouls"] as! Bool, call: call, push: v["push"] as! Bool,
                  option: str(v["option"]), scored: int(v["scored"])!, rerack: str(v["rerack"]), threeFouls: v["threeFouls"] as! Bool, illegalBreak: v["illegalBreak"] as! Bool)
  o.off = (v["off"] as? [NSNumber])?.map { $0.intValue }; o.chose = str(v["chose"]); o.chooser = int(v["chooser"])
  return o
}
func decodeShot(_ o: [String: Any]) -> RuleShot {
  let im = { (a: Any?) -> [Int: Int] in var m: [Int: Int] = [:]; for (k, v) in (a as? [String: Any]) ?? [:] { m[Int(k)!] = int(v) }; return m }
  return RuleShot(balls: (o["balls"] as! [[String: Any]]).map(decodeBall), first: int(o["first"]), railAfter: o["railAfter"] as! Bool, crossed: o["crossed"] as? Bool,
                  potted: (o["potted"] as! [NSNumber]).map { $0.intValue }, pocketOf: im(o["pocketOf"]), rails: o["rails"] == nil ? nil : im(o["rails"]), kick: int(o["kick"]))
}

/* the differences between the page's game and ours, as paths */
func diffGame(_ want: [String: Any], _ got: Game) -> [String] {
  var out: [String] = []
  func eq(_ path: String, _ a: Any?, _ b: Any?) {
    let an = a is NSNull ? nil : a, bn = b is NSNull ? nil : b
    switch (an, bn) {
    case (nil, nil): return
    case (let x as NSNumber, let y as Double): if x.doubleValue != y || CFGetTypeID(x) == CFBooleanGetTypeID() { out.append("\(path): \(x) vs \(y)") }
    case (let x as NSNumber, let y as Int): if x.doubleValue != Double(y) || CFGetTypeID(x) == CFBooleanGetTypeID() { out.append("\(path): \(x) vs \(y)") }
    case (let x as NSNumber, let y as Bool): if CFGetTypeID(x) != CFBooleanGetTypeID() || x.boolValue != y { out.append("\(path): \(x) vs \(y)") }
    case (let x as String, let y as String): if x != y { out.append("\(path): \(x) vs \(y)") }
    case (let x as [Any], let y as [Any]):
      if x.count != y.count { out.append("\(path): \(x.count) items vs \(y.count)"); return }
      for i in x.indices { eq("\(path)[\(i)]", x[i], y[i]) }
    case (let x as [String: Any], let y as [String: Any]):
      for k in Set(x.keys).union(y.keys) { eq("\(path).\(k)", x[k], y[k]) }
    default: out.append("\(path): \(String(describing: an)) vs \(String(describing: bn))")
    }
  }
  eq("g", want, encode(got))
  return out
}
func encode(_ g: Game) -> [String: Any] {
  func ball(_ b: GBall) -> [String: Any] { ["n": b.n, "x": b.x, "y": b.y, "vx": b.vx, "vy": b.vy, "on": b.on, "wx": b.wx, "wy": b.wy, "wz": b.wz] }
  func opt(_ a: Any?) -> Any { a ?? NSNull() }
  var o: [String: Any] = ["kind": g.kind, "balls": g.balls.map(ball), "turn": g.turn, "groups": g.groups.map { opt($0) }, "open": g.open, "breakShot": g.breakShot,
    "inHand": opt(g.inHand), "fouls": g.fouls, "winner": opt(g.winner), "shots": g.shots, "dry": g.dry, "pushAvail": g.pushAvail, "breaker": g.breaker,
    "call": NSNull(), "option": NSNull(), "verdict": NSNull(),
    "calls": g.calls.map { ["p": $0.p, "ball": opt($0.ball), "pocket": opt($0.pocket), "safety": $0.safety, "push": $0.push, "made": opt($0.made), "auto": $0.auto] as [String: Any] }]
  if let c = g.call {
    var d: [String: Any] = [:]
    if let b = c.ball { d["ball"] = b }; if let p = c.pocket { d["pocket"] = p }
    if c.safety { d["safety"] = true }; if c.push { d["push"] = true }
    o["call"] = d
  }
  if let op = g.option { o["option"] = ["kind": op.kind, "who": op.who, "choices": op.choices] }
  if let s = g.score { o["score"] = s }; if let r = g.race { o["race"] = r }; if let h = g.high { o["high"] = h }; if let r = g.run { o["run"] = r }
  if let v = g.verdict {
    let c = v.call
    var cd: [String: Any] = ["ball": opt(c.ball), "pocket": opt(c.pocket), "auto": c.auto, "need": c.need, "made": opt(c.made), "safety": c.safety, "push": c.push, "extra": c.extra, "why": c.why]
    if let m = c.missing { cd["missing"] = m }
    var vd: [String: Any] = ["foul": opt(v.foul), "keep": v.keep, "win": opt(v.win), "why": v.why, "potted": v.potted, "scratch": v.scratch, "grouped": v.grouped,
      "twoFouls": v.twoFouls, "call": cd, "push": v.push, "option": opt(v.option), "scored": v.scored, "rerack": opt(v.rerack), "threeFouls": v.threeFouls, "illegalBreak": v.illegalBreak]
    if let off = v.off { vd["off"] = off }; if let c = v.chose { vd["chose"] = c }; if let c = v.chooser { vd["chooser"] = c }
    o["verdict"] = vd
  }
  return o
}

@Suite struct RulesTests {
  nonisolated(unsafe) static let games: [[String: Any]] = {
    let url = Bundle.module.url(forResource: "rules.json", withExtension: nil, subdirectory: "Fixtures")!
    return (try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any])["games"] as! [[String: Any]]
  }()

  @Test(arguments: 0..<RulesTests.games.count)
  func game(_ i: Int) {
    let G = Self.games[i], name = G["name"] as! String, kind = G["kind"] as! String
    let sim = Sim()
    sim.setPockets("regulation"); sim.setTable(G["table"] as! String)
    let E = RulesEngine(sim: sim)
    var cfg = CallConfig(); cfg.mode = G["mode"] as! String
    let rules = makeRules(kind, ruleset: G["ruleset"] as? String, call: cfg, race: int(G["race"]))
    /* the opening game: the page's newGame, ours made the same way */
    let fresh = E.newGame(kind, rules: rules)
    let d0 = diffGame(G["g0"] as! [String: Any], fresh)
    #expect(d0.isEmpty, "\(name): newGame: \(d0.prefix(5))")
    var prev = G["g0"] as! [String: Any]
    for (k, s) in (G["steps"] as! [[String: Any]]).enumerated() {
      var g = decodeGame(prev, rules: rules)
      let out: Game
      if let choice = s["choice"] as? String {
        out = E.chooseOption(g, choice)!
      } else {
        if let p = s["place"] as? [NSNumber] {
          let i = g.balls.firstIndex { $0.n == 0 }!
          g.balls[i].x = p[0].doubleValue; g.balls[i].y = p[1].doubleValue; g.balls[i].vx = 0; g.balls[i].vy = 0; g.balls[i].on = true
        }
        g.call = decodeCall(s["call"])
        out = E.judge(g, decodeShot(s["r"] as! [String: Any]))
      }
      let want = s["out"] as! [String: Any], d = diffGame(want, out)
      if !d.isEmpty { Issue.record("\(name) step \(k) (\(s["choice"] != nil ? "choice" : "shot")): \(d.prefix(6))"); return }
      prev = want
    }
  }
}

/* the comparison itself: a game out with one field changed must differ, so a pass above means something */
@Suite struct RulesCompareTests {
  @Test func diffCatchesChanges() {
    let G = RulesTests.games.max { ($0["steps"] as! [Any]).count < ($1["steps"] as! [Any]).count }!, kind = G["kind"] as! String
    let sim = Sim(); sim.setTable(G["table"] as! String)
    var cfg = CallConfig(); cfg.mode = G["mode"] as! String
    let rules = makeRules(kind, ruleset: G["ruleset"] as? String, call: cfg)
    let steps = G["steps"] as! [[String: Any]]
    #expect(steps.count > 10)
    let want = steps[1]["out"] as! [String: Any], got = decodeGame(want, rules: rules)
    #expect(diffGame(want, got).isEmpty, "a decoded game re-encodes to itself")
    var a = got; a.turn = 1 - a.turn
    var b = got; b.balls[3].x = b.balls[3].x.nextUp
    var c = got; c.verdict!.why += "!"
    var d = got; d.verdict!.call.missing = d.verdict!.call.missing == nil ? false : nil
    var e = got; e.inHand = e.inHand == nil ? "table" : nil
    for (label, x) in [("turn", a), ("one ulp of x", b), ("why", c), ("missing absent vs present", d), ("inHand", e)] {
      #expect(!diffGame(want, x).isEmpty, "\(label) must show as a difference")
    }
  }
}
