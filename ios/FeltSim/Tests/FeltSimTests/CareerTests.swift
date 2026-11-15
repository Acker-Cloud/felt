/* the career library against the page's (tools/ios-golden.cjs: career.json): generated players field by field, the
   match model's scores and first breakers, and brackets played through with every match's state at every step */
import Foundation
import Testing
@testable import FeltSim

@Suite struct CareerTests {
  nonisolated(unsafe) static let fx: [String: Any] = {
    let url = Bundle.module.url(forResource: "career.json", withExtension: nil, subdirectory: "Fixtures")!
    return ExactJSON.parse(try! Data(contentsOf: url)) as! [String: Any]
  }()
  static func num(_ a: Any?) -> Double { (a as! NSNumber).doubleValue }

  @Test func hashes() {
    for h in Self.fx["hashes"] as! [[Any]] { #expect(CareerLib.hashStr(h[0] as! String) == UInt32((h[1] as! NSNumber).uint64Value), "\(h[0])") }
  }
  @Test func players() {
    var names = Set<String>()
    let seed = Int(Self.num(Self.fx["seed"]))
    for o in Self.fx["players"] as! [[String: Any]] {
      let id = Int(Self.num(o["id"])), p = CareerLib.genPlayer(seed, id, &names)
      let av = o["avatar"] as! [String: Any]
      #expect(p.name == o["name"] as! String && p.nick == o["nick"] as! String && p.nat == o["nat"] as! String && p.town == o["town"] as! String, "\(id): \(p.name)")
      #expect(p.hand == o["hand"] as! String && p.age0 == Int(Self.num(o["age0"])) && p.talent == Self.num(o["talent"]) && p.peak == Int(Self.num(o["peak"])) && p.retire == Int(Self.num(o["retire"])), "\(id): age, talent")
      #expect(p.arch == o["arch"] as! String && p.disc == o["disc"] as! String && p.ini == av["ini"] as! String && p.col == av["col"] as! String, "\(id): arch, disc, avatar")
      let base = o["base"] as! [String: Any]
      #expect(CareerData.ATTRS.allSatisfy { p.base[$0] == Self.num(base[$0]) }, "\(id): attributes \(p.base)")
    }
  }
  @Test func models() {
    var names = Set<String>(), byId: [Int: CareerLib.Player] = [:]
    let seed = Int(Self.num(Self.fx["seed"]))
    for o in Self.fx["players"] as! [[String: Any]] { let id = Int(Self.num(o["id"])); byId[id] = CareerLib.genPlayer(seed, id, &names) }
    var n = 0
    for m in Self.fx["models"] as! [[String: Any]] {
      let a = byId[Int(Self.num(m["a"]))]!, b = byId[Int(Self.num(m["b"]))]!
      let r = CareerLib.playModel(.init(at: a.base, pref: a.disc, adj: Self.num(m["adj"])), .init(at: b.base, pref: b.disc), m["disc"] as! String, Int(Self.num(m["race"])), Self.num(m["seed"]))
      let want = (m["s"] as! [NSNumber]).map { $0.intValue }
      #expect(r.s == want && r.first == Int(Self.num(m["first"])), "model \(n) \(m["disc"]!): \(r.s) vs \(want)")
      n += 1
    }
    #expect(n == 300)
  }
  @Test func brackets() {
    for B in Self.fx["brackets"] as! [[String: Any]] {
      let fmt = B["fmt"] as! String, n = Int(Self.num(B["n"])), T = CareerLib.makeBracket(fmt, n)
      let want = B["M"] as! [[String: Any]]
      #expect(T.M.count == want.count, "\(fmt) \(n): \(T.M.count) matches vs \(want.count)")
      func ref(_ r: CareerLib.Ref) -> [String] { switch r { case .s(let i): return ["s", "\(i)"]; case .w(let m): return ["w", "\(m)"]; case .l(let m): return ["l", "\(m)"]; case .g(let g, let k): return ["g", "\(g)", "\(k)"]; case .n: return ["n"] } }
      for (i, w) in want.enumerated() where i < T.M.count {
        let x = T.M[i], wa = (w["a"] as! [Any]).map { "\($0)" }, wb = (w["b"] as! [Any]).map { "\($0)" }
        #expect(ref(x.a) == wa && ref(x.b) == wb && x.br == w["br"] as! String && x.rd == Int(Self.num(w["rd"])) && x.dep == Int(Self.num(w["dep"])), "\(fmt) \(n) match \(i)")
        #expect(x.fin == w["fin"] as! Bool && x.cond == w["cond"] as? String && x.of == (w["of"] as? NSNumber)?.intValue && x.st == (w["st"] as? NSNumber)?.intValue, "\(fmt) \(n) match \(i): fin, cond, stage")
      }
      /* played through: each step's states, then the next ready match given the page's result */
      let res = (B["res"] as! [Any]).map { ($0 as? [NSNumber])?.map { $0.intValue } }, f = (0..<n).map { 100 + $0 }
      var cur: [[Int]?] = T.M.map { _ in nil }
      for (k, step) in (B["steps"] as! [[[Any]]]).enumerated() {
        let c = CareerLib.Ctx(T, f, cur)
        for (m, w) in step.enumerated() {
          let o = CareerLib.outcome(c, m), enc = { (v: Int?) -> Int in v == nil ? -2 : v == CareerLib.NONE ? -1 : v! }
          #expect(o.st == w[0] as! String && enc(o.a) == (w[1] as! NSNumber).intValue && enc(o.b) == (w[2] as! NSNumber).intValue && enc(o.w) == (w[3] as! NSNumber).intValue,
                  "\(fmt) \(n) step \(k) match \(m): \(o) vs \(w)")
        }
        if let ready = (0..<T.M.count).first(where: { CareerLib.outcome(c, $0).st == "ready" }) { cur[ready] = res[ready] }
      }
    }
  }
  /* whole quick tournaments: the page's tourneyNew (field, draw, the CPU matches settled), the player's matches
     reported as the page reported them, every result after each, then the places and every round's name */
  @Test func tourneys() {
    let ints = { (a: Any?) -> [Int]? in (a as? [NSNumber])?.map { $0.intValue } }
    for o in Self.fx["tourneys"] as! [[String: Any]] {
      let kind = o["kind"] as! String, name = "\(kind) \(o["size"]!) \(o["fmt"]!)"
      var t = Tourney.make(kind: kind, ruleset: nil, size: Int(Self.num(o["size"])), fmt: o["fmt"] as! String, race: Int(Self.num(o["race"])),
                           field: o["field"] as! String, seed: Int(Self.num(o["seed"])))
      let st = o["start"] as! [String: Any], fw = st["field"] as! [[String: Any]]
      #expect(t.field.map { $0.name } == fw.map { $0["name"] as! String } && t.field.map { $0.level } == fw.map { $0["level"] as? String }, "\(name): field")
      #expect(t.field.map { $0.arch } == fw.map { $0["arch"] as? String } && t.f == ints(st["f"])! && t.ruleset == st["ruleset"] as! String && t.race == Int(Self.num(st["race"])), "\(name): draw, rules, race")
      #expect(t.res.map { $0 } == (st["res"] as! [Any]).map { ints($0) }, "\(name): the opening's CPU matches")
      for (k, r) in (o["reports"] as! [[String: Any]]).enumerated() {
        let m = Int(Self.num(r["m"]))
        #expect(t.mine() == m, "\(name) report \(k): the player's match")
        t.report(m, Int(Self.num(r["mine"])), Int(Self.num(r["theirs"])), forfeit: false)
        #expect(t.res.map { $0 } == (r["res"] as! [Any]).map { ints($0) } && t.sim == (r["sim"] as! [Bool]), "\(name) report \(k): results")
      }
      #expect(t.done == o["done"] as! Bool, "\(name): done")
      let wp = (o["places"] as? [[NSNumber]])?.map { $0.map { $0.intValue } }
      #expect(t.places == wp, "\(name): places \(String(describing: t.places)) vs \(String(describing: wp))")
      #expect(t.bracket.M.indices.map { CareerLib.roundName(t.fmt, t.bracket, $0) } == o["rounds"] as! [String], "\(name): round names")
    }
  }
  /* the career engine against the page: careers created in one store (ids c1, c2, c3), the state at each checkpoint
     the page traced, compared as JSON.stringify writes it */
  @Test func create() {
    let url = Bundle.module.url(forResource: "career.json", withExtension: nil, subdirectory: "Fixtures")!
    let fx = JV.parse(try! String(contentsOf: url, encoding: .utf8))!
    let E = CareerEngine()
    for c in fx["careers"]!.a {
      let r = E.create(c["profile"]!, seed: c["seed"]!.i)
      #expect(r.ok && r.id == c["id"]!.s, "\(c["profile"]!["name"]!.s): id \(String(describing: r.id))")
      for (k, want) in c["trace"]!.a.map({ $0.s }).enumerated() {
      let got = k < E.trace.count ? E.trace[k] : ""
      if got != want {
        let w = Array(want.utf8), g = Array(got.utf8), i = (0..<Swift.min(w.count, g.count)).first { w[$0] != g[$0] } ?? Swift.min(w.count, g.count)
        Issue.record("\(c["profile"]!["name"]!.s) checkpoint \(k): first difference at \(i): ...\(String(decoding: g[Swift.max(0, i - 60)..<Swift.min(g.count, i + 60)], as: UTF8.self))... vs ...\(String(decoding: w[Swift.max(0, i - 60)..<Swift.min(w.count, i + 60)], as: UTF8.self))...")
      }
      }
      #expect(E.digest() == c["digest"]!.s, "\(c["profile"]!["name"]!.s): Career.digest() \(E.digest()) vs \(c["digest"]!.s)")
      E.trace = []
      /* a season played: enter the first event open, a week ahead, a match due settled by the model */
      let name = c["profile"]!["name"]!.s
      for (k, step) in (c["play"]?.a ?? []).enumerated() {
        let day = E.S["day"]!.i, to = step["to"]?.str
        var stop: String?
        if to == "season" { stop = E.advance(toSeason: true) } else if to == "day" { stop = E.advance(days: 1) } else {
          let ev = E.S["cal"]!.a.first { $0["start"]!.i > day && E.eligibility($0).isEmpty }
          #expect(ev?["id"]?.str == step["enter"]?.str, "\(name) step \(k): entered \(String(describing: ev?["id"])) vs \(String(describing: step["enter"]))")
          if let ev { E.enter(ev["id"]!.s) }
          stop = E.advance(week: true)
        }
        if stop == "match" && to != "day" { E.simMatch() }
        #expect(stop == step["stop"]?.str && E.S["day"]!.i == step["day"]!.i, "\(name) step \(k): stopped \(String(describing: stop)) on day \(E.S["day"]!.i)")
        if let want = step["state"]?.str { let got = E.S.stringify(); if got != want {
          let w = Array(want.utf8), g = Array(got.utf8), i = (0..<Swift.min(w.count, g.count)).first { w[$0] != g[$0] } ?? Swift.min(w.count, g.count)
          Issue.record("\(name) step \(k): first difference at \(i): ...\(String(decoding: g[Swift.max(0, i - 80)..<Swift.min(g.count, i + 80)], as: UTF8.self))... vs ...\(String(decoding: w[Swift.max(0, i - 80)..<Swift.min(w.count, i + 80)], as: UTF8.self))...")
        } }
        if E.digest() != step["digest"]!.s { Issue.record("\(name) step \(k): digest \(E.digest()) vs \(step["digest"]!.s)"); break }
      }
    }
  }
  /* saves against the page's: the store's every key and value at each mark, and each call's answer */
  @Test func saves() {
    let url = Bundle.module.url(forResource: "career.json", withExtension: nil, subdirectory: "Fixtures")!
    let fx = JV.parse(try! String(contentsOf: url, encoding: .utf8))!
    let E = CareerEngine(), marks = fx["saves"]!.a
    var k = 0
    func snap(_ what: String, _ out: JV?) {
      let want = marks[k]; k += 1
      #expect(want["what"]!.s == what)
      if let o = want["out"]?.str { #expect(out?.stringify() == o, "\(what): \(out?.stringify() ?? "nil") vs \(o)") }
      let ws = Dictionary(want["store"]!.a.map { ($0[0]!.s, $0[1]!.s) }, uniquingKeysWith: { a, _ in a })
      #expect(Set(E.store.keys) == Set(ws.keys), "\(what): keys \(E.store.keys.sorted()) vs \(ws.keys.sorted())")
      for (key, v) in ws where E.store[key] != v { Issue.record("\(what): \(key) differs (\(E.store[key]?.count ?? -1) vs \(v.count) chars)") }
    }
    let r = E.create(["name": "Ada Save", "nat": "GB", "disc": "8", "style": "potter", "difficulty": "medium", "start": "amateur", "age": 28], seed: 31337)
    snap("create", ["ok": .bool(r.ok), "id": .str(r.id!)])
    for _ in 0..<6 {
      let day = E.S["day"]!.i
      if let ev = E.S["cal"]!.a.first(where: { $0["start"]!.i > day && E.eligibility($0).isEmpty }) { E.enter(ev["id"]!.s) }
      if E.advance(week: true) == "match" { E.simMatch() }
    }
    snap("played", nil)
    snap("slots", .arr(E.listSlots()))
    E.store["felt.career.v2.c1"] = "F2|junk"
    snap("slots-corrupt", .arr(E.listSlots()))
    let l1 = E.load("c1")
    snap("load-bak", ["ok": .bool(l1.ok), "recovered": l1.recovered.map { .str($0) } ?? .null, "digest": .str(E.digest())])
    E.store["felt.career.v2.c1"] = "x"; E.store["felt.career.v2.c1.bak"] = nil
    let l2 = E.load("c1")
    snap("load-none", ["ok": .bool(l2.ok), "why": .str(l2.why ?? "")])
    E.load("c1")
    let r2 = E.create(["name": "Bo Two", "nat": "SE", "disc": "snooker", "style": "defender", "difficulty": "easy", "start": "novice", "age": 19], seed: 99)
    snap("create2", ["ok": .bool(r2.ok), "id": .str(r2.id!)])
    snap("delete", ["ok": .bool(E.deleteSlot("c1"))])
    snap("slots-end", .arr(E.listSlots()))
  }
}
