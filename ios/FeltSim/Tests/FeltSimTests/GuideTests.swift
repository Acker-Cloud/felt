/* 4d against the page: aimTrace and the shot preview (the page's own functions, run on fdlibm by
   tools/ios-golden.cjs) for racks and scatters on every table, full and short guides, bit for bit. */
import Foundation
import Testing
@testable import FeltSim

private func d(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }
private func hx(_ v: Double) -> String { let s = String(v.bitPattern, radix: 16); return String(repeating: "0", count: 16 - s.count) + s }

@Suite struct GuideTests {
  @Test(arguments: 0..<(GoldenTests.golden["guides"] as! [Any]).count)
  func guide(_ i: Int) {
    let g = (GoldenTests.golden["guides"] as! [[String: Any]])[i], name = g["name"] as! String
    let sim = Sim()
    sim.setPockets(g["pockets"] as! String); sim.setTable(g["table"] as! String, g["shape"] as? String)
    let balls = (g["balls"] as! [[String: Any]]).map { o -> Ball in
      let b = Ball(o["n"] as! Int, d(o["x"]), d(o["y"])); b.on = o["on"] as! Bool; return b
    }
    let cue = g["cue"] as! Int, c = balls.first { $0.n == cue }!, ang = d(g["ang"]), sp = g["spin"] as! [String: Any]
    let h = sim.aimTrace(balls, c.x, c.y, JSMath.cos(ang), JSMath.sin(ang), skip: [cue], far: 6)
    let wh = g["hit"] as! [String: Any]
    #expect(hx(h.t) == wh["t"] as! String && h.kind == wh["kind"] as! String && h.ball?.n == wh["ball"] as? Int && h.k == wh["k"] as! Int, "\(name): aimTrace")
    let lens = ["carom": PV_CAROM, "short": PV_SHORT][g["lens"] as! String] ?? PV_FULL
    let P = sim.previewStart(balls, cueN: cue, ang, d(g["pw"]), Spin(x: d(sp["x"]), y: d(sp["y"]), e: d(sp["e"])), h, lens, caromNeed: g["carom"] as! Int)
    sim.previewRun(P)
    let w = g["P"] as! [String: Any]
    let pts = { (a: [[Double]]?) -> [[String]]? in a?.map { $0.map(hx) } }
    #expect(P.s == w["s"] as! Int, "\(name): steps \(P.s) vs \(w["s"]!)")
    #expect(pts(P.cue) == w["cue"] as? [[String]], "\(name): cue path")
    #expect(pts(P.obj) == w["obj"] as? [[String]], "\(name): object path")
    #expect(P.first == w["first"] as? Int && P.crossed == w["crossed"] as! Bool, "\(name): first, crossed")
    #expect(P.cuePot == w["cuePot"] as! Int && P.objPot == w["objPot"] as! Int && P.objHit == w["objHit"] as! Bool && P.cueStop == w["cueStop"] as! Bool, "\(name): ends")
    #expect(pts(P.air) == w["air"] as? [[String]], "\(name): jump arc")
    #expect(pts(P.bounces) == w["bounces"] as? [[String]], "\(name): carom bounces")
  }
}
