/* Section 4b of index.html (balls) on Canvas2D: each ball's orientation matrix, rolled from its
   displacement; the base colour; the white areas as exact projections of spherical caps (stripe ends,
   number circles, the cue ball's dots); the number as a decal on its circle; then the lamp's shading
   sprite; and the table's cast shadow and contact shade (drawCast). Ball sets are 4l's BALLSETS. */
#if canImport(CoreGraphics)
import CoreGraphics
import FeltSim
import Foundation

public typealias Mat3 = [Double]   /* row major, world = m . local */
public let IDENT: Mat3 = [1, 0, 0, 0, 1, 0, 0, 0, 1]

/* left-multiply m by a rotation about axis by angle, columns re-normalised */
public func rotate(_ m: Mat3, _ axis: [Double], _ ang: Double) -> Mat3 {
  let L = JSMath.hypot(axis[0], axis[1], axis[2])
  if L < 1e-12 || ang == 0 { return m }
  let x = axis[0] / L, y = axis[1] / L, z = axis[2] / L, c = JSMath.cos(ang), s = JSMath.sin(ang), t = 1 - c
  let r = [t * x * x + c, t * x * y - s * z, t * x * z + s * y, t * x * y + s * z, t * y * y + c, t * y * z - s * x, t * x * z - s * y, t * y * z + s * x, t * z * z + c]
  var o = [Double](repeating: 0, count: 9)
  for i in 0..<3 { for j in 0..<3 { o[i * 3 + j] = r[i * 3] * m[j] + r[i * 3 + 1] * m[3 + j] + r[i * 3 + 2] * m[6 + j] } }
  for j in 0..<3 { let l = JSMath.hypot(o[j], o[3 + j], o[6 + j]); o[j] /= l; o[3 + j] /= l; o[6 + j] /= l }
  return o
}

public struct BallSet: Sendable {
  public let col: [Int: [Double]]?, stripe: [Double]?, ivory: String, circle: Double, cue: [(Int, Double, String)]
  public static let all: [String: BallSet] = [
    "classic": BallSet(col: nil, stripe: nil, ivory: "#f7f4ea", circle: 0.866, cue: [(2, 0.975, "#b3302a")]),
    "tv": BallSet(col: [1: [255, 204, 0], 2: [20, 84, 222], 3: [232, 36, 30], 4: [240, 92, 150], 5: [255, 120, 10], 6: [10, 150, 72], 7: [164, 104, 62], 8: [16, 16, 18]],
                  stripe: nil, ivory: "#fbfaf4", circle: 0.8, cue: [0, 1, 2].map { ($0, 0.986, "#1d4fb8") }),
    "pro": BallSet(col: nil, stripe: nil, ivory: "#f7f4ea", circle: 0.866, cue: [0, 1, 2].map { ($0, 0.982, "#c4342c") }),
    "vintage": BallSet(col: [1: [222, 170, 62], 2: [44, 70, 140], 3: [172, 52, 40], 4: [92, 58, 116], 5: [212, 116, 52], 6: [40, 102, 70], 7: [116, 44, 34], 8: [30, 26, 24]],
                       stripe: nil, ivory: "#ece2c6", circle: 0.866, cue: []),
    "measles": BallSet(col: [1: [255, 204, 0], 2: [20, 84, 222], 3: [232, 36, 30], 4: [240, 92, 150], 5: [255, 120, 10], 6: [10, 150, 72], 7: [164, 104, 62], 8: [16, 16, 18]],
                       stripe: nil, ivory: "#fbfaf4", circle: 0.8, cue: [0, 1, 2].map { ($0, 0.986, "#c4342c") }),
    "pinkblue": BallSet(col: [1: [238, 88, 150], 2: [238, 88, 150], 3: [238, 88, 150], 4: [238, 88, 150], 5: [238, 88, 150], 6: [238, 88, 150], 7: [238, 88, 150], 8: [16, 16, 18]],
                        stripe: [40, 120, 232], ivory: "#fbfaf4", circle: 0.8, cue: [0, 1, 2].map { ($0, 0.986, "#c4342c") }),
  ]
  /* GAME_LOOK's balls */
  public static func of(game: String) -> BallSet {
    all[Dress.game(game).balls] ?? all["classic"]!
  }
}

