/* practice against the page (tools/ios-golden.cjs: practice.json): rng's draws; on each pool table every layout's rack
   (the scatter by seed); practiceJudge on a pot, a scratch, the table cleared and the toggle on; the free table's
   editing (addBall over a grid from the empty table, then removeBall). Doubles by their bits. */
import Foundation
import Testing
@testable import FeltSim

private func d(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }
private func hx(_ v: Double) -> String { String(v.bitPattern, radix: 16) }
private func lay(_ bs: [GBall]) -> [[String]] { bs.map { ["\($0.n)", hx($0.x), hx($0.y), "\($0.on)"] } }
private func lay(_ a: Any?) -> [[String]] {
  (a as! [[Any]]).map { ["\(($0[0] as! NSNumber).intValue)", String(UInt64($0[1] as! String, radix: 16)!, radix: 16), String(UInt64($0[2] as! String, radix: 16)!, radix: 16), "\($0[3] as! Bool)"] }
}
private func ints(_ a: Any?) -> [Int]? { (a as? [NSNumber])?.map { $0.intValue } }

@Suite struct PracticeTests {
  @Test func practice() throws {
    let url = try #require(Bundle.module.url(forResource: "practice.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    for row in fx["draws"] as! [[Any]] {
      let r = rng(UInt32((row[0] as! NSNumber).uint32Value))
      #expect((1..<row.count).map { _ in r() } == row.dropFirst().map { d($0) }, "rng(\(row[0]))")
    }
    var n = 0
    for t in fx["tables"] as! [[String: Any]] {
      let T = t["table"] as! [Any], s = Sim()
      s.setPockets(T[2] as! String); s.setTable(T[0] as! String, T[1] as? String)
      let E = RulesEngine(sim: s), tn = T[0] as! String
      for r in t["racks"] as! [[String: Any]] {
        let layout = r["layout"] as! String, seed = UInt32((r["seed"] as! NSNumber).uint32Value), g = E.newPractice(layout, seed: seed)
        #expect(g.kind == r["kind"] as! String && g.layout == r["glayout"] as? String && g.inHand == r["inHand"] as? String && g.breakShot == r["breakShot"] as! Bool, "\(tn) \(layout) \(seed): the game")
        #expect(lay(g.balls) == lay(r["balls"]), "\(tn) \(layout) \(seed): the balls")
        n += 1
      }
      var g0 = E.newPractice("scatter", seed: 2)
      let mv = g0.balls.map { b -> GBall in var c = b; c.x = b.x + 0.01; c.vx = 0.5; return c }
      for j in t["judged"] as! [[String: Any]] {
        let potted = ints(j["potted"])!, hand = j["hand"] as! Bool
        g0.hand = hand; g0.dry = 2
        let balls = mv.map { b -> GBall in var c = b; c.on = !potted.contains(b.n); return c }
        let shot = RuleShot(balls: balls, first: nil, railAfter: false, crossed: nil, potted: potted, pocketOf: [:], rails: nil, kick: nil)
        let x = E.practiceJudge(g0, shot), v = j["v"] as! [Any]
        #expect(x.inHand == j["inHand"] as? String && x.dry == (j["dry"] as! NSNumber).intValue && x.shots == (j["shots"] as! NSNumber).intValue
                && x.turn == (j["turn"] as! NSNumber).intValue && x.breakShot == j["breakShot"] as! Bool, "\(tn) judge \(potted) hand \(hand)")
        #expect(x.verdict!.potted == ints(v[0])! && x.verdict!.scratch == v[1] as! Bool && x.verdict!.cleared == v[2] as? Bool, "\(tn) judge \(potted): the verdict")
        #expect(lay(x.balls) == lay(j["balls"]), "\(tn) judge \(potted): the balls")
        n += 1
      }
      var g = E.newPractice("empty", seed: 1)
      for e in t["edits"] as! [[Any]] {
        switch e[0] as! String {
        case "add":
          let r = E.addBall(g, d(e[1]), d(e[2]))
          #expect((r.map { E.onTable($0) }) == ints(e[3]), "\(tn) add at \(e[1]), \(e[2])")
          if let r { g = r }
        case "remove":
          let k = (e[1] as! NSNumber).intValue, r = E.removeBall(g, k)
          #expect((r.map { E.onTable($0) }) == ints(e[2]), "\(tn) remove \(k)")
          if let r { g = r }
        default: #expect(lay(g.balls) == lay(e[1]), "\(tn) the edited table")
        }
        n += 1
      }
    }
    #expect(n == 83)
  }
}
