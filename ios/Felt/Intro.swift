/* index.html 6o, the opening: a cold open of about 4.5 s on a cold launch at home, then the home. The setup hero's
   renderer (Hero.swift) on two cameras of its own (introCams): low behind the shot, its still running on above the frame
   so it starts on the lamp and tilts down to the rack, then a cut at the cue ball's first contact (a flash and a small
   shake) to high over the table. The game is the last one played if it is a pocket game, else 8-ball on the 9 ft table,
   in the player's look; the roll on the opening's own clock (a sim second a screen second, introClock), the stroke its
   own (introCueGap). One enamel pendant (introLight: its pool baked into the stills, the fixture a layer that settles on
   its cord, the cone and the dust), the far room (introRoom), the level (introScene: the scene's opacity over the
   home's #09090a). The wordmark dims, lands large in the middle with a spring and a sheen, glides home, then the cards
   rise. Built off the main thread while the first frame (the wordmark alone) holds; a tap skips it (a 200 ms glide);
   Reduce Motion: the cards fade in under the wordmark. Silent, as on the phone's web page (its audio is never running
   before a touch). Settings > Graphics > Opening Animation turns it off. */
import FeltRender
import FeltSim
import SwiftUI

enum IntroArt {
  /* the timeline (ms from the start) */
  static let hold = 120.0, dim = 340.0, lamp = 180.0, lampMs = 600.0, pan = 330.0, panMs = 520.0, hero = 380.0, land = 3480.0
  static let sheen = 3580.0, sheenMs = 380.0, out = 3980.0, glide = 440.0, outMs = 550.0, skipMs = 200.0, FLASH_MS = 200.0
  static let END = out + outMs, PREP_MAX = 3000.0, LAMP_H = 1.0, SHADES = [0.74], RIM_R = 0.15, SHADE_H = 0.19
  static let POCKET_KINDS = ["8", "9", "10", "straight", "rotation", "heyball"]