/* BALL_COLOR, SNOOKER_COLOR, CAROM_COLOR, BUMPER_COLOR (4) */
public func colorOf(_ n: Int) -> [Double] {
  if n >= 70 { return [[247, 244, 234], [244, 196, 48], [206, 34, 40]][n - 70] }
  if n > 40 {
    if n >= 41 && n <= 55 { return [196, 28, 36] }
    return [57: [246, 206, 40], 58: [26, 132, 72], 59: [124, 66, 34], 60: [30, 80, 196], 61: [246, 146, 176], 62: [22, 22, 24]][n] ?? [0, 0, 0]
  }
  if n > 20 { return n > 30 ? [244, 241, 230] : [200, 38, 44] }
  let pool: [[Double]] = [[247, 244, 234], [246, 186, 28], [28, 72, 184], [208, 42, 36], [92, 46, 146], [242, 112, 26], [22, 120, 66], [122, 30, 32], [20, 20, 22]]
  return pool[n > 8 ? n - 8 : n]
}
func cssRgb(_ c: [Double]) -> String { "rgb(\(Int(c[0])),\(Int(c[1])),\(Int(c[2])))" }

public final class BallPainter {
  public let set: BallSet, bounce: String, dpr: Double, portrait: Bool
  public let lowRim: Bool, rimAll: Bool, clothBase: [Double]
  /* settings.marks: the colour-blind safe badge on every ball (drawMark) */
  public var marks = false
  struct Paint { let base: String; let caps: [(Int, Double, String)] }
  /* a ball's paint (PAINT[n]: its base and caps), for the 3D view's ball shader */
  public func paintOf(_ n: Int) -> (base: String, caps: [(Int, Double, String)]) { let p = paint[n] ?? paint[0]!; return (p.base, p.caps) }
  /* the 3D view's light rim: the 8 (snooker's black) on a rimmed cloth, or a ball close to the cloth's colour */
  public func rim3(_ n: Int) -> Bool { ((n == 8 || n == 62) && rimAll) || lowBall(n) }
  private var paint: [Int: Paint] = [:]
  struct Sprites { let r: Double, shade: CGImage, c: Double, cast: CGImage, ao: CGImage, sc: Double, castW: Double, shadeW: Double }
  private var sprites: [Int: Sprites] = [:]

  /* bounce: the cloth's colour bounced into the shade side (CLOTHS[...].bounce); lowRim, rimAll: the
     cloth's lowRim and rim; clothBase: its base colour, 0-255 */
  public init(set: BallSet, bounce: String, dpr: Double, portrait: Bool, lowRim: Bool = false, rimAll: Bool = false, clothBase: [Double] = [27, 93, 71]) {
    self.set = set; self.bounce = bounce; self.dpr = dpr; self.portrait = portrait; self.lowRim = lowRim; self.rimAll = rimAll; self.clothBase = clothBase
    for n in 0...15 {
      if n == 0 { paint[0] = Paint(base: set.ivory, caps: set.cue); continue }
      let c = setCol(n) ?? colorOf(n)
      paint[n] = Paint(base: cssRgb(c), caps: n > 8 ? [(0, 0.5, set.ivory), (2, set.circle, set.ivory)] : [(2, set.circle, set.ivory)])
    }
    for n in [21, 22, 23, 24, 25, 31, 32, 33, 34, 35] {
      let spot = n == 21 ? "#f7f4ea" : "#c8262c"
      paint[n] = Paint(base: cssRgb(colorOf(n)), caps: n == 21 || n == 31 ? [(0, 0.94, spot), (1, 0.94, spot), (2, 0.94, spot)] : [])
    }
    for n in Array(41...55) + [57, 58, 59, 60, 61, 62, 70, 71, 72] { paint[n] = Paint(base: cssRgb(colorOf(n)), caps: []) }
  }
  func setCol(_ n: Int) -> [Double]? { n > 8 && set.stripe != nil ? set.stripe : set.col?[n > 8 ? n - 8 : n] }

