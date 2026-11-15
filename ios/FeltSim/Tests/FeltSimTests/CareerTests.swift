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
      func ref(_ r: CareerLib.Ref) -> [String] { switch r { case .s(let i): return ["s", "\(i)"]; case .w(let m): return ["w", "\(m)"]; case .l(let m): return ["l", "\(m)"]; case .n: return ["n"] } }
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
          let o = CareerLib.outcome(c, m), enc = { (v: Int?) -> Int in v ?? -2 }
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
    }
  }
}
