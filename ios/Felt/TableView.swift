/* The table, top down, in the web build's colours (CLOTHS, RAILS, BALL_COLOR in index.html section
   4): wood, cloth with the lamp's pool, the pocket holes, the cushion rubbers from the sim's own
   CUSHION_POLYS, the sights, the balls with their shadows, and the guide. Upright on a phone held
   upright (the head string at the foot of the screen), lengthwise on its side. */
import FeltRender
import FeltSim
import SwiftUI
import QuartzCore

struct Look {
  var cloth: Color, cushion: Color, rail: Color, railDark: Color
  /* CLOTHS[...].ovMin and .illegal: every white overlay at least ovMin opaque; the illegal colour */
  var ov: Double? = nil, ill: Color? = nil, cl: Color? = nil
  var ovMin: Double { ov ?? ["8": 0.6, "9": 0.72, "10": 0.78, "heyball": 0.64, "snooker": 0.66, "carom": 0.66, "bumper": 0.76, "straight": 0.6, "rotation": 0.66][game] ?? 0.6 }
  var illegal: Color { ill ?? (game == "8" || game == "straight" ? Color(hex: 0xffa597) : Color(hex: 0xffe27a)) }
  /* CL.call: the called ball's ring and pocket's glow, 3:1 and more on the cloth */
  var call: Color { cl ?? (game == "8" || game == "straight" ? Color(hex: 0xffe27a) : Color(hex: 0x9ff0ff)) }
  var game = "8"
  static func of(_ g: TableGame) -> Look {
    var l = base(g); l.game = g.table.2; return l
  }
  /* the look a dress makes: its cloth's colours, overlay floor, illegal and call colours; its rail's wood */
  static func of(_ d: Dress, game g: TableGame) -> Look {
    let c = TableLook.CLOTH[d.cloth] ?? TableLook.CLOTH["green"]!, r = TableLook.RAILS[d.rail] ?? TableLook.RAILS["walnut"]!
    var l = Look(cloth: css(c.base), cushion: css(c.cushion), rail: css(r.base), railDark: Color(rgb: Int(r.dark[0]), Int(r.dark[1]), Int(r.dark[2])))
    l.game = g.table.2; l.ov = c.ovMin; l.ill = css(c.illegal); l.cl = css(c.call)
    return l
  }
  static func base(_ g: TableGame) -> Look {
    switch g {
    case .eight, .ten: Look(cloth: Color(hex: 0x1b5d47), cushion: Color(hex: 0x1d6450), rail: Color(hex: 0x4f2714), railDark: Color(rgb: 44, 19, 9))
    case .nine: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x100f11), railDark: Color(rgb: 6, 6, 7))
    case .heyball: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x2a1a12), railDark: Color(rgb: 16, 9, 6))
    case .snooker: Look(cloth: Color(hex: 0x1b5d47), cushion: Color(hex: 0x1d6450), rail: Color(hex: 0x7c5228), railDark: Color(rgb: 86, 52, 22))
    case .carom: Look(cloth: Color(hex: 0x1d4f91), cushion: Color(hex: 0x21579c), rail: Color(hex: 0x33201a), railDark: Color(rgb: 20, 11, 8))
    case .straight: Look(cloth: Color(hex: 0x134a44), cushion: Color(hex: 0x16524b), rail: Color(hex: 0x44190f), railDark: Color(rgb: 34, 10, 6))
    case .rotation: Look(cloth: Color(hex: 0x8c1f25), cushion: Color(hex: 0x94242b), rail: Color(hex: 0x6b2213), railDark: Color(rgb: 60, 14, 8))
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
  private(set) var k: Double, ox: Double, oy: Double
  let upright: Bool, TL: Double, TW: Double, rail: Double
  /* the camera's zoom (3b, view.z): 1 for the fitted view */
  private(set) var z = 1.0
  /* tableExt: how far the rails (never the bed) may run past the stage into a safe-area inset on each side (the status
     bar or the island; never the controls' side or the foot). The stage's canvas is drawn that much bigger on those sides,
     so its coordinates start at the inset's edge: the safe stage begins at (l, t). */
  struct Ext: Equatable, Sendable { var t = 0.0, l = 0.0, r = 0.0 }
  nonisolated(unsafe) private static var cur = Ext()
  private static let extLock = NSLock()
  /* the game screen's ext, as last laid out (any thread may read it) */
  static var current: Ext { get { extLock.lock(); defer { extLock.unlock() }; return cur } set { extLock.lock(); cur = newValue; extLock.unlock() } }
  init(size: CGSize, TL: Double, TW: Double, ext: Ext = Mapper.current) {
    /* the safe stage: the canvas less the ext */
    let w = Double(size.width) - ext.l - ext.r, h = Double(size.height) - ext.t
    let e = max(0, min(1, (min(w, h) - 430) / (700 - 430)))
    var rail = RAIL_MIN + (RAIL_MAX - RAIL_MIN) * e * e * (3 - 2 * e)
    /* railFit: the scale at which a bed B with its rails fits a span S, its rails up to a and b past either end;
       railStart: where its footprint then starts, centred where it can be (relative to the safe stage) */
    func feas(_ k: Double, _ S: Double, _ a: Double, _ b: Double, _ B: Double, _ R: Double) -> Bool { max(-a, -R * k) <= min(S + b - (B + 2 * R) * k, S - (R + B) * k) + 1e-9 }
    func railFit(_ S: Double, _ a: Double, _ b: Double, _ B: Double, _ R: Double) -> Double {
      var lo = 0.0, hi = (S + a + b) / B
      for _ in 0..<48 { let m = (lo + hi) / 2; if feas(m, S, a, b, B, R) { lo = m } else { hi = m } }
      return lo
    }
    func railStart(_ k: Double, _ S: Double, _ a: Double, _ b: Double, _ B: Double, _ R: Double) -> Double {
      let lo = max(-a, -R * k), hi = min(S + b - (B + 2 * R) * k, S - (R + B) * k)
      return min(max((S - (B + 2 * R) * k) / 2, lo), max(lo, hi))
    }
    /* fitTable: upright or along the screen, whichever is bigger */
    func fit(_ R: Double) -> (k: Double, up: Bool) {
      let kp = min(railFit(w, ext.l, ext.r, TW, R), railFit(h, ext.t, 0, TL, R)), kl = min(railFit(w, ext.l, ext.r, TL, R), railFit(h, ext.t, 0, TW, R))
      /* the octagon is square: on a tie it stands upright on an upright stage (red's end at the bottom) */
      if TL == TW && abs(kp - kl) <= 1e-9 * kl { return (kl, h > w) }
      return kp > kl ? (kp, true) : (kl, false)
    }
    var f = fit(rail)
    /* layout()'s WOOD_MIN: the wood (rail past the cushion's depth) never slimmer than 13 pt, so the rail row's inlays
       have room; the rails drawn wider (the cushions and the physics are the table's own) and the table fitted again */
    if let co = Mapper.co(TL, TW) {
      var i = 0
      while i < 3 && (rail - co) * f.k < Mapper.WOOD_MIN - 0.01 { rail = co + Mapper.WOOD_MIN / f.k + 0.0005; f = fit(rail); i += 1 }
    }
    let k = f.k, bw = f.up ? TW : TL, bh = f.up ? TL : TW
    self.TL = TL; self.TW = TW; self.upright = f.up; self.rail = rail; self.k = k
    ox = ext.l + railStart(k, w, ext.l, ext.r, bw, rail) + rail * k; oy = ext.t + railStart(k, h, ext.t, 0, bh, rail) + rail * k
  }
  static let WOOD_MIN = 13.0
  /* each table's cushion depth (TablePainter.cushionDepth at RAIL_MAX), by its size, recorded when a Sim is set to it
     (any thread: the home's cards and the bakes set theirs off the main one) */
  nonisolated(unsafe) private static var coBy: [String: Double] = [:]
  private static let coLock = NSLock()
  private static func key(_ TL: Double, _ TW: Double) -> String { "\(TL)x\(TW)" }
  static func co(_ TL: Double, _ TW: Double) -> Double? { coLock.lock(); defer { coLock.unlock() }; return coBy[key(TL, TW)] }
  static func note(_ s: Sim) {
    var d = 0.02
    for p in s.CUSHION_POLYS { for q in p { d = max(d, -q[0], -q[1], q[0] - s.TL, q[1] - s.TW) } }
    coLock.lock(); coBy[key(s.TL, s.TW)] = min(d, RAIL_MAX - 0.02); coLock.unlock()
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
  /* camRect (3b): the window the camera shows, the table's footprint at z = 1 (the rail's outer edge) */
  var camRect: CGRect {
    let a = pt(-rail, -rail), b = pt(TL + rail, TW + rail)
    return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
  }
  /* camView (3b): this (fitted) view at zoom z about table point (x, y), the centre clamped so the table covers camRect */
  func cam(_ z: Double, _ x: Double, _ y: Double) -> Mapper {
    guard z > 1 else { return self }
    let R = camRect, hw = Double(R.width) / 2, hh = Double(R.height) / 2, f = pt(x, y)
    let fx = clamp(Double(f.x), Double(R.minX) + hw / z, Double(R.maxX) - hw / z), fy = clamp(Double(f.y), Double(R.minY) + hh / z, Double(R.maxY) - hh / z)
    var m = self
    m.k = k * z; m.ox = Double(R.minX) + hw + z * (ox - fx); m.oy = Double(R.minY) + hh + z * (oy - fy); m.z = z
    return m
  }
}

struct TableCanvas: View {
  let model: TableModel
  let look: Look
  @Environment(\.displayScale) private var scale

