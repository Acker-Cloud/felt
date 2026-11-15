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
  /* ROOMS: where each game is played. wall: [height, colour] stops, high to low; seats: [z0, z1, gap deg, colours];
     backdrop: [d0, d1, top, colour]; rig: overhead lights; strips; pine; floor: carpet or boards; near: neighbours */
  public struct Def: Sendable {
    public var near = false, wall: [(Double, String)] = [], seats: (Double, Double, Double, [String])? = nil, backdrop: (Double, Double, Double, String)? = nil
    public var rig = 0, rigCol = "", strips = false, pine = false, blur = 2, floorBase = "#2a1c14", carpet = false, board: [Double] = [78, 52, 36], plank = 0.12
  }
  public static let ROOMS: [String: Def] = [
    "hall": Def(near: true),
    "arena": Def(wall: [(5.5, "#010102"), (2.8, "#040507"), (0.3, "#06070a"), (-0.76, "#020203")], seats: (0.35, 3.1, 0, ["120,140,175", "90,100,120", "160,165,180", "70,80,100"]),
                 rig: 26, rigCol: "205,225,255", blur: 2, floorBase: "#0b0c10", carpet: true),
    "crucible": Def(wall: [(5.5, "#000000"), (3.2, "#030202"), (0.2, "#070504"), (-0.76, "#020101")], seats: (0.22, 2.7, 34, ["150,120,92", "110,90,74", "170,150,128", "84,70,62"]),
                    blur: 2, floorBase: "#100a08", carpet: true),
    "joy": Def(wall: [(5.5, "#030303"), (3.0, "#0a0908"), (0.3, "#100d0b"), (-0.76, "#040303")], seats: (0.3, 2.4, 42, ["170,150,130", "120,105,95", "190,170,150"]),
               backdrop: (-40, 40, 3.0, "120,92,70"), rig: 18, rigCol: "255,226,190", blur: 2, floorBase: "#14110f", carpet: true),
    "carom": Def(near: true, wall: [(5.5, "#3a3730"), (3.2, "#6f685a"), (1.2, "#857d6c"), (0.3, "#4a4438"), (-0.76, "#1a1712")], strips: true, blur: 2,
                 floorBase: "#2a2823", board: [108, 102, 88], plank: 0.3),
    "rec": Def(wall: [(5.5, "#030201"), (2.4, "#0a0603"), (-0.76, "#0c0704")], pine: true, blur: 1, floorBase: "#231b12", board: [104, 76, 46], plank: 0.09),
  ]

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
  public static func paintFloor(_ S: Int, _ id: String = "hall") -> CGImage {
    let RF = ROOMS[id] ?? ROOMS["hall"]!, dressed = id != "hall"
    let Sd = Double(S), K = Sd / (2 * R), g = Canvas2D(width: S, height: S), rnd = cpuRng(11), pw = (dressed ? RF.plank : 0.12) * K
    g.fillStyle(dressed ? RF.floorBase : "#2a1c14"); g.fillRect(0, 0, Sd, Sd)
    /* carpet: a flat speck; or boards in the room's own colour */
    if RF.carpet { for _ in 0..<9000 { let w = rnd() < 0.5; g.fillStyle("rgba(\(w ? "255,255,255" : "0,0,0"),\(0.02 + rnd() * 0.05))"); let x = rnd() * Sd, yy = rnd() * Sd; g.fillRect(x, yy, 1.6, 1.6) } }
    var y = RF.carpet ? Sd : 0.0
    while y < Sd {
      var x = -rnd() * 2 * K
      while x < Sd {
        let L = (1.1 + rnd() * 1.6) * K, l = 0.8 + rnd() * 0.3, w = rnd(), fc = dressed ? RF.board : [78.0, 52, 36]
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
  public static func paintWall(_ W: Int, _ H: Int, _ id: String = "hall") -> CGImage {
    if id != "hall", let RD = ROOMS[id] { return paintDressedWall(W, H, RD) }
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

  /* the other rooms' walls, by the same pipeline (all judgment, no real hall copied) */
  static func paintDressedWall(_ W: Int, _ H: Int, _ RD: Def) -> CGImage {
    let pad = js(Double(W) / 12), Wd = Double(W), Hd = Double(H), g = Canvas2D(width: W + 2 * pad, height: H), rnd = cpuRng(41), cw = Double(W + 2 * pad)
    let Y = { (z: Double) in (TOP - z) / (TOP + FLOOR) * Hd }, X = { (deg: Double) in Double(pad) + deg / 360 * Wd }, mPer = Wd / (2 * Double.pi * R)
    func rep(_ f: () -> Void) { for o in [-Wd, 0, Wd] { g.save(); g.translate(o, 0); f(); g.restore() } }
    let bg = g.createLinearGradient(0, 0, 0, Hd)
    for (z, c) in RD.wall { bg.addColorStop(Swift.min(1, Swift.max(0, Y(z) / Hd)), c) }
    g.fillStyle = .gradient(bg); g.fillRect(0, 0, cw, Hd)
    if let (z0, z1, gap, cols) = RD.seats {
      /* banked seating: rows of dim heads, a dark gap where the room has none (gap, degrees either side of angle 0) */
      var z = z0
      while z < z1 {
        var d = 0.0
        while d < 360 {
          if !(d < gap || d > 360 - gap) {
            let c = cols[Int((rnd() * Double(cols.count)).rounded(.down))], a = (0.25 + rnd() * 0.5) * (1 - 0.55 * (z - z0) / (z1 - z0))
            rep { g.fillStyle("rgba(\(c),\(a))"); g.fillRect(X(d + (rnd() - 0.5) * 0.6), Y(z) - 1, 1.6, 2) }
          }
          d += 1.15
        }
        z += 0.34
      }
      g.fillStyle("rgba(0,0,0,0.75)"); rep { g.fillRect(0, Y(z0 - 0.04), cw, Y(-0.76) - Y(z0 - 0.04)) }
    }
    if let (d0, d1, top, col) = RD.backdrop {
      /* a plain lit backdrop behind the stage, washed from below */
      rep {
        let gr = g.createLinearGradient(0, Y(top), 0, Y(-0.2)); gr.addColorStop(0, "rgba(0,0,0,0)"); gr.addColorStop(0.35, "rgba(\(col),0.55)"); gr.addColorStop(1, "rgba(\(col),0.9)")
        g.fillStyle = .gradient(gr); g.fillRect(X(d0), Y(top), X(d1) - X(d0), Y(-0.2) - Y(top))
      }
    }
    if RD.strips {
      /* rows of strip lights along a pale hall's ceiling */
      var d = 0.0
      while d < 360 { let dd = d; rep { g.fillStyle("rgba(255,250,235,0.85)"); g.fillRect(X(dd), Y(3.05), 12, 3); g.fillStyle("rgba(255,245,225,0.5)"); g.fillRect(X(dd + 9), Y(2.6), 10, 2) }; d += 18 }
      d = 0
      while d < 360 { let dd = d; rep { g.fillStyle("rgba(0,0,0,0.14)"); g.fillRect(X(dd), Y(2.2), 1.5, Y(-0.7) - Y(2.2)) }; d += 12 }
    }
    if RD.pine {
      /* knotty pine: boards with a dark seam and the odd knot, up to a low ceiling */
      var d = 0.0, i = 0
      while d < 360 {
        let l = 0.82 + rnd() * 0.32, c = [js(146 * l), js(96 * l), js(52 * l)], dd = d
        rep { g.fillStyle("rgb(\(c[0]),\(c[1]),\(c[2]))"); g.fillRect(X(dd), Y(2.4), mPer * 0.26, Y(-0.76) - Y(2.4)); g.fillStyle("rgba(30,16,8,0.7)"); g.fillRect(X(dd), Y(2.4), 1, Y(-0.76) - Y(2.4)) }
        if i % 2 == 0 { let kz = 0.1 + rnd() * 2.1, ox = rnd() * 2; rep { g.fillStyle("rgba(46,24,10,0.75)"); g.beginPath(); g.arc(X(dd) + ox, Y(kz), 1.2, 0, 7); g.fill() } }
        d += 1.6; i += 1
      }
      g.fillStyle("rgba(0,0,0,0.62)"); rep { g.fillRect(0, 0, cw, Y(2.4)) }
      let dim = g.createLinearGradient(0, Y(2.4), 0, Hd); dim.addColorStop(0, "rgba(10,6,3,0.72)"); dim.addColorStop(0.5, "rgba(10,6,3,0.42)"); dim.addColorStop(1, "rgba(10,6,3,0.82)")
      g.fillStyle = .gradient(dim); g.fillRect(0, Y(2.4), cw, Hd - Y(2.4))
    }
    let o = Canvas2D(width: W + 2 * pad, height: H)
    o.drawImage(blur(g.image(), RD.blur), 0, 0, cw, Hd)
    o.cg.setBlendMode(.plusLighter)
    for _ in 0..<RD.rig {
      /* the rig: cool lights far overhead */
      let d = rnd() * 360, z = 3.4 + rnd() * 1.4, r = (0.1 + rnd() * 0.12) * mPer * 2.4, a = 0.18 + rnd() * 0.16
      for k in [-Wd, 0, Wd] { bokeh(o, X(d) + k, Y(z), r, RD.rigCol, a) }
    }
    o.cg.setBlendMode(.normal)
    return blur(o.image(), 1).cropping(to: CGRect(x: pad, y: 0, width: W, height: H))!
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
  public static func geo(_ s: Sim, outline: [[Double]], lampH: Double, room: String = "hall") -> Geo {
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
    let near = (ROOMS[room]?.near ?? true) ? [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]].map { [cx + Double($0[0]) * ox, cy + Double($0[1]) * oy] } : []
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
  // MARK: the neighbours' cards
  /* v3PaintNTop: a neighbouring table from above, 3.4 x 2.3 m, lit by its own lamp */
  static func paintNTop() -> CGImage {
    let K = 64.0, g = Canvas2D(width: js(3.4 * K), height: js(2.3 * K)), rnd = cpuRng(5), o = 0.45
    g.fillStyle("#2c1a11"); roundRect(g, o * K, o * K, 2.5 * K, 1.4 * K, 0.06 * K); g.fill()
    g.fillStyle("#2f7560"); g.fillRect((o + 0.13) * K, (o + 0.13) * K, 2.24 * K, 1.14 * K)
    let L = g.createRadialGradient((o + 1.25) * K, (o + 0.7) * K, 0, (o + 1.25) * K, (o + 0.7) * K, 1.3 * K)
    L.addColorStop(0, "rgba(255,240,200,0.4)"); L.addColorStop(1, "rgba(0,0,0,0.35)")
    g.fillStyle = .gradient(L); g.fillRect((o + 0.13) * K, (o + 0.13) * K, 2.24 * K, 1.14 * K)
    for c in ["#d8d2c0", "#c9a43a", "#2d4a9a", "#a8342c", "#5a2e70", "#d07a2a", "#222"] {
      g.fillStyle(c); g.beginPath(); let x = (o + 0.4 + rnd() * 1.7) * K, y = (o + 0.3 + rnd() * 0.8) * K; g.arc(x, y, 0.035 * K, 0, 7); g.fill()
    }
    return blur(g.image(), 4)
  }
  public static let NSIDE = [0.16, -0.34], NSIDE_W = 3.0, NSIDE_EL = [0.2, 0.5]
  /* v3PaintNSide: a neighbouring table side on, as a low eye sees it across the room */
  static func paintNSide() -> CGImage {
    let K = 64.0, W = NSIDE_W, g = Canvas2D(width: js(W * K), height: js((NSIDE[0] - NSIDE[1]) * K)), rnd = cpuRng(9)
    let Y = { (z: Double) in (NSIDE[0] - z) * K }, X = { (x: Double) in (W / 2 + x) * K }, L = 1.3, Lb = 1.05
    let bd = g.createLinearGradient(0, Y(-0.17), 0, Y(-0.32))
    bd.addColorStop(0, "rgba(18,11,7,1)"); bd.addColorStop(1, "rgba(18,11,7,0)")
    g.fillStyle = .gradient(bd); g.fillRect(X(-Lb), Y(-0.17), 2 * Lb * K, 0.15 * K)
    let ap = g.createLinearGradient(0, Y(0), 0, Y(-0.17))
    ap.addColorStop(0, "#7a4a2a"); ap.addColorStop(1, "#2e1b10")
    g.fillStyle = .gradient(ap); g.fillRect(X(-L), Y(0), 2 * L * K, 0.17 * K)
    g.fillStyle("#b07a4a"); g.fillRect(X(-L), Y(0.035), 2 * L * K, 0.035 * K)
    g.fillStyle("#4fae8a"); g.fillRect(X(-L + 0.12), Y(0.06), 2 * (L - 0.12) * K, 0.025 * K)
    for c in ["#e8e2d0", "#d9b240", "#3a5ab0", "#b8402f", "#222"] { g.fillStyle(c); g.beginPath(); let x = X(-0.9 + rnd() * 1.8); g.arc(x, Y(0.085), 0.03 * K, 0, 7); g.fill() }
    return blur(g.image(), 2)
  }
  /* v3PaintLamp: the neighbour's lamp side on, the shade with its lit lip and its glow round and under it */
  static func paintLamp() -> CGImage {
    let K = 64.0, g = Canvas2D(width: js(1.9 * K), height: js(0.66 * K)), y0 = 0.16 * K, y1 = 0.33 * K
    let gr = g.createRadialGradient(0, 0, 0, 0, 0, 1)
    gr.addColorStop(0, "rgba(255,214,160,0.42)"); gr.addColorStop(0.35, "rgba(255,200,140,0.16)"); gr.addColorStop(1, "rgba(255,200,140,0)")
    g.save(); g.translate(0.95 * K, y1); g.scale(0.92 * K, 0.33 * K); g.fillStyle = .gradient(gr); g.fillRect(-1, -1, 2, 2); g.restore()
    g.fillStyle("#121110"); g.beginPath(); g.moveTo(0.3 * K, y0); g.lineTo(1.6 * K, y0); g.lineTo(1.65 * K, y1); g.lineTo(0.25 * K, y1); g.closePath(); g.fill()
    g.fillStyle("rgba(255,214,150,0.9)"); g.fillRect(0.25 * K, y1 - 2, 1.4 * K, 3)
    return blur(g.image(), 3)
  }
  /* v3CardAtlas: the three cards in one 512 x 256 atlas with gutters; at[name] = [u0, v0, u1, v1] */
  public static func cardAtlas() -> (image: CGImage, at: [String: [Double]]) {
    let parts: [(String, CGImage)] = [("top", paintNTop()), ("lamp", paintLamp()), ("side", paintNSide())]
    let W = 512.0, H = 256.0, g = Canvas2D(width: 512, height: 256), gap = 6.0
    var at: [String: [Double]] = [:], x = gap, y = gap, row = 0.0
    for (k, c) in parts {
      let cw = Double(c.width), ch = Double(c.height)
      if x + cw + gap > W { x = gap; y += row + gap; row = 0 }
      g.drawImage(c, x, y, cw, ch)
      at[k] = [(x + 0.5) / W, (y + 0.5) / H, (x + cw - 0.5) / W, (y + ch - 0.5) / H]
      x += cw + gap; row = Swift.max(row, ch)
    }
    return (g.image(), at)
  }
}
#endif
