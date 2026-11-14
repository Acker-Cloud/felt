/* index.html 4e (the cue) on SwiftUI's GraphicsContext: the same silhouette, maple, parts, forearm
   points, wrap patterns, light bands and three-layer shadow, in table metres under the page's
   tableXform, each discipline's shape (CUE_GEO) in each game's cue (CUES) and chalk (CHALKS). */
import FeltRender
import FeltSim
import SwiftUI

struct CueGeo {
  let len, r0, dr, ferrule: Double, ferCol: String, joint: Double?, pts: [Double]?, wrap: [Double]?
  var fore: [Double]? = nil, collar: [Double]? = nil, sleeve: [Double]? = nil, ring: [Double]? = nil
  var pool = false
  func r(_ x: Double) -> Double { r0 + dr * x / len }
  static let CUE_LEN = 1.47
  static let poolGeo = CueGeo(len: CUE_LEN, r0: 0.0064, dr: 0.0082, ferrule: 0.027, ferCol: "#f1ece0", joint: 0.74, pts: [0.83, 1.0], wrap: [1.008, 1.26], pool: true)
  static let snooker = CueGeo(len: 1.473, r0: 0.00485, dr: 0.01015, ferrule: 0.02, ferCol: "#c7a24a", joint: 1.067, pts: [0.72, 1.06], wrap: nil, sleeve: [1.077, 1.452], ring: [1.3, 1.306])
  static let carom = CueGeo(len: 1.425, r0: 0.006, dr: 0.01, ferrule: 0.006, ferCol: "#f1ece0", joint: 0.705, pts: nil, wrap: nil, fore: [0.715, 1.0], collar: [1.0, 1.022], sleeve: [1.022, 1.405], ring: [1.2, 1.206])
  static let heyball = CueGeo(len: 1.473, r0: 0.00575, dr: 0.00925, ferrule: 0.02, ferCol: "#26282c", joint: 1.067, pts: [0.76, 1.06], wrap: nil, sleeve: [1.077, 1.452], ring: [1.26, 1.266])
  static func of(game: String) -> CueGeo { ["snooker": snooker, "carom": carom, "heyball": heyball][game] ?? poolGeo }
}

struct CueLook {
  let shaft: [String], metal, joint, fore: String, pts: String?, wrap, pat, sleeve, ring, cap: String
  static let all: [String: CueLook] = [
    "house": CueLook(shaft: ["#f0dcae", "#d7b07a"], metal: "#c9ccd2", joint: "#151515", fore: "#2b150b", pts: "#a3622f", wrap: "#1c1d21", pat: "linen", sleeve: "#3c1b0d", ring: "#e7e2ef", cap: "#0c0c0c"),
    "ebony": CueLook(shaft: ["#f0dcae", "#d7b07a"], metal: "#e3e6ea", joint: "#0d0d0f", fore: "#121012", pts: "#d8dbe0", wrap: "#2b2c31", pat: "stack", sleeve: "#121012", ring: "#d8dbe0", cap: "#0a0a0a"),
    "carbon": CueLook(shaft: ["#454950", "#26282c"], metal: "#8a9099", joint: "#111214", fore: "#202226", pts: nil, wrap: "#2a2c31", pat: "weave", sleeve: "#1a1b1e", ring: "#c8433b", cap: "#0c0c0c"),
    "ash": CueLook(shaft: ["#ead9b2", "#cfb384"], metal: "#c7a24a", joint: "#17100a", fore: "#16100c", pts: "#16100c", wrap: "#16100c", pat: "linen", sleeve: "#16100c", ring: "#c7a24a", cap: "#0c0a08"),
    "hall": CueLook(shaft: ["#f1e0b8", "#dabb88"], metal: "#c9ccd2", joint: "#20140c", fore: "#3a1d10", pts: nil, wrap: "#3a1d10", pat: "linen", sleeve: "#2b150b", ring: "#c9ccd2", cap: "#151515"),
    "rosewood": CueLook(shaft: ["#ead9b2", "#cfb384"], metal: "#b8bcc2", joint: "#1a0e0a", fore: "#3f1711", pts: "#3f1711", wrap: "#3f1711", pat: "linen", sleeve: "#3f1711", ring: "#d9c9a3", cap: "#0c0a08"),
  ]
  /* GAME_LOOK's cue and chalk */
  static func of(game: String) -> (CueLook, String) {
    let cue = ["9": "ebony", "10": "carbon", "heyball": "rosewood", "snooker": "ash", "carom": "hall"][game] ?? "house"
    return (all[cue]!, game == "snooker" ? "#3f9a5c" : "#4f84bd")
  }
}

