/* index.html 4m, the setup hero, on the canvas shim: the game's table seen low from behind its signature shot (Hero,
   HeroRun: the page's to the bit), hand-written perspective as the page's: a pinhole camera over the table plane
   (heroCam, heroProj, heroCamera's fit), drawTableImage's art turned to the camera's yaw and laid on the bed and the
   cushion and rail tops in bands of constant depth (heroTurnedJob, heroPlane), the apron and noses between them, the
   lamp's pool, the near rail over the balls (fg), the vignette (heroStill); each frame the balls from the recorded roll
   on the warped clock (heroSimT), the drops into their pockets on the screen's clock (heroPotT, HERO_DROP_MS), the
   bumper posts (heroPost) and the cue's stroke (heroCue), under the slow pull-back (HERO_ZOOM). */
import FeltRender
import FeltSim
import SwiftUI

enum HeroArt {
  static let CUE_MS = 560.0, ROLL_MS = 2340.0, DPR = 2.0, ZOOM = 1.14, DROP_MS = 260.0

  struct Geo { let TL, TW, R, rail, co, h: Double; let noses: [[Double]], polys: [[[Double]]], outline: [[Double]], mouths: Int, pockets: [[Double]], pr: [Double], posts: [[Double]], postR: Double }
  struct Data { let kind: String, spec: (table: String, shape: String?, pockets: String), geo: Geo, balls: [Ball], ball: Int, angle: Double, power: Double, spin: Spin }
  struct Cam { var E, f, r, u: [Double]; var F = 1.0, cx = 0.0, cy = 0.0, yaw: Double }
  struct Art { let C: Cam, bg: CGImage, fg: CGImage, vg: CGImage?, W: Int, H: Int }

  /* heroPrep: what the hero needs of the table, its layout and its shot */
  static func prep(_ kind: String, _ spec: (table: String, shape: String?, pockets: String)) -> Data {
    let s = Sim(); TableModel.setUp(s, spec)
    let P = TablePainter(sim: s, view: TableView2D(k: 1, ox: 0, oy: 0, portrait: false), dpr: 1, rail: RAIL_MAX, look: TableLook.of(game: kind))
    let co = P.cushionDepth(), su = Hero.setup(kind, RulesEngine(sim: s))
    let cx = s.TL / 2, cy = s.TW / 2
    func ang(_ p: [Double]) -> Double { atan2(p[1] - cy, p[0] - cx) }
    var noses: [[Double]] = []
    for q in s.CUSHION_POLYS { noses.append(q[1]); noses.append(q[2]) }
    noses.sort { ang($0) < ang($1) }
    let geo = Geo(TL: s.TL, TW: s.TW, R: s.BALL_R, rail: RAIL_MAX, co: co, h: s.BALL_R * 1.42, noses: noses, polys: s.CUSHION_POLYS, outline: V3Geo.outline(s, P, co),
                  mouths: s.MOUTHS.count, pockets: s.POCKETS, pr: s.POCKET_R, posts: s.BUMPERS, postR: BUMPER_R)
    return Data(kind: kind, spec: spec, geo: geo, balls: su.balls, ball: su.ball, angle: su.angle, power: su.power, spin: su.spin)
  }
  static func run(_ d: Data) -> HeroRun {
    let s = Sim(); TableModel.setUp(s, d.spec)
    let r = HeroRun(s, balls: d.balls.map { b -> Ball in let c = Ball(b.n, b.x, b.y); c.on = b.on; return c }, ball: d.ball, angle: d.angle, power: d.power, spin: d.spin)
    r.runAll()
    return r
  }

