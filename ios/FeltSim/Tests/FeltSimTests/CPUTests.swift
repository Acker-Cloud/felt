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
    let c = Self.cases[i], (cpu, g) = Self.state(c), level = c["level"] as! String
    /* a personality: cpuProfile({ level, arch }, { hill }) */
    cpu.arch = c["arch"] as? String; cpu.hill = c["hill"] as? Bool ?? false
    let name = "game \(c["gi"]!) step \(c["k"]!) \(level)" + (cpu.arch.map { " \($0)" } ?? "") + (cpu.hill ? " on the hill" : "")
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

  /* page 5's think once the plan is made (cpuAnim): the turn round the short way by 60%, then the pull to the power */
  @Test func anim() {
    #expect(CPU_ANIM_MS == 900)
    let from = 3.0, to = -3.0, pw = 0.8   /* the short way: across pi, 2pi - 6 */
    let d = 2 * Double.pi - 6
    let a0 = cpuAnim(0, from: from, to: to, power: pw)
    #expect(a0.aim == from && a0.pull == nil)
    let a3 = cpuAnim(0.3, from: from, to: to, power: pw)
    #expect(abs(a3.aim - (from + d * 0.875)) < 1e-12 && a3.pull == nil)
    let a6 = cpuAnim(0.6, from: from, to: to, power: pw)
    #expect(abs(a6.aim - (from + d)) < 1e-12 && a6.pull == nil, "on the line by 60%, the cue still at rest")
    let a8 = cpuAnim(0.8, from: from, to: to, power: pw)
    #expect(abs(a8.pull! - pw * 0.75) < 1e-12)
    let a1 = cpuAnim(1.4, from: from, to: to, power: pw)
    #expect(a1.aim == to && a1.pull == pw)
    var last = -1.0
    for i in 0...100 { let p = cpuAnim(Double(i) / 100, from: 0, to: 1, power: 1); #expect(p.aim >= last); last = p.aim }
  }
  /* the think wait on the frame clock: it runs with the frames, stands still while held (the pause menu, the handoff) and
     adds nothing for the time held, a frame's step at most 0.1 s; due at the hold over the speed */
  @Test func thinkClock() {
    var c = CPUThinkClock()
    c.step(10, held: false)
    #expect(c.el == 0 && !c.due(650, speed: 1))
    for k in 1...30 { c.step(10 + Double(k) / 60, held: false) }
    #expect(abs(c.el - 0.5) < 1e-9 && !c.due(650, speed: 1) && c.due(650, speed: 2))
    for k in 31...600 { c.step(10 + Double(k) / 60, held: true) }
    #expect(abs(c.el - 0.5) < 1e-9 && c.last == nil, "held ten seconds: the think stood still")
    c.step(30, held: false)
    #expect(abs(c.el - 0.5) < 1e-9, "the frame after the hold adds nothing")
    for k in 1...10 { c.step(30 + Double(k) / 60, held: false) }
    #expect(abs(c.el - (0.5 + 10.0 / 60)) < 1e-9 && c.due(650, speed: 1))
    c.step(31, held: false)
    #expect(abs(c.el - (0.6 + 10.0 / 60)) < 1e-9, "a long frame counts 0.1 s")
    c.step(30, held: false)
    #expect(abs(c.el - (0.6 + 10.0 / 60)) < 1e-9, "never backwards")
  }
}
