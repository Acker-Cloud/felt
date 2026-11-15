/* The home's game cards' pictures (index.html, page 6: paintArt, paintRackIn's 'card' mode, coverView, paintScrim,
   heyArt, caromArt), line for line on FeltRender: each card is its game's own table (paintTable, no vignette) in the
   game's look, its rack in drawBall's spheres over drawShadow's shadows (the cue ball left out, it would sit under the
   words), zoomed in on the rack and placed where the words are not, and the scrim the words sit on painted into it. */
import CoreGraphics
import FeltRender
import FeltSim
import Foundation

enum HomeArt {
  /* the page's home order (#playRow): 8, 9, 10, 14.1, rotation, snooker, three-cushion, bumper, Chinese 8-ball */
  static let ORDER: [TableGame] = [.eight, .nine, .ten, .straight, .rotation, .snooker, .carom, .bumper, .heyball]
  /* each card's line (.tile small) */
  static func line(_ g: TableGame) -> String {
    switch g {
    case .eight: "Solids and stripes"
    case .nine: "Lowest ball first"
    case .ten: "Call every shot"
    case .straight: "14.1, a point a ball"
    case .rotation: "Numbers score, 61 wins"
    case .snooker: "Reds, then colours"
    case .carom: "No pockets, 3 rails"
    case .bumper: "Round the posts"
    case .heyball: "Snooker pockets, pool balls"
    }
  }
  /* paintRackIn(cv, kind, 'card', low): w, h the card in points, low its words' height, d the screen's scale */
  static func paint(_ game: TableGame, _ w: Double, _ h: Double, low: Double, d: Double) -> CGImage? {
    guard w > 0, h > 0 else { return nil }
    let kind = game.table.2, spec = TableModel.spec(for: game), dress = Prefs.dress(kind), look = TableLook.of(dress)
    let s = Sim(); TableModel.setUp(s, spec)
    let g = RulesEngine(sim: s).newGame(kind)
    var all = g.balls
    let hey = kind == "heyball" ? heyArt(s, &all, w, h) : nil
    let pocketKinds = ["8", "9", "10", "straight", "rotation", "heyball"]
    var balls = all.filter { $0.on && !($0.n == 0 && hey == nil && (pocketKinds.contains(kind) || kind == "snooker")) }
    if kind == "carom" { caromArt(s, &balls, w > h * 1.6) }
    let obj = kind == "snooker" ? balls.filter { ($0.n >= 41 && $0.n <= 55) || $0.n == 61 } : balls.filter { $0.n > 0 }
    let view = hey ?? coverView(s, w, h, kind, obj, low)
    let W = Int((w * d).rounded()), H = Int((h * d).rounded())
    let P = TablePainter(sim: s, view: view, dpr: d, rail: RAIL_MAX, look: look)
    let x = P.paint(width: W, height: H, vignette: false)
    let cloth = RGBA(css: look.cloth.base)
    let bp = BallPainter(set: BallSet.all[dress.balls] ?? BallSet.all["classic"]!, bounce: look.cloth.bounce, dpr: d, portrait: view.portrait,
                         lowRim: look.cloth.lowRim, rimAll: look.cloth.rim, clothBase: [cloth.r * 255, cloth.g * 255, cloth.b * 255])
    let k = view.k, rb = s.BALL_R * k * d
    let toScreen = { (bx: Double, by: Double) -> (Double, Double) in
      view.portrait ? (view.ox + by * k, view.oy + (s.TL - bx) * k) : (view.ox + bx * k, view.oy + by * k)
    }
    let pos = balls.map { toScreen($0.x, $0.y) }
    x.setTransform(1, 0, 0, 1, 0, 0)
    for p in pos { bp.drawShadow(x, p.0 * d, p.1 * d, rb) }
    for (i, b) in balls.enumerated() { bp.drawBall(x, b.n, pos[i].0 * d, pos[i].1 * d, rb, bp.axesOf(artTilt(b.n))) }
    paintScrim(x, Double(W), Double(H), band: kind == "bumper" && w > h * 1.6 ? max(0.2, (h - low - 6) / h) : 0)
    return x.image()
  }

