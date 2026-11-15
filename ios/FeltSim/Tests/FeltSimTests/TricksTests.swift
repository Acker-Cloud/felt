/* trick shots against the page (tools/ios-golden.cjs: tricks.json): on each table setting every challenge's layout and
   zone, its stored solution simulated (rest positions, pots, pockets) and judged (ok and the words, which must also be ok on
   every setting), and the program's numbers. Doubles by their bits. */
import Foundation
import Testing
@testable import FeltSim

private func d(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }
private func i(_ a: Any?) -> Int { (a as! NSNumber).intValue }

@Suite struct TricksTests {
  @Test func tricks() throws {
    let url = try #require(Bundle.module.url(forResource: "tricks.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    #expect(programMax() == i(fx["max"]))
    let val = (fx["val"] as! [[Any]]).map { "\($0[0]):\($0[1]):\(i($0[2]))" }.sorted()
    #expect(TRICK_VAL.map { "\($0.key):\($0.value.disc):\($0.value.val)" }.sorted() == val, "TRICK_VAL")
    #expect([6, 7, 8, 9, 10].map { v in [0, 1, 2, 3, 4].map { trickPts(v, $0) } } == (fx["pts"] as! [[NSNumber]]).map { $0.map(\.intValue) })
    #expect([1, 2, 3, 4, 9].map(trickStars) == (fx["stars"] as! [NSNumber]).map(\.intValue))
    #expect(trickScoreFromStars(["kiss": 3, "carom": 2, "two": 1, "long": 3, "bad": 3, "needle": 7], ["carom": 9]) == (fx["fromStars"] as! [String: NSNumber]).mapValues(\.intValue))
    var n = 0
    for set in fx["sets"] as! [[String: Any]] {
      let s = Sim(), t = set["table"] as! String
      s.setPockets(set["pockets"] as! String); s.setTable(t)
      let E = RulesEngine(sim: s), tag = t + (set["pockets"] as! String).prefix(1)
      let rows = set["rows"] as! [[String: Any]]
      #expect(rows.map { $0["id"] as! String } == TRICKS.map(\.id), "\(tag): the challenges")
      for row in rows {
        let c = trickById(row["id"] as! String)!, P = E.trickPoints(c), key = "\(tag) \(c.id)"
        let pts = (row["pts"] as! [[Any]]).map { r -> (Int, Double, Double) in let k = r[0] as! String; return (k == "zone" ? -1 : Int(k)!, d(r[1]), d(r[2])) }
        #expect(pts.count == P.count && pts.allSatisfy { P[$0.0] == [$0.1, $0.2] }, "\(key): the layout")
        let g = E.trickGame(c)
        #expect(g.balls.map(\.n) == (row["balls"] as! [NSNumber]).map(\.intValue) && g.mode == "trick" && g.inHand == nil && !g.breakShot, "\(key): the game")
        let res = s.simulateShot(g.balls.map { Ball($0.n, $0.x, $0.y) }, E.trickSol(c)!)
        let rest = (row["rest"] as! [[Any]]).map { r in "\(i(r[0])) \(r[1] as! String) \(r[2] as! String) \(r[3] as! Bool)" }
        #expect(res.balls.map { "\($0.n) \(String($0.x.bitPattern, radix: 16)) \(String($0.y.bitPattern, radix: 16)) \($0.on)" } == rest, "\(key): the rest")
        #expect(res.potted == (row["potted"] as! [NSNumber]).map(\.intValue), "\(key): the pots")
        #expect(res.pocketOf == Dictionary(uniqueKeysWithValues: (row["pocketOf"] as! [String: NSNumber]).map { (Int($0.key)!, $0.value.intValue) }), "\(key): the pockets")
        let j = E.trickJudge(c, res)
        #expect(j.ok == row["ok"] as! Bool && j.why == row["why"] as! String && j.ok, "\(key): judged \(j.ok) \(j.why)")
        /* the misses: the angle off, soft, turned back with half the side (the tip on the ball, as the pad keeps it) */
        let sol = E.trickSol(c)!
        for (k, m) in (row["miss"] as! [[Any]]).enumerated() {
          let (da, kp, ks) = [(0.06, 1.0, 1.0), (0, 0.35, 1), (Double.pi, 1, 0.5)][k]
          var sh = sol; sh.angle = sol.angle + da; sh.power = sol.power * kp; sh.spin.x = sol.spin.x * ks
          let r2 = s.simulateShot(g.balls.map { Ball($0.n, $0.x, $0.y) }, sh), j2 = E.trickJudge(c, r2)
          #expect(j2.ok == m[0] as! Bool && j2.why == m[1] as! String && r2.potted == (m[2] as! [NSNumber]).map(\.intValue), "\(key) miss \(k): \(j2.why) vs \(m[1])")
        }
        n += 1
      }
    }
    #expect(n == 124)
  }
}
