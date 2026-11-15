/* Section 4a of index.html (the table, painted once per layout) and its vignette, line for line on
   Canvas2D: the room's glow, the table's shadow on the floor, the grained rails and their bullnose,
   the sights, the cloth, the pocket caps and drops, the cushions and their shadow, the nap and the
   lamp, the cushions' shade, the bevels, the pocket lips and the markings. Same names, same order,
   the same rng(0x5eed) sequence, so the grain and the nap land where the page puts them.
   tools/ios-pixels.cjs makes the references; FeltRenderTests measures the difference. */
#if canImport(CoreGraphics)
import CoreGraphics
import FeltSim
import Foundation

/* the page's rng (sim 1f): mulberry32 */
public func feltRng(_ seed: UInt32) -> () -> Double {
  var a = seed
  return {
    a = a &+ 0x6d2b79f5
    var t = a
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4294967296
  }
}

public struct ClothLook: Sendable { public let base, cushion, lamp: String; public let worsted: Bool }
public struct RailLook: Sendable {
  public let base: String; public let dark, lite: [Double]; public let mat, metal, sight: String?
}
public struct RoomLook: Sendable { public let glow: String; public let glowA: Double }
public struct TableLook: Sendable {
  public let cloth: ClothLook, rail: RailLook, room: RoomLook
  /* GAME_LOOK's cloth, rail and room for each game (index.html 4l) */
  public static func of(game: String) -> TableLook {
    switch game {
    case "9": return TableLook(cloth: CLOTH["tourney"]!, rail: RAILS["lacquer"]!, room: ROOM["arena"]!)
    case "10": return TableLook(cloth: CLOTH["electric"]!, rail: RAILS["ebony"]!, room: ROOM["arena"]!)
    case "heyball": return TableLook(cloth: CLOTH["joy"]!, rail: RAILS["arena"]!, room: ROOM["joy"]!)
    case "snooker": return TableLook(cloth: CLOTH["baize"]!, rail: RAILS["baulk"]!, room: ROOM["crucible"]!)
    case "carom": return TableLook(cloth: CLOTH["blue"]!, rail: RAILS["carom"]!, room: ROOM["carom"]!)
    case "bumper": return TableLook(cloth: CLOTH["olive"]!, rail: RAILS["veneer"]!, room: ROOM["rec"]!)
    default: return TableLook(cloth: CLOTH["green"]!, rail: RAILS["walnut"]!, room: ROOM["hall"]!)
    }
  }
  public static let CLOTH: [String: ClothLook] = [
    "green": ClothLook(base: "#1b5d47", cushion: "#1d6450", lamp: "255,248,220", worsted: false),
    "blue": ClothLook(base: "#1d4f91", cushion: "#21579c", lamp: "235,240,255", worsted: false),
    "tourney": ClothLook(base: "#1f5fa8", cushion: "#2367b3", lamp: "235,240,255", worsted: true),
    "electric": ClothLook(base: "#1566b8", cushion: "#186fc4", lamp: "235,242,255", worsted: true),
    "baize": ClothLook(base: "#1f6b3a", cushion: "#22733f", lamp: "255,248,220", worsted: false),
    "joy": ClothLook(base: "#1e6340", cushion: "#206a45", lamp: "255,250,230", worsted: false),
    "olive": ClothLook(base: "#4f6030", cushion: "#586a35", lamp: "255,244,210", worsted: false),
  ]
  public static let RAILS: [String: RailLook] = [
    "walnut": RailLook(base: "#4f2714", dark: [44, 19, 9], lite: [140, 78, 40], mat: nil, metal: nil, sight: nil),
    "ebony": RailLook(base: "#1d1613", dark: [9, 7, 6], lite: [78, 62, 52], mat: nil, metal: nil, sight: nil),
    "lacquer": RailLook(base: "#100f11", dark: [6, 6, 7], lite: [34, 33, 36], mat: "lacquer", metal: "chrome", sight: "dot"),
    "baulk": RailLook(base: "#7c5228", dark: [86, 52, 22], lite: [190, 142, 86], mat: nil, metal: "brass", sight: nil),
    "arena": RailLook(base: "#2a1a12", dark: [16, 9, 6], lite: [92, 62, 42], mat: nil, metal: "leather", sight: nil),
    "carom": RailLook(base: "#33201a", dark: [20, 11, 8], lite: [104, 70, 54], mat: nil, metal: nil, sight: "dot"),
    "veneer": RailLook(base: "#5c3a1e", dark: [58, 34, 16], lite: [148, 104, 62], mat: nil, metal: nil, sight: nil),
  ]
  public static let ROOM: [String: RoomLook] = [
    "hall": RoomLook(glow: "255,240,215", glowA: 0.07), "arena": RoomLook(glow: "205,222,255", glowA: 0.06),
    "crucible": RoomLook(glow: "255,226,180", glowA: 0.05), "joy": RoomLook(glow: "255,232,200", glowA: 0.07),
    "carom": RoomLook(glow: "245,245,235", glowA: 0.09), "rec": RoomLook(glow: "255,210,150", glowA: 0.1),
  ]
}

/* the page's view: table metres to CSS px (toScreen), at dpr device px a CSS px */
public struct TableView2D: Sendable {
  public var k: Double, ox: Double, oy: Double, portrait: Bool
  public init(k: Double, ox: Double, oy: Double, portrait: Bool) { self.k = k; self.ox = ox; self.oy = oy; self.portrait = portrait }
}

public let LIGHT = [-0.55, -0.835]
public let RAIL_MAX = 0.115, RAIL_MIN = 0.10

private let CAP_METAL: [String: [String]] = ["nickel": ["#e2dfd8", "#a4a19b", "#5d5a55"], "brass": ["#f3dc96", "#b8923e", "#67501f"],
  "chrome": ["#f6f8fb", "#b6bac2", "#585c64"], "leather": ["#46403b", "#221f1c", "#0f0e0d"]]
private let JAW_ROUND = 0.0035, SIDE_RING = 0.006, SIDE_WOOD = 0.0015

public final class TablePainter {
  let s: Sim, view: TableView2D, dpr: Double, RAIL: Double, look: TableLook, pageColor: String
  var TL: Double { s.TL }
  var TW: Double { s.TW }

  public init(sim: Sim, view: TableView2D, dpr: Double, rail: Double, look: TableLook, pageColor: String = "rgb(15, 15, 16)") {
    s = sim; self.view = view; self.dpr = dpr; RAIL = rail; self.look = look; self.pageColor = pageColor
  }

