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

  public static func sub(_ a: [Double], _ b: [Double]) -> [Double] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
  public static func dot(_ a: [Double], _ b: [Double]) -> Double { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
  public static func cross(_ a: [Double], _ b: [Double]) -> [Double] { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
  public static func norm(_ a: [Double]) -> [Double] { var l = M.hypot(a[0], a[1], a[2]); if l == 0 { l = 1 }; return [a[0] / l, a[1] / l, a[2] / l] }
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
  /* toScreen and toTable while the view is live (v3Screen, v3Table): a table point at a ball centre's height R to page px
     (far off screen behind the eye), and a page point back onto that plane (off the table where the ray misses) */
  public static func screen(_ C: Cam, _ box: Box, _ x: Double, _ y: Double, _ R: Double) -> [Double] { proj(C, box, x, y, R).map { [$0[0], $0[1]] } ?? [-1e5, -1e5] }
  public static func table(_ C: Cam, _ box: Box, _ sx: Double, _ sy: Double, _ R: Double) -> [Double] { unproj(C, box, sx, sy, R) ?? [-10, -10] }
  /* V3.k: the input's scale (tap reach, grab radius), CSS px per metre at the pivot (px, py) */
  public static func k(_ C: Cam, _ px: Double, _ py: Double, _ R: Double) -> Double { C.F / Swift.max(0.05, dot(sub([px, py, -R], C.Er), C.f)) }
  /* pocketFrame in 3D (5c): where pocket k lies from the table's middle along the camera's own axes, metres (f ahead,
     r to the right), so a pocket off the screen or behind the eye has its place too */
  public static func pocketFrame(_ s: Sim, _ C: Cam, _ k: Int) -> (f: Double, r: Double)? {
    guard k >= 0 && k < s.POCKET_AIM.count else { return nil }
    let p = s.POCKET_AIM[k], fh = M.hypot(C.f[0], C.f[1]), rh = M.hypot(C.r[0], C.r[1]), fl = fh != 0 ? fh : 1, rl = rh != 0 ? rh : 1
    let vx = p[0] - s.TL / 2, vy = p[1] - s.TW / 2
    return ((vx * C.f[0] + vy * C.f[1]) / fl, (vx * C.r[0] + vy * C.r[1]) / rl)
  }
  /* pocketWords in 3D: "far left corner", "near side". The corners ranked, never two of a name: the two farthest are
     far, of a pair the one more to the left left; the side pockets (opposite each other) by the axis they lie along */
  public static func pocketWords(_ s: Sim, _ C: Cam, _ k: Int) -> String {
    guard let q = pocketFrame(s, C, k) else { return "pocket" }
    if k == 1 || k == 4 { return "\(abs(q.r) >= abs(q.f) ? (q.r >= 0 ? "right" : "left") : (q.f >= 0 ? "far" : "near")) side" }
    let cs = s.POCKET_AIM.indices.filter { $0 != 1 && $0 != 4 }.compactMap { j in pocketFrame(s, C, j).map { (j: j, f: $0.f, r: $0.r) } }
      .enumerated().sorted { $0.element.f != $1.element.f ? $0.element.f > $1.element.f : $0.offset < $1.offset }.map { $0.element }
    let i = cs.firstIndex { $0.j == k } ?? 0, pair = i < 2 ? Array(cs.prefix(2)) : Array(cs.dropFirst(2)), o = pair.first { $0.j != k }
    return "\(i < 2 ? "far" : "near") \(q.r <= (o?.r ?? q.r) ? "left" : "right") corner"
  }
  /* POCKET_RANK, pocketCell, pocketOrder: the pockets in reading order as the player sees them (the far corners left then
     right, the sides, the near corners), each in its cell [row, column] of a 3 x 3 picture; top-down words read as far
     and near */
  public static let POCKET_RANK = ["far left corner", "far side", "far right corner", "left side", "right side", "near left corner", "near side", "near right corner"]
  static let POCKET_CELL = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 2], [2, 0], [2, 1], [2, 2]]
  public static func pocketRank(_ words: String) -> Int {
    var w = words
    if w.hasPrefix("top") { w = "far" + w.dropFirst(3) } else if w.hasPrefix("bottom") { w = "near" + w.dropFirst(6) }
    return POCKET_RANK.firstIndex(of: w) ?? -1
  }
  public static func pocketCell(_ words: String) -> [Int] { let r = pocketRank(words); return r >= 0 ? POCKET_CELL[r] : [1, 1] }
  public static func pocketOrder(_ words: [String]) -> [Int] {
    words.indices.sorted { a, b in let ra = pocketRank(words[a]), rb = pocketRank(words[b]); return ra != rb ? ra < rb : a < b }
  }
}

