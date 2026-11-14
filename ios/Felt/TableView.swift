/* The table, top down, in the web build's colours (CLOTHS, RAILS, BALL_COLOR in index.html section
   4): wood, cloth with the lamp's pool, the pocket holes, the cushion rubbers from the sim's own
   CUSHION_POLYS, the sights, the balls with their shadows, and the guide. Upright on a phone held
   upright (the head string at the foot of the screen), lengthwise on its side. */
import FeltRender
import FeltSim
import SwiftUI

struct Look {
  var cloth: Color, cushion: Color, rail: Color, railDark: Color
  /* CLOTHS[...].ovMin and .illegal: every white overlay at least ovMin opaque; the illegal colour */
  var ovMin: Double { ["8": 0.6, "9": 0.72, "10": 0.78, "heyball": 0.64, "snooker": 0.66, "carom": 0.66][game] ?? 0.6 }
  var illegal: Color { game == "8" ? Color(hex: 0xffa597) : Color(hex: 0xffe27a) }
  var game = "8"
  static func of(_ g: Game) -> Look {
    var l = base(g); l.game = g.table.2; return l
  }
  static func base(_ g: Game) -> Look {
    switch g {
    case .eight, .ten: Look(cloth: Color(hex: 0x1b5d47), cushion: Color(hex: 0x1d6450), rail: Color(hex: 0x4f2714), railDark: Color(rgb: 44, 19, 9))
    case .nine: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x100f11), railDark: Color(rgb: 6, 6, 7))
    case .heyball: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x2a1a12), railDark: Color(rgb: 16, 9, 6))
    case .snooker: Look(cloth: Color(hex: 0x1b5d47), cushion: Color(hex: 0x1d6450), rail: Color(hex: 0x7c5228), railDark: Color(rgb: 86, 52, 22))
    case .carom: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x33201a), railDark: Color(rgb: 20, 11, 8))
    }
  }
}