  static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }
  static func ease(_ a: Double, _ b: Double, _ u: Double) -> Double { let t = clamp((u - a) / (b - a), 0, 1); return t * t * (3 - 2 * t) }
  static let easeIO3 = HeroArt.easeIO
  static func hash(_ i: Int, _ n: Double) -> Double { let v = (sin(Double(i + 1) * n) * 43758.5453).truncatingRemainder(dividingBy: 1); return (v + 1).truncatingRemainder(dividingBy: 1) }

  /* introKind, introArgs: the last game played if a pocket game (its table and pockets), else 8-ball on the 9 ft table */
  static func game() -> (kind: String, spec: (table: String, shape: String?, pockets: String)) {
    if let g = TableGame.allCases.first(where: { $0.table.2 == Prefs.last }), POCKET_KINDS.contains(Prefs.last) { return (Prefs.last, TableModel.spec(for: g)) }
    return ("8", ("9", Prefs.bumperTable, "regulation"))
  }
  static func clock(_ run: HeroRun) -> (sim: (Double) -> Double, ms: (Double) -> Double) {
    let end = Double(run.pos.count - 1) * Double(HERO_SUB) * SIM_DT
    return ({ ms in clamp(ms / 1000, 0, end) }, { s in s * 1000 })
  }
  static func cueGap(_ t: Double) -> (Double, Double)? {
    let T = HeroArt.CUE_MS, back = 0.24
    if t < 60 { return (0.025, 1) }
    if t < 410 { return (0.025 + (back - 0.025) * (0.5 - 0.5 * cos(Double.pi * (t - 60) / 350)), 1) }
    if t < T - 62 { return (back, 1) }
    if t < T { let u = (t - (T - 62)) / 62; return (back * (1 - u * u), 1) }
    let u = (t - T) / 170
    if u >= 2.6 { return nil }
    return (-0.17 * (1 - pow(1 - min(1, u), 2)), 1 - ease(1, 2.6, u))
  }
  typealias Cam = HeroArt.Cam
  static func proj(_ C: Cam, _ x: Double, _ y: Double, _ z: Double) -> [Double] { HeroArt.proj(C, x, y, z) }
  /* introCams: low behind the shot, then high */
  static func cams(_ d: HeroArt.Data, _ W: Double, _ H: Double) -> [Cam] {
    let g = d.geo, L = g.TL, side = W > H, b = d.balls.first { $0.n == d.ball }!, a = d.angle, dx = cos(a), dy = sin(a)
    func fit(_ C0: Cam, _ pts: [[Double]], _ box: (x: Double, y: Double, w: Double, h: Double)) -> Cam {
      var C = C0, x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
      for p in pts { let q = proj(C, p[0], p[1], p[2]); x0 = min(x0, q[0]); x1 = max(x1, q[0]); y0 = min(y0, q[1]); y1 = max(y1, q[1]) }
      let F = min(box.w / (x1 - x0), box.h / (y1 - y0))
      C.F = F; C.cx = box.x + box.w / 2 - F * (x0 + x1) / 2; C.cy = box.y + box.h / 2 - F * (y0 + y1) / 2
      return C
    }
    let back = side ? 1.7 : 1.3, E0 = [b.x - dx * back - dy * 0.14, b.y - dy * back + dx * 0.14, side ? 0.55 : 0.5]
    let rack = d.balls.filter { $0 !== b }
    let rc = [rack.reduce(0) { $0 + $1.x } / Double(rack.count), rack.reduce(0) { $0 + $1.y } / Double(rack.count)]
    var C0 = HeroArt.cam(E0, [rc[0], rc[1] + (b.y - rc[1]) * 0.3, 0], 0.025)
    do {
      let ps = rack.map { proj(C0, $0.x, $0.y, g.R) }, cb = proj(C0, b.x, b.y, g.R), rx0 = ps.map { $0[0] }.min()!, rx1 = ps.map { $0[0] }.max()!
      let ry = ps.reduce(0) { $0 + $1[1] } / Double(ps.count), rxm = (rx0 + rx1) / 2
      let F = min((side ? 0.24 : 0.36) * W / (rx1 - rx0), (side ? 0.46 : 0.4) * H / max(1e-6, cb[1] - ry))
      C0.F = F; C0.cx = W * 0.54 - F * (rxm * 0.75 + cb[0] * 0.25); C0.cy = H * (side ? 0.3 : 0.38) - F * ry
    }
    let C1 = side ? HeroArt.cam([L * 0.5 + 0.2, -1.05, 2.5], [L * 0.5, g.TW * 0.54, 0], 0) : HeroArt.cam([0.04 * L, g.TW / 2 + 0.12, 2.75], [L * 0.56, g.TW / 2, 0], 0)
    let box = side ? (x: W * 0.12, y: H * 0.08, w: W * 0.76, h: H * 0.86) : (x: W * 0.04, y: H * 0.13, w: W * 0.92, h: H * 0.8)
    return [C0, fit(C1, g.outline.map { [$0[0], $0[1], g.h] }, box)]
  }
  /* introRoom: the far room on the low camera, under the table */
  static func room(_ x: Canvas2D, _ C: Cam, _ g: HeroArt.Geo, _ W: Double, _ H: Double) {
    let yf = proj(C, g.TL + g.rail, g.TW / 2, g.h)[1]
    if yf <= 0 { return }
    var gr = x.createLinearGradient(0, 0, 0, yf)
    gr.addColorStop(0, "rgba(4,4,5,0.9)"); gr.addColorStop(0.55, "rgba(10,9,9,0.4)"); gr.addColorStop(1, "rgba(26,21,17,0.0)")
    x.fillStyle = .gradient(gr); x.fillRect(0, 0, W, yf)
    let by = yf * 0.62, bh = yf * 0.2
    gr = x.createLinearGradient(0, by - bh, 0, by + bh)
    gr.addColorStop(0, "rgba(255,170,90,0)"); gr.addColorStop(0.5, "rgba(255,170,90,0.07)"); gr.addColorStop(1, "rgba(255,170,90,0)")
    x.fillStyle = .gradient(gr); x.fillRect(0, by - bh, W, 2 * bh)
    let cols = ["255,176,96", "255,214,160", "255,196,128", "140,196,190", "255,128,96"]
    x.cg.setBlendMode(.plusLighter)
    for i in 0..<16 {
      let r = min(W, H) * (0.018 + 0.05 * hash(i, 7.31)), cx = W * hash(i, 12.9898), cy = yf * (0.3 + 0.6 * hash(i, 78.233)), a = 0.025 + 0.06 * hash(i, 3.77) * (cy / yf)
      let c = cols[Int((hash(i, 51.7) * Double(cols.count)).rounded(.down))]
      gr = x.createRadialGradient(cx, cy, 0, cx, cy, r)
      gr.addColorStop(0, "rgba(\(c),\(a * 0.8))"); gr.addColorStop(0.7, "rgba(\(c),\(a))"); gr.addColorStop(0.88, "rgba(\(c),\(a * 1.12))"); gr.addColorStop(1, "rgba(\(c),0)")
      x.fillStyle = .gradient(gr); x.beginPath(); x.arc(cx, cy, r, 0, 2 * Double.pi); x.fill()
    }
    x.cg.setBlendMode(.normal)
    gr = x.createLinearGradient(0, yf * 0.9, 0, yf)
    gr.addColorStop(0, "rgba(0,0,0,0)"); gr.addColorStop(1, "rgba(0,0,0,0.35)")
    x.fillStyle = .gradient(gr); x.fillRect(0, yf * 0.9, W, yf * 0.1)
  }
  /* introPool: the pool's dark, as projected */
  static func pool(_ C: Cam, _ g: HeroArt.Geo, _ x: Canvas2D, _ k: Double = 1) {
    var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
    for i in 0..<32 { let a = Double(i) / 32 * 2 * Double.pi, p = proj(C, g.TL / 2 + 1.25 * cos(a), g.TW / 2 + 0.8 * sin(a), 0); x0 = min(x0, p[0]); x1 = max(x1, p[0]); y0 = min(y0, p[1]); y1 = max(y1, p[1]) }
    let ex = (x0 + x1) / 2, ey = (y0 + y1) / 2, rx = (x1 - x0) / 2, ry = (y1 - y0) / 2
    x.save()
    x.setTransform(rx * 1.12, 0, 0, ry * 1.12, ex, ey)
    let gr = x.createRadialGradient(0, 0, 0, 0, 0, 1)
    gr.addColorStop(0, "rgba(9,9,10,0)"); gr.addColorStop(0.5, "rgba(9,9,10,\(0.04 * k))"); gr.addColorStop(0.82, "rgba(9,9,10,\(0.36 * k))"); gr.addColorStop(1, "rgba(9,9,10,\(0.66 * k))")
    x.fillStyle = .gradient(gr); x.fillRect(-60, -60, 120, 120)
    x.restore()
  }
  struct Light { var pad = 0.0, dPool = [0.0, 0], dFix = [0.0, 0], fix: CGImage? = nil, cone = false, dot: CGImage? = nil, dr = 0.0, ap = [0.0, 0], rim = 0.0, len = 0.0, hw = 0.0, ang = 0.0 }
  /* introLight on the still's canvas x (camera i): the pool baked in; on the low camera the cones and blooms baked in
     too, the fixture and the dust apart */
  static func light(_ d: HeroArt.Data, _ x: Canvas2D, _ C: Cam, _ i: Int, _ W: Double, _ H: Double) -> Light {
    let g = d.geo
    if i == 1 { pool(C, g, x, 0.62); return Light() }
    func per(_ px: Double, _ py: Double, _ pz: Double) -> [Double] { let a = proj(C, px, py, pz), b = proj(C, px, py + 0.1, pz); return [(b[0] - a[0]) * 10, (b[1] - a[1]) * 10] }
    var L = Light()
    L.dPool = per(g.TL / 2, g.TW / 2, 0); L.dFix = per(g.TL * 0.78, g.TW / 2, LAMP_H)
    L.pad = (0.08 * max(JSMath.hypot(L.dPool[0], L.dPool[1]), JSMath.hypot(L.dFix[0], L.dFix[1]))).rounded(.up) + 4
    pool(C, g, x)
    struct Shade { let rim, top: [Double], R, Rt, e: Double, bed: [Double], bw: Double }
    var shades: [Shade] = []
    for fx in SHADES {
      let cx = g.TL * fx, cy = g.TW / 2, rim = proj(C, cx, cy, LAMP_H), top = proj(C, cx, cy, LAMP_H + SHADE_H)
      if rim[2] < 0.3 { continue }
      let R = C.F * RIM_R / rim[2], el = abs(atan2(LAMP_H - C.E[2], JSMath.hypot(cx - C.E[0], cy - C.E[1])))
      if rim[0] < -2 * R || rim[0] > W + 2 * R || rim[1] < -R || rim[1] > H { continue }
      let bed = proj(C, cx, cy, 0)
      shades.append(Shade(rim: rim, top: top, R: R, Rt: C.F * 0.05 / top[2], e: max(0.08, sin(el)), bed: bed, bw: C.F * 0.55 / bed[2]))
    }
    if shades.isEmpty { return L }
    let pad = L.pad, f = Canvas2D(width: Int(W + 2 * pad), height: Int(H + 2 * pad))
    f.translate(pad, pad)
    var gr: Gradient2D
    for s in shades.sorted(by: { $0.rim[2] > $1.rim[2] }) {
      let rim = s.rim, top = s.top, R = s.R, Rt = s.Rt, e = s.e, ry = R * e
      f.fillStyle("#0c0b0a"); f.fillRect(top[0] - max(1, Rt * 0.12), -pad, max(2, Rt * 0.24), top[1] + pad)
      f.fillStyle("#17150f"); f.fillRect(top[0] - Rt * 0.3, top[1] - Rt * 0.9, Rt * 0.6, Rt * 0.9)
      gr = f.createLinearGradient(rim[0] - R, 0, rim[0] + R, 0)
      gr.addColorStop(0, "#07100b"); gr.addColorStop(0.28, "#183a28"); gr.addColorStop(0.4, "#4f7a62"); gr.addColorStop(0.47, "#1e4430"); gr.addColorStop(0.8, "#0c1f15"); gr.addColorStop(1, "#040806")
      f.fillStyle = .gradient(gr)
      f.beginPath(); f.moveTo(top[0] - Rt, top[1]); f.bezierCurveTo(top[0] - Rt * 1.6, top[1] + (rim[1] - top[1]) * 0.55, rim[0] - R * 0.98, rim[1] - (rim[1] - top[1]) * 0.25, rim[0] - R, rim[1])
      f.ellipse(rim[0], rim[1], R, ry, Double.pi, 0, true)
      f.bezierCurveTo(rim[0] + R * 0.98, rim[1] - (rim[1] - top[1]) * 0.25, top[0] + Rt * 1.6, top[1] + (rim[1] - top[1]) * 0.55, top[0] + Rt, top[1])
      f.closePath(); f.fill()
      gr = f.createLinearGradient(top[0] - Rt, 0, top[0] + Rt, 0)
      gr.addColorStop(0, "#5a4420"); gr.addColorStop(0.4, "#e6c47c"); gr.addColorStop(1, "#6b5126")
      f.fillStyle = .gradient(gr); f.beginPath(); f.ellipse(top[0], top[1], Rt, max(1, Rt * e), 0, Double.pi * 2); f.fill()
      gr = f.createRadialGradient(rim[0], rim[1] - ry * 0.15, 0, rim[0], rim[1], R)
      gr.addColorStop(0, "rgba(255,250,236,1)"); gr.addColorStop(0.22, "rgba(255,240,210,1)"); gr.addColorStop(0.7, "rgba(242,214,166,1)"); gr.addColorStop(1, "rgba(176,138,88,1)")
      f.fillStyle = .gradient(gr); f.beginPath(); f.ellipse(rim[0], rim[1], R * 0.97, ry * 0.97, 0, Double.pi * 2); f.fill()
      gr = f.createLinearGradient(rim[0] - R, 0, rim[0] + R, 0)
      gr.addColorStop(0, "#6d5226"); gr.addColorStop(0.3, "#f3dc9e"); gr.addColorStop(0.5, "#b88f45"); gr.addColorStop(0.75, "#fff0c4"); gr.addColorStop(1, "#5c4520")
      f.strokeStyle = .gradient(gr); f.lineWidth = max(1.2, R * 0.075); f.beginPath(); f.ellipse(rim[0], rim[1], R, ry, 0, Double.pi * 2); f.stroke()
    }
    L.fix = f.image()
    /* the cones and the blooms, into the still */
    x.save()
    x.cg.setBlendMode(.plusLighter)
    for s in shades {
      let rim = s.rim, R = s.R, bed = s.bed, bw = s.bw, len = JSMath.hypot(bed[0] - rim[0], bed[1] - rim[1]), ang = atan2(bed[1] - rim[1], bed[0] - rim[0])
      x.save(); x.translate(rim[0], rim[1]); x.rotate(ang)
      for k in 0..<9 {
        let fk = 1 - Double(k) / 9, lg = x.createLinearGradient(0, 0, len, 0)
        lg.addColorStop(0, "rgba(255,230,186,0.024)"); lg.addColorStop(0.5, "rgba(255,230,186,0.012)"); lg.addColorStop(1, "rgba(255,230,186,0.004)")
        x.fillStyle = .gradient(lg); x.beginPath(); x.moveTo(0, -R * 0.95 * fk); x.lineTo(len, -bw * fk); x.lineTo(len, bw * fk); x.lineTo(0, R * 0.95 * fk); x.closePath(); x.fill()
      }
      x.restore()
      let bl = x.createRadialGradient(rim[0], rim[1], R * 0.4, rim[0], rim[1], R * 2.6)
      bl.addColorStop(0, "rgba(255,226,170,0.16)"); bl.addColorStop(1, "rgba(255,226,170,0)")
      x.fillStyle = .gradient(bl); x.fillRect(rim[0] - R * 2.6, rim[1] - R * 2.6, R * 5.2, R * 5.2)
    }
    x.cg.setBlendMode(.normal)
    x.restore()
    L.cone = true
    /* the dust: in the cone nearest the frame's middle */
    let s = shades.reduce(shades[0]) { abs($1.rim[0] - W / 2) < abs($0.rim[0] - W / 2) ? $1 : $0 }
    let dr = max(2, (W / 300).rounded()), dc = Canvas2D(width: Int(dr * 4), height: Int(dr * 4))
    let dg = dc.createRadialGradient(dr * 2, dr * 2, 0, dr * 2, dr * 2, dr * 2)
    dg.addColorStop(0, "rgba(255,240,215,0.9)"); dg.addColorStop(0.4, "rgba(255,240,215,0.35)"); dg.addColorStop(1, "rgba(255,240,215,0)")
    dc.fillStyle = .gradient(dg); dc.fillRect(0, 0, dr * 4, dr * 4)
    L.dot = dc.image(); L.dr = dr; L.ap = s.rim; L.rim = s.R
    L.len = JSMath.hypot(s.bed[0] - s.rim[0], s.bed[1] - s.rim[1]); L.hw = s.bw; L.ang = atan2(s.bed[1] - s.rim[1], s.bed[0] - s.rim[0])
    return L
  }
  /* introHalo: the title's ground */
  static func halo(_ w: Double, _ h: Double) -> CGImage {
    let c = Canvas2D(width: max(2, Int(w.rounded(.up))), height: max(2, Int(h.rounded(.up))))
    c.setTransform(Double(c.width) / 2, 0, 0, Double(c.height) / 2, Double(c.width) / 2, Double(c.height) / 2)
    let gr = c.createRadialGradient(0, 0, 0, 0, 0, 1)
    gr.addColorStop(0, "rgba(9,9,10,0.82)"); gr.addColorStop(0.55, "rgba(9,9,10,0.5)"); gr.addColorStop(1, "rgba(9,9,10,0)")
    c.fillStyle = .gradient(gr); c.fillRect(-1, -1, 2, 2)
    return c.image()
  }
  static func lampK(_ t: Double) -> Double {
    let u = t - lamp
    if u <= 0 { return 0 }
    if u < 50 { return 0.5 * u / 50 }
    if u < 100 { return 0.12 }
    if u < 160 { return 0.72 }
    if u < 210 { return 0.3 }
    return 0.3 + 0.7 * ease(210, lampMs, u)
  }
  static func swing(_ t: Double) -> Double { let u = max(0, t - lamp) / 1000; return 0.03 * exp(-u / 1.2) * cos(2 * Double.pi * u / 1.9 + 0.3) }
  static func cards(_ t: Double) -> Double { easeIO3(clamp((t - out - glide + 180) / (outMs - glide + 180), 0, 1)) }
  static func scene(_ t: Double) -> Double { t < lamp ? 1 : lampK(t) * (1 - 0.4 * ease(land - 150, land + 450, t)) * (1 - ease(0, 1, (t - out) / glide)) }
}