  // MARK: the camera
  static func sub(_ a: [Double], _ b: [Double]) -> [Double] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
  static func dot(_ a: [Double], _ b: [Double]) -> Double { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
  static func cross(_ a: [Double], _ b: [Double]) -> [Double] { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
  static func norm(_ a: [Double]) -> [Double] { let l = JSMath.hypot(a[0], a[1], a[2]); return [a[0] / l, a[1] / l, a[2] / l] }
  static func cam(_ E: [Double], _ T: [Double], _ roll: Double) -> Cam {
    let f = norm(sub(T, E)), r0 = norm(cross([0, 0, 1], f)), u0 = cross(f, r0), c = cos(roll), s = sin(roll)
    let r = (0..<3).map { r0[$0] * c + u0[$0] * s }, u = (0..<3).map { u0[$0] * c - r0[$0] * s }
    return Cam(E: E, f: f, r: r, u: u, yaw: atan2(f[1], f[0]))
  }
  static func proj(_ C: Cam, _ x: Double, _ y: Double, _ z: Double) -> [Double] {
    let dx = x - C.E[0], dy = y - C.E[1], dz = z - C.E[2], d = dx * C.f[0] + dy * C.f[1] + dz * C.f[2]
    return [C.cx + C.F * (dx * C.r[0] + dy * C.r[1] + dz * C.r[2]) / d, C.cy - C.F * (dx * C.u[0] + dy * C.u[1] + dz * C.u[2]) / d, d]
  }
  /* heroCamera: behind the shot at the pocket games and snooker, from an end at carom and bumper pool, fitted to the box */
  static func camera(_ d: Data, _ W: Double, _ H: Double, _ box: (x: Double, y: Double, w: Double, h: Double), _ tall: Double) -> Cam {
    let g = d.geo, L = g.TL, b = d.balls.first { $0.n == d.ball }!, kind = d.kind, up = 1 + 0.55 * tall
    var E: [Double], T: [Double]
    if kind == "carom" { T = [L * (0.56 - 0.06 * tall), g.TW * 0.56, 0]; E = [-0.16 * L * (1 + 0.5 * tall), -0.3 * L * (1 + 0.3 * tall), 0.36 * L * up] }
    else if kind == "bumper" { T = [L * 0.56, g.TW * 0.5, 0]; E = [-0.62 * L * (1 + 0.15 * tall), g.TW * 0.6, 0.78 * L * up] }
    else {
      let a = d.angle * 0.55, back = 0.9 * L * (1 + 0.2 * tall), ca = cos(a), sa = sin(a)
      T = [L * (0.66 - 0.08 * tall), g.TW / 2 + (b.y - g.TW / 2) * 0.25, 0]
      E = [b.x - ca * back, b.y - sa * back + (b.y < g.TW / 2 ? 1 : -1) * 0.04 * L, 0.54 * L * up]
    }
    var C = cam(E, T, kind == "bumper" ? 0 : 0.035 * (kind == "carom" ? -1 : 1))
    var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
    for q in g.outline { let p = proj(C, q[0], q[1], g.h); x0 = min(x0, p[0]); x1 = max(x1, p[0]); y0 = min(y0, p[1]); y1 = max(y1, p[1]) }
    let F = min(box.w / (x1 - x0), box.h / ((y1 - y0) * (0.86 + 0.14 * tall))) * (kind == "carom" ? 1.3 - 0.3 * tall : 1.06 - 0.06 * tall)
    C.F = F; C.cx = box.x + box.w / 2 - F * (x0 + x1) / 2; C.cy = box.y - F * y0
    return C
  }

  // MARK: the still parts
  struct Turned { let c, s, K, u0, v0: Double; let img: CGImage }
  static func mixRgb(_ hex: String, _ k: Double, _ to: [Double] = [0, 0, 0]) -> String {
    let c = RGBA(css: hex), v = [c.r * 255, c.g * 255, c.b * 255]
    return "rgb(" + (0..<3).map { String(Int((v[$0] + (to[$0] - v[$0]) * k + 0.5).rounded(.down))) }.joined(separator: ",") + ")"
  }
  /* heroTextureJob and heroTurnedJob: the table's art at K px a metre (posts left out), turned by -yaw */
  static func turned(_ d: Data, _ look: TableLook, _ yaw: Double) -> Turned {
    let g = d.geo, ext = g.rail + 0.02, K = min(720, 2400 / (g.TL + 2 * ext))
    let w = Int(((g.TL + 2 * ext) * K).rounded(.up)), h = Int(((g.TW + 2 * ext) * K).rounded(.up))
    let s = Sim(); TableModel.setUp(s, d.spec)
    var P = TablePainter(sim: s, view: TableView2D(k: K, ox: ext * K, oy: ext * K, portrait: false), dpr: 1, rail: RAIL_MAX, look: look)
    P.noPosts = true
    let tex = P.paint(width: w, height: h, vignette: false).image()
    let c = cos(yaw), sn = sin(yaw)
    var us: [Double] = [], vs: [Double] = []
    for q in [[-ext, -ext], [g.TL + ext, -ext], [g.TL + ext, g.TW + ext], [-ext, g.TW + ext]] { us.append((q[0] * c + q[1] * sn) * K); vs.append((-q[0] * sn + q[1] * c) * K) }
    let u0 = us.min()!.rounded(.down), v0 = vs.min()!.rounded(.down)
    let cv = Canvas2D(width: Int(us.max()!.rounded(.up) - u0 + 1), height: Int(vs.max()!.rounded(.up) - v0 + 1))
    cv.setTransform(c, -sn, sn, c, -u0, -v0)
    cv.drawImage(tex, -ext * K, -ext * K, Double(w), Double(h))
    return Turned(c: c, s: sn, K: K, u0: u0, v0: v0, img: cv.image())
  }
  /* heroPlane: the turned art on the plane z = h inside the clip, bands of 1.6 device px far to near, each one affine */
  static func plane(_ x: Canvas2D, _ C: Cam, _ T: Turned, _ h: Double, _ uLo: Double, _ uHi: Double) {
    let BAND = 1.6
    func at(_ u: Double, _ v: Double) -> [Double] { let U = (u + T.u0) / T.K, V = (v + T.v0) / T.K; return proj(C, U * T.c - V * T.s, U * T.s + V * T.c, h) }
    let vc = (-C.E[0] * T.s + C.E[1] * T.c) * T.K - T.v0, Hh = Double(T.img.height)
    var u = uHi
    while u > uLo {
      if at(u, vc)[2] < 0.05 { break }
      let p = at(u, vc), q = at(u - 1, vc), per = max(1e-3, JSMath.hypot(p[0] - q[0], p[1] - q[1]))
      let u0 = max(uLo, u - BAND / per), um = (u + u0) / 2
      if at(u0, vc)[2] < 0.05 { break }
      let a = at(u, vc), b = at(u0, vc), m = at(um, vc), m2 = at(um, vc + 64)
      let ju = [(a[0] - b[0]) / (u - u0), (a[1] - b[1]) / (u - u0)], jv = [(m2[0] - m[0]) / 64, (m2[1] - m[1]) / 64]
      x.setTransform(ju[0], ju[1], jv[0], jv[1], m[0] - ju[0] * um - jv[0] * vc, m[1] - ju[1] * um - jv[1] * vc)
      let ext = 1.2 / per
      x.drawImage(T.img, u0, 0, u - u0 + ext, Hh, u0, 0, u - u0 + ext, Hh)
      u = u0
    }
    x.setTransform(1, 0, 0, 1, 0, 0)
  }
  static func uRange(_ T: Turned, _ pts: [[Double]]) -> (Double, Double) {
    let us = pts.map { ($0[0] * T.c + $0[1] * T.s) * T.K - T.u0 }
    return (max(0, us.min()! - 2), min(Double(T.img.width), us.max()! + 2))
  }
  static func path(_ x: Canvas2D, _ C: Cam, _ pts: [[Double]], _ z: Double) {
    for (i, q) in pts.enumerated() { let p = proj(C, q[0], q[1], z); i == 0 ? x.moveTo(p[0], p[1]) : x.lineTo(p[0], p[1]) }
    x.closePath()
  }
  /* heroStill: W x H device px; txt: the words' block over the hero's foot, device px */
  static func still(_ d: Data, _ W: Int, _ H: Int, txt: Double, dress: Dress, vignette: Bool = true) -> Art {
    let Wd = Double(W), Hd = Double(H), tall = min(1, max(0, (Hd / Wd - 0.66) / 0.5)), top = Hd * (0.13 - 0.03 * tall)
    let box = (x: Wd * 0.04, y: top, w: Wd * 0.92, h: Hd * 0.62 + (Hd - 0.8 * txt - top - Hd * 0.62) * tall)
    let g = d.geo, C = camera(d, Wd, Hd, box, tall), look = TableLook.of(dress), RW = look.rail, CL = look.cloth
    let T = turned(d, look, C.yaw), x = Canvas2D(width: W, height: H), hC = g.h
    /* the room: near black, warmer where the lamp falls */
    x.fillStyle("#0b0b0c"); x.fillRect(0, 0, Wd, Hd)
    let mid = proj(C, g.TL / 2, g.TW / 2, 0)
    var gr = x.createRadialGradient(mid[0], mid[1], 0, mid[0], mid[1], max(Wd, Hd) * 0.75)
    if dress.room == "hall" { gr.addColorStop(0, "rgba(255,236,205,0.10)"); gr.addColorStop(1, "rgba(255,236,205,0)") }
    else { let R = TableLook.ROOM[dress.room] ?? TableLook.ROOM["hall"]!; gr.addColorStop(0, "rgba(\(R.glow),\(R.glowA * 1.45))"); gr.addColorStop(1, "rgba(\(R.glow),0)") }
    x.fillStyle = .gradient(gr); x.fillRect(0, 0, Wd, Hd)
    /* the bed (and everything at z 0) */
    let (uA, uB) = uRange(T, g.outline)
    x.save(); x.beginPath(); path(x, C, g.outline, 0); x.clip(); plane(x, C, T, 0, uA, uB); x.restore()
    /* the apron (the faces toward the eye, from its top down 15 cm) and the noses (and jaws), far first */
    var faces: [(a: [Double], b: [Double], z0: Double, z1: Double, d: Double, apron: Bool)] = []
    let O = g.outline
    for i in O.indices {
      let a = O[i], b = O[(i + 1) % O.count], mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2, nx = b[1] - a[1], ny = a[0] - b[0]
      if nx * (C.E[0] - mx) + ny * (C.E[1] - my) > 0 { faces.append((a, b, hC, -0.15, proj(C, mx, my, 0)[2], true)) }
    }
    let cx = g.TL / 2, cy = g.TW / 2
    for q in g.polys {
      for (a, b) in g.mouths > 0 ? [(q[1], q[2]), (q[0], q[1]), (q[2], q[3])] : [(q[1], q[2])] {
        let mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2
        var nx = b[1] - a[1], ny = a[0] - b[0]
        if nx * (cx - mx) + ny * (cy - my) < 0 { nx = -nx; ny = -ny }
        if nx * (C.E[0] - mx) + ny * (C.E[1] - my) > 0 { faces.append((a, b, hC, 0, proj(C, mx, my, 0)[2], false)) }
      }
    }
    faces.sort { $0.d > $1.d }
    for f in faces {
      let t0 = proj(C, f.a[0], f.a[1], f.z0), t1 = proj(C, f.b[0], f.b[1], f.z0), b1 = proj(C, f.b[0], f.b[1], f.z1), b0 = proj(C, f.a[0], f.a[1], f.z1)
      x.beginPath(); x.moveTo(t0[0], t0[1]); x.lineTo(t1[0], t1[1]); x.lineTo(b1[0], b1[1]); x.lineTo(b0[0], b0[1]); x.closePath()
      gr = x.createLinearGradient(0, min(t0[1], t1[1]), 0, max(b0[1], b1[1]))
      if f.apron { gr.addColorStop(0, mixRgb(RW.base, 0.25)); gr.addColorStop(0.12, mixRgb(RW.base, 0.5)); gr.addColorStop(1, mixRgb(RW.base, 0.88)) }
      else { gr.addColorStop(0, mixRgb(CL.cushion, 0.05, [255, 255, 255])); gr.addColorStop(0.35, mixRgb(CL.cushion, 0.3)); gr.addColorStop(1, mixRgb(CL.cushion, 0.62)) }
      x.fillStyle = .gradient(gr); x.fill()
    }
    /* the rubber and rail tops, at their height */
    x.save(); x.beginPath(); path(x, C, g.outline, hC); path(x, C, g.noses, hC); x.clip(.evenodd); plane(x, C, T, hC, uA, uB); x.restore()
    /* the lamp's pool on the bed */
    let lamp = proj(C, g.TL * 0.55, g.TW / 2, 0), e = proj(C, g.TL, g.TW / 2, 0), lr = JSMath.hypot(e[0] - lamp[0], e[1] - lamp[1]) * 1.1
    x.cg.setBlendMode(.plusLighter)
    gr = x.createRadialGradient(lamp[0], lamp[1], 0, lamp[0], lamp[1], max(lr, Wd * 0.4))
    gr.addColorStop(0, "rgba(\(CL.lamp),0.07)"); gr.addColorStop(0.6, "rgba(\(CL.lamp),0.025)"); gr.addColorStop(1, "rgba(\(CL.lamp),0)")
    x.fillStyle = .gradient(gr); x.fillRect(0, 0, Wd, Hd)
    x.cg.setBlendMode(.normal)
    /* fg: the rail and rubber nearer than the nearest nose, which a ball against them sits behind */
    let nd = g.noses.map { ($0[0] * T.c + $0[1] * T.s) * T.K - T.u0 }.min()!, y = Canvas2D(width: W, height: H)
    y.save(); y.beginPath(); path(y, C, g.outline, hC); path(y, C, g.noses, hC); y.clip(.evenodd); plane(y, C, T, hC, uA, nd); y.restore()
    var vg: CGImage? = nil
    if vignette {
      let z = Canvas2D(width: W, height: H)
      let gv = z.createRadialGradient(Wd / 2, Hd * 0.42, min(Wd, Hd) * 0.35, Wd / 2, Hd * 0.42, JSMath.hypot(Wd, Hd) * 0.62)
      gv.addColorStop(0, "rgba(0,0,0,0)"); gv.addColorStop(1, "rgba(0,0,0,0.55)")
      z.fillStyle = .gradient(gv); z.fillRect(0, 0, Wd, Hd)
      vg = z.image()
    }
    return Art(C: C, bg: x.image(), fg: y.image(), vg: vg, W: W, H: H)
  }

  // MARK: a frame
  static func easeIO(_ u: Double) -> Double { u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2 }
  /* heroSimT: the sim's seconds at playback fraction u: near real time at the strike, faster as they slow */
  static func simT(_ run: HeroRun, _ u: Double) -> Double {
    let S = run.S, a = min(1, max(0.06, 0.62 * ROLL_MS / 1000 / S))
    return S * (a * u + (1 - a) * pow(u, 2.4))
  }
  /* heroPotT: the hero's clock (ms) when the sim reaches a pot's time */
  static func potT(_ run: HeroRun, _ t: Double) -> Double {
    var lo = 0.0, hi = 1.0
    for _ in 0..<40 { let mid = (lo + hi) / 2; if simT(run, mid) < t { lo = mid } else { hi = mid } }
    return CUE_MS + hi * ROLL_MS
  }
  static func draw(_ t: Double, _ d: Data, _ run: HeroRun, _ A: Art, _ x: Canvas2D, bp: BallPainter, dress: Dress) {
    let C = A.C, g = d.geo, Wd = Double(A.W), Hd = Double(A.H), total = CUE_MS + ROLL_MS, still = t >= total
    let z = still ? 1 : 1 + (ZOOM - 1) * (1 - easeIO(min(1, t / total)))
    let c0 = d.balls.first { $0.n == d.ball }!, fc = proj(C, c0.x, c0.y, g.R), F0 = proj(C, g.TL * 0.6, g.TW / 2, 0)
    let fx = (fc[0] + F0[0]) / 2, fy = (fc[1] + F0[1]) / 2
    func Z(_ p: [Double]) -> [Double] { [fx + (p[0] - fx) * z, fy + (p[1] - fy) * z, p[2]] }
    x.setTransform(1, 0, 0, 1, 0, 0)
    x.drawImage(A.bg, fx - fx * z, fy - fy * z, Wd * z, Hd * z)
    let n = d.balls.count, s: Double = t < CUE_MS ? -1 : still ? .infinity : simT(run, (t - CUE_MS) / ROLL_MS)
    let dt = Double(HERO_SUB) * SIM_DT, nS = run.pos.count
    struct Item { var ball = 0, p: [Double] = [], q: [Double] = [], m: Mat3 = [], fade = 1.0, drop: (k: Int, u: Double)? = nil, d = 0.0, rd = 0.0, post: [Double]? = nil }
    var list: [Item] = []
    for i in 0..<n {
      var bx: Double, by: Double, bz = g.R, on = true, m: Mat3, fade = 1.0, drop: (k: Int, u: Double)? = nil
      if s < 0 { bx = d.balls[i].x; by = d.balls[i].y; m = artTilt(d.balls[i].n) }
      else if s == .infinity { let p = run.pos[nS - 1]; bx = p[2 * i]; by = p[2 * i + 1]; on = run.on[nS - 1][i]; m = run.rot[nS - 1][(9 * i)..<(9 * i + 9)].map { Double($0) } }
      else {
        let f = min(Double(nS - 1), s / dt), k = Int(f.rounded(.down)), k1 = min(nS - 1, k + 1), w = f - Double(k), P = run.pos[k], Q = run.pos[k1]
        on = run.on[k1][i]; bx = P[2 * i] + (Q[2 * i] - P[2 * i]) * w; by = P[2 * i + 1] + (Q[2 * i + 1] - P[2 * i + 1]) * w
        m = run.rot[k][(9 * i)..<(9 * i + 9)].map { Double($0) }
        if !on, let pt = run.pots[i], pt.k >= 0, pt.k < g.pockets.count {
          let u = (t - potT(run, pt.t)) / DROP_MS
          if u >= 0 && u < 1 {
            let P2 = g.pockets[pt.k], e = 1 - (1 - u) * (1 - u)
            bx = pt.at[0] + (P2[0] - pt.at[0]) * e; by = pt.at[1] + (P2[1] - pt.at[1]) * e
            bz = g.R * (1 - 2.6 * u * u); fade = 1 - u * u; drop = (pt.k, u); on = true
          }
        }
      }
      if !on { continue }
      let p = Z(proj(C, bx, by, bz)), q = Z(proj(C, bx, by, 0))
      list.append(Item(ball: d.balls[i].n, p: p, q: q, m: m, fade: fade, drop: drop, d: p[2], rd: drop != nil ? Z(proj(C, bx, by, g.R))[2] : p[2]))
    }
    for pp in g.posts { let p = Z(proj(C, pp[0], pp[1], 0)); list.append(Item(d: p[2], post: pp)) }
    list.sort { $0.d > $1.d }
    /* contact shadows, flattened to the bed by how low the eye looks at it */
    for o in list where o.post == nil {
      let r = C.F * g.R / o.rd * z, sq = min(1, max(0.28, C.E[2] / JSMath.hypot(C.E[0], C.E[1], C.E[2]) * 1.1))
      x.setTransform(1, 0, 0, sq, o.q[0], o.q[1])
      bp.drawShadow(x, 0, 0, r, alpha: 0.9 * (o.drop.map { max(0, 1 - 2.5 * $0.u) } ?? o.fade))
    }
    x.setTransform(1, 0, 0, 1, 0, 0)
    for o in list {
      if let pp = o.post { post(x, C, g, pp[0], pp[1], Z, z); continue }
      let r = C.F * g.R / o.rd * z
      let ax = (0..<3).map { j -> [Double] in let w = [o.m[j], o.m[3 + j], o.m[6 + j]]; return [dot(w, C.r), -dot(w, C.u), -dot(w, C.f)] }
      if let dr = o.drop {
        /* the pocket's mouth on the bed, the cut closing from the ball's width to the hole's as it falls */
        let P2 = g.pockets[dr.k], rr = g.pr[dr.k] + g.R * (1 - dr.u)
        x.save(); x.beginPath()
        for j in 0...24 { let a = Double(j) / 24 * 2 * Double.pi, w = Z(proj(C, P2[0] + rr * cos(a), P2[1] + rr * sin(a), 0)); j == 0 ? x.moveTo(w[0], w[1]) : x.lineTo(w[0], w[1]) }
        x.clip(); bp.drawBall(x, o.ball, o.p[0], o.p[1], r, ax, alpha: 1 - pow(dr.u, 1.4), dark: min(1, 1.6 * dr.u)); x.restore()
      } else { bp.drawBall(x, o.ball, o.p[0], o.p[1], r, ax, alpha: o.fade, dark: 1 - o.fade) }
    }
    x.setTransform(1, 0, 0, 1, 0, 0)
    x.drawImage(A.fg, fx - fx * z, fy - fy * z, Wd * z, Hd * z)
    if !still { cue(x, C, g, d, t, Z, z, dress) }
    x.setTransform(1, 0, 0, 1, 0, 0)
    if let vg = A.vg { x.drawImage(vg, 0, 0, Wd, Hd) }
  }
  /* heroPost: a black rubber ring round a turned nickel cap, standing on the bed */
  static func post(_ x: Canvas2D, _ C: Cam, _ g: Geo, _ px: Double, _ py: Double, _ Z: ([Double]) -> [Double], _ z: Double) {
    let hp = 0.052, b = Z(proj(C, px, py, 0)), t = Z(proj(C, px, py, hp)), r = C.F * g.postR / b[2] * z, rt = C.F * g.postR / t[2] * z
    let sq = min(1, max(0.15, abs(b[1] - Z(proj(C, px + C.f[0] * g.postR, py + C.f[1] * g.postR, 0))[1]) / max(1e-6, r)))
    var gr = x.createLinearGradient(b[0] - r, 0, b[0] + r, 0)
    gr.addColorStop(0, "#050505"); gr.addColorStop(0.3, "#2b2b2e"); gr.addColorStop(0.45, "#4a4a4f"); gr.addColorStop(0.7, "#141416"); gr.addColorStop(1, "#030303")
    x.fillStyle = .gradient(gr)
    x.beginPath(); x.moveTo(t[0] - rt, t[1]); x.lineTo(b[0] - r, b[1]); x.ellipse(b[0], b[1], r, r * sq, Double.pi, 0, true); x.lineTo(t[0] + rt, t[1]); x.closePath(); x.fill()
    gr = x.createRadialGradient(t[0] - rt * 0.3, t[1] - rt * sq * 0.4, 0, t[0], t[1], rt)
    gr.addColorStop(0, "#f4f2ec"); gr.addColorStop(0.45, "#a9a6a0"); gr.addColorStop(1, "#4a4844")
    x.fillStyle = .gradient(gr); x.beginPath(); x.ellipse(t[0], t[1], rt * 0.82, rt * sq * 0.82, 0, Double.pi * 2); x.fill()
    x.strokeStyle("#0b0b0c"); x.lineWidth = max(1, rt * 0.18); x.beginPath(); x.ellipse(t[0], t[1], rt * 0.91, rt * sq * 0.91, 0, Double.pi * 2); x.stroke()
  }
  /* heroCue: draws back, strikes at CUE_MS, follows through, then lifts away and fades */
  static func cue(_ x: Canvas2D, _ C: Cam, _ g: Geo, _ d: Data, _ t: Double, _ Z: ([Double]) -> [Double], _ z: Double, _ dress: Dress) {
    let T0 = CUE_MS, b = d.balls.first { $0.n == d.ball }!, dx = cos(d.angle), dy = sin(d.angle)
    var gap: Double, alpha = 1.0
    if t < 0.66 * T0 { gap = 0.03 + 0.2 * easeIO(t / (0.66 * T0)) }
    else if t < 0.74 * T0 { gap = 0.23 }
    else if t < T0 { let u = (t - 0.74 * T0) / (0.26 * T0); gap = 0.23 * (1 - u * u) }
    else {
      let u = (t - T0) / 420
      if u >= 1 { return }
      gap = -0.05 * min(1, u * 3) - 0.1 * max(0, u - 0.33)
      let e = min(1, max(0, (u - 0.25) / 0.75)); alpha = 1 - e * e * (3 - 2 * e)
    }
    let (cu, tip) = CueLook.of(dress), GC = CueGeo.of(game: d.kind), pool = GC.pool, len = pool ? 1.45 : GC.len, el = 0.1, R = g.R
    func at(_ s: Double) -> [Double] { let k = gap + R + s * cos(el); return [b.x - dx * k, b.y - dy * k, R + s * sin(el)] }
    func rad(_ s: Double) -> Double { pool ? 0.0064 + (0.0145 - 0.0064) * pow(s / len, 1.3) : GC.r0 + GC.dr * pow(s / len, 1.3) }
    let shEnd = GC.joint ?? (GC.sleeve?[0] ?? 0.74)
    let parts: [(Double, Double, [String])] = pool
      ? [(0, 0.006, [tip]), (0.006, 0.02, ["#f2efe6"]), (0.02, 0.98, cu.shaft), (0.98, 1.0, [cu.metal]), (1.0, 1.06, [cu.joint]), (1.06, 1.2, [cu.fore]), (1.2, 1.36, [cu.wrap]), (1.36, 1.44, [cu.sleeve]), (1.44, len, [cu.cap])]
      : [(GC.ferrule, shEnd, cu.shaft)] + cueParts(cu, tip, GC).map { ($0.0, $0.1, [$0.2]) }
    x.globalAlpha = alpha
    for (s0, s1, col) in parts {
      var p1 = at(s1)
      let p0 = at(s0), d0 = dot(sub(p0, C.E), C.f), d1 = dot(sub(p1, C.E), C.f)
      if d0 < 0.08 { continue }
      var e1 = s1
      if d1 < 0.08 { e1 = s0 + (s1 - s0) * (d0 - 0.08) / (d0 - d1); p1 = at(e1) }
      let A = Z(proj(C, p0[0], p0[1], p0[2])), B = Z(proj(C, p1[0], p1[1], p1[2])), ra = C.F * rad(s0) / A[2] * z, rb = C.F * rad(e1) / B[2] * z
      let ux = B[0] - A[0], uy = B[1] - A[1]
      var ul = JSMath.hypot(ux, uy); if ul == 0 { ul = 1 }
      let nx = -uy / ul, ny = ux / ul
      x.beginPath(); x.moveTo(A[0] + nx * ra, A[1] + ny * ra); x.lineTo(B[0] + nx * rb, B[1] + ny * rb); x.lineTo(B[0] - nx * rb, B[1] - ny * rb); x.lineTo(A[0] - nx * ra, A[1] - ny * ra); x.closePath()
      let m = [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2], rm = (ra + rb) / 2, gr = x.createLinearGradient(m[0] + nx * rm, m[1] + ny * rm, m[0] - nx * rm, m[1] - ny * rm)
      let base = col[0]
      gr.addColorStop(0, mixRgb(base, 0.55)); gr.addColorStop(0.3, base); gr.addColorStop(0.42, mixRgb(base, 0.35, [255, 255, 255])); gr.addColorStop(0.6, col.count > 1 ? col[1] : base); gr.addColorStop(1, mixRgb(base, 0.6))
      x.fillStyle = .gradient(gr); x.fill()
    }
    x.globalAlpha = 1
  }
}

/* the hero on screen: built off the main thread (the roll, the still), then a frame a display refresh until the shot's
   end, the last frame held; a tap replays it; Reduce Motion: the final still */
@MainActor @Observable final class HeroModel {
  var frame: CGImage? = nil
  @ObservationIgnored var parts: (d: HeroArt.Data, run: HeroRun, art: HeroArt.Art, bp: BallPainter, dress: Dress)? = nil
  @ObservationIgnored var t0 = 0.0
  @ObservationIgnored var key = ""
  var done = false
  func build(_ game: TableGame, size: CGSize, txt: Double) {
    let W = Int(size.width * HeroArt.DPR), H = Int(size.height * HeroArt.DPR), k = "\(game.rawValue)|\(W)x\(H)"
    if key == k || W < 8 || H < 8 { return }
    key = k
    let kind = game.table.2, dress = Prefs.dress(kind), spec = TableModel.spec(for: game)
    Task.detached(priority: .userInitiated) {
      let d = HeroArt.prep(kind, spec), run = HeroArt.run(d), art = HeroArt.still(d, W, H, txt: txt * HeroArt.DPR, dress: dress)
      let look = TableLook.of(dress), cloth = RGBA(css: look.cloth.base)
      let bp = BallPainter(set: BallSet.all[dress.balls] ?? BallSet.all["classic"]!, bounce: look.cloth.bounce, dpr: HeroArt.DPR, portrait: false,
                           lowRim: look.cloth.lowRim, rimAll: look.cloth.rim, clothBase: [cloth.r * 255, cloth.g * 255, cloth.b * 255])
      let built = Built(d: d, run: run, art: art, bp: bp)
      await MainActor.run {
        guard self.key == k else { return }
        self.parts = (built.d, built.run, built.art, built.bp, dress)
        self.replay()
      }
    }
  }
  func replay() { t0 = CACurrentMediaTime(); done = false; if UIAccessibility.isReduceMotionEnabled { t0 -= 10; tick() } }
  func tick() {
    guard let p = parts, !done else { return }
    let t = (CACurrentMediaTime() - t0) * 1000
    let x = Canvas2D(width: p.art.W, height: p.art.H)
    HeroArt.draw(t, p.d, p.run, p.art, x, bp: p.bp, dress: p.dress)
    frame = x.image()
    if t >= HeroArt.CUE_MS + HeroArt.ROLL_MS { done = true }
  }
}

struct HeroView: View {
  let game: TableGame
  var txt = 0.0
  @State private var hero = HeroModel()
  var body: some View {
    GeometryReader { g in
      TimelineView(.animation(paused: hero.done)) { tl in
        ZStack {
          Color(rgb: 11, 11, 12)
          if let f = hero.frame { Image(decorative: f, scale: HeroArt.DPR).resizable().frame(width: g.size.width, height: g.size.height) }
        }
        .onChange(of: tl.date) { _, _ in hero.tick() }
      }
      .onAppear { hero.build(game, size: g.size, txt: txt) }
      .onChange(of: g.size) { _, s in hero.build(game, size: s, txt: txt) }
      .contentShape(Rectangle())
      .onTapGesture { hero.replay() }
    }
    .accessibilityLabel("\(game.rawValue) table, its signature shot")
  }
}

/* what the build hands the main thread, made once off it and never touched there again */
private final class Built: @unchecked Sendable {
  let d: HeroArt.Data, run: HeroRun, art: HeroArt.Art, bp: BallPainter
  init(d: HeroArt.Data, run: HeroRun, art: HeroArt.Art, bp: BallPainter) { self.d = d; self.run = run; self.art = art; self.bp = bp }
}
