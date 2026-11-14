/* The table, top down, in the web build's colours (CLOTHS, RAILS, BALL_COLOR in index.html section
   4): wood, cloth with the lamp's pool, the pocket holes, the cushion rubbers from the sim's own
   CUSHION_POLYS, the sights, the balls with their shadows, and the guide. Upright on a phone held
   upright (the head string at the foot of the screen), lengthwise on its side. */
import FeltRender
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
      let s = model.sim, m = Mapper(size: size, TL: s.TL, TW: s.TW), R = s.BALL_R
      let rect = { (x0: Double, y0: Double, x1: Double, y1: Double) -> Path in
        var p = Path(); p.move(to: m.pt(x0, y0)); p.addLine(to: m.pt(x1, y0)); p.addLine(to: m.pt(x1, y1)); p.addLine(to: m.pt(x0, y1)); p.closeSubpath(); return p
      }
      let circle = { (x: Double, y: Double, r: Double) -> Path in
        let c = m.pt(x, y); return Path(ellipseIn: CGRect(x: c.x - r * m.k, y: c.y - r * m.k, width: 2 * r * m.k, height: 2 * r * m.k))
      }
      if let img = model.tableImage, img.size == size {
        ctx.draw(Image(decorative: img.image, scale: img.scale), in: CGRect(origin: .zero, size: size))
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
      for b in list {
        let p = m.pt(b.x, b.y), z = b.z ?? 0, air = z > 0 ? 0.6 / (0.6 - min(z, 0.3)) : 1
        let (img, x, y) = model.ballImage(bp, b.n, Double(p.x) * sc, Double(p.y) * sc, rb * air)
        ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: x, y: y, width: Double(img.width), height: Double(img.height)))
      }
    }
  }
}
