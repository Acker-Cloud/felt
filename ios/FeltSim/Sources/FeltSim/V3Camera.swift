/* index.html 4o's camera, line for line (fdlibm and V8's hypot, as the page's numbers): the matrices for an eye and a
   target (v3Mats), a pose as an orbit (v3OrbitOf, v3EyeOf, v3Lerp), the overview's fit (v3OvPts, v3Overview), the
   player's pose behind the cue ball (v3Pose) and the projection both ways (v3Proj, v3Unproj). Table metres, z up;
   the render frame is the top-down view's handedness (z = -height). DOM-free: the box is the stage's CSS px rect. */
import Foundation

private typealias M = JSMath

public enum V3 {
  public static let PITCH = [8.0, 70], DIST = [0.45, 3.2], PITCH0 = 24.0, DIST0 = 1.1
  public static let FY = 0.5, AHEAD = 0.8, FOV = [21.0, 24], NEAR = 0.02
  public static let OUT_MS = 800.0, BACK_MS = 600.0, OV_MARGIN = 0.07, OV_YAW = [0.0, 15, -15, 30, -30, 45, -45], OV_PITCH = [40.0, 48, 56, 64]
  public static let ROOM_R = 9.0

  public struct Box: Sendable { public var left, top, width, height: Double
    public init(left: Double, top: Double, width: Double, height: Double) { self.left = left; self.top = top; self.width = width; self.height = height } }
  public struct Cam: Sendable {
    public let E, T, Er, f, r, u: [Double], V, P, M: [Double], F, cx, cy, W, H: Double
    public var yaw = 0.0, phase = "aim", mu = 1.0
  }
  public struct Orbit: Sendable { public var T: [Double], yaw, pitch, dist: Double
    public init(T: [Double], yaw: Double, pitch: Double, dist: Double) { self.T = T; self.yaw = yaw; self.pitch = pitch; self.dist = dist } }

