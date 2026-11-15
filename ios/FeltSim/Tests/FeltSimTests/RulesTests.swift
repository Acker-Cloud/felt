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
  g.pushAvail = o["pushAvail"] as? Bool ?? false; g.breaker = int(o["breaker"]) ?? 0
  g.calls = ((o["calls"] as? [[String: Any]]) ?? []).map { c in
    CallRec(p: int(c["p"])!, ball: int(c["ball"]), pocket: int(c["pocket"]), safety: c["safety"] as! Bool, push: c["push"] as! Bool, made: c["made"] as? Bool, auto: c["auto"] as! Bool)
  }
  if let s = o["score"] as? [NSNumber] { g.score = s.map { $0.intValue } }
  if let r = o["race"] { g.race = int(r) }
  if let h = o["high"] as? [NSNumber] { g.high = h.map { $0.intValue } }
  if let r = o["run"] { g.run = int(r) }
  if let v = o["verdict"] as? [String: Any] { g.verdict = decodeVerdict(v) }
  if g.kind == "bumper" {
    g.striker = int(o["striker"]); g.opening = int(o["opening"]); g.openPot = (o["openPot"] as! [NSNumber]).map { $0.boolValue }
  }
  if g.kind == "carom" {
    g.striker = int(o["striker"]); g.need = int(o["need"]); g.innings = (o["innings"] as! [NSNumber]).map { $0.intValue }
  }
  if g.kind == "snooker" {
    func on(_ a: Any?) -> SnkOn { if let s = a as? String { return s == "red" ? .red : .colour }; if let n = int(a) { return .ball(n) }; return .none }
    var S = SnkState()
    S.on = on(o["on"]); S.brk = int(o["brk"])!; S.frames = int(o["frames"])!; S.won = (o["won"] as! [NSNumber]).map { $0.intValue }; S.frame = int(o["frame"])!
    S.reblack = o["reblack"] as! Bool; S.free = int(o["free"]); S.replaced = o["replaced"] as! Bool
    if let m = o["missRun"] as? [String: Any] { S.missRun = (int(m["p"])!, int(m["n"])!) }
    if let p = o["prev"] as? [String: Any] { S.prev = SnkPrev(balls: (p["balls"] as! [[String: Any]]).map(decodeBall), on: on(p["on"]), free: int(p["free"]), inHand: str(p["inHand"])) }
    g.snk = S
    if let op = o["option"] as? [String: Any] { g.option = GOption(kind: op["kind"] as! String, who: int(op["who"])!, choices: op["choices"] as! [String], free: op["free"] as? Bool, miss: op["miss"] as? Bool) }
  }
  return g
}
func decodeVerdict(_ v: [String: Any]) -> Verdict {
  if v["gave"] != nil {
    var o = Verdict(foul: str(v["foul"]), keep: v["keep"] as! Bool, win: int(v["win"]), why: v["why"] as! String, potted: (v["potted"] as! [NSNumber]).map { $0.intValue },
                    scratch: false, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: nil, scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    let ints = { (a: Any?) in (a as! [NSNumber]).map { $0.intValue } }
    o.bumper = BumperVerdict(gave: ints(v["gave"]), back: ints(v["back"]), dropped: int(v["dropped"]), opening: int(v["opening"])!)
    return o
  }
  if let c = v["count"] as? [String: Any] {
    var o = Verdict(foul: str(v["foul"]), keep: v["keep"] as! Bool, win: int(v["win"]), why: v["why"] as! String, potted: [], scratch: false, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: str(v["option"]), scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    o.carom = CaromVerdict(point: v["point"] as! Bool, count: CaromCount(first: int(c["first"]), balls: (c["balls"] as! [NSNumber]).map { $0.intValue }, cushions: int(c["cushions"])!,
                                                                        point: c["point"] as! Bool), back: (v["back"] as! [NSNumber]).map { $0.intValue })
    o.chose = str(v["chose"]); o.chooser = int(v["chooser"])
    return o
  }
  if v["pen"] != nil {
    var o = Verdict(foul: str(v["foul"]), keep: v["keep"] as! Bool, win: int(v["win"]), why: v["why"] as! String, potted: (v["potted"] as! [NSNumber]).map { $0.intValue },
                    scratch: v["scratch"] as! Bool, grouped: false, twoFouls: false,
                    call: CallOut(ball: nil, pocket: nil, auto: false, need: false, made: nil, safety: false, push: false, missing: nil, extra: [], why: ""),
                    push: false, option: str(v["option"]), scored: 0, rerack: nil, threeFouls: false, illegalBreak: false)
    var fo: FrameOver? = nil
    if let f = v["frameOver"] as? [String: Any] {
      fo = FrameOver(winner: int(f["winner"])!, score: (f["score"] as! [NSNumber]).map { $0.intValue }, frame: int(f["frame"])!, won: (f["won"] as! [NSNumber]).map { $0.intValue },
                     conceded: f["conceded"] as! Bool, forfeit: str(f["forfeit"]))
    }
    o.snk = SnkVerdict(pen: int(v["pen"])!, pts: int(v["pts"])!, nom: int(v["nom"]), back: (v["back"] as! [NSNumber]).map { $0.intValue }, brk: int(v["brk"])!, ended: int(v["ended"])!,
                       frameOver: fo, reblack: v["reblack"] as! Bool, miss: v["miss"] as? Bool, misses: int(v["misses"]), warn: v["warn"] as? Bool,
                       freeBall: v.keys.contains("freeBall") ? .some(int(v["freeBall"])) : nil, nominated: v.keys.contains("nominated") ? .some(int(v["nominated"])) : nil)
    o.chose = str(v["chose"]); o.chooser = int(v["chooser"])
    return o
  }
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
  var r = RuleShot(balls: (o["balls"] as! [[String: Any]]).map(decodeBall), first: int(o["first"]), railAfter: o["railAfter"] as! Bool, crossed: o["crossed"] as? Bool,
                  potted: (o["potted"] as! [NSNumber]).map { $0.intValue }, pocketOf: im(o["pocketOf"]), rails: o["rails"] == nil ? nil : im(o["rails"]), kick: int(o["kick"]),
                  seq: (o["seq"] as? [NSNumber])?.map { $0.intValue } ?? [], over: (o["over"] as? [NSNumber])?.map { $0.intValue })
  r.cue = int(o["cue"])
  return r
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
  var w = want
  if got.kind == "snooker" { w.removeValue(forKey: "call") }
  eq("g", w, encode(got))
  return out
}
func encodeBall(_ b: GBall) -> [String: Any] { ["n": b.n, "x": b.x, "y": b.y, "vx": b.vx, "vy": b.vy, "on": b.on, "wx": b.wx, "wy": b.wy, "wz": b.wz] }
func encodeSnooker(_ g: Game) -> [String: Any] {
  func opt(_ a: Any?) -> Any { a ?? NSNull() }
  func on(_ o: SnkOn) -> Any { switch o { case .red: return "red"; case .colour: return "colour"; case .ball(let n): return n; case .none: return NSNull() } }
  let S = g.snk!
  var o: [String: Any] = ["kind": g.kind, "balls": g.balls.map(encodeBall), "turn": g.turn, "groups": [NSNull(), NSNull()], "open": g.open, "breakShot": g.breakShot,
    "inHand": opt(g.inHand), "fouls": g.fouls, "winner": opt(g.winner), "shots": g.shots, "dry": g.dry, "on": on(S.on), "score": g.score!, "brk": S.brk, "high": g.high!,
    "frames": S.frames, "won": S.won, "frame": S.frame, "breaker": g.breaker, "reblack": S.reblack, "free": opt(S.free), "replaced": S.replaced, "option": NSNull(), "verdict": NSNull(),
    "prev": NSNull(), "missRun": NSNull()]
  if let p = S.prev { o["prev"] = ["balls": p.balls.map(encodeBall), "on": on(p.on), "free": opt(p.free), "inHand": opt(p.inHand)] as [String: Any] }
  if let m = S.missRun { o["missRun"] = ["p": m.p, "n": m.n] }
  if let op = g.option {
    var d: [String: Any] = ["kind": op.kind, "who": op.who, "choices": op.choices]
    if let f = op.free { d["free"] = f }; if let m = op.miss { d["miss"] = m }
    o["option"] = d
  }
  if let v = g.verdict, let sv = v.snk {
    var d: [String: Any] = ["foul": opt(v.foul), "pen": sv.pen, "pts": sv.pts, "keep": v.keep, "nom": opt(sv.nom), "win": opt(v.win), "why": v.why, "potted": v.potted, "back": sv.back,
      "scratch": v.scratch, "grouped": false, "twoFouls": false, "brk": sv.brk, "ended": sv.ended, "frameOver": NSNull(), "reblack": sv.reblack, "option": opt(v.option)]
    if let m = sv.miss { d["miss"] = m }; if let m = sv.misses { d["misses"] = m }; if let w = sv.warn { d["warn"] = w }
    if let f = sv.freeBall { d["freeBall"] = opt(f) }; if let nm = sv.nominated { d["nominated"] = opt(nm) }
    if let c = v.chose { d["chose"] = c }; if let c = v.chooser { d["chooser"] = c }
    if let f = sv.frameOver { d["frameOver"] = ["winner": f.winner, "score": f.score, "frame": f.frame, "won": f.won, "conceded": f.conceded, "forfeit": opt(f.forfeit)] as [String: Any] }
    o["verdict"] = d
  }
  return o
}
func encodeCarom(_ g: Game) -> [String: Any] {
  func opt(_ a: Any?) -> Any { a ?? NSNull() }
  var o: [String: Any] = ["kind": g.kind, "balls": g.balls.map(encodeBall), "turn": g.turn, "groups": [NSNull(), NSNull()], "open": g.open, "breakShot": g.breakShot,
    "inHand": opt(g.inHand), "fouls": g.fouls, "winner": opt(g.winner), "shots": g.shots, "dry": g.dry, "striker": g.striker!, "race": g.race!, "need": g.need!, "score": g.score!,
    "innings": g.innings!, "run": g.run!, "high": g.high!, "option": NSNull(), "verdict": NSNull()]
  if let op = g.option { o["option"] = ["kind": op.kind, "who": op.who, "choices": op.choices] }
  if let v = g.verdict, let cv = v.carom {
    var d: [String: Any] = ["foul": opt(v.foul), "keep": v.keep, "win": opt(v.win), "why": v.why, "point": cv.point, "back": cv.back, "potted": v.potted, "scratch": v.scratch,
      "grouped": false, "twoFouls": false, "option": opt(v.option),
      "count": ["first": opt(cv.count.first), "balls": cv.count.balls, "cushions": cv.count.cushions, "point": cv.count.point] as [String: Any]]
    if let c = v.chose { d["chose"] = c }; if let c = v.chooser { d["chooser"] = c }
    o["verdict"] = d
  }
  return o
}
/* bumper pool's game as the page writes it (bumperGame's fields, judgeBumper's verdict) */
func encodeBumper(_ g: Game) -> [String: Any] {
  func opt(_ a: Any?) -> Any { a ?? NSNull() }
  var o: [String: Any] = ["kind": g.kind, "balls": g.balls.map(encodeBall), "turn": g.turn, "groups": [NSNull(), NSNull()], "open": g.open, "breakShot": g.breakShot,
    "inHand": opt(g.inHand), "fouls": g.fouls, "winner": opt(g.winner), "shots": g.shots, "dry": g.dry, "verdict": NSNull(),
    "opening": g.opening!, "openPot": g.openPot!, "striker": opt(g.striker)]
  if let v = g.verdict, let b = v.bumper {
    o["verdict"] = ["foul": opt(v.foul), "keep": v.keep, "win": opt(v.win), "why": v.why, "potted": v.potted, "gave": b.gave, "back": b.back, "dropped": opt(b.dropped),
      "scratch": v.scratch, "grouped": v.grouped, "twoFouls": v.twoFouls, "opening": b.opening] as [String: Any]
  }
  return o
}
func encode(_ g: Game) -> [String: Any] {
  if g.kind == "bumper" { return encodeBumper(g) }
  if g.kind == "snooker" { return encodeSnooker(g) }
  if g.kind == "carom" { return encodeCarom(g) }
  func ball(_ b: GBall) -> [String: Any] { encodeBall(b) }
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
    return (ExactJSON.parse(try! Data(contentsOf: url)) as! [String: Any])["games"] as! [[String: Any]]
  }()

  @Test(arguments: 0..<RulesTests.games.count)
  func game(_ i: Int) {
    let G = Self.games[i], name = G["name"] as! String, kind = G["kind"] as! String
    let sim = Sim()
    sim.setPockets("regulation"); sim.setTable(G["table"] as! String, G["shape"] as? String)
    let E = RulesEngine(sim: sim)
    var cfg = CallConfig(); cfg.mode = G["mode"] as! String
    let rules = makeRules(kind, ruleset: G["ruleset"] as? String, call: cfg, race: int(G["race"]))
    /* the opening game: the page's newGame, ours made the same way */
    let fresh = kind == "carom" ? E.caromGame(race: int(G["race"])!, cushions: int(G["need"])!, side: int(G["side"])!) : kind == "snooker" ? E.snookerGame(frames: int((G["g0"] as! [String: Any])["frames"])!, first: int((G["g0"] as! [String: Any])["breaker"])!) : E.newGame(kind, rules: rules)
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
      let want = s["out"] as! [String: Any]
      let d = diffGame(want, out)
      if !d.isEmpty { Issue.record("\(name) step \(k) (\(s["choice"] != nil ? "choice" : "shot")): \(d.prefix(6))"); return }
      prev = want
    }
  }
}