/* what the build makes, handed to the main thread once */
final class IntroBuilt: @unchecked Sendable {
  var d: HeroArt.Data! = nil, run: HeroRun! = nil, arts: [HeroArt.Art] = [], lights: [IntroArt.Light] = [], focus: [[Double]] = []
  var flash: CGImage! = nil, bp: BallPainter! = nil, dress = Dress.standard, lift = 0.0, cy0 = 0.0
  var cut = 0.0, hitT = 0.0, hitAt: [Double]? = nil, simAt: ((Double) -> Double)! = nil, potAt: ((Double) -> Double)! = nil
  var motes: [[Double]] = [], W = 0, H = 0
}

@MainActor @Observable final class IntroModel {
  enum State { case off, prep, play, out, fade, done }
  var state: State = .off
  var frame: CGImage? = nil
  /* the wordmark's pose (pt: translate, scale, opacity, the sheen's place %), the cards, the scene's opacity, the camera's move */
  var pose: [Double] = [0, 0, 1, 1, 100]
  var ik = 0.0
  var cv = 1.0
  var cam: [Double] = [1, 50, 50, 0, 0]
  var sheenOn = false
  @ObservationIgnored var b: IntroBuilt? = nil
  @ObservationIgnored var t0 = 0.0
  @ObservationIgnored var skip: (t0: Double, t1: Double, from: [Double], ik: Double, cv: Double)? = nil
  @ObservationIgnored var mid = (tx: 0.0, ty: 0.0, s: 1.0, drop: 0.0, cx: 0.0, cy: 0.0)
  @ObservationIgnored var halo: CGImage? = nil
  @ObservationIgnored var dp = 3.0
  @ObservationIgnored var prepT0 = 0.0
  /* decided at launch, before anything is drawn: off in Settings, or a test hook (any -felt- argument but -felt-intro) */
  init() {
    let a = ProcessInfo.processInfo.arguments
    if !Prefs.intro || a.contains(where: { $0.hasPrefix("-felt-") && $0 != "-felt-intro" }) { state = .done; ik = 1 }
  }
  /* introBoot: on a cold launch at home, unless it is off, Reduce Motion (the fade) or a test asks for none */
  func boot(size: CGSize, title: CGRect, insets: EdgeInsets, scale: Double) {
    guard state == .off else { return }
    if UIAccessibility.isReduceMotionEnabled { state = .fade; withAnimation(.easeOut(duration: 0.24)) { ik = 1 } completion: { self.state = .done }; return }
    state = .prep; prepT0 = CACurrentMediaTime(); ik = 0; cv = 0; pose = [0, 0, 1, 1, 100]
    let dp = min(3, scale), W = Int((size.width * dp).rounded()), H = Int((size.height * dp).rounded())
    self.dp = dp
    /* the wordmark: where it lands, large, in the middle of the safe area */
    let vw = size.width, vh = size.height, sat = insets.top, sab = insets.bottom
    let s = min(2.6, vw * 0.5 / title.width, (vh - sat - sab) * 0.16 / title.height), cy = sat + (vh - sat - sab) * (W > H ? 0.5 : 0.47)
    mid = (vw / 2 - title.midX, cy - title.midY, s, title.height * s * 0.5, vw / 2, cy)
    let hw = title.width * s * 2.3 * dp, hh = title.height * s * 2.6 * dp
    let (kind, spec) = IntroArt.game(), dress = Prefs.dress(kind)
    Task.detached(priority: .userInitiated) {
      let B = IntroModel.build(kind: kind, spec: spec, dress: dress, W: W, H: H, dp: dp)
      let hl = IntroArt.halo(hw, hh)
      await MainActor.run {
        guard self.state == .prep else { return }
        /* a slow device: the home rather than a long hold on the first frame */
        if (CACurrentMediaTime() - self.prepT0) * 1000 > 2.5 * IntroArt.PREP_MAX { self.finish(); return }
        self.b = B; self.halo = hl
        self.state = .play; self.t0 = CACurrentMediaTime()
        self.tick()
      }
    }
  }
  nonisolated static func build(kind: String, spec: (table: String, shape: String?, pockets: String), dress: Dress, W: Int, H: Int, dp: Double) -> IntroBuilt {
    let B = IntroBuilt(), d = HeroArt.prep(kind, spec), Wd = Double(W), Hd = Double(H)
    B.d = d; B.dress = dress; B.W = W; B.H = H
    var cams = IntroArt.cams(d, Wd, Hd)
    /* the low camera's still runs on above the frame to take in the lamp over the rack */
    let C0 = cams[0], g0 = d.geo, top = IntroArt.proj(C0, g0.TL * IntroArt.SHADES[0], g0.TW / 2, IntroArt.LAMP_H + IntroArt.SHADE_H + 0.06)[1]
    let X = IntroArt.clamp(Hd * 0.14 - top, 0, Hd * 1.4).rounded(), Hc = Hd + X
    cams[0].cy += X
    B.lift = X
    for i in 0..<2 {
      var L = IntroArt.Light()
      let room: ((Canvas2D, HeroArt.Cam, HeroArt.Geo, Double, Double) -> Void)? = i == 0 ? { x, C, g, w, h in IntroArt.room(x, C, g, w, h) } : nil
      let hh = i == 1 ? Hd : Hc
      let post: (Canvas2D, HeroArt.Cam) -> Void = { x, C in L = IntroArt.light(d, x, C, i, Wd, hh) }
      var A = HeroArt.still(d, W, Int(hh), txt: 0, dress: dress, vignette: false, cam: cams[i], room: room, post: post)
      if i == 0 { B.cy0 = A.C.cy; A.pan = 0 }
      let fp = i == 1 ? IntroArt.proj(A.C, d.geo.TL * 0.55, d.geo.TW / 2, 0) : IntroArt.proj(A.C, d.balls[1].x, d.balls[1].y, 0)
      B.focus.append([IntroArt.clamp(fp[0] / Wd * 100, 20, 80), IntroArt.clamp((fp[1] - (i == 1 ? 0 : X)) / Hd * 100, 20, 80)])
      B.arts.append(A); B.lights.append(L)
    }
    let fl = Canvas2D(width: 128, height: 128), fg2 = fl.createRadialGradient(64, 64, 0, 64, 64, 64)
    fg2.addColorStop(0, "rgba(255,252,240,0.95)"); fg2.addColorStop(0.18, "rgba(255,236,200,0.55)"); fg2.addColorStop(0.5, "rgba(255,214,160,0.12)"); fg2.addColorStop(1, "rgba(255,214,160,0)")
    fl.fillStyle = .gradient(fg2); fl.fillRect(0, 0, 128, 128)
    B.flash = fl.image()
    let run = HeroArt.run(d)
    B.run = run
    /* the cut: the cue ball meets the rack */
    let j = run.tab.hits.firstIndex { $0.kind == "ball" }
    let k = j.map { j in run.hitN.firstIndex { $0 > j } ?? 0 } ?? 0
    let tc = j == nil ? 0.25 : Double(k) * Double(HERO_SUB) * SIM_DT, clk = IntroArt.clock(run)
    B.simAt = { t in clk.sim(t - HeroArt.CUE_MS) }
    B.potAt = { pt in HeroArt.CUE_MS + clk.ms(pt) }
    B.hitT = HeroArt.CUE_MS + clk.ms(tc)
    B.cut = B.hitT + 50
    let ci = d.balls.firstIndex { $0.n == d.ball }!
    B.hitAt = j == nil ? nil : [run.pos[k][2 * ci], run.pos[k][2 * ci + 1]]
    let look = TableLook.of(dress), cloth = RGBA(css: look.cloth.base)
    B.bp = BallPainter(set: BallSet.all[dress.balls] ?? BallSet.all["classic"]!, bounce: look.cloth.bounce, dpr: dp, portrait: false,
                       lowRim: look.cloth.lowRim, rimAll: look.cloth.rim, clothBase: [cloth.r * 255, cloth.g * 255, cloth.b * 255])
    B.motes = (0..<42).map { i in [0.08 + 0.88 * IntroArt.hash(i, 12.9898), IntroArt.hash(i, 78.233) * 2 - 1, IntroArt.hash(i, 39.425) * 6.283, 0.35 + 0.65 * IntroArt.hash(i, 93.989), 0.6 + 0.8 * IntroArt.hash(i, 17.17)] }
    return B
  }
  /* introPose */
  func poseAt(_ t: Double) -> [Double] {
    let M = mid
    if t < IntroArt.hold { return [0, 0, 1, 1, 100] }
    if t < IntroArt.hold + IntroArt.dim { let e = IntroArt.ease(0, 1, (t - IntroArt.hold) / IntroArt.dim); return [0, 0, 1 - 0.035 * e, 1 - e, 100] }
    if t < IntroArt.land { return [0, 0, 0.965, 0, 100] }
    let sx = 100 * (1 - IntroArt.easeIO3(IntroArt.clamp((t - IntroArt.sheen) / IntroArt.sheenMs, 0, 1)))
    if t < IntroArt.out {
      let s = (t - IntroArt.land) / 1000, k = 1 - exp(-7.5 * s) * (cos(10.5 * s) + 0.71 * sin(10.5 * s))
      return [M.tx, M.ty - M.drop * (1 - k), M.s * (1.12 - 0.12 * k), IntroArt.clamp((t - IntroArt.land) / 170, 0, 1), sx]
    }
    let e = IntroArt.easeIO3(IntroArt.clamp((t - IntroArt.out) / IntroArt.glide, 0, 1))
    return [M.tx * (1 - e), M.ty * (1 - e), M.s + (1 - M.s) * e, 1, sx]
  }
  /* introCamMove */
  func camAt(_ t: Double) -> [Double] {
    guard let B = b, t >= IntroArt.lamp else { return [1, 50, 50, 0, 0] }
    let hT = max(0, t - IntroArt.hero), f = B.focus[hT >= B.cut ? 1 : 0], q = (hT - B.cut) / 1000, sh = q >= 0 && q < 0.26 ? 2.6 * exp(-q / 0.07) : 0
    let dx = sh * sin(q * 2 * Double.pi * 23), dy = sh * 0.6 * sin(q * 2 * Double.pi * 31 + 1.3)
    if hT < B.cut { return [1 + 0.05 * IntroArt.ease(IntroArt.pan, IntroArt.hero + 900, t), f[0], f[1], 0, 0] }
    return [1.004 + 0.12 * (1 - HeroArt.easeIO(IntroArt.clamp((hT - B.cut) / (IntroArt.land - IntroArt.hero - B.cut), 0, 1))), f[0], f[1], dx, dy]
  }
  func tick() {
    guard state == .play || state == .out else { return }
    let t = (CACurrentMediaTime() - t0) * 1000
    if let S = skip { if t >= S.t1 { finish(); return } } else if t >= IntroArt.END { finish(); return }
    frameAt(t)
  }
  func frameAt(_ t: Double) {
    draw(t)
    var p = poseAt(t), k = IntroArt.cards(t), c = IntroArt.scene(t)
    if let S = skip {
      let e = IntroArt.easeIO3(IntroArt.clamp((t - S.t0) / (S.t1 - S.t0), 0, 1)), f = S.from
      p = [f[0] * (1 - e), f[1] * (1 - e), f[2] + (1 - f[2]) * e, f[3] + (1 - f[3]) * e, f[4] * (1 - e)]
      k = S.ik + (1 - S.ik) * e; c = S.cv * (1 - e)
    }
    sheenOn = skip != nil ? sheenOn && p[4] > 0.5 : t >= IntroArt.land - 40 && t < IntroArt.sheen + IntroArt.sheenMs
    pose = p; ik = k >= 0.995 ? 1 : k; cv = c
    cam = camAt(skip.map { $0.t0 + (t - $0.t0) * 0.3 } ?? t)
  }
  /* introDraw: the scene into a fresh frame */
  func draw(_ t: Double) {
    guard let B = b else { return }
    if t < IntroArt.lamp { frame = nil; return }
    let W = B.W, H = B.H, x = Canvas2D(width: W, height: H)
    let hT = max(0, t - IntroArt.hero), i = hT >= B.cut ? 1 : 0, L = B.lights[i], sw = IntroArt.swing(t)
    var A = B.arts[i]
    var pan = 0.0
    if A.pan != nil { pan = (B.lift * IntroArt.easeIO3(IntroArt.clamp((t - IntroArt.pan) / IntroArt.panMs, 0, 1))).rounded(); A.pan = pan; A.C.cy = B.cy0 - pan }
    HeroArt.draw(hT, B.d, B.run, A, x, bp: B.bp, dress: B.dress, opt: HeroArt.Opt(flat: true, cueOff: i == 1, simAt: B.simAt, potAt: B.potAt, cueGap: IntroArt.cueGap))
    x.setTransform(1, 0, 0, 1, 0, 0)
    if L.cone, let dot = L.dot, let fix = L.fix {
      let px = (L.dPool[0] * sw).rounded(), py = (L.dPool[1] * sw).rounded() - pan
      x.cg.setBlendMode(.plusLighter)
      let dr = L.dr * 4, u0 = t / 1000, ca = cos(L.ang), sa = sin(L.ang)
      for m in B.motes {
        let u = (m[0] + 0.012 * sin(u0 * 0.7 * m[4] + m[2])).truncatingRemainder(dividingBy: 1), w = L.rim + (L.hw - L.rim) * u, v = (m[1] + 0.05 * sin(u0 * 1.1 * m[4] + m[2] * 2)) * w * 0.8, U = u * L.len
        let tw = 0.5 + 0.5 * sin(u0 * 2.3 * m[4] + m[2])
        x.globalAlpha = m[3] * (0.25 + 0.75 * tw) * (1 - u * 0.6)
        x.drawImage(dot, L.ap[0] + U * ca - v * sa - dr / 2 + px, L.ap[1] + U * sa + v * ca - dr / 2 + py, dr, dr)
      }
      x.cg.setBlendMode(.normal)
      x.globalAlpha = 1
      x.drawImage(fix, (L.dFix[0] * sw).rounded() - L.pad, (L.dFix[1] * sw).rounded() - L.pad - pan, Double(fix.width), Double(fix.height))
    }
    /* the break's crack */
    let u = (hT - B.hitT) / IntroArt.FLASH_MS, g = B.d.geo
    if u >= 0 && u < 1, let at = B.hitAt {
      let p = IntroArt.proj(A.C, at[0], at[1], g.R), r = A.C.F * g.R / p[2], s = r * (2.2 + 3.5 * u)
      let sq = IntroArt.clamp(A.C.E[2] / JSMath.hypot(A.C.E[0] - at[0], A.C.E[1] - at[1], A.C.E[2]), 0.15, 1)
      x.cg.setBlendMode(.plusLighter)
      x.globalAlpha = (1 - u) * (1 - u)
      x.drawImage(B.flash, p[0] - s, p[1] - s, 2 * s, 2 * s)
      x.globalAlpha = 0.35 * (1 - u)
      x.strokeStyle("#fff1d6"); x.lineWidth = max(1, r * 0.08 * (1 - u))
      x.beginPath(); x.ellipse(p[0], p[1] + r * 0.5, r * (1.4 + 4 * u), r * (1.4 + 4 * u) * sq, 0, Double.pi * 2); x.stroke()
      x.cg.setBlendMode(.normal)
      x.globalAlpha = 1
    }
    /* the title's ground, where the wordmark lands */
    let hk = IntroArt.ease(IntroArt.land - 100, IntroArt.land + 300, t)
    if hk > 0, let hl = halo {
      let cw = Double(W) / dp, ch = Double(H) / dp, c = camAt(t), k = c[0], fx = c[1], fy = c[2]
      let cx = fx / 100 * cw + (mid.cx - fx / 100 * cw) / k, cy = fy / 100 * ch + (mid.cy - fy / 100 * ch) / k
      x.globalAlpha = 0.75 * hk
      x.drawImage(hl, (cx * dp - Double(hl.width) / 2).rounded(), (cy * dp - Double(hl.height) / 2).rounded(), Double(hl.width), Double(hl.height))
      x.globalAlpha = 1
    }
    frame = x.image()
  }
  /* introSkip: a short glide home (before the scene is built: home at once) */
  func skipNow() {
    if state == .prep { finish(); return }
    guard state == .play else { return }
    let t = (CACurrentMediaTime() - t0) * 1000
    skip = (t, t + IntroArt.skipMs, poseAt(t), ik, cv)
    state = .out
  }
  func finish() { state = .done; frame = nil; b = nil; halo = nil; ik = 1; cv = 0; pose = [0, 0, 1, 1, 100]; sheenOn = false }
}

