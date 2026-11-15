/* One table at play: the sim (FeltSim, index.html's physics bit for bit), the balls at rest, the
   roll in progress and the player's aim, power and english. The pocket games (8, 9, 10, Chinese
   8-ball) are played under their default rules by FeltSim's RulesEngine (sim 1e, the page's judge),
   two players on one device; snooker and carom are still the free practice table until their rule
   modules are ported. The roll steps exactly as the page's frame() does: dtMs / 1000 / SIM_DT steps
   a frame, the fraction carried to the next. */
import Foundation
import CoreGraphics
import FeltRender
import FeltSim
import Observation

enum TableGame: String, CaseIterable, Identifiable {
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
  let game: TableGame
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
  /* the rules (sim 1e): the game being played, nil on the practice tables */
  @ObservationIgnored let engine: RulesEngine
  private(set) var g: Game?
  /* the status line (the page's say()) and the banner over the table (flash()) */
  private(set) var msg = ""
  private(set) var banner: (title: String, sub: String, until: TimeInterval)?
  var rulesKind: String? { ["8": "8", "9": "9", "10": "10", "heyball": "heyball", "snooker": "snooker", "carom": "carom"][game.table.2] }

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
  /* the screen's device px a point, as the ball painter last made */
  var scaleFactor: Double { Double(painter?.2 ?? 3) }
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

  /* the ball struck: carom's shooter strikes their own cue ball (game.striker) */
  var cueN: Int { g?.striker ?? (game == .carom ? 70 : 0) }
  var shown: [Ball] { rolling?.balls ?? balls }
  var cue: Ball? { shown.first { $0.n == cueN && $0.on } }

  /* the opponent: nil for two players on one device, else the CPU's level, playing player 2 */
  let cpuLevel: String?
  @ObservationIgnored private var cpuBusy = false
  private(set) var cpuThinking = false

  init(game: TableGame, cpu: String? = nil) {
    self.game = game
    cpuLevel = cpu
    Words.cpuMode = cpuLevel != nil
    sim.setTable(game.table.0, game.table.1)
    engine = RulesEngine(sim: sim)
    rerack()
  }

  /* the game's balls as the sim's (velocities as the game left them; newTable zeroes the spin) */
  private func syncBalls() {
    guard let g else { return }
    balls = g.balls.map { gb in let b = Ball(gb.n, gb.x, gb.y); b.on = gb.on; return b }
    inHand = g.inHand != nil && g.winner == nil && g.option == nil
  }

