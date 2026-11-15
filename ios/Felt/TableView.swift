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
  var ovMin: Double { ["8": 0.6, "9": 0.72, "10": 0.78, "heyball": 0.64, "snooker": 0.66, "carom": 0.66, "bumper": 0.76][game] ?? 0.6 }
  var illegal: Color { game == "8" ? Color(hex: 0xffa597) : Color(hex: 0xffe27a) }
  var game = "8"
  static func of(_ g: TableGame) -> Look {
    var l = base(g); l.game = g.table.2; return l
  }
  static func base(_ g: TableGame) -> Look {
    switch g {
    case .eight, .ten: Look(cloth: Color(hex: 0x1b5d47), cushion: Color(hex: 0x1d6450), rail: Color(hex: 0x4f2714), railDark: Color(rgb: 44, 19, 9))
    case .nine: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x100f11), railDark: Color(rgb: 6, 6, 7))
    case .heyball: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x2a1a12), railDark: Color(rgb: 16, 9, 6))
    case .snooker: Look(cloth: Color(hex: 0x1b5d47), cushion: Color(hex: 0x1d6450), rail: Color(hex: 0x7c5228), railDark: Color(rgb: 86, 52, 22))
    case .carom: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x33201a), railDark: Color(rgb: 20, 11, 8))
    case .bumper: Look(cloth: Color(hex: 0x4f6030), cushion: Color(hex: 0x586a35), rail: Color(hex: 0x5c3a1e), railDark: Color(rgb: 58, 34, 16))
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
      drawPots(&ctx, m, bp, rb, sc)
      for b in list {
        let p = m.pt(b.x, b.y), z = b.z ?? 0, air = z > 0 ? 0.6 / (0.6 - min(z, 0.3)) : 1
        let (img, x, y) = model.ballImage(bp, b.n, Double(p.x) * sc, Double(p.y) * sc, rb * air)
        ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: x, y: y, width: Double(img.width), height: Double(img.height)))
      }
      ctx.scaleBy(x: sc, y: sc)
      drawFx(&ctx, m)
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
      ctx.scaleBy(x: sc, y: sc)
      drawPotRail(&ctx, m, bp)
      drawRail(&ctx, m, bp)
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
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
    /* guideLines' verdict: a first contact that is not a legal target, or (ball in hand in the kitchen) a
       ball behind the string reached before the cue ball crossed it; practice: any contact */
    var legal = model.game == .carom ? true : first != nil
    if let gm = model.g, let f = first {
      let E = model.engine, lt = E.legalTargets(gm)
      let wrong = !(is8(gm.kind) && gm.breakShot) && !lt.contains(f.n)
      let kitchen = gm.inHand == "kitchen" && !gm.breakShot && !P.crossed && f.x < s.HEAD_X
        && (gm.rules.kitchenSpot || lt.contains { n in (gm.balls.first { $0.n == n }?.x ?? 0) >= s.HEAD_X })
      legal = !wrong && !kitchen
    }
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

  /* 4c drawPots, in device px: the ball runs on to the drop's centre, shrinking and darkening, clipped to
     the cap's back or the bed (it goes under the rail where the rail overhangs the drop) and to a circle
     about the hole that closes in as it sinks */
  private func drawPots(_ ctx: inout GraphicsContext, _ m: Mapper, _ bp: BallPainter, _ rb: Double, _ sc: Double) {
    let s = model.sim, now = model.now, T = model.potGeometry(m)
    func ease(_ a: Double, _ b: Double, _ u: Double) -> Double { let t = min(1, max(0, (u - a) / (b - a))); return t * t * (3 - 2 * t) }
    func dev(_ x: Double, _ y: Double) -> CGPoint { let p = m.pt(x, y); return CGPoint(x: p.x * sc, y: p.y * sc) }
    func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { let c = dev(x, y), d = r * m.k * sc; return Path(ellipseIn: CGRect(x: c.x - d, y: c.y - d, width: 2 * d, height: 2 * d)) }
    for p in model.pots where p.k >= 0 && p.k < s.POCKETS.count {
      let u = (now - p.t) / TableModel.POT_MS, P = s.POCKETS[p.k], m1 = 1 - pow(1 - min(1, u / 0.5), 2), sink = ease(0.15, 1, u)
      let x = p.from.0 + (P[0] - p.from.0) * m1, y = p.from.1 + (P[1] - p.from.1) * m1, at = dev(x, y)
      var g = ctx
      /* drawCupPot: a cup has no cap or rail to go under, only the closing circle */
      if s.BUMPERS.isEmpty {
        let cl = T.potClip(p.k)
        var back = circle(cl.cx, cl.cy, cl.rb)
        let a = dev(-cl.co, -cl.co), b = dev(s.TL + cl.co, s.TW + cl.co)
        back.addRect(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
        g.clip(to: back)
      }
      g.clip(to: circle(P[0], P[1], s.POCKET_R[p.k] + (1 - ease(0.1, 0.55, u)) * 3 * s.BALL_R))
      let (img, ix, iy) = bp.ballImage(p.n, Double(at.x), Double(at.y), rb * (1 - 0.32 * sink), bp.axesOf(model.orient[p.n] ?? IDENT), dark: 0.88 * sink, rim: true)
      g.draw(Image(decorative: img, scale: 1), in: CGRect(x: ix, y: iy, width: Double(img.width), height: Double(img.height)))
    }
  }
  /* 4c drawFx, in CSS points, added as the page's 'lighter': a cushion's glow, a ball contact's ring, the cue's flash */
  private func drawFx(_ ctx: inout GraphicsContext, _ m: Mapper) {
    let rp = model.sim.BALL_R * m.k
    var g = ctx
    g.blendMode = .plusLighter
    for e in model.effects {
      let u = min(1, max(0, (model.now - e.t) / e.d)), s = m.pt(e.x, e.y), a = min(1, e.v / 3) * (1 - u) * (1 - u)
      if e.kind == "rail" {
        let r = rp * 2.2
        g.fill(Path(CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: [Color(.sRGB, red: 190 / 255, green: 1, blue: 220 / 255, opacity: 0.2 * a), Color(.sRGB, red: 190 / 255, green: 1, blue: 220 / 255, opacity: 0)]),
                                     center: s, startRadius: 0, endRadius: r))
      } else {
        let col = e.kind == "cue" ? Color(.sRGB, red: 170 / 255, green: 205 / 255, blue: 1, opacity: 0.6 * a) : Color.white.opacity(0.5 * a)
        let r = rp * (e.kind == "cue" ? 0.25 + 0.5 * u : 0.3 + 1.1 * u)
        g.stroke(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r)), with: .color(col), lineWidth: 1.5)
      }
    }
  }

  /* 6b2, the bottom rail's row: a seat per player (chipOf) inlaid in the wood nearest the player (upright the
     head rail, on its side the near long rail), each centred in a gap of the rail clear of every pocket and
     sight (railSpans), the score keeper's two in the gaps nearest the middle, snooker's bar in the next. Pearl
     ink (--ink) cut dark all round (RAIL_EDGE), the shooter lit with the lamp's glow, the other dimmed. */
  private func drawRail(_ ctx: inout GraphicsContext, _ m: Mapper, _ bp: BallPainter) {
    guard let g = model.g, g.winner == nil else { return }
    let s = model.sim, T = model.potGeometry(m), band = T.railBand
    let ink = Color(.sRGB, red: 0xef / 255.0, green: 0xe7 / 255.0, blue: 0xda / 255.0), edge = Color(.sRGB, red: 20 / 255, green: 8 / 255, blue: 3 / 255, opacity: 0.85)
    let mid = -(band.co + band.rail) / 2   /* the band's middle, metres out from the nose */
    /* the rail's run on screen: along y (upright, the head rail at x = 0) or along x (on its side, the rail at y = TW) */
    func at(_ u: Double) -> CGPoint { m.upright ? m.pt(mid, u) : m.pt(u, s.TW - mid) }
    /* the pill's height: the wood's, but never under Caption 2's 11 pt (--rf), as the page widens slim wood to WOOD_MIN */
    let ph = Swift.max(14, (band.rail - band.co) * m.k * 0.62), dot = ph * 0.8
    /* the gaps: the rail's span less every pocket (hole, jaws) and sight, with their pads */
    let len = m.upright ? s.TW : s.TL
    var spans: [[Double]] = [[0, len]]
    var holes: [[Double]] = []
    for (i, p) in s.POCKETS.enumerated() {
      let near = m.upright ? p[0] < s.TL / 2 : p[1] > s.TW / 2
      if !near { continue }
      let r = s.POCKET_R[i] + 4 / m.k, c = m.upright ? p[1] : p[0]
      var lo = c - r, hi = c + r
      for j in s.MOUTHS.indices.contains(i) ? s.MOUTHS[i] : [] { for q in [j.p, j.e] { let v = m.upright ? q[1] : q[0]; lo = Swift.min(lo, v - 4 / m.k); hi = Swift.max(hi, v + 4 / m.k) } }
      holes.append([lo, hi])
    }
    for q in T.railSights() {
      let onRail = m.upright ? q[0] < 0 : q[1] > s.TW
      if !onRail { continue }
      let c = m.upright ? q[1] : q[0], h = (m.upright ? q[3] : q[2]) + 1 / m.k
      holes.append([c - h, c + h])
    }
    for h in holes { spans = spans.flatMap { [[$0[0], Swift.min($0[1], h[0])], [Swift.max($0[0], h[1]), $0[1]]] }.filter { $0[1] - $0[0] > 0.01 } }
    /* a gap across the middle (snooker's head rail has no sights) holds both seats: split it there */
    spans = spans.flatMap { $0[0] < len / 2 && $0[1] > len / 2 ? [[$0[0], len / 2], [len / 2, $0[1]]] : [$0] }
    let left = spans.filter { ($0[0] + $0[1]) / 2 < len / 2 }.sorted { $0[1] > $1[1] }, right = spans.filter { ($0[0] + $0[1]) / 2 >= len / 2 }.sorted { $0[0] < $1[0] }
    /* upright the screen's left is the table's y = 0 side; on its side, x = 0 */
    let seats: [(Int, [Double]?)] = [(0, left.first), (1, right.first)]
    let next = model.railNext()
    for (p, span) in seats {
      guard let span else { continue }
      let lit = p == g.turn
      var items: [(kind: String, n: Int, text: String)] = []
      let on = g.balls.filter { $0.on && $0.n > 0 }.map { $0.n }.sorted()
      let nx = lit ? next : nil
      switch g.kind {
      case "snooker": items.append(("num", 0, String(g.score![p])))
      case "bumper":
        /* chipOf: the first of the player's balls still up, and how many */
        let mine = on.filter { bOwner($0) == p }
        if let f = mine.first { items.append(("ball", f, "")) }
        items.append(("num", 0, String(mine.count)))
      case "carom": items.append(("num", C_CUE[p], String(g.score![p]))); items.append(("of", 0, "/\(g.race!)"))
      case "straight", "rotation":
        if let nx { items.append(("ball", nx, "")) } else if g.kind == "rotation" && lit, let f = on.first { items.append(("ball", f, "")) }
        items.append(("num", 0, String(g.score![p]))); items.append(("of", 0, "/\(g.race!)"))
      case "9", "10":
        if lit, let f = nx ?? on.first { items.append(("ball", f, "")) }
      default:
        if let gr = g.groups[p] {
          items.append(("grp", gr == "stripes" ? 1 : 0, ""))
          if let nx { items.append(("ball", nx, "")) }
          else if !on.contains(where: { model.engine.groupOf($0) == gr }) { items.append(("ball", 8, "")) }
        } else if let nx { items.append(("ball", nx, "")) }
      }
      if items.isEmpty { items.append(("pip", 0, "")) }
      /* each item's width, then laid out centred in the gap */
      let font = Font.system(size: Swift.max(11, ph * 0.78), weight: .bold, design: .rounded).monospacedDigit()
      let widths = items.map { it -> Double in it.kind == "num" || it.kind == "of" ? Double(ctx.resolve(Text(it.text).font(font)).measure(in: CGSize(width: 200, height: 100)).width) : dot }
      let gap = ph * 0.22, total = widths.reduce(0, +) + gap * Double(items.count - 1)
      let c0 = at((span[0] + span[1]) / 2)
      var g2 = ctx
      g2.opacity = lit ? 1 : 0.45
      if lit { g2.addFilter(.shadow(color: Color(.sRGB, red: 1, green: 236 / 255, blue: 190 / 255, opacity: 0.75), radius: 3)) }
      var x = Double(c0.x) - total / 2
      for (i, it) in items.enumerated() {
        let w = widths[i], cx = x + w / 2, cy = Double(c0.y)
        switch it.kind {
        case "ball":
          let r = dot / 2 * model.scaleFactor, (img, ix, iy) = bp.ballImage(it.n, cx * model.scaleFactor, cy * model.scaleFactor, r, bp.axesOf(IDENT, screen: true))
          g2.draw(Image(decorative: img, scale: model.scaleFactor), in: CGRect(x: ix / model.scaleFactor, y: iy / model.scaleFactor, width: Double(img.width) / model.scaleFactor, height: Double(img.height) / model.scaleFactor))
        case "grp":
          let rect = CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot), disc = Path(ellipseIn: rect)
          g2.stroke(disc, with: .color(edge), lineWidth: 1.5)
          if it.n == 0 { g2.fill(disc, with: .color(ink)) }
          else {
            var c = g2; c.clip(to: disc)
            c.fill(Path(rect), with: .color(ink)); c.fill(Path(CGRect(x: rect.minX, y: cy - dot * 0.22, width: dot, height: dot * 0.44)), with: .color(edge))
          }
        case "pip":
          g2.stroke(Path(ellipseIn: CGRect(x: cx - dot * 0.3, y: cy - dot * 0.3, width: dot * 0.6, height: dot * 0.6)), with: .color(ink), lineWidth: 1.5)
        default:
          let col: Color = it.kind == "num" && it.n >= 70 ? { let c = ballColor(it.n); return Color(rgb: c.0, c.1, c.2) }() : ink
          let t = Text(it.text).font(it.kind == "of" ? Font.system(size: Swift.max(11, ph * 0.6), weight: .semibold, design: .rounded) : font).foregroundColor(col)
          var e = g2; e.addFilter(.shadow(color: edge, radius: 0.7))
          e.draw(t, at: CGPoint(x: cx, y: cy))
        }
        x += w + gap
      }
    }
    /* snooker's bar (6b): the ball on, the break while one runs, in the gap after the second seat */
    if g.kind == "snooker", let S = g.snk, right.count > 1 {
      let span = right[1], c0 = at((span[0] + span[1]) / 2)
      var dots: [Int] = []
      if let f = S.free { dots = S.on == .red ? [41, f] : [f] }
      else { switch S.on { case .red: dots = [41]; case .colour: dots = S_COLS.filter { c in g.balls.contains { $0.n == c && $0.on } }; case .ball(let b): dots = [b]; case .none: dots = [] } }
      let w = Double(dots.count) * dot * 0.9
      var x = Double(c0.x) - w / 2 - (S.brk > 0 ? ph * 0.8 : 0)
      for n in dots {
        let r = dot * 0.42 * model.scaleFactor, (img, ix, iy) = bp.ballImage(n, (x + dot * 0.45) * model.scaleFactor, Double(c0.y) * model.scaleFactor, r, bp.axesOf(IDENT, screen: true))
        ctx.draw(Image(decorative: img, scale: model.scaleFactor), in: CGRect(x: ix / model.scaleFactor, y: iy / model.scaleFactor, width: Double(img.width) / model.scaleFactor, height: Double(img.height) / model.scaleFactor))
        x += dot * 0.9
      }
      if S.brk > 0 {
        var e = ctx; e.addFilter(.shadow(color: edge, radius: 0.7))
        e.draw(Text(String(S.brk)).font(.system(size: ph * 0.78, weight: .bold, design: .rounded).monospacedDigit()).foregroundColor(ink), at: CGPoint(x: x + ph * 0.6, y: Double(c0.y)))
      }
    }
  }

  /* 6b3: the potted balls, each in a window of its own in the wood of the rails at the screen's left and right
     (potPlan's slots: the gaps between the holes and sights, packed for POT_PER_RAIL, filling from the foot), 8-ball's
     solids up the left and stripes up the right, the 8 up its potter's group's side; 9 and 10-ball in pot order up the
     left, then the right. A dark recess (POT_RECESS) cut dark round its edge, the rail's true little ball in it, a rim
     of light on a ball under 3:1 on the recess. */
  private func drawPotRail(_ ctx: inout GraphicsContext, _ m: Mapper, _ bp: BallPainter) {
    guard let g = model.g, !model.potOrder.isEmpty else { return }
    let s = model.sim, T = model.potGeometry(m), band = T.railBand, k = m.k
    let wk = (band.rail - band.co) * k, mid = (band.co + band.rail) / 2
    let a = m.pt(0, 0), b = m.pt(s.TL, s.TW)
    let left = Double(min(a.x, b.x)), right = Double(max(a.x, b.x)), top = Double(min(a.y, b.y)), bottom = Double(max(a.y, b.y))
    let sz = max(9, (wk - 2).rounded(.down)), ballD = sz - 3, POT_GAP = 3.0, PER = 8
    /* the obstacles on screen: each pocket's hole and jaws (RAIL_PAD 4), each sight (POT_SIGHT_PAD 3) */
    var holes: [[Double]] = []
    func box(_ pts: [[Double]], _ pad: Double) {
      let ps = pts.map { m.pt($0[0], $0[1]) }
      holes.append([Double(ps.map(\.x).min()!), Double(ps.map(\.x).max()!), Double(ps.map(\.y).min()!), Double(ps.map(\.y).max()!), pad])
    }
    for (i, p) in s.POCKETS.enumerated() {
      let r = s.POCKET_R[i]
      var pts = [[p[0] - r, p[1]], [p[0] + r, p[1]], [p[0], p[1] - r], [p[0], p[1] + r]]
      if s.MOUTHS.indices.contains(i) { for j in s.MOUTHS[i] { pts.append(j.p); pts.append(j.e) } }
      box(pts, 4)
    }
    for q in T.railSights() { box([[q[0] - q[2], q[1] - q[3]], [q[0] + q[2], q[1] + q[3]]], 3) }
    let sides: [[CGPoint]] = [left - mid * k, right + mid * k].map { cx in
      var gaps = [[top, bottom]]
      for h in holes {
        if h[1] < cx - wk / 2 || h[0] > cx + wk / 2 { continue }
        gaps = gaps.flatMap { [[$0[0], min($0[1], h[2] - h[4])], [max($0[0], h[3] + h[4]), $0[1]]] }.filter { $0[1] - $0[0] >= sz }
      }
      gaps.sort { $0[0] > $1[0] }
      let cap = gaps.map { Int((($0[1] - $0[0] + POT_GAP) / (sz + POT_GAP)).rounded(.down)) }
      var mm = 1
      while mm < max(1, cap.max() ?? 1) && cap.reduce(0, { $0 + min(mm, $1) }) < PER { mm += 1 }
      var slots: [CGPoint] = []
      for (i, gp) in gaps.enumerated() {
        let kk = min(mm, cap[i]), run = Double(kk) * sz + Double(kk - 1) * POT_GAP
        for j in 0..<kk { slots.append(CGPoint(x: cx, y: (gp[0] + gp[1]) / 2 + run / 2 - sz / 2 - Double(j) * (sz + POT_GAP))) }
      }
      return slots
    }
    /* potSeats */
    var seats: [(Int, CGPoint)] = []
    if is8(g.kind) {
      var n8 = [0, 0]
      for n in model.potOrder {
        var side = n > 8 ? 1 : 0
        if n == 8 { side = g.groups[model.potBy[8] ?? 0] == "stripes" ? 1 : 0 }
        if n8[side] < sides[side].count { seats.append((n, sides[side][n8[side]])); n8[side] += 1 }
      }
    } else {
      for (i, n) in model.potOrder.enumerated() {
        if i < sides[0].count { seats.append((n, sides[0][i])) } else if i - sides[0].count < sides[1].count { seats.append((n, sides[1][i - sides[0].count])) }
      }
    }
    let recess = Color(rgb: 16, 11, 8), edge = Color(.sRGB, red: 20 / 255, green: 8 / 255, blue: 3 / 255, opacity: 0.85), f = model.scaleFactor
    for (n, c) in seats {
      if let t = model.potAt[n], model.now < t { continue }   /* still dropping into its pocket */
      let rr = CGRect(x: c.x - sz / 2, y: c.y - sz / 2, width: sz, height: sz)
      ctx.fill(Path(ellipseIn: rr), with: .color(recess))
      ctx.stroke(Path(ellipseIn: rr), with: .color(edge), lineWidth: 1)
      let (img, ix, iy) = bp.ballImage(n, Double(c.x) * f, Double(c.y) * f, ballD / 2 * f, bp.axesOf(IDENT, screen: true))
      ctx.draw(Image(decorative: img, scale: f), in: CGRect(x: ix / f, y: iy / f, width: Double(img.width) / f, height: Double(img.height) / f))
      /* a ball too dark for the recess (a solid under 3:1 on it) gets a rim of light */
      let col = ballColor(n), lum = { (v: Int) -> Double in let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
      let L1 = 0.2126 * lum(col.0) + 0.7152 * lum(col.1) + 0.0722 * lum(col.2), L2 = 0.2126 * lum(16) + 0.7152 * lum(11) + 0.0722 * lum(8)
      if n < 9 && (max(L1, L2) + 0.05) / (min(L1, L2) + 0.05) < 3 {
        /* .rim: box-shadow 0 0 0 1px #77716b, a hairline of light just outside the ball */
        let br = ballD / 2 + 0.5
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: 2 * br, height: 2 * br)), with: .color(Color(rgb: 0x77, 0x71, 0x6b)), lineWidth: 1)
      }
    }
  }
}