  func toScreen(_ x: Double, _ y: Double) -> (Double, Double) {
    view.portrait ? (view.ox + y * view.k, view.oy + (TL - x) * view.k) : (view.ox + x * view.k, view.oy + y * view.k)
  }
  func tableXform(_ c: Canvas2D) {
    let k = view.k * dpr
    if view.portrait { c.setTransform(0, -k, k, 0, view.ox * dpr, (view.oy + TL * view.k) * dpr) }
    else { c.setTransform(k, 0, 0, k, view.ox * dpr, view.oy * dpr) }
  }
  func tdir(_ sx: Double, _ sy: Double) -> [Double] { view.portrait ? [-sy, sx] : [sx, sy] }
  func cushionDepth() -> Double {
    var d = 0.02
    for p in s.CUSHION_POLYS { for q in p { d = max(d, -q[0], -q[1], q[0] - TL, q[1] - TW) } }
    return min(d, RAIL - 0.02)
  }
  func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }
  func capW(_ co: Double) -> Double { clampD(0.5 * (RAIL - co), 0.012, 0.032) }
  func capBack(_ co: Double) -> Double { clampD(0.3 * (RAIL - co), 0.006, 0.014) }
  func capGap(_ co: Double) -> Double { clampD(0.12 * (RAIL - co), 0.004, 0.008) }
  func circle(_ g: Canvas2D, _ x: Double, _ y: Double, _ r: Double) { g.beginPath(); g.arc(x, y, r, 0, Double.pi * 2) }
  func polyPath(_ g: Canvas2D, _ p: [[Double]]) {
    for (i, q) in p.enumerated() { i == 0 ? g.moveTo(q[0], q[1]) : g.lineTo(q[0], q[1]) }
    g.closePath()
  }
  func jawRadius(_ p: [Double]) -> Double {
    s.JAW_ARCS.isEmpty ? 0 : s.JAW_RAD[abs(p[0] - TL / 2) < TL / 4 ? 1 : 0]
  }

  /* drawTableImage: the table into a new w x h device-px canvas, with the game screen's vignette */
  public func paint(width w: Int, height h: Int, vignette: Bool = true) -> Canvas2D {
    let c = paintTable(w, h)
    if vignette { paintVignette(c) }
    return c
  }

  func paintVignette(_ g: Canvas2D) {
    tableXform(g)
    let ax = TL / 2 + RAIL, ay = TW / 2 + RAIL
    g.save()
    g.translate(TL / 2, TW / 2); g.scale(ax, ay)
    let gr = g.createRadialGradient(0, 0, 0, 0, 0, 1.75)
    gr.addColorStop(0, "rgba(0,0,0,0)"); gr.addColorStop(0.45, "rgba(0,0,0,0)"); gr.addColorStop(0.65, "rgba(0,0,0,0.1)")
    gr.addColorStop(0.85, "rgba(0,0,0,0.25)"); gr.addColorStop(1, "rgba(0,0,0,0.42)")
    g.fillStyle = .gradient(gr); g.fillRect(-4, -4, 8, 8)
    g.restore()
  }

  // MARK: pockets

  /* the bottom rail's row (6b2): where the wood band runs (its depth from the nose, co to RAIL) and the sights on it */
  public var railBand: (co: Double, rail: Double) { (cushionDepth(), RAIL) }
  public func railSights() -> [[Double]] {
    if s.TABLE == "snooker" { return [] }
    let co = cushionDepth(), q = sightsAt(co)
    return q.at.map { [$0[0], $0[1], $0[2] != 0 ? q.hw : q.hl, $0[2] != 0 ? q.hl : q.hw] }
  }

  /* what the pot animation clips to (4c drawPots): pocket k's cap centre and back radius, and the cushion depth */
  public func potClip(_ k: Int) -> (cx: Double, cy: Double, rb: Double, co: Double) {
    let co = cushionDepth(), sp = pocketShape(k, co)
    return (sp.C[0], sp.C[1], sp.rb, co)
  }

  struct PocketShape { var P: [Double], C: [Double], r: Double, rc: Double, rb: Double, quad: [[Double]], side: Bool }
  private var shapes: [PocketShape] = []
  func pocketShape(_ k: Int, _ co: Double) -> PocketShape {
    if shapes.isEmpty { shapes = s.POCKETS.indices.map { pocketFit($0, co) } }
    return shapes[k]
  }
  func pocketFit(_ k: Int, _ co: Double) -> PocketShape {
    let P = s.POCKETS[k], A = s.POCKET_AIM[k], r = s.POCKET_R[k], cb = capBack(co), m = capGap(co)
    let d = JSMath.hypot(P[0] - A[0], P[1] - A[1]), ux = (P[0] - A[0]) / d, uy = (P[1] - A[1]) / d
    var jaws = s.CUSHION_POLYS.flatMap { q in [[q[1], q[0]], [q[2], q[3]]] }
    jaws = jaws.enumerated().sorted { l, r in
      let a = JSMath.hypot(l.element[0][0] - A[0], l.element[0][1] - A[1]), b = JSMath.hypot(r.element[0][0] - A[0], r.element[0][1] - A[1])
      return a != b ? a < b : l.offset < r.offset
    }.map { $0.element }
    let quad = [jaws[0][0], jaws[0][1], jaws[1][1], jaws[1][0]]
    if k == 1 || k == 4 {
      let back = abs(P[1] - (P[1] < TW / 2 ? 0 : TW)) + r
      return PocketShape(P: P, C: P, r: r, rc: r + max(0.002, min(SIDE_RING, RAIL - SIDE_WOOD - back)), rb: r, quad: quad, side: true)
    }
    func centre(_ rc: Double) -> [Double] {
      var t = Double.infinity
      let e = rc + m
      if ux < -1e-9 { t = min(t, (e - RAIL - A[0]) / ux) } else if ux > 1e-9 { t = min(t, (TL + RAIL - e - A[0]) / ux) }
      if uy < -1e-9 { t = min(t, (e - RAIL - A[1]) / uy) } else if uy > 1e-9 { t = min(t, (TW + RAIL - e - A[1]) / uy) }
      return [A[0] + ux * t, A[1] + uy * t]
    }
    var pts: [[Double]] = []
    for i in 0..<180 { let a = Double(i) * Double.pi / 90; pts.append([P[0] + r * JSMath.cos(a), P[1] + r * JSMath.sin(a)]) }
    let lo = r + capW(co)
    for b in [cb, 0.8 * cb, 0.65 * cb, 0.5 * cb, 0.4 * cb, cb / 3] {
      var rc = lo
      while rc < 2 * lo {
        let C = centre(rc)
        if pts.allSatisfy({ JSMath.hypot($0[0] - C[0], $0[1] - C[1]) <= rc - b - 0.0003 }) {
          return PocketShape(P: P, C: C, r: r, rc: rc, rb: rc - b, quad: quad, side: false)
        }
        rc += 0.0005
      }
    }
    return PocketShape(P: P, C: centre(lo), r: r, rc: lo, rb: lo - cb / 3, quad: quad, side: false)
  }

  // MARK: paintTable

  func paintTable(_ w: Int, _ h: Int) -> Canvas2D {
    shapes = []
    let g = Canvas2D(width: w, height: h), co = cushionDepth(), L = tdir(LIGHT[0], LIGHT[1]), K = view.k * dpr, px = 1 / K, rnd = feltRng(0x5eed)
    g.fillStyle(pageColor); g.fillRect(0, 0, Double(w), Double(h))
    let m = toScreen(TL / 2, TW / 2)
    var gr = g.createRadialGradient(m.0 * dpr, m.1 * dpr, 0, m.0 * dpr, m.1 * dpr, JSMath.hypot(Double(w), Double(h)) / 2)
    gr.addColorStop(0, "rgba(\(look.room.glow),\(look.room.glowA))"); gr.addColorStop(1, "rgba(\(look.room.glow),0)")
    g.fillStyle = .gradient(gr); g.fillRect(0, 0, Double(w), Double(h))
    tableXform(g)
    g.save()
    g.shadow("rgba(0,0,0,0.65)", blur: 0.07 * K, x: -LIGHT[0] * 0.025 * K, y: -LIGHT[1] * 0.025 * K)
    g.fillStyle("#2a140a"); railOutline(g, co); g.fill()
    g.restore()
    if s.BED_LINES != nil { paintOctaRails(g, co, L, px, rnd) } else { paintRails(g, co, L, px, rnd) }
    if !s.BUMPERS.isEmpty { paintBumperTable(g, co, L, px, K, rnd); return g }
    if s.TABLE != "snooker" { paintSights(g, co, L, px) }
    g.fillStyle(look.cloth.base); g.fillRect(-co, -co, TL + 2 * co, TW + 2 * co)
    paintPocketCaps(g, co, L, px)
    paintHoles(g, co, L, px)
    paintCushions(g, co, K)
    paintClothLight(g, co, rnd)
    paintCushionAO(g, co)
    paintBevels(g, co, L, px)
    paintPocketLips(g, co, L, px)
    if s.TABLE == "carom" { paintCaromSpots(g, px); return g }
    if s.TABLE == "snooker" { paintSnookerMarks(g, px) }
    else {
      g.strokeStyle("rgba(255,255,255,0.09)"); g.lineWidth = 1.2 * px
      g.beginPath(); g.moveTo(s.HEAD_X, 0); g.lineTo(s.HEAD_X, TW); g.stroke()
      g.fillStyle("rgba(255,255,255,0.42)")
      g.beginPath(); g.arc(s.FOOT[0], s.FOOT[1], 0.0045, 0, Double.pi * 2); g.fill()
      g.fillStyle("rgba(255,255,255,0.2)")
      g.beginPath(); g.arc(s.HEAD_X, TW / 2, 0.0032, 0, Double.pi * 2); g.fill()
    }
    _ = gr; gr = g.createLinearGradient(0, 0, 0, 0)
    return g
  }

  func railOutline(_ g: Canvas2D, _ co: Double) { g.beginPath(); railPath(g, co) }
  func railPath(_ g: Canvas2D, _ co: Double) {
    if s.BED_LINES != nil {   /* the octagonal bumper table: the rail's eight sides, corners eased */
      let P = s.octagon(RAIL), r = 0.012, n = P.count
      func mid(_ a: [Double], _ b: [Double]) -> [Double] { [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2] }
      let st = mid(P[n - 1], P[0])
      g.moveTo(st[0], st[1])
      for i in 0..<n { let q = mid(P[i], P[(i + 1) % n]); g.arcTo(P[i][0], P[i][1], q[0], q[1], r) }
      g.closePath()
      return
    }
    let r = s.MOUTHS.isEmpty ? min(0.045, RAIL) : min(pocketShape(0, co).rc + capGap(co), RAIL + co)
    let x0 = -RAIL, y0 = -RAIL, x1 = TL + RAIL, y1 = TW + RAIL
    g.moveTo(x0 + r, y0); g.arcTo(x1, y0, x1, y1, r); g.arcTo(x1, y1, x0, y1, r); g.arcTo(x0, y1, x0, y0, r); g.arcTo(x0, y0, x1, y0, r); g.closePath()
  }

  func paintRails(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double, _ rnd: () -> Double) {
    let E = RAIL
    struct Board { let q: [[Double]]; let along: Int; let a: [Double]; let n: [Double] }
    let boards = [
      Board(q: [[-E, -E], [TL + E, -E], [TL + co, -co], [-co, -co]], along: 0, a: [-co, -E], n: [0, -1]),
      Board(q: [[-E, TW + E], [TL + E, TW + E], [TL + co, TW + co], [-co, TW + co]], along: 0, a: [TW + co, TW + E], n: [0, 1]),
      Board(q: [[-E, -E], [-E, TW + E], [-co, TW + co], [-co, -co]], along: 1, a: [-co, -RAIL], n: [-1, 0]),
      Board(q: [[TL + E, -E], [TL + E, TW + E], [TL + co, TW + co], [TL + co, -co]], along: 1, a: [TL + co, TL + RAIL], n: [1, 0]),
    ]
    let RW = look.rail, DARK = RW.dark, LITE = RW.lite
    for b in boards {
      let at = { (u: Double, a: Double) -> (Double, Double) in b.along == 1 ? (a, u) : (u, a) }
      let len = (b.along == 1 ? TW : TL) + 2 * E, a0 = b.a[0], a1 = b.a[1], w = a1 - a0
      let ws = (w > 0 ? 1.0 : w < 0 ? -1.0 : 0) * (RAIL - co)
      g.save()
      railOutline(g, co); g.clip()
      g.beginPath(); polyPath(g, b.q); g.clip()
      g.fillStyle(RW.base); g.fillRect(-E, -E, TL + 2 * E, TW + 2 * E)
      let lines = Int(ceil(abs(w) / (1.4 * px)))
      for i in 0..<(lines + 6) {
        let broad = i < 6, t = rnd()
        let base = a0 + (broad ? ws * rnd() : w * (Double(i - 6) + rnd()) / Double(lines))
        let f1 = 2 * Double.pi / (0.5 + rnd() * 1.2), f2 = 2 * Double.pi / (0.09 + rnd() * 0.12), p1 = rnd() * 7, p2 = rnd() * 7
        let A1 = abs(ws) * (broad ? 0.25 : 0.06 + rnd() * 0.08), A2 = abs(ws) * 0.01
        let col = (0..<3).map { j in (DARK[j] + (LITE[j] - DARK[j]) * t).rounded(.toNearestOrAwayFromZero) }
        let alpha = broad ? 0.16 : 0.16 + rnd() * 0.3
        g.strokeStyle = .color(RGBA(col[0] / 255, col[1] / 255, col[2] / 255, alpha))
        g.lineWidth = broad ? abs(ws) * (0.15 + rnd() * 0.2) : px * (0.7 + rnd() * 1.8)
        g.beginPath()
        var u = -E
        while u <= len - E + 0.02 {
          let (x, y) = at(u, base + A1 * JSMath.sin(u * f1 + p1) + A2 * JSMath.sin(u * f2 + p2))
          u == -E ? g.moveTo(x, y) : g.lineTo(x, y)
          u += 0.02
        }
        g.stroke()
      }
      let f = max(0, b.n[0] * L[0] + b.n[1] * L[1]), (ix, iy) = at(0, a0), (ox, oy) = at(0, a0 + ws)
      let gr = g.createLinearGradient(ix, iy, ox, oy)
      gr.addColorStop(0, "rgba(0,0,0,0.18)"); gr.addColorStop(0.1, "rgba(255,225,190,0.03)")
      gr.addColorStop(0.55, RGBA(1, 225.0 / 255, 190.0 / 255, 0.04 + 0.08 * f)); gr.addColorStop(1, RGBA(1, 225.0 / 255, 190.0 / 255, 0.04 + 0.08 * f))
      g.fillStyle = .gradient(gr); g.fillRect(-E, -E, TL + 2 * E, TW + 2 * E)
      if RW.mat == "lacquer" {
        let sh = g.createLinearGradient(ix, iy, ox, oy)
        sh.addColorStop(0.2, "rgba(255,255,255,0)"); sh.addColorStop(0.52, RGBA(235.0 / 255, 240.0 / 255, 1, 0.1 + 0.14 * f)); sh.addColorStop(0.82, "rgba(255,255,255,0)")
        g.fillStyle = .gradient(sh); g.fillRect(-E, -E, TL + 2 * E, TW + 2 * E)
      }
      g.restore()
    }
    let K = 1 / px
    let edge = { (color: String, blur: Double, off: Double) in
      g.shadow(color, blur: blur * K, x: LIGHT[0] * off * K, y: LIGHT[1] * off * K)
      g.beginPath(); g.rect(-E - 1, -E - 1, self.TL + 2 * E + 2, self.TW + 2 * E + 2); self.railPath(g, co)
      g.fill(.evenodd)
    }
    g.save()
    railOutline(g, co); g.clip()
    g.fillStyle("#000")
    edge("rgba(255,232,205,0.3)", 0.014, -0.008)
    edge("rgba(0,0,0,0.32)", 0.012, 0.007)
    edge("rgba(0,0,0,0.7)", 0.005, 0)
    g.restore()
    g.save()
    railOutline(g, co); g.clip()
    g.strokeStyle("rgba(0,0,0,0.4)"); g.lineWidth = px
    for q in [[-RAIL, -RAIL, -co, -co], [TL + RAIL, -RAIL, TL + co, -co], [-RAIL, TW + RAIL, -co, TW + co], [TL + RAIL, TW + RAIL, TL + co, TW + co]] {
      g.beginPath(); g.moveTo(q[0], q[1]); g.lineTo(q[2], q[3]); g.stroke()
    }
    g.restore()
  }

  func paintPocketCaps(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double) {
    if s.POCKETS.isEmpty { return }
    let CM = CAP_METAL[look.rail.metal ?? "nickel"] ?? CAP_METAL["nickel"]!
    g.save()
    let noses = s.CUSHION_POLYS.flatMap { [$0[1], $0[2]] }.enumerated().sorted { l, r in
      let a = atan2(l.element[1] - TW / 2, l.element[0] - TL / 2), b = atan2(r.element[1] - TW / 2, r.element[0] - TL / 2)
      return a != b ? a < b : l.offset < r.offset
    }.map { $0.element }
    g.beginPath(); g.rect(-RAIL - 1, -RAIL - 1, TL + 2 * RAIL + 2, TW + 2 * RAIL + 2); polyPath(g, noses)
    for k in s.POCKETS.indices { polyPath(g, pocketShape(k, co).quad) }
    g.clip(.evenodd)
    for k in s.POCKETS.indices {
      let sp = pocketShape(k, co), P = sp.P, r = sp.r, C = sp.C, rc = sp.rc, rb = sp.rb, side = sp.side
      let lw = max(1.6 * px, side ? 0.68 * (rc - r) : min(0.0035, 0.11 * capW(co), 0.32 * (rc - rb)))
      let gr = g.createRadialGradient(C[0], C[1], max(0, side ? r - 0.006 : rb - 0.02), C[0], C[1], rc)
      gr.addColorStop(0, "#0d0b09"); gr.addColorStop(0.55, "#1f1b17"); gr.addColorStop(1, "#2d2722")
      g.fillStyle = .gradient(gr); circle(g, C[0], C[1], rc); g.fill()
      let lip = side ? rc - r - lw : min(0.004, 0.5 * (rc - r))
      let sh = g.createLinearGradient(P[0] + L[0] * r, P[1] + L[1] * r, P[0] - L[0] * r, P[1] - L[1] * r)
      sh.addColorStop(0, "rgba(92,70,50,0.35)"); sh.addColorStop(0.6, "rgba(110,84,60,0.45)"); sh.addColorStop(1, "rgba(150,118,86,0.6)")
      g.strokeStyle = .gradient(sh); g.lineWidth = lip
      circle(g, P[0], P[1], r + lip / 2); g.stroke()
      let metal = g.createLinearGradient(C[0] + L[0] * rc, C[1] + L[1] * rc, C[0] - L[0] * rc, C[1] - L[1] * rc)
      metal.addColorStop(0, CM[0]); metal.addColorStop(0.5, CM[1]); metal.addColorStop(1, CM[2])
      g.strokeStyle = .gradient(metal); g.lineWidth = lw
      circle(g, C[0], C[1], rc - lw / 2); g.stroke()
      g.strokeStyle("rgba(0,0,0,0.5)"); g.lineWidth = max(px, lw * 0.35)
      if side { g.lineWidth = px; circle(g, C[0], C[1], rc - px / 2) } else { circle(g, C[0], C[1], rc - lw * 1.45) }
      g.stroke()
    }
    g.restore()
  }

  func sightsAt(_ co: Double) -> (at: [[Double]], hw: Double, hl: Double) {
    let mid = (co + RAIL) / 2, hw = min(0.0062, 0.3 * (RAIL - co)), hl = hw * 1.7
    var at: [[Double]] = []
    for i in s.MOUTHS.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : [1, 2, 3, 5, 6, 7] { at.append([TL * Double(i) / 8, -mid, 0]); at.append([TL * Double(i) / 8, TW + mid, 0]) }
    for i in [1, 2, 3] { at.append([-mid, TW * Double(i) / 4, 1]); at.append([TL + mid, TW * Double(i) / 4, 1]) }
    return (at, hw, hl)
  }
  func paintSights(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double) {
    let (at, hw, hl) = sightsAt(co), dot = look.rail.sight == "dot"
    for q in at {
      let x = q[0], y = q[1], v = q[2] != 0
      if dot {
        let pe = g.createRadialGradient(x + L[0] * hw * 0.3, y + L[1] * hw * 0.3, 0, x, y, hw)
        pe.addColorStop(0, "#fffdf8"); pe.addColorStop(0.7, "#e4dfd4"); pe.addColorStop(1, "#a9a49a")
        g.fillStyle = .gradient(pe); circle(g, x, y, hw * 0.92); g.fill()
        g.strokeStyle("rgba(25,10,4,0.6)"); g.lineWidth = 1.2 * px; g.stroke()
        continue
      }
      let ax = v ? 0 : hl, ay = v ? hl : 0, bx = v ? hw : 0, by = v ? 0 : hw
      g.beginPath(); g.moveTo(x - ax, y - ay); g.lineTo(x + bx, y + by); g.lineTo(x + ax, y + ay); g.lineTo(x - bx, y - by); g.closePath()
      let pe = g.createRadialGradient(x + L[0] * hw * 0.5, y + L[1] * hw * 0.5, 0, x, y, hl)
      pe.addColorStop(0, "#fffbf3"); pe.addColorStop(0.55, "#e6ded3"); pe.addColorStop(1, "#aea8c4")
      g.fillStyle = .gradient(pe); g.fill()
      let ir = g.createLinearGradient(x - bx - ax, y - by - ay, x + bx + ax, y + by + ay)
      ir.addColorStop(0, "rgba(255,186,214,0.35)"); ir.addColorStop(0.5, "rgba(255,255,255,0)"); ir.addColorStop(1, "rgba(160,212,255,0.4)")
      g.fillStyle = .gradient(ir); g.fill()
      g.strokeStyle("rgba(25,10,4,0.6)"); g.lineWidth = 1.2 * px; g.stroke()
    }
  }

  func holeClip(_ g: Canvas2D, _ k: Int, _ co: Double) {
    let sp = pocketShape(k, co)
    circle(g, sp.C[0], sp.C[1], sp.rb); g.clip()
    circle(g, sp.P[0], sp.P[1], sp.r); g.clip()
  }
  func paintHoles(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double) {
    for k in s.POCKETS.indices {
      let sp = pocketShape(k, co), P = sp.P, C = sp.C, r = sp.r, rb = sp.rb, fx = P[0] + L[0] * r * 0.35, fy = P[1] + L[1] * r * 0.35
      g.save()
      holeClip(g, k, co)
      g.fillStyle("#040303"); g.fillRect(P[0] - r, P[1] - r, 2 * r, 2 * r)
      let gr = g.createRadialGradient(fx, fy, 0, fx, fy, r * 1.35)
      gr.addColorStop(0, "rgba(40,30,22,0)"); gr.addColorStop(0.6, "rgba(40,30,22,0)")
      gr.addColorStop(0.86, "rgba(48,37,28,0.5)"); gr.addColorStop(1, "rgba(74,57,42,0.85)")
      g.fillStyle = .gradient(gr); g.fillRect(P[0] - r, P[1] - r, 2 * r, 2 * r)
      let sh = g.createRadialGradient(C[0], C[1], rb - 0.012, C[0], C[1], rb)
      sh.addColorStop(0, "rgba(0,0,0,0)"); sh.addColorStop(1, "rgba(0,0,0,0.7)")
      g.fillStyle = .gradient(sh); g.fillRect(P[0] - r, P[1] - r, 2 * r, 2 * r)
      g.strokeStyle("rgba(255,236,212,0.16)"); g.lineWidth = max(1.2 * px, 0.0012)
      circle(g, C[0], C[1], rb - g.lineWidth / 2); g.stroke()
      g.restore()
    }
  }

  func rubberPath(_ g: Canvas2D, _ p: [[Double]], _ open: Bool = false) {
    g.moveTo(p[0][0], p[0][1])
    g.arcTo(p[1][0], p[1][1], p[2][0], p[2][1], max(JAW_ROUND, jawRadius(p[1])))
    g.arcTo(p[2][0], p[2][1], p[3][0], p[3][1], max(JAW_ROUND, jawRadius(p[2])))
    g.lineTo(p[3][0], p[3][1])
    if !open { g.closePath() }
  }
  func paintCushions(_ g: Canvas2D, _ co: Double, _ K: Double) {
    g.save()
    g.beginPath(); g.rect(-co, -co, TL + 2 * co, TW + 2 * co); g.clip()
    clipOutHoles(g)
    g.shadow("rgba(0,0,0,0.55)", blur: 0.014 * K, x: -LIGHT[0] * 0.007 * K, y: -LIGHT[1] * 0.007 * K)
    g.fillStyle(look.cloth.cushion)
    for p in s.CUSHION_POLYS { g.beginPath(); rubberPath(g, p); g.fill() }
    g.restore()
  }
  func clipOutHoles(_ g: Canvas2D) {
    g.beginPath(); g.rect(-1, -1, TL + 2, TW + 2)
    for k in s.POCKETS.indices { let P = s.POCKETS[k]; g.moveTo(P[0] + s.POCKET_R[k], P[1]); g.arc(P[0], P[1], s.POCKET_R[k], 0, Double.pi * 2) }
    g.clip(.evenodd)
  }
  func clipBed(_ g: Canvas2D, _ co: Double) {
    g.beginPath(); g.rect(-co, -co, TL + 2 * co, TW + 2 * co); g.clip()
    clipOutHoles(g)
    g.beginPath(); g.rect(-1, -1, TL + 2, TW + 2)
    for p in s.CUSHION_POLYS { rubberPath(g, p) }
    g.clip(.evenodd)
  }
  func clipCloth(_ g: Canvas2D, _ co: Double) {
    g.beginPath(); g.rect(-co, -co, TL + 2 * co, TW + 2 * co); g.clip()
    clipOutHoles(g)
  }
  func paintPocketLips(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double) {
    g.save()
    clipBed(g, co)
    for (k, P) in s.POCKETS.enumerated() {
      let r = s.POCKET_R[k], quad = pocketShape(k, co).quad
      let R = max(JSMath.hypot(quad[0][0] - P[0], quad[0][1] - P[1]), JSMath.hypot(quad[3][0] - P[0], quad[3][1] - P[1]))
      g.save()
      g.beginPath(); polyPath(g, quad); g.clip()
      let th = g.createRadialGradient(P[0], P[1], r, P[0], P[1], max(R, r + 0.02))
      th.addColorStop(0, "rgba(0,0,0,0.6)"); th.addColorStop(0.3, "rgba(0,0,0,0.32)"); th.addColorStop(0.7, "rgba(0,0,0,0.09)"); th.addColorStop(1, "rgba(0,0,0,0)")
      g.fillStyle = .gradient(th); g.fillRect(P[0] - R, P[1] - R, 2 * R, 2 * R)
      g.restore()
      let d = 0.014, o = 0.0035, fx = P[0] + L[0] * o, fy = P[1] + L[1] * o
      let gr = g.createRadialGradient(fx, fy, r, fx, fy, r + d)
      gr.addColorStop(0, "rgba(0,0,0,0.62)"); gr.addColorStop(0.3, "rgba(0,0,0,0.3)"); gr.addColorStop(0.65, "rgba(0,0,0,0.08)"); gr.addColorStop(1, "rgba(0,0,0,0)")
      g.fillStyle = .gradient(gr); g.fillRect(P[0] - r - d, P[1] - r - d, 2 * (r + d), 2 * (r + d))
      let sh = g.createLinearGradient(P[0] + L[0] * r, P[1] + L[1] * r, P[0] - L[0] * r, P[1] - L[1] * r)
      sh.addColorStop(0, "rgba(255,246,225,0)"); sh.addColorStop(0.55, "rgba(255,246,225,0)"); sh.addColorStop(1, "rgba(255,246,225,0.22)")
      g.strokeStyle = .gradient(sh); g.lineWidth = max(1.5 * px, 0.002)
      g.beginPath(); g.arc(P[0], P[1], r + g.lineWidth / 2, 0, Double.pi * 2); g.stroke()
    }
    g.restore()
  }
  func paintClothLight(_ g: Canvas2D, _ co: Double, _ rnd: () -> Double) {
    g.save()
    clipCloth(g, co)
    let W = Double(g.width), H = Double(g.height)
    if view.portrait { g.setTransform(0, -1, 1, 0, 0, H) } else { g.setTransform(1, 0, 0, 1, 0, 0) }
    if !look.cloth.worsted {
      g.fillStyle = .pattern(napTile(g, rnd))
      g.fillRect(0, 0, view.portrait ? H : W, view.portrait ? W : H)
    }
    tableXform(g)
    g.translate(TL / 2, TW / 2); g.scale(TL / 2, TW / 2)
    let lamp = look.cloth.lamp
    let gr = g.createRadialGradient(0, 0, 0, 0, 0, 1.3)
    gr.addColorStop(0, "rgba(\(lamp),0.09)"); gr.addColorStop(0.3, "rgba(\(lamp),0.05)"); gr.addColorStop(0.5, "rgba(\(lamp),0)")
    gr.addColorStop(0.72, "rgba(0,0,0,0.08)"); gr.addColorStop(1, "rgba(0,0,0,0.3)")
    g.fillStyle = .gradient(gr); g.fillRect(-2, -2, 4, 4)
    g.restore()
  }
  func napTile(_ g: Canvas2D, _ rnd: () -> Double) -> Pattern2D {
    let n = 256
    var row: [Double] = []
    for _ in 0..<n { row.append(rnd() - 0.5) }
    var data = [UInt8](repeating: 0, count: n * n * 4)
    for y in 0..<n {
      for x in 0..<n {
        let i = (y * n + x) * 4
        let a = 0.55 * (rnd() - 0.5)
        let v = a + 0.45 * row[y] * (0.6 + 0.4 * JSMath.sin(Double(x) / Double(n) * Double.pi * 8 + Double(y)))
        let c: UInt8 = v > 0 ? 255 : 0
        data[i] = c; data[i + 1] = c; data[i + 2] = c
        data[i + 3] = UInt8(floor(abs(v) * 30))
      }
    }
    return g.createPattern(rgba: data, width: n, height: n)
  }
  func paintCushionAO(_ g: Canvas2D, _ co: Double) {
    let w = 1.3 * s.BALL_R
    g.save()
    clipBed(g, co)
    for poly in s.CUSHION_POLYS {
      let pa = poly[1], pb = poly[2]
      let dx = pb[0] - pa[0], dy = pb[1] - pa[1], h = JSMath.hypot(dx, dy), l = h == 0 ? 1 : h, mx = (pa[0] + pb[0]) / 2, my = (pa[1] + pb[1]) / 2
      var nx = -dy / l, ny = dx / l
      if nx * (TL / 2 - mx) + ny * (TW / 2 - my) < 0 { nx = -nx; ny = -ny }
      let gr = g.createLinearGradient(mx, my, mx + nx * w, my + ny * w)
      gr.addColorStop(0, "rgba(0,0,0,0.2)"); gr.addColorStop(0.35, "rgba(0,0,0,0.08)"); gr.addColorStop(1, "rgba(0,0,0,0)")
      g.fillStyle = .gradient(gr)
      g.beginPath(); polyPath(g, [[pa[0] - nx * 0.01, pa[1] - ny * 0.01], [pb[0] - nx * 0.01, pb[1] - ny * 0.01], [pb[0] + nx * w, pb[1] + ny * w], [pa[0] + nx * w, pa[1] + ny * w]]); g.fill()
    }
    g.restore()
  }
  func paintBevels(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double) {
    let bw = 0.0105
    func shade(_ f: Double, _ k: Double = 1) -> RGBA { f > 0 ? RGBA(1, 1, 240.0 / 255, (0.03 + 0.11 * f) * k) : RGBA(0, 0, 0, (0.06 - 0.22 * f) * k) }
    func crease(_ f: Double, _ k: Double = 1) -> RGBA { RGBA(1, 1, 245.0 / 255, (0.07 + 0.16 * max(0, f)) * k) }
    func fill(_ q: [[Double]]) { g.beginPath(); polyPath(g, q); g.fill() }
    func off(_ q: [Double], _ n: [Double], _ d: Double) -> [Double] { [q[0] - n[0] * d, q[1] - n[1] * d] }
    func meet(_ a1: [Double], _ a2: [Double], _ b1: [Double], _ b2: [Double]) -> [Double] {
      let dx = a2[0] - a1[0], dy = a2[1] - a1[1], ex = b2[0] - b1[0], ey = b2[1] - b1[1], d = dx * ey - dy * ex
      if abs(d) < 1e-12 { return a2 }
      let t = ((b1[0] - a1[0]) * ey - (b1[1] - a1[1]) * ex) / d
      return [a1[0] + dx * t, a1[1] + dy * t]
    }
    g.save()
    g.beginPath()
    for p in s.CUSHION_POLYS { rubberPath(g, p) }
    g.clip()
    clipOutHoles(g)
    for poly in s.CUSHION_POLYS {
      let ea = poly[0], pa = poly[1], pb = poly[2], eb = poly[3]
      let cx = poly.reduce(0) { $0 + $1[0] } / 4, cy = poly.reduce(0) { $0 + $1[1] } / 4
      func nOf(_ u: [Double], _ v: [Double]) -> [Double] {
        let dx = v[0] - u[0], dy = v[1] - u[1], h = JSMath.hypot(dx, dy), l = h == 0 ? 1 : h
        var nx = -dy / l, ny = dx / l
        if (cx - (u[0] + v[0]) / 2) * nx + (cy - (u[1] + v[1]) / 2) * ny > 0 { nx = -nx; ny = -ny }
        return [nx, ny, l]
      }
      let na = nOf(ea, pa), n = nOf(pa, pb), nb = nOf(pb, eb), fN = n[0] * L[0] + n[1] * L[1]
      let ma = meet(off(ea, na, bw), off(pa, na, bw), off(pa, n, bw), off(pb, n, bw))
      let mb = meet(off(pa, n, bw), off(pb, n, bw), off(pb, nb, bw), off(eb, nb, bw))
      if n[2] > 0.2 {
        let gr = g.createLinearGradient(pa[0] - n[0] * bw, pa[1] - n[1] * bw, pa[0] - n[0] * co, pa[1] - n[1] * co)
        gr.addColorStop(0, "rgba(255,255,255,0.035)"); gr.addColorStop(1, "rgba(0,0,0,0.14)")
        g.fillStyle = .gradient(gr); fill([ma, mb, off(pb, n, co + 0.01), off(pa, n, co + 0.01)])
      }
      g.fillStyle = .color(shade(fN)); fill([pa, pb, mb, ma])
      g.strokeStyle = .color(crease(fN)); g.lineWidth = 1.1 * px
      g.beginPath(); g.moveTo(ma[0], ma[1]); g.lineTo(mb[0], mb[1]); g.stroke()
      for (p, e, m, nf) in [(pa, ea, ma, na), (pb, eb, mb, nb)] {
        let f = nf[0] * L[0] + nf[1] * L[1], ei = off(e, nf, bw)
        var gr = g.createLinearGradient(p[0], p[1], e[0], e[1])
        gr.addColorStop(0, shade(fN)); gr.addColorStop(0.3, shade(f, 0.65)); gr.addColorStop(0.75, shade(min(f, 0), 0.8)); gr.addColorStop(1, "rgba(0,0,0,0.32)")
        g.fillStyle = .gradient(gr); fill([p, e, ei, m])
        gr = g.createLinearGradient(p[0], p[1], e[0], e[1])
        gr.addColorStop(0, "rgba(0,0,0,0)"); gr.addColorStop(0.45, "rgba(0,0,0,0)"); gr.addColorStop(1, "rgba(0,0,0,0.16)")
        g.fillStyle = .gradient(gr); fill([m, ei, off(e, nf, 2.4 * bw), off(p, nf, 2.4 * bw)])
        gr = g.createLinearGradient(m[0], m[1], ei[0], ei[1])
        gr.addColorStop(0, crease(fN)); gr.addColorStop(0.35, crease(f, 0.55)); gr.addColorStop(1, "rgba(255,255,245,0)")
        g.strokeStyle = .gradient(gr)
        g.beginPath(); g.moveTo(m[0], m[1]); g.lineTo(ei[0], ei[1]); g.stroke()
      }
      g.strokeStyle("rgba(0,0,0,0.38)"); g.lineWidth = 1.4 * px
      g.beginPath(); rubberPath(g, poly, true); g.stroke()
    }
    g.restore()
    g.save()
    g.beginPath(); g.rect(-RAIL - 1, -RAIL - 1, TL + 2 * RAIL + 2, TW + 2 * RAIL + 2)
    for k in s.POCKETS.indices { let sp = pocketShape(k, co); g.moveTo(sp.C[0] + sp.rc, sp.C[1]); g.arc(sp.C[0], sp.C[1], sp.rc, 0, Double.pi * 2) }
    g.clip(.evenodd)
    g.strokeStyle("rgba(0,0,0,0.55)"); g.lineWidth = 1.6 * px
    g.strokeRect(-co, -co, TL + 2 * co, TW + 2 * co)
    g.strokeStyle("rgba(255,215,170,0.08)"); g.lineWidth = px
    g.strokeRect(-co - 1.5 * px, -co - 1.5 * px, TL + 2 * co + 3 * px, TW + 2 * co + 3 * px)
    g.restore()
  }
  func paintSnookerMarks(_ g: Canvas2D, _ px: Double) {
    g.strokeStyle("rgba(255,255,255,0.32)"); g.lineWidth = max(1.2 * px, 0.0018)
    g.beginPath(); g.moveTo(s.HEAD_X, 0); g.lineTo(s.HEAD_X, TW); g.stroke()
    g.beginPath(); g.arc(s.HEAD_X, TW / 2, s.D_R, Double.pi / 2, Double.pi * 1.5); g.stroke()
    g.fillStyle("rgba(255,255,255,0.5)")
    for c in [57, 58, 59, 60, 61, 62] { g.beginPath(); g.arc(s.SPOTS[c]![0], s.SPOTS[c]![1], max(1.5 * px, 0.0035), 0, Double.pi * 2); g.fill() }
  }
  func paintCaromSpots(_ g: Canvas2D, _ px: Double) {
    let r = 0.0042
    for q in [[s.FOOT[0], s.FOOT[1], 0.42], [TL / 2, TW / 2, 0.3], [s.HEAD_X, TW / 2, 0.42], [s.HEAD_X, TW / 2 - 0.1524, 0.3], [s.HEAD_X, TW / 2 + 0.1524, 0.3]] {
      g.fillStyle = .color(RGBA(1, 1, 1, q[2])); circle(g, q[0], q[1], r); g.fill()
      g.strokeStyle("rgba(0,0,0,0.18)"); g.lineWidth = px; circle(g, q[0], q[1], r + px / 2); g.stroke()
    }
  }

  // MARK: 4a, the bumper pool table (paintBumperTable and its parts, line for line)

  func paintBumperTable(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double, _ K: Double, _ rnd: () -> Double) {
    g.save()
    if s.BED_LINES != nil { g.beginPath(); polyPath(g, s.octagon(co)); g.clip() }
    g.fillStyle(look.cloth.base); g.fillRect(-co, -co, TL + 2 * co, TW + 2 * co)
    for (k, P) in s.POCKETS.enumerated() {
      let r = s.POCKET_R[k], fx = P[0] + L[0] * r * 0.35, fy = P[1] + L[1] * r * 0.35
      g.fillStyle("#040303"); circle(g, P[0], P[1], r + 0.0005); g.fill()
      let gr = g.createRadialGradient(fx, fy, 0, fx, fy, r * 1.35)
      gr.addColorStop(0, "rgba(40,30,22,0)"); gr.addColorStop(0.6, "rgba(40,30,22,0)")
      gr.addColorStop(0.86, "rgba(48,37,28,0.5)"); gr.addColorStop(1, "rgba(74,57,42,0.85)")
      g.save(); circle(g, P[0], P[1], r); g.clip()
      g.fillStyle = .gradient(gr); g.fillRect(P[0] - r, P[1] - r, 2 * r, 2 * r)
      g.restore()
    }
    paintCushions(g, co, K)
    paintClothLight(g, co, rnd)
    paintBumperBevels(g, co, L, px)
    /* the cups' turn-under, liner and rim */
    g.save(); clipBed(g, co)
    for (k, P) in s.POCKETS.enumerated() {
      let r = s.POCKET_R[k], d = 0.016, o = 0.003, fx = P[0] + L[0] * o, fy = P[1] + L[1] * o
      let gr = g.createRadialGradient(fx, fy, r, fx, fy, r + d)
      gr.addColorStop(0, "rgba(0,0,0,0.55)"); gr.addColorStop(0.35, "rgba(0,0,0,0.24)"); gr.addColorStop(1, "rgba(0,0,0,0)")
      g.fillStyle = .gradient(gr); g.fillRect(P[0] - r - d, P[1] - r - d, 2 * (r + d), 2 * (r + d))
    }
    g.restore()
    g.restore()
    if s.BED_LINES != nil { octaSeam(g, co, px) }
    for (k, P) in s.POCKETS.enumerated() {
      let r = s.POCKET_R[k], lw = max(1.5 * px, 0.0042), rim = max(px, 0.0013)
      g.strokeStyle("#17120f"); g.lineWidth = lw; circle(g, P[0], P[1], r + lw / 2); g.stroke()
      let metal = g.createLinearGradient(P[0] + L[0] * r, P[1] + L[1] * r, P[0] - L[0] * r, P[1] - L[1] * r)
      metal.addColorStop(0, "#d8d5cd"); metal.addColorStop(0.5, "#7b7872"); metal.addColorStop(1, "#3a3834")
      g.strokeStyle = .gradient(metal); g.lineWidth = rim; circle(g, P[0], P[1], r + lw + rim / 2); g.stroke()
      /* the liner's lip catches a little light on the far side, inside the hole */
      let sh = g.createLinearGradient(P[0] + L[0] * r, P[1] + L[1] * r, P[0] - L[0] * r, P[1] - L[1] * r)
      sh.addColorStop(0, "rgba(255,240,220,0)"); sh.addColorStop(0.6, "rgba(255,240,220,0)"); sh.addColorStop(1, "rgba(255,240,220,0.18)")
      g.strokeStyle = .gradient(sh); g.lineWidth = max(px, 0.0012); circle(g, P[0], P[1], r - g.lineWidth / 2); g.stroke()
    }
    if s.BED_LINES != nil { paintMushrooms(g, L, px) } else { paintPosts(g, L, px) }
  }
  /* the rubbers' lit noses: shaded by how squarely each faces the lamp, a crease, the bed line, the mitres, the seam */
  func paintBumperBevels(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double) {
    let bw = 0.0105, f = bw / CUSH_W
    func shade(_ v: Double) -> RGBA { v > 0 ? RGBA(1, 1, 240.0 / 255, 0.03 + 0.11 * v) : RGBA(0, 0, 0, 0.06 - 0.22 * v) }
    g.save()
    g.beginPath(); for q in s.CUSHION_POLYS { polyPath(g, q) }; g.clip()
    for q in s.CUSHION_POLYS {
      let ea = q[0], pa = q[1], pb = q[2], eb = q[3]
      let dx = pb[0] - pa[0], dy = pb[1] - pa[1], l = JSMath.hypot(dx, dy)
      var nx = -dy / l, ny = dx / l
      if (TL / 2 - pa[0]) * nx + (TW / 2 - pa[1]) * ny < 0 { nx = -nx; ny = -ny }
      let fN = nx * L[0] + ny * L[1], ia = [pa[0] + (ea[0] - pa[0]) * f, pa[1] + (ea[1] - pa[1]) * f], ib = [pb[0] + (eb[0] - pb[0]) * f, pb[1] + (eb[1] - pb[1]) * f]
      g.fillStyle = .color(shade(fN)); g.beginPath(); polyPath(g, [pa, pb, ib, ia]); g.fill()
      let gr = g.createLinearGradient(ia[0], ia[1], ia[0] - nx * (co - bw), ia[1] - ny * (co - bw))
      gr.addColorStop(0, "rgba(255,255,255,0.035)"); gr.addColorStop(1, "rgba(0,0,0,0.14)")
      g.fillStyle = .gradient(gr); g.beginPath(); polyPath(g, [ia, ib, eb, ea]); g.fill()
      g.strokeStyle = .color(RGBA(1, 1, 245.0 / 255, 0.07 + 0.16 * max(0, fN))); g.lineWidth = 1.1 * px
      g.beginPath(); g.moveTo(ia[0], ia[1]); g.lineTo(ib[0], ib[1]); g.stroke()
      g.strokeStyle("rgba(0,0,0,0.38)"); g.lineWidth = 1.4 * px
      g.beginPath(); g.moveTo(pa[0], pa[1]); g.lineTo(pb[0], pb[1]); g.stroke()
      g.strokeStyle("rgba(0,0,0,0.3)"); g.lineWidth = px
      g.beginPath(); g.moveTo(pa[0], pa[1]); g.lineTo(ea[0], ea[1]); g.stroke()
    }
    g.restore()
    if s.BED_LINES != nil { return }   /* the octagon's seam is drawn by octaSeam */
    g.strokeStyle("rgba(0,0,0,0.55)"); g.lineWidth = 1.6 * px
    g.strokeRect(-co, -co, TL + 2 * co, TW + 2 * co)
    g.strokeStyle("rgba(255,215,170,0.08)"); g.lineWidth = px
    g.strokeRect(-co - 1.5 * px, -co - 1.5 * px, TL + 2 * co + 3 * px, TW + 2 * co + 3 * px)
  }
  func octaSeam(_ g: Canvas2D, _ co: Double, _ px: Double) {
    g.strokeStyle("rgba(0,0,0,0.55)"); g.lineWidth = 1.6 * px
    g.beginPath(); polyPath(g, s.octagon(co)); g.stroke()
    g.strokeStyle("rgba(255,215,170,0.08)"); g.lineWidth = px
    g.beginPath(); polyPath(g, s.octagon(co + 1.5 * px)); g.stroke()
  }
  /* the octagon's studs: each corner and each side's middle, halfway across the wood */
  func octaStuds(_ co: Double) -> [[Double]] {
    let M = s.octagon((co + RAIL) / 2)
    var at: [[Double]] = []
    for i in 0..<8 { let a = M[i], b = M[(i + 1) % 8]; at.append(a); at.append([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]) }
    return at
  }
  /* the octagon's wood: eight boards mitred at the corners, grain along each, lit by how squarely it faces the lamp,
     the bullnose's inner shadows, the mitre joints and the nickel studs */
  func paintOctaRails(_ g: Canvas2D, _ co: Double, _ L: [Double], _ px: Double, _ rnd: () -> Double) {
    let I = s.octagon(co), O = s.octagon(RAIL + 0.02), E = s.octagon(RAIL), w = RAIL - co, BL = s.BED_LINES!
    let RW = look.rail, DARK = RW.dark, LITE = RW.lite
    for i in 0..<8 {
      let a = I[i], b = I[(i + 1) % 8], len = JSMath.hypot(b[0] - a[0], b[1] - a[1])
      let ux = (b[0] - a[0]) / len, uy = (b[1] - a[1]) / len, nx = -BL[i][0], ny = -BL[i][1]
      g.save()
      railOutline(g, co); g.clip()
      g.beginPath(); polyPath(g, [O[i], O[(i + 1) % 8], b, a]); g.clip()
      /* the board's own frame: x along it from its inner corner, y out across the wood */
      g.transform(ux, uy, nx, ny, a[0], a[1])
      g.fillStyle(RW.base); g.fillRect(-0.4, -0.01, len + 0.8, w + 0.05)
      let lines = Int(ceil(w / (1.4 * px)))
      for k in 0..<(lines + 6) {
        let broad = k < 6, t = rnd(), base = broad ? w * rnd() : w * (Double(k - 6) + rnd()) / Double(lines)
        let f1 = 2 * Double.pi / (0.5 + rnd() * 1.2), f2 = 2 * Double.pi / (0.09 + rnd() * 0.12), p1 = rnd() * 7, p2 = rnd() * 7
        let A1 = w * (broad ? 0.25 : 0.06 + rnd() * 0.08), A2 = w * 0.01
        let col = (0..<3).map { j in (DARK[j] + (LITE[j] - DARK[j]) * t).rounded(.toNearestOrAwayFromZero) }
        let alpha = broad ? 0.16 : 0.16 + rnd() * 0.3
        g.strokeStyle = .color(RGBA(col[0] / 255, col[1] / 255, col[2] / 255, alpha))
        g.lineWidth = broad ? w * (0.15 + rnd() * 0.2) : px * (0.7 + rnd() * 1.8)
        g.beginPath()
        var u = -0.35
        while u <= len + 0.37 {
          let y = base + A1 * JSMath.sin(u * f1 + p1) + A2 * JSMath.sin(u * f2 + p2)
          u == -0.35 ? g.moveTo(u, y) : g.lineTo(u, y)
          u += 0.02
        }
        g.stroke()
      }
      let f = max(0, nx * L[0] + ny * L[1]), gr = g.createLinearGradient(0, 0, 0, w)
      gr.addColorStop(0, "rgba(0,0,0,0.18)"); gr.addColorStop(0.1, "rgba(255,225,190,0.03)")
      gr.addColorStop(0.55, RGBA(1, 225.0 / 255, 190.0 / 255, 0.04 + 0.08 * f)); gr.addColorStop(1, RGBA(1, 225.0 / 255, 190.0 / 255, 0.04 + 0.08 * f))
      g.fillStyle = .gradient(gr); g.fillRect(-0.4, -0.01, len + 0.8, w + 0.05)
      g.restore()
    }
    let K = 1 / px
    let edge = { (color: String, blur: Double, off: Double) in
      g.shadow(color, blur: blur * K, x: LIGHT[0] * off * K, y: LIGHT[1] * off * K)
      g.beginPath(); g.rect(-self.RAIL - 1, -self.RAIL - 1, self.TL + 2 * self.RAIL + 2, self.TW + 2 * self.RAIL + 2); self.railPath(g, co)
      g.fill(.evenodd)
    }
    g.save()
    railOutline(g, co); g.clip()
    g.fillStyle("#000")
    edge("rgba(255,232,205,0.3)", 0.014, -0.008)
    edge("rgba(0,0,0,0.32)", 0.012, 0.007)
    edge("rgba(0,0,0,0.7)", 0.005, 0)
    g.restore()
    g.save()
    railOutline(g, co); g.clip()
    g.strokeStyle("rgba(0,0,0,0.45)"); g.lineWidth = px
    for i in 0..<8 { g.beginPath(); g.moveTo(E[i][0], E[i][1]); g.lineTo(I[i][0], I[i][1]); g.stroke() }
    g.restore()
    let r = min(0.0048, 0.2 * w)
    for q in octaStuds(co) {
      let x = q[0], y = q[1]
      g.fillStyle("rgba(20,8,2,0.55)"); circle(g, x - L[0] * r * 0.3, y - L[1] * r * 0.3, r * 1.25); g.fill()
      let gr = g.createRadialGradient(x + L[0] * r * 0.4, y + L[1] * r * 0.4, 0, x, y, r)
      gr.addColorStop(0, "#ffffff"); gr.addColorStop(0.3, "#e2ded4"); gr.addColorStop(0.75, "#8d887d"); gr.addColorStop(1, "#4d4942")
      g.fillStyle = .gradient(gr); circle(g, x, y, r); g.fill()
      g.strokeStyle("rgba(25,10,4,0.6)"); g.lineWidth = max(0.8 * px, r * 0.12); g.stroke()
    }
  }
  /* a post's colour on the octagon: red on red's half, white on white's; the middle pair split by y */
  func postSide(_ q: [Double]) -> Int { abs(q[0] - TL / 2) > 1e-6 ? (q[0] < TL / 2 ? 0 : 1) : (q[1] < TW / 2 ? 0 : 1) }
  /* the octagon's mushroom bumpers (MUSHROOM): shadow, rubber ring, the stem's neck, the domed cap, its rim, knob and hot spot */
  func paintMushrooms(_ g: Canvas2D, _ L: [Double], _ px: Double) {
    struct Mush { let ring: [Double], ringOnRed: [Double]?, cap: [Double], hi: [Double], rim: String }
    let MUSH = [Mush(ring: [150, 22, 30], ringOnRed: [232, 222, 206], cap: [214, 40, 46], hi: [255, 190, 180], rim: "rgba(255,220,210,0.55)"),
                Mush(ring: [196, 190, 176], ringOnRed: nil, cap: [246, 243, 234], hi: [255, 255, 255], rim: "rgba(255,255,255,0.6)")]
    let R = BUMPER_R, rc = R * 0.74, sx = -L[0] * 0.011, sy = -L[1] * 0.011, onRed = look.cloth.base == "#9a1f26"
    func c(_ v: [Double], _ k: Double = 1) -> RGBA { let q = v.map { min(255, $0 * k).rounded(.toNearestOrAwayFromZero) / 255 }; return RGBA(q[0], q[1], q[2], 1) }
    for q in s.BUMPERS {
      let x = q[0], y = q[1], M = MUSH[postSide(q)], ring = onRed && M.ringOnRed != nil ? M.ringOnRed! : M.ring
      var gr = g.createRadialGradient(x + sx, y + sy, R * 0.5, x + sx, y + sy, R * 1.6)
      gr.addColorStop(0, "rgba(0,0,0,0.55)"); gr.addColorStop(0.6, "rgba(0,0,0,0.25)"); gr.addColorStop(1, "rgba(0,0,0,0)")
      g.fillStyle = .gradient(gr); circle(g, x + sx, y + sy, R * 1.6); g.fill()
      gr = g.createRadialGradient(x + L[0] * R * 0.35, y + L[1] * R * 0.35, R * 0.3, x, y, R)
      gr.addColorStop(0, c(ring, 1.12)); gr.addColorStop(0.75, c(ring)); gr.addColorStop(1, c(ring, 0.8))
      g.fillStyle = .gradient(gr); circle(g, x, y, R); g.fill()
      let sh = g.createLinearGradient(x + L[0] * R, y + L[1] * R, x - L[0] * R, y - L[1] * R)
      sh.addColorStop(0, "rgba(255,255,255,0.35)"); sh.addColorStop(0.5, "rgba(255,255,255,0)"); sh.addColorStop(1, "rgba(0,0,0,0.35)")
      g.strokeStyle = .gradient(sh); g.lineWidth = max(px, R * 0.1); circle(g, x, y, R - g.lineWidth / 2); g.stroke()
      g.fillStyle("rgba(0,0,0,0.45)"); circle(g, x - L[0] * R * 0.08, y - L[1] * R * 0.08, rc + R * 0.07); g.fill()
      gr = g.createRadialGradient(x + L[0] * rc * 0.4, y + L[1] * rc * 0.4, 0, x, y, rc)
      gr.addColorStop(0, c(M.hi)); gr.addColorStop(0.3, c(M.cap, 1.04)); gr.addColorStop(0.8, c(M.cap, 0.86)); gr.addColorStop(1, c(M.cap, 0.62))
      g.fillStyle = .gradient(gr); circle(g, x, y, rc); g.fill()
      g.strokeStyle(M.rim); g.lineWidth = max(0.8 * px, rc * 0.06)
      let la = JSMath.atan2(L[1], L[0])
      g.beginPath(); g.arc(x, y, rc - g.lineWidth / 2, la - 1.2, la + 1.2); g.stroke()
      g.strokeStyle("rgba(0,0,0,0.28)"); g.lineWidth = max(0.8 * px, rc * 0.07); circle(g, x, y, rc * 0.36); g.stroke()
      g.fillStyle("rgba(255,255,255,0.8)"); circle(g, x + L[0] * rc * 0.45, y + L[1] * rc * 0.45, rc * 0.13); g.fill()
    }
  }
  /* the rectangle's posts: a shadow, the black rubber ring with its sheen, the nickel cap, its groove, screw and hot spot */
  func paintPosts(_ g: Canvas2D, _ L: [Double], _ px: Double) {
    let R = BUMPER_R, rc = R * 0.6, sx = -L[0] * 0.007, sy = -L[1] * 0.007
    for q in s.BUMPERS {
      let x = q[0], y = q[1]
      var gr = g.createRadialGradient(x + sx, y + sy, R * 0.6, x + sx, y + sy, R * 1.45)
      gr.addColorStop(0, "rgba(0,0,0,0.5)"); gr.addColorStop(1, "rgba(0,0,0,0)")
      g.fillStyle = .gradient(gr); circle(g, x + sx, y + sy, R * 1.45); g.fill()
      gr = g.createRadialGradient(x + L[0] * R * 0.3, y + L[1] * R * 0.3, R * 0.2, x, y, R)
      gr.addColorStop(0, "#3a3633"); gr.addColorStop(0.7, "#1b1918"); gr.addColorStop(1, "#0a0909")
      g.fillStyle = .gradient(gr); circle(g, x, y, R); g.fill()
      let rim = g.createLinearGradient(x + L[0] * R, y + L[1] * R, x - L[0] * R, y - L[1] * R)
      rim.addColorStop(0, "rgba(255,255,255,0.32)"); rim.addColorStop(0.45, "rgba(255,255,255,0.04)"); rim.addColorStop(1, "rgba(0,0,0,0.4)")
      g.strokeStyle = .gradient(rim); g.lineWidth = max(1.2 * px, R * 0.12); circle(g, x, y, R - g.lineWidth / 2); g.stroke()
      g.fillStyle("rgba(0,0,0,0.55)"); circle(g, x - L[0] * R * 0.06, y - L[1] * R * 0.06, rc + R * 0.08); g.fill()
      gr = g.createRadialGradient(x + L[0] * rc * 0.45, y + L[1] * rc * 0.45, 0, x, y, rc)
      gr.addColorStop(0, "#fbfaf6"); gr.addColorStop(0.35, "#cfccc4"); gr.addColorStop(0.8, "#7d7a73"); gr.addColorStop(1, "#4a4843")
      g.fillStyle = .gradient(gr); circle(g, x, y, rc); g.fill()
      g.strokeStyle("rgba(0,0,0,0.45)"); g.lineWidth = max(px, rc * 0.08); circle(g, x, y, rc * 0.82); g.stroke()
      g.fillStyle("#5d5a54"); circle(g, x, y, rc * 0.2); g.fill()
      g.fillStyle("rgba(255,255,255,0.85)"); circle(g, x + L[0] * rc * 0.45, y + L[1] * rc * 0.45, rc * 0.14); g.fill()
    }
  }
}
#endif