func css(_ s: String) -> Color { let c = RGBA(css: s); return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }

/* drawCue(c, ang, gap, alpha): the cue's tip gap metres back from the cue ball at (cx, cy) */
func drawCue(_ ctx: inout GraphicsContext, _ m: Mapper, game: String, cx: Double, cy: Double, ang: Double, gap: Double, alpha: Double = 1) {
  let G = CueGeo.of(game: game), LEN = G.len, dx = cos(ang), dy = sin(ang), tx = cx - dx * gap, ty = cy - dy * gap, bx = tx - dx * LEN, by = ty - dy * LEN
  let nx = -dy, ny = dx, sd = m.upright ? [LIGHT[1], -LIGHT[0]] : [-LIGHT[0], -LIGHT[1]]
  var g = ctx
  g.opacity = alpha
  /* tableXform, in points */
  g.concatenate(m.upright ? CGAffineTransform(a: 0, b: -m.k, c: m.k, d: 0, tx: m.ox, ty: m.oy + m.TL * m.k) : CGAffineTransform(a: m.k, b: 0, c: 0, d: m.k, tx: m.ox, ty: m.oy))
  for i in 0..<3 {
    let w = 0.0015 + Double(i) * 0.004, a0 = 0.01, a1 = 0.08, r0 = G.r(0) + w, r1 = G.r(LEN) + 2 * w
    let sx = tx + sd[0] * a0, sy = ty + sd[1] * a0, ex = bx + sd[0] * a1, ey = by + sd[1] * a1
    var p = Path()
    p.move(to: CGPoint(x: sx + nx * r0, y: sy + ny * r0)); p.addLine(to: CGPoint(x: ex + nx * r1, y: ey + ny * r1))
    p.addLine(to: CGPoint(x: ex - nx * r1, y: ey - ny * r1)); p.addLine(to: CGPoint(x: sx - nx * r0, y: sy - ny * r0)); p.closeSubpath()
    g.fill(p, with: .color(.black.opacity(0.12)))
  }
  g.translateBy(x: tx, y: ty); g.rotate(by: .radians(ang + .pi))
  let r0 = G.r(0), r1 = G.r(LEN)
  func band(_ f0: Double, _ f1: Double, _ col: Color) {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: f0 * G.r(0))); p.addLine(to: CGPoint(x: LEN, y: f0 * G.r(LEN)))
    p.addLine(to: CGPoint(x: LEN, y: f1 * G.r(LEN))); p.addLine(to: CGPoint(x: 0, y: f1 * G.r(0))); p.closeSubpath()
    g.fill(p, with: .color(col))
  }
  func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ col: Color) { g.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(col)) }
  var outline = Path()
  outline.move(to: CGPoint(x: 0, y: -r0)); outline.addLine(to: CGPoint(x: LEN - 0.004, y: -r1))
  outline.addQuadCurve(to: CGPoint(x: LEN, y: 0), control: CGPoint(x: LEN, y: -r1))
  outline.addQuadCurve(to: CGPoint(x: LEN - 0.004, y: r1), control: CGPoint(x: LEN, y: r1))
  outline.addLine(to: CGPoint(x: 0, y: r0)); outline.addQuadCurve(to: CGPoint(x: 0, y: -r0), control: CGPoint(x: -0.0012, y: 0)); outline.closeSubpath()
  g.clip(to: outline)
  let (CU, tip) = CueLook.of(game: game), SH = G.joint ?? (G.sleeve?[0] ?? 0.74), f0 = G.pool ? 0.027 : G.ferrule
  g.fill(Path(CGRect(x: 0.02, y: -0.02, width: G.pool ? 0.73 : SH - 0.01, height: 0.04)),
         with: .linearGradient(Gradient(colors: [css(CU.shaft[0]), css(CU.shaft[1])]), startPoint: CGPoint(x: f0, y: 0), endPoint: CGPoint(x: SH, y: 0)))
  for (a, b, col) in cueParts(CU, tip, G) { rect(a, -0.02, b - a, 0.04, css(col)) }
  if let pc = CU.pts, let pr = G.pts {
    for s in [-1.0, 1.0] {
      var p = Path()
      p.move(to: CGPoint(x: pr[0], y: s * 0.45 * G.r(pr[0]))); p.addLine(to: CGPoint(x: pr[1], y: s * 0.1 * G.r(pr[1]))); p.addLine(to: CGPoint(x: pr[1], y: s * 0.95 * G.r(pr[1]))); p.closeSubpath()
      g.fill(p, with: .color(css(pc)))
    }
  }
  if let w = G.wrap {
    let a = w[0], b = w[1], R = G.r(b)
    switch CU.pat {
    case "linen": var x = a; while x < b { rect(x, -0.02, 0.0016, 0.04, .white.opacity(0.07)); x += 0.0045 }
    case "leather": var x = a; while x < b { rect(x, -0.02, 0.009, 0.04, .white.opacity(0.05)); x += 0.021 }
    case "stack": var x = a, i = 0; while x < b { rect(x, -0.02, 0.011, 0.04, i % 2 == 1 ? .white.opacity(0.16) : .black.opacity(0.25)); x += 0.011; i += 1 }
    case "weave":
      let q = 0.004; var x = a, i = 0
      while x < b { var y = -R, j = 0; while y < R { rect(x, y, q, q, (i + j) % 2 == 1 ? .white.opacity(0.12) : .black.opacity(0.2)); y += q; j += 1 }; x += q; i += 1 }
    default: break
    }
  }
  /* lit along the side toward the lamp, shaded on the other */
  let ly = m.upright ? [-cos(ang), -sin(ang)] : [sin(ang), -cos(ang)]
  let s: Double = ly[0] * LIGHT[0] + ly[1] * LIGHT[1] > 0 ? 1 : -1
  band(s * 0.1, s * 0.75, .white.opacity(0.16))
  band(s * 0.3, s * 0.5, .white.opacity(0.24))
  band(-s * 0.15, -s * 1.05, .black.opacity(0.3))
  band(-s * 0.6, -s * 1.05, .black.opacity(0.25))
  band(s * 0.85, s * 1.05, .black.opacity(0.18))
}

