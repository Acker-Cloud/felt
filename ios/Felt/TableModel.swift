/* One table at play: the sim (FeltSim, index.html's physics bit for bit), the balls at rest, the
   roll in progress and the player's aim, power and english. No rules yet: this is the web build's
   free practice table (Practice > the rack) on every table the port has. The roll steps exactly as
   the page's frame() does: dtMs / 1000 / SIM_DT steps a frame, the fraction carried to the next. */
import Foundation
import CoreGraphics
import FeltRender
import FeltSim
import Observation

enum Game: String, CaseIterable, Identifiable {
  case eight = "8-Ball", nine = "9-Ball", ten = "10-Ball", heyball = "Chinese 8-Ball", snooker = "Snooker", carom = "Three-Cushion"
  var id: String { rawValue }
  /* the sim's table, its shape, and the game whose look it wears (GAME_LOOK) */
  var table: (String, String?, String) {
    switch self {
    case .eight: ("7", nil, "8")
    case .nine: ("9", nil, "9")
    case .ten: ("9", nil, "10")
    case .heyball: ("heyball", nil, "heyball")
    case .snooker: ("snooker", "compact", "snooker")
    case .carom: ("carom", nil, "carom")
    }
  }
  var line: String {
    switch self {
    case .eight: "Solids and stripes on a 7 ft table"
    case .nine: "The lowest ball first, on a 9 ft table"
    case .ten: "Ten balls on a 9 ft table"
    case .heyball: "Tight pockets, a 9 ft bed"
    case .snooker: "Fifteen reds on a 10 ft table"
    case .carom: "No pockets, three cushions"
    }
  }
}

@MainActor @Observable
final class TableModel {
  let game: Game
  @ObservationIgnored let sim = Sim()
  private(set) var balls: [Ball] = []
  private(set) var rolling: Tab?
  private(set) var frame = 0              /* bumped every drawn frame, so the canvas redraws */
  var aim = 0.0
  var power = 0.0                         /* the bar's pull, 0 to 1, while held */
  var spin = Spin()
  private(set) var inHand = false
  private(set) var potCount = 0
  @ObservationIgnored private var carry = 0.0
  @ObservationIgnored private var lastT: TimeInterval?
  @ObservationIgnored private var heard = 0
  @ObservationIgnored let sound = Sound()

