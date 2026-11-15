/* index.html 4o's room, the hall: painted once on 2D canvases and laid on real geometry round the table, as the page:
   the floor (v3PaintFloor: boards along the table, sharp near and blurred far, the lamp's warm pool falling to black at
   the walls; v3FloorTex: the neighbours' pools of light and this table's shadow laid in), the wall (v3PaintWall: a
   cylinder V3_ROOM_R out, the wainscot, the back bar's shelves and bottles, the cue racks, the sconces, the lights out of
   focus) and this table's lamp (v3RoomGeo's shade on two rods). v3Rng, v3Blur (halved and doubled back) and v3Bokeh are
   the page's. Not yet: the other games' dressed rooms (they wear the hall), the neighbours' cards. */
#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import FeltSim

public enum V3Room {
  public static let R = 9.0, TOP = 5.5, FLOOR = 0.76, FLOOR_R = 7.2

  /* v3Blur: halved `levels` times, then doubled back up, smoothed each step */
  static func blur(_ img: CGImage, _ levels: Int) -> CGImage {
    func scaled(_ i: CGImage, _ w: Int, _ h: Int) -> CGImage {
      let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      c.interpolationQuality = .high
      c.draw(i, in: CGRect(x: 0, y: 0, width: w, height: h))
      return c.makeImage()!
    }
    var chain = [img]
    for _ in 0..<levels { let a = chain.last!; chain.append(scaled(a, Swift.max(1, (a.width + 1) / 2), Swift.max(1, (a.height + 1) / 2))) }
    var i = chain.count - 2
    while i >= 0 { chain[i] = scaled(chain[i + 1], chain[i].width, chain[i].height); i -= 1 }
    return chain[0]
  }
  static func bokeh(_ g: Canvas2D, _ x: Double, _ y: Double, _ r: Double, _ rgb: String, _ a: Double) {
    let gr = g.createRadialGradient(x, y, 0, x, y, r)
    gr.addColorStop(0, "rgba(\(rgb),\(a))"); gr.addColorStop(0.62, "rgba(\(rgb),\(a * 0.85))"); gr.addColorStop(1, "rgba(\(rgb),0)")
    g.fillStyle = .gradient(gr); g.fillRect(x - r, y - r, 2 * r, 2 * r)
  }
  static func roundRect(_ g: Canvas2D, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
    g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath()
  }
  static func js(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

  /* the floor: boards along the table, R each way from the middle; sharp near, blurred far, lit by the lamp */
  public static func paintFloor(_ S: Int) -> CGImage {
    let Sd = Double(S), K = Sd / (2 * R), g = Canvas2D(width: S, height: S), rnd = cpuRng(11), pw = 0.12 * K
    g.fillStyle("#2a1c14"); g.fillRect(0, 0, Sd, Sd)
    var y = 0.0
    while y < Sd {
      var x = -rnd() * 2 * K
      while x < Sd {
        let L = (1.1 + rnd() * 1.6) * K, l = 0.8 + rnd() * 0.3, w = rnd(), fc = [78.0, 52, 36]
        g.fillStyle("rgb(\(js(fc[0] * l + w * 8)),\(js(fc[1] * l + w * 4)),\(js(fc[2] * l)))")
        g.fillRect(x, y, L, pw)
        g.globalAlpha = 0.22; g.strokeStyle("#1c120b"); g.lineWidth = 0.7
        for _ in 0..<3 {
          let yy = y + rnd() * pw
          g.beginPath(); g.moveTo(x, yy)
          let a1 = yy + (rnd() - 0.5) * pw * 0.6, a2 = yy + (rnd() - 0.5) * pw * 0.6, a3 = yy + (rnd() - 0.5) * pw * 0.4
          g.bezierCurveTo(x + L * 0.3, a1, x + L * 0.7, a2, x + L, a3); g.stroke()
        }
        g.globalAlpha = 1
        g.fillStyle("rgba(12,7,4,0.6)"); g.fillRect(x + L - 1, y, 1.2, pw)
        x += L
      }
      g.fillStyle("rgba(10,6,3,0.6)"); g.fillRect(0, y + pw - 1, Sd, 1.2)
      y += pw
    }
    /* farther, blurrier: two blurred copies over the sharp one, each through a ring that opens outward */
    let base = g.image()
    func ring(_ img: CGImage, _ r0: Double, _ r1: Double) -> CGImage {
      let h = Canvas2D(width: S, height: S)
      h.drawImage(img, 0, 0, Sd, Sd)
      let gr = h.createRadialGradient(Sd / 2, Sd / 2, r0 * K, Sd / 2, Sd / 2, r1 * K)
      gr.addColorStop(0, "rgba(0,0,0,0)"); gr.addColorStop(1, "#000")
      h.cg.setBlendMode(.destinationIn); h.fillStyle = .gradient(gr); h.fillRect(0, 0, Sd, Sd); h.cg.setBlendMode(.normal)
      return h.image()
    }
    let B1 = ring(blur(base, 1), 1.6, 3.2), B2 = ring(blur(base, 3), 3.4, 6)
    g.drawImage(B1, 0, 0, Sd, Sd); g.drawImage(B2, 0, 0, Sd, Sd)
    /* the light: the lamp's pool round the table, warm, falling to near black at the walls */
    let Lg = g.createRadialGradient(Sd / 2, Sd / 2, 0, Sd / 2, Sd / 2, R * K)
    Lg.addColorStop(0, "rgb(176,158,136)"); Lg.addColorStop(0.17, "rgb(124,108,92)"); Lg.addColorStop(0.36, "rgb(62,54,48)"); Lg.addColorStop(0.7, "rgb(28,25,23)"); Lg.addColorStop(1, "rgb(10,9,9)")
    g.cg.setBlendMode(.multiply); g.fillStyle = .gradient(Lg); g.fillRect(0, 0, Sd, Sd); g.cg.setBlendMode(.normal)
    return g.image()
  }

  /* the walls: a band W x H round the room, angle 0 (left) the table's +x, top TOP, bottom the floor */
  public static func paintWall(_ W: Int, _ H: Int) -> CGImage {
    let pad = js(Double(W) / 12), Wd = Double(W), Hd = Double(H), g = Canvas2D(width: W + 2 * pad, height: H), rnd = cpuRng(23), cw = Double(W + 2 * pad)
    let Y = { (z: Double) in (TOP - z) / (TOP + FLOOR) * Hd }, X = { (deg: Double) in Double(pad) + deg / 360 * Wd }, mPer = Wd / (2 * Double.pi * R)
    func rep(_ f: () -> Void) { for o in [-Wd, 0, Wd] { g.save(); g.translate(o, 0); f(); g.restore() } }
    let bg = g.createLinearGradient(0, 0, 0, Hd)
    bg.addColorStop(0, "#050404"); bg.addColorStop(Y(2.8) / Hd, "#0d0a09"); bg.addColorStop(Y(1.6) / Hd, "#211813"); bg.addColorStop(Y(0.45) / Hd, "#140e0b")
    bg.addColorStop(Y(0.4) / Hd, "#1c140f"); bg.addColorStop(Y(0.36) / Hd, "#0c0807"); bg.addColorStop(Y(-0.35) / Hd, "#060505"); bg.addColorStop(1, "#040303")
    g.fillStyle = .gradient(bg); g.fillRect(0, 0, cw, Hd)
    /* wainscot panels */
    g.fillStyle("rgba(0,0,0,0.25)")
    var d = 0.0
    while d < 360 { let dd = d; rep { g.fillRect(X(dd), Y(0.36), 1.5, Y(-0.7) - Y(0.36)) }; d += 6 }
    /* the back bar, behind the table's foot (angle 0): shelves lit amber, bottles, a counter with a glow under its lip */
    let bar0 = -22.0, bar1 = 22.0
    rep {
      let x0 = X(bar0), x1 = X(bar1)
      let sh = g.createLinearGradient(0, Y(2.0), 0, Y(0.5))
      sh.addColorStop(0, "rgba(120,84,48,0.2)"); sh.addColorStop(0.5, "rgba(176,122,66,0.55)"); sh.addColorStop(1, "rgba(120,80,44,0.3)")
      g.fillStyle = .gradient(sh); g.fillRect(x0, Y(2.0), x1 - x0, Y(0.5) - Y(2.0))
      for zs in [1.65, 1.2, 0.78] {
        g.fillStyle("rgba(30,20,14,0.9)"); g.fillRect(x0, Y(zs) - 1, x1 - x0, 2)
        var x = x0 + 2
        while x < x1 - 2 {
          let h = (0.18 + rnd() * 0.14) * Hd / (TOP + FLOOR), cs = [[92, 60, 34], [60, 72, 52], [120, 96, 70], [70, 46, 40], [140, 118, 86]][Int((rnd() * 5).rounded(.down))]
          g.fillStyle("rgba(\(cs[0]),\(cs[1]),\(cs[2]),0.9)"); g.fillRect(x, Y(zs) - 1 - h, 1.6, h)
          x += 2 + rnd() * 3
        }
      }
      g.fillStyle("#140d09"); g.fillRect(x0 - 6, Y(0.32), x1 - x0 + 12, Y(-0.76) - Y(0.32))
      g.fillStyle("rgba(190,130,70,0.5)"); g.fillRect(x0 - 6, Y(0.28), x1 - x0 + 12, 2)
    }
    /* cue racks on the side walls */
    for dg in [90.0, 270] {
      rep {
        let x0 = X(dg) - 0.5 * mPer, w = 1.0 * mPer
        g.fillStyle("#1a110c"); g.fillRect(x0, Y(1.75), w, Y(0.15) - Y(1.75))
        for i in 0..<9 { g.fillStyle(i % 3 != 0 ? "rgba(200,170,120,0.55)" : "rgba(120,84,56,0.7)"); g.fillRect(x0 + (Double(i) + 0.6) * w / 10, Y(1.68), 1.2, Y(0.2) - Y(1.68)) }
      }
    }
    /* sconces: a warm wash up and down the wall */
    let skip = { (d: Double) in d > 360 + bar0 - 12 || d < bar1 + 12 || abs(d - 90) < 12 || abs(d - 270) < 12 }
    d = 15
    while d < 360 {
      if !skip(d) {
        let dd = d
        rep {
          let x = X(dd), y = Y(1.9), gr = g.createRadialGradient(x, y, 0, x, y, 1.3 * mPer * 1.6)
          gr.addColorStop(0, "rgba(255,196,128,0.5)"); gr.addColorStop(0.35, "rgba(200,140,84,0.18)"); gr.addColorStop(1, "rgba(120,80,50,0)")
          g.save(); g.translate(x, y); g.scale(0.7, 1.15); g.translate(-x, -y); g.fillStyle = .gradient(gr); g.fillRect(x - 3 * mPer, y - 3 * mPer, 6 * mPer, 6 * mPer); g.restore()
        }
      }
      d += 30
    }
    let o = Canvas2D(width: W + 2 * pad, height: H)
    o.drawImage(blur(g.image(), 3), 0, 0, cw, Hd)
    o.cg.setBlendMode(.plusLighter)
    /* the lights out of focus: the sconces' bulbs, the bar's bottles and lamps far off */
    d = 15
    while d < 360 { if !skip(d) { for k in [-Wd, 0, Wd] { bokeh(o, X(d) + k, Y(1.9), 0.16 * mPer * 2.4, "255,200,140", 0.35) } }; d += 30 }
    for _ in 0..<26 {
      let dd = bar0 + rnd() * (bar1 - bar0), z = 0.6 + rnd() * 1.3, r = (0.07 + rnd() * 0.1) * mPer * 2.4, c = ["255,190,120", "230,210,170", "255,160,96", "200,190,160"][Int((rnd() * 4).rounded(.down))]
      let a = 0.12 + rnd() * 0.12
      for k in [-Wd, 0, Wd] { bokeh(o, X(dd) + k, Y(z), r, c, a) }
    }
    for _ in 0..<40 {
      let dd = rnd() * 360, z = 0.9 + rnd() * 1.8, r = (0.08 + rnd() * 0.16) * mPer * 2.4, a = 0.04 + rnd() * 0.07
      for k in [-Wd, 0, Wd] { bokeh(o, X(dd) + k, Y(z), r, "255,206,150", a) }
    }
    o.cg.setBlendMode(.normal)
    let out = blur(o.image(), 1)
    return out.cropping(to: CGRect(x: pad, y: 0, width: W, height: H))!
  }

  /* v3PaintShadow: the table's soft shadow on the floor */
  static func paintShadow() -> CGImage {
    let g = Canvas2D(width: 128, height: 64)
    g.fillStyle("#000"); roundRect(g, 16, 14, 96, 36, 10); g.fill()
    return blur(g.image(), 3)
  }

  public struct Geo: Sendable {
    public let wall: [Float], nWall: Int, floor: [Float], nFloor: Int, lamp: [Float], nLamp: Int, lampZ: Double, lampBox: [Double], near: [[Double]], foot: [Double]
  }
  /* v3RoomGeo: the wall (a cylinder) and the floor (a polar grid from under the rails' edge out to the wall) as
     [x, y, z, u, v] in the render frame, this table's lamp as mesh vertices, the neighbours' places, the shadow's size */
  public static func geo(_ s: Sim, outline: [[Double]], lampH: Double) -> Geo {
    let TL = s.TL, TW = s.TW, cx = TL / 2, cy = TW / 2, N = 64
    func inner(_ a: Double) -> [Double] {
      let dx = cos(a), dy = sin(a)
      var best = 1e9
      for i in outline.indices {
        let p = outline[i], q = outline[(i + 1) % outline.count], ex = q[0] - p[0], ey = q[1] - p[1], den = dx * ey - dy * ex
        if abs(den) < 1e-12 { continue }
        let t = ((p[0] - cx) * ey - (p[1] - cy) * ex) / den, u = ((p[0] - cx) * dy - (p[1] - cy) * dx) / den
        if t > 0 && u >= -1e-9 && u <= 1 + 1e-9 { best = Swift.min(best, t) }
      }
      return [cx + dx * Swift.min(best, R * 0.5), cy + dy * Swift.min(best, R * 0.5)]
    }
    func uv(_ x: Double, _ y: Double) -> [Float] { [Float((x - cx) / (2 * R) + 0.5), Float((y - cy) / (2 * R) + 0.5)] }
    let RF = [0, 0.015, 0.035, 0.06, 0.09, 0.13, 0.18, 0.25, 0.34, 0.46, 0.6, 0.78, 1.0], NF = 128
    var grid: [[[Double]]] = []
    for i in 0..<NF {
      let a = Double(i) / Double(NF) * 2 * Double.pi, q = inner(a), o = [cx + FLOOR_R * cos(a), cy + FLOOR_R * sin(a)]
      grid.append(RF.map { f in [q[0] + (o[0] - q[0]) * f, q[1] + (o[1] - q[1]) * f] })
    }
    var floor: [Float] = []
    for i in 0..<NF {
      let a = grid[i], b = grid[(i + 1) % NF]
      for j in 0..<(RF.count - 1) {
        for q in [a[j], a[j + 1], b[j + 1], a[j], b[j + 1], b[j]] { floor += [Float(q[0]), Float(q[1]), Float(FLOOR)] + uv(q[0], q[1]) }
      }
    }
    var wall: [Float] = []
    for i in 0..<N {
      let a0 = Double(i) / Double(N) * 2 * Double.pi, a1 = Double(i + 1) / Double(N) * 2 * Double.pi, u0 = Float(Double(i) / Double(N)), u1 = Float(Double(i + 1) / Double(N))
      let x0 = Float(cx + R * cos(a0)), y0 = Float(cy + R * sin(a0)), x1 = Float(cx + R * cos(a1)), y1 = Float(cy + R * sin(a1))
      let T0: [Float] = [x0, y0, Float(-TOP), u0, 0], T1: [Float] = [x1, y1, Float(-TOP), u1, 0], B0: [Float] = [x0, y0, Float(FLOOR), u0, 1], B1: [Float] = [x1, y1, Float(FLOOR), u1, 1]
      for q in [T0, T1, B1, T0, B1, B0] { wall += q }
    }
    /* the lamp: a shade (a frustum, its underside the diffuser) on two rods up into the dark */
    var lamp: [Float] = []
    let lw = Swift.min(2, Swift.max(0.45, TL * 0.5)) / 2, ld = Swift.min(0.6, Swift.max(0.28, TW * 0.34)) / 2, zb = lampH - 0.06, zt = zb + 0.17, ins = 0.05
    func v(_ p: [Double], _ c: [Double]) { lamp += [Float(p[0]), Float(p[1]), Float(-p[2]), 0, 0, -1, Float(c[0]), Float(c[1]), Float(c[2]), 1] }
    func quadL(_ a: [Double], _ b: [Double], _ c2: [Double], _ d: [Double], _ ca: [Double], _ cb: [Double]) { v(a, ca); v(b, ca); v(c2, cb); v(a, ca); v(c2, cb); v(d, cb) }
    let bot = [[cx - lw, cy - ld], [cx + lw, cy - ld], [cx + lw, cy + ld], [cx - lw, cy + ld]]
    let tp = [[cx - lw + ins, cy - ld + ins], [cx + lw - ins, cy - ld + ins], [cx + lw - ins, cy + ld - ins], [cx - lw + ins, cy + ld - ins]]
    let side = [0.17, 0.155, 0.13], dark = [0.05, 0.05, 0.048], diff = [0.72, 0.62, 0.48], diffE = [0.36, 0.3, 0.22]
    for i in 0..<4 { let j = (i + 1) % 4; quadL(tp[i] + [zt], tp[j] + [zt], bot[j] + [zb], bot[i] + [zb], dark, side) }
    quadL(tp[0] + [zt], tp[1] + [zt], tp[2] + [zt], tp[3] + [zt], dark, dark)
    let e = 0.012
    for (y0, y1, c0, c1) in [(cy - ld + e, cy, diffE, diff), (cy, cy + ld - e, diff, diffE)] {
      quadL([cx - lw + e, y0, zb + 0.01], [cx + lw - e, y0, zb + 0.01], [cx + lw - e, y1, zb + 0.01], [cx - lw + e, y1, zb + 0.01], c0, c1)
    }
    for x in [cx - lw * 0.6, cx + lw * 0.6] {
      let r = 0.006, rod = [[x - r, cy - r], [x + r, cy - r], [x + r, cy + r], [x - r, cy + r]], rc = [0.12, 0.115, 0.11]
      for i in 0..<4 { let j = (i + 1) % 4; quadL(rod[i] + [TOP], rod[j] + [TOP], rod[j] + [zt], rod[i] + [zt], dark, rc) }
    }
    /* the neighbours: across the room on a grid clear of this table and its players (a hall has them) */
    var hx = 0.0, hy = 0.0
    for q in outline { hx = Swift.max(hx, abs(q[0] - cx)); hy = Swift.max(hy, abs(q[1] - cy)) }
    let ox = Swift.max(4.4, hx + 1.25 + 1.6), oy = Swift.max(3.3, hy + 0.7 + 1.5)
    let near = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]].map { [cx + Double($0[0]) * ox, cy + Double($0[1]) * oy] }
    return Geo(wall: wall, nWall: wall.count / 5, floor: floor, nFloor: floor.count / 5, lamp: lamp, nLamp: lamp.count / 10, lampZ: zb,
               lampBox: [cx - lw, cy - ld, zb, cx + lw, cy + ld, TOP], near: near, foot: [hx, hy])
  }
  /* v3FloorTex: the painted boards with the neighbours' pools of light and this table's shadow laid in */
  public static func floorTex(_ base: CGImage, _ s: Sim, _ G: Geo) -> CGImage {
    let S = base.width, Sd = Double(S), K = Sd / (2 * R), g = Canvas2D(width: S, height: S)
    let X = { (x: Double) in Sd / 2 + (x - s.TL / 2) * K }, Y = { (y: Double) in Sd / 2 + (y - s.TW / 2) * K }
    g.drawImage(base, 0, 0, Sd, Sd)
    g.cg.setBlendMode(.plusLighter)
    for p in G.near {
      let gr = g.createRadialGradient(0, 0, 0, 0, 0, 1)
      gr.addColorStop(0, "rgba(36,29,20,1)"); gr.addColorStop(0.25, "rgba(20,16,11,1)"); gr.addColorStop(0.6, "rgba(5,4,3,1)"); gr.addColorStop(1, "rgba(0,0,0,1)")
      g.save(); g.translate(X(p[0]), Y(p[1])); g.scale(2.0 * K, 1.5 * K); g.fillStyle = .gradient(gr); g.fillRect(-1, -1, 2, 2); g.restore()
    }
    g.cg.setBlendMode(.normal)
    let hx = (G.foot[0] + 0.25) * 1.33, hy = (G.foot[1] + 0.25) * 1.78
    g.globalAlpha = 0.82; g.drawImage(paintShadow(), X(s.TL / 2 - hx), Y(s.TW / 2 - hy), 2 * hx * K, 2 * hy * K); g.globalAlpha = 1
    return g.image()
  }
}
#endif
