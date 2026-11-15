/* The port's contract: index.html's sim, bit for bit. Fixtures from `node tools/ios-golden.cjs`
   (the page's own sim region on fdlibm math). Every double is compared by its bit pattern. */
import Foundation
import Testing
@testable import FeltSim

private func fixture(_ name: String) throws -> URL {
  try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
}
private func d(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }
private func hx(_ v: Double) -> String { let s = String(v.bitPattern, radix: 16); return String(repeating: "0", count: 16 - s.count) + s }
private func arr(_ a: Any?) -> [Any] { a as! [Any] }

private func fnv(_ h: UInt32, _ w: UInt32) -> UInt32 { (h ^ w) &* 16777619 }
private func fnvD(_ h: UInt32, _ v: Double) -> UInt32 {
  fnv(fnv(h, UInt32(truncatingIfNeeded: v.bitPattern >> 32)), UInt32(truncatingIfNeeded: v.bitPattern))
}
func hashBalls(_ B: [Ball]) -> UInt32 {
  var h: UInt32 = 2166136261
  for b in B {
    h = fnv(h, UInt32(truncatingIfNeeded: b.n)); h = fnv(h, b.on ? 1 : 0)
    for v in [b.x, b.y, b.vx, b.vy, b.wx, b.wy, b.wz] { h = fnvD(h, v) }
    for v in [b.z, b.vz] { if let v { h = fnvD(h, v) } else { h = fnv(h, 0xffffffff) } }
  }
  return h
}
func hashHits(_ H: [Hit]) -> UInt32 {
  var h: UInt32 = 2166136261
  for x in H {
    for c in x.kind.utf8 { h = fnv(h, UInt32(c)) }
    h = fnvD(h, x.v)
    if let t = x.tag { for c in t.utf8 { h = fnv(h, UInt32(c)) }; h = fnv(h, 0xfffffffe) }
    else { h = fnv(h, x.extra.map { UInt32(bitPattern: Int32($0)) } ?? 0xffffffff) }
  }
  return h
}

private func ball(_ o: [String: Any]) -> Ball {
  let b = Ball(o["n"] as! Int, d(o["x"]), d(o["y"]))
  b.vx = d(o["vx"]); b.vy = d(o["vy"]); b.wx = d(o["wx"]); b.wy = d(o["wy"]); b.wz = d(o["wz"]); b.on = o["on"] as! Bool
  b.z = o["z"].map { d($0) }; b.vz = o["vz"].map { d($0) }
  return b
}
private func ballBits(_ b: Ball) -> String {
  "\(b.n) \(b.on) " + [b.x, b.y, b.vx, b.vy, b.wx, b.wy, b.wz].map(hx).joined(separator: " ") + " z:\(b.z.map(hx) ?? "-") vz:\(b.vz.map(hx) ?? "-")"
}
private func intMap(_ a: Any?) -> [Int: Int] {
  var o: [Int: Int] = [:]
  for (k, v) in a as! [String: Any] { o[Int(k)!] = v as? Int }
  return o
}

@Suite struct GoldenTests {
  nonisolated(unsafe) static let golden: [String: Any] = {
    let url = Bundle.module.url(forResource: "golden.json", withExtension: nil, subdirectory: "Fixtures")!
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  }()

  @Test func math() throws {
    let txt = try String(contentsOf: fixture("math.txt"), encoding: .utf8)
    var bad = [Int](repeating: 0, count: 21), n = 0
    for line in txt.split(separator: "\n") {
      let f = line.split(separator: " ").map { Double(bitPattern: UInt64($0, radix: 16)!) }
      let (x, y, p, c) = (f[0], f[1], f[2], f[3])
      let got = [JSMath.sin(x), JSMath.cos(x), JSMath.tan(x), JSMath.atan(x), JSMath.acos(c), JSMath.exp(-y * 1.088), JSMath.exp(x),
        JSMath.pow(y, p), JSMath.pow(y, 1 / p), JSMath.hypot(x, y), JSMath.hypot(x, y, c),
        JSMath.atan2(c, x), JSMath.asin(c), JSMath.tanh(x), JSMath.atanh(c * 0.999), JSMath.log1p(y - 0.3), JSMath.expm1(x)]
      for (i, g) in got.enumerated() where g.bitPattern != f[4 + i].bitPattern { bad[i] += 1 }
      n += 1
    }
    #expect(n > 1000)
    #expect(bad.allSatisfy { $0 == 0 }, "mismatches per function (sin cos tan atan acos exp exp pow pow hypot2 hypot3 atan2 asin tanh atanh log1p expm1): \(bad)")
  }

  private func setUp(_ sim: Sim, _ c: [String: Any]) {
    /* a bumper table from the 7 ft table, as the generator does (the octagon keeps the last table's SKIMS) */
    if c["table"] as! String == "bumper" { sim.setTable("7") }
    sim.setPockets(c["pockets"] as! String)
    sim.setTable(c["table"] as! String, c["shape"] as? String)
  }