  /* the baked table (FeltRender: index.html's paintTable and vignette) for one screen size */
  struct Baked { let image: CGImage; let size: CGSize; let scale: CGFloat }
  private(set) var tableImage: Baked?
  @ObservationIgnored private var baking: CGSize?
  func bake(_ size: CGSize, scale: CGFloat) {
    guard size.width > 0, size.height > 0, tableImage?.size != size, baking != size else { return }
    baking = size
    let (t, shape, look) = game.table
    Task.detached(priority: .userInitiated) {
      let sim = Sim(); sim.setTable(t, shape)
      let m = Mapper(size: size, TL: sim.TL, TW: sim.TW)
      let p = TablePainter(sim: sim, view: m.view, dpr: Double(scale), rail: m.rail, look: TableLook.of(game: look), pageColor: "rgb(9, 9, 10)")
      let img = p.paint(width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded())).image()
      await MainActor.run { if self.baking == size { self.tableImage = Baked(image: img, size: size, scale: scale); self.baking = nil } }
    }
  }

  /* each ball's orientation (4b's orient), random at each rack (randomOrient) */
  @ObservationIgnored var orient: [Int: Mat3] = [:]
  func randomOrient() {
    for b in balls {
      var m = IDENT
      for _ in 0..<3 { m = rotate(m, [Double.random(in: -0.5..<0.5), Double.random(in: -0.5..<0.5), Double.random(in: -0.5..<0.5)], Double.random(in: 0..<6.3)) }
      orient[b.n] = m
    }
  }
  /* the balls' painter for this screen (4b), and each ball's image while it has not moved or turned */
  @ObservationIgnored private var painter: (BallPainter, Bool, CGFloat)?
  @ObservationIgnored private var ballCache: [Int: (key: [Double], img: (CGImage, Double, Double))] = [:]
  func ballPainter(upright: Bool, scale: CGFloat) -> BallPainter {
    if let p = painter, p.1 == upright, p.2 == scale { return p.0 }
    let look = TableLook.of(game: game.table.2), cloth = RGBA(css: look.cloth.base)
    let bounce = ["8": "120,200,160", "9": "120,165,235", "10": "110,170,240", "heyball": "120,200,150", "snooker": "120,205,150", "carom": "120,160,230"][game.table.2] ?? "120,200,160"
    let p = BallPainter(set: BallSet.of(game: game.table.2), bounce: bounce, dpr: Double(scale), portrait: upright,
                        lowRim: game != .eight && game != .carom, clothBase: [cloth.r * 255, cloth.g * 255, cloth.b * 255])
    painter = (p, upright, scale); ballCache = [:]
    return p
  }
  func ballImage(_ p: BallPainter, _ n: Int, _ X: Double, _ Y: Double, _ r: Double) -> (CGImage, Double, Double) {
    let m = orient[n] ?? IDENT, key = m + [X, Y, r]
    if let c = ballCache[n], c.key == key { return c.img }
    let img = p.ballImage(n, X, Y, r, p.axesOf(m))
    ballCache[n] = (key, img)
    return img
  }

  var cueN: Int { game == .carom ? 70 : 0 }
  var shown: [Ball] { rolling?.balls ?? balls }
  var cue: Ball? { shown.first { $0.n == cueN && $0.on } }

  init(game: Game) {
    self.game = game
    sim.setTable(game.table.0, game.table.1)
    rerack()
  }

  func rerack() {
    rolling = nil; inHand = game != .carom; potCount = 0
    switch game {
    case .eight: balls = sim.rack("8")
    case .nine: balls = sim.rack("9")
    case .ten: balls = sim.rack("10")
    case .heyball: balls = sim.rack("heyball")
    case .snooker: balls = sim.snookerRack()
    case .carom:
      balls = [Ball(70, sim.HEAD_X, sim.TW / 2 + 0.1524), Ball(71, sim.HEAD_X, sim.TW / 2), Ball(72, sim.FOOT[0], sim.FOOT[1])]
    }
    randomOrient()
    aimAtNearest()
  }

  func aimAtNearest() {
    guard let c = balls.first(where: { $0.n == cueN }) else { return }
    let others = balls.filter { $0.on && $0.n != cueN }
    if let t = others.min(by: { JSMath.hypot($0.x - c.x, $0.y - c.y) < JSMath.hypot($1.x - c.x, $1.y - c.y) }) {
      aim = atan2(t.y - c.y, t.x - c.x)
    }
  }

  /* only the power bar shoots (the page's rule) */
  func shoot() {
    guard rolling == nil, power > 0.01 else { power = 0; return }
    let tab = sim.newTable(balls, cue: cueN)
    sim.strike(tab, aim, power, spin)
    markPower = power
    rolling = tab; heard = 0; carry = 0; lastT = nil; inHand = false; power = 0
    play(tab)
  }

  func tick(_ now: TimeInterval) {
    defer { frame &+= 1 }
    guard let tab = rolling else { lastT = nil; return }
    /* as frameBody: never backwards, at most 50 ms a frame */
    let dt = min(0.05, max(0, lastT.map { now - $0 } ?? 1.0 / 60))
    lastT = now
    let want = dt / SIM_DT + carry
    var n = Int(want)
    carry = want - Double(n)
    let before = tab.balls.map { ($0.x, $0.y, $0.on) }
    var going = true
    while n > 0 && going { going = sim.stepTable(tab); n -= 1 }
    /* rollBall: each ball's orientation turned by its displacement, the top toward the motion */
    for (i, b) in tab.balls.enumerated() where before[i].2 {
      let dx = b.x - before[i].0, dy = b.y - before[i].1, d = JSMath.hypot(dx, dy)
      if d > 0 && d < 0.5 { orient[b.n] = rotate(orient[b.n] ?? IDENT, [-dy, dx, 0], d / sim.BALL_R) }
    }
    play(tab)
    if !going { settle(sim.resultOf(tab)) }
  }

  private func play(_ tab: Tab) {
    while heard < tab.hits.count { sound.hit(tab.hits[heard]); heard += 1 }
  }

  /* the roll is over: practice puts the cue ball back (in hand behind the string) and spots a
     potted snooker colour */
  private func settle(_ r: ShotResult) {
    var next = r.balls
    potCount += r.potted.filter { $0 != cueN }.count
    if let c = next.first(where: { $0.n == cueN }), !c.on {
      c.on = true; c.vx = 0; c.vy = 0
      let p = freeSpot(sim.HEAD_X - 0.2, sim.TW / 2, next.filter { $0 !== c })
      c.x = p.0; c.y = p.1
      inHand = true
    }
    if game == .snooker {
      for b in next where !b.on && b.n >= 57 {
        guard let s = sim.SPOTS[b.n] else { continue }
        let p = freeSpot(s[0], s[1], next.filter { $0 !== b && $0.on }); b.x = p.0; b.y = p.1; b.on = true
      }
    }
    next = next.map { $0.copy() }
    balls = next; rolling = nil
    if balls.allSatisfy({ !$0.on || $0.n == cueN }) { rerack() }
  }

  private func freeSpot(_ x: Double, _ y: Double, _ others: [Ball]) -> (Double, Double) {
    let R = sim.BALL_R
    var px = x
    while others.contains(where: { $0.on && JSMath.hypot($0.x - px, $0.y - y) < 2 * R + 1e-4 }) { px -= 2 * R }
    return (max(R + 0.001, px), y)
  }

  /* ball in hand: put the cue ball at (x, y) if it fits there */
  func place(_ x: Double, _ y: Double) {
    guard inHand, rolling == nil, let c = balls.first(where: { $0.n == cueN }) else { return }
    let R = sim.BALL_R, lo = R + 0.001
    let px = min(max(x, lo), sim.TL - lo), py = min(max(y, lo), sim.TW - lo)
    if balls.contains(where: { $0 !== c && $0.on && JSMath.hypot($0.x - px, $0.y - py) < 2 * R }) { return }
    c.x = px; c.y = py
    frame &+= 1
  }

  /* the guide (4d): aimTrace's first contact and the shot preview, run whole on a copy of the balls at
     the power the shot will have (the live pull, else the last shot's: markPower), cached on aim,
     power, spin and layout as shotPreview keys it */
  var markPower = 0.5
  @ObservationIgnored private var pvKey: [Double] = []
  @ObservationIgnored private var pvVal: (AimHit, Preview)?
  func guide() -> (AimHit, Preview)? {
    guard rolling == nil, let c = cue else { return nil }
    let pw = power > 0 ? power : markPower, q = { (v: Double, s: Double) in (v / s).rounded() }
    var key = [q(aim, 2e-5), q(pw, 0.001), q(spin.x, 0.005), q(spin.y, 0.005), q(spin.e, 0.002), c.x, c.y]
    for b in balls where b.n != cueN { key += b.on ? [b.x, b.y] : [-1] }
    if key == pvKey, let v = pvVal { return v }
    let dx = JSMath.cos(aim), dy = JSMath.sin(aim)
    let h = sim.aimTrace(balls, c.x, c.y, dx, dy, skip: [cueN], far: 6)
    let P = sim.previewStart(balls, cueN: cueN, aim, pw, spin, h, game == .carom ? PV_CAROM : PV_FULL, caromNeed: game == .carom ? 3 : 0)
    sim.previewRun(P)
    pvKey = key; pvVal = (h, P)
    return (h, P)
  }
}