/* the comparison itself: a game out with one field changed must differ, so a pass above means something */
@Suite struct RulesCompareTests {
  @Test func diffCatchesChanges() {
    let pool = RulesTests.games.filter { !["snooker", "carom"].contains($0["kind"] as! String) }
    let G = pool.max { ($0["steps"] as! [Any]).count < ($1["steps"] as! [Any]).count }!, kind = G["kind"] as! String
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
    /* and snooker's own parts */
    let S = RulesTests.games.first { $0["kind"] as! String == "snooker" }!, ss = S["steps"] as! [[String: Any]]
    let sw = ss[ss.count / 2]["out"] as! [String: Any], sg = decodeGame(sw, rules: makeRules("snooker"))
    #expect(diffGame(sw, sg).isEmpty, "a decoded snooker game re-encodes to itself")
    var f = sg; f.snk!.brk += 1
    var h = sg; h.snk!.on = h.snk!.on == .red ? .colour : .red
    for (label, x) in [("the break", f), ("the ball on", h)] { #expect(!diffGame(sw, x).isEmpty, "snooker \(label) must show as a difference") }
  }
}

/* the app's glue: a shot simulated here and turned into the rules' view (RuleShot(result)) is the
   page's r for the same shot, for the first shots of every golden game */
@Suite struct RuleShotTests {
  @Test func fromResult() {
    var checked = 0
    for G in RulesTests.games {
      let sim = Sim(); sim.setPockets("regulation"); sim.setTable(G["table"] as! String, G["shape"] as? String)
      var prev = G["g0"] as! [String: Any]
      for s in (G["steps"] as! [[String: Any]]).prefix(6) {
        defer { prev = s["out"] as! [String: Any] }
        guard let sh = s["shot"] as? [String: Any] else { continue }
        var balls = (prev["balls"] as! [[String: Any]]).map(decodeBall)
        if let p = s["place"] as? [NSNumber], let i = balls.firstIndex(where: { $0.n == 0 }) { balls[i].x = p[0].doubleValue; balls[i].y = p[1].doubleValue; balls[i].on = true }
        let h = { (a: Any?) in Double(bitPattern: UInt64(a as! String, radix: 16)!) }, sp = sh["spin"] as! [String: Any]
        let input = balls.map { gb -> Ball in let b = Ball(gb.n, gb.x, gb.y); b.on = gb.on; return b }
        let got = RuleShot(sim.simulateShot(input, Sim.Shot(angle: h(sh["angle"]), power: h(sh["power"]), spin: Spin(x: h(sp["x"]), y: h(sp["y"])), ball: int(sh["ball"]) ?? 0)))
        let want = decodeShot(s["r"] as! [String: Any])
        let fields = [("balls", got.balls == want.balls), ("first", got.first == want.first), ("railAfter", got.railAfter == want.railAfter), ("crossed", got.crossed == want.crossed),
                      ("potted", got.potted == want.potted), ("pocketOf", got.pocketOf == want.pocketOf), ("rails", got.rails == want.rails), ("kick", got.kick == want.kick)]
        let bad = fields.filter { !$0.1 }.map { $0.0 }
        let ballDiff = zip(got.balls, want.balls).first { $0 != $1 }.map { "\($0.0) vs \($0.1)" } ?? ""
        #expect(bad.isEmpty, "\(G["name"]!): RuleShot(result) differs in \(bad) \(ballDiff.prefix(400))")
        #expect(got.balls == want.balls && got.first == want.first && got.railAfter == want.railAfter && got.crossed == want.crossed
                && got.potted == want.potted && got.pocketOf == want.pocketOf && got.rails == want.rails && got.kick == want.kick, "\(G["name"]!): RuleShot(result)")
        checked += 1
      }
    }
    #expect(checked > 100)
  }
}