  @Test func tables() {
    let sim = Sim()
    for t in arr(Self.golden["tables"]) as! [[String: Any]] {
      setUp(sim, t)
      let name = "\(t["table"]!)/\(t["pockets"]!)"
      let flat = { (a: Any?) -> [String] in (a as! [Any]).flatMap { ($0 as? [Any])?.map { $0 as! String } ?? [$0 as! String] } }
      #expect(hx(sim.TL) == t["TL"] as! String && hx(sim.TW) == t["TW"] as! String, "\(name) bed")
      #expect(hx(sim.HEAD_X) == t["HEAD_X"] as! String && sim.FOOT.map(hx) == flat(t["FOOT"]), "\(name) spots")
      #expect(hx(sim.BALL_R) == t["BALL_R"] as! String, "\(name) ball")
      #expect(sim.CUSH.flatMap { $0.map(hx) } == flat(t["CUSH"]), "\(name) cushions")
      #expect(sim.POCKETS.flatMap { $0.map(hx) } == flat(t["POCKETS"]), "\(name) pockets")
      #expect(sim.POCKET_R.map(hx) == flat(t["POCKET_R"]), "\(name) pocket radii")
      #expect(sim.POCKET_AIM.flatMap { $0.map(hx) } == flat(t["POCKET_AIM"]), "\(name) mouths")
      #expect(sim.JAW_ARCS.flatMap { $0.map(hx) } == flat(t["JAW_ARCS"]), "\(name) jaw arcs")
      #expect(sim.BUMPERS.flatMap { $0.map(hx) } == flat(t["BUMPERS"] ?? []), "\(name) posts")
    }
  }

  @Test(arguments: 0..<(GoldenTests.golden["cases"] as! [Any]).count)
  func shot(_ i: Int) {
    let c = (Self.golden["cases"] as! [[String: Any]])[i], name = c["name"] as! String
    let sim = Sim()
    setUp(sim, c)
    let balls = (c["balls"] as! [[String: Any]]).map(ball)
    let s = c["shot"] as! [String: Any], sp = s["spin"] as! [String: Any]
    let tab = sim.strike(sim.newTable(balls, cue: s["ball"] as! Int), d(s["angle"]), d(s["power"]), Spin(x: d(sp["x"]), y: d(sp["y"]), e: d(sp["e"])))
    let every = c["hashEvery"] as! Int, hashes = (c["hashes"] as! [NSNumber]).map { $0.uint32Value }
    var k = 0, diverged: Int? = nil
    while sim.stepTable(tab) {
      if tab.steps % every == 0 {
        if diverged == nil && (k >= hashes.count || hashBalls(tab.balls) != hashes[k]) { diverged = tab.steps }
        k += 1
      }
    }
    #expect(diverged == nil, "\(name): ball state first differs by step \(diverged ?? 0)")
    #expect(k == hashes.count, "\(name): \(k) hash points, golden \(hashes.count)")
    let r = sim.resultOf(tab), g = c["result"] as! [String: Any]
    let want = (g["balls"] as! [[String: Any]]).map(ball)
    #expect(r.balls.map(ballBits) == want.map(ballBits), "\(name): final balls")
    #expect(r.steps == g["steps"] as! Int && hx(r.t) == g["t"] as! String, "\(name): steps \(r.steps) vs \(g["steps"]!)")
    #expect(r.end == g["end"] as? String, "\(name): end")
    #expect(r.first == g["first"] as? Int && r.kick == g["kick"] as? Int, "\(name): first contact")
    #expect(r.railAfter == g["railAfter"] as! Bool && r.crossed == g["crossed"] as! Bool, "\(name): railAfter / crossed")
    #expect(r.potted == g["potted"] as! [Int] && r.pocketOf == intMap(g["pocketOf"]), "\(name): pots")
    #expect(r.rails == intMap(g["rails"]), "\(name): rails")
    #expect(r.contacts == g["contacts"] as! [[Int]] && r.seq == g["seq"] as! [Int] && r.railSeq == g["railSeq"] as! [[Int]], "\(name): sequences")
    var railAt: [Int: [String]] = [:]
    for (k, v) in g["railAt"] as! [String: [String]] { railAt[Int(k)!] = v }
    #expect(r.railAt.mapValues { $0.map(hx) } == railAt, "\(name): railAt")
    #expect(r.over == g["over"] as? [Int], "\(name): over")
    #expect(tab.escaped == g["escaped"] as! Int, "\(name): escaped")
    #expect(tab.hits.count == c["hits"] as! Int && hashHits(tab.hits) == (c["hitsHash"] as! NSNumber).uint32Value, "\(name): hits")
  }
}
