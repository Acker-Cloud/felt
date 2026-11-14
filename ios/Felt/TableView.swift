/* The table, top down, in the web build's colours (CLOTHS, RAILS, BALL_COLOR in index.html section
   4): wood, cloth with the lamp's pool, the pocket holes, the cushion rubbers from the sim's own
   CUSHION_POLYS, the sights, the balls with their shadows, and the guide. Upright on a phone held
   upright (the head string at the foot of the screen), lengthwise on its side. */
import FeltSim
import SwiftUI

struct Look {
  var cloth: Color, cushion: Color, rail: Color, railDark: Color
  static func of(_ g: Game) -> Look {
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

/* table metres to screen points, upright or lengthwise */
struct Mapper {
  let k: Double, ox: Double, oy: Double, upright: Bool, TL: Double, TW: Double
  static let margin = 0.13   /* the wood round the bed, metres from the nose line */
  init(size: CGSize, TL: Double, TW: Double) {
    self.TL = TL; self.TW = TW
    let L = TL + 2 * Mapper.margin, W = TW + 2 * Mapper.margin
    upright = size.height > size.width
    let (sw, sh) = upright ? (W, L) : (L, W)
    k = min(Double(size.width) / sw, Double(size.height) / sh)
    ox = (Double(size.width) - sw * k) / 2; oy = (Double(size.height) - sh * k) / 2
  }
  func pt(_ x: Double, _ y: Double) -> CGPoint {
    upright ? CGPoint(x: ox + (y + Mapper.margin) * k, y: oy + (TL - x + Mapper.margin) * k)
      : CGPoint(x: ox + (x + Mapper.margin) * k, y: oy + (y + Mapper.margin) * k)
  }
  func table(_ p: CGPoint) -> (Double, Double) {
    upright ? (TL + Mapper.margin - (Double(p.y) - oy) / k, (Double(p.x) - ox) / k - Mapper.margin)
      : ((Double(p.x) - ox) / k - Mapper.margin, (Double(p.y) - oy) / k - Mapper.margin)
  }
  /* a table angle as a screen angle */
  func screenAngle(_ a: Double) -> Double { upright ? atan2(-cos(a), sin(a)) : a }
}

struct TableCanvas: View {
  let model: TableModel
  let look: Look

  var body: some View {
    Canvas { ctx, size in
      _ = model.frame
      let s = model.sim, m = Mapper(size: size, TL: s.TL, TW: s.TW), R = s.BALL_R
      let rect = { (x0: Double, y0: Double, x1: Double, y1: Double) -> Path in
        var p = Path(); p.move(to: m.pt(x0, y0)); p.addLine(to: m.pt(x1, y0)); p.addLine(to: m.pt(x1, y1)); p.addLine(to: m.pt(x0, y1)); p.closeSubpath(); return p
      }
      let circle = { (x: Double, y: Double, r: Double) -> Path in
        let c = m.pt(x, y); return Path(ellipseIn: CGRect(x: c.x - r * m.k, y: c.y - r * m.k, width: 2 * r * m.k, height: 2 * r * m.k))
      }
      let g = Mapper.margin
      /* the wood, darker at its outer edge */
      ctx.fill(rect(-g, -g, s.TL + g, s.TW + g), with: .color(look.railDark))
      ctx.fill(rect(-g + 0.012, -g + 0.012, s.TL + g - 0.012, s.TW + g - 0.012), with: .color(look.rail))
      /* the bed out to the rubbers' backs, and the lamp's pool */
      let bed = rect(-CUSH_W, -CUSH_W, s.TL + CUSH_W, s.TW + CUSH_W)
      ctx.fill(bed, with: .color(look.cloth))
      let mid = m.pt(s.TL / 2, s.TW / 2)
      ctx.fill(bed, with: .radialGradient(Gradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.18)]),
        center: mid, startRadius: 0, endRadius: CGFloat(max(s.TL, s.TW) * 0.62 * m.k)))
      /* the holes */
      for (k, p) in s.POCKETS.enumerated() {
        ctx.fill(circle(p[0], p[1], s.POCKET_R[k] + 0.006), with: .color(.black.opacity(0.55)))
        ctx.fill(circle(p[0], p[1], s.POCKET_R[k]), with: .color(Color(rgb: 8, 8, 9)))
      }
      /* the rubbers */
      for poly in s.CUSHION_POLYS {
        var p = Path()
        for (i, q) in poly.enumerated() { i == 0 ? p.move(to: m.pt(q[0], q[1])) : p.addLine(to: m.pt(q[0], q[1])) }
        p.closeSubpath()
        ctx.fill(p, with: .color(look.cushion))
        ctx.stroke(p, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
      }
      /* sights: three a side on the ends, seven (less the side pocket's) on the long rails */
      let rw = -CUSH_W - (g - CUSH_W) / 2
      for i in 1..<8 where i != 4 || s.POCKETS.isEmpty {
        let x = s.TL * Double(i) / 8
        for y in [rw, s.TW - rw] { ctx.fill(circle(x, y, 0.0055), with: .color(Color(white: 0.92))) }
      }
      for i in 1..<4 { let y = s.TW * Double(i) / 4; for x in [rw, s.TL - rw] { ctx.fill(circle(x, y, 0.0055), with: .color(Color(white: 0.92))) } }
      /* the head string, faint */
      if model.inHand {
        var l = Path(); l.move(to: m.pt(s.HEAD_X, 0)); l.addLine(to: m.pt(s.HEAD_X, s.TW))
        ctx.stroke(l, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
      }
      /* the guide */
      if let gd = model.guide(), let c = model.cue {
        var l = Path(); l.move(to: m.pt(c.x, c.y)); l.addLine(to: m.pt(gd.end.0, gd.end.1))
        ctx.stroke(l, with: .color(.white.opacity(0.75)), lineWidth: 1.5)
        if gd.ghost {
          ctx.stroke(circle(gd.end.0, gd.end.1, R), with: .color(.white.opacity(0.7)), lineWidth: 1.25)
          if let o = gd.objectDir, let t = model.shown.first(where: { $0.n == gd.target }) {
            var ol = Path(); ol.move(to: m.pt(t.x, t.y)); ol.addLine(to: m.pt(t.x + o.0 * R * 6, t.y + o.1 * R * 6))
            ctx.stroke(ol, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
          }
        }
      }
      /* shadows, then balls */
      for b in model.shown where b.on {
        let air = b.z ?? 0, sc = 1 + air * 4
        ctx.fill(circle(b.x + R * 0.18 + air * 0.6, b.y + R * 0.22 + air * 0.6, R * 1.02), with: .color(.black.opacity(0.35 / sc)))
      }
      for b in model.shown where b.on { drawBall(&ctx, m, b, R * (1 + (b.z ?? 0) * 4)) }
    }
  }

  private func drawBall(_ ctx: inout GraphicsContext, _ m: Mapper, _ b: Ball, _ R: Double) {
    let c = m.pt(b.x, b.y), r = R * m.k
    let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    let (cr, cg, cb) = ballColor(b.n)
    let base = Color(rgb: cr, cg, cb), stripe = b.n >= 9 && b.n <= 15
    ctx.fill(disc, with: .color(stripe ? Color(rgb: 247, 244, 234) : base))
    if stripe {
      var band = ctx
      band.clip(to: disc)
      let a = m.screenAngle(0)
      var p = Path(); p.addRect(CGRect(x: -r * 1.2, y: -r * 0.55, width: r * 2.4, height: r * 1.1))
      band.fill(p.applying(CGAffineTransform(rotationAngle: a + .pi / 2).concatenating(CGAffineTransform(translationX: c.x, y: c.y))), with: .color(base))
    }
    if b.n >= 1 && b.n <= 15 {
      let d = r * 0.98
      ctx.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(Color(rgb: 247, 244, 234)))
      if r > 5 {
        ctx.draw(Text("\(b.n)").font(.system(size: r * 0.62, weight: .bold, design: .rounded)).foregroundStyle(.black), at: c)
      }
    }
    /* the lamp's highlight and the shade side */
    ctx.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0), .black.opacity(0.32)]),
      center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.6))
  }
}
