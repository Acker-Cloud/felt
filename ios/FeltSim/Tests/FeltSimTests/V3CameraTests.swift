/* 4o's camera against the page (tools/ios-golden.cjs: v3.json): on each table and two boxes, poses behind the cue ball
   (every matrix entry, F, the principal point, eye and target), points projected and unprojected through each, the
   orbit, its eye and a blend, and the overview's fit for three shot directions; every double by its bits */
import Foundation
import Testing
@testable import FeltSim

private func d(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String, radix: 16)!) }
private func ds(_ a: Any?) -> [Double]? { (a as? [Any])?.map { d($0) } }

@Suite struct V3CameraTests {
  @Test func cameras() throws {
    let url = try #require(Bundle.module.url(forResource: "v3.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var n = 0
    for c in fx["cams"] as! [[String: Any]] {
      let s = Sim()
      s.setPockets(c["pockets"] as! String); s.setTable(c["table"] as! String, c["shape"] as? String)
      let b = (c["box"] as! [NSNumber]).map { $0.doubleValue }, box = V3.Box(left: b[0], top: b[1], width: b[2], height: b[3])
      let name = "\(c["table"]!) \(Int(b[2]))x\(Int(b[3]))"
      for (k, p) in (c["poses"] as! [[String: Any]]).enumerated() {
        let C = V3.pose(s, box, px: d(p["px"]), py: d(p["py"]), yaw: d(p["yaw"]), pitch: (p["pitch"] as! NSNumber).doubleValue, dist: (p["dist"] as! NSNumber).doubleValue)
        #expect(C.M == ds(p["M"])! && C.F == d(p["F"]) && C.cx == d(p["cx"]) && C.cy == d(p["cy"]) && C.E == ds(p["E"])! && C.T == ds(p["T"])!, "\(name) pose \(k): matrices")
        let pts = [[s.TL / 2, s.TW / 2, 0], [d(p["px"]) + 0.3, d(p["py"]), s.BALL_R], [0, 0, 0.04], [s.TL, s.TW, 0], [d(p["px"]) - 0.2, d(p["py"]) + 0.1, 0]]
        for (i, P) in pts.enumerated() { #expect(V3.proj(C, box, P[0], P[1], P[2]) == ds((p["pts"] as! [Any])[i]), "\(name) pose \(k): proj \(i)") }
        let back = [[box.left + 100, box.top + 200], [box.left + box.width / 2, box.top + box.height * 0.7], [box.left + 10, box.top + 10]]
        for (i, Q) in back.enumerated() { #expect(V3.unproj(C, box, Q[0], Q[1], s.BALL_R) == ds((p["back"] as! [Any])[i]), "\(name) pose \(k): unproj \(i)") }
        let o = V3.orbitOf(C.E, C.T), e = V3.eyeOf(o), l = V3.lerp(o, V3.Orbit(T: [s.TL / 2, s.TW / 2, 0], yaw: o.yaw + 2.5, pitch: 0.9, dist: 2.4), 0.37)
        #expect(o.T + [o.yaw, o.pitch, o.dist] == ds(p["orbit"])! && e.E + e.T == ds(p["eye"])! && l.T + [l.yaw, l.pitch, l.dist] == ds(p["lerp"])!, "\(name) pose \(k): orbit")
        n += 1
      }
      for w in c["ovs"] as! [[String: Any]] {
        let o = V3.overview(s, box, d(w["yaw0"]))
        #expect(o.o.T == ds(w["T"])! && o.o.yaw == d(w["yaw"]) && o.o.pitch == d(w["pitch"]) && o.o.dist == d(w["dist"]) && o.fill == d(w["fill"]) && o.ok == (w["ok"] as! Bool),
                "\(name) overview from \(d(w["yaw0"])): \(o.o) vs \(w)")
        n += 1
      }
    }
    #expect(n == 84)
  }
  /* the input through the camera (v3Screen, v3Table, V3.k): a tap at a ball's projected centre maps back to that ball, a
     tap off the bed's plane misses it, and V3.k is the screen scale at the pivot (a centimetre across it, in px) */
  @Test func input() {
    let s = Sim()
    s.setTable("9")
    let R = s.BALL_R, box = V3.Box(left: 0, top: 0, width: 393, height: 700)
    for (px, py, yaw, pitch) in [(s.TL / 4, s.TW / 2, 0.0, 24.0), (s.TL * 0.6, s.TW * 0.3, 2.2, 50), (0.3, 0.2, -0.7, 10)] {
      let C = V3.pose(s, box, px: px, py: py, yaw: yaw, pitch: pitch, dist: 1.1)
      for (x, y) in [(px + 0.4 * cos(yaw), py + 0.4 * sin(yaw)), (s.TL / 2, s.TW / 2), (px + 0.05, py - 0.08)] {
        let p = V3.screen(C, box, x, y, R), q = V3.table(C, box, p[0], p[1], R)
        #expect(abs(q[0] - x) < 1e-9 && abs(q[1] - y) < 1e-9, "\(x), \(y) -> \(p) -> \(q)")
      }
      let k = V3.k(C, px, py, R), a = V3.screen(C, box, px, py, R), b = V3.screen(C, box, px - 0.005 * sin(yaw), py + 0.005 * cos(yaw), R)
      #expect(abs(JSMath.hypot(b[0] - a[0], b[1] - a[1]) / 0.005 - k) < 0.01 * k, "k \(k)")
      #expect(V3.table(C, box, box.width / 2, -1e4, R) == [-10, -10])
    }
  }
  /* 5c's pocket words in 3D (pocketFrame, pocketWords) and the call menu's picture (pocketOrder, pocketCell) against the
     page's own functions on every table, round the table from two pivots at a low and a high pitch */
  @Test func pocketWords() throws {
    let url = try #require(Bundle.module.url(forResource: "v3.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var n = 0, names = Set<String>()
    for c in fx["cams"] as! [[String: Any]] {
      let s = Sim()
      s.setPockets(c["pockets"] as! String); s.setTable(c["table"] as! String, c["shape"] as? String)
      let b = (c["box"] as! [NSNumber]).map { $0.doubleValue }, box = V3.Box(left: b[0], top: b[1], width: b[2], height: b[3])
      for w in c["words"] as! [[String: Any]] {
        let C = V3.pose(s, box, px: d(w["px"]), py: d(w["py"]), yaw: d(w["yaw"]), pitch: (w["pitch"] as! NSNumber).doubleValue, dist: 1.1)
        let words = s.POCKET_AIM.indices.map { V3.pocketWords(s, C, $0) }
        #expect(words == w["words"] as! [String], "\(c["table"]!) yaw \(d(w["yaw"])) pitch \(w["pitch"]!)")
        #expect(V3.pocketOrder(words) == (w["order"] as! [NSNumber]).map { $0.intValue } && words.map(V3.pocketCell) == (w["cells"] as! [[NSNumber]]).map { $0.map { $0.intValue } })
        if words.count == 6 { #expect(Set(words).count == 6, "two pockets of one name: \(words)") }
        names.formUnion(words); n += 1
      }
    }
    #expect(n == 512 && names.isSuperset(of: ["far left corner", "near right corner", "left side", "far side", "near side"]), "\(n) poses, \(names.sorted())")
  }
  /* 4o's air against v3Scene's own lines: a ball's shadow (on the bed, a jump at three heights, carried, dropping: where
     it falls, its grow, its two alphas) and the cue's tip and axis (level and raised, on the bed and in the air) */
  @Test func air() throws {
    let url = try #require(Bundle.module.url(forResource: "v3.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var n = 0
    for c in fx["cams"] as! [[String: Any]] {
      let s = Sim()
      s.setPockets(c["pockets"] as! String); s.setTable(c["table"] as! String, c["shape"] as? String)
      for k in c["casts"] as! [[String: Any]] {
        let i = ds(k["in"])!, o = V3.cast(s, x: i[0], y: i[1], z: i[2], air: i[3], a: i[4], liftH: 0.045, lampH: 1.1, light: [-0.55, -0.835])
        #expect([o.bx, o.by, o.grow, o.ao, o.ca] == ds(k["out"])!, "\(c["table"]!) cast \(i)")
        n += 1
      }
      for t in c["tips"] as! [[String: Any]] {
        let i = ds(t["in"])!, o = V3.cueTip(s, x: i[0], y: i[1], air: i[2], aim: i[3], sx: i[4], sy: i[5], el: i[6], gap: i[7])
        #expect(o.tip == ds(t["tip"])! && o.ax == ds(t["ax"])!, "\(c["table"]!) tip \(i)")
        n += 1
      }
    }
    #expect(n == 108 && V3.air(nil) == 0 && V3.air(-0.0) == 0 && V3.air(0.02) == 0.02)
  }
  /* 6b3 against the page's potPlan, potPlace and potCovered: on the pool tables and two boxes, the plan top-down and in
     3D (every slot's place, spot and room), then through four poses every 3D slot's projected window and, for each one
     shown, whether a ball, the cue or the loupe lies over it */
  @Test func pots() throws {
    let url = try #require(Bundle.module.url(forResource: "v3.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var n = 0, shown = 0, hid = [0, 0, 0]
    for c in fx["cams"] as! [[String: Any]] {
      guard let p = c["pots"] as? [String: Any] else { continue }
      let s = Sim()
      s.setPockets(c["pockets"] as! String); s.setTable(c["table"] as! String, c["shape"] as? String)
      let b = (c["box"] as! [NSNumber]).map { $0.doubleValue }, box = V3.Box(left: b[0], top: b[1], width: b[2], height: b[3]), name = "\(c["table"]!) \(Int(b[2]))x\(Int(b[3]))"
      let v = ds(p["view"])!, rail = d(p["rail"]), co = d(p["co"]), sights = (p["sights"] as! [Any]).map { ds($0)! }, z = d(p["z"]), len = d(p["len"])
      func same(_ P: PotRail.Plan, _ w: [String: Any], _ what: String) {
        let sides = (w["sides"] as! [[Any]]).map { $0.map { ds($0)! } }
        #expect(P.sides.map { $0.map { [$0.x, $0.y, $0.t[0], $0.t[1], $0.room] } } == sides, "\(name) \(what) slots")
        #expect(P.s == d(w["s"]) && P.ball == d(w["ball"]) && P.up == (w["up"] as! [NSNumber]).map { $0.doubleValue } && P.k == d(w["k"]) && P.half == d(w["half"]), "\(name) \(what) sizes")
      }
      let flat = PotRail.plan(s, k: v[0], ox: v[1], oy: v[2], portrait: true, live: false, rail: rail, co: co, sights: sights, screen: (b[2], b[3]))
      let P = PotRail.plan(s, k: v[0], ox: v[1], oy: v[2], portrait: true, live: true, rail: rail, co: co, sights: sights)
      same(flat, p["flat"] as! [String: Any], "top-down"); same(P, p["live"] as! [String: Any], "3D")
      let balls = (p["balls"] as! [[Any]]).filter { $0[3] as! Bool }.map { (x: d($0[0]), y: d($0[1]), z: d($0[2])) }
      for a in p["at"] as! [[String: Any]] {
        let C = V3.pose(s, box, px: d(a["px"]), py: d(a["py"]), yaw: d(a["yaw"]), pitch: (a["pitch"] as! NSNumber).doubleValue, dist: (a["dist"] as! NSNumber).doubleValue)
        let cue = (a["cue"] as! [Any]).map { ds($0)! }, places = (a["places"] as! [Any]).map { ds($0) }, cover = a["cover"] as! [[Bool]]
        let mine = P.sides.flatMap { $0 }.map { PotRail.place(P, $0, C, box, z: z) }
        #expect(mine == places, "\(name) pose \(n): places")
        var j = 0
        for f in mine.compactMap({ $0 }) {
          let lp = (x: box.left + box.width * 0.25, y: box.top + box.height * 0.55, r: 70.0)
          let got = [PotRail.covered(f[0], f[1], f[2] / 2, loupe: nil, cue: nil, cueLen: len, balls: balls, C, box, R: s.BALL_R),
                     PotRail.covered(f[0], f[1], f[2] / 2, loupe: nil, cue: (cue[0], cue[1]), cueLen: len, balls: [], C, box, R: s.BALL_R),
                     PotRail.covered(f[0], f[1], f[2] / 2, loupe: lp, cue: nil, cueLen: len, balls: [], C, box, R: s.BALL_R)]
          #expect(j < cover.count && got == cover[j], "\(name) pose \(n): window \(j) covered")
          for q in 0..<3 where got[q] { hid[q] += 1 }
          j += 1; shown += 1
        }
        #expect(j == cover.count)
        n += 1
      }
    }
    /* every table's poses ran, windows showed, and each of the ball, the cue and the loupe hid one or more */
    #expect(n == 24 && shown > 40 && hid.allSatisfy { $0 > 0 }, "\(n) poses, \(shown) windows, hidden \(hid)")
  }
}