/* the wordmark: "felt" in Large Title weight, the red point (.brand h1: 34 px, 700, -0.02em) */
struct Wordmark: View {
  var sheen: Double? = nil
  var body: some View {
    let t = Text("felt").foregroundStyle(.white) + Text(".").foregroundStyle(Color(rgb: 0xe8, 0x48, 0x3a))
    t.font(.system(size: 34, weight: .bold)).kerning(-0.68)
      .overlay {
        if let sx = sheen {
          /* the sheen across the word (the page's 300% gradient at background-position sx) */
          GeometryReader { g in
            LinearGradient(stops: [.init(color: Color(rgb: 0xf5, 0xf5, 0xf7), location: 0.41), .init(color: .white, location: 0.46), .init(color: Color(rgb: 0xff, 0xf1, 0xd6), location: 0.5),
                                   .init(color: .white, location: 0.54), .init(color: Color(rgb: 0xb9, 0xb9, 0xbe), location: 0.59)], startPoint: .leading, endPoint: .trailing)
              .frame(width: g.size.width * 3).offset(x: -g.size.width * 2 * sx / 100)
          }
          .mask(Text("felt").font(.system(size: 34, weight: .bold)).kerning(-0.68).frame(maxWidth: .infinity, alignment: .leading))
          .allowsHitTesting(false)
        }
      }
  }
}

/* the opening over the home: the room's colour hiding the cards until they rise, the scene, the wordmark */
struct IntroOverlay: View {
  @Bindable var model: IntroModel
  let title: CGRect
  var body: some View {
    TimelineView(.animation(paused: !(model.state == .play || model.state == .out))) { tl in
      ZStack(alignment: .topLeading) {
        Color(rgb: 9, 9, 10).opacity(1 - model.ik)
        if let f = model.frame {
          Image(decorative: f, scale: model.dp).resizable()
            .opacity(model.cv)
            .scaleEffect(model.cam[0], anchor: UnitPoint(x: model.cam[1] / 100, y: model.cam[2] / 100))
            .offset(x: model.cam[3], y: model.cam[4])
        }
        Wordmark(sheen: model.sheenOn ? model.pose[4] : nil)
          .fixedSize()
          .scaleEffect(model.pose[2])
          .opacity(model.pose[3])
          .position(x: title.midX + model.pose[0], y: title.midY + model.pose[1])
      }
      .onChange(of: tl.date) { _, _ in model.tick() }
    }
    .ignoresSafeArea()
    .contentShape(Rectangle())
    .onTapGesture { model.skipNow() }
    .accessibilityHidden(true)
  }
}