  var body: some View {
    let _ = Bench.hit("TableCanvas")
    Canvas { ctx, size in
      let dt0 = CACurrentMediaTime()
      defer { if TableModel.fpsOn { let d = CACurrentMediaTime() - dt0; if d > 0.1 { print(String(format: "felt-fps slow draw %.0f ms", d * 1000)) } } }
      defer { if TableModel.aimBench || TableModel.touchBench { Bench.draw(CACurrentMediaTime() - dt0) } }
      _ = model.frame
      TouchLog.add(String(format: "draw aim %.5f cue %.4f %.4f", model.aim, model.cue?.x ?? -1, model.cue?.y ?? -1))
      let s = model.sim, base = Mapper(size: size, TL: s.TL, TW: s.TW), m = model.camView(base)
      /* the last baked table, even for another size while this one bakes (never a blank frame) */
      if let img = model.tableImage {
        ctx.draw(Image(decorative: img.image, scale: img.scale), in: CGRect(origin: .zero, size: size))
        /* zoomed (3b, camTable): the table again under the camera (the fitted image scaled up), and everything after
           clipped to its window */
        if m.z > 1 {
          ctx.clip(to: Path(base.camRect))
          ctx.draw(Image(decorative: img.image, scale: img.scale), in: CGRect(x: m.ox - m.z * base.ox, y: m.oy - m.z * base.oy, width: Double(size.width) * m.z, height: Double(size.height) * m.z))
        }
      }
      /* drawCast's shadows, then the balls (4b), each composited from its own image at device px */
      let sc = Double(scale), bp = model.ballPainter(upright: m.upright, scale: scale), rb = s.BALL_R * m.k * sc
      /* the cue ball in hand: the ghost (drawPlace, lifted) stands in for it on a legal spot; over an illegal one the ball
         stays drawn on its last legal spot. A ball let go settles (settleH) */
      let ghostOk = model.rp == nil && model.placeAt.map { at in model.g.map { model.engine.canPlace($0, at.0, at.1) } ?? true } ?? false
      let list = model.shown.filter { $0.on && !(ghostOk && $0.n == model.cueN) }, sh = model.rp == nil ? model.settleH(model.now) : 0
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
      for b in list {
        let p = m.pt(b.x, b.y)
        for (img, rect, a) in bp.castParts(b.x, b.y, Double(p.x) * sc, Double(p.y) * sc, rb, tl: s.TL, tw: s.TW, ballR: s.BALL_R, lift: b.n == model.cueN ? sh : 0, z: b.z ?? 0) {
          var c = ctx; c.opacity = a; c.draw(Image(decorative: img, scale: 1), in: rect)
        }
      }
      ctx.scaleBy(x: sc, y: sc)
      let pen = Sink2D(ctx: ctx, m: m)
      drawHandZone(pen, m)
      drawHint(pen, m)
      drawGuide(pen, m)
      drawSolo(pen, m)
      defer { drawLoupe(&ctx, m, bp) }
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
      drawPots(&ctx, m, bp, rb, sc)
      /* the game ball's halo, under the balls */
      if let gb = gameBall { for b in list where b.n == gb { drawHalo(pen, m.pt(b.x, b.y), s.BALL_R * m.k) } }
      for b in list {
        let p = m.pt(b.x, b.y), z = b.z ?? 0, air = z > 0 ? 0.6 / (0.6 - min(z, 0.3)) : 1, grow = b.n == model.cueN && sh > 0 ? 1 + TableModel.LIFT_GROW * sh : 1
        let (img, x, y) = model.ballImage(bp, b.n, Double(p.x) * sc, Double(p.y) * sc, rb * air * grow)
        ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: x, y: y, width: Double(img.width), height: Double(img.height)))
      }
      ctx.scaleBy(x: sc, y: sc)
      if model.aimHeld, model.rolling == nil, let c = model.cue, c.on { drawHeld(&ctx, m, c) }
      drawPlace(&ctx, m, bp, sc)
      drawFx(&ctx, m)
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
      ctx.scaleBy(x: sc, y: sc)
      /* the rail row and the potted windows sit on the fitted view (the page's DOM over the canvas); the windows hide
         while zoomed (potTick: cam.z > 1.02) */
      if m.z <= 1.02 { drawPotRail(&ctx, base, bp) } else { model.potSlideDue = [] }   /* hidden: a pot then never rolls in */
      drawRail(&ctx, base, bp)
      drawCall(Sink2D(ctx: ctx, m: m), m)
      ctx.scaleBy(x: 1 / sc, y: 1 / sc)
      /* the cue (4f): pulled back by power while aiming, driven through during the stroke, carried a
         few centimetres on and faded as the shot starts */
      ctx.scaleBy(x: sc, y: sc)
      let rest = s.BALL_R + 0.012, back = 0.27, R = s.BALL_R, g = model.game.table.2
      if let rc = model.replayCue {
        drawCue(&ctx, m, game: g, dress: model.dress, cx: rc.x, cy: rc.y, ang: rc.ang, gap: rc.gap, alpha: rc.alpha)
      } else if model.rp != nil {
      } else if model.rolling == nil, let c = model.cue {
        var gap = rest + back * min(1, max(0, model.power))
        if let st = model.stroke {
          let u = min(1, max(0, (st.t0.map { model.now - $0 } ?? 0) * model.speed / TableModel.STROKE_MS)), g0 = rest + back * min(1, max(0, st.power))
          gap = g0 + (R - g0) * u * u
        }
        drawCue(&ctx, m, game: g, dress: model.dress, cx: c.x, cy: c.y, ang: model.aim, gap: gap)
      } else if model.rolling != nil, let lc = model.lastCue, model.now - model.shotAt < 0.18 {
        let u = (model.now - model.shotAt) / 0.18, e = min(1, max(0, u * 2)), ease = e * e * (3 - 2 * e)
        drawCue(&ctx, m, game: g, dress: model.dress, cx: lc.x, cy: lc.y, ang: lc.ang, gap: R - 0.035 * ease, alpha: 1 - u)
      }
    }
  }

  /* 4d's guideLines in CSS points: the aim line to the ghost ball (pure geometry), then the preview's
     paths, the object ball's solid line and the cue ball's dashed one, each over a faint dark
     under-stroke so it reads on any cloth (strokeLine, guideRing). Practice has no rules: any first
     contact is legal, and only the cue ball's pot is not. */
  /* drawSolo: a trick shot's marks, the cue ball's target ring (filled faintly, a dashed edge) and the pocket the goal names
     (a gold ring) */
  func drawSolo(_ pen: OverlayPen, _ m: Mapper) {
    defer { pen.alpha = 1 }
    /* the lesson's step 1: a gold ring round the 1 */
    if let L = model.lesson, L.step == 1, !model.lessonDone, let b = model.g?.balls.first(where: { $0.n == 1 && $0.on }) {
      pen.circle(m.pt(b.x, b.y), model.sim.BALL_R * m.k + 10, Color(rgb: 0xf2, 0xc9, 0x4c), 2.5, dash: [])
    }
    /* #coachRing: what the coach rings (tutMarks): a ball, a pocket, a colour's spot, the rail's mark, the D */
    if let r = model.tutRing, r.kind != "none", let gm = model.g {
      let s = model.sim, k = m.k
      var c: CGPoint? = nil, rad = 0.0
      switch r.kind {
      case "ball": if let b = gm.balls.first(where: { $0.n == r.n && $0.on }) { c = m.pt(b.x, b.y); rad = s.BALL_R * k + 10 }
      case "pocket": if r.n < s.POCKETS.count { c = m.pt(s.POCKETS[r.n][0], s.POCKETS[r.n][1]); rad = s.POCKET_R[r.n] * k + 9 }
      case "spot": if let p = s.SPOTS[r.n] { c = m.pt(p[0], p[1]); rad = s.BALL_R * k + 12 }
      case "rail": if let q = model.tutRail() { c = m.pt(q[0], q[1]); rad = 16 }
      case "d":
        let pts = (0...24).map { i -> CGPoint in let a = Double.pi / 2 + Double(i) / 24 * Double.pi; return m.pt(s.HEAD_X + (s.D_R + s.BALL_R) * cos(a), s.TW / 2 + (s.D_R + s.BALL_R) * sin(a)) }
        pen.stroke(pts, closed: true, .white.opacity(0.9), 2.5, dash: [], round: false)
      default: break
      }
      if let c { pen.circle(c, rad, .white.opacity(0.9), 2.5, dash: []) }
    }
    /* drawDrill: the ring (its full-marks edge, and faint where it scores nothing), the line, the break's box, the pocket */
    if let gm = model.g, gm.mode == "drill", let S = model.drill?.S {
      let dash: [CGFloat] = [6, 5], W = Color.white.opacity(0.85), R = model.sim.BALL_R
      if let z = S.zone {
        let p = m.pt(z.at[0], z.at[1]), r = (z.full + R) * m.k, r0 = (z.zero + R) * m.k
        pen.fillCircle(p, r, .white.opacity(0.08))
        pen.circle(p, r, W, 2, dash: dash)
        pen.alpha = 0.3; pen.circle(p, r0, W, 2, dash: dash); pen.alpha = 1
      }
      if let L = S.line { pen.stroke([m.pt(L.x, 0), m.pt(L.x, model.sim.TW)], closed: false, W, 2, dash: dash, round: false) }
      if let B = S.box { pen.stroke([m.pt(B[0], B[1]), m.pt(B[2], B[1]), m.pt(B[2], B[3]), m.pt(B[0], B[3])], closed: true, W, 2, dash: dash, round: false) }
      if let k = S.pocket, k < model.sim.POCKETS.count {
        let P = model.sim.POCKETS[k]
        pen.circle(m.pt(P[0], P[1]), model.sim.POCKET_R[k] * m.k + 5, Color(rgb: 0xf2, 0xc9, 0x4c), 2.5, dash: [])
      }
      return
    }
    guard let gm = model.g, gm.mode == "trick", let id = gm.trick, let c = trickById(id), c.zoneR != nil || c.pocket != nil else { return }
    if let r0 = c.zoneR, let z = model.engine.trickPoints(c)[-1] {
      let p = m.pt(z[0], z[1]), r = r0 * m.k
      pen.fillCircle(p, r, .white.opacity(0.08))
      pen.circle(p, r, .white.opacity(0.85), 2, dash: [6, 5])
    }
    if let k = c.pocket, k < model.sim.POCKETS.count {
      let P = model.sim.POCKETS[k]
      pen.circle(m.pt(P[0], P[1]), model.sim.POCKET_R[k] * m.k + 5, Color(rgb: 0xf2, 0xc9, 0x4c), 2.5, dash: [])
    }
  }
  /* drawHeld: a held pointer aim (5 input): a small padlock up and to the side of the ghost ball (or, with the guide off,
     a little way along the line from the cue ball), white over a near-black edge so it keeps 3:1 on any cloth; beside
     the line, on its upper side on screen, never over the ghost itself */
  private func drawHeld(_ ctx: inout GraphicsContext, _ m: Mapper, _ c: Ball) {
    let R = model.sim.BALL_R, a = model.aim
    let at = model.ghostAt ?? (c.x + JSMath.cos(a) * 3 * R, c.y + JSMath.sin(a) * 3 * R), s = m.pt(at.0, at.1)
    let rp = R * m.k, off = rp + 9
    /* screen-space side of the line: the glyph sits up from the ghost on whichever side is up */
    let e = m.pt(at.0 + JSMath.cos(a) * R, at.1 + JSMath.sin(a) * R), lx = Double(e.x - s.x), ly = Double(e.y - s.y), L = JSMath.hypot(lx, ly) == 0 ? 1 : JSMath.hypot(lx, ly)
    var nx = -ly / L, ny = lx / L
    if ny > 0 { nx = -nx; ny = -ny }
    let x = Double(s.x) + nx * off, y = Double(s.y) + ny * off
    var path = Path()
    path.move(to: CGPoint(x: x - 4, y: y - 1)); path.addLine(to: CGPoint(x: x - 4, y: y - 3.2))
    path.addArc(center: CGPoint(x: x, y: y - 3.2), radius: 4, startAngle: .radians(Double.pi), endAngle: .radians(0), clockwise: false)
    path.addLine(to: CGPoint(x: x + 4, y: y - 1))
    let edge = Color.black.opacity(0.8)
    ctx.stroke(path, with: .color(edge), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
    let box = Path(roundedRect: CGRect(x: x - 6, y: y - 1.5, width: 12, height: 9), cornerRadius: 2, style: .circular)
    ctx.fill(box, with: .color(edge)); ctx.stroke(box, with: .color(edge), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
    ctx.fill(Path(roundedRect: CGRect(x: x - 5.5, y: y - 1, width: 11, height: 8), cornerRadius: 1.75, style: .circular), with: .color(.white))
    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: y + 2.6 - 1.3, width: 2.6, height: 2.6)), with: .color(.black.opacity(0.75)))
  }
  /* gameBall: the game ball (the 8 in 8-ball, the 9 in 9-ball), none at 14.1 and rotation */
  private var gameBall: Int? {
    guard let gm = model.g, gm.kind != "straight" && gm.kind != "rotation" else { return nil }
    return model.engine.gameBallOf(gm) ?? 8
  }
  /* drawHalo: the game ball's thin soft halo on the cloth, under its edge: a pale gold core in a faint glow (a ring round
     the ball, so it rolls with nothing); c and rp in CSS pt */
  func drawHalo(_ pen: OverlayPen, _ c: CGPoint, _ rp: Double) {
    let w = max(1.25, rp * 0.075), R = rp + w * 0.75
    pen.circle(c, R + w * 0.6, Color(red: 1, green: 222 / 255, blue: 140 / 255).opacity(0.22), w * 3, dash: [])
    pen.circle(c, R, Color(red: 1, green: 236 / 255, blue: 190 / 255).opacity(0.95), w, dash: [])
  }
  /* v3Overlays: the overlays of a 3D frame in draw()'s order, through the recorder (each path a ribbon at one height,
     v3PathZ): the kitchen or the D, the game ball's halo, the hint, the solo marks, the call, the guide, ball in hand's marks */
  func drawOverlays(_ sink: Sink3D, _ m: Mapper, balls: [Ball]) {
    drawHandZone(sink, m)
    if let gb = gameBall { for b in balls where b.on && b.n == gb { drawHalo(sink, m.pt(b.x, b.y), model.sim.BALL_R * m.k) } }
    drawHint(sink, m); drawSolo(sink, m); drawCall(sink, m)
    if model.rolling == nil { drawGuide(sink, m) }
    drawPlaceMarks(sink, m)
  }
  /* drawHint: auto aim's suggestion, a ring breathing round its ball (HINT_PULSE 2.4 s, faded in over HINT_FADE 300 ms)
     and a chevron on the cloth a few cm inside the pocket's mouth, its point toward the drop; a call on the table stands
     in for it */
  func drawHint(_ pen: OverlayPen, _ m: Mapper) {
    guard let h = model.hint, model.rolling == nil, model.stroke == nil, !model.cpuTurn, model.rp == nil, model.humanCall()?.ball == nil,
          let b = model.balls.first(where: { $0.n == h.n && $0.on }) else { return }
    let s = model.sim, t = (model.now - model.hintT) * 1000, still = model.reduceMotion
    let fade = min(1, max(0, t / 300)), breath = still ? 0 : 0.5 - 0.5 * cos(t / 2400 * 2 * Double.pi)
    let p = m.pt(b.x, b.y), rp = s.BALL_R * m.k, w = max(1.5, rp * 0.08), R = rp + 3.5 + 1.5 * breath
    pen.alpha = fade
    defer { pen.alpha = 1 }
    pen.circle(p, R, .white.opacity(0.08 + 0.06 * breath), w * 3, dash: [])
    pen.circle(p, R, .white.opacity(max(0.62 + 0.18 * breath, look.ovMin)), w, dash: [])
    if h.k >= 0 && h.k < s.POCKET_AIM.count {
      let A = s.POCKET_AIM[h.k], N = s.CPU_MOUTH_N[h.k], d = 0.045, c = m.pt(A[0] + N[0] * d, A[1] + N[1] * d), tp = m.pt(A[0], A[1])
      let ux = Double(tp.x - c.x), uy = Double(tp.y - c.y), ul = max(1e-9, (ux * ux + uy * uy).squareRoot()), fx = ux / ul, fy = uy / ul
      let hh = max(5, 0.012 * m.k), sx = Double(c.x) + fx * hh * 0.5, sy = Double(c.y) + fy * hh * 0.5
      let q = [CGPoint(x: sx - fx * hh - fy * hh, y: sy - fy * hh + fx * hh), CGPoint(x: sx, y: sy), CGPoint(x: sx - fx * hh + fy * hh, y: sy - fy * hh - fx * hh)]
      pen.stroke(q, closed: false, .white.opacity(0.1), w * 3.2, dash: [], round: true)
      pen.stroke(q, closed: false, .white.opacity(max(0.7, look.ovMin)), w, dash: [], round: true)
    }
  }
  /* the player's ball in hand: the turn is human, the shot not yet played, no replay */
  private var handOn: Bool { model.inHand && model.rolling == nil && model.stroke == nil && !model.cpuTurn && model.rp == nil }
  /* draw()'s kitchen (ball in hand behind the head string: a faint tint on the bed and the string) and drawD (the D) */
  func drawHandZone(_ pen: OverlayPen, _ m: Mapper) {
    guard handOn, let gm = model.g else { return }
    let s = model.sim, w = Color.white.opacity(max(0.3, look.ovMin))
    if gm.inHand == "kitchen" {
      pen.fill([m.pt(0, 0), m.pt(s.HEAD_X, 0), m.pt(s.HEAD_X, s.TW), m.pt(0, s.TW)], Color(red: 1, green: 1, blue: 240 / 255).opacity(0.045))
      pen.stroke([m.pt(s.HEAD_X, 0), m.pt(s.HEAD_X, s.TW)], closed: false, w, 1.5, dash: [], round: false)
    } else if gm.inHand == "D" {
      let pts = (0...32).map { i -> CGPoint in let a = Double.pi / 2 + Double(i) / 32 * Double.pi; return m.pt(s.HEAD_X + s.D_R * cos(a), s.TW / 2 + s.D_R * sin(a)) }
      pen.fill(pts, Color(red: 1, green: 1, blue: 240 / 255).opacity(0.06))
      pen.stroke(pts, closed: true, w, 1.5, dash: [], round: false)
    }
  }
  /* drawPlace: ball in hand, the whole turn: four chevrons that say the ball can be moved; while it is carried, the ghost
     where the finger has it and a ring that says whether it may stay there (white) or not (the illegal colour) */
  private func drawPlace(_ ctx: inout GraphicsContext, _ m: Mapper, _ bp: BallPainter, _ sc: Double) {
    guard handOn, let c = model.cue else { return }
    let s = model.sim, placing = model.placeAt != nil, at = model.placeAt ?? (c.x, c.y)
    let ok = !placing || model.g.map { model.engine.canPlace($0, at.0, at.1) } ?? true, p = m.pt(at.0, at.1), rp = s.BALL_R * m.k
    if placing {
      /* the ghost, lifted (bihH): its shadow, then the ball a touch bigger; faint over an illegal spot, where the ball
         itself stays on its last legal spot */
      var g = ctx; g.scaleBy(x: 1 / sc, y: 1 / sc)
      let h = model.bihH
      for (img, rect, a) in bp.castParts(at.0, at.1, Double(p.x) * sc, Double(p.y) * sc, rp * sc, tl: s.TL, tw: s.TW, ballR: s.BALL_R, lift: h, alpha: ok ? 1 : 0.4) {
        var c2 = g; c2.opacity = a; c2.draw(Image(decorative: img, scale: 1), in: rect)
      }
      g.opacity = ok ? 0.96 : 0.5
      let (img, x, y) = bp.ballImage(model.cueN, Double(p.x) * sc, Double(p.y) * sc, rp * sc * (1 + TableModel.LIFT_GROW * h), bp.axesOf(model.orient[model.cueN] ?? IDENT))
      g.draw(Image(decorative: img, scale: 1), in: CGRect(x: x, y: y, width: Double(img.width), height: Double(img.height)))
    }
    drawPlaceMarks(Sink2D(ctx: ctx, m: m), m)
  }
  /* drawPlace's marks (all the 3D view draws of it, noBall): while carried the ring that says whether the ball may stay
     (white) or not (the illegal colour), and the four chevrons */
  func drawPlaceMarks(_ pen: OverlayPen, _ m: Mapper) {
    guard handOn, let c = model.cue else { return }
    let placing = model.placeAt != nil, at = model.placeAt ?? (c.x, c.y)
    let ok = !placing || model.g.map { model.engine.canPlace($0, at.0, at.1) } ?? true, p = m.pt(at.0, at.1), rp = model.sim.BALL_R * m.k
    if placing { pen.circle(p, rp * 1.4, ok ? Color.white.opacity(0.75) : look.illegal, 1.5, dash: []) }
    let a = (placing ? 0.8 : 0.5) * (0.75 + 0.25 * sin(model.now * 1000 / 280)), d = rp * 2.1 + 3, w = 4.0
    for (ux, uy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
      let x = Double(p.x) + ux * d, y = Double(p.y) + uy * d
      pen.stroke([CGPoint(x: x - ux * w + uy * w, y: y - uy * w - ux * w), CGPoint(x: x, y: y), CGPoint(x: x - ux * w - uy * w, y: y - uy * w + ux * w)], closed: false,
                 Color.white.opacity(max(a, look.ovMin)), 1.5, dash: [], round: true)
    }
  }
  func drawGuide(_ sink: GuideSink, _ m: Mapper) {
    model.ghostAt = nil
    if model.guideMode == "off" || model.rp != nil { return }
    guard let c = model.cue else { return }
    let gi = model.guide()
    guard let h = gi?.0 ?? (model.rolling == nil ? model.aimHit : nil) else { return }
    let s = model.sim, R = s.BALL_R, rp = R * m.k, dx = JSMath.cos(model.aim), dy = JSMath.sin(model.aim)
    let gx = c.x + dx * h.t, gy = c.y + dy * h.t, ov = look.ovMin
    let wa = { (a: Double) in Color.white.opacity(max(a, ov)) }, white = { (a: Double) in Color.white.opacity(a) }
    /* a held pointer aim (5 input) draws its line solid, the soft one is free to follow the pointer */
    let held = model.aimHeld
    model.ghostAt = (gx, gy)
    /* with no complete preview of this layout yet, the line and the ghost on the last verdict (the ring never flips on
       half-known data) */
    guard let P = gi?.1 else {
      if h.t > 2 * R { sink.line([[c.x + dx * R, c.y + dy * R], [gx - dx * R, gy - dy * R]], wa(held ? 0.9 : 0.5), held ? 1.75 : 1.25, []) }
      sink.ring(gx, gy, rp, model.guideLegal ? white(0.9) : look.illegal, 1.5, fill: white(0.08), ghost: true)
      return
    }
    func strokeLine(_ pts: [[Double]], _ col: Color, _ w: Double, _ dash: [CGFloat] = []) { sink.line(pts, col, w, dash) }
    func ring(_ x: Double, _ y: Double, _ r: Double, _ col: Color, _ w: Double, fill: Color? = nil, ghost: Bool = false) { sink.ring(x, y, r, col, w, fill: fill, ghost: ghost) }
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
    defer { model.guideLegal = legal }
    if let gm = model.g, let f = first {
      let E = model.engine, lt = E.legalTargets(gm)
      let wrong = !(is8(gm.kind) && gm.breakShot) && !lt.contains(f.n)
      let kitchen = gm.inHand == "kitchen" && !gm.breakShot && !P.crossed && f.x < s.HEAD_X
        && (gm.rules.kitchenSpot || lt.contains { n in (gm.balls.first { $0.n == n }?.x ?? 0) >= s.HEAD_X })
      legal = !wrong && !kitchen
    }
    if h.t > 2 * R { strokeLine([[c.x + dx * R, c.y + dy * R], [gx - dx * R, gy - dy * R]], wa(held ? 0.9 : 0.5), held ? 1.75 : 1.25) }
    ring(gx, gy, rp, legal ? white(0.9) : look.illegal, 1.5, fill: white(0.08), ghost: true)
    if let f = first, !legal { ring(f.x, f.y, rp + 3, look.illegal, 2) }
    if legal, let obj = P.obj, obj.count > 1 {
      let o = trimStart(obj, R), end = obj[obj.count - 1]
      if o.count > 1 { strokeLine(o, white(0.9), 2) }
      if P.objPot >= 0 && P.objPot < s.POCKETS.count { ring(s.POCKETS[P.objPot][0], s.POCKETS[P.objPot][1], s.POCKET_R[P.objPot] * m.k * 0.8, white(0.7), 1.5) }
      else if P.objHit { ring(end[0], end[1], rp, wa(0.35), 1.25) }
    }
    let cueCol = P.cuePot < 0 ? white(0.9) : look.illegal
    /* a preview a frame or two behind the aim, on the same ball or cushion: its cue path moves with the ghost ball */
    let (ox, oy) = model.pvShift, pcue = ox != 0 || oy != 0 ? P.cue.map { [$0[0] + ox, $0[1] + oy] } : P.cue
    if pcue.count > 1 {
      strokeLine(pcue, wa(0.55), 1.5, [5, 5])
      let end = pcue[pcue.count - 1]
      if P.cueStop { ring(end[0], end[1], rp, wa(0.3), 1.25) }
      for q in P.bounces ?? [] { ring(q[0] + ox, q[1] + oy, 2.5, wa(0.85), 1, fill: wa(0.85)) }
      if P.cuePot >= 0 {
        var tail = Array(pcue.reversed()), len = 0.0
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
    if P.air.count > 1, let ctx = sink.ctx {
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

  /* 4g's loupe: while the fine-aim wheel is held, a round magnifier, LOUPE_MAG times, over the ghost-ball contact: the
     table behind it, the balls, the aim line, the ghost ring and the object ball's line drawn again at the larger scale;
     off the contact, inside the table, keeping off the lines and balls, leaning to the middle, kept while it fits and
     gliding (LOUPE_GLIDE_MS) when it must move; it fades in and out over LOUPE_FADE_MS */
  static let LOUPE_MAG = 3.0, LOUPE_FADE_MS = 90.0, LOUPE_GLIDE_MS = 60.0
  func loupeStep(_ m: Mapper) -> (L: (x: Double, y: Double, r: Double), a: Double, C: CGPoint, h: AimHit, P: FeltSim.Preview)? {
    let s = model.sim, a0 = m.pt(0, 0), b0 = m.pt(s.TL, s.TW)
    return loupeStep(pt: { m.pt($0, $1) }, rect: (Double(min(a0.x, b0.x)), Double(max(a0.x, b0.x)), Double(min(a0.y, b0.y)), Double(max(a0.y, b0.y))), rp: s.BALL_R * m.k)
  }
  /* pt: table to screen (top-down the fitted view, in 3D the camera); rect: [left, right, top, bottom] it must stay inside */
  func loupeStep(pt: (Double, Double) -> CGPoint, rect: (Double, Double, Double, Double), rp: Double) -> (L: (x: Double, y: Double, r: Double), a: Double, C: CGPoint, h: AimHit, P: FeltSim.Preview)? {
    let now = model.now * 1000
    let gi = model.guideMode == "off" ? nil : model.guide()
    let on = gi != nil && model.rolling == nil && !model.cpuTurn && model.fineAim
    let dt = model.loupeT > 0 ? min(100, max(0, now - model.loupeT)) : 16
    model.loupeT = now
    model.loupeA = on ? min(1, model.loupeA + dt / Self.LOUPE_FADE_MS) : max(0, model.loupeA - dt / Self.LOUPE_FADE_MS)
    if !on { if model.loupeA == 0 { model.loupe = nil }; if gi == nil || model.loupeA == 0 { return nil } }
    guard let (h, P) = gi, let c = model.cue else { return nil }
    let tl = rect.0, tr = rect.1, tt = rect.2, tb = rect.3
    let r = min(72, max(56, min(tr - tl, tb - tt) * 0.2))
    let dx = JSMath.cos(model.aim), dy = JSMath.sin(model.aim), C = pt(c.x + dx * h.t, c.y + dy * h.t), cue = pt(c.x, c.y)
    var lines: [(CGPoint, CGPoint, Double)] = [(cue, C, 8)]
    if let o = P.obj, o.count > 1 { for i in 1..<o.count { lines.append((pt(o[i - 1][0], o[i - 1][1]), pt(o[i][0], o[i][1]), 4)) } }
    if P.cue.count > 1 { for i in 1..<P.cue.count { lines.append((pt(P.cue[i - 1][0], P.cue[i - 1][1]), pt(P.cue[i][0], P.cue[i][1]), 2)) } }
    let balls = model.balls.filter { $0.on }.map { b -> (CGPoint, Double) in (pt(b.x, b.y), b.n == model.cueN ? 16 : 1) }
    /* loupePlace */
    let mx = (tl + tr) / 2, my = (tt + tb) / 2, mg = 4.0, cx = Double(C.x), cy = Double(C.y)
    func seg(_ x: Double, _ y: Double, _ a: CGPoint, _ b: CGPoint) -> Double {
      let ax = Double(a.x), ay = Double(a.y), bx = Double(b.x), by = Double(b.y), l2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
      let t = l2 > 0 ? min(1, max(0, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / l2)) : 0
      return JSMath.hypot(x - (ax + (bx - ax) * t), y - (ay + (by - ay) * t))
    }
    func fits(_ x: Double, _ y: Double) -> Bool { x - r >= tl - mg && x + r <= tr + mg && y - r >= tt - mg && y + r <= tb + mg && JSMath.hypot(x - cx, y - cy) > r * 1.25 }
    func cost(_ x: Double, _ y: Double) -> Double {
      var k = 0.0
      for l in lines where seg(x, y, l.0, l.1) < r + 6 { k += l.2 }
      for b in balls where JSMath.hypot(x - Double(b.0.x), y - Double(b.0.y)) < r + rp { k += b.1 }
      return k
    }
    let prev = model.loupe?.to
    var to: (x: Double, y: Double, r: Double)
    let was = prev.map { p in abs(p.r - r) < 0.5 && fits(p.x, p.y) ? cost(p.x, p.y) : Double.infinity } ?? .infinity
    if was == 0, let p = prev { to = p } else {
      var best: (x: Double, y: Double, r: Double)? = nil, bs = Double.infinity, bc = Double.infinity
      for d in [1.45, 1.9, 2.5, 3.2] { for i in 0..<24 {
        let ang = Double(i) * Double.pi / 12, x = cx + cos(ang) * r * d, y = cy + sin(ang) * r * d
        if !fits(x, y) { continue }
        let k = cost(x, y), sc = k * 1000 + JSMath.hypot(x - mx, y - my) + d * r * 0.3
        if sc < bs { bs = sc; bc = k; best = (x, y, r) }
      } }
      if let p = prev, was <= bc { to = p } else if let b = best { to = b } else {
        let pl = tr - tl > tb - tt
        to = (pl ? (cx < mx ? (mx + tr) / 2 : (tl + mx) / 2) : mx, pl ? my : (cy < my ? (my + tb) / 2 : (tt + my) / 2), r)
      }
    }
    if model.loupe == nil || model.loupeA <= dt / Self.LOUPE_FADE_MS { model.loupe = (to.x, to.y, r, to) }
    else { let L = model.loupe!, u = 1 - exp(-dt / Self.LOUPE_GLIDE_MS); model.loupe = (L.x + (to.x - L.x) * u, L.y + (to.y - L.y) * u, r, to) }
    let L = model.loupe!, A = model.loupeA
    return ((L.x, L.y, L.r), A * A * (3 - 2 * A), C, h, P)
  }
  private func drawLoupe(_ ctx: inout GraphicsContext, _ m: Mapper, _ bp: BallPainter) {
    guard let st = loupeStep(m), let c = model.cue else { return }
    let s = model.sim, R = s.BALL_R, rp = R * m.k, M = Self.LOUPE_MAG, L = st.L, C = st.C, sc = model.scaleFactor
    func at(_ x: Double, _ y: Double) -> CGPoint { let p = m.pt(x, y); return CGPoint(x: L.x + Double(p.x - C.x) * M, y: L.y + Double(p.y - C.y) * M) }
    var g = ctx
    g.opacity = st.a
    let lens = Path(ellipseIn: CGRect(x: L.x - L.r, y: L.y - L.r, width: 2 * L.r, height: 2 * L.r))
    /* a soft shadow under it, the cloth, then everything inside clipped to it */
    var sh = g; sh.addFilter(.shadow(color: .black.opacity(0.55), radius: 7, x: 0, y: 3)); sh.fill(lens, with: .color(look.cloth))
    g.clip(to: lens)
    if let img = model.tableImage {
      var t = g
      t.translateBy(x: L.x - Double(C.x) * M, y: L.y - Double(C.y) * M); t.scaleBy(x: M, y: M)
      t.draw(Image(decorative: img.image, scale: img.scale), in: CGRect(origin: .zero, size: img.size))
    }
    /* the balls near the contact */
    let reach = L.r / M + 2 * rp, gb = gameBall
    for b in model.balls where b.on {
      let p = m.pt(b.x, b.y)
      if JSMath.hypot(Double(p.x - C.x), Double(p.y - C.y)) > reach { continue }
      let q = at(b.x, b.y), X = Double(q.x) * sc, Y = Double(q.y) * sc, Rr = rp * M * sc
      var d = g; d.scaleBy(x: 1 / sc, y: 1 / sc)
      for (img, rect, a) in bp.castParts(b.x, b.y, X, Y, Rr, tl: s.TL, tw: s.TW, ballR: R, z: 0) { var cc = d; cc.opacity = a * st.a; cc.draw(Image(decorative: img, scale: 1), in: rect) }
      if b.n == gb { drawHalo(Sink2D(ctx: g, m: m), q, rp * M) }
      let (img, ix, iy) = bp.ballImage(b.n, X, Y, Rr, bp.axesOf(model.orient[b.n] ?? IDENT))
      d.draw(Image(decorative: img, scale: 1), in: CGRect(x: ix, y: iy, width: Double(img.width), height: Double(img.height)))
    }
    /* the lines, a little heavier than on the table but not three times */
    let ov = look.ovMin, wa = { (a: Double) in Color.white.opacity(max(a, ov)) }
    func line(_ pts: [[Double]], _ col: Color, _ w: Double, _ dash: [CGFloat] = []) {
      var p = Path(); for (i, q) in pts.enumerated() { i == 0 ? p.move(to: at(q[0], q[1])) : p.addLine(to: at(q[0], q[1])) }
      g.stroke(p, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: w + 2.5, lineCap: .round, lineJoin: .round, dash: dash))
      g.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: dash))
    }
    let dx = JSMath.cos(model.aim), dy = JSMath.sin(model.aim), gx = c.x + dx * st.h.t, gy = c.y + dy * st.h.t, legal = model.guideLegal
    if st.h.t > 2 * R { line([[c.x + dx * R, c.y + dy * R], [gx - dx * R, gy - dy * R]], wa(0.6), 1.75) }
    if let o = st.P.obj, o.count > 1 {
      var d = R, ot: [[Double]] = []
      for i in 1..<o.count {
        let a = o[i - 1], b = o[i], l = JSMath.hypot(b[0] - a[0], b[1] - a[1])
        if l > d { ot = [[a[0] + (b[0] - a[0]) * d / l, a[1] + (b[1] - a[1]) * d / l]] + o[i...]; break }
        d -= l
      }
      if ot.count > 1 { line(ot, .white.opacity(0.92), 2.5) }
    }
    if st.P.cue.count > 1 { line(st.P.cue, wa(0.55), 2, [7, 6]) }
    let q = at(gx, gy), ring = Path(ellipseIn: CGRect(x: q.x - rp * M, y: q.y - rp * M, width: 2 * rp * M, height: 2 * rp * M))
    g.fill(ring, with: .color(.white.opacity(0.08))); g.stroke(ring, with: .color(legal ? .white.opacity(0.92) : look.illegal), lineWidth: 2)
    /* the contact point itself */
    if st.h.kind == "ball", let hb = st.h.ball {
      let k = at(gx + (hb.x - gx) / 2, gy + (hb.y - gy) / 2)
      g.fill(Path(ellipseIn: CGRect(x: k.x - 2.25, y: k.y - 2.25, width: 4.5, height: 4.5)), with: .color(legal ? .white : look.illegal))
    }
    /* the rim: a thin bright ring over a dark one */
    var rim = ctx; rim.opacity = st.a
    rim.stroke(Path(ellipseIn: CGRect(x: L.x - L.r - 0.5, y: L.y - L.r - 0.5, width: 2 * L.r + 1, height: 2 * L.r + 1)), with: .color(.black.opacity(0.45)), lineWidth: 3)
    rim.stroke(lens, with: .color(.white.opacity(0.85)), lineWidth: 1.25)
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
      let u = (now - p.t) / model.potMs, P = s.POCKETS[p.k], m1 = 1 - pow(1 - min(1, u / 0.5), 2), sink = ease(0.15, 1, u)
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
  /* row: the 3D view's (placeRail when V3.live): the stage's bottom row (V3_PIN_B up from its foot), its gaps the stage's
     width less every pocket (hole, jaws) and sight as the camera projects them */
  func drawRail(_ ctx: inout GraphicsContext, _ m: Mapper, _ bp: BallPainter, row: (y: Double, width: Double, C: V3.Cam, box: V3.Box)? = nil) {
    /* a party of three or four: the cards in the pause menu and the handoff carry the scores (the rail's .many chips are
       not ported) */
    guard let g = model.g, g.winner == nil, (model.party?.names.count ?? 2) <= 2 else { return }
    let s = model.sim, T = model.potGeometry(m), band = T.railBand
    let ink = Color(.sRGB, red: 0xef / 255.0, green: 0xe7 / 255.0, blue: 0xda / 255.0), edge = Color(.sRGB, red: 20 / 255, green: 8 / 255, blue: 3 / 255, opacity: 0.85)
    let mid = -(band.co + band.rail) / 2   /* the band's middle, metres out from the nose */
    /* the rail's run on screen: along y (upright, the head rail at x = 0) or along x (on its side, the rail at y = TW) */
    func at(_ u: Double) -> CGPoint { row.map { CGPoint(x: u, y: $0.y) } ?? (m.upright ? m.pt(mid, u) : m.pt(u, s.TW - mid)) }
    /* the pill's height: the wood's, but never under Caption 2's 11 pt (--rf), as the page widens slim wood to WOOD_MIN;
       in 3D the row's 22 */
    /* --ph: the wood band less 2 px, 11 to 22 (placeRail); in 3D the row's 22. The next ball (nextBallEl) is --ph tall,
       a pip or a group's glyph smaller */
    let ph = row != nil ? 22 : Swift.min(22, Swift.max(11, ((band.rail - band.co) * m.k - 2).rounded(.down))), dot = Swift.min(12, ph * 0.62)
    /* the gaps: the rail's span less every pocket (hole, jaws) and sight, with their pads */
    let len = row?.width ?? (m.upright ? s.TW : s.TL)
    var spans: [[Double]] = row != nil ? [[6, len - 6]] : [[0, len]]
    var holes: [[Double]] = []
    if let r = row {
      /* railHoles through the camera: each pocket's box at the bed (RAIL_PAD 4), each sight's at the cushion tops
         (SIGHT_PAD 1), those reaching the row (22 either side of its middle) */
      func box(_ pts: [[Double]], _ z: Double, _ pad: Double) {
        let q = pts.compactMap { V3.proj(r.C, r.box, $0[0], $0[1], z) }
        if q.count < pts.count { return }
        let ys = q.map { $0[1] }
        if ys.max()! < r.y - 22 || ys.min()! > r.y + 22 { return }
        holes.append([q.map { $0[0] }.min()! - pad, q.map { $0[0] }.max()! + pad])
      }
      for (i, p) in s.POCKETS.enumerated() {
        let rr = s.POCKET_R[i]
        var pts = [[p[0] - rr, p[1]], [p[0] + rr, p[1]], [p[0], p[1] - rr], [p[0], p[1] + rr]]
        if s.MOUTHS.indices.contains(i) { for j in s.MOUTHS[i] { pts.append(j.p); pts.append(j.e) } }
        box(pts, 0, 4)
      }
      for q in T.railSights() { box([[q[0] - q[2], q[1] - q[3]], [q[0] + q[2], q[1] - q[3]], [q[0] + q[2], q[1] + q[3]], [q[0] - q[2], q[1] + q[3]]], s.BALL_R * (1 + NOSE_S), 1) }
    } else {
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
    }
    for h in holes { spans = spans.flatMap { [[$0[0], Swift.min($0[1], h[0])], [Swift.max($0[0], h[1]), $0[1]]] }.filter { $0[1] - $0[0] > 0.01 } }
    /* placeRail: the row's items placed in the gaps (rail units: metres top-down, points in 3D), each kept RAIL_GAP (6 pt)
       from the others: the seats first (player 1 the gap nearest the rail's middle on its left, player 2 on its right; a
       gap across the middle gives each its half, the two meeting at the middle), snooker's scoreboard beside the player
       to shoot, then the 3D switch (its whole 44 pt target where a gap has it, else its glyph) nearest its gap's middle,
       in the first gap from the left with room */
    let unit = row != nil ? 1.0 : 1 / m.k, G = 6 * unit, rmid = len / 2
    var used: [[Double]] = []
    func free(_ g: [Double]) -> [[Double]] {
      used.reduce([g]) { f, u in f.flatMap { [[$0[0], Swift.min($0[1], u[0] - G)], [Swift.max($0[0], u[1] + G), $0[1]]] }.filter { $0[1] - $0[0] > unit } }
    }
    func fitIn(_ g: [Double], _ w: Double) -> Double? {
      let c = (g[0] + g[1]) / 2
      var best: Double? = nil
      for f in free(g) where f[1] - f[0] >= w { let x = Swift.min(Swift.max(c, f[0] + w / 2), f[1] - w / 2); if best == nil || abs(x - c) < abs(best! - c) { best = x } }
      return best
    }
    func seatAt(_ w: Double, left: Bool) -> Double? {
      var best: (x: Double, d: Double)? = nil
      for g in spans { for f in free(g) {
        let a = left ? f[0] : Swift.max(f[0], rmid + G / 2), b = left ? Swift.min(f[1], rmid - G / 2) : f[1]
        if b - a < w { continue }
        let across = g[0] < rmid && g[1] > rmid, c = (g[0] + g[1]) / 2
        let x = across ? (left ? b - w / 2 : a + w / 2) : Swift.min(Swift.max(c, a + w / 2), b - w / 2), d = abs(x - rmid)
        if best == nil || d < best!.d { best = (x, d) }
      } }
      return best?.x
    }
    /* hudSolo: practice has no seats; a trick shot and a drill one, lit, its number engraved: the try ("Try 3") or the
       shot of how many ("Shot 2/4") */
    let soloNum: String? = g.mode == "trick" ? model.trick.map { String($0.attempts + (model.trickRes == nil ? 1 : 0)) }
      : g.mode == "drill" ? model.drill.flatMap { D in drillById(D.id).map { "\(min(D.js.count + (D.beat || model.drillRes != nil ? 0 : 1), $0.shots))/\($0.shots)" } } : nil
    let seatList: [Int] = g.mode == "practice" || model.tut != nil ? [] : soloNum != nil ? [0] : [0, 1]
    let next = model.railNext()
    let font = Font.system(size: Swift.max(11, Swift.min(13, ph * 0.62)), weight: .bold, design: .rounded).monospacedDigit()
    /* each seat's items (chipOf) and their widths (pt) */
    var seatItems: [Int: [(kind: String, n: Int, text: String)]] = [:], seatW: [Int: [Double]] = [:]
    for p in seatList {
      let lit = p == g.turn || soloNum != nil
      var items: [(kind: String, n: Int, text: String)] = []
      if let t = soloNum { items.append(("num", 0, t)) } else {
      let on = g.balls.filter { $0.on && $0.n > 0 }.map { $0.n }.sorted()
      let nx = lit ? next : nil
      switch g.kind {
      case "snooker": items.append(("num", 0, String(g.score![p])))
      case "bumper":
        /* chipOf: the first of the player's balls still up, and how many */
        let mine = on.filter { bOwner($0) == p }
        if let f = mine.first { items.append(("dot", f, "")) }
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
      }
      if items.isEmpty { items.append(("pip", 0, "")) }
      seatItems[p] = items
      seatW[p] = items.map { it -> Double in it.kind == "num" || it.kind == "of" ? Double(ctx.resolve(Text(it.text).font(font)).measure(in: CGSize(width: 200, height: 100)).width) : it.kind == "ball" ? ph : it.kind == "dot" ? Swift.min(10, ph - 3) : Swift.min(10, ph - 3) - 2 }
    }
    let ig = 4.0
    func total(_ p: Int) -> Double { let w = seatW[p] ?? []; return w.reduce(0, +) + ig * Double(Swift.max(0, w.count - 1)) + 4 }
    var seatX: [Int: Double] = [:]
    for p in seatList {
      let w = total(p) * unit
      if let x = seatAt(w, left: p == 0) { seatX[p] = x; used.append([x - w / 2, x + w / 2]) }
    }
    /* snooker's scoreboard: the ball on (two with a free ball), the break while one runs; beside the shooter's seat */
    var snkDots: [Int] = [], snkX: Double? = nil
    let sdot = Swift.min(10, ph - 3)
    if g.kind == "snooker", let S = g.snk {
      if let f = S.free { snkDots = S.on == .red ? [41, f] : [f] }
      else { switch S.on { case .red: snkDots = [41]; case .colour: snkDots = S_COLS.filter { c in g.balls.contains { $0.n == c && $0.on } }; case .ball(let b): snkDots = [b]; case .none: snkDots = [] } }
      /* numRoll(e, 'snkBreak', val): the break rolls up as it grows (asked at 0 too, as the page's bar keeps it) */
      let brkS = NumRoll.text("snkBreak", String(S.brk))
      let brkW = S.brk > 0 ? Double(ctx.resolve(Text(String(S.brk)).font(font)).measure(in: CGSize(width: 200, height: 100)).width) + ig : 0
      let w = (Double(snkDots.count) * (sdot + 2) + brkW + 4) * unit
      if !snkDots.isEmpty || S.brk > 0, let sx = seatX[g.turn] ?? seatX[0] {
        var best: Double? = nil
        for gp in spans { for f in free(gp) where f[1] - f[0] >= w { let x = Swift.min(Swift.max(sx, f[0] + w / 2), f[1] - w / 2); if best == nil || abs(x - sx) < abs(best! - sx) { best = x } } }
        if let x = best { snkX = x; used.append([x - w / 2, x + w / 2]) }
      }
      if let x = snkX {
        var cx = Double(at(x).x) - w / unit / 2 + 2, cy = Double(at(x).y)
        for n in snkDots {
          let r = sdot / 2 * model.scaleFactor, (img, ix, iy) = bp.ballImage(n, (cx + sdot / 2) * model.scaleFactor, cy * model.scaleFactor, r, bp.axesOf(IDENT, screen: true))
          ctx.draw(Image(decorative: img, scale: model.scaleFactor), in: CGRect(x: ix / model.scaleFactor, y: iy / model.scaleFactor, width: Double(img.width) / model.scaleFactor, height: Double(img.height) / model.scaleFactor))
          cx += sdot + 2
        }
        if S.brk > 0 {
          var e = ctx; e.addFilter(.shadow(color: edge, radius: 0.7))
          let t = ctx.resolve(Text(brkS).font(font).foregroundColor(ink))
          e.draw(t, at: CGPoint(x: cx + ig, y: cy), anchor: .leading)
        }
        _ = cy
      }
    }
    /* #viewBtn (v3Btn, placeRail's side(viewBtn, left)): the 3D switch, a cube inlaid in the rail, bright while 3D is on;
       shown in a game, never in the lesson */
    model.railSwitch = nil
    if model.lesson == nil {
      let gl = Swift.min(16, ph + 1)
      var sx: Double? = nil
      outer: for gp in spans { for w in [44.0, gl + 4] { if let x = fitIn(gp, w * unit) { sx = x; used.append([x - w * unit / 2, x + w * unit / 2]); break outer } } }
      if let x = sx {
        let c = at(x), on = model.view3d
        model.railSwitch = c
        var e = ctx
        e.opacity = on ? 1 : 0.78
        e.addFilter(.shadow(color: edge, radius: 0.7))
        if on { e.addFilter(.shadow(color: Color(.sRGB, red: 1, green: 236 / 255, blue: 190 / 255, opacity: 0.75), radius: 3)) }
        let k = gl / 24, o = CGPoint(x: c.x - gl / 2, y: c.y - gl / 2)
        func P(_ pts: [(Double, Double)]) -> Path { var p = Path(); for (i, q) in pts.enumerated() { let v = CGPoint(x: o.x + q.0 * k, y: o.y + q.1 * k); i == 0 ? p.move(to: v) : p.addLine(to: v) }; p.closeSubpath(); return p }
        e.fill(P([(12, 2.5), (21, 7.5), (12, 12.5), (3, 7.5)]), with: .color(ink))
        e.fill(P([(3, 7.5), (12, 12.5), (12, 22), (3, 17)]), with: .color(ink.opacity(0.72)))
        e.fill(P([(21, 7.5), (12, 12.5), (12, 22), (21, 17)]), with: .color(ink.opacity(0.5)))
      }
    }
    for p in seatList {
      guard let sx = seatX[p], let items = seatItems[p], let widths = seatW[p] else { continue }
      let lit = p == g.turn || soloNum != nil
      let tot = total(p) - 4
      let c0 = at(sx)
      var g2 = ctx
      g2.opacity = lit ? 1 : 0.78
      if lit { g2.addFilter(.shadow(color: Color(.sRGB, red: 1, green: 236 / 255, blue: 190 / 255, opacity: 0.75), radius: 3)) }
      var x = Double(c0.x) - tot / 2
      for (i, it) in items.enumerated() {
        let w = widths[i], cx = x + w / 2, cy = Double(c0.y)
        switch it.kind {
        case "ball": drawNB(&g2, bp, it.n, CGPoint(x: cx, y: cy), ph, inset: 0.19)
        case "dot":
          /* .pchip .dot: the ball's colour, --dot across, cut dark round its edge */
          let col = bp.flatOf(it.n).col, rect = CGRect(x: cx - w / 2, y: cy - w / 2, width: w, height: w)
          g2.fill(Path(ellipseIn: rect), with: .color(Color(rgb: Int(col[0]), Int(col[1]), Int(col[2]))))
          g2.stroke(Path(ellipseIn: rect.insetBy(dx: -0.5, dy: -0.5)), with: .color(edge), lineWidth: 1)
        case "grp":
          let rect = CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot), disc = Path(ellipseIn: rect)
          g2.stroke(disc, with: .color(edge), lineWidth: 1.5)
          if it.n == 0 { g2.fill(disc, with: .color(ink)) }
          else {
            var c = g2; c.clip(to: disc)
            c.fill(Path(rect), with: .color(ink)); c.fill(Path(CGRect(x: rect.minX, y: cy - dot * 0.22, width: dot, height: dot * 0.44)), with: .color(edge))
          }
        case "pip":
          /* .pip: --dot less 2 across, a 1.5 px ink ring inside, cut dark inside and out */
          let pd = Swift.min(10, ph - 3) - 2, pr = CGRect(x: cx - pd / 2, y: cy - pd / 2, width: pd, height: pd)
          g2.stroke(Path(ellipseIn: pr.insetBy(dx: -0.5, dy: -0.5)), with: .color(edge), lineWidth: 1)
          g2.stroke(Path(ellipseIn: pr.insetBy(dx: 1.75, dy: 1.75)), with: .color(edge), lineWidth: 1)
          g2.stroke(Path(ellipseIn: pr.insetBy(dx: 0.75, dy: 0.75)), with: .color(ink), lineWidth: 1.5)
        default:
          /* carom's points are engraved like the others (the seats tell the players apart), then the race */
          /* numRoll(t, 'chip' + p, c.num): a seat's number rolls up as it rises */
          let t = Text(it.kind == "num" ? NumRoll.text("chip\(p)", it.text) : it.text).font(it.kind == "of" ? Font.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit() : font).foregroundColor(ink)
          var e = g2; e.addFilter(.shadow(color: edge, radius: 0.7))
          e.draw(t, at: CGPoint(x: cx, y: cy))
        }
        x += w + ig
      }
    }
  }

  /* nextBallEl (.dot.nb): the ball to play as a true little ball, flat: the set's colour (a stripe's ivory caps, 21% top
     and bottom), cut dark round its edge with a soft shade at its foot, its number in heavy type (half its height) on the
     ivory circle (inset 19%; the potted windows' 21%); two digits drawn condensed (scaleX .8) to sit at the one-digit size */
  func drawNB(_ ctx: inout GraphicsContext, _ bp: BallPainter, _ n: Int, _ c: CGPoint, _ d: Double, inset: Double, pot: Bool = false, numOff: CGSize = .zero, numSc: CGSize = CGSize(width: 1, height: 1)) {
    let (col, iv) = bp.flatOf(n), C = Color(rgb: Int(col[0]), Int(col[1]), Int(col[2])), I = css(iv)
    let r = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d), disc = Path(ellipseIn: r)
    var g = ctx
    g.clip(to: disc)
    if n > 8 && n <= 15 {
      g.fill(Path(r), with: .color(I))
      g.fill(Path(CGRect(x: r.minX, y: r.minY + d * 0.21, width: d, height: d * 0.58)), with: .color(C))
    } else { g.fill(Path(r), with: .color(C)) }
    if !pot {
      /* inset -1px -2px 2px rgba(0,0,0,.28): the shade at its lower right; inset 1px the inlay's dark edge */
      g.stroke(Path(ellipseIn: r.offsetBy(dx: 1, dy: 2).insetBy(dx: -1, dy: -1)), with: .color(.black.opacity(0.28)), lineWidth: 3.5)
      g.stroke(disc, with: .color(Color(.sRGB, red: 25 / 255, green: 10 / 255, blue: 4 / 255, opacity: 0.6)), lineWidth: 2)
    }
    let ir = r.insetBy(dx: d * inset, dy: d * inset)
    /* .cb: with marks on, the mark's badge in place of the number's circle (dark or light, its words in the other) */
    let mk = bp.marks ? BallPainter.markOf(n) : nil
    let face = mk.map { $0.1 ? Color(rgb: 0x14, 0x14, 0x14) : I } ?? I, ink = mk.map { $0.1 ? I : Color(rgb: 0x14, 0x14, 0x14) } ?? Color(rgb: 0x14, 0x14, 0x14)
    /* the number's circle moved (the roll in: translate, then scale about its centre) */
    var gn = g
    if numOff != .zero || numSc != CGSize(width: 1, height: 1) {
      gn.translateBy(x: c.x + numOff.width, y: c.y + numOff.height); gn.scaleBy(x: numSc.width, y: numSc.height); gn.translateBy(x: -c.x, y: -c.y)
    }
    gn.fill(Path(ellipseIn: ir), with: .color(face))
    var t = gn
    let word = mk?.0 ?? String(n)
    if word.count > 1 { t.translateBy(x: c.x, y: c.y); t.scaleBy(x: 0.8, y: 1); t.translateBy(x: -c.x, y: -c.y) }
    t.draw(Text(word).font(.system(size: d * (pot ? 0.46 : 0.5), weight: .heavy)).foregroundColor(ink), at: c)
    if pot {
      /* #potRail .nb::after, the lamp's light: a highlight up and to the left, the far side in shade (CSS radial
         gradients reach the box's farthest corner); its edge inset .5px rgba(0,0,0,.45) */
      func far(_ fx: Double, _ fy: Double) -> Double { let x = max(fx, 1 - fx) * d, y = max(fy, 1 - fy) * d; return (x * x + y * y).squareRoot() }
      let h = CGPoint(x: r.minX + d * 0.34, y: r.minY + d * 0.28), hr = far(0.34, 0.28)
      g.fill(Path(r), with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.62), location: 0), .init(color: .white.opacity(0.14), location: 0.16), .init(color: .white.opacity(0), location: 0.34)]), center: h, startRadius: 0, endRadius: hr))
      let sh = CGPoint(x: r.minX + d * 0.42, y: r.minY + d * 0.38), sr = far(0.42, 0.38)
      g.fill(Path(r), with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(0), location: 0.52), .init(color: .black.opacity(0.42), location: 1)]), center: sh, startRadius: 0, endRadius: sr))
      g.stroke(disc, with: .color(.black.opacity(0.45)), lineWidth: 1)
    }
  }

  /* 6b3: the potted balls, each in a window of its own in the wood of the rails at the screen's left and right
     (potPlan's slots: the gaps between the holes and sights, packed for POT_PER_RAIL, filling from the foot), 8-ball's
     solids up the left and stripes up the right, the 8 up its potter's group's side; 9 and 10-ball in pot order up the
     left, then the right. A dark recess (POT_RECESS) cut dark round its edge, the rail's true little ball in it, a rim
     of light on a ball under 3:1 on the recess. live: the 3D view's camera and the rail row's top (potPlace): the
     windows on the long rails, each its slot on the rail top projected, none on the row or off the stage, faded where
     the cue, the loupe or a ball lies over it (potCovered). */
  func drawPotRail(_ ctx: inout GraphicsContext, _ m: Mapper, _ bp: BallPainter, live: (C: V3.Cam, box: V3.Box, rowTop: Double)? = nil) {
    /* potGame: a game with no mode, or practice; never a trick shot or a drill */
    guard let g = model.g, !model.potOrder.isEmpty, g.mode == nil || g.mode == "practice", model.tut == nil else { return }
    let s = model.sim, T = model.potGeometry(m), band = T.railBand
    /* potPlan: the slots, packed for POT_PER_RAIL between the holes (RAIL_PAD) and sights (POT_SIGHT_PAD) */
    let P = PotRail.plan(s, k: m.k, ox: m.ox, oy: m.oy, portrait: m.upright, live: live != nil, rail: band.rail, co: band.co, sights: T.railSights())
    let sides = P.sides
    /* potSeats */
    var seats: [(Int, PotRail.Slot)] = []
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
    /* 3D: what may lie over a window (the cue as last drawn, the loupe while shown, the balls on the table) */
    let cueLen = CueGeo.of(game: model.game.table.2).len, now = model.now
    let lp = model.loupeA > 0.02 ? model.loupe.map { (x: $0.x, y: $0.y, r: $0.r) } : nil
    let onTable = live == nil ? [] : (model.rolling?.balls ?? model.balls).filter { $0.on }.map { (x: $0.x, y: $0.y, z: $0.z ?? 0) }
    let recess = Color(rgb: 16, 11, 8), edge = Color(.sRGB, red: 20 / 255, green: 8 / 255, blue: 3 / 255, opacity: 0.85), f = model.scaleFactor
    for (n, slot) in seats {
      if let t = model.potAt[n], model.now < t { continue }   /* still dropping into its pocket */
      var c = CGPoint(x: slot.x, y: slot.y), sz = P.s, ballD = P.ball, ctx = ctx
      /* the roll in starts the first time the window shows (one with no place then never rolls in) */
      let due = model.potSlideDue.remove(n) != nil
      if let L = live {
        guard let f = PotRail.place(P, slot, L.C, L.box, z: s.cushionTop()) else { model.potHid[n] = nil; continue }
        c = CGPoint(x: f[0], y: f[1]); sz = f[2]; ballD = Swift.max(5, (sz * P.ball / P.s).rounded())
        let r = sz / 2, cut = f[1] + r > L.rowTop - 2 || f[0] - r < 0 || f[0] + r > L.box.width || f[1] - r < 0
        let hid = cut || PotRail.covered(f[0], f[1], r, loupe: lp, cue: model.potCue, cueLen: cueLen, balls: onTable, L.C, L.box, R: s.BALL_R)
        /* .hid: opacity 0 over .12s */
        let h = model.potHid[n] ?? (a: hid ? 0 : 1, t: now), u = Swift.min(1, Swift.max(0, now - h.t) / 0.12), a = hid ? Swift.max(0, h.a - u) : Swift.min(1, h.a + u)
        model.potHid[n] = (a, now)
        if a <= 0.001 { continue }
        ctx.opacity = a
      }
      if due { model.potSlideT[n] = now }
      /* the roll in: up the rail from the window below (u the rail's up on the screen: top-down straight up, in 3D the
         slot's up projected), its number coming round to the front, the window fading in; cut by the window */
      var bc = c, numOff = CGSize.zero, numSc = CGSize(width: 1, height: 1)
      let sl = model.potSlideT[n].flatMap { PotRail.slide((now - $0) * 1000) }
      if let sl {
        var u = [0.0, -1]
        if let L = live, let a = V3.proj(L.C, L.box, slot.t[0], slot.t[1], s.cushionTop()), let b = V3.proj(L.C, L.box, slot.t[0] + P.up[0] * 0.05, slot.t[1] + P.up[1] * 0.05, s.cushionTop()) {
          let h = hypot(b[0] - a[0], b[1] - a[1]), l = h != 0 ? h : 1
          u = [(b[0] - a[0]) / l, (b[1] - a[1]) / l]
        }
        let k = 1 - sl.e, d = sz + PotRail.GAP, q = 1 - 0.45 * k
        bc = CGPoint(x: c.x - u[0] * d * k, y: c.y - u[1] * d * k)
        numOff = CGSize(width: -u[0] * ballD * 0.32 * k, height: -u[1] * ballD * 0.32 * k)
        numSc = abs(u[0]) > 0.5 ? CGSize(width: q, height: 1) : CGSize(width: 1, height: q)
        ctx.opacity = sl.a   /* the animation's opacity stands in for .hid's while it runs */
      } else { model.potSlideT[n] = nil }
      let rr = CGRect(x: c.x - sz / 2, y: c.y - sz / 2, width: sz, height: sz)
      ctx.fill(Path(ellipseIn: rr), with: .color(recess))
      ctx.stroke(Path(ellipseIn: rr), with: .color(edge), lineWidth: 1)
      if sl != nil { ctx.clip(to: Path(ellipseIn: rr)) }
      drawNB(&ctx, bp, n, bc, ballD, inset: 0.21, pot: true, numOff: numOff, numSc: numSc)
      /* a ball too dark for the recess (a solid under 3:1 on it) gets a rim of light */
      let col = ballColor(n), lum = { (v: Int) -> Double in let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
      let L1 = 0.2126 * lum(col.0) + 0.7152 * lum(col.1) + 0.0722 * lum(col.2), L2 = 0.2126 * lum(16) + 0.7152 * lum(11) + 0.0722 * lum(8)
      if n < 9 && (max(L1, L2) + 0.05) / (min(L1, L2) + 0.05) < 3 {
        /* .rim: box-shadow 0 0 0 1px #77716b, a hairline of light just outside the ball */
        let br = ballD / 2 + 0.5
        ctx.stroke(Path(ellipseIn: CGRect(x: bc.x - br, y: bc.y - br, width: 2 * br, height: 2 * br)), with: .color(Color(rgb: 0x77, 0x71, 0x6b)), lineWidth: 1)
      }
    }
  }

  /* 5c drawCall: the called ball (a ring) and pocket (a pulsing glow and a ring) until the shot: the player's call while
     aiming, the CPU's in its plan; an obvious (auto) call a little fainter */
  func drawCall(_ pen: OverlayPen, _ m: Mapper) {
    guard let c = model.cpuTurn ? model.g?.call : model.humanCall(), let n = c.ball, model.rolling == nil else { return }
    let s = model.sim, rp0 = s.BALL_R * m.k, w = max(2, rp0 * 0.12), col = look.call
    defer { pen.alpha = 1 }
    pen.alpha = c.auto ? 0.8 : 1
    if let b = model.balls.first(where: { $0.n == n && $0.on }) { pen.circle(m.pt(b.x, b.y), rp0 + 2 + w / 2, col, w, dash: []) }
    if let k = c.pocket, k < s.POCKETS.count {
      let P = s.POCKETS[k], p = m.pt(P[0], P[1]), r = s.POCKET_R[k] * m.k, pulse = 0.5 + 0.5 * sin(model.now * 1000 / 320)
      pen.alpha = (c.auto ? 0.35 : 0.5) + 0.15 * pulse
      pen.glow(p, r * 0.4, r * 1.9, col)
      pen.alpha = c.auto ? 0.8 : 1
      pen.circle(p, r * 1.15, col, w, dash: [])
    }
  }
}

