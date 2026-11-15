/* drills against the page (tools/ios-golden.cjs: drills.json): on each table setting every drill run with its 7 ft
   regulation solutions and with two misses (angle off, soft): each shot's layout as the run reaches it (the balls by
   their bits, the words, the pocket, ring, line, box and ball on), its score, words, count and balls left, the total,
   and the tiers */
import Foundation
import Testing
@testable import FeltSim

private func d(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }
private func h(_ v: Double) -> String { String(v.bitPattern, radix: 16) }
private func norm(_ s: Any?) -> String { String(UInt64(s as! String, radix: 16)!, radix: 16) }

@Suite struct DrillsTests {
  @Test func drills() throws {
    let url = try #require(Bundle.module.url(forResource: "drills.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let sols = (try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../tests/drill-solutions.json"))) as! [String: Any])["7r"] as! [String: Any]
    var n = 0
    for set in fx["sets"] as! [[String: Any]] {
      let s = Sim(), t = set["table"] as! String, pk = set["pockets"] as! String
      s.setPockets(pk); s.setTable(t)
      let E = RulesEngine(sim: s), tag = t + pk.prefix(1)
      for row in set["rows"] as! [[String: Any]] {
        let id = row["id"] as! String, dr = drillById(id)!, key = "\(tag) \(id)"
        #expect(dr.shots == (row["shots"] as! NSNumber).intValue && dr.tiers == (row["tiers"] as! [NSNumber]).map(\.intValue), "\(key): the drill")
        #expect([0, 33, 45, 50, 66, 85, 99, 100].map { drillTier(dr, $0) } == (row["tierOf"] as! [NSNumber]).map(\.intValue), "\(key): tiers")
        let base = ((sols[id] as! [String: Any])["shots"] as! [[NSNumber]]).map { a in Sim.Shot(angle: a[0].doubleValue, power: a[1].doubleValue, spin: Spin(x: a[2].doubleValue, y: a[3].doubleValue)) }
        for run in row["runs"] as! [[String: Any]] {
          let da = (run["da"] as! NSNumber).doubleValue, kp = (run["kp"] as! NSNumber).doubleValue
          let shots = base.map { x -> Sim.Shot in var y = x; y.angle = x.angle + da; y.power = x.power * kp; return y }
          var prev: [Ball]? = nil
          for (i, L) in (run["lays"] as! [[String: Any]]).enumerated() {
            let S = E.drillShot(dr, i, prev), r = s.simulateShot(E.drillBalls(S).map { Ball($0.n, $0.x, $0.y) }, shots[i])
            let lb = (L["balls"] as! [[Any]]).map { "\(($0[0] as! NSNumber).intValue) \(norm($0[1])) \(norm($0[2]))" }
            #expect(S.balls.map { "\($0.0) \(h($0.1[0])) \(h($0.1[1]))" } == lb, "\(key) \(da)/\(kp) shot \(i): the balls")
            #expect(S.say == L["say"] as! String && S.pocket == (L["pocket"] as? NSNumber)?.intValue && S.target == (L["target"] as? NSNumber)?.intValue, "\(key) shot \(i): words, pocket, target")
            let z = S.zone.map { [h($0.at[0]), h($0.at[1]), h($0.full), h($0.zero)] }, lz = (L["zone"] as? [Any])?.map { norm($0) }
            let ln = S.line.map { "\(h($0.x)) \(h($0.full)) \(h($0.zero)) \($0.lag)" }, ll = (L["line"] as? [Any]).map { "\(norm($0[0])) \(norm($0[1])) \(norm($0[2])) \($0[3] as! Bool)" }
            #expect(z == lz && ln == ll && S.box.map { $0.map(h) } == (L["box"] as? [Any])?.map { norm($0) }, "\(key) shot \(i): ring, line, box")
            prev = r.balls
          }
          let R = E.drillRun(dr, shots), js = (run["js"] as! [[Any]])
          #expect(R.js.count == js.count, "\(key) \(da)/\(kp): shots played")
          for (j, x) in zip(R.js, js) {
            #expect(j.s == (x[0] as! NSNumber).intValue && j.why == x[1] as! String && j.n == (x[2] as! NSNumber).intValue && j.left == (x[3] as! NSNumber).intValue, "\(key) \(da)/\(kp): \(j.s) \(j.why) vs \(x[0]) \(x[1])")
          }
          #expect(R.total == (run["total"] as! NSNumber).intValue, "\(key) \(da)/\(kp): total \(R.total)")
          n += 1
        }
      }
    }
    #expect(n == 132)
  }
}
