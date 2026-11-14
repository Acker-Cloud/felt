/* One table at play: the sim (FeltSim, index.html's physics bit for bit), the balls at rest, the
   roll in progress and the player's aim, power and english. No rules yet: this is the web build's
   free practice table (Practice > the rack) on every table the port has. The roll steps exactly as
   the page's frame() does: dtMs / 1000 / SIM_DT steps a frame, the fraction carried to the next. */
import Foundation
import FeltSim
import Observation

enum Game: String, CaseIterable, Identifiable {
  case eight = "8-Ball", nine = "9-Ball", ten = "10-Ball", heyball = "Chinese 8-Ball", snooker = "Snooker", carom = "Three-Cushion"
  var id: String { rawValue }
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

  var cueN: Int { game == .carom ? 70 : 0 }
  var shown: [Ball] { rolling?.balls ?? balls }
  var cue: Ball? { shown.first { $0.n == cueN && $0.on } }

  init(game: Game) {
    self.game = game
    switch game {
    case .eight: sim.setTable("7")
    case .nine, .ten: sim.setTable("9")
    case .heyball: sim.setTable("heyball")
    case .snooker: sim.setTable("snooker", "compact")
    case .carom: sim.setTable("carom")
    }
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
    rolling = tab; heard = 0; carry = 0; lastT = nil; inHand = false; power = 0
    play(tab)
  }

  func tick(_ now: TimeInterval) {
    defer { frame &+= 1 }
    guard let tab = rolling else { lastT = nil; return }
    let dt = min(0.1, lastT.map { now - $0 } ?? 1.0 / 60)
    lastT = now
    let want = dt / SIM_DT + carry
    var n = Int(want)
    carry = want - Double(n)
    var going = true
    while n > 0 && going { going = sim.stepTable(tab); n -= 1 }
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

  /* the guide: where the cue ball first meets a ball or the cushion line along the aim */
  struct Guide { var end: (Double, Double); var ghost: Bool; var objectDir: (Double, Double)?; var target: Int? }
  func guide() -> Guide? {
    guard rolling == nil, let c = cue else { return nil }
    let R = sim.BALL_R, dx = cos(aim), dy = sin(aim)
    var best = Double.infinity, target: Ball?
    for b in shown where b.on && b !== c {
      let fx = b.x - c.x, fy = b.y - c.y, along = fx * dx + fy * dy
      if along <= 0 { continue }
      let perp2 = fx * fx + fy * fy - along * along, r2 = 4 * R * R
      if perp2 >= r2 { continue }
      let t = along - (r2 - perp2).squareRoot()
      if t < best { best = t; target = b }
    }
    let lo = R
    var wall = Double.infinity
    if dx > 0 { wall = min(wall, (sim.TL - lo - c.x) / dx) } else if dx < 0 { wall = min(wall, (lo - c.x) / dx) }
    if dy > 0 { wall = min(wall, (sim.TW - lo - c.y) / dy) } else if dy < 0 { wall = min(wall, (lo - c.y) / dy) }
    if let b = target, best < wall {
      let gx = c.x + dx * best, gy = c.y + dy * best, ox = b.x - gx, oy = b.y - gy, l = (ox * ox + oy * oy).squareRoot()
      return Guide(end: (gx, gy), ghost: true, objectDir: (ox / l, oy / l), target: b.n)
    }
    return Guide(end: (c.x + dx * wall, c.y + dy * wall), ghost: false, objectDir: nil, target: nil)
  }
}
