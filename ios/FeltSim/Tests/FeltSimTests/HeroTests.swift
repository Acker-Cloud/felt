/* the setup hero against the page (tools/ios-golden.cjs: hero.json): on each table, heroSetup's shot and the recorded
   roll (heroRunStart, heroSample every HERO_SUB steps): the sample count, a sample midway, the rest, which balls are up,
   each pot's time, pocket and where it left the bed, the last motion, and every ball's turn; doubles by their bits, the
   recorded turns as the page's Float32Array */
import Foundation
import Testing
@testable import FeltSim
import FeltRender

private func d(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }
private func ds(_ a: Any?) -> [Double] { (a as! [Any]).map { d($0) } }

@Suite struct HeroTests {
  @Test func rolls() throws {
    let url = try #require(Bundle.module.url(forResource: "hero.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var n = 0
    for h in fx["heroes"] as! [[String: Any]] {
      let kind = h["kind"] as! String, args = h["args"] as! [Any], s = Sim()
      s.setPockets(args[2] as! String); s.setTable(args[0] as! String, args[1] as? String)
      let key = Hero.key(kind, s), E = RulesEngine(sim: s), su = Hero.setup(kind, E)
      #expect(key == h["key"] as! String, "\(kind): key \(key)")
      let sh = h["shot"] as! [Any]
      #expect(su.ball == (sh[0] as! NSNumber).intValue && su.angle == d(sh[1]) && su.power == d(sh[2]), "\(key): the shot")
      let run = HeroRun(s, balls: su.balls, ball: su.ball, angle: su.angle, power: su.power, spin: su.spin)
      run.runAll()
      #expect(run.pos.count == (h["samples"] as! NSNumber).intValue, "\(key): \(run.pos.count) samples vs \(h["samples"]!)")
      if run.pos.count == (h["samples"] as! NSNumber).intValue {
        #expect(run.pos[run.pos.count / 2] == ds(h["mid"]) && run.pos.last! == ds(h["last"]) && run.on.last! == (h["on"] as! [Bool]), "\(key): positions")
      }
      let pots = (h["pots"] as! [[Any]]).sorted { ($0[0] as! NSNumber).intValue < ($1[0] as! NSNumber).intValue }
      let mine = run.pots.keys.sorted()
      #expect(mine == pots.map { ($0[0] as! NSNumber).intValue }, "\(key): which balls went down")
      for p in pots where run.pots[(p[0] as! NSNumber).intValue] != nil {
        let q = run.pots[(p[0] as! NSNumber).intValue]!
        #expect(q.t == d(p[1]) && q.k == (p[2] as! NSNumber).intValue && q.at == ds(p[3]), "\(key): pot of ball \(p[0])")
      }
      #expect(run.moveT == d(h["moveT"]) && run.S == d(h["S"]), "\(key): the last motion")
      #expect(run.m == (h["m"] as! [Any]).map { ds($0) }, "\(key): every ball's turn")
      #expect(run.rot.last! == (h["rot"] as! [NSNumber]).map { $0.floatValue }, "\(key): the recorded turns")
      n += 1
    }
    #expect(n == 14)
  }
}