extension Color {
  init(hex: UInt32) { self.init(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }
  init(rgb r: Int, _ g: Int, _ b: Int) { self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

/* BALL_COLOR, SNOOKER_COLOR, CAROM_COLOR (index.html 4) */
func ballColor(_ n: Int) -> (Int, Int, Int) {
  let pool: [(Int, Int, Int)] = [(247, 244, 234), (246, 186, 28), (28, 72, 184), (208, 42, 36), (92, 46, 146), (242, 112, 26), (22, 120, 66), (122, 30, 32), (20, 20, 22)]
  if n >= 70 { return [(247, 244, 234), (244, 196, 48), (206, 34, 40)][n - 70] }
  if n >= 41 && n <= 55 { return (196, 28, 36) }
  let snk: [Int: (Int, Int, Int)] = [57: (246, 206, 40), 58: (26, 132, 72), 59: (124, 66, 34), 60: (30, 80, 196), 61: (246, 146, 176), 62: (22, 22, 24)]
  if let c = snk[n] { return c }
  return pool[n > 8 ? n - 8 : n]
}

/* table metres to screen points: the page's view (toScreen/toTable, 3), fitted as layout() fits the
   bed and its rails (RAIL from railFor), centred. Upright on a phone held upright, the head string at
   the foot of the screen. */
struct Mapper {
  let k: Double, ox: Double, oy: Double, upright: Bool, TL: Double, TW: Double, rail: Double
  init(size: CGSize, TL: Double, TW: Double) {
    self.TL = TL; self.TW = TW
    let w = Double(size.width), h = Double(size.height)
    let e = max(0, min(1, (min(w, h) - 430) / (700 - 430)))
    rail = RAIL_MIN + (RAIL_MAX - RAIL_MIN) * e * e * (3 - 2 * e)
    upright = h > w
    let L = TL + 2 * rail, W = TW + 2 * rail, (sw, sh) = upright ? (W, L) : (L, W)
    k = min(w / sw, h / sh)
    ox = (w - sw * k) / 2 + rail * k; oy = (h - sh * k) / 2 + rail * k
  }
  var view: TableView2D { TableView2D(k: k, ox: ox, oy: oy, portrait: upright) }
  func pt(_ x: Double, _ y: Double) -> CGPoint {
    upright ? CGPoint(x: ox + y * k, y: oy + (TL - x) * k) : CGPoint(x: ox + x * k, y: oy + y * k)
  }
  func table(_ p: CGPoint) -> (Double, Double) {
    upright ? (TL - (Double(p.y) - oy) / k, (Double(p.x) - ox) / k) : ((Double(p.x) - ox) / k, (Double(p.y) - oy) / k)
  }
  /* a table angle as a screen angle */
  func screenAngle(_ a: Double) -> Double { upright ? atan2(-cos(a), sin(a)) : a }
}

struct TableCanvas: View {
  let model: TableModel
  let look: Look
  @Environment(\.displayScale) private var scale

  var body: some View {
    Canvas { ctx, size in
      _ = model.frame
      let s = model.sim, m = Mapper(size: size, TL: s.TL, TW: s.TW)
      /* the last baked table, even for another size while this one bakes (never a blank frame) */
      if let img = model.tableImage {
        ctx.draw(Image(decorative: img.image, scale: img.scale), in: CGRect(origin: .zero, size: size))
      }
      /* drawCast's shadows, then the balls (4b), each composited from its own image at device px */
      let sc = Double(scale), bp = model.ballPainter(upright: m.upright, scale: scale), rb = s.BALL_R * m.k * sc
      let list = model.shown.filter { $0.on }
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
      for b in list {
        let p = m.pt(b.x, b.y)
        for (img, rect, a) in bp.castParts(b.x, b.y, Double(p.x) * sc, Double(p.y) * sc, rb, tl: s.TL, tw: s.TW, ballR: s.BALL_R, z: b.z ?? 0) {
          var c = ctx; c.opacity = a; c.draw(Image(decorative: img, scale: 1), in: rect)
        }
      }
      ctx.scaleBy(x: sc, y: sc)
      drawGuide(&ctx, m)
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
      for b in list {
        let p = m.pt(b.x, b.y), z = b.z ?? 0, air = z > 0 ? 0.6 / (0.6 - min(z, 0.3)) : 1
        let (img, x, y) = model.ballImage(bp, b.n, Double(p.x) * sc, Double(p.y) * sc, rb * air)
        ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: x, y: y, width: Double(img.width), height: Double(img.height)))
      }
      /* the cue (4f): pulled back by power while aiming, driven through during the stroke, carried a
         few centimetres on and faded as the shot starts */
      ctx.scaleBy(x: sc, y: sc)
      let rest = s.BALL_R + 0.012, back = 0.27, R = s.BALL_R, g = model.game.table.2
      if model.rolling == nil, let c = model.cue {
        var gap = rest + back * min(1, max(0, model.power))
        if let st = model.stroke {
          let u = min(1, max(0, (st.t0.map { model.now - $0 } ?? 0) / TableModel.STROKE_MS)), g0 = rest + back * min(1, max(0, st.power))
          gap = g0 + (R - g0) * u * u
        }
        drawCue(&ctx, m, game: g, cx: c.x, cy: c.y, ang: model.aim, gap: gap)
      } else if model.rolling != nil, let lc = model.lastCue, model.now - model.shotAt < 0.18 {
        let u = (model.now - model.shotAt) / 0.18, e = min(1, max(0, u * 2)), ease = e * e * (3 - 2 * e)
        drawCue(&ctx, m, game: g, cx: lc.x, cy: lc.y, ang: lc.ang, gap: R - 0.035 * ease, alpha: 1 - u)
      }
    }
  }

  /* 4d's guideLines in CSS points: the aim line to the ghost ball (pure geometry), then the preview's
     paths, the object ball's solid line and the cue ball's dashed one, each over a faint dark
     under-stroke so it reads on any cloth (strokeLine, guideRing). Practice has no rules: any first
     contact is legal, and only the cue ball's pot is not. */
  private func drawGuide(_ ctx: inout GraphicsContext, _ m: Mapper) {
    guard let c = model.cue, let (h, P) = model.guide() else { return }
    let s = model.sim, R = s.BALL_R, rp = R * m.k, dx = JSMath.cos(model.aim), dy = JSMath.sin(model.aim)
    let gx = c.x + dx * h.t, gy = c.y + dy * h.t, ov = look.ovMin
    let wa = { (a: Double) in Color.white.opacity(max(a, ov)) }, white = { (a: Double) in Color.white.opacity(a) }
    func path(_ pts: [[Double]]) -> Path { var p = Path(); for (i, q) in pts.enumerated() { i == 0 ? p.move(to: m.pt(q[0], q[1])) : p.addLine(to: m.pt(q[0], q[1])) }; return p }
    func strokeLine(_ pts: [[Double]], _ col: Color, _ w: Double, _ dash: [CGFloat] = []) {
      let p = path(pts)
      ctx.stroke(p, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: w + 2, lineCap: .round, lineJoin: .round, dash: dash))
      ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: dash))
    }
    func ring(_ x: Double, _ y: Double, _ r: Double, _ col: Color, _ w: Double, fill: Color? = nil) {
      let q = m.pt(x, y), p = Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
      if let f = fill { ctx.fill(p, with: .color(f)) }
      ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
    func trimStart(_ pts: [[Double]], _ d0: Double) -> [[Double]] {
      var d = d0
      for i in 1..<max(1, pts.count) {
        let a = pts[i - 1], b = pts[i], l = JSMath.hypot(b[0] - a[0], b[1] - a[1])
        if l > d { return [[a[0] + (b[0] - a[0]) * d / l, a[1] + (b[1] - a[1]) * d / l]] + pts[i...] }
        d -= l
      }
      return []
    }
    let first = P.first.flatMap { f in model.balls.first { $0.n == f } }
    let legal = model.game == .carom ? true : first != nil
    if h.t > 2 * R { strokeLine([[c.x + dx * R, c.y + dy * R], [gx - dx * R, gy - dy * R]], wa(0.5), 1.25) }
    ring(gx, gy, rp, legal ? white(0.9) : look.illegal, 1.5, fill: white(0.08))
    if let f = first, !legal { ring(f.x, f.y, rp + 3, look.illegal, 2) }
    if legal, let obj = P.obj, obj.count > 1 {
      let o = trimStart(obj, R), end = obj[obj.count - 1]
      if o.count > 1 { strokeLine(o, white(0.9), 2) }
      if P.objPot >= 0 && P.objPot < s.POCKETS.count { ring(s.POCKETS[P.objPot][0], s.POCKETS[P.objPot][1], s.POCKET_R[P.objPot] * m.k * 0.8, white(0.7), 1.5) }
      else if P.objHit { ring(end[0], end[1], rp, wa(0.35), 1.25) }
    }
    let cueCol = P.cuePot < 0 ? white(0.9) : look.illegal
    if P.cue.count > 1 {
      strokeLine(P.cue, wa(0.55), 1.5, [5, 5])
      let end = P.cue[P.cue.count - 1]
      if P.cueStop { ring(end[0], end[1], rp, wa(0.3), 1.25) }
      for q in P.bounces ?? [] { ring(q[0], q[1], 2.5, wa(0.85), 1, fill: wa(0.85)) }
      if P.cuePot >= 0 {
        var tail = Array(P.cue.reversed()), len = 0.0
        for i in 1..<tail.count { len += JSMath.hypot(tail[i][0] - tail[i - 1][0], tail[i][1] - tail[i - 1][1]) }
        var cut = [tail[0]], left = min(len, 0.1)
        for i in 1..<tail.count where left > 0 {
          let a = tail[i - 1], b = tail[i], d = JSMath.hypot(b[0] - a[0], b[1] - a[1])
          if d <= left { cut.append(b); left -= d } else { cut.append([a[0] + (b[0] - a[0]) * left / d, a[1] + (b[1] - a[1]) * left / d]); left = 0 }
        }
        tail = cut
        strokeLine(tail, cueCol, 2)
      }
    }
    if P.cuePot >= 0 && P.cuePot < s.POCKETS.count { ring(s.POCKETS[P.cuePot][0], s.POCKETS[P.cuePot][1], s.POCKET_R[P.cuePot] * m.k, cueCol, 2) }
    /* drawJumpArc: the flight lifted up the screen by its height, a dot at each landing */
    if P.air.count > 1 {
      var p = Path(), lands: [CGPoint] = []
      for (i, a) in P.air.enumerated() {
        let q = m.pt(a[0], a[1]), y = q.y - a[2] * m.k
        i == 0 ? p.move(to: CGPoint(x: q.x, y: y)) : p.addLine(to: CGPoint(x: q.x, y: y))
        if i > 0 && a[2] == 0 { lands.append(q) }
      }
      ctx.stroke(p, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round, dash: [2, 4]))
      ctx.stroke(p, with: .color(wa(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [2, 4]))
      for q in lands { ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)), with: .color(wa(0.85))) }
    }
  }
}
