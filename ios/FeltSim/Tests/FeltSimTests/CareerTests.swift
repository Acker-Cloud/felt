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
}
