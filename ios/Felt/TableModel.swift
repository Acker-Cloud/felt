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
  /* the page's home order: 8, 9, 10, 14.1, rotation, bumper, snooker, carom, Chinese 8-ball */
  case eight = "8-Ball", nine = "9-Ball", ten = "10-Ball", straight = "Straight Pool", rotation = "Rotation", bumper = "Bumper Pool"
  case snooker = "Snooker", carom = "Three-Cushion", heyball = "Chinese 8-Ball"
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
    case .bumper: ("bumper", "octagon", "bumper")
    case .straight: ("7", nil, "straight")
    case .rotation: ("7", nil, "rotation")
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
    case .bumper: "Round the posts"
    case .straight: "14.1, a point a ball"
    case .rotation: "Numbers score, 61 wins"
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
  /* a flash asked for before the clock runs (a new rack): shown for its ms from the next tick */
  @ObservationIgnored private var flashDue: (String, String, TimeInterval)?
  var rulesKind: String? { ["8": "8", "9": "9", "10": "10", "heyball": "heyball", "snooker": "snooker", "carom": "carom", "bumper": "bumper", "straight": "straight", "rotation": "rotation"][game.table.2] }

  /* the baked table (FeltRender: index.html's paintTable and vignette) for one screen size */
  /* the table this game is played on, and one Sim set to it exactly as the model's is (the art and the CPU's
     search build their own): a bumper table reached from the 7 ft table, as every golden reaches it */
  let spec: (table: String, shape: String?, pockets: String)
  nonisolated static func setUp(_ sim: Sim, _ spec: (table: String, shape: String?, pockets: String)) {
    if spec.table == "bumper" { sim.setTable("7") }
    sim.setPockets(spec.pockets)
    sim.setTable(spec.table, spec.shape)
  }
  struct Baked { let image: CGImage; let size: CGSize; let scale: CGFloat }
  private(set) var tableImage: Baked?
  @ObservationIgnored private var baking: CGSize?
  func bake(_ size: CGSize, scale: CGFloat) {
    guard size.width > 0, size.height > 0, tableImage?.size != size, baking != size else { return }
    baking = size
    let look = game.table.2, spec = spec
    Task.detached(priority: .userInitiated) {
      let sim = Sim(); TableModel.setUp(sim, spec)
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
    let bounce = ["8": "120,200,160", "9": "120,165,235", "10": "110,170,240", "heyball": "120,200,150", "snooker": "120,205,150", "carom": "120,160,230", "bumper": "170,190,110", "straight": "110,190,175", "rotation": "236,122,118"][game.table.2] ?? "120,200,160"
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
  /* an exhibition (6f, 'exhibit'): both players the CPU, each at its own level and with its own style (arch) */
  let exhib: [String]?
  let exhibArch: [String]?
  /* a party (6f, 'party'): 2 to 4 people in turn on a ring ruleset; their racks won, the rack, the ruleset */
  struct Party { var names: [String], wins: [Int], rack = 0, ruleset: String }
  private(set) var party: Party?
  /* a quick tournament's match (6f, tmatch): the bracket's match, the opponent, racks won, the race in racks (a points
     race is one game, need 1), the lag's winner, and where the result goes */
  struct TMatch { let m: Int, foe: String, level: String, arch: String?, need: Int, points: Bool, race: Int, lag: Int, ruleset: String; var score = [0, 0], rack = 1, done = false, counted = false }
  private(set) var tmatch: TMatch?
  @ObservationIgnored var onReport: ((Int, Int, Int, Bool) -> Void)?
  /* the handoff: the player the device is passed to (the breaker at a rack's start), until they are ready */
  var handoff: (p: Int, first: Bool)? = nil
  @ObservationIgnored private var cpuBusy = false
  private(set) var cpuThinking = false

  init(game: TableGame, cpu: String? = nil, exhib: [String]? = nil, exhibArch: [String]? = nil, party: (names: [String], ruleset: String)? = nil, tourney: Tourney? = nil) {
    self.game = game
    /* tourneyPlay: the player's next match, the opponent's level, the lag from the tournament's seed */
    var tm: TMatch? = nil
    if let t = tourney, let m = t.mine() {
      let foe = t.foe(m), pts = Tourney.points(t.kind)
      tm = TMatch(m: m, foe: foe.name, level: foe.level ?? "medium", arch: foe.arch, need: pts ? 1 : t.race, points: pts, race: t.race,
                      lag: cpuRng(Double(CareerLib.seedOf([String(t.seed), "lag", String(m)])))() < 0.5 ? 0 : 1, ruleset: t.ruleset)
    }
    cpuLevel = tm?.level ?? (exhib == nil && party == nil ? cpu : nil)
    self.exhib = exhib
    self.exhibArch = exhibArch
    self.party = party.map { Party(names: $0.names, wins: $0.names.map { _ in 0 }, ruleset: $0.ruleset) }
    Words.cpuMode = cpuLevel != nil
    Words.names = exhib.map { $0.map { TableModel.FOES[$0] ?? "CPU" } } ?? party?.names
    /* start(): the settings' table (every pool game on its size and pockets; snooker's size; the bumper table's shape) */
    spec = switch game {
    case .eight, .nine, .ten, .straight, .rotation: (Prefs.table, nil, Prefs.pockets)
    case .snooker: ("snooker", Prefs.snookerTable, Prefs.pockets)
    case .bumper: ("bumper", Prefs.bumperTable, Prefs.pockets)
    default: (game.table.0, game.table.1, Prefs.pockets)
    }
    TableModel.setUp(sim, spec)
    engine = RulesEngine(sim: sim)
    tmatch = tm
    rerack()
    /* a test hook: `-felt-paused` opens the table with the pause menu up */
    if ProcessInfo.processInfo.arguments.contains("-felt-paused") { paused = true }
  }

  /* the game's balls as the sim's (velocities as the game left them; newTable zeroes the spin) */
  private func syncBalls() {
    guard let g else { return }
    balls = g.balls.map { gb in let b = Ball(gb.n, gb.x, gb.y); b.on = gb.on; return b }
    inHand = g.inHand != nil && g.winner == nil && g.option == nil
  }

  func rerack() {
    rolling = nil; inHand = game != .carom && game != .bumper; picked = false; resetCall(); pottedBy = [[], [], [], []]; potCount = 0; banner = nil
    if let k = rulesKind {
      /* newGame with the settings' rules, snooker's frames and carom's race and cushions */
      g = tmatch != nil ? tourneyGame(k) : k == "snooker" ? engine.snookerGame(frames: Prefs.snookerFrames, first: 0)
        : k == "carom" ? engine.caromGame(race: Prefs.caromRace, cushions: Prefs.caromCush)
        : party != nil ? partyGame(k) : engine.newGame(k, rules: Prefs.rules(k))
      /* a test hook: `-felt-pots "1,9,8"` starts the rack with those balls down (the potted windows) */
      let a = ProcessInfo.processInfo.arguments
      if let i = a.firstIndex(of: "-felt-pots"), i + 1 < a.count {
        let ns = a[i + 1].split(separator: ",").compactMap { Int($0) }
        for j in g!.balls.indices where ns.contains(g!.balls[j].n) { g!.balls[j].on = false }
        if ns.contains(where: { $0 < 8 }) { g!.groups = ["solids", "stripes"] }
        /* the rack is past its break: calls are open, the cue ball where the rack left it */
        g!.breakShot = false; g!.inHand = nil; inHand = false
      }
      syncBalls()
      msg = k == "snooker" ? "\(Words.dWords(0)). On a red." : k == "carom" ? "\(Words.nameOf(0)) to break: the red first." : "\(Words.nameOf(0)) to break."
      /* start()'s flash: who breaks, and where the ball goes (1.4 s; carom 1.6 s, the race) */
      let brk = cpuLevel != nil ? "You break" : "Player 1 breaks"
      if k == "bumper" {
        msg = "Opening shots: \(cpuLevel != nil ? "you shoot" : "Red shoots") the marked ball at the far cup."
        flashDue = ("Opening shots", "\(cpuLevel != nil ? "You shoot" : "Red shoots") the marked ball at the far cup", 1.6)
      } else if k == "carom" { flashDue = (brk, "Hit the red first. \(g!.need == 1 ? "One cushion" : "Three cushions"), \(g!.race!) points", 1.6) }
      else { flashDue = (brk, k == "snooker" ? "Ball in hand in the D" : "Ball in hand behind the line", 1.4) }
      randomOrient(); aimAtNearest()
      return
    }
    switch game {
    case .eight: balls = sim.rack("8")
    case .nine: balls = sim.rack("9")
    case .ten: balls = sim.rack("10")
    case .heyball: balls = sim.rack("heyball")
    case .snooker: balls = sim.snookerRack()
    case .bumper, .straight, .rotation: balls = []
    case .carom:
      balls = [Ball(70, sim.HEAD_X, sim.TW / 2 + 0.1524), Ball(71, sim.HEAD_X, sim.TW / 2), Ball(72, sim.FOOT[0], sim.FOOT[1])]
    }
    randomOrient()
    aimAtNearest()
  }

  /* bumper pool: the player chose the ball to strike this turn (pickBall), so auto aim keeps it */
  @ObservationIgnored var picked = false
  func aimAtNearest() {
    /* auto aim off: each turn keeps the aim it was left with (a new rack still aims) */
    if !Prefs.autoAim && (g?.shots ?? 0) > 0 { return }
    /* bumper's autoAim (page 5): suggestBumper's ball unless one was picked; its line, or straight at the far cup */
    if game == .bumper, var gm = g, gm.winner == nil, let sg = CPU(engine: engine).suggestBumper(gm) {
      if !picked, let n = sg.n, n != gm.striker { gm.striker = n; g = gm; syncBalls() }
      if let c = cue {
        let T = sim.POCKETS[sg.k]
        aim = g?.striker == sg.n ? sg.angle : atan2(T[1] - c.y, T[0] - c.x)
      }
      return
    }
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
    /* a pull the call refuses (no needed call yet) opens the call's menu on the let-go, the pockets first */
    if !callReady { power = 0; callMenu = true; return }
    markPower = power
    stroke = (power, nil)
  }
  private func strikeNow(_ pw: Double, _ t: TimeInterval) {
    /* shoot(): the declaration the player built (humanCall) goes on the game; judge takes it from there */
    if var gm = g, !cpuTurn { gm.call = humanCall(); g = gm }
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
    if let f = flashDue { banner = (f.0, f.1, now + f.2); flashDue = nil }
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
    picked = false; resetCall()
    gBefore = g
    guard let before = g else { return }
    let shot = RuleShot(r)
    let shooter = before.turn, next = engine.judge(before, shot)
    potCount += next.verdict?.potted.count ?? 0
    if let gm0 = gBefore, gm0.turn < 4 { pottedBy[gm0.turn] += next.verdict?.potted.filter { $0 > 0 } ?? [] }
    g = next; rolling = nil; spin = Spin()
    /* a party: the device is handed over each time the turn goes to another player (or a choice to another) */
    if party != nil, next.winner == nil, (next.option?.who ?? next.turn) != shooter { handoff = (next.option?.who ?? next.turn, false) }
    syncBalls()
    words(next, shooter)
    aimAtNearest()
  }
  private func words(_ gm: Game, _ shooter: Int, chose: (who: Int, kind: String, choice: String)? = nil) {
    guard let v = gm.verdict else { return }
    if gm.winner != nil { msg = Words.overLine(gm); banner = nil; tourneyRackOver(); return }
    if gm.kind == "bumper" {
      let w = Words.bumper(v, gm, shooter, gm.turn)
      msg = w.msg
      banner = w.banner.map { ($0.0, $0.1, now + $0.2) }
      return
    }
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
  static let FOES = ["easy": "Rookie", "medium": "Regular", "hard": "Hustler"]
  var cpuTurn: Bool { (cpuLevel != nil || exhib != nil) && g != nil && g!.winner == nil && (exhib != nil || (g!.option?.who ?? g!.turn) == 1) }
  /* the level searching for the player to act now: the opponent's, or an exhibition's player's own */
  var actingLevel: String? { exhib.map { $0[min(1, g?.option?.who ?? g?.turn ?? 0)] } ?? cpuLevel }
  /* the person searching: a tournament opponent's archetype, on the hill when either side is a rack from the match; an
     exhibition player's own; else a bare level */
  var actingArch: String? { exhibArch.map { $0[min(1, g?.option?.who ?? g?.turn ?? 0)] } ?? tmatch?.arch }
  var actingHill: Bool { guard let t = tmatch, !t.points else { return false }; return t.score.contains(t.need - 1) }
  func cpuStep() {
    guard cpuTurn, !cpuBusy, rolling == nil, stroke == nil, let gm = g, let level = actingLevel else { return }
    let arch = actingArch, hill = actingHill
    cpuBusy = true; cpuThinking = true
    let t0 = now, spec = spec, seed = Double(Int.random(in: 1...1_000_000))
    if gm.option != nil {
      let c = CPU(engine: engine); c.arch = arch; c.hill = hill
      let pick = c.cpuOption(gm, level: level) ?? gm.option!.choices[0]
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(900))
        cpuBusy = false; cpuThinking = false
        if g?.option != nil { choose(pick) }
      }
      return
    }
    Task.detached(priority: .userInitiated) {
      let sim = Sim(); TableModel.setUp(sim, spec)
      let c = CPU(engine: RulesEngine(sim: sim)); c.arch = arch; c.hill = hill
      let shot = c.cpuShot(gm, seed: seed, level: level)
      await MainActor.run { self.cpuPlay(shot, gm, t0: t0, seed: seed) }
    }
  }
  private func cpuPlay(_ shot: CPUShot, _ gm: Game, t0: TimeInterval, seed: Double) {
    guard var g0 = g, g0.shots == gm.shots, g0.turn == gm.turn else { cpuBusy = false; cpuThinking = false; return }
    if let p = shot.place { g0 = engine.placeCue(g0, p[0], p[1]) }
    if gm.kind == "bumper", let b = shot.ball { g0.striker = b }
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
    let T = ["break": 900.0, "pot": 650, "carom": 1500, "bumper": 1100, "bank": 2000, "combo": 2200, "safety": 1900, "kick": 2300, "push": 1600, "blind": 1300, "kickpot": 2300, "jump": 2100, "swerve": 2100]
    var ms = T[shot.intent.type] ?? 1300
    if shot.intent.type == "pot" || shot.intent.type == "carom" { ms += 1900 * pow(1 - min(1, max(0, shot.intent.q.isFinite ? shot.intent.q : 0.5)), 1.5) }
    if gm.inHand != nil && !gm.breakShot { ms += 500 }
    /* times the personality's pace (P.think) and a seeded jitter */
    ms *= CPUProfile.make(actingLevel ?? "medium", arch: actingArch).think * (0.85 + 0.3 * cpuRng((seed.truncatingRemainder(dividingBy: 1e6)) * 7919 + 3)())
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


  /* tourneyTerms: the tournament's rules (locked), who breaks (the lag's winner, then alternate breaks; carom the player) */
  private func tourneyGame(_ k: String) -> Game {
    let t = tmatch!, br = k == "carom" ? 0 : (t.lag + t.rack - 1) % 2
    var c = CallConfig(); c.mode = Prefs.calls
    if k == "snooker" { return engine.snookerGame(frames: 1, first: br) }
    if k == "carom" { return engine.caromGame(race: t.race, cushions: 3) }
    var gm = engine.newGame(k, rules: makeRules(k, ruleset: t.ruleset, call: c, race: k == "straight" ? t.race : nil, locked: true))
    if br > 0 { gm.turn = br; gm.breaker = br }
    return gm
  }
  /* tourneyRackOver: a rack's winner counts; the match ends at the race (a points race: the game's points) */
  func tourneyRackOver() {
    guard var t = tmatch, !t.done, !t.counted, let w = g?.winner else { return }
    t.counted = true
    t.score[w] += 1
    if t.score[w] >= t.need {
      t.done = true
      let rec = t.points ? [0, 1].map { p in p == w ? t.race : max(0, min(t.race - 1, g?.score?[p] ?? 0)) } : t.score
      onReport?(t.m, rec[0], rec[1], false)
    }
    tmatch = t
  }
  func tourneyNextRack() { guard var t = tmatch, !t.done else { return }; t.rack += 1; t.counted = false; tmatch = t; rerack() }
  /* tourneyAbandon: a match left before its end is a forfeit, the racks (or points) won so far against the race */
  func tourneyAbandon() {
    guard let t = tmatch, !t.done else { return }
    let mine = t.points ? (g?.score?[0] ?? 0) : t.score[0]
    onReport?(t.m, max(0, min(mine, t.race - 1)), t.race, true)
    tmatch = nil
  }

  /* partyTerms: the ring ruleset for the party's players, the settings' calls; the break passed round (rack % n) */
  private func partyGame(_ k: String) -> Game {
    let P = party!
    var c = CallConfig(); c.mode = Prefs.calls
    var gm = engine.newGame(k, rules: makeRules(k, ruleset: P.ruleset, call: c, players: P.names.count))
    let b = P.rack % P.names.count
    if b > 0 { gm.turn = b; gm.breaker = b }
    handoff = (b, true)
    return gm
  }
  /* Play Again in a party: the rack's winner gets it, the next rack breaks round */
  func partyAgain() {
    if var P = party, let w = g?.winner, w < P.wins.count { P.wins[w] += 1; P.rack += 1; party = P }
    rerack()
  }
  /* the scores the handoff shows: the game's points, else racks won */
  func partyScore(_ p: Int) -> String {
    if let s = g?.score, p < s.count { return "\(s[p]) of \(g!.race!)" }
    let w = party?.wins[p] ?? 0
    return "\(w) rack\(w == 1 ? "" : "s")"
  }

  /* stats.potted: each player's pots (the verdict's potted, their own), for the pause menu's cards */
  @ObservationIgnored private(set) var pottedBy: [[Int]] = [[], [], [], []]
  @ObservationIgnored private var gBefore: Game? = nil

  /* cardOf (page 6b): a player's card in the pause menu, the second line in words and its balls */
  func cardOf(_ p: Int) -> (meta: String, dots: [Int], warn: Bool) {
    guard let gm = g else { return ("", [], false) }
    let on = gm.balls.filter { $0.on && $0.n > 0 }.map { $0.n }
    switch gm.kind {
    case "carom":
      return ("\(p != 0 ? "Yellow" : "White"), \(gm.score![p]) of \(gm.race!)" + (gm.high![p] > 1 ? ", best run \(gm.high![p])" : ""), [C_CUE[p]], false)
    case "straight", "rotation":
      let f = gm.fouls[p], st = gm.kind == "straight"
      return ("\(gm.score![p]) of \(gm.race!)" + (st && gm.high![p] > 1 ? ", best run \(gm.high![p])" : "") + (st && f > 0 ? ", \(f) foul\(f > 1 ? "s" : "") in a row" : ""),
              !st && p == gm.turn && !on.isEmpty ? [on.min()!] : [], st && f >= 2)
    case "snooker":
      let up = p == gm.turn && gm.winner == nil, need = up && engine.snookersNeeded(gm, p), S = gm.snk!
      var dots: [Int] = []
      if up {
        if let f = S.free { dots = S.on == .red ? [41, f] : [f] }
        else { switch S.on { case .red: dots = [41]; case .colour: dots = S_COLS.filter { c in gm.balls.contains { $0.n == c && $0.on } }; case .ball(let b): dots = [b]; case .none: dots = [] } }
      }
      return (Words.ptsWord(gm.score![p]) + (up && S.brk > 0 ? ", break \(S.brk)" : "") + (need ? ", needs snookers" : ""), dots, need)
    case "bumper":
      let mine = on.filter { bOwner($0) == p }.sorted()
      return ("\(Words.colourOf(p)), \(mine.count) left" + (mine.contains(B_MARK[p]) && mine.count > 1 ? ", marked first" : ""), mine, false)
    default:
      if is8(gm.kind) {
        guard let gr = gm.groups[p] else { return ("Open table", [], false) }
        let left = on.filter { engine.groupOf($0) == gr }
        if left.isEmpty { return ("On the 8", on.contains(8) ? [8] : [], false) }
        return (gr.prefix(1).uppercased() + gr.dropFirst(), left, false)
      }
      let f = gm.fouls[p], two = (gm.kind == "9" || gm.kind == "10") && gm.rules.threeFoul != nil && f >= 2, fw = two ? "Two fouls" : f > 0 ? "1 foul" : ""
      if gm.turn == p && gm.winner == nil && !on.isEmpty { return (fw.isEmpty ? "Ball on" : "\(fw), ball on", [on.min()!], f > 0) }
      let pot = pottedBy[p].count
      return (!fw.isEmpty ? fw : pot > 0 ? "\(pot) potted" : "", pottedBy[p], f > 0)
    }
  }
  /* the pause menu's card name: the CPU by its opponent's name (FOES) */
  func cardName(_ p: Int) -> String { cpuLevel != nil && p == 1 ? "\(["easy": "Rookie", "medium": "Regular", "hard": "Hustler"][cpuLevel!] ?? "CPU") (CPU)" : Words.nameOf(p) }
  /* the potted row: the players' pots in pot order, then any other ball off the table */
  var pottedRow: [Int] {
    var out: [Int] = []
    for n in pottedBy.flatMap({ $0 }) where n > 0 && !out.contains(n) { out.append(n) }
    for b in g?.balls ?? [] where !b.on && b.n > 0 && !out.contains(b.n) { out.append(b.n) }
    return out
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

  // MARK: 5c. the called shot

  /* what the player chose by tapping (a ball, then a pocket; Bank, Kick and Combo under custom detail), a declared
     safety, a push-out, and the aim's obvious call switched off by Change Call; cleared every turn (resetCall) */
  var callMan: ShotCall? = nil
  var callSafe = false
  var callPushOn = false
  var callAutoOff = false
  var callMenu = false
  func resetCall() { callMan = nil; callSafe = false; callPushOn = false; callAutoOff = false; callMenu = false }
  var callable: Bool { rolling == nil && stroke == nil && !cpuTurn && g?.winner == nil && g?.option == nil && g?.mode == nil }
  var callOn: Bool {
    guard callable, let gm = g else { return false }
    return engine.callNeed(gm) != nil || (gm.kind == "straight" && gm.breakShot && engine.callScope(gm) != "none")
  }
  var pushOffer: Bool { callable && (g?.pushAvail ?? false) && (g?.rules.pushOut ?? false) }
  /* the obvious shot down the aim line: the legal ball it meets, and the pocket its line runs into with a clear path */
  func obviousCall() -> ShotCall? {
    guard let gm = g, let c = cue else { return nil }
    let dx = JSMath.cos(aim), dy = JSMath.sin(aim), h = sim.aimTrace(balls, c.x, c.y, dx, dy, skip: [c.n], far: 6)
    guard h.kind == "ball", let o = h.ball, engine.legalTargets(gm).contains(o.n) else { return nil }
    let gx = c.x + dx * h.t, gy = c.y + dy * h.t, l0 = JSMath.hypot(o.x - gx, o.y - gy), ul = l0 == 0 ? 1 : l0, ux = (o.x - gx) / ul, uy = (o.y - gy) / ul
    var best = -1, bd = Double.infinity
    let cp = CPU(engine: engine)
    for (k, p) in sim.POCKET_AIM.enumerated() {
      let vx = p[0] - o.x, vy = p[1] - o.y, along = vx * ux + vy * uy, off = abs(vx * uy - vy * ux)
      if along > 0 && off < (k == 1 || k == 4 ? sim.SIDE_W : sim.CORNER_W) * 0.45 && off < bd && cp.cpuClear(gm.balls, o.x, o.y, p[0], p[1], o.n) { best = k; bd = off }
    }
    guard best >= 0 else { return nil }
    var r = ShotCall(); r.ball = o.n; r.pocket = best; r.auto = true
    return r
  }
  /* the declaration the next human shot carries */
  func humanCall() -> ShotCall? {
    if callPushOn && pushOffer { var c = ShotCall(); c.push = true; return c }
    guard callOn, let gm = g else { return nil }
    if callSafe { var c = ShotCall(); c.safety = true; return c }
    let need = engine.callNeed(gm), auto = (need?.auto ?? false) && !callAutoOff ? obviousCall() : nil
    if var c = callMan, c.ball != nil {
      if c.pocket == nil, let a = auto, a.ball == c.ball { c.pocket = a.pocket }
      return c
    }
    return callMan != nil ? nil : auto
  }
  /* the bar may arm: no call needed, or the declaration is whole */
  var callReady: Bool {
    if cpuTurn || rolling != nil { return true }
    if callPushOn && pushOffer { return true }
    guard callOn, let gm = g, let need = engine.callNeed(gm) else { return true }
    guard let c = humanCall() else { return false }
    return c.safety || (c.ball != nil && (!need.pocket || c.pocket != nil))
  }
  var callLocked: Bool { !(g?.rules.call.change ?? true) && callMan?.ball != nil && callMan?.pocket != nil }
  /* a tap on an object ball while a call is open: it is the called ball (the tap still aims) */
  func pickCallBall(_ n: Int) {
    guard callOn, !callLocked else { return }
    callSafe = false
    if callMan == nil || callMan!.ball != n {
      var c = ShotCall(); c.ball = n; c.pocket = callMan != nil && callMan!.ball == nil ? callMan!.pocket : nil; callMan = c
    }
  }
  /* a tap on a pocket: the called pocket (the ball from the aim when none is picked yet) */
  func pickPocket(_ k: Int) {
    guard callOn, !callLocked, let gm = g else { return }
    callSafe = false
    if callMan == nil || callMan!.ball == nil {
      let t = engine.legalTargets(gm)
      var c = ShotCall(); c.ball = obviousCall()?.ball ?? (t.count == 1 ? t[0] : nil); c.pocket = k; callMan = c
    } else { callMan!.pocket = k }
  }
  /* Change Call (or Clear): the aim's call goes, the player taps the ball and the pocket; a safety or push-out is undone */
  func changeCall() {
    guard callable else { return }
    if callPushOn { callPushOn = false; return }
    if callSafe { callSafe = false; return }
    if callLocked { return }
    callMan = ShotCall(); callAutoOff = true
  }
  func toggleFlag(_ f: String) {
    guard callOn, !callLocked else { return }
    if callMan == nil { var c = ShotCall(); if let h = humanCall(), h.ball != nil { c.ball = h.ball; c.pocket = h.pocket }; callMan = c }
    switch f { case "bank": callMan!.bank.toggle(); case "kick": callMan!.kick.toggle(); default: callMan!.combo.toggle() }
  }
  func toggleSafety() { guard callOn else { return }; callSafe.toggle(); callPushOn = false }
  func togglePush() { guard pushOffer else { return }; callPushOn.toggle(); callSafe = false }
  /* a pocket in words as the player sees the table (pocketWords, top-down): "top left corner", "right side" */
  func pocketWords(_ k: Int, upright: Bool) -> String {
    let p = sim.POCKET_AIM[k]
    let f = upright ? p[0] - sim.TL / 2 : sim.TW / 2 - p[1], r = upright ? p[1] - sim.TW / 2 : p[0] - sim.TL / 2
    let e = 0.01, v = f > e ? "top" : f < -e ? "bottom" : "", h = r < -e ? "left" : r > e ? "right" : ""
    return k == 1 || k == 4 ? "\(v.isEmpty ? h : v) side" : "\(v) \(h) corner"
  }
  func pocketShort(_ k: Int, upright: Bool) -> String {
    pocketWords(k, upright: upright).replacingOccurrences(of: " corner", with: "").split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
  }
  /* callLab: the bar's label for the call, or nil when the bar says its own words */
  func callLab(upright: Bool) -> String? {
    guard callOn || pushOffer, let c = humanCall() else { return nil }
    if c.push { return "Push Out" }
    if c.safety { return "Safety" }
    guard let b = c.ball else { return nil }
    let fl = [("Bank", c.bank), ("Kick", c.kick), ("Combo", c.combo)].filter { $0.1 }.map { $0.0 }.joined(separator: ", ")
    let need = g.flatMap { engine.callNeed($0) }
    let body = c.pocket != nil ? "\(b) · \(pocketShort(c.pocket!, upright: upright))" : need?.pocket == true ? "\(b) · Tap a Pocket" : String(b)
    return (fl.isEmpty ? "" : fl + ": ") + body
  }
  var callMenuOffered: Bool { callOn || pushOffer }
  /* the table is drawn upright (a phone held upright): the call's pocket words follow the screen */
  var uprightView = true

  /* pickBall: bumper pool, strike ball n from now on (one of the shooter's, any but on the opening) */
  func pickBall(_ n: Int) -> Bool {
    guard var gm = g, gm.kind == "bumper", engine.bumperStrikers(gm).contains(n), rolling == nil, stroke == nil, !cpuTurn else { return false }
    if gm.striker != n { gm.striker = n; g = gm; syncBalls(); picked = true; aimAtNearest() }
    return true
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
    let P = sim.previewStart(balls, cueN: cueN, aim, pw, spin, h, game == .carom ? PV_CAROM : Prefs.guide == "short" ? PV_SHORT : PV_FULL, caromNeed: game == .carom ? (g?.need ?? 3) : 0)
    sim.previewRun(P)
    pvKey = key; pvVal = (h, P)
    return (h, P)
  }
}