/* the overlays' pen: draw()'s calls in the view's CSS pt (the Mapper's), so one drawing serves the 2D canvas and the 3D
   view's recorder (4o's V3R: each point back to table metres through the flat mapping, a stroke a ribbon of the same
   width, a fill triangles, a gradient evaluated per vertex). alpha: the context's globalAlpha */
protocol OverlayPen: AnyObject {
  var alpha: Double { get set }
  func stroke(_ pts: [CGPoint], closed: Bool, _ col: Color, _ w: Double, dash: [CGFloat], round: Bool)
  func circle(_ c: CGPoint, _ r: Double, _ col: Color, _ w: Double, dash: [CGFloat])
  func fill(_ pts: [CGPoint], _ col: Color)
  func fillCircle(_ c: CGPoint, _ r: Double, _ col: Color)
  /* a disc of radius r1 filled with a radial gradient, col at r0 to clear at r1 */
  func glow(_ c: CGPoint, _ r0: Double, _ r1: Double, _ col: Color)
}

/* where the guide is drawn: the 2D canvas, or the 3D view's recorder (4o's V3R: the strokes laid on the bed as ribbons,
   the ghost ball a faint ball, the jump's arc left out) */
protocol GuideSink: AnyObject {
  var ctx: GraphicsContext? { get }
  func line(_ pts: [[Double]], _ col: Color, _ w: Double, _ dash: [CGFloat])
  func ring(_ x: Double, _ y: Double, _ r: Double, _ col: Color, _ w: Double, fill: Color?, ghost: Bool)
}
final class Sink2D: GuideSink, OverlayPen {
  var g: GraphicsContext
  let m: Mapper
  init(ctx: GraphicsContext, m: Mapper) { g = ctx; self.m = m }
  var ctx: GraphicsContext? { g }
  var alpha = 1.0
  private var pg: GraphicsContext { var c = g; if alpha != 1 { c.opacity = g.opacity * alpha }; return c }
  private func path(_ pts: [CGPoint], _ closed: Bool) -> Path {
    var p = Path(); for (i, q) in pts.enumerated() { i == 0 ? p.move(to: q) : p.addLine(to: q) }
    if closed { p.closeSubpath() }
    return p
  }
  private func disc(_ c: CGPoint, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
  func stroke(_ pts: [CGPoint], closed: Bool, _ col: Color, _ w: Double, dash: [CGFloat], round: Bool) {
    pg.stroke(path(pts, closed), with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: round ? .round : .butt, lineJoin: round ? .round : .miter, dash: dash))
  }
  func circle(_ c: CGPoint, _ r: Double, _ col: Color, _ w: Double, dash: [CGFloat]) {
    pg.stroke(disc(c, r), with: .color(col), style: StrokeStyle(lineWidth: w, dash: dash))
  }
  func fill(_ pts: [CGPoint], _ col: Color) { pg.fill(path(pts, true), with: .color(col)) }
  func fillCircle(_ c: CGPoint, _ r: Double, _ col: Color) { pg.fill(disc(c, r), with: .color(col)) }
  func glow(_ c: CGPoint, _ r0: Double, _ r1: Double, _ col: Color) {
    pg.fill(disc(c, r1), with: .radialGradient(Gradient(colors: [col, .clear]), center: c, startRadius: r0, endRadius: r1))
  }
  /* settings.hcAim (guideHC): every guide stroke at least 2.5 pt (1.8 times its width) over a near-black edge, its white
     opaque */
  let hc = Prefs.bool("hcAim", false)
  func line(_ pts: [[Double]], _ col: Color, _ w: Double, _ dash: [CGFloat]) {
    var p = Path(); for (i, q) in pts.enumerated() { i == 0 ? p.move(to: m.pt(q[0], q[1])) : p.addLine(to: m.pt(q[0], q[1])) }
    let W = hc ? Swift.max(2.5, w * 1.8) : w
    g.stroke(p, with: .color(.black.opacity(hc ? 0.85 : 0.22)), style: StrokeStyle(lineWidth: W + (hc ? 3 : 2), lineCap: .round, lineJoin: .round, dash: dash))
    g.stroke(p, with: .color(hcStyle(col, hc)), style: StrokeStyle(lineWidth: W, lineCap: .round, lineJoin: .round, dash: dash))
  }
  func ring(_ x: Double, _ y: Double, _ r: Double, _ col: Color, _ w: Double, fill: Color?, ghost: Bool) {
    let q = m.pt(x, y), p = Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
    if let f = fill { g.fill(p, with: .color(f)) }
    let W = hc ? Swift.max(2.5, w * 1.8) : w
    if hc { g.stroke(p, with: .color(.black.opacity(0.85)), style: StrokeStyle(lineWidth: W + 3, lineCap: .round, lineJoin: .round)) }
    g.stroke(p, with: .color(hcStyle(col, hc)), style: StrokeStyle(lineWidth: W, lineCap: .round, lineJoin: .round))
  }
}
/* hcStyle: a white overlay drawn opaque under high contrast */
func hcStyle(_ c: Color, _ hc: Bool) -> Color { guard hc else { return c }; let v = rgbaOf(c); return v[0] > 0.99 && v[1] > 0.99 && v[2] > 0.99 ? .white : c }
func rgbaOf(_ c: Color) -> [Double] { var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a); return [r, g, b, a].map { Double($0) } }
final class Sink3D: GuideSink, OverlayPen {
  var alpha = 1.0
  /* V3R.tab: a CSS pt of the flat mapping back to table metres */
  private func tab(_ p: CGPoint) -> [Double] { let q = m.table(p); return [q.0, q.1] }
  private func rgba(_ col: Color) -> [Double] { var c = rgbaOf(col); c[3] *= alpha; return c }
  private func ringPts(_ c: CGPoint, _ r: Double) -> [[Double]] { let q = tab(c); return rib.arc(q[0], q[1], r / m.k, scale: scale) }
  /* V3R.stroke: a path of the same CSS width, dashed in metres as on screen, at its one height (v3PathZ) */
  private func put(_ pts: [[Double]], _ closed: Bool, _ col: Color, _ w: Double, _ dash: [CGFloat]) {
    let c = rgba(col)
    if !(w > 0) || c[3] <= 0.002 { return }
    rib.line(pts, w * scale, c, dash: dash.isEmpty ? nil : dash.map { Double($0) / m.k }, closed: closed, z: V3Ribbons.pathZ(s, pts, closed, topH: topH))
  }
  func stroke(_ pts: [CGPoint], closed: Bool, _ col: Color, _ w: Double, dash: [CGFloat], round: Bool) { put(pts.map(tab), closed, col, w, dash) }
  func circle(_ c: CGPoint, _ r: Double, _ col: Color, _ w: Double, dash: [CGFloat]) { put(ringPts(c, r), true, col, w, dash) }
  /* V3R.fill: triangles at the shape's height, a gradient evaluated at each vertex */
  private func fillPts(_ pts: [[Double]], rings: Int, _ col: ([Double]) -> [Double]) { rib.fill(pts, z: V3Ribbons.pathZ(s, pts, true, topH: topH), rings: rings, col) }
  func fill(_ pts: [CGPoint], _ col: Color) { let c = rgba(col); fillPts(pts.map(tab), rings: 1) { _ in c } }
  func fillCircle(_ c: CGPoint, _ r: Double, _ col: Color) { let k = rgba(col); fillPts(ringPts(c, r), rings: 1) { _ in k } }
  func glow(_ c: CGPoint, _ r0: Double, _ r1: Double, _ col: Color) {
    let k = rgba(col), q = tab(c), a = r0 / m.k, b = r1 / m.k
    fillPts(ringPts(c, r1), rings: 4) { p in
      let t = Swift.min(1, Swift.max(0, (JSMath.hypot(p[0] - q[0], p[1] - q[1]) - a) / Swift.max(1e-9, b - a)))
      return [k[0] * (1 - t), k[1] * (1 - t), k[2] * (1 - t), k[3] * (1 - t)]
    }
  }
  var rib: V3Ribbons
  let s: Sim, m: Mapper, C: V3.Cam, scale: Double, topH: Double
  var ghost: (x: Double, y: Double, col: [Double])? = nil
  init(_ C: V3.Cam, s: Sim, m: Mapper, scale: Double, topH: Double) { rib = V3Ribbons(C); self.C = C; self.s = s; self.m = m; self.scale = scale; self.topH = topH }
  var ctx: GraphicsContext? { nil }
  let hc = Prefs.bool("hcAim", false)
  func line(_ pts: [[Double]], _ col: Color, _ w: Double, _ dash: [CGFloat]) {
    let d = dash.isEmpty ? nil : dash.map { Double($0) / m.k }, W = hc ? Swift.max(2.5, w * 1.8) : w
    rib.line(pts, (W + (hc ? 3 : 2)) * scale, [0, 0, 0, hc ? 0.85 : 0.22], dash: d)
    rib.line(pts, W * scale, rgbaOf(hcStyle(col, hc)), dash: d)
  }
  func ring(_ x: Double, _ y: Double, _ r: Double, _ col: Color, _ w: Double, fill: Color?, ghost g: Bool) {
    if g { let c = rgbaOf(col); ghost = (x, y, c[0] > 0.85 && c[1] > 0.85 && c[2] > 0.85 ? [0.96, 0.96, 0.93] : c); return }
    /* the arc cut to about 2.5 device px a chord at its distance */
    let rm = r / m.k, dd = Swift.max(0.05, V3.dot(V3.sub([x, y, 0], C.Er), C.f)), px = 2 * Double.pi * rm * C.F / dd * scale
    let n = Swift.max(12, Swift.min(256, Int((px / 2.5).rounded(.up))))
    let pts = (0..<n).map { i -> [Double] in let a = Double(i) / Double(n) * 2 * Double.pi; return [x + rm * cos(a), y + rm * sin(a)] }
    rib.line(pts, w * scale, rgbaOf(col), closed: true, z: V3Ribbons.pathZ(s, pts, true, topH: topH))
  }
}