  static func sub(_ a: [Double], _ b: [Double]) -> [Double] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
  static func dot(_ a: [Double], _ b: [Double]) -> Double { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
  static func cross(_ a: [Double], _ b: [Double]) -> [Double] { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
  static func norm(_ a: [Double]) -> [Double] { var l = M.hypot(a[0], a[1], a[2]); if l == 0 { l = 1 }; return [a[0] / l, a[1] / l, a[2] / l] }
  static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, v)) }

  /* the matrices for an eye E and a target T on a W x H box; Fo: a focal length of its own, centred (the loupe's) */
  public static func mats(_ E: [Double], _ T: [Double], _ W: Double, _ H: Double, _ Fo: Double? = nil) -> Cam {
    let Er = [E[0], E[1], -E[2]], Tr = [T[0], T[1], -T[2]], f = norm(sub(Tr, Er)), r = norm(cross(f, [0, 0, -1])), u = cross(r, f)
    let Vm = [r[0], u[0], -f[0], 0, r[1], u[1], -f[1], 0, r[2], u[2], -f[2], 0, -dot(r, Er), -dot(u, Er), dot(f, Er), 1]
    let F = Fo ?? Swift.min(W / (2 * M.tan(FOV[0] * Double.pi / 180)), H / (2 * M.tan(FOV[1] * Double.pi / 180)))
    let cx = W / 2, cy = Fo != nil ? H / 2 : H * FY, n = NEAR, fa = 40.0
    let Pm: [Double] = [2 * F / W, 0, 0, 0, 0, 2 * F / H, 0, 0, 1 - 2 * cx / W, -(1 - 2 * cy / H), (fa + n) / (n - fa), -1, 0, 0, 2 * fa * n / (n - fa), 0]
    var Mm = [Double](repeating: 0, count: 16)
    for i in 0..<4 { for j in 0..<4 { for k in 0..<4 { Mm[j * 4 + i] += Pm[k * 4 + i] * Vm[j * 4 + k] } } }
    return Cam(E: E, T: T, Er: Er, f: f, r: r, u: u, V: Vm, P: Pm, M: Mm, F: F, cx: cx, cy: cy, W: W, H: H)
  }
  public static func orbitOf(_ E: [Double], _ T: [Double]) -> Orbit {
    let dx = E[0] - T[0], dy = E[1] - T[1], dz = E[2] - T[2], h = M.hypot(dx, dy)
    return Orbit(T: T, yaw: M.atan2(-dy, -dx), pitch: M.atan2(dz, h), dist: M.hypot(h, dz))
  }
  public static func eyeOf(_ o: Orbit) -> (E: [Double], T: [Double]) {
    let c = M.cos(o.pitch) * o.dist
    return ([o.T[0] - M.cos(o.yaw) * c, o.T[1] - M.sin(o.yaw) * c, o.T[2] + M.sin(o.pitch) * o.dist], o.T)
  }
  public static func lerp(_ a: Orbit, _ b: Orbit, _ u: Double) -> Orbit {
    let dy = M.atan2(M.sin(b.yaw - a.yaw), M.cos(b.yaw - a.yaw))
    return Orbit(T: (0..<3).map { a.T[$0] + (b.T[$0] - a.T[$0]) * u }, yaw: a.yaw + dy * u, pitch: a.pitch + (b.pitch - a.pitch) * u, dist: a.dist * M.pow(b.dist / a.dist, u))
  }
  /* what the overview must show: the cushions' tops round the bed and every pocket's mouth (co: the cushion's width,
     0.05 before the geometry is built) */
  static func ovPts(_ s: Sim, co: Double = 0.05) -> [[Double]] {
    let h = s.BALL_R * 1.42, c = [s.TL / 2, s.TW / 2]
    var pts: [[Double]] = []
    for q in s.BED_LINES != nil ? s.octagon(0) : [[0, 0], [s.TL, 0], [s.TL, s.TW], [0, s.TW]] {
      let dx = q[0] - c[0], dy = q[1] - c[1]
      var l = M.hypot(dx, dy); if l == 0 { l = 1 }
      pts.append([q[0], q[1], 0]); pts.append([q[0] + dx / l * co * 1.42, q[1] + dy / l * co * 1.42, h])
    }
    for (i, P) in s.POCKETS.enumerated() { let r = s.POCKET_R[i]; for o in [[r, 0], [-r, 0], [0, r], [0, -r]] { pts.append([P[0] + o[0], P[1] + o[1], 0]) } }
    return pts
  }
  public struct Overview: Sendable { public var o: Orbit, fill: Double, ok: Bool, score = 0.0 }
  /* the overview after a shot: from the shooter's side (yaw within OV_YAW of the shot's), a pitch from OV_PITCH; each the
     distance and target that fit the points inside the box less OV_MARGIN a side, centred; the largest table wins, less a
     little for each degree turned and each degree up */
  public static func overview(_ s: Sim, _ box: Box, _ yaw0: Double, co: Double = 0.05) -> Overview {
    let W = box.width, H = box.height, pts = ovPts(s, co: co), m = OV_MARGIN, D = Double.pi / 180
    func fit(_ yaw: Double, _ pitch: Double) -> Overview {
      var T = [s.TL / 2, s.TW / 2, 0.0], dist = 4.0, fill = 0.0, ok = false, gx = 1.0, gy = 1.0, gd = 1.0
      var last: (ox: Double, oy: Double, sc: Double)? = nil
      let fh = [M.cos(yaw), M.sin(yaw)]
      var it = 0
      while it < 160 && !ok {
        it += 1
        let q = eyeOf(Orbit(T: T, yaw: yaw, pitch: pitch, dist: dist)), C = mats(q.E, q.T, W, H)
        var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity, dm = 0.0, behind = false
        for P in pts {
          let w = sub([P[0], P[1], -P[2]], C.Er), dd = dot(w, C.f)
          if dd < 0.1 { behind = true; break }
          let sx = C.cx + C.F * dot(w, C.r) / dd, sy = C.cy - C.F * dot(w, C.u) / dd
          x0 = Swift.min(x0, sx); x1 = Swift.max(x1, sx); y0 = Swift.min(y0, sy); y1 = Swift.max(y1, sy); dm += dd
        }
        if behind { dist *= 1.5; continue }
        dm /= Double(pts.count)
        let sc = Swift.max((x1 - x0) / (W * (1 - 2 * m)), (y1 - y0) / (H * (1 - 2 * m))), ox = (x0 + x1) / 2 - C.cx, oy = (y0 + y1) / 2 - C.cy
        fill = (x1 - x0) * (y1 - y0) / (W * H)
        ok = sc <= 1 && sc > 0.998 && abs(ox) < 0.5 && abs(oy) < 0.5
        if ok { break }
        /* a step that overshot (the sign flipped and grew) halves that step's gain from then on */
        if let l = last {
          if ox * l.ox < 0 && abs(ox) > 0.5 * abs(l.ox) { gx *= 0.5 }
          if oy * l.oy < 0 && abs(oy) > 0.5 * abs(l.oy) { gy *= 0.5 }
          if (sc - 1) * (l.sc - 1) < 0 && abs(sc - 1) > 0.5 * abs(l.sc - 1) { gd *= 0.5 }
        }
        last = (ox, oy, sc)
        let k = dm / C.F, sp = Swift.max(0.2, M.sin(pitch))
        T = [T[0] + (C.r[0] * ox * gx - fh[0] * oy * gy / sp) * k, T[1] + (C.r[1] * ox * gx - fh[1] * oy * gy / sp) * k, 0]
        dist = clamp(dist * M.pow(sc * 1.0008, gd), 0.5, ROOM_R * 0.6)
      }
      return Overview(o: Orbit(T: T, yaw: yaw, pitch: pitch, dist: dist), fill: fill, ok: ok)
    }
    var best: Overview? = nil
    for dy in OV_YAW {
      for pd in OV_PITCH {
        var o = fit(yaw0 + dy * D, pd * D)
        o.score = o.ok ? o.fill * (1 - 0.006 * abs(dy)) * (1 - 0.004 * (pd - OV_PITCH[0])) : -1 / o.o.dist
        if best == nil || o.score > best!.score { best = o }
      }
    }
    return best!
  }
  /* the player's pose: behind the pivot (px, py) on the yaw (the aim) at pitch (degrees) and distance; the move to or
     from the overview is the caller's (blend with lerp, then eyeOf) */
  public static func pose(_ s: Sim, _ box: Box, px: Double, py: Double, yaw: Double, pitch pitchDeg: Double, dist d0: Double) -> Cam {
    let W = box.width, H = box.height
    let p = clamp(pitchDeg, PITCH[0], PITCH[1]) * Double.pi / 180, d = clamp(d0, DIST[0], DIST[1]), R = s.BALL_R
    let ca = M.cos(yaw), sa = M.sin(yaw), hd = M.cos(p) * d, hc = s.BALL_R * 1.42
    let E = [px - ca * hd, py - sa * hd, Swift.max(R + M.sin(p) * d, hc + 0.05)], A = AHEAD * d * M.cos(p), T = [px + ca * A, py + sa * A, R * (1 - AHEAD)]
    var C = mats(E, T, W, H)
    C.yaw = yaw
    return C
  }
  /* table (x, y) at height z to page CSS px, and depth; nil behind the eye */
  public static func proj(_ C: Cam, _ box: Box, _ x: Double, _ y: Double, _ z: Double) -> [Double]? {
    let w = sub([x, y, -z], C.Er), d = dot(w, C.f)
    if d < NEAR { return nil }
    return [box.left + C.cx + C.F * dot(w, C.r) / d, box.top + C.cy - C.F * dot(w, C.u) / d, d]
  }
  /* a page point back onto the plane at height z: table [x, y], or nil where the ray never meets it */
  public static func unproj(_ C: Cam, _ box: Box, _ sx: Double, _ sy: Double, _ z: Double) -> [Double]? {
    let a = (sx - box.left - C.cx) / C.F, b = -(sy - box.top - C.cy) / C.F, dir = (0..<3).map { C.r[$0] * a + C.u[$0] * b + C.f[$0] }
    if abs(dir[2]) < 1e-9 { return nil }
    let t = (-z - C.Er[2]) / dir[2]
    if t <= 0 { return nil }
    return [C.Er[0] + dir[0] * t, C.Er[1] + dir[1] * t]
  }
}