  /* a ball's local axes as screen directions (x right, y down, z toward the eye) */
  public func axesOf(_ m: Mat3, screen: Bool = false) -> [[Double]] {
    let P = portrait && !screen
    return (0..<3).map { j in let wx = m[j], wy = m[3 + j], wz = m[6 + j]; return P ? [wy, -wx, wz] : [wx, wy, wz] }
  }

  func capPath(_ g: Canvas2D, _ p: [Double], _ ca: Double) -> Bool {
    let sa = (1 - ca * ca).squareRoot(), q = JSMath.hypot(p[0], p[1])
    g.beginPath()
    if q < 1e-4 { if p[2] <= 0 { return false }; g.arc(0, 0, sa, 0, Double.pi * 2); return true }
    let dx = p[0] / q, dy = p[1] / q, s0 = -ca * p[2] / (sa * q)
    if s0 >= 1 { return false }
    func pt(_ t: Double) -> [Double] {
      [ca * q * dx + sa * (-dy * cos(t) - p[2] * dx * sin(t)), ca * q * dy + sa * (dx * cos(t) - p[2] * dy * sin(t))]
    }
    let full = s0 <= -1, t1 = full ? 0 : asin(s0), t2 = full ? Double.pi * 2 : Double.pi - t1, N = 28
    for i in 0...N { let v = pt(t1 + (t2 - t1) * Double(i) / Double(N)); i == 0 ? g.moveTo(v[0], v[1]) : g.lineTo(v[0], v[1]) }
    if !full {
      let P1 = pt(t1), P2 = pt(t2), a1 = atan2(P1[1], P1[0]), a2 = atan2(P2[1], P2[0]), ad = atan2(dy, dx)
      let T = Double.pi * 2
      func wrap(_ v: Double) -> Double { ((v.truncatingRemainder(dividingBy: T)) + T).truncatingRemainder(dividingBy: T) }
      g.arc(0, 0, 1, a2, a1, !(wrap(ad - a2) < wrap(a1 - a2)))
    }
    g.closePath()
    return true
  }

  func ballSprites(_ r: Double) -> Sprites {
    let key = Int((r * 4).rounded())
    if let s = sprites[key] { return s }
    let sz = Int(ceil(2 * r)) + 2, c = Double(sz) / 2
    var g = Canvas2D(width: sz, height: sz)
    g.translate(c, c)
    g.beginPath(); g.arc(0, 0, r, 0, Double.pi * 2); g.clip()
    let lx = LIGHT[0] * r, ly = LIGHT[1] * r
    func fill(_ g: Canvas2D, _ x: Double, _ y: Double, _ r0: Double, _ r1: Double, _ stops: [(Double, String)], _ x1: Double? = nil, _ y1: Double? = nil) {
      let gr = g.createRadialGradient(x, y, r0, x1 ?? x, y1 ?? y, r1)
      for (t, col) in stops { gr.addColorStop(t, col) }
      g.fillStyle = .gradient(gr); g.fillRect(-c, -c, Double(sz), Double(sz))
    }
    fill(g, lx * 0.45, ly * 0.45, 0, r * 1.6, [(0, "rgba(255,255,255,0.12)"), (0.3, "rgba(255,255,255,0)"), (0.6, "rgba(0,0,0,0.16)"), (0.82, "rgba(0,0,0,0.42)"), (1, "rgba(0,0,0,0.66)")], lx * 0.25, ly * 0.25)
    fill(g, -lx * 0.85, -ly * 0.85, 0, r * 0.75, [(0, "rgba(\(bounce),0.16)"), (1, "rgba(\(bounce),0)")])
    fill(g, 0, 0, r * 0.72, r, [(0, "rgba(0,0,0,0)"), (1, "rgba(0,0,0,0.3)")])
    fill(g, lx * 0.5, ly * 0.5, 0, r * 0.7, [(0, "rgba(255,255,255,0.3)"), (1, "rgba(255,255,255,0)")])
    fill(g, lx * 0.52, ly * 0.52, 0, r * 0.22, [(0, "rgba(255,255,255,1)"), (0.4, "rgba(255,255,255,0.85)"), (1, "rgba(255,255,255,0)")])
    fill(g, -lx * 0.5, -ly * 0.5, 0, r * 0.42, [(0, "rgba(255,250,240,0.1)"), (1, "rgba(255,250,240,0)")])
    let shade = g.image()
    let ssz = Int(ceil(5 * r)), sc = Double(ssz) / 2
    g = Canvas2D(width: ssz, height: ssz)
    g.translate(sc, sc)
    var gr = g.createRadialGradient(0, 0, 0, 0, 0, r * 1.5)
    gr.addColorStop(0, "rgba(0,0,0,0.56)"); gr.addColorStop(0.5, "rgba(0,0,0,0.36)"); gr.addColorStop(0.78, "rgba(0,0,0,0.1)"); gr.addColorStop(1, "rgba(0,0,0,0)")
    g.fillStyle = .gradient(gr); g.fillRect(-sc, -sc, Double(ssz), Double(ssz))
    let cast = g.image()
    g = Canvas2D(width: ssz, height: ssz)
    g.translate(sc, sc)
    gr = g.createRadialGradient(0, 0, r * 0.8, 0, 0, r * 1.16)
    gr.addColorStop(0, "rgba(0,0,0,0.55)"); gr.addColorStop(1, "rgba(0,0,0,0)")
    g.fillStyle = .gradient(gr); g.fillRect(-sc, -sc, Double(ssz), Double(ssz))
    let ao = g.image()
    let s = Sprites(r: r, shade: shade, c: c, cast: cast, ao: ao, sc: sc, castW: Double(ssz), shadeW: Double(sz))
    sprites[key] = s
    return s
  }