/* 4o's overlays: the 2D view's strokes laid on the bed as ribbons (v3Line, v3Strip, v3Push, v3PathZ): each polyline at one
   height, cut at the near plane, dashed as the bed measures it, then one mitred ribbon per run. A vertex: P (3), the point
   before and after it on its line (3 + 3: the joins are mitred in screen space), [side, width device px] (2), rgba (4) */
public struct V3Ribbons {
  public static let OVF = 15
  public var v: [Float] = []
  let C: V3.Cam
  public init(_ C: V3.Cam) { self.C = C }
  func depth(_ P: [Double]) -> Double { V3.dot(V3.sub(P, C.Er), C.f) - V3.NEAR * 2 }
  mutating func push(_ P: [Double], _ Q: [Double], _ N: [Double], _ s: Double, _ w: Double, _ c: [Double]) {
    v += [P[0], P[1], P[2], Q[0], Q[1], Q[2], N[0], N[1], N[2], s, w, c[0], c[1], c[2], c[3]].map { Float($0) }
  }
  mutating func strip(_ P: [[Double]], _ closed: Bool, _ w: Double, _ c: [Double]) {
    let n = P.count
    if n < 2 { return }
    func at(_ i: Int) -> [Double] { closed ? P[((i % n) + n) % n] : P[Swift.max(0, Swift.min(n - 1, i))] }
    let last = closed ? n : n - 1
    for i in 0..<last {
      let A = at(i), B = at(i + 1), Ap = closed || i > 0 ? at(i - 1) : A, Bn = closed || i + 2 < n ? at(i + 2) : B
      push(A, Ap, B, -1, w, c); push(A, Ap, B, 1, w, c); push(B, A, Bn, 1, w, c)
      push(A, Ap, B, -1, w, c); push(B, A, Bn, 1, w, c); push(B, A, Bn, -1, w, c)
    }
  }
  /* v3Tri: a filled triangle at height z (width 0: the shader lays it as it is), a colour at each corner; none unless all
     three are in front of the eye */
  public mutating func tri(_ ps: [[Double]], _ cs: [[Double]], z: Double = 0.0012) {
    let P = ps.map { [$0[0], $0[1], -z] }
    if !P.allSatisfy({ depth($0) > 0 }) { return }
    for i in 0..<3 { push(P[i], P[i], P[i], 0, 0, cs[i]) }
  }
  /* V3R.fill: a closed path of table points at height z as a fan from its middle, the colour per vertex (col: a flat
     colour or a gradient's at that point; rings 4 for a gradient, so it is evaluated across the shape) */
  public mutating func fill(_ pts: [[Double]], z: Double, rings: Int = 1, _ col: ([Double]) -> [Double]) {
    if pts.count < 3 { return }
    var mx = 0.0, my = 0.0
    for p in pts { mx += p[0]; my += p[1] }
    let m = [mx / Double(pts.count), my / Double(pts.count)]
    func L(_ u: [Double], _ f: Double) -> [Double] { [m[0] + (u[0] - m[0]) * f, m[1] + (u[1] - m[1]) * f] }
    for i in pts.indices {
      let p = pts[i], q = pts[(i + 1) % pts.count]
      for j in 0..<rings {
        let f0 = Double(j) / Double(rings), f1 = Double(j + 1) / Double(rings), qd = [L(p, f0), L(q, f0), L(q, f1), L(p, f1)], cs = qd.map(col)
        if j == 0 { tri([qd[0], qd[2], qd[3]], [cs[0], cs[2], cs[3]], z: z) }
        else { tri([qd[0], qd[1], qd[2]], [cs[0], cs[1], cs[2]], z: z); tri([qd[0], qd[2], qd[3]], [cs[0], cs[2], cs[3]], z: z) }
      }
    }
  }
  /* V3R.arc's ring: as many points as keep each chord about V3_ARC_PX device px where the camera sees its near side
     (scale: device px per CSS px) */
  public func arc(_ x: Double, _ y: Double, _ rm: Double, scale: Double) -> [[Double]] {
    let dd = V3.dot(V3.sub([x, y, 0], C.Er), C.f), n = Swift.max(8, Swift.min(720, Int((2 * Double.pi * rm * C.F * scale / Swift.max(V3.NEAR * 4, dd - rm) / V3Ribbons.ARC_PX).rounded(.up))))
    return (0..<n).map { i in let a = Double(i) / Double(n) * 2 * Double.pi; return [x + rm * cos(a), y + rm * sin(a)] }
  }
  public static let ARC_PX = 2.5
  /* v3PathZ: a closed path round a pocket (or outside the bed) sits on the rail tops, the rest on the bed */
  public static func pathZ(_ s: Sim, _ pts: [[Double]], _ closed: Bool, topH: Double) -> Double {
    if !closed || pts.isEmpty { return 0.0012 }
    var mx = 0.0, my = 0.0
    for p in pts { mx += p[0]; my += p[1] }
    mx /= Double(pts.count); my /= Double(pts.count)
    let atPocket = s.POCKETS.indices.contains { JSMath.hypot(mx - s.POCKETS[$0][0], my - s.POCKETS[$0][1]) < s.POCKET_R[$0] * 1.6 }
    let inside = s.BED_LINES.map { L in L.allSatisfy { $0[0] * mx + $0[1] * my - $0[2] >= 0 } } ?? (mx >= 0 && mx <= s.TL && my >= 0 && my <= s.TW)
    return inside && !atPocket ? 0.0012 : topH + 0.0012
  }
  /* v3Line: table points at height z, width w device px, dash in metres (nil: solid) */
  public mutating func line(_ pts: [[Double]], _ w: Double, _ c: [Double], dash: [Double]? = nil, closed: Bool = false, z: Double = 0.0012) {
    if pts.count < 2 { return }
    let P = pts.map { [$0[0], $0[1], -z] }, ring = closed ? P + [P[0]] : P
    var runs: [[[Double]]] = [], cur: [[Double]] = []
    for i in ring.indices {
      let B = ring[i], db = depth(B)
      if i > 0 {
        let A = ring[i - 1], da = depth(A)
        if (da > 0) != (db > 0) { let t = da / (da - db); cur.append((0..<3).map { A[$0] + (B[$0] - A[$0]) * t }); if db <= 0 { runs.append(cur); cur = [] } }
      }
      if db > 0 { cur.append(B) }
    }
    if !cur.isEmpty { runs.append(cur) }
    let whole = closed && runs.count == 1 && runs[0].count == ring.count
    for run in runs {
      let r = whole ? Array(run.dropLast()) : run
      guard let dash, dash.contains(where: { $0 > 0 }) else { strip(r, whole, w, c); continue }
      /* dashes along the run, measured on the bed as the 2D view measures them */
      let pl = whole ? r + [r[0]] : r
      var k = 0, left = dash[0], on = true, piece = [pl[0]]
      for i in 1..<pl.count {
        var a = pl[i - 1]
        let b = pl[i]
        var L = JSMath.hypot(b[0] - a[0], b[1] - a[1])
        while L > 1e-9 {
          let st = Swift.min(L, left), q = (0..<3).map { a[$0] + (b[$0] - a[$0]) * st / L }
          if on { piece.append(q) }
          a = q; L -= st; left -= st
          if left <= 1e-9 {
            if on && piece.count > 1 { strip(piece, false, w, c) }
            k = (k + 1) % dash.count; left = dash[k] > 0 ? dash[k] : 1e-3; on = !on; piece = [a]
          }
        }
      }
      if on && piece.count > 1 { strip(piece, false, w, c) }
    }
  }
}