  /* coverView: the picture covers its card (no letterbox), zoomed in on the rack and placed where the words are not */
  static func coverView(_ s: Sim, _ w: Double, _ h: Double, _ kind: String, _ obj: [GBall], _ low: Double) -> TableView2D {
    let TL = s.TL, TW = s.TW, RAIL = RAIL_MAX
    let bump = kind == "bumper", wide = w > h * 1.6, up = !bump && h > w * 1.05, W = (up ? TW : TL) + 2 * RAIL, H = (up ? TL : TW) + 2 * RAIL
    let free = max(h * 0.3, h - low - 8)
    var k: Double, e: Double
    if bump {
      k = wide ? max(w / W, h / H) * 1.25 : max(w / W * 1.04, free * 0.86 / H); e = wide ? -0.02 : RAIL
    } else {
      let xs = obj.map(\.x), ys = obj.map(\.y)
      let span: Double = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!) + 2 * s.BALL_R
      let room: Double = wide ? min(w * 0.29, h * 0.6) : min(w * 0.56, h * 0.36, free * 0.78)
      let k0: Double = max(up ? w / TW : w / TL, up ? h / TL : h / TW, room / span)
      k = k0 * (kind == "carom" && !wide ? 1.5 : 1); e = -0.02
    }
    let fx = bump || obj.isEmpty ? TL / 2 : obj.reduce(0) { $0 + $1.x } / Double(obj.count), fy = TW / 2
    let cw = kind == "carom"
    let tx = wide && !bump ? (cw ? w * 0.8 : w * 0.75) : w * 0.5, ty = wide ? (cw ? h * 0.32 : max(h * 0.3, (h - low) / 2 + 2)) : min(h * 0.42, free / 2 + 4)
    func fit(_ o: Double, _ size: Double, _ len: Double) -> Double {
      let lo = size - (len + e) * k, hi = e * k
      return lo > hi ? (bump ? o : (lo + hi) / 2) : min(max(o, lo), hi)
    }
    return up ? TableView2D(k: k, ox: fit(tx - fy * k, w, TW), oy: fit(ty - (TL - fx) * k, h, TL), portrait: true)
      : TableView2D(k: k, ox: fit(tx - fx * k, w, TL), oy: fit(ty - fy * k, h, TW), portrait: false)
  }

  /* paintScrim: the scrim under a card's words, painted into the art so it is exactly what the words sit on */
  static func paintScrim(_ x: Canvas2D, _ W: Double, _ H: Double, band: Double) {
    let g = x.createLinearGradient(0, 0, 0, H)
    if band > 0 {
      g.addColorStop(0, "rgba(6,6,8,0)"); g.addColorStop(max(0, band - 0.32), "rgba(6,6,8,0)")
      g.addColorStop(band, "rgba(6,6,8,0.7)"); g.addColorStop(1, "rgba(6,6,8,0.9)")
    } else {
      let from = 0.4, top = 0.84
      for i in 0...8 { let u = Double(i) / 8; g.addColorStop(from + (1 - from) * u, "rgba(6,6,8,\(String(format: "%.3f", top * u * u * (3 - 2 * u))))") }
      g.addColorStop(0, "rgba(6,6,8,0)")
    }
    x.setTransform(1, 0, 0, 1, 0, 0)
    x.fillStyle = .gradient(g); x.fillRect(0, 0, W, H)
  }

  /* heyArt: Chinese 8-ball's card, one pocket close up (the foot corner's rounded jaws), the 8 hanging in the jaws and the
     cue ball coming down the line at it; the rest of the rack off */
  static func heyArt(_ s: Sim, _ balls: inout [GBall], _ w: Double, _ h: Double) -> TableView2D {
    let k = max(h / (h < 60 ? 0.2 : 0.31), w / (s.TL + RAIL_MAX)), P = s.POCKET_AIM[2], u = [-0.5.squareRoot(), 0.5.squareRoot()], r = s.BALL_R
    let at = { (d: Double) in [P[0] + u[0] * d, P[1] + u[1] * d] }
    let pos: [Int: [Double]] = [8: at(1.9 * r), 0: at(1.9 * r + 0.15)]
    for i in balls.indices { if let p = pos[balls[i].n] { balls[i].x = p[0]; balls[i].y = p[1]; balls[i].on = true } else { balls[i].on = false } }
    return TableView2D(k: k, ox: w - (s.TL + RAIL_MAX) * k + 1, oy: h * 0.4 - P[1] * k, portrait: false)
  }

  /* caromArt: the three balls in play near the middle of the table, close up */
  static func caromArt(_ s: Sim, _ balls: inout [GBall], _ wide: Bool) {
    let at: [Int: [Double]] = wide ? [70: [0.522, 0.445], 71: [0.549, 0.478], 72: [0.495, 0.472]] : [70: [0.497, 0.6], 71: [0.532, 0.66], 72: [0.52, 0.42]]
    for i in balls.indices { if let p = at[balls[i].n] { balls[i].x = s.TL * p[0]; balls[i].y = s.TW * p[1] } }
  }
}