  /* one ball at device pixel (X, Y), radius r device px, axes from axesOf() */
  /* drawShadow: the contact shadow sprite (ballSprites' shadow) at (X, Y) for radius r: the lamp's offset pool and the
     shade round the ball's foot */
  public func drawShadow(_ g: Canvas2D, _ X: Double, _ Y: Double, _ r: Double, alpha: Double = 1) {
    let sc = (5 * r).rounded(.up) / 2, ox = -LIGHT[0] * r * 0.38, oy = -LIGHT[1] * r * 0.38
    g.save(); g.translate(X, Y); let a0 = g.globalAlpha; g.globalAlpha = alpha
    let gr = g.createRadialGradient(ox, oy, 0, ox, oy, r * 1.55)
    gr.addColorStop(0, "rgba(0,0,0,0.45)"); gr.addColorStop(0.55, "rgba(0,0,0,0.26)"); gr.addColorStop(1, "rgba(0,0,0,0)")
    g.fillStyle = .gradient(gr); g.fillRect(-sc, -sc, 2 * sc, 2 * sc)
    let g2 = g.createRadialGradient(0, 0, r * 0.85, 0, 0, r * 1.14)
    g2.addColorStop(0, "rgba(0,0,0,0.5)"); g2.addColorStop(1, "rgba(0,0,0,0)")
    g.fillStyle = .gradient(g2); g.fillRect(-sc, -sc, 2 * sc, 2 * sc)
    g.globalAlpha = a0; g.restore()
  }
  public func drawBall(_ g: Canvas2D, _ n: Int, _ X: Double, _ Y: Double, _ r: Double, _ ax: [[Double]], alpha: Double = 1, dark: Double = 0, rim: Bool = false) {
    guard let P = paint[n] else { return }
    let S = ballSprites(r), k = r / S.r
    g.globalAlpha = alpha
    g.setTransform(r, 0, 0, r, X, Y)
    g.fillStyle(P.base); g.beginPath(); g.arc(0, 0, 1, 0, Double.pi * 2); g.fill()
    for (i, ca, col) in P.caps {
      g.fillStyle(col)
      let a = ax[i]
      if capPath(g, a, ca) { g.fill() }
      if capPath(g, [-a[0], -a[1], -a[2]], ca) { g.fill() }
    }
    if n > 0 && n < 16 {
      var p = ax[2], e2 = ax[1]
      let e1 = ax[0]
      if p[2] < 0 { p = [-p[0], -p[1], -p[2]]; e2 = [-e2[0], -e2[1], -e2[2]] }
      if p[2] > 0.1 {
        g.globalAlpha = alpha * clamp((p[2] - 0.1) / 0.3, 0, 1)
        g.setTransform(e1[0], e1[1], e2[0], e2[1], X + p[0] * r, Y + p[1] * r)
        if n > 9 { g.scale(0.82, 1) }
        g.fillStyle("#141414")
        g.fillTextCentered(String(n), 0, r * 0.04, size: (r * 0.6 * 10).rounded() / 10)
        g.globalAlpha = alpha
      }
    }
    g.setTransform(1, 0, 0, 1, 0, 0)
    g.drawImage(S.shade, X - S.c * k, Y - S.c * k, S.shadeW * k, S.shadeW * k)
    if ((n == 8 || (n == 62 && rimAll)) && (rim || rimAll)) || lowBall(n) {
      g.strokeStyle("#c4c4c4"); g.lineWidth = max(dpr, r * 0.08)
      g.beginPath(); g.arc(X, Y, r - g.lineWidth / 2, 0, Double.pi * 2); g.stroke()
    }
    if marks { drawMark(g, n, X, Y, r) }
    if dark > 0 { g.fillStyle = .color(RGBA(0, 0, 0, dark)); g.beginPath(); g.arc(X, Y, r + 0.5, 0, Double.pi * 2); g.fill() }
    g.globalAlpha = 1
  }
  /* markOf: colour-blind safe marks, read by lightness and by their words, never by hue: pool's solids (and the 8) a light
     badge with a dark number, stripes a dark badge with a light one; snooker's colours their value (2 yellow to 7 black,
     reds none); carom's yellow Y (dark) and red R (light), the white none; bumper pool's reds R. [text, dark] */
  public static func markOf(_ n: Int) -> (String, Bool)? {
    if n >= 1 && n <= 15 { return (String(n), n > 8) }
    if n >= 57 && n <= 62 { return (String(n - 55), n == 62) }
    if n == 71 { return ("Y", true) }
    if n == 72 { return ("R", false) }
    if n >= 21 && n <= 25 { return ("R", true) }
    return nil
  }
  /* drawMark: an upright badge, 0.6 of the ball across, ringed in the other tone, its words in the bold number face */
  func drawMark(_ g: Canvas2D, _ n: Int, _ X: Double, _ Y: Double, _ r: Double) {
    guard let m = BallPainter.markOf(n) else { return }
    let R = r * 0.6, dark = m.1, ivory = "#f7f4ea", ink = "#141414"
    g.setTransform(1, 0, 0, 1, 0, 0)
    g.fillStyle(dark ? ink : ivory); g.beginPath(); g.arc(X, Y, R, 0, Double.pi * 2); g.fill()
    g.strokeStyle(dark ? ivory : ink); g.lineWidth = max(dpr * 0.75, r * 0.07); g.stroke()
    g.fillStyle(dark ? ivory : ink)
    g.fillTextCentered(m.0, X, Y + R * 0.06, size: (R * (m.0.count > 1 ? 1.0 : 1.2) * 10).rounded() / 10)
  }
  /* setBall: a ball's colour in this set and the set's ivory (the rail's flat inlay, nextBallEl) */
  public func flatOf(_ n: Int) -> (col: [Double], iv: String) { ((n >= 1 && n <= 15 ? setCol(n) : nil) ?? colorOf(n), set.ivory) }
  func lowBall(_ n: Int) -> Bool {
    guard lowRim else { return false }
    let c = (n >= 1 && n <= 15 ? setCol(n) : nil) ?? colorOf(n)
    func lum(_ c: [Double]) -> Double {
      let f = { (v: Double) -> Double in let s = v / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
      return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
    }
    let a = lum(c), l = lum(clothBase)
    return (max(a, l) + 0.05) / (min(a, l) + 0.05) < 1.45
  }

  /* one ball alone, for a renderer that composites (the app): its image and where its top-left goes
     relative to the ball's centre, in device px. The centre keeps its fraction of a pixel, so the
     edges anti-alias as they would on the page's canvas. */
  public func ballImage(_ n: Int, _ X: Double, _ Y: Double, _ r: Double, _ ax: [[Double]], dark: Double = 0, rim: Bool = false) -> (CGImage, Double, Double) {
    let size = Int(ceil(2 * r)) + 4, fx = X - floor(X), fy = Y - floor(Y), o = Double(size / 2)
    let g = Canvas2D(width: size, height: size)
    drawBall(g, n, o + fx, o + fy, r, ax, dark: dark, rim: rim)
    return (g.image(), floor(X) - o, floor(Y) - o)
  }
  /* drawCast's two sprites as [image, rect, alpha], for a compositing renderer */
  public func castParts(_ x: Double, _ y: Double, _ X: Double, _ Y: Double, _ r: Double, tl: Double, tw: Double, ballR: Double,
                        lift: Double = 0, alpha: Double = 1, z: Double = 0) -> [(CGImage, CGRect, Double)] {
    let S = ballSprites(r), k = r / S.r, m = r / ballR, air = z > 0 ? clamp(z / 0.12, 0, 1) : 0
    let dx = x - tl / 2, dy = y - tw / 2, d = JSMath.hypot(dx, dy), zc = ballR + BallPainter.LIFT_H * lift + max(0, z), t = zc / (BallPainter.LAMP_H - zc)
    let key = portrait ? [LIGHT[1], -LIGHT[0]] : [-LIGHT[0], -LIGHT[1]], lean = ballR * (0.2 + 0.7 * max(lift, air))
    let tx = dx * t + key[0] * lean, ty = dy * t + key[1] * lean
    let (sx, sy) = portrait ? (ty, -tx) : (tx, ty)
    let grow = (1 + 0.6 * lift) * (1 - 0.35 * air) * (1 + 0.1 * min(1, d / 1.2)), w = S.castW * k * grow, cx = X + sx * m, cy = Y + sy * m
    var out: [(CGImage, CGRect, Double)] = []
    if lift < 1 && air < 1 { out.append((S.ao, CGRect(x: X - S.sc * k, y: Y - S.sc * k, width: S.castW * k, height: S.castW * k), alpha * (1 - lift) * (1 - air))) }
    out.append((S.cast, CGRect(x: cx - w / 2, y: cy - w / 2, width: w, height: w), alpha * (1 - 0.5 * lift) * (1 - 0.55 * air)))
    return out
  }

  public static let LAMP_H = 1.1, LIFT_H = 0.045
  /* the table's shadows under a ball at table (x, y), drawn at device (X, Y) radius r; tl, tw the bed, ballR the sim's ball */
  public func drawCast(_ g: Canvas2D, _ x: Double, _ y: Double, _ X: Double, _ Y: Double, _ r: Double, tl: Double, tw: Double, ballR: Double,
                       lift: Double = 0, alpha: Double = 1, z: Double = 0) {
    let S = ballSprites(r), k = r / S.r, m = r / ballR, air = z > 0 ? clamp(z / 0.12, 0, 1) : 0
    let dx = x - tl / 2, dy = y - tw / 2, d = JSMath.hypot(dx, dy), zc = ballR + BallPainter.LIFT_H * lift + max(0, z), t = zc / (BallPainter.LAMP_H - zc)
    let key = portrait ? [LIGHT[1], -LIGHT[0]] : [-LIGHT[0], -LIGHT[1]], lean = ballR * (0.2 + 0.7 * max(lift, air))
    let tx = dx * t + key[0] * lean, ty = dy * t + key[1] * lean
    let (sx, sy) = portrait ? (ty, -tx) : (tx, ty)
    let grow = (1 + 0.6 * lift) * (1 - 0.35 * air) * (1 + 0.1 * min(1, d / 1.2)), w = S.castW * k * grow, cx = X + sx * m, cy = Y + sy * m
    g.setTransform(1, 0, 0, 1, 0, 0)
    if lift < 1 && air < 1 { g.globalAlpha = alpha * (1 - lift) * (1 - air); g.drawImage(S.ao, X - S.sc * k, Y - S.sc * k, S.castW * k, S.castW * k) }
    g.globalAlpha = alpha * (1 - 0.5 * lift) * (1 - 0.55 * air)
    g.drawImage(S.cast, cx - w / 2, cy - w / 2, w, w)
    g.globalAlpha = 1
  }
}
#endif
