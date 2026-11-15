/* shot moments against the page (rules.json's games carry each shot's moments from the page's shotMoments, and the visit
   before it as noteShot keeps it): every shot of every golden game replayed here (placed, called, simulated for the full
   result, judged), the visit tracked the same way, and shotMoments compared: the legal pots, the moments, the visit */
import Foundation
import Testing
@testable import FeltSim

private func int(_ a: Any?) -> Int? { a is NSNull || a == nil ? nil : (a as! NSNumber).intValue }

@Suite struct MomentsTests {
  @Test func moments() {
    var n = 0, seen = Set<String>()
    for G in RulesTests.games {
      let name = G["name"] as! String, kind = G["kind"] as! String
      let sim = Sim(); sim.setPockets("regulation"); sim.setTable(G["table"] as! String, G["shape"] as? String)
      let E = RulesEngine(sim: sim)
      var cfg = CallConfig(); cfg.mode = G["mode"] as! String
      let rules = makeRules(kind, ruleset: G["ruleset"] as? String, call: cfg, race: int(G["race"]))
      var prev = G["g0"] as! [String: Any]
      var vis: (p: Int, pots: Int, fromBreak: Bool)? = nil
      for (k, s) in (G["steps"] as! [[String: Any]]).enumerated() {
        defer { prev = s["out"] as! [String: Any] }
        guard let sh = s["shot"] as? [String: Any], let m = s["m"] as? [Any] else { continue }
        var g = decodeGame(prev, rules: rules)
        if let p = s["place"] as? [NSNumber], let i = g.balls.firstIndex(where: { $0.n == 0 }) {
          g.balls[i].x = p[0].doubleValue; g.balls[i].y = p[1].doubleValue; g.balls[i].vx = 0; g.balls[i].vy = 0; g.balls[i].on = true
        }
        g.call = decodeCall(s["call"])
        let h = { (a: Any?) in Double(bitPattern: UInt64(a as! String, radix: 16)!) }, sp = sh["spin"] as! [String: Any]
        let input = g.balls.map { gb -> Ball in let b = Ball(gb.n, gb.x, gb.y); b.on = gb.on; return b }
        let res = sim.simulateShot(input, Sim.Shot(angle: h(sh["angle"]), power: h(sh["power"]), spin: Spin(x: h(sp["x"]), y: h(sp["y"])), ball: int(sh["ball"]) ?? 0))
        let out = E.judge(g, RuleShot(res)), p = g.turn
        let v: (p: Int, pots: Int, fromBreak: Bool) = vis.flatMap { $0.p == p ? $0 : nil } ?? (p, 0, g.breakShot)
        #expect(v.pots == int(m[2])! && v.fromBreak == (m[3] as! Bool), "\(name) step \(k): the visit \(v.pots) \(v.fromBreak)")
        let got = E.shotMoments(g, res, out, run: (v.pots, v.fromBreak)), want = (m[1] as! [String])
        #expect(got.legal == int(m[0])! && got.keys == want, "\(name) step \(k): \(got.legal) \(got.keys) vs \(m[0]) \(want)")
        vis = out.winner == nil && out.turn == p && out.verdict?.foul == nil ? (p, v.pots + got.legal, v.fromBreak) : nil
        seen.formUnion(got.keys); n += 1
      }
    }
    #expect(n == 3294)
    #expect(seen == ["bank", "point", "combo", "long", "kick", "double", "cleanBreak", "runOut"], "\(seen)")
  }
}