  func rerack() {
    rolling = nil; inHand = game != .carom; potCount = 0; banner = nil
    if let k = rulesKind {
      g = engine.newGame(k)
      /* a test hook: `-felt-pots "1,9,8"` starts the rack with those balls down (the potted windows) */
      let a = ProcessInfo.processInfo.arguments
      if let i = a.firstIndex(of: "-felt-pots"), i + 1 < a.count {
        let ns = a[i + 1].split(separator: ",").compactMap { Int($0) }
        for j in g!.balls.indices where ns.contains(g!.balls[j].n) { g!.balls[j].on = false }
        if ns.contains(where: { $0 < 8 }) { g!.groups = ["solids", "stripes"] }
      }
      syncBalls()
      msg = k == "snooker" ? "\(Words.dWords(0)). On a red." : k == "carom" ? "\(Words.nameOf(0)) to break: the red first." : "\(Words.nameOf(0)) to break."
      randomOrient(); aimAtNearest()
      return
    }
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

  /* only the power bar shoots (the page's rule). Its release starts the stroke: the cue is driven
     into the ball over STROKE_MS, and the physics starts when it arrives (frameBody's shoot()) */
  static let STROKE_MS = 0.110
  private(set) var stroke: (power: Double, t0: TimeInterval?)?
  /* the cue after the strike: carried a few centimetres on and faded over 180 ms */
  private(set) var lastCue: (x: Double, y: Double, ang: Double)?
  private(set) var shotAt: TimeInterval = 0
  private(set) var now: TimeInterval = 0
  func shoot() {
    guard rolling == nil, stroke == nil, power > 0.01, g?.option == nil, g?.winner == nil, !cpuTurn else { power = 0; return }
    markPower = power
    stroke = (power, nil)
  }
  private func strikeNow(_ pw: Double, _ t: TimeInterval) {
    /* a shot the rules need called: the obvious call from the guide's preview, the ball it pots and its
       pocket, else a declared safety (the page's call menu is not ported yet) */
    if var gm = g, !cpuTurn, let need = engine.callNeed(gm) {
      var c = ShotCall()
      if let (_, P) = guide(), let f = P.first, P.objPot >= 0 { c.ball = f; c.pocket = P.objPot; c.auto = need.auto } else { c.safety = true }
      gm.call = c; g = gm
    }
    let tab = sim.newTable(balls, cue: cueN)
    if let c = cue { lastCue = (c.x, c.y, aim) }
    sim.strike(tab, aim, pw, spin)
    rolling = tab; heard = 0; carry = 0; lastT = t; inHand = false; power = 0; stroke = nil; shotAt = t
  }

  /* the pause menu is up: the table stands still (frameBody does not run under it) */
  var paused = false
  func tick(_ now: TimeInterval) {
    defer { frame &+= 1 }
    if paused { lastT = nil; return }
    self.now = now
    pots.removeAll { now - $0.t >= TableModel.POT_MS }
    if let b = banner, now >= b.until { banner = nil }
    potTrack()
    effects.removeAll { now - $0.t >= $0.d }
    if let st = stroke {
      if st.t0 == nil { stroke = (st.power, now) } else if now - st.t0! >= TableModel.STROKE_MS { strikeNow(st.power, now) }
    }
    if cpuTurn && rolling == nil && stroke == nil && !cpuBusy { cpuStep() }
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
    onHits(Array(tab.hits[heard...]), before, tab, now)
    for (i, b) in tab.balls.enumerated() where before[i].2 && !b.on { onPot(b.n, tab.pocketOf[b.n] ?? -1, (before[i].0, before[i].1), now) }
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
    if g != nil { settleRules(r); return }
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

  /* settle() for a pocket game: the page's judge, then its words (banner and status line) */
  private func settleRules(_ r: ShotResult) {
    guard let before = g else { return }
    let shot = RuleShot(r)
    let shooter = before.turn, next = engine.judge(before, shot)
    potCount += next.verdict?.potted.count ?? 0
    g = next; rolling = nil; spin = Spin()
    syncBalls()
    words(next, shooter)
    aimAtNearest()
  }
  private func words(_ gm: Game, _ shooter: Int, chose: (who: Int, kind: String, choice: String)? = nil) {
    guard let v = gm.verdict else { return }
    if gm.winner != nil { msg = Words.overLine(gm); banner = nil; return }
    if gm.kind == "carom" {
      let w = Words.carom(v, gm, shooter, gm.turn)
      msg = w.msg
      if gm.option == nil { banner = (w.banner.0, w.banner.1, now + w.banner.2) }
      return
    }
    if gm.kind == "snooker" {
      let w = Words.snooker(v, gm, shooter, gm.option?.who ?? gm.turn)
      msg = gm.option != nil ? "\(w.msg) \(Words.OPT[gm.option!.kind]?["head"] ?? ""): \(Words.nameOf(gm.option!.who)) to choose." : w.msg
      if let b = w.banner, gm.option == nil { banner = (b.0, b.1, now + b.2) }
      return
    }
    let who = gm.turn, lt = engine.legalTargets(gm)
    let ballOn = ["9", "10"].contains(gm.kind) && !lt.isEmpty ? " Ball on: the \(lt[0])." : ""
    let group = v.grouped ? "\(Words.isOf(shooter)) \(gm.groups[shooter] ?? "")." : ""
    let onTwo = { (p: Int) in (gm.kind == "9" || gm.kind == "10") && gm.rules.threeFoul != nil && gm.fouls[p] >= 2 }
    let warn = { (p: Int) in onTwo(p) ? "\(Words.isOf(p)) on two fouls: a third loses." : "" }
    let extra = Words.callWords(v, gm.kind, shooter, chose: chose)
    if let o = gm.option {
      let w = Words.OPT[o.kind]
      msg = extra.isEmpty ? "\(w?["head"] ?? o.kind): \(Words.nameOf(o.who)) to choose." : extra
      return
    }
    if !extra.isEmpty && v.foul == nil {
      banner = (extra, who == shooter ? "\(Words.nameOf(who)) shoots again" : Words.turnOf(who), now + 1.5)
      msg = "\(extra) \(Words.turnOf(who)).\(ballOn)"
    } else if let f = v.foul {
      let hand = (extra.isEmpty ? "" : extra + "\n") + Words.handWords(who, kitchen: gm.inHand == "kitchen")
      let w = [warn(shooter), warn(who)].filter { !$0.isEmpty }.joined(separator: "\n")
      banner = ("Foul: \(f)", hand + (w.isEmpty ? "" : "\n" + w), now + (w.isEmpty ? 1.5 : 2.4))
      msg = gm.inHand != nil ? Words.hint(gm.inHand) + ballOn : "Foul: \(f). \(hand).\(ballOn)"
    } else if who != shooter {
      let w = warn(who)
      banner = (Words.turnOf(who), w.isEmpty ? String(group.dropLast()) : w, now + (w.isEmpty ? 0.9 : 2.0))
      msg = "\(group.isEmpty ? "" : group + " ")\(Words.turnOf(who)).\(ballOn)"
    } else {
      if !group.isEmpty { banner = ("\(Words.isOf(shooter)) \(gm.groups[shooter] ?? "")", "and shoots again", now + 1.1) }
      msg = "\(group.isEmpty ? "" : group + " ")\(Words.nameOf(who)) goes again.\(ballOn)"
    }
  }
  /* a choice the rules give (game.option) made */
  func choose(_ choice: String) {
    guard let gm = g, let o = gm.option, let next = engine.chooseOption(gm, choice) else { return }
    g = next; syncBalls()
    let said = choice.hasPrefix("free:") ? "free ball, the \(snkName(Int(choice.dropFirst(5)) ?? 0))" : Words.optLabel(o.kind, choice).lowercased()
    msg = "\(Words.nameOf(o.who)): \(said). \(Words.turnOf(next.turn))."
    if next.option != nil { words(next, gm.turn, chose: (o.who, o.kind, choice)) }
    randomOrientIfRacked(gm, next)
    aimAtNearest()
  }
  /* the CPU's turn (page 5's think): its search off the main thread on its own sim, held for the page's
     think time (cpuThinkMs, from the search's start), then its stroke through the same cue as a player's */
  var cpuTurn: Bool { cpuLevel != nil && g != nil && g!.winner == nil && (g!.option?.who ?? g!.turn) == 1 }
  func cpuStep() {
    guard cpuTurn, !cpuBusy, rolling == nil, stroke == nil, let gm = g, let level = cpuLevel else { return }
    cpuBusy = true; cpuThinking = true
    let t0 = now, (table, shape, _) = game.table, seed = Double(Int.random(in: 1...1_000_000))
    if gm.option != nil {
      let pick = CPU(engine: engine).cpuOption(gm, level: level) ?? gm.option!.choices[0]
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(900))
        cpuBusy = false; cpuThinking = false
        if g?.option != nil { choose(pick) }
      }
      return
    }
    Task.detached(priority: .userInitiated) {
      let sim = Sim(); sim.setTable(table, shape)
      let shot = CPU(engine: RulesEngine(sim: sim)).cpuShot(gm, seed: seed, level: level)
      await MainActor.run { self.cpuPlay(shot, gm, t0: t0, seed: seed) }
    }
  }
  private func cpuPlay(_ shot: CPUShot, _ gm: Game, t0: TimeInterval, seed: Double) {
    guard var g0 = g, g0.shots == gm.shots, g0.turn == gm.turn else { cpuBusy = false; cpuThinking = false; return }
    if let p = shot.place { g0 = engine.placeCue(g0, p[0], p[1]) }
    g0.call = shot.call; g = g0; syncBalls()
    aim = shot.angle; spin = shot.spin
    let think = cpuThinkMs(gm, shot, seed) / 1000, wait = max(0, think - (now - t0))
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
      cpuThinking = false
      power = shot.power; markPower = shot.power
      stroke = (shot.power, nil)
      cpuBusy = false
    }
  }
  /* cpuThinkMs: short on the break or an easy pot, longer on a hard one, longest on a safety or kick */
  private func cpuThinkMs(_ gm: Game, _ shot: CPUShot, _ seed: Double) -> Double {
    let T = ["break": 900.0, "pot": 650, "carom": 1500, "bank": 2000, "combo": 2200, "safety": 1900, "kick": 2300, "push": 1600, "blind": 1300, "kickpot": 2300, "jump": 2100, "swerve": 2100]
    var ms = T[shot.intent.type] ?? 1300
    if shot.intent.type == "pot" || shot.intent.type == "carom" { ms += 1900 * pow(1 - min(1, max(0, shot.intent.q.isFinite ? shot.intent.q : 0.5)), 1.5) }
    if gm.inHand != nil && !gm.breakShot { ms += 500 }
    ms *= 0.85 + 0.3 * cpuRng((seed.truncatingRemainder(dividingBy: 1e6)) * 7919 + 3)()
    return max(350, min(3500, ms.rounded()))
  }

  private func randomOrientIfRacked(_ a: Game, _ b: Game) { if b.breakShot && !a.breakShot { randomOrient() } }

  private func freeSpot(_ x: Double, _ y: Double, _ others: [Ball]) -> (Double, Double) {
    let R = sim.BALL_R
    var px = x
    while others.contains(where: { $0.on && JSMath.hypot($0.x - px, $0.y - y) < 2 * R + 1e-4 }) { px -= 2 * R }
    return (max(R + 0.001, px), y)
  }

  /* ball in hand: put the cue ball at (x, y) if it fits there */
  func place(_ x: Double, _ y: Double) {
    guard inHand, rolling == nil, !cpuTurn, let c = balls.first(where: { $0.n == cueN }) else { return }
    if let gm = g {
      let R = sim.BALL_R, lo = R + 0.001
      let px = min(max(x, lo), sim.TL - lo), py = min(max(y, lo), sim.TW - lo)
      guard engine.canPlace(gm, px, py) else { return }
      g = engine.placeCue(gm, px, py); c.x = px; c.y = py
      frame &+= 1
      return
    }
    let R = sim.BALL_R, lo = R + 0.001
    let px = min(max(x, lo), sim.TL - lo), py = min(max(y, lo), sim.TW - lo)
    if balls.contains(where: { $0 !== c && $0.on && JSMath.hypot($0.x - px, $0.y - py) < 2 * R }) { return }
    c.x = px; c.y = py
    frame &+= 1
  }

  /* 4c: a pot runs on into its drop over POT_MS, shrinking and darkening under the rim */
  static let POT_MS = 0.420
  struct Pot { let n: Int, k: Int, from: (Double, Double), t: TimeInterval }
  @ObservationIgnored private(set) var pots: [Pot] = []
  func onPot(_ n: Int, _ k: Int, _ from: (Double, Double), _ t: TimeInterval) {
    pots.removeAll { $0.n == n }
    pots.append(Pot(n: n, k: k, from: from, t: t))
  }

  /* onHits: hits carry no position, so the contacts are found from where the balls were last frame and
     where they are now. Ball-ball a ring at the contact, a cushion a soft glow on the nose, the cue a tip flash */
  struct Fx { let kind: String, key: String, x: Double, y: Double, v: Double, t: TimeInterval, d: Double }
  @ObservationIgnored private(set) var effects: [Fx] = []
  private func onHits(_ hits: [Hit], _ before: [(Double, Double, Bool)], _ T: Tab, _ now: TimeInterval) {
    if hits.isEmpty { return }
    var ball = 0.0, rail = 0.0, cueV = 0.0
    for h in hits {
      if h.kind == "ball" { ball = max(ball, h.v) } else if h.kind == "rail" || h.kind == "jaw" { rail = max(rail, h.v) } else if h.kind == "cue" { cueV = h.v }
    }
    var prev: [Int: (Double, Double)] = [:]
    for (i, b) in T.balls.enumerated() { prev[b.n] = (before[i].0, before[i].1) }
    let B = T.balls.filter { $0.on }, R = sim.BALL_R
    func recent(_ key: String) -> Bool { effects.contains { $0.key == key && now - $0.t < 0.140 } }
    if ball > 0.05 {
      var found = 0
      outer: for i in 0..<B.count {
        for j in (i + 1)..<max(i + 1, B.count) {
          if found >= 4 { break outer }
          let a = B[i], b = B[j], pa = prev[a.n] ?? (a.x, a.y), pb = prev[b.n] ?? (b.x, b.y)
          if JSMath.hypot(a.x - pa.0 - b.x + pb.0, a.y - pa.1 - b.y + pb.1) < 1e-5 { continue }
          var best = Double.infinity, bu = 0.0
          for s in 0...4 {
            let u = Double(s) / 4, d = JSMath.hypot(pa.0 + (a.x - pa.0) * u - pb.0 - (b.x - pb.0) * u, pa.1 + (a.y - pa.1) * u - pb.1 - (b.y - pb.1) * u)
            if d < best { best = d; bu = u }
          }
          let key = "\(a.n)-\(b.n)"
          if best < 2 * R + 0.004 && !recent(key) {
            found += 1
            effects.append(Fx(kind: "ball", key: key, x: (pa.0 + pb.0 + (a.x - pa.0 + b.x - pb.0) * bu) / 2, y: (pa.1 + pb.1 + (a.y - pa.1 + b.y - pb.1) * bu) / 2, v: ball, t: now, d: 0.280))
          }
        }
      }
    }
    if rail > 0.05 {
      var found = 0
      for b in B {
        for s in sim.CUSH {
          if found >= 3 { break }
          let ex = s[2] - s[0], ey = s[3] - s[1], L2 = ex * ex + ey * ey
          let t = L2 != 0 ? min(1, max(0, ((b.x - s[0]) * ex + (b.y - s[1]) * ey) / L2)) : 0
          let px = s[0] + ex * t, py = s[1] + ey * t, key = "r\(b.n)"
          if JSMath.hypot(b.x - px, b.y - py) < R + 0.004 && !recent(key) { found += 1; effects.append(Fx(kind: "rail", key: key, x: px, y: py, v: rail, t: now, d: 0.340)) }
        }
      }
    }
    if cueV > 0, let c = B.first(where: { $0.n == T.cue }) {
      let p = prev[T.cue] ?? (c.x, c.y), h = JSMath.hypot(c.vx, c.vy), v = h == 0 ? 1 : h
      effects.append(Fx(kind: "cue", key: "cue", x: p.0 - c.vx / v * R, y: p.1 - c.vy / v * R, v: cueV, t: now, d: 0.200))
    }
  }


  /* 6b3: the balls down in pot order, who potted each, and when (a pot's window waits for its drop) */
  @ObservationIgnored private(set) var potOrder: [Int] = []
  @ObservationIgnored private(set) var potBy: [Int: Int] = [:]
  @ObservationIgnored private(set) var potAt: [Int: TimeInterval] = [:]
  private func potTrack() {
    guard let gm = g, ["8", "9", "10", "heyball"].contains(gm.kind) else { potOrder = []; return }
    let src = rolling?.balls.map { ($0.n, $0.on) } ?? gm.balls.map { ($0.n, $0.on) }
    let off = src.filter { !$0.1 && $0.0 >= 1 && $0.0 <= 15 }.map { $0.0 }
    potOrder = potOrder.filter { off.contains($0) }
    for n in off.filter({ !potOrder.contains($0) }).sorted() {
      potOrder.append(n); potBy[n] = gm.turn; potAt[n] = rolling != nil ? now + TableModel.POT_MS : 0
    }
  }

  /* railNext (6b2): the ball to play next on a human's turn while aiming. 9, 10 and rotation: the ball on; 8-ball,
     Chinese 8-ball and 14.1: the ball the aim meets first when it is a legal target */
  func railNext() -> Int? {
    guard let gm = g, gm.winner == nil, rolling == nil, stroke == nil, !cpuTurn, POCKET_KINDS.contains(gm.kind) else { return nil }
    let lt = engine.legalTargets(gm)
    if !is8(gm.kind) && gm.kind != "straight" { return lt.first }
    guard let c = cue else { return nil }
    let h = sim.aimTrace(balls, c.x, c.y, JSMath.cos(aim), JSMath.sin(aim), skip: [c.n], far: 6)
    if h.kind == "ball", let b = h.ball, b.n > 0, lt.contains(b.n) { return b.n }
    return nil
  }

  /* the table's pocket shapes for this layout (the pot animation's clip), built with the bake's view */
  @ObservationIgnored private var potGeo: (TablePainter, Double)?
  func potGeometry(_ m: Mapper) -> TablePainter {
    if let g = potGeo, g.1 == m.k { return g.0 }
    let p = TablePainter(sim: sim, view: m.view, dpr: 1, rail: m.rail, look: TableLook.of(game: game.table.2))
    potGeo = (p, m.k)
    return p
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
