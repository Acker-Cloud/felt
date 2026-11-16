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
}
