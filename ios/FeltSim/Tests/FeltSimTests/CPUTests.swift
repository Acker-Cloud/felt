/* 1f against the page: cpuShot at easy, medium and hard (fixed seeds) and cpuOption, from positions of
   the rules golden games (tools/ios-golden.cjs: cpu.json). The stroke is compared bit for bit, with
   where the cue ball is placed, the call and the intent. */
import Foundation
import Testing
@testable import FeltSim

@Suite struct CPUTests {
  nonisolated(unsafe) static let cases: [[String: Any]] = {
    let url = Bundle.module.url(forResource: "cpu.json", withExtension: nil, subdirectory: "Fixtures")!
    return (ExactJSON.parse(try! Data(contentsOf: url)) as! [String: Any])["cpu"] as! [[String: Any]]
  }()
  static func state(_ c: [String: Any]) -> (CPU, Game) {
    let G = RulesTests.games[(c["gi"] as! NSNumber).intValue], k = (c["k"] as! NSNumber).intValue, kind = G["kind"] as! String
    let sim = Sim(); sim.setPockets("regulation"); sim.setTable(G["table"] as! String, G["shape"] as? String)
    var cfg = CallConfig(); cfg.mode = G["mode"] as! String
    let rules = makeRules(kind, ruleset: G["ruleset"] as? String, call: cfg, race: (G["race"] as? NSNumber)?.intValue)
    let raw = k < 0 ? G["g0"] as! [String: Any] : (G["steps"] as! [[String: Any]])[k]["out"] as! [String: Any]
    return (CPU(engine: RulesEngine(sim: sim)), decodeGame(raw, rules: rules))
  }

  @Test(arguments: 0..<CPUTests.cases.count)
  func decision(_ i: Int) {
    let c = Self.cases[i], (cpu, g) = Self.state(c), level = c["level"] as! String, name = "game \(c["gi"]!) step \(c["k"]!) \(level)"
    if let want = c["option"] as? String {
      #expect(cpu.cpuOption(g, level: level) == want, "\(name): option")
      return
    }
    let got = cpu.cpuShot(g, seed: (c["seed"] as! NSNumber).doubleValue, level: level), w = c["shot"] as! [String: Any]
    let hx = { (v: Double) -> String in let s = String(v.bitPattern, radix: 16); return String(repeating: "0", count: 16 - s.count) + s }
    let sp = w["spin"] as! [String: Any], it = w["intent"] as! [String: Any]
    #expect(got.intent.type == it["type"] as! String && hx(got.intent.q) == it["q"] as! String, "\(name): intent \(got.intent) vs \(it)")
    #expect(hx(got.angle) == w["angle"] as! String && hx(got.power) == w["power"] as! String, "\(name): stroke")
    #expect(hx(got.spin.x) == sp["x"] as! String && hx(got.spin.y) == sp["y"] as! String && hx(got.spin.e) == sp["e"] as! String, "\(name): spin")
    #expect(got.place?.map(hx) == (w["place"] as? [String]), "\(name): place")
    let wc = w["call"] as? [String: Any]
    #expect((got.call == nil) == (wc == nil), "\(name): call present")
    if let gc = got.call, let wc { #expect(gc == decodeCall(wc)!, "\(name): call \(gc) vs \(wc)") }
    #expect(got.ball == (w["ball"] as? NSNumber)?.intValue && got.first == (w["first"] as? NSNumber)?.intValue, "\(name): carom's ball and first")
  }
}

/* the comparison has teeth: another seed moves the stroke, and the decisions are not all one shot */
@Suite struct CPUCompareTests {
  @Test func seedsAndLevelsMatter() {
    let shots = CPUTests.cases.filter { $0["shot"] != nil }
    #expect(shots.count > 300)
    let c = shots.first { (($0["shot"] as! [String: Any])["intent"] as! [String: Any])["type"] as! String == "pot" && $0["level"] as! String == "medium" }!
    let (cpu, g) = CPUTests.state(c), seed = (c["seed"] as! NSNumber).doubleValue
    let a = cpu.cpuShot(g, seed: seed, level: "medium"), b = cpu.cpuShot(g, seed: seed + 1, level: "medium")
    #expect(a.angle != b.angle || a.power != b.power, "another seed must move the stroke")
    let angles = Set(shots.map { ($0["shot"] as! [String: Any])["angle"] as! String })
    #expect(angles.count > shots.count / 2, "the goldens are many different shots")
  }
}
