/* the tutorials against the page (tools/ios-golden.cjs: tutorials.json): every step, both groups where 8-ball's numbers
   swap, on its tutorial's table: the game as laid (balls by their bits, the state its setup leaves) and after the
   solution's placement, then the stored solution and two misses struck, judged by the real judge and the step's goal
   (ok, the words, the pots, the foul, the winner, the turn, the banner), with the step's head, text, aim and pocket */
import Foundation
import Testing
@testable import FeltSim

private func h(_ v: Double) -> String { String(v.bitPattern, radix: 16) }
private func norm(_ s: Any?) -> String { String(UInt64(s as! String, radix: 16)!, radix: 16) }
private func i(_ a: Any?) -> Int? { (a as? NSNumber)?.intValue }

@Suite struct TutorialsTests {
  func view(_ g: Game) -> String {
    let on: String? = g.snk.map { s in switch s.on { case .red: "red"; case .colour: "colour"; case .ball(let n): "\(n)"; case .none: "none" } }
    return "\(g.balls.map { "\($0.n) \(h($0.x)) \(h($0.y))" }) \(g.inHand ?? "-") \(g.striker.map(String.init) ?? "-") \(g.need.map(String.init) ?? "-") \(g.groups.map { $0 ?? "-" }) \(g.open) \(on ?? "-") \(g.score ?? []) \(g.snk.map { String($0.brk) } ?? "-") \(g.breakShot) \(g.shots) \(g.turn)"
  }
  func view(_ o: [String: Any]) -> String {
    let balls = (o["balls"] as! [[Any]]).map { "\(i($0[0])!) \(norm($0[1])) \(norm($0[2]))" }
    let groups = (o["groups"] as! [Any]).map { ($0 as? String) ?? "-" }
    return "\(balls) \(o["inHand"] as? String ?? "-") \(i(o["striker"]).map(String.init) ?? "-") \(i(o["need"]).map(String.init) ?? "-") \(groups) \(o["open"] as! Bool) \(o["on"] as? String ?? "-") \((o["score"] as? [NSNumber])?.map(\.intValue) ?? []) \(i(o["brk"]).map(String.init) ?? "-") \(o["breakShot"] as! Bool) \(i(o["shots"])!) \(i(o["turn"])!)"
  }
  @Test func steps() throws {
    let url = try #require(Bundle.module.url(forResource: "tutorials.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any], steps = fx["steps"] as! [[String: Any]]
    for x in steps {
      let t = tutById(x["id"] as! String)!, si = i(x["i"])!, grp = x["grp"] as? String, st = t.steps[si], key = "\(t.id) \(si) \(grp ?? "")"
      let s = Sim(); s.setPockets(t.pockets); s.setTable(t.table[0], t.table.count > 1 ? t.table[1] : nil)
      let E = RulesEngine(sim: s), g0 = E.tutGame(t, si, grp)
      #expect(st.head == x["head"] as! String && st.text(grp ?? "solids") == x["text"] as! String && tutNum(t, si, grp, st.aim) == i(x["aim"]) && st.pocket == i(x["pocket"]), "\(key): the step's words")
      #expect(view(g0) == view(x["game"] as! [String: Any]), "\(key): the game \(view(g0))")
      let sol = tutSol(t.id, si)!, g = sol.place.map { E.placeCue(g0, $0[0], $0[1]) } ?? g0
      if let p = x["placed"] as? [String: Any] { #expect(view(g) == view(p), "\(key): placed") }
      let ball = sol.ball ?? (t.kind == "carom" ? g0.striker! : 0)
      for r in x["runs"] as! [[String: Any]] {
        let da = (r["da"] as! NSNumber).doubleValue, kp = (r["kp"] as! NSNumber).doubleValue
        var sh = sol.shot; sh.angle += da; sh.power *= kp; sh.ball = ball
        let res = s.simulateShot(g.balls.map { b -> Ball in let o = Ball(b.n, b.x, b.y); o.on = b.on; return o }, sh), j = E.tutJudge(t, si, g, RuleShot(res)), v = j.n.verdict
        let done = j.ok ? st.done?(j.n) : nil
        #expect(j.ok == r["ok"] as! Bool && j.why == r["why"] as! String, "\(key) \(da)/\(kp): \(j.ok) \(j.why) vs \(r["why"]!)")
        #expect(v?.potted == (r["potted"] as! [NSNumber]).map(\.intValue) && v?.foul == r["foul"] as? String && j.n.winner == i(r["winner"]) && j.n.turn == i(r["turn"]), "\(key) \(da)/\(kp): the verdict")
        #expect(done == (r["done"] as? [String]), "\(key) \(da)/\(kp): the banner")
      }
    }
    #expect(steps.count == 27)
  }
}