/* cueParts: the cue's bands from the tip back, the tip in its chalk */
private func cueParts(_ C: CueLook, _ tip: String, _ G: CueGeo) -> [(Double, Double, String)] {
  if G.pool {
    return [(0, 0.005, tip), (0.005, 0.027, G.ferCol), (0.74, 0.744, C.metal), (0.744, 0.752, C.joint), (0.752, 0.756, C.metal),
            (0.756, 1.0, C.fore), (1.0, 1.006, C.metal), (1.006, 1.262, C.wrap), (1.262, 1.268, C.metal), (1.268, 1.45, C.sleeve), (1.33, 1.338, C.ring), (1.45, CueGeo.CUE_LEN, C.cap)]
  }
  var out: [(Double, Double, String)] = [(0, 0.005, tip), (0.005, G.ferrule, G.ferCol)]
  if let j = G.joint { out += [(j - 0.004, j, C.metal), (j, j + 0.006, C.joint), (j + 0.006, j + 0.01, C.metal)] }
  if let f = G.fore { out.append((f[0], f[1], C.fore)) }
  if let c = G.collar { out.append((c[0], c[1], C.metal)) }
  let sl = G.sleeve!
  out.append((sl[0], sl[1], C.sleeve))
  if let r = G.ring { out.append((r[0], r[1], C.ring)) }
  out.append((sl[1], G.len, C.cap))
  return out
}
