/* One table at play: the sim (FeltSim, index.html's physics bit for bit), the balls at rest, the
   roll in progress and the player's aim, power and english. The pocket games (8, 9, 10, Chinese
   8-ball) are played under their default rules by FeltSim's RulesEngine (sim 1e, the page's judge),
   two players on one device; snooker and carom are still the free practice table until their rule
   modules are ported. The roll steps exactly as the page's frame() does: dtMs / 1000 / SIM_DT steps
   a frame, the fraction carried to the next. */
import Accessibility
import Foundation
import CoreGraphics
import FeltRender
import FeltSim
import Observation
import QuartzCore

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
  /* #elevPop: the cue elevation sheet, opened by a hold on the pad; spinOk: the player's turn to aim */
  var elevOpen = false { didSet { if elevOpen { hideElevTip() } } }
  /* the elevation tip (5s, #elevTip): the first jump or masse challenge ever opened says where the raised cue is (the
     pad's hold), in a card by the pad, once. It goes on Got It, when the elevation sheet opens, or once the turn is not
     the player's to aim; seen persists under ELEV_TIP_KEY ({ v: 1, seen }) the moment it shows, so it never shows again */
  static let ELEV_TIP_KEY = "felt.elevTip.v1"
  static let ELEV_TIP_HEAD = "Raise the Cue", ELEV_TIP_TEXT = "Hold the english pad, or right click it, to raise the cue. Slide it up: high and firm jumps, high with side curves."
  private(set) var elevTip = false
  @ObservationIgnored private var elevTipSeen = TableModel.loadElevTip()
  @ObservationIgnored private(set) var elevTipShows = 0
  static func loadElevTip() -> Bool { guard let o = TrickStore.json(ELEV_TIP_KEY) as? [String: Any] else { return false }; return TrickStore.int(o["v"]) == 1 && (o["seen"] as? Bool) == true }
  @discardableResult func showElevTip() -> Bool {
    if elevTipSeen || !spinOk { return false }
    elevTipSeen = true
    TrickStore.put(TableModel.ELEV_TIP_KEY, ["v": 1, "seen": true])
    elevTip = true; elevTipShows += 1
    msg = TableModel.ELEV_TIP_TEXT
    return true
  }
  func hideElevTip() { if elevTip { elevTip = false } }
  var spinOk: Bool { rolling == nil && stroke == nil && !cpuTurn && trickRes == nil && !drillBlocked && (g?.winner == nil) }
  /* setElev: whole degrees 0 to 60 on spin.e (radians) */
  func setElev(_ deg: Double) { spin = spinOf(x: spin.x, y: spin.y, e: max(0, min(60, deg.rounded())) * Double.pi / 180) }
  var elevDeg: Int { Int((spin.e * 180 / Double.pi).rounded()) }
  private(set) var inHand = false
  private(set) var potCount = 0
  @ObservationIgnored private var carry = 0.0
  @ObservationIgnored private var lastT: TimeInterval?
  @ObservationIgnored private var heard = 0
  @ObservationIgnored let sound = Sound.shared
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
  /* start()'s table for a game from the settings (every pool game on its size and pockets; snooker's size; bumper's shape) */
  nonisolated static func spec(for game: TableGame) -> (table: String, shape: String?, pockets: String) {
    switch game {
    case .eight, .nine, .ten, .straight, .rotation: (Prefs.table, nil, Prefs.pockets)
    case .snooker: ("snooker", Prefs.snookerTable, Prefs.pockets)
    case .bumper: ("bumper", Prefs.bumperTable, Prefs.pockets)
    default: (game.table.0, game.table.1, Prefs.pockets)
    }
  }
  nonisolated static func setUp(_ sim: Sim, _ spec: (table: String, shape: String?, pockets: String)) {
    if spec.table == "bumper" { sim.setTable("7") }
    sim.setPockets(spec.pockets)
    sim.setTable(spec.table, spec.shape)
    Mapper.note(sim)
  }
  struct Baked { let image: CGImage; let size: CGSize; let scale: CGFloat }
  private(set) var tableImage: Baked?
  @ObservationIgnored private var baking: CGSize?
  /* the stage's size, for placing the coach card (placeCoach) */
  var stageSize = CGSize.zero
  func bake(_ size: CGSize, scale: CGFloat) {
    if stageSize != size { stageSize = size }
    guard size.width > 0, size.height > 0, tableImage?.size != size, baking != size else { return }
    baking = size
    let look = dress, spec = spec
    let ext = Mapper.current
    Task.detached(priority: .userInitiated) {
      let sim = Sim(); TableModel.setUp(sim, spec)
      let m = Mapper(size: size, TL: sim.TL, TW: sim.TW, ext: ext)
      let p = TablePainter(sim: sim, view: m.view, dpr: Double(scale), rail: m.rail, look: TableLook.of(look), pageColor: "rgb(9, 9, 10)")
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
  /* dotEl: a little ball for a sheet (the table's own painter, so it is the ball on the cloth), d pt across */
  func ballIcon(_ n: Int, _ d: Double) -> (CGImage, CGFloat) {
    let sc = scaleFactor, bp = ballPainter(upright: true, scale: sc), r = d / 2 * sc
    let (img, _, _) = bp.ballImage(n, r * 1.6, r * 1.6, r, bp.axesOf(IDENT, screen: true))
    return (img, sc)
  }
  func ballPainter(upright: Bool, scale: CGFloat) -> BallPainter {
    if let p = painter, p.1 == upright, p.2 == scale, p.0.marks == Prefs.bool("marks", false) { return p.0 }
    let look = TableLook.of(dress), cloth = RGBA(css: look.cloth.base)
    let p = BallPainter(set: BallSet.all[dress.balls] ?? BallSet.all["classic"]!, bounce: look.cloth.bounce, dpr: Double(scale), portrait: upright,
                        lowRim: look.cloth.lowRim, rimAll: look.cloth.rim, clothBase: [cloth.r * 255, cloth.g * 255, cloth.b * 255])
    p.marks = Prefs.bool("marks", false)
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
  var shown: [Ball] { rp?.tab.balls ?? rolling?.balls ?? balls }

  /* 5r, the shot replay: every shot recorded as it is struck (shotRecord); at rest a Replay pill offered for
     REPLAY_OFFER_MS (REPLAY_NOTABLE_MS, gold, when notableOf finds the shot's moment); a tap plays it again in its own table
     (rp.tab, drawn instead of the live one): the cue's run-up (REPLAY_LEAD), real speed slowed to REPLAY_SLOW round the
     first contact and the first object ball's drop. The live game holds still (the CPU waits) until it ends; any touch
     ends it */
  struct ShotRec { let balls: [Ball], angle: Double, power: Double, spin: Spin, ball: Int, g: Game?, orient: [Int: Mat3], id: Int }
  struct Replay { let rec: ShotRec, tab: Tab; var lead: Double, struck = false, acc = 0.0, hold = 0.0, end = false, shotAt = 0.0, camT: Double; let moments: [Double], keepOrient: [Int: Mat3], keepPots: [Pot], keepFx: [Fx], plan: Cam.Plan }
  static let REPLAY_OFFER_MS = 3.5, REPLAY_NOTABLE_MS = 6.5, REPLAY_LEAD = 0.5, REPLAY_SLOW = 0.35, SLOW_IN = 0.09, SLOW_OUT = 0.12, SLOW_RAMP = 0.06
  @ObservationIgnored var lastShot: ShotRec? = nil
  @ObservationIgnored private var shotN = 0
  private(set) var offer: (notable: String?, until: TimeInterval)? = nil
  private(set) var rp: Replay? = nil
  func hideOffer() { if offer != nil { offer = nil } }
  /* notableOf: the shot's best notable moment, by shotMoments on the game as it stood */
  private func notableOf(_ res: ShotResult, _ rec: ShotRec) -> String? {
    guard let g0 = rec.g else { return nil }
    return engine.shotMoments(g0, res, engine.judge(g0, RuleShot(res))).keys.first { NOTABLE_MOMENTS.contains($0) }
  }
  /* offerReplay: the balls at rest after a shot, on a turn to aim or the CPU's think (state aim or thinking: never with a
     choice the rules give on the table, never in the lesson or a tutorial, or over a result) */
  private func offerReplay(_ res: ShotResult) {
    guard let rec = lastShot, lesson == nil, tut == nil, trickRes == nil, drillRes == nil, g?.winner == nil, g?.option == nil, Prefs.bool("replays", true) else { return }
    let nb = notableOf(res, rec)
    offer = (nb, now + (nb != nil ? TableModel.REPLAY_NOTABLE_MS : TableModel.REPLAY_OFFER_MS))
  }
  private static func ease(_ a: Double, _ b: Double, _ u: Double) -> Double { let t = min(1, max(0, (u - a) / (b - a))); return t * t * (3 - 2 * t) }
  /* startReplay: the record's whole roll (its prediction, camPredict, run to the end): the moments (the first contact,
     the first object ball's drop) and the camera's plan in close (CAM_REPLAY) on the cue ball and the first ball it hits */
  func startReplay() {
    guard rp == nil, let rec = lastShot, rolling == nil, stroke == nil, g?.option == nil else { return }
    hideOffer(); aimLock = .free
    let P = camPred.flatMap { $0.id == rec.id ? $0 : nil } ?? Cam.predict(sim, id: rec.id, balls: rec.balls, ball: rec.ball, angle: rec.angle, power: rec.power, spin: rec.spin)
    while !Cam.step(sim, P, 1) {}
    let tr = P.tr, ci = rec.balls.firstIndex { $0.n == rec.ball } ?? -1, oi = tr.first.flatMap { f in rec.balls.firstIndex { $0.n == f.n } } ?? -1
    let drop = tr.pots.first { $0.n != rec.ball }, moments = [tr.first?.t, drop?.t].compactMap { $0 }
    let plan = Cam.plan(tr, Cam.REPLAY, rec.balls.indices.map { $0 == ci || $0 == oi }, lead: TableModel.REPLAY_LEAD, TL: sim.TL, TW: sim.TW, RAIL: camRail, POCKETS: sim.POCKETS)
    rp = Replay(rec: rec, tab: sim.newTable(rec.balls.map { $0.copy() }, cue: rec.ball), lead: -TableModel.REPLAY_LEAD, camT: -TableModel.REPLAY_LEAD, moments: moments, keepOrient: orient, keepPots: pots, keepFx: effects, plan: plan)
    orient = rec.orient; pots = []; effects = []
    sound.replaying = true
  }
  /* endReplay: the live table back exactly as it was: the balls' turn, the live drops and the hit flashes (rp.keep) */
  func endReplay() {
    guard let R = rp else { return }
    rp = nil; orient = R.keepOrient; pots = R.keepPots; effects = R.keepFx
    sound.replaying = false
  }
  private func replayRate(_ t: Double) -> Double {
    var w = 0.0
    for m in rp?.moments ?? [] { let d = t - m; w = max(w, d < -TableModel.SLOW_IN ? TableModel.ease(-TableModel.SLOW_IN - TableModel.SLOW_RAMP, -TableModel.SLOW_IN, d) : 1 - TableModel.ease(TableModel.SLOW_OUT, TableModel.SLOW_OUT + TableModel.SLOW_RAMP, d)) }
    return 1 - (1 - TableModel.REPLAY_SLOW) * w
  }
  var replaySlow: Bool { guard let R = rp, R.struck, !R.end else { return false }; return replayRate(R.tab.t) < 0.9 }
  /* replayStep: one frame of replay, instead of the live roll */
  private func replayStep(_ now: TimeInterval) {
    guard var R = rp else { return }
    let dt = min(0.05, max(0, lastT.map { now - $0 } ?? 1.0 / 60)) * speed
    lastT = now
    var s = 0.0
    if !R.struck {
      R.lead += dt
      if R.lead >= 0 { s = R.lead; R.lead = 0; R.struck = true; R.shotAt = now; sim.strike(R.tab, R.rec.angle, R.rec.power, R.rec.spin) }
    } else { s = dt }
    if R.struck && !R.end {
      R.acc += s * replayRate(R.tab.t) / SIM_DT
      let n = Int(R.acc), before = R.tab.balls.map { ($0.x, $0.y, $0.on) }
      R.acc -= Double(n)
      var live = true, k = 0
      let h0 = R.tab.hits.count
      while k < n && live { live = sim.stepTable(R.tab); k += 1 }
      for h in R.tab.hits[h0...] { sound.hit(h) }
      for (i, b) in R.tab.balls.enumerated() where before[i].2 {
        let dx = b.x - before[i].0, dy = b.y - before[i].1, d = JSMath.hypot(dx, dy)
        if d > 0 && d < 0.5 { orient[b.n] = rotate(orient[b.n] ?? IDENT, [-dy, dx, 0], d / sim.BALL_R) }
        if !b.on { onPot(b.n, R.tab.pocketOf[b.n] ?? -1, (before[i].0, before[i].1), now) }
      }
      if !live { R.end = true }
    } else if R.end { R.hold += dt }
    R.camT = R.struck ? R.tab.t + R.hold : R.lead
    rp = R
    if R.end && (R.hold >= 1.5 || (R.hold >= 0.4 && abs(cam.z - 1) < 0.01)) { endReplay() }
  }
  /* 3b, the camera (Camera.swift): its state, and the prediction of the shot last struck (camPred) */
  @ObservationIgnored private(set) var cam = (z: 1.0, x: 0.0, y: 0.0, vz: 0.0, vx: 0.0, vy: 0.0)
  @ObservationIgnored private var camPred: Cam.Pred?
  @ObservationIgnored private var camLast: TimeInterval?
  /* the view's rail (RAIL), for camPlan's framing */
  private var camRail: Double { Mapper(size: stageSize, TL: sim.TL, TW: sim.TW).rail }
  /* the fitted view under the camera (camView) */
  func camView(_ m: Mapper) -> Mapper { m.cam(cam.z, cam.x, cam.y) }
  /* camStep: once a frame, the camera toward where the shot, the replay or the turn wants it. The prediction is stepped
     only with Follow on (the replay finishes one itself), so Fixed costs the frame nothing */
  private func camStep(_ now: TimeInterval) {
    let dtMs = min(50, max(0, (now - (camLast ?? now)) * 1000))
    camLast = now
    let follow = Prefs.camera == "auto"
    if follow, let P = camPred, !P.done { Cam.step(sim, P, 0.004) }
    if let P = camPred, P.done, P.plan == nil { P.plan = Cam.plan(P.tr, Cam.LIVE, nil, TL: sim.TL, TW: sim.TW, RAIL: camRail, POCKETS: sim.POCKETS) }
    var want: [Double]? = nil
    if !follow { want = nil }
    else if let R = rp { want = Cam.at(R.plan, R.camT) }
    else if let tab = rolling, let P = camPred, let pl = P.plan, P.id == lastShot?.id { want = Cam.at(pl, tab.t) }
    else if rolling != nil || stroke != nil { want = [1, cam.x, cam.y] }
    if want == nil {
      /* off, or a turn: z = 1 (what is left after a shot's tail is under 3%: let it go) */
      if !follow || abs(cam.z - 1) < 0.03 { cam = (1, cam.x, cam.y, 0, 0, 0); return }
      want = [1, cam.x, cam.y]
    }
    let w = want!, dt = min(50, dtMs) / 1000 * speed, W = rp != nil ? Cam.W * 1.2 : Cam.W
    (cam.z, cam.vz) = Cam.spring(cam.z, cam.vz, w[0], W, dt)
    (cam.x, cam.vx) = Cam.spring(cam.x, cam.vx, w[1], W, dt)
    (cam.y, cam.vy) = Cam.spring(cam.y, cam.vy, w[2], W, dt)
    if cam.z < 1 { cam.z = 1; cam.vz = max(0, cam.vz) }
    if w[0] == 1 && abs(cam.z - 1) < 1e-4 && abs(cam.vz) < 1e-3 { cam.z = 1; cam.vz = 0 }
  }
  /* the cue in a replay: at address, drawn back by the power, through the ball, then the follow-through fade */
  var replayCue: (x: Double, y: Double, ang: Double, gap: Double, alpha: Double)? {
    guard let R = rp, let c = R.rec.balls.first(where: { $0.n == R.rec.ball }), c.on else { return nil }
    let rest = sim.BALL_R + 0.012, sS = TableModel.STROKE_MS, BR = sim.BALL_R
    if !R.struck {
      let g0 = rest + 0.27 * min(1, max(0, R.rec.power)), u = R.lead + TableModel.REPLAY_LEAD
      let gap = R.lead < -sS ? rest + (g0 - rest) * TableModel.ease(0.05, TableModel.REPLAY_LEAD - sS - 0.04, u) : g0 + (BR - g0) * pow((R.lead + sS) / sS, 2)
      return (c.x, c.y, R.rec.angle, gap, TableModel.ease(0, 0.12, u))
    }
    let u = (now - R.shotAt) / (0.18 / speed)
    return u < 1 ? (c.x, c.y, R.rec.angle, BR - 0.035 * TableModel.ease(0, 1, u * 2), 1 - u) : nil
  }
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
  struct TMatch { let m: Int, foe: String, level: String, arch: String?, need: Int, points: Bool, race: Int, lag: Int, ruleset: String; var score = [0, 0], rack = 1, done = false, counted = false
    /* a career match (careerTerms): its event's calls and table, the event's own words */
    var call: CallConfig? = nil, spec: (table: String, shape: String?, pockets: String)? = nil, career = false, dress: Dress? = nil
    /* Career.assist() when simulation purity is off (nil when on), the execution jitter's seed, the shots it has drawn */
    var assist: JV? = nil, execSeed: UInt32 = 0, shot = 0 }
  private(set) var tmatch: TMatch?
  /* settleSolo's trick shot: judged, the tries, the old stars and the program's run (TRICK_RUN attempts: full value on
     the first, minus 1, minus 2), then the result sheet */
  private func settleTrick(_ before: Game, _ r: ShotResult) {
    guard var T = trick, let c = trickById(T.id) else { return }
    let j = engine.trickJudge(c, r)
    var gm = before; gm.balls = r.balls.map { b -> GBall in var x = GBall(n: b.n, x: b.x, y: b.y); x.on = b.on; return x }; gm.shots += 1
    g = gm; rolling = nil; spin = Spin(); v3Top2d = false; syncBalls(); inHand = false
    if !T.demo {
      T.attempts += 1
      var tries = TrickStore.tries; tries[c.id] = max(tries[c.id] ?? 0, T.attempts); TrickStore.tries = tries
      if j.ok {
        T.stars = trickStars(T.attempts)
        var best = TrickStore.best; if T.stars > (best[c.id] ?? 0) { best[c.id] = T.stars; TrickStore.best = best }
      }
      let val = T.daily == nil ? trickVal(c.id) : 0
      T.got = 0; T.runOver = false; T.runTry = 0
      /* a make on the day's counted try is remembered */
      if let d = T.daily, d.live, j.ok { var R = DailyStore.rec; if !R.made { R.made = true; DailyStore.rec = R } }
      if val > 0 {
        var sc = TrickStore.score
        let n = (sc.run[c.id] ?? 0) + 1; T.runTry = n
        if j.ok { T.got = trickPts(val, n); sc.pts[c.id] = max(sc.pts[c.id] ?? 0, T.got); sc.run[c.id] = nil }
        else if n >= TRICK_RUN { T.runOver = true; sc.run[c.id] = nil }
        else { sc.run[c.id] = n }
        TrickStore.score = sc
      }
    }
    trick = T
    /* showTrickRes: the head, the words (a run's attempt and points, or the stars by try), the score now */
    let i = TRICKS.firstIndex { $0.id == c.id } ?? 0, val = T.daily == nil ? trickVal(c.id) : 0, n = T.runTry, a = T.attempts
    let why: String
    if T.demo { why = j.ok ? "One way to make it. Your turn." : j.why }
    else if val > 0 {
      let best = TrickStore.score.pts[c.id] ?? 0
      why = j.ok ? "\(n == 1 ? "First attempt" : "Attempt \(n)") of this run: \(T.got) point\(T.got == 1 ? "" : "s"). Best: \(best) of \(val)."
        : T.runOver ? "\(j.why) Run over, no points. Try again for a new run: full value on the first attempt." : "\(j.why) Attempt \(n) of \(TRICK_RUN): the next make scores \(trickPts(val, n + 1))."
    } else {
      let best = TrickStore.best[c.id] ?? 0
      why = j.ok ? "\(a == 1 ? "First try" : "On try \(a)"): \(T.stars) star\(T.stars == 1 ? "" : "s")." + (best > T.stars ? " Best: \(best)." : "") : "\(j.why) Tries: \(a)."
    }
    /* the daily shot says what the try did for the streak: the first counts, the rest are practice */
    var dayWords = ""
    if let d = T.daily, !T.demo {
      let R = DailyStore.rec
      dayWords = d.live ? " Day streak: \(R.streak)\(R.streak == R.best && R.best > 1 ? ", your best" : "")." : " Practice: today's try is in."
    }
    let pts = val > 0 ? (j.ok && !T.demo && T.got > 0 ? "\(T.got) of \(val)" : "") : (j.ok && !T.demo ? String(repeating: "★", count: T.stars) + String(repeating: "☆", count: 3 - T.stars) : "")
    trickRes = TrickRes(ok: j.ok, why: why + dayWords, head: T.demo ? (j.ok ? "Like that" : "Close") : j.ok ? "Made it" : "Not quite",
                        kind: T.daily.map { "Daily shot, \(DrillStore.dayWords($0.day)): \(c.title)" } ?? "Trick shot \(i + 1) of \(TRICKS.count): \(c.title)", pts: pts, demo: T.demo, i: i, daily: T.daily != nil)
    msg = why
    sound.cue(j.ok ? "win" : "foul")
  }
  /* placeCoach, simplified: the card at the stage's top or foot, whichever is further from the marks it must not hide (the
     cue ball, the ball and pocket to play, the line between them) */
  var coachAtTop: Bool {
    guard stageSize.height > 0, let c = cue else { return true }
    let m = Mapper(size: stageSize, TL: sim.TL, TW: sim.TW)
    var pts: [[Double]] = [[c.x, c.y]]
    if lesson != nil { let P = lessonPoints(); pts += [P.b, sim.POCKETS[TableModel.LESSON_POCKET]] }
    if let T = tut, let t = tutById(T.id) {
      let st = t.steps[T.step]
      if let n = tutNum(t, T.step, T.ctx, st.aim), let b = balls.first(where: { $0.n == n && $0.on }) { pts.append([b.x, b.y]) }
      if let k = st.pocket, k < sim.POCKETS.count { pts.append(sim.POCKETS[k]) }
      if let r = tutRing, r.kind == "ball", let b = balls.first(where: { $0.n == r.n && $0.on }) { pts.append([b.x, b.y]) }
    }
    var line = pts; for p in pts.dropFirst() { line.append([(c.x + p[0]) / 2, (c.y + p[1]) / 2]) }
    let ys = line.map { Double(m.pt($0[0], $0[1]).y) }, H = Double(stageSize.height), band = min(220, H * 0.3)
    let top = ys.filter { $0 < band }.count, foot = ys.filter { $0 > H - band }.count
    return top <= foot
  }
  /* lessonPoints: the 1 six radii in from the pocket's mouth, the cue ball sixteen behind it on the same line */
  func lessonPoints() -> (b: [Double], c: [Double], line: Double) {
    let k = TableModel.LESSON_POCKET, n = sim.CPU_MOUTH_N[k], A = sim.POCKET_AIM[k], R = sim.BALL_R
    let b = [A[0] + n[0] * 6 * R, A[1] + n[1] * 6 * R], c = [b[0] + n[0] * 16 * R, b[1] + n[1] * 16 * R]
    return (b, c, atan2(b[1] - c[1], b[0] - c[0]))
  }
  private func lessonGame() -> Game {
    let P = lessonPoints()
    var g = engine.newGame("8")
    g.mode = "practice"; g.layout = "lesson"; g.seed = 0; g.hand = false; g.breakShot = false; g.inHand = nil
    g.balls = [GBall(n: 0, x: P.c[0], y: P.c[1]), GBall(n: 1, x: P.b[0], y: P.b[1])]
    return g
  }
  /* the aim a step starts on: well off the line for step 1, on it after that */
  private func lessonAim() { aim = lessonPoints().line + (lesson?.step == 1 ? 0.6 : 0) }
  private func lessonStep(_ n: Int) { lesson?.step = n; lesson?.again = false; if n == 2 { lesson?.a0 = aim; lesson?.wheel = false } }
  /* each frame of the lesson: has the step been done? */
  private func lessonCheck() {
    guard let s = lesson, rolling == nil, stroke == nil, !lessonDone else { return }
    let w = { (a: Double) in atan2(sin(a), cos(a)) }
    if s.step == 1 && !touching && !fineAim && abs(w(aim - lessonPoints().line)) <= TableModel.LESSON_TOL { lessonStep(2) }
    else if s.step == 2 && s.wheel && !fineAim && abs(w(aim - s.a0)) > 1e-5 { lessonStep(3) }
  }
  func lessonWheel() { if lesson != nil { lesson?.wheel = true } }
  /* lessonSettle: the 1 down finishes, else the balls go back */
  private func settleLesson(_ r: ShotResult) {
    rolling = nil; spin = Spin(); v3Top2d = false
    if r.potted.contains(1) {
      var gm = g!; gm.balls = r.balls.map { b -> GBall in var x = GBall(n: b.n, x: b.x, y: b.y); x.on = b.on; return x }; g = gm; syncBalls()
      LessonStore.rec = (true, true); lessonDone = true; sound.cue("win")
      return
    }
    g = lessonGame(); syncBalls(); lessonAim()
    lesson?.again = true
    if lesson?.step == 2 { lesson?.a0 = aim }
  }
  /* tutBegin: step i on the tutorial's table: the layout, a fresh turn, the step's flash, the hint's aim */
  func tutBegin(_ i: Int) {
    guard var T = tut, let t = tutById(T.id) else { return }
    T.step = i; T.again = false; T.why = ""; T.then = false; T.demo = false
    g = engine.tutGame(t, i, T.ctx); trickRes = nil; tutDone = false
    syncBalls(); spin = Spin(); power = 0; picked = false
    T.cue0 = cue.map { [$0.x, $0.y] }; tut = T
    let st = t.steps[i]
    if let f = st.flash { flashDue = (f[0], f[1], 1.8) }
    randomOrient(); tutAim()
    msg = "\(t.name), step \(i + 1) of \(t.steps.count): \(st.head). " + st.text(T.ctx ?? "solids")
  }
  /* tutHint's aim: the step's ball (bumper pool: the striker at the far cup); a system shot at its mark on the rail */
  private func tutAim() {
    guard let T = tut, let t = tutById(T.id), let gm = g else { return }
    let st = t.steps[T.step]
    if st.ring(gm, false).kind == "rail", let q = tutRail(), let c = cue { aim = atan2(q[1] - c.y, q[0] - c.x); return }
    if gm.kind == "bumper" {
      if let b = gm.balls.first(where: { $0.n == gm.striker && $0.on }), let k = st.pocket, k < sim.POCKETS.count { aim = atan2(sim.POCKETS[k][1] - b.y, sim.POCKETS[k][0] - b.x) }
      return
    }
    guard let n = tutNum(t, T.step, T.ctx, st.aim), let b = gm.balls.first(where: { $0.n == n && $0.on }), let c = cue else { aimAtNearest(); return }
    aim = atan2(b.y - c.y, b.x - c.x)
  }
  /* tutRail: where the stored solution's line first meets a cushion, out on the rail by the diamonds */
  func tutRail() -> [Double]? {
    guard let T = tut, let sol = tutSol(T.id, T.step), let c = cue else { return nil }
    var sh = sol.shot; sh.ball = c.n
    let r = sim.simulateShot(balls.map { $0.copy() }, sh)
    guard let p = r.railAt[c.n] else { return nil }
    let d = [p[0], sim.TL - p[0], p[1], sim.TW - p[1]], m = d.firstIndex(of: d.min()!)!, out = sim.BALL_R + 0.035
    return [p[0] + (m == 0 ? -out : m == 1 ? out : 0), p[1] + (m == 2 ? -out : m == 3 ? out : 0)]
  }
  /* tutSettle: a miss puts the step back with why; a make moves on (a result to show first, then Next), the step that
     chose 8-ball's group keeping it */
  private func settleTut(_ before: Game, _ shot: RuleShot) {
    guard var T = tut, let t = tutById(T.id) else { return }
    let st = t.steps[T.step], j = engine.tutJudge(t, T.step, before, shot), v = j.n.verdict
    T.demo = false; rolling = nil; spin = Spin(); v3Top2d = false
    if !j.ok {
      g = engine.tutGame(t, T.step, T.ctx); syncBalls()
      T.again = true; T.why = j.why; T.cue0 = cue.map { [$0.x, $0.y] }; tut = T
      if let f = v?.foul { flashDue = ("Foul: \(f)", "The balls go back", 1.5); sound.cue("foul") }
      msg = "Close. Try again. \(j.why) " + st.text(T.ctx ?? "solids"); tutAim()
      return
    }
    if T.ctx != nil, v?.grouped == true, let gr = j.n.groups[0] { T.ctx = gr }
    var n = j.n; for k in n.balls.indices { n.balls[k].vx = 0; n.balls[k].vy = 0; n.balls[k].wx = 0; n.balls[k].wy = 0; n.balls[k].wz = 0 }
    g = n; syncBalls(); tut = T
    if let th = st.then { T.then = true; T.again = false; tut = T; sound.cue("turn"); msg = th.text(); return }
    tutNext(st.done?(j.n))
  }
  func tutNext(_ words: [String]?) {
    guard let T = tut, let t = tutById(T.id) else { return }
    if T.step + 1 >= t.steps.count {
      var r = TutStore.rec; r.done.insert(t.id); TutStore.rec = r
      tutDone = true; sound.cue("win"); msg = "Tutorial complete. That's \(t.name)."
      return
    }
    tutBegin(T.step + 1)
    if let w = words, t.steps[T.step + 1].flash == nil { flashDue = (w[0], w[1], 1.5) }
    sound.cue("point")
  }
  /* the coach's button: Show me (the stored solution from the step's layout, placed first in hand, the ball to strike
     picked in bumper pool), or Next after a result shown */
  func tutShowMe() {
    guard var T = tut, let t = tutById(T.id) else { return }
    if T.then { tutNext(nil); return }
    guard let sol = tutSol(T.id, T.step), rolling == nil, stroke == nil else { return }
    var gm = engine.tutGame(t, T.step, T.ctx)
    if let p = sol.place { gm = engine.placeCue(gm, p[0], p[1]) }
    if let b = sol.ball { gm.striker = b; picked = true }
    g = gm; syncBalls()
    T.demo = true; tut = T
    aim = sol.shot.angle; spin = sol.shot.spin; power = sol.shot.power
    flashDue = ("Show me", "One way to do it", 1.1)
    shoot()
  }
  /* the ring the coach shows now (tutMarks) */
  var tutRing: TutRing? {
    guard let T = tut, let t = tutById(T.id), let gm = g, !tutDone else { return nil }
    let st = t.steps[T.step]
    if T.then { return st.then?.ring(gm) }
    let moved = cue.map { c in T.cue0.map { JSMath.hypot(c.x - $0[0], c.y - $0[1]) > 1e-4 } ?? false } ?? false
    var r = st.ring(gm, moved)
    if r.kind == "ball" { r.n = tutNum(t, T.step, T.ctx, r.n) ?? r.n }
    return r
  }
  /* drillSettle: the shot judged, its flash, then after DRILL_BEAT the next layout or the result */
  private func settleDrill(_ before: Game, _ r: ShotResult) {
    guard var D = drill, let d = drillById(D.id), let S = D.S else { return }
    let j = engine.drillJudge(d, S, r)
    D.js.append(j); D.beat = true; drill = D
    var gm = before; gm.balls = r.balls.map { b -> GBall in var x = GBall(n: b.n, x: b.x, y: b.y); x.on = b.on; return x }; gm.shots += 1
    g = gm; rolling = nil; spin = Spin(); v3Top2d = false; syncBalls(); inHand = false
    sound.cue(j.s >= 50 ? "win" : "foul")
    flashDue = ("Shot \(D.i + 1) of \(d.shots): \(j.s)", j.why, max(1.2, TableModel.DRILL_BEAT + 0.6)); msg = "\(j.why) Shot \(D.i + 1): \(j.s)."
    let balls = r.balls
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(TableModel.DRILL_BEAT))
      guard let self, var D = self.drill, D.id == d.id, D.beat else { return }
      D.beat = false
      if drillOver(d, D.js) { self.drill = D; self.drillFinish(d); return }
      D.i += 1; D.S = self.engine.drillShot(d, D.i, balls); self.drill = D
      self.g = self.engine.drillGame(d, D.i, balls); self.syncBalls(); self.aimAtNearest()
      self.msg = "Shot \(D.i + 1) of \(d.shots). \(D.S!.say)"
    }
  }
  /* drillFinish: the score into the record (best, plays, the last DRILL_HIST with their days), the result */
  private func drillFinish(_ d: Drill) {
    guard let D = drill else { return }
    let total = drillTotal(d, D.js)
    var all = DrillStore.all
    let was = all[d.id]?.best
    var rec = all[d.id] ?? DrillRec(best: 0, n: 0, hist: [])
    rec.n += 1; rec.best = max(rec.best, total); rec.hist.append((total, Rec.today()))
    if rec.hist.count > DrillStore.HIST { rec.hist.removeFirst(rec.hist.count - DrillStore.HIST) }
    all[d.id] = rec; DrillStore.all = all
    drillRes = DrillResult(total: total, was: was, tier: drillTier(d, total), career: onDrillDone?(d.id, total))
    sound.cue(drillTier(d, total) > 0 ? "win" : "foul")
  }
  func startDrill(_ id: String) { guard drillById(id) != nil else { return }; drill = DrillSession(id: id); rerack() }
  var drillBlocked: Bool { drill?.beat == true || drillRes != nil }
  /* startTrick again (Try Again), or another (Next) */
  func startTrick(_ id: String) {
    guard let c = trickById(id) else { return }
    let daily = trick?.id == c.id ? trick?.daily : nil
    trick = TrickSession(id: c.id, attempts: trick?.id == c.id ? trick!.attempts : (TrickStore.tries[c.id] ?? 0))
    if let d = daily { trick!.daily = (d.day, !DailyStore.done(d.day), false, false) }
    rerack()
    if let d = trick?.daily, let c = trickById(trick!.id) { flashDue = ("Daily shot: \(c.title)", d.scored ? c.goal : "\(c.goal) Practice: today's try is in.", 2.4) }
  }
  /* startDaily: today's shot, its first try scored for the streak */
  func startDaily() {
    let day = Rec.today(), c = dailyTrick(day)
    trick = TrickSession(id: c.id, attempts: TrickStore.tries[c.id] ?? 0)
    trick!.daily = (day, !DailyStore.done(day), false, false)
    rerack()
    flashDue = ("Daily shot: \(c.title)", trick!.daily!.scored ? c.goal : "\(c.goal) Practice: today's try is in.", 2.4)
  }
  /* scoreDaily: the day's scored try counts as it is struck (quitting mid-roll cannot throw it away); the streak moves
     once a day, a clock gone back starts a new one */
  private func scoreDaily() {
    guard var T = trick, var d = T.daily, d.scored, !T.demo else { return }
    let was = d.counted
    d.scored = false
    var R = DailyStore.rec
    let gap = R.last.map { dayNum(d.day) - dayNum($0) } ?? Int.max
    if gap != 0 {
      R.streak = gap == 1 ? R.streak + 1 : 1; R.best = max(R.best, R.streak); R.last = d.day; R.made = false
      d.counted = true; DailyStore.rec = R
    }
    d.live = !was && d.counted
    T.daily = d; trick = T
  }
  /* showMe: the layout again and the stored solution played as a shot (not an attempt) */
  func showMe() {
    guard let T = trick, let c = trickById(T.id), let sol = engine.trickSol(c) else { return }
    startTrick(c.id)
    trick?.demo = true
    flashDue = ("Show me", "One way to make it", 1.1)
    aim = sol.angle; spin = sol.spin; power = sol.power
    shoot()
  }
  /* concedeFrame: the player to shoot (you, against the CPU) concedes snooker's frame; the frame's end as any other */
  func concedeFrame() {
    guard let gm = g, gm.kind == "snooker", gm.winner == nil, rolling == nil else { return }
    let p = cpuLevel != nil ? 0 : gm.turn, next = engine.concedeSnooker(gm, p)
    stroke = nil; power = 0
    if exhib == nil { Rec.frame(next, cpu: cpuLevel != nil) }
    g = next; syncBalls()
    words(next, p)
    if next.winner != nil, exhib == nil { Rec.game(next, level: cpuLevel) }
    aimAtNearest()
  }
  /* settleSolo's practice: practiceJudge, the session's numbers, its words and cues */
  private func settlePractice(_ before: Game, _ shot: RuleShot) {
    if prac != nil { pushUndo(before) }
    let next = engine.practiceJudge(before, shot), v = next.verdict!
    potCount += v.potted.count
    g = next; rolling = nil; spin = Spin(); v3Top2d = false; handAimed = false
    syncBalls()
    guard var P = prac else { return }
    P.shots += 1; P.pots += v.potted.count; if !v.potted.isEmpty { P.potting += 1 }
    prac = P
    if v.scratch { flashDue = ("Scratch", "Ball in hand anywhere", 1.3); msg = "Scratch. Ball in hand anywhere."; sound.cue("foul") }
    else if v.cleared == true && !v.potted.isEmpty {
      flashDue = ("Table cleared", "\(P.shots) shots, \(P.shots > 0 ? Int((100 * Double(P.potting) / Double(P.shots)).rounded()) : 0)% potting", 1.8)
      msg = "Table cleared. Reset the rack or undo to go again."; sound.cue("win")
    } else { msg = v.potted.isEmpty ? "Your shot." : "The \(v.potted.map(String.init).joined(separator: " and the ")) down. Your shot." }
    aimAtNearest()
  }
  /* pushUndo: the layout before a shot, a reset or an edit */
  private func pushUndo(_ gm: Game) {
    guard var P = prac else { return }
    P.undo.append(gm)
    if P.undo.count > TableModel.UNDO_MAX { P.undo.removeFirst() }
    prac = P
  }
  var canSolo: Bool { prac != nil && rolling == nil && stroke == nil }
  /* undo: the layout before the last shot (or reset, or edit), cue ball and ball in hand included */
  func undo() {
    guard canSolo, var P = prac, let last = P.undo.popLast() else { return }
    P.tools = false; prac = P
    g = last; syncBalls(); aimAtNearest()
    flashDue = ("Undone", "", 0.7); msg = "Undone. Your shot."
  }
  func resetRack() {
    guard canSolo, let P = prac, let gm = g else { return }
    pushUndo(gm)
    var n = engine.newPractice(P.layout, seed: P.seed)
    if gm.hand { n.hand = true; n.inHand = "table" }
    g = n; prac?.tools = false
    syncBalls(); randomOrient(); aimAtNearest()
    flashDue = ("Reset", TableModel.PRACTICE_NAMES[P.layout] ?? "", 0.9)
  }
  /* the ball-in-hand toggle: on, the cue ball moves anywhere before every shot; off, it stays put (a rack's opening shot
     goes back to the kitchen) */
  func toggleHand() {
    guard canSolo, var gm = g else { return }
    gm.hand.toggle()
    gm.inHand = gm.hand ? "table" : gm.breakShot ? "kitchen" : nil
    g = gm; syncBalls()
    msg = gm.hand ? "Ball in hand: drag the cue ball anywhere." : "Your shot."
  }
  func setEdit(_ on: Bool) {
    guard freeTable else { return }
    prac?.edit = on; prac?.tools = false
    if on { flashDue = ("Add and remove balls", "Tap the cloth to drop the next ball, tap a ball to take it off", 1.8) }
    msg = on ? "Editing: tap the cloth to drop the next ball, tap a ball to take it off." : "Your shot."
  }
  /* editAt: a tap in edit mode takes an object ball off, or drops the next number on free cloth */
  func editAt(_ x: Double, _ y: Double) {
    guard canSolo, let gm = g else { return }
    let hit = gm.balls.first { $0.on && $0.n > 0 && JSMath.hypot($0.x - x, $0.y - y) < sim.BALL_R * 1.5 }
    let n = hit.map { engine.removeBall(gm, $0.n) } ?? engine.addBall(gm, x, y)
    guard let n else {
      let full = engine.onTable(gm).count >= 15
      flashDue = (full ? "All fifteen are out" : "No room there", full ? "" : "Keep clear of balls, cushions and pockets", 0.9)
      return
    }
    pushUndo(gm)
    let added = hit == nil ? engine.onTable(n).first { !engine.onTable(gm).contains($0) } : nil
    g = n; syncBalls(); aimAtNearest(keep: true)
    msg = hit.map { "Took the \($0.n) off." } ?? "Dropped the \(added ?? 0)."
  }
  /* audit F5: a CPU quick game the player has shot in (cpuGameLive) */
  @ObservationIgnored private var begun = false
  var cpuGameLive: Bool { begun && cpuLevel != nil && exhib == nil && tmatch == nil && g?.mode == nil && g?.winner == nil }
  /* abandonCpuGame: left before its end, it counts as a loss */
  func abandonCpuGame() {
    guard cpuGameLive, let k = g?.kind, let lv = cpuLevel else { begun = false; return }
    begun = false
    Rec.dropAbandon()
    Rec.countLoss(k, lv)
  }
  /* the visit so far (stats.visit): its shooter and legal pots */
  @ObservationIgnored private var visit: (p: Int, pots: Int, fromBreak: Bool)? = nil
  /* #callout (6c): the shot's moment named over the far end of the cloth, about 1.3 s */
  private(set) var callout: (text: String, at: TimeInterval)? = nil
  /* what the table, the cue and the balls wear (4l) */
  @ObservationIgnored var dress: Dress = .standard
  /* 4g: the fine-aim wheel held (fineAim), the loupe's fade, place and clock, the guide's last verdict */
  @ObservationIgnored var fineAim = false
  @ObservationIgnored var loupeA = 0.0
  @ObservationIgnored var loupeT = 0.0
  @ObservationIgnored var loupe: (x: Double, y: Double, r: Double, to: (x: Double, y: Double, r: Double))? = nil
  @ObservationIgnored var guideLegal = true
  /* the ghost ball the guide last drew (drawHeld's padlock stands by it), nil with no guide */
  @ObservationIgnored var ghostAt: (Double, Double)? = nil
  /* the 3D view (4o): on, its pitch and distance (the player's, kept in the settings), the camera last drawn */
  var view3d = Prefs.view == "3d"
  /* the rail's 3D switch: its centre on the stage as last drawn (nil: not shown) */
  @ObservationIgnored var railSwitch: CGPoint?
  /* #viewBtn's tap: 3D on or off, kept as the setting */
  /* v3Sync: the Table View setting changed elsewhere (Settings, from the pause menu): the next frame draws it */
  func syncView(_ on: Bool) {
    guard on != view3d else { return }
    view3d = on
    frame &+= 1
  }
  func toggleView() {
    view3d.toggle()
    UserDefaults.standard.set(view3d ? "3d" : "top", forKey: "felt.settings.view")
    frame &+= 1
  }
  @ObservationIgnored var v3Pitch = Prefs.viewPitch
  @ObservationIgnored var v3Dist = Prefs.viewDist
  @ObservationIgnored var v3Cam: (V3.Cam, V3.Box)? = nil
  /* 6b3 in 3D: the cue as last drawn (its tip and axis, potCue), and each window's fade (.tw.hid's opacity .12s) */
  @ObservationIgnored var potCue: (tip: [Double], ax: [Double])? = nil
  @ObservationIgnored var potHid: [Int: (a: Double, t: Double)] = [:]
  /* V3.k: the input's scale at the camera's pivot, as last drawn */
  @ObservationIgnored var v3K = 100.0
  /* After the Shot 'top': the roll drawn top-down, the setting staying 3D (V3.top2d), until the turn's end */
  var v3Top2d = false
  /* v3Want: the view is wanted (the setting) and has a place (not a replay, not the lesson, not the roll top-down) */
  var v3Live: Bool { view3d && !v3Top2d && rp == nil && lesson == nil }
  /* pocketWords in 3D: each pocket's words from the camera of the last frame drawn (Renderer3D sets them when they change) */
  var v3Words: [String]? = nil
  @ObservationIgnored var onReport: ((Int, Int, Int, Bool) -> Void)?
  /* the handoff: the player the device is passed to (the breaker at a rack's start), until they are ready */
  var handoff: (p: Int, first: Bool)? = nil
  /* hoGo: Ready puts the device in the player's hands, and the status line says whose turn it is (aimHint) */
  func handoffGo() {
    handoff = nil
    if let gm = g { msg = "\(Words.turnOf(gm.turn))." + (gm.inHand != nil ? " Drag the cue ball to move it." : "") }
  }
  @ObservationIgnored private var cpuBusy = false
  private(set) var cpuThinking = false
  /* the CPU's shot found and its think time up (the page's cpuPlan): the 3D view cuts to it, the line and the cue show */
  private(set) var cpuPlanned = false
  /* think's turn and pull (page 5, cpuAnim): the cue turns from where it was onto the line, then draws back to the shot's
     power, and the stroke follows; el the time run */
  /* the page's aiming: the player's turn, the stroke, or the CPU's with its plan (never while its search runs) */
  var cueShown: Bool { !cpuTurn || stroke != nil || cpuPlan != nil }
  @ObservationIgnored private(set) var cpuPlan: (from: Double, angle: Double, power: Double, el: Double, last: Double, shots: Int, turn: Int)? = nil
  /* the search's answer and its think time (the page's cpuReady, .hold), held until the think clock runs past it */
  @ObservationIgnored private var cpuReady: (shot: CPUShot, gm: Game, hold: Double)? = nil
  @ObservationIgnored private(set) var cpuClock = CPUThinkClock()
  /* the last CPU stroke's think, run from the turn's start to the stroke, and whether a tap hurried it (the page's
     felt.lastThink, for the UI tests' cpu-probe) */
  @ObservationIgnored private(set) var lastThink = ""

  /* practice (page 5s): the session's layout and seed, the undo stack (UNDO_MAX), its numbers, editing and the tools strip */
  struct Practice { var layout: String, seed: UInt32, undo: [Game] = [], shots = 0, pots = 0, potting = 0, edit: Bool, tools = false }
  static let UNDO_MAX = 60
  var prac: Practice? = nil
  static let PRACTICE_NAMES = ["8": "8-Ball Rack", "9": "9-Ball Rack", "heyball": "Chinese 8-Ball Rack", "scatter": "Free Table", "empty": "Empty Table"]
  var freeTable: Bool { prac.map { $0.layout == "scatter" || $0.layout == "empty" } ?? false }

  /* a trick shot session (startTrick): the challenge, attempts this run of the list, a Show me in play, and the last
     attempt's result for the sheet (showTrickRes) */
  struct TrickRes { var ok: Bool, why: String, head: String, kind: String, pts: String, demo: Bool, i: Int, daily = false }
  struct TrickSession { var id: String, attempts: Int, demo = false, stars = 0, got = 0, runOver = false, runTry = 0
    /* the daily shot: its day, whether this session's next try is the day's scored one, whether it was counted, and
       whether the try now rolling is it */
    var daily: (day: String, scored: Bool, counted: Bool, live: Bool)? = nil }
  var trick: TrickSession? = nil
  var trickRes: TrickRes? = nil
  /* a drill session (startDrill): the shot, its layout, each shot's judgement, the beat after a shot; the result */
  struct DrillSession { var id: String, i = 0, js: [DrillJ] = [], S: DrillShot? = nil, beat = false }
  struct DrillResult { var total: Int, was: Int?, tier: Int, career: String? = nil }
  /* a drill the career's Practice launched: its score goes to Career.practice, and the words come back for the result */
  @ObservationIgnored var onDrillDone: ((String, Int) -> String)? = nil
  var drill: DrillSession? = nil
  /* a tutorial (startTutorial): the step, 8-ball's group, a failed try's words, a result shown (then), Show me in play,
     where the cue ball began (the ring's "moved"); finished, the done sheet */
  struct TutSession { var id: String, step = 0, ctx: String? = nil, again = false, why = "", then = false, demo = false, cue0: [Double]? = nil }
  var tut: TutSession? = nil
  /* the lesson (startLesson): three steps on one layout, watched, never shot for: 1 aim within LESSON_TOL of the line,
     2 the wheel moved the aim, 3 the bar; the 1 down finishes, a miss puts the balls back */
  struct LessonSession { var step = 1, a0 = 0.0, wheel = false, again = false }
  var lesson: LessonSession? = nil
  var lessonDone = false
  @ObservationIgnored var touching = false
  static let LESSON_TOL = 2 * Double.pi / 180, LESSON_POCKET = 2
  static let LESSON_STEPS = [("Aim", "Drag anywhere on the table to swing the cue. Tap a ball to aim straight at it."), ("Fine-tune", "Roll the wheel to nudge the aim."), ("Shoot", "Pull the power bar and let go.")]
  var tutDone = false
  var drillRes: DrillResult? = nil
  static let DRILL_BEAT = 0.9
  /* the 7 ft regulation solutions (tests/drill-solutions.json), bundled for the -felt-drillshots hook only when present */
  static let drillSols: [String: [[Double]]]? = {
    guard let u = Bundle.main.url(forResource: "drill-solutions", withExtension: "json"), let d = try? Data(contentsOf: u),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let r = o["7r"] as? [String: Any] else { return nil }
    return r.compactMapValues { (($0 as? [String: Any])?["shots"] as? [[NSNumber]])?.map { $0.map(\.doubleValue) } }
  }()

  init(game: TableGame, cpu: String? = nil, practice: String? = nil, trick: String? = nil, drill: String? = nil, tutorial: String? = nil, lesson: Bool = false, exhib: [String]? = nil, exhibArch: [String]? = nil, party: (names: [String], ruleset: String)? = nil, tourney: Tourney? = nil, match: TMatch? = nil) {
    self.game = game
    /* tourneyPlay: the player's next match, the opponent's level, the lag from the tournament's seed */
    var tm: TMatch? = match
    if let t = tourney, let m = t.mine() {
      let foe = t.foe(m), pts = Tourney.points(t.kind)
      tm = TMatch(m: m, foe: foe.name, level: foe.level ?? "medium", arch: foe.arch, need: pts ? 1 : t.race, points: pts, race: t.race,
                      lag: cpuRng(Double(CareerLib.seedOf([String(t.seed), "lag", String(m)])))() < 0.5 ? 0 : 1, ruleset: t.ruleset)
    }
    cpuLevel = practice != nil || trick != nil || drill != nil || tutorial != nil || lesson ? nil : tm?.level ?? (exhib == nil && party == nil ? cpu : nil)
    if lesson { var r = LessonStore.rec; r.seen = true; LessonStore.rec = r; self.lesson = LessonSession() }
    /* startPractice: a fresh seed, editing on for the empty table */
    if let id = drill, drillById(id) != nil { self.drill = DrillSession(id: id) }
    if let id = tutorial, let t = tutById(id) { self.tut = TutSession(id: id, ctx: t.ctx) }
    if let id = trick, trickById(id) != nil { self.trick = TrickSession(id: id, attempts: TrickStore.tries[id] ?? 0) }
    if trick == "daily" { let day = Rec.today(), c = dailyTrick(day); var T = TrickSession(id: c.id, attempts: TrickStore.tries[c.id] ?? 0); T.daily = (day, !DailyStore.done(day), false, false); self.trick = T }
    if let l = practice {
      var P = Practice(layout: l, seed: UInt32.random(in: 0...0x7fffffff), edit: l == "empty")
      /* test hooks: `-felt-seed n` the scatter's seed, `-felt-tools` the tools strip open */
      let a = ProcessInfo.processInfo.arguments
      if let i = a.firstIndex(of: "-felt-seed"), i + 1 < a.count, let n = UInt32(a[i + 1]) { P.seed = n }
      if a.contains("-felt-tools") { P.tools = true }
      prac = P
    }
    self.exhib = exhib
    self.exhibArch = exhibArch
    sound.replaying = false   /* a table left mid-replay leaves the shared sound turned down: a new one starts live */
    self.party = party.map { Party(names: $0.names, wins: $0.names.map { _ in 0 }, ruleset: $0.ruleset) }
    Words.cpuMode = cpuLevel != nil
    /* nameOf: an exhibition's or a party's players, else (two players) the names given at setup, else Player 1 and 2 */
    let given = Prefs.names
    /* an exhibition's players are named as the page's exhibitionTerms names them: Career.lib.genPlayer on a fresh seed */
    var exNames = Set<String>(), exSeed = Int.random(in: 1...0x7fffffff)
    Words.names = exhib.map { l in l.indices.map { CareerLib.genPlayer(exSeed, $0 + 1, &exNames).name } } ?? party?.names
      ?? (cpuLevel == nil && given.contains { !$0.isEmpty } ? given.enumerated().map { $1.isEmpty ? "Player \($0 + 1)" : $1 } : nil)
    /* start(): the settings' table (every pool game on its size and pockets; snooker's size; the bumper table's shape) */
    let prefSpec: (table: String, shape: String?, pockets: String) = switch game {
    case .eight, .nine, .ten, .straight, .rotation: (Prefs.table, nil, Prefs.pockets)
    case .snooker: ("snooker", Prefs.snookerTable, Prefs.pockets)
    case .bumper: ("bumper", Prefs.bumperTable, Prefs.pockets)
    default: (game.table.0, game.table.1, Prefs.pockets)
    }
    /* a tutorial plays on its own table */
    spec = tutorial.flatMap { tutById($0) }.map { ($0.table[0], $0.table.count > 1 ? $0.table[1] : nil, $0.pockets) } ?? tm?.spec ?? prefSpec
    TableModel.setUp(sim, spec)
    engine = RulesEngine(sim: sim)
    sound.cupTable = !sim.BUMPERS.isEmpty
    tmatch = tm
    /* the look: a career match wears the career's equipped items (lookCareer), else the settings' (look()) */
    dress = tm?.dress ?? Prefs.dress(game.table.2)
    rerack()
    /* a test hook: `-felt-replayrun` shoots the auto aim's line at half power, then plays the replay once the offer is up */
    if ProcessInfo.processInfo.arguments.contains("-felt-replayrun") {
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(2)); guard let s = self else { return }
        s.power = 0.6; s.shoot()
        for _ in 0..<200 { try? await Task.sleep(for: .milliseconds(100)); if s.offer != nil { break } }
        try? await Task.sleep(for: .seconds(0.5)); s.startReplay()
      }
    }
    /* a test hook: `-felt-callout "Bank shot"` calls that moment out a moment after the table opens */
    if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-felt-callout"), i + 1 < ProcessInfo.processInfo.arguments.count {
      let w = ProcessInfo.processInfo.arguments[i + 1]
      Task { @MainActor [weak self] in try? await Task.sleep(for: .seconds(2)); guard let s = self else { return }; s.callout = (w, s.now); s.sound.cue("moment") }
    }
    /* a test hook: `-felt-lessonrun` walks the lesson as the controls would: the aim onto the line, the wheel's nudge, the bar */
    if lesson, ProcessInfo.processInfo.arguments.contains("-felt-lessonrun") {
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(2.5)); guard let s = self else { return }
        s.aim = s.lessonPoints().line
        try? await Task.sleep(for: .seconds(2.5)); s.lessonWheel(); s.aim += 0.0004
        try? await Task.sleep(for: .seconds(2.5)); s.aim = s.lessonPoints().line; s.power = 0.5; s.shoot()
      }
    }
    /* a test hook: `-felt-tutshow` plays each step's Show me, one a beat */
    if tutorial != nil, ProcessInfo.processInfo.arguments.contains("-felt-tutshow") {
      Task { @MainActor [weak self] in
        for _ in 0..<12 {
          try? await Task.sleep(for: .seconds(1.6))
          while let s = self, s.rolling != nil || s.stroke != nil { try? await Task.sleep(for: .milliseconds(100)) }
          guard let s = self, !s.tutDone else { return }
          s.tutShowMe()
        }
      }
    }
    /* a test hook: `-felt-drillshots` plays the drill's 7 ft regulation solutions, one a beat */
    if let id = drill, ProcessInfo.processInfo.arguments.contains("-felt-drillshots"), let sol = TableModel.drillSols?[id] {
      Task { @MainActor [weak self] in
        for a in sol {
          try? await Task.sleep(for: .seconds(1.2))
          while let s = self, s.rolling != nil || s.stroke != nil || s.drillBlocked && s.drillRes == nil { try? await Task.sleep(for: .milliseconds(100)) }
          guard let s = self, s.drillRes == nil else { return }
          s.aim = a[0]; s.power = a[1]; s.spin = Spin(x: a[2], y: a[3]); s.shoot()
        }
      }
    }
    /* a test hook: `-felt-elev` opens the elevation sheet at 45 degrees */
    if ProcessInfo.processInfo.arguments.contains("-felt-elev") { setElev(45); elevOpen = true }
    /* a test hook: `-felt-poplayout` takes the break off (so a shot is called), opens the call's menu, then the
       elevation sheet; TableScreen's PopLayer prints each one's frame by its control's */
    if ProcessInfo.processInfo.arguments.contains("-felt-poplayout") {
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(1.5))
        guard let s = self, var gm = s.g else { return }
        gm.breakShot = false; gm.inHand = nil; gm.pushAvail = false; s.g = gm
        s.callMenu = true
        try? await Task.sleep(for: .seconds(1.5))
        s.callMenu = false; s.elevOpen = true
      }
    }
    /* a test hook: `-felt-over` ends the game a moment after the table opens, player 1 the winner (the game over card) */
    if ProcessInfo.processInfo.arguments.contains("-felt-over") {
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(1.5))
        guard let s = self, var gm = s.g else { return }
        gm.winner = 0; s.g = gm
      }
    }
    /* a test hook: `-felt-showme` plays the trick's stored solution a moment after it opens */
    if trick != nil && ProcessInfo.processInfo.arguments.contains("-felt-showme") {
      Task { @MainActor [weak self] in try? await Task.sleep(for: .seconds(1.5)); self?.showMe() }
    }
    if let d = self.trick?.daily, let c = trickById(self.trick!.id) { flashDue = ("Daily shot: \(c.title)", d.scored ? c.goal : "\(c.goal) Practice: today's try is in.", 2.4) }
    /* a test hook: `-felt-paused` opens the table with the pause menu up */
    if ProcessInfo.processInfo.arguments.contains("-felt-paused") { paused = true }
    /* a test hook: `-felt-loupe` holds the fine-aim wheel's loupe open */
    if ProcessInfo.processInfo.arguments.contains("-felt-loupe") { fineAim = true }
  }

  /* the game's balls as the sim's (velocities as the game left them; newTable zeroes the spin) */
  private func syncBalls() {
    guard let g else { return }
    balls = g.balls.map { gb in let b = Ball(gb.n, gb.x, gb.y); b.on = gb.on; return b }
    inHand = g.inHand != nil && g.winner == nil && g.option == nil
  }

  func rerack() {
    abandonCpuGame()
    rolling = nil; inHand = game != .carom && game != .bumper; picked = false; resetCall(); handAimed = false; pottedBy = [[], [], [], []]; stats = GStats(); statsN += 1; potCount = 0; banner = nil
    if tut != nil { tutBegin(0); return }
    if lesson != nil { g = lessonGame(); syncBalls(); randomOrient(); lessonAim(); return }
    if let D = drill, let d = drillById(D.id) {
      drill = DrillSession(id: d.id); drillRes = nil
      drill!.S = engine.drillShot(d, 0, nil); g = engine.drillGame(d, 0, nil)
      syncBalls()
      flashDue = (d.name, d.goal, 2.2); msg = "\(d.name). \(drill!.S!.say)"
      randomOrient(); aimAtNearest()
      return
    }
    if let T = trick, let c = trickById(T.id) {
      g = engine.trickGame(c); trickRes = nil
      syncBalls()
      hideElevTip()
      let hint = trickHint(c)
      flashDue = (c.title, hint.isEmpty ? c.goal : "\(c.goal) \(hint)", 2.2); msg = c.title + ". " + c.goal + (hint.isEmpty ? "" : " " + hint)
      if !hint.isEmpty { showElevTip() }
      randomOrient(); aimAtNearest()
      return
    }
    if let P = prac {
      g = engine.newPractice(P.layout, seed: P.seed)
      syncBalls()
      if P.edit { flashDue = ("Empty table", "Tap the cloth to drop a ball, tap a ball to take it off", 2.2); msg = "Empty table: tap the cloth to drop a ball, tap a ball to take it off." }
      else { flashDue = ("Practice", "No fouls: it is always your shot", 1.5); msg = "Your shot." }
      randomOrient(); aimAtNearest()
      return
    }
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
  func aimAtNearest(keep: Bool = false) {
    /* a turn, a ball in hand moved, a new rack: the pointer's hold starts over (every aimLock reset); a bumper ball
       picked or a free table edited keeps it (keep) */
    if !keep { aimLock = .free }
    /* auto aim off: each turn keeps the aim it was left with (a new rack still aims) */
    if !(Prefs.autoAim && careerAutoAim) && (g?.shots ?? 0) > 0 { return }
    /* bumper's autoAim (page 5): suggestBumper's ball unless one was picked; its line, or straight at the far cup */
    if game == .bumper, var gm = g, gm.winner == nil, let sg = CPU(engine: engine).suggestBumper(gm) {
      aimAnim = nil; hint = nil
      if let n = sg.n, !cpuTurn { hint = (n, sg.k); hintT = now }
      if !picked, let n = sg.n, n != gm.striker { gm.striker = n; g = gm; syncBalls() }
      if let c = cue {
        let T = sim.POCKETS[sg.k]
        aim = g?.striker == sg.n ? sg.angle : atan2(T[1] - c.y, T[0] - c.x)
      }
      return
    }
    /* autoAim (page 5): a human turn starts on suggestAim's line, the cue swung onto it over AUTO_AIM_MS (at once
       with Reduce Motion), and `hint` names its ball and pocket (drawHint); never in the lesson, which teaches aiming,
       nor once the player has aimed by hand this turn (the hint still follows) */
    aimAnim = nil; hint = nil
    if let gm = g, !cpuTurn, lesson == nil, rolling == nil {
      guard Prefs.autoAim && careerAutoAim, let sg = CPU(engine: engine).suggestAim(gm), let c = cue, gm.balls.contains(where: { $0.n == sg.n && $0.on }) else {
        if !(Prefs.autoAim && careerAutoAim) && (g?.shots ?? 0) == 0 { nearestAim() }
        return
      }
      hint = (sg.n, sg.k); hintT = now
      if handAimed { return }
      /* the cue points at the centre of the ball suggested (carom: the suggested line itself) */
      guard let t = gm.balls.first(where: { $0.n == sg.n }) else { return }
      let to = gm.kind == "carom" ? sg.angle : atan2(t.y - c.y, t.x - c.x)
      lockAim()
      if reduceMotion { aim = to; keepAim(); return }
      aimAnim = (aim, AimFeel.wrap(to - aim), now)
      return
    }
    nearestAim()
  }
  private func nearestAim() {
    guard let c = balls.first(where: { $0.n == cueN }) else { return }
    let others = balls.filter { $0.on && $0.n != cueN }
    if let t = others.min(by: { JSMath.hypot($0.x - c.x, $0.y - c.y) < JSMath.hypot($1.x - c.x, $1.y - c.y) }) {
      aim = atan2(t.y - c.y, t.x - c.x)
    }
  }
  /* auto aim's suggestion (hint: the ball and pocket drawHint marks), its swing (stepAutoAim), and whether the player
     has aimed by hand this turn */
  static let AUTO_AIM_MS = 0.25
  @ObservationIgnored var hint: (n: Int, k: Int)?
  @ObservationIgnored var hintT: TimeInterval = 0
  @ObservationIgnored var aimAnim: (from: Double, d: Double, t0: TimeInterval)?
  @ObservationIgnored var handAimed = false
  /* the system's Reduce Motion, as the game screen reads it */
  @ObservationIgnored var reduceMotion = false
  func stepAutoAim() {
    guard let a = aimAnim else { return }
    if rolling != nil || stroke != nil { aimAnim = nil; return }
    let u = min(1, max(0, (now - a.t0) / (TableModel.AUTO_AIM_MS / speed)))
    aim = a.from + a.d * (1 - pow(1 - u, 3))
    if u >= 1 { aimAnim = nil }
  }
  /* finishAutoAim: the player takes the aim mid-swing: it lands where it was going first; and from now this turn's aim
     is the player's */
  func takeAim() {
    if let a = aimAnim { aim = a.from + a.d; aimAnim = nil }
    handAimed = true
  }

  /* a pointer (an iPad's mouse or trackpad; page 5's input comment). hov: where the pointer is anchored (x, y, since t),
     whether it is on the bed, and `rest`, the aim where it last rested. aimLock: free, pending (lock wherever the
     pointer next shows up), locked at a point, or held: a click on the cloth (or a pointer sweep let go) holds the aim,
     top-down only, and no later pointer move breaks it; the wheel, the arrows and the english still adjust it; another
     click aims there and holds that; Esc (before it pauses) or a right click lets go. Touch and pen never hold */
  enum AimLock: Equatable { case free, pending, at(CGPoint), held }
  struct Hov { var x: CGFloat, y: CGFloat, t: Double, bed: Bool, rest: Double }
  static let LOCK_PX: CGFloat = 24, DWELL_MS = 150.0
  @ObservationIgnored var aimLock = AimLock.free
  @ObservationIgnored var hov: Hov? = nil
  func lockAim() { if aimLock != .held { aimLock = hov.map { .at(CGPoint(x: $0.x, y: $0.y)) } ?? .pending }; keepAim() }
  /* a fine adjustment made off the table: lock where the pointer next shows up (a held aim stays held) */
  func pendLock() { if aimLock != .held { aimLock = .pending }; keepAim() }
  /* the pointer's click-to-hold: top-down only, where hover aims */
  func holdAim() { aimLock = view3d ? .free : .held; keepAim() }
  @discardableResult func letGoAim() -> Bool {
    guard aimLock == .held else { return false }
    aimLock = .free; keepAim()
    return true
  }
  var aimHeld: Bool { aimLock == .held && human && trickRes == nil && rp == nil && !view3d }
  /* this aim is deliberate: a dash off the bed comes back to it */
  func keepAim() { hov?.rest = aim }
  func leaveBed() {
    guard var h = hov, h.bed else { return }
    h.bed = false; hov = h
    if human && !touching && aimLock == .free { aim = h.rest }
  }
  /* hover: the pointer at p (the table's view, at time t in ms) aims, over the bed only and never while the aim is locked
     or in 3D (the camera is the aim) */
  func hover(_ p: CGPoint, _ t: Double, _ m: Mapper) {
    if view3d || touching { return }
    let (x, y) = m.table(p), bed = x >= 0 && x <= sim.TL && y >= 0 && y <= sim.TW
    if hov == nil { hov = Hov(x: p.x, y: p.y, t: t, bed: false, rest: aim) }
    if JSMath.hypot(Double(p.x - hov!.x), Double(p.y - hov!.y)) > 4 {
      if t - hov!.t >= TableModel.DWELL_MS && hov!.bed { hov!.rest = aim }
      hov!.x = p.x; hov!.y = p.y; hov!.t = t
    }
    if aimLock == .pending { aimLock = .at(p) }
    else if case .at(let q) = aimLock, JSMath.hypot(Double(p.x - q.x), Double(p.y - q.y)) > Double(TableModel.LOCK_PX) { aimLock = .free }
    if !bed { leaveBed(); return }
    hov!.bed = true
    let aiming = human && trickRes == nil && rp == nil
    if aiming && !mouseTipSeen { showMouseTip() }
    guard aiming, aimLock == .free, let c = cue else { return }
    let s = m.pt(c.x, c.y)
    if JSMath.hypot(Double(p.x - s.x), Double(p.y - s.y)) > 2 * sim.BALL_R * m.k { aimAnim = nil; aim = atan2(y - c.y, x - c.x) }
  }
  /* the pointer tip: once ever, the first time a pointer hovers the bed on the player's aim (felt.mouseTip.v1, written the
     moment it shows); never over the lesson's or a tutorial's coach */
  static let MOUSE_TIP = "Click the cloth to lock your aim, then pull the power bar."
  @ObservationIgnored private(set) var mouseTipSeen = MouseTipStore.seen
  @ObservationIgnored private(set) var mouseTipShows = 0
  @discardableResult func showMouseTip() -> Bool {
    guard !mouseTipSeen, lesson == nil, tut == nil else { return false }
    mouseTipSeen = true; mouseTipShows += 1
    MouseTipStore.seen = true
    banner = ("Aiming With a Mouse", TableModel.MOUSE_TIP, now + 4.2)
    msg = TableModel.MOUSE_TIP
    return true
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
    guard rolling == nil, stroke == nil, power > 0.01, g?.option == nil, g?.winner == nil, !cpuTurn, trickRes == nil, !drillBlocked, rp == nil else { power = 0; return }
    /* a pull the call refuses (no needed call yet) opens the call's menu on the let-go, the pockets first */
    if !callReady { power = 0; callMenu = true; return }
    markPower = power
    stroke = (power, nil)
    confirmCall(humanCall())
  }
  /* careerAssist (6d): a career match's assist, while the match is on and simulation purity is off */
  var careerAssist: JV? { guard let t = tmatch, t.career, !t.done, g?.mode == nil else { return nil }; return t.assist }
  static let GUIDE_ORDER = ["off", "short", "full"]
  /* careerGuide: the settings' guide, capped by position play in a career match */
  var guideMode: String {
    let mode = Prefs.guide
    guard let gd = careerAssist?["guide"]?.str, let i = Self.GUIDE_ORDER.firstIndex(of: mode) else { return mode }
    let cap = gd == "none" ? "off" : gd == "long" ? "full" : "short"
    return Self.GUIDE_ORDER[min(i, Self.GUIDE_ORDER.firstIndex(of: cap)!)]
  }
  /* careerAutoAim: auto aim needs tactics 40 in a career match */
  var careerAutoAim: Bool { careerAssist.map { $0["autoAim"] != false } ?? true }
  /* careerExec: the skills' jitter on the player's own shot (normal draws from the match's seed and shot count: spin x,
     spin y, angle, power), times hillNoise when either player is a rack from the match */
  private func careerExec(_ angle: Double, _ pw: Double, _ sp: Spin) -> (angle: Double, power: Double, spin: Spin) {
    guard let a = careerAssist, !cpuTurn, var tm = tmatch else { return (angle, pw, sp) }
    let an = a["aimNoise"]?.d ?? 0, pn = a["powerNoise"]?.d ?? 0, bn = a["breakNoise"]?.d ?? 0, sn = a["spinNoise"]?.d ?? 0
    if an == 0 && pn == 0 && bn == 0 && sn == 0 { return (angle, pw, sp) }
    tm.shot += 1; tmatch = tm
    let r = rng(tm.execSeed &+ UInt32(truncatingIfNeeded: tm.shot) &* 0x9e3779b1)
    let gn = { () -> Double in let u = max(1e-9, r()), v = r(); return (-2 * Foundation.log(u)).squareRoot() * Foundation.cos(2 * Double.pi * v) }
    let hill = !tm.points && (tm.score.max() ?? 0) == tm.need - 1 ? (a["hillNoise"]?.d ?? 1) : 1
    var x = sp.x + gn() * sn * hill, y = sp.y + gn() * sn * hill
    let L = (x * x + y * y).squareRoot()
    if L > 1 { x /= L; y /= L }
    let ang = angle + gn() * an * hill
    let pow = clamp(pw * (1 + gn() * ((g?.breakShot ?? false) ? bn : pn) * hill), 0, 1)
    return (ang, pow, spinOf(x: x, y: y, e: sp.e))
  }
  private func strikeNow(_ pw: Double, _ t: TimeInterval) {
    if held != nil { placeEnd(); placeAt = nil; placeBack = nil }
    if g?.mode == "trick" { scoreDaily() }
    /* shoot(): the declaration the player built (humanCall) goes on the game; judge takes it from there */
    if var gm = g, !cpuTurn { gm.call = humanCall(); g = gm }
    /* shotRecord: what the shot needs to be played again, and the game as it stood (notableOf) */
    /* a career match without simulation purity: the skills' execution jitter (6d, careerExec) */
    let ex = careerExec(aim, pw, spin)
    shotN += 1
    lastShot = ShotRec(balls: balls.map { $0.copy() }, angle: ex.angle, power: ex.power, spin: ex.spin, ball: cueN, g: g, orient: orient, id: shotN); offer = nil
    camPred = Cam.predict(sim, id: shotN, balls: balls, ball: cueN, angle: ex.angle, power: ex.power, spin: ex.spin)
    let tab = sim.newTable(balls, cue: cueN)
    if let c = cue { lastCue = (c.x, c.y, aim) }
    sim.strike(tab, ex.angle, ex.power, ex.spin)
    rolling = tab; heard = 0; carry = 0; lastT = t; inHand = false; power = 0; stroke = nil; shotAt = t
    fps.prev = nil   /* the -felt-fps hook counts a roll's own frames: the time between rolls is no stall */
  }

  static let fpsOn = ProcessInfo.processInfo.arguments.contains("-felt-fps")


  @ObservationIgnored var fps: (t0: Double?, prev: Double?, n: Int, sim: Double, dtMax: Double) = (nil, nil, 0, 0, 0)
  /* the pause menu is up: the table stands still (frameBody does not run under it) */
  var paused = false
  /* a test hook: `-felt-aimbench` turns the aim a little every frame, as a slow sweep, and prints every 2 s the frames,
     the worst gap between them and how many times each counted view's body ran (Bench.bodies) */
  static let aimBench = ProcessInfo.processInfo.arguments.contains("-felt-aimbench")
  /* `-felt-aimprobe`: the aim and its hold in an element's value for the UI tests (PointerTests) */
  static let aimProbe = ProcessInfo.processInfo.arguments.contains("-felt-aimprobe")
  static let pointerBench = ProcessInfo.processInfo.arguments.contains("-felt-pointerbench")
  static let touchBench = ProcessInfo.processInfo.arguments.contains("-felt-touchbench") || ProcessInfo.processInfo.arguments.contains("-felt-touchbench-hand") || ProcessInfo.processInfo.arguments.contains("-felt-touchbench-slow")
  @ObservationIgnored private var bench: (t0: Double, prev: Double, n: Int, worst: Double)?
  /* keyboard (page 5's keydown, for a hardware keyboard): left and right aim (Shift coarse 0.03, Alt or Ctrl one ridge
     of the fine wheel, FINE_STEP, else 0.004 rad); R centres the english; B (bumper) takes the next striker; up and
     down move the bar's mark (Shift 0.1, else 0.02); M carries the cue ball in hand, the arrows move it (Shift 5 cm,
     else 1 cm) until M, Space or Enter; Space or Enter on the bar drives it (keyDrive, only with settings.keyShoot).
     No key ever shoots otherwise. Any key during a drive stops it. Returns whether the key was the game's. */
  static let FINE_STEP = 4 * 0.02 * Double.pi / 180, KEY_PULL_MS = 0.9
  @ObservationIgnored private var keyPull: (t0: TimeInterval, to: Double)?
  @ObservationIgnored private(set) var keyMove = false
  var keyMsg = ""
  var human: Bool { !cpuTurn && g?.winner == nil && rolling == nil && stroke == nil }
  func key(_ k: String, shift: Bool, alt: Bool) -> Bool {
    if keyPull != nil { cancelKeyPull(); return true }
    /* Esc lets a held pointer aim go before it pauses */
    if k == "escape" { if !paused && letGoAim() { return true }; paused.toggle(); return true }
    guard !paused, human, trickRes == nil else { return false }
    let dx = k == "right" ? 1.0 : k == "left" ? -1.0 : 0, dy = k == "up" ? 1.0 : k == "down" ? -1.0 : 0
    if keyMove {
      if dx != 0 || dy != 0, let c = cue {
        let st = shift ? 0.05 : 0.01, at = placeAt ?? (c.x, c.y)
        /* on screen: right is +x, up is -y (upright: the table's long side runs up the screen) */
        let (tx, ty) = uprightView ? (at.0 + dy * st, at.1 + dx * st) : (at.0 + dx * st, at.1 - dy * st)
        place(tx, ty); return true
      }
      if k == "m" || k == "space" || k == "return" { keyMove = false; placeEnd(); return true }
      return false
    }
    switch k {
    case "r": if spinOk { spin = spinOf(x: 0, y: 0, e: spin.e) }; return true
    case "b":
      if game == .bumper, let gm = g { let list = engine.bumperStrikers(gm); if list.count > 1, let i = list.firstIndex(of: cueN) { _ = pickBall(list[(i + 1) % list.count]) } }
      return true
    case "m": if inHand { keyMove = true; return true }; return false
    case "space", "return": keyDrive(); return true
    case "up", "down":
      markPower = min(1, max(0.02, ((markPower + dy * (shift ? 0.1 : 0.02)) * 100).rounded() / 100)); power = 0
      keyMsg = "Mark \(Int((markPower * 100).rounded()))%"
      return true
    case "left", "right":
      takeAim()
      aim = AimFeel.wrap(aim + dx * (shift ? 0.03 : alt ? TableModel.FINE_STEP : 0.004))
      lockAim()
      return true
    default: return false
    }
  }
  func keyDrive() {
    guard keyPull == nil, human else { return }
    if !Prefs.bool("keyShoot", false) { keyMsg = "Space on the power bar is off. Turn on Space drives the power bar in Settings, Accessibility."; return }
    if !callReady { keyMsg = "Call your shot: tap a ball, then a pocket, or play a safety."; callMenu = true; return }
    takeAim()
    keyPull = (now, min(1, max(0.02, markPower))); power = 0
    keyMsg = "The bar pulls to \(Int((keyPull!.to * 100).rounded()))% and lets go. Any key stops it."
  }
  private func stepKeyPull() {
    guard let k = keyPull else { return }
    if !human { cancelKeyPull(); return }
    let u = min(1, max(0, (now - k.t0) / (TableModel.KEY_PULL_MS * max(0.35, k.to))))
    power = k.to * u
    if u >= 1 { keyPull = nil; keyMsg = ""; shoot() }
  }
  func cancelKeyPull() { guard keyPull != nil else { return }; keyPull = nil; power = 0; keyMsg = "" }
  /* the display's frame interval, as the ticks measure it (1/60 until known) */
  @ObservationIgnored private(set) var frameGap = 1.0 / 60
  @ObservationIgnored private var tickPrev: TimeInterval?
  func tick(_ now: TimeInterval) {
    if let p = tickPrev, now - p > 0.002, now - p < 0.05 { frameGap += (now - p - frameGap) * 0.1 }
    tickPrev = now
    if (TableModel.aimBench || TableModel.touchBench) && rolling == nil && !cpuTurn && g?.winner == nil {
      if TableModel.aimBench { aim = AimFeel.wrap(aim + 0.004) }
      var b = bench ?? (now, now, 0, 0)
      b.n += 1; b.worst = max(b.worst, now - b.prev); b.prev = now
      if now - b.t0 >= 2 {
        print(String(format: "felt-aimbench %.1f frames/s, worst gap %.1f ms, %@, %@, bodies %@", Double(b.n) / (now - b.t0), b.worst * 1000, Bench.drawWords(), Bench.pvWords(), Bench.bodies.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")))
        Bench.bodies = [:]; b = (now, now, 0, 0)
      }
      bench = b
    }
    let tt0 = CACurrentMediaTime()
    defer { if TableModel.fpsOn { let d = CACurrentMediaTime() - tt0; if d > 0.1 { print(String(format: "felt-fps slow tick %.0f ms", d * 1000)) } } }
    defer { frame &+= 1 }
    /* the CPU's think (cpuClock) and its turn and pull (cpuPlan, its last frame put at infinity, so the frame after the
       pause adds nothing) stand still under the pause menu, as the page's resume moves cpuT0 and cpuAnim on */
    if paused { lastT = nil; camLast = nil; cpuClock.last = nil; cpuPlan?.last = .infinity; return }
    self.now = now
    voTick()
    if cpuThinking { cpuClock.step(now, held: rp != nil || handoff != nil) }
    defer { camStep(now) }
    stepAutoAim()
    stepPlaceBack()
    liftStep(now)
    stepKeyPull()
    if lesson != nil { lessonCheck() }
    if let o = offer, now > o.until || rolling != nil || stroke != nil { offer = nil }
    if rp != nil { if let f = flashDue { banner = (f.0, f.1, now + f.2); flashDue = nil }; pots.removeAll { now - $0.t >= potMs }; replayStep(now); return }
    if let f = flashDue { banner = (f.0, f.1, now + f.2); flashDue = nil }
    pots.removeAll { now - $0.t >= potMs }
    if let b = banner, now >= b.until { banner = nil }
    potTrack()
    effects.removeAll { now - $0.t >= $0.d }
    if let st = stroke {
      if st.t0 == nil { stroke = (st.power, now) } else if now - st.t0! >= TableModel.STROKE_MS / speed { strikeNow(st.power, now) }
    }
    cpuThinkStep()
    cpuAnimStep()
    if cpuTurn && rolling == nil && stroke == nil && !cpuBusy { cpuStep() }
    guard let tab = rolling else { lastT = nil; return }
    /* as frameBody: never backwards, at most 50 ms a frame */
    let dt = min(0.05, max(0, lastT.map { now - $0 } ?? 1.0 / 60))
    lastT = now
    let want = dt / SIM_DT * speed + carry
    /* a test hook: `-felt-fps` prints the frame rate and the roll's pace (sim seconds per real second) every 2 s */
    if TableModel.fpsOn {
      if let p = fps.prev, now - p > 0.2 { print(String(format: "felt-fps stall %.0f ms: %.2f s into the roll, pots %d, effects %d, banner %d, hits %d", (now - p) * 1000, p - shotAt, pots.count, effects.count, banner != nil ? 1 : 0, rolling?.hits.count ?? -1)) }
      fps.n += 1; fps.sim += dt * speed; fps.dtMax = max(fps.dtMax, now - (fps.prev ?? now)); fps.prev = now
      if fps.t0 == nil { fps.t0 = now }
      if now - fps.t0! >= 2 { print(String(format: "felt-fps %.1f frames/s, pace %.2f, worst frame %.0f ms", Double(fps.n) / (now - fps.t0!), fps.sim / (now - fps.t0!), fps.dtMax * 1000)); fps = (nil, nil, 0, 0, 0) }
    }
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
    if !going { let res = sim.resultOf(tab); settle(res); offerReplay(res) }
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
    balls = next; rolling = nil; v3Top2d = false
    if balls.allSatisfy({ !$0.on || $0.n == cueN }) { rerack() }
  }

  /* settle() for a pocket game: the page's judge, then its words (banner and status line) */
  private func settleRules(_ r: ShotResult) {
    picked = false; resetCall()
    gBefore = g
    guard let before = g else { return }
    let shot = RuleShot(r)
    if before.mode == "practice" && before.layout == "lesson" { settleLesson(r); return }
    if before.mode == "practice" { settlePractice(before, shot); return }
    if before.mode == "trick" { settleTrick(before, r); return }
    if before.mode == "drill" { settleDrill(before, r); return }
    if tut != nil { settleTut(before, shot); return }
    let shooter = before.turn, next = engine.judge(before, shot)
    potCount += next.verdict?.potted.count ?? 0
    if let gm0 = gBefore, gm0.turn < 4 { pottedBy[gm0.turn] += next.verdict?.potted.filter { $0 > 0 } ?? [] }
    /* noteShot: the shot's moments (shotMoments) with the visit so far, which carries on while the same player keeps the
       table without a foul; the record (recordShot, recordFrame); the moment called out */
    let vis: (p: Int, pots: Int, fromBreak: Bool) = visit.flatMap { $0.p == shooter ? $0 : nil } ?? (shooter, 0, before.breakShot)
    let mo = engine.shotMoments(before, r, next, run: (vis.pots, vis.fromBreak))
    visit = next.winner == nil && next.turn == shooter && next.verdict?.foul == nil ? (shooter, vis.pots + mo.legal, vis.fromBreak) : nil
    if shooter < 4 {
      stats.shots[shooter] += 1; stats.pots[shooter] += mo.legal; stats.best[shooter] = max(stats.best[shooter], vis.pots + mo.legal)
      if next.verdict?.foul != nil { stats.fouls[shooter] += 1 }
      if before.breakShot { stats.brk = (shooter, (next.verdict?.potted ?? []).filter { $0 != 0 }.count, next.verdict?.foul != nil) }
      for k in mo.keys { stats.notes[shooter][k, default: 0] += 1 }
      stats.last = mo.keys; stats.lastP = shooter
    }
    if let k = mo.keys.first, next.winner == nil, before.kind != "carom" { callout = (momentWord(k, before.kind), now); sound.cue("moment") }
    /* markBegun: the player's first shot of a CPU game */
    if !begun, cpuLevel != nil, exhib == nil, tmatch == nil, before.mode == nil, shooter == 0 { begun = true; Rec.markBegun(before.kind, cpuLevel!) }
    if exhib == nil && !(cpuLevel != nil && shooter != 0) { Rec.shot(before, shot, next, p: shooter, vis: vis.pots + mo.legal, legal: mo.legal, keys: mo.keys, pockets: sim.POCKETS) }
    if exhib == nil && next.kind == "snooker" { Rec.frame(next, cpu: cpuLevel != nil) }
    g = next; rolling = nil; spin = Spin(); v3Top2d = false
    /* a party: the device is handed over each time the turn goes to another player (or a choice to another) */
    if party != nil, next.winner == nil, (next.option?.who ?? next.turn) != shooter { handoff = (next.option?.who ?? next.turn, false) }
    /* a choice the rules give (5c): the CPU answers at once (the page's nextTurn), and its choice is in the shot's words */
    var chose: (who: Int, kind: String, choice: String)? = nil
    while let gm = g, let o = gm.option, let pick = cpuPick(), let n = engine.chooseOption(gm, pick) {
      chose = (o.who, o.kind, pick); g = n
      randomOrientIfRacked(gm, n)
    }
    syncBalls()
    words(g ?? next, shooter, chose: chose)
    aimAtNearest()
  }
  private func words(_ gm: Game, _ shooter: Int, chose: (who: Int, kind: String, choice: String)? = nil) {
    guard let v = gm.verdict else { return }
    /* the page's cues: a win (or, against the CPU, a loss: two soft falling notes), a foul, carom's point, the turn passing */
    if let w = gm.winner {
      sound.cue(cpuLevel != nil && w == 1 ? "lose" : "win")
      if exhib == nil { Rec.game(gm, level: cpuLevel) }
    }
    else if v.foul != nil { sound.cue("foul") }
    else if gm.kind == "carom" && v.carom?.point == true { sound.cue("point") }
    else if gm.turn != shooter { sound.cue("turn") }
    if gm.winner != nil { msg = Words.overLine(gm); banner = nil; tourneyRackOver(); return }
    if gm.kind == "bumper" {
      let w = Words.bumper(v, gm, shooter, gm.turn)
      msg = w.msg
      banner = w.banner.map { ($0.0, $0.1, now + $0.2) }
      return
    }
    if gm.kind == "carom" {
      let w = Words.carom(v, gm, shooter, gm.turn)
      msg = chose.map { "\(Words.nameOf($0.who)): \(Words.optLabel($0.kind, $0.choice).lowercased()). \(Words.turnOf(gm.turn))." } ?? w.msg
      if gm.option == nil { banner = (w.banner.0, w.banner.1, now + w.banner.2) }
      return
    }
    if gm.kind == "snooker" {
      let w = Words.snooker(v, gm, shooter, gm.option?.who ?? gm.turn, chose: chose)
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
  /* the player's answer to a choice the rules give (game.option; the page's choose): the CPU's choices that follow are
     answered at once (nextTurn), then the flash ('turn', 1000 ms) names the choice over the CPU's that followed, else
     the turn, and the status line says both: "Spot the 8. CPU: Re-rack." */
  func choose(_ choice: String) {
    guard let gm = g, let o = gm.option, let next = engine.chooseOption(gm, choice) else { return }
    g = next
    randomOrientIfRacked(gm, next)
    var chose: (who: Int, kind: String, choice: String)? = nil
    while let a = g, let co = a.option, let pick = cpuPick(), let n = engine.chooseOption(a, pick) { chose = (co.who, co.kind, pick); g = n; randomOrientIfRacked(a, n) }
    syncBalls()
    let gn = g!, t = Words.optLabel(o.kind, choice)
    /* optionSay: a choice still to make, the player's own */
    let then = chose.map { "\(Words.nameOf($0.who)): \(Words.optLabel($0.kind, $0.choice))" }
      ?? gn.option.map { "\(Words.nameOf($0.who)): \(Words.OPT[$0.kind]?["head"] ?? ""). \(Words.OPT[$0.kind]?["sub"] ?? "")" } ?? Words.turnOf(gn.turn)
    banner = (t, chose != nil ? then : Words.turnOf(gn.turn), now + 1.0)
    msg = "\(t). \(then)\(then.hasSuffix(".") ? "" : ".")"
    aimAtNearest()
  }
  /* the page's nextTurn: a choice the rules give the CPU (game.option) is answered at once, with no think time and no
     wait, and the turn goes on from what it chose. Called from cpuStep (the shot's and the player's choices answer the
     CPU's themselves), so never under the pause menu, the handoff or a replay */
  private func cpuAnswer() {
    var chose: (who: Int, kind: String, choice: String)? = nil
    while let a = g, let co = a.option, let pick = cpuPick(), let n = engine.chooseOption(a, pick) { chose = (co.who, co.kind, pick); g = n; randomOrientIfRacked(a, n) }
    guard let c = chose, let gn = g else { return }
    syncBalls()
    msg = "\(Words.nameOf(c.who)): \(Words.optLabel(c.kind, c.choice).lowercased()). \(Words.turnOf(gn.turn))."
    aimAtNearest()
  }
  /* cpuOption's answer to the choice on the table, when it is the CPU's to make */
  private func cpuPick() -> String? {
    guard cpuTurn, let gm = g, let o = gm.option, let level = actingLevel else { return nil }
    let c = CPU(engine: engine); c.arch = actingArch; c.hill = actingHill
    return c.cpuOption(gm, level: level) ?? o.choices[0]
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
    guard cpuTurn, !cpuBusy, rolling == nil, stroke == nil else { return }
    cpuAnswer()
    guard cpuTurn, let gm = g, gm.option == nil, let level = actingLevel else { return }
    let arch = actingArch, hill = actingHill
    cpuBusy = true; cpuThinking = true; cpuPlanned = false; cpuReady = nil; cpuClock = CPUThinkClock()
    cpuClock.step(now, held: false)
    let spec = spec, seed = Double(Int.random(in: 1...1_000_000))
    Task.detached(priority: .userInitiated) {
      let sim = Sim(); TableModel.setUp(sim, spec)
      let c = CPU(engine: RulesEngine(sim: sim)); c.arch = arch; c.hill = hill
      let shot = c.cpuShot(gm, seed: seed, level: level)
      await MainActor.run { self.cpuPlay(shot, gm, seed: seed) }
    }
  }
  /* the search's answer waits for the think time (the page's cpuReady, its hold), counted on the frame clock from the
     turn's start (cpuClock: still under the pause menu, the handoff or a replay) */
  private func cpuPlay(_ shot: CPUShot, _ gm: Game, seed: Double) {
    guard let g1 = g, g1.shots == gm.shots, g1.turn == gm.turn else { cpuBusy = false; cpuThinking = false; return }
    cpuReady = (shot, gm, cpuThinkMs(gm, shot, seed))
  }
  /* think's first half, each frame: once the think time is up the answer becomes the plan: the cue ball placed, the line,
     the call and the spin set, and the cue turns onto it and draws back (cpuAnimStep) */
  private func cpuThinkStep() {
    guard let r = cpuReady, cpuClock.due(r.hold, speed: speed) else { return }
    cpuReady = nil
    let gm = r.gm, shot = r.shot
    guard var g0 = g, g0.shots == gm.shots, g0.turn == gm.turn, cpuTurn else { cpuBusy = false; cpuThinking = false; return }
    if let p = shot.place { g0 = engine.placeCue(g0, p[0], p[1]) }
    if gm.kind == "bumper", let b = shot.ball { g0.striker = b }
    g0.call = shot.call; g = g0; syncBalls()
    spin = shot.spin; cpuPlanned = true
    cpuPlan = (aim, shot.angle, shot.power, 0, now, g0.shots, g0.turn); power = 0   /* the cue at rest until the pull */
  }
  /* think's second half, each frame (cpuAnim); at the end the stroke, as commit() */
  private func cpuAnimStep() {
    guard var P = cpuPlan else { return }
    guard let gm = g, gm.shots == P.shots, gm.turn == P.turn, cpuTurn, rolling == nil, stroke == nil else {
      cpuPlan = nil; cpuBusy = false; cpuThinking = false; power = 0; return
    }
    P.el += min(0.1, max(0, now - P.last)); P.last = now; cpuPlan = P
    let u = P.el / cpuClock.animS(speed: speed), a = cpuAnim(u, from: P.from, to: P.angle, power: P.power)
    aim = a.aim
    if let p = a.pull { power = p }
    if u >= 1 {
      lastThink = String(format: "think %.3f skip %d tap %.3f", cpuClock.el, cpuClock.skip ? 1 : 0, cpuClock.skipAt ?? -1); TouchLog.add("cpustroke " + lastThink)
      cpuPlan = nil
      cpuThinking = false
      power = P.power; markPower = P.power
      stroke = (P.power, nil)
      confirmCall(g?.call)
      cpuBusy = false
    }
  }
  /* F8 (the page's cpuSkip): a tap on the table during the CPU's turn hurries it, the wait and the cue's swing; never the
     search. Returns whether it was the CPU's turn (the press is then eaten whole) */
  func cpuSkip() -> Bool {
    guard cpuTurn, rolling == nil, stroke == nil, rp == nil else { return false }
    if cpuThinking, !cpuClock.skip { cpuClock.skip = true; cpuClock.skipAt = cpuClock.el }
    return true
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

  /* placeAt: while the cue ball in hand is carried, where the finger has it (drawPlace's ghost and ring), up to 2 cm
     past the rails as the page's moveBall; on a legal spot the ball is there too, on an illegal one it stays on its
     last legal spot. The game takes the spot once, at the let-go (placeEnd): writing the observed game on every move
     rebuilt the whole screen at the touch rate. An illegal let-go slides the ghost back to the last legal spot over
     PLACE_BACK_MS (at once with Reduce Motion); a ball that moved gets auto aim again (endMove). */
  static let PLACE_BACK_MS = 0.120
  /* 4f's ball in hand lift, visual only: while carried on legal and illegal spots alike (placeAt, a human turn) it rises
     over BIH_UP_MS (bihH 0..1: the shadow grows, softens and falls further from the lamp, the ball LIFT_GROW bigger);
     let go on the table it settles over SETTLE_MS (down, one tiny bounce, still: settleH). Reduce Motion: up and down
     at once, no bounce. Never the spot, the input or the view */
  static let BIH_UP_MS = 0.090, SETTLE_MS = 0.150, LIFT_GROW = 0.06
  @ObservationIgnored private(set) var bihH = 0.0
  @ObservationIgnored private var bih: (t: TimeInterval?, on: Bool, settle: (t0: TimeInterval, h0: Double)?) = (nil, false, nil)
  func liftStep(_ now: TimeInterval) {
    let carrying = placeAt != nil && placeBack == nil && !cpuTurn && rolling == nil
    let dt = bih.t.map { min(0.1, max(0, now - $0)) } ?? 0.016, rm = (carrying || bih.on || bih.settle != nil) && reduceMotion
    bih.t = now
    if carrying { bih.settle = nil; bihH = rm ? 1 : min(1, bihH + dt / TableModel.BIH_UP_MS) }
    else {
      if bih.on && bihH > 0 && !rm, let c = cue, c.on, rolling == nil { bih.settle = (now, bihH) }
      bihH = 0
    }
    bih.on = carrying
    if let st = bih.settle, rm || rolling != nil || now - st.t0 >= TableModel.SETTLE_MS || now < st.t0 { bih.settle = nil }
  }
  /* the settling cue ball's height (0..1): down in the first third, a bounce a tenth as high, still */
  func settleH(_ now: TimeInterval) -> Double {
    guard let st = bih.settle else { return 0 }
    let u = min(1, max(0, (now - st.t0) / TableModel.SETTLE_MS))
    return st.h0 * abs(cos(1.5 * Double.pi * u)) * pow(1 - u, 2)
  }
  @ObservationIgnored var placeAt: (Double, Double)? = nil
  @ObservationIgnored private var held: (moved: Bool, last: (Double, Double))? = nil
  @ObservationIgnored private var placeBack: (from: (Double, Double), to: (Double, Double), t0: TimeInterval)? = nil
  func placeEnd() {
    guard let m = held else { return }
    held = nil
    if let at = placeAt, let gm = g, !engine.canPlace(gm, at.0, at.1), !reduceMotion { placeBack = (at, m.last, now) } else { placeAt = nil }
    if m.moved, let gm = g {
      g = engine.placeCue(gm, m.last.0, m.last.1)
      aimAtNearest()
    }
  }
  func stepPlaceBack() {
    guard let b = placeBack else { return }
    if rolling != nil { placeBack = nil; placeAt = nil; return }
    let u = min(1, max(0, (now - b.t0) / (TableModel.PLACE_BACK_MS / speed))), e = 1 - pow(1 - u, 3)
    placeAt = (b.from.0 + (b.to.0 - b.from.0) * e, b.from.1 + (b.to.1 - b.from.1) * e)
    if u >= 1 { placeBack = nil; placeAt = nil }
  }
  /* ball in hand: held the cue ball to (x, y), and put it there if it fits */
  func place(_ x: Double, _ y: Double) {
    guard inHand, rolling == nil, !cpuTurn, let c = balls.first(where: { $0.n == cueN }) else { return }
    if let gm = g {
      placeBack = nil
      if held == nil { held = (false, (c.x, c.y)) }
      let px = min(max(x, -0.02), sim.TL + 0.02), py = min(max(y, -0.02), sim.TW + 0.02)
      placeAt = (px, py)
      guard engine.canPlace(gm, px, py) else { return }
      c.x = px; c.y = py; held = (true, (px, py))
      return
    }
    let R = sim.BALL_R, lo = R + 0.001
    let px = min(max(x, lo), sim.TL - lo), py = min(max(y, lo), sim.TW - lo)
    if balls.contains(where: { $0 !== c && $0.on && JSMath.hypot($0.x - px, $0.y - py) < 2 * R }) { return }
    c.x = px; c.y = py
  }

  /* 4c: a pot runs on into its drop over POT_MS, shrinking and darkening under the rim */
  static let POT_MS = 0.420
  /* felt.speed: an exhibition runs at 1x, 2x or 4x (the physics' steps a frame, the stroke, the drops, the think) */
  var speed = 1.0
  var potMs: Double { TableModel.POT_MS / speed }
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
    var c = Prefs.callConfig
    if let cc = t.call { c = cc }
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
    let c = Prefs.callConfig
    var gm = engine.newGame(k, rules: makeRules(k, ruleset: P.ruleset, call: c, locked: true, players: P.names.count))
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
  /* newStats: the game's numbers for the game-over sheet: shots, fouls, legal pots, the best visit, each player's moments,
     the break, and the last shot's moments and shooter */
  struct GStats { var shots = [0, 0, 0, 0], fouls = [0, 0, 0, 0], pots = [0, 0, 0, 0], best = [0, 0, 0, 0], notes: [[String: Int]] = [[:], [:], [:], [:]]
    var brk: (p: Int, down: Int, foul: Bool)? = nil, last: [String] = [], lastP: Int? = nil }
  @ObservationIgnored private(set) var stats = GStats()
  /* a new stats each game (the page's stats object): the turn is spoken again when a game starts (railSayTurn's key) */
  @ObservationIgnored private(set) var statsN = 0
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
      return (SeatWords.bumperMeta(gm, p), on.filter { bOwner($0) == p }.sorted(), false)
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
  /* rackTally (6b2): a match raced in racks (a career or tournament match), player p's racks won and the race, 7 at most */
  func rackTally(_ p: Int) -> (Int, Int)? {
    guard let t = tmatch, !t.done, !t.points, g?.mode == nil, t.need > 1, t.need <= 7, p <= 1 else { return nil }
    return (t.score[p], t.need)
  }

  /* VoiceOver at the table (issue #4). The status line (#msg, polite) is spoken when it changes, its own turn words
     ("Player 2 to shoot.") left out when the turn will be spoken (say, railWillSay); then the turn, once (#railSay,
     railSayTurn: "Player 2's turn, solids"), when the shooter changes or a game starts, never as the aim moves. Both
     queued behind other speech (polite: AnnouncementPriority low). The seats and the potted windows are elements over
     the canvas (railAX, potAX: TableCanvas records them as it draws, RailAX shows them) */
  struct SeatAX: Equatable { let id: String, rect: CGRect, words: String }
  var railAX: [SeatAX] = []
  var potAX: SeatAX? = nil
  @ObservationIgnored private var saidMsg = ""
  @ObservationIgnored private var railSayKey: (stats: Int, p: Int)? = nil
  /* the words spoken, newest last (a test hook: `-felt-aimprobe`'s vo-probe) */
  @ObservationIgnored private(set) var voSaid: [String] = []
  /* the turn is spoken in a game on: not a solo session (practice, a trick shot, a drill, the lesson, a tutorial), not over */
  private var railSayOn: Bool { guard let gm = g else { return false }; return gm.winner == nil && gm.mode == nil && tut == nil && lesson == nil }
  private func voTick() {
    let on = railSayOn, turn = g?.turn ?? 0
    let will = on && !(railSayKey.map { $0.stats == statsN && $0.p == turn } ?? false)
    if msg != saidMsg {
      saidMsg = msg
      announce(will ? SeatWords.unspoken(msg, turn: Words.turnOf(turn)) : msg)
    }
    guard on, let gm = g else { railSayKey = nil; return }
    if !will { return }
    railSayKey = (statsN, turn)
    let who = cpuLevel != nil ? (turn == 0 ? "Your turn" : "CPU's turn") : "\(Words.nameOf(turn))'s turn"
    announce(SeatWords.turn(gm, turn, who: who, tally: rackTally(turn)))
  }
  private func announce(_ t: String) {
    if t.isEmpty { return }
    voSaid = Array((voSaid + [t]).suffix(8))
    var a = AttributedString(t)
    a.accessibilitySpeechAnnouncementPriority = .low
    AccessibilityNotification.Announcement(a).post()
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
  /* the roll in (POT_SLIDE_MS): a pot to roll up into its window when it first shows (potSlideDue; never on the first
     look at a game, nor under Reduce Motion), and when its roll began (potSlideT) */
  @ObservationIgnored var potSlideDue: Set<Int> = []
  @ObservationIgnored var potSlideT: [Int: TimeInterval] = [:]
  @ObservationIgnored private var potTracking = false
  private func potTrack() {
    guard let gm = g, ["8", "9", "10", "heyball"].contains(gm.kind) else { potOrder = []; potTracking = false; potSlideDue = []; potSlideT = [:]; return }
    let src = rolling?.balls.map { ($0.n, $0.on) } ?? gm.balls.map { ($0.n, $0.on) }
    let off = src.filter { !$0.1 && $0.0 >= 1 && $0.0 <= 15 }.map { $0.0 }
    let fresh = !potTracking
    potTracking = true
    potOrder = potOrder.filter { off.contains($0) }
    for n in off.filter({ !potOrder.contains($0) }).sorted() {
      potOrder.append(n); potBy[n] = gm.turn; potAt[n] = rolling != nil ? now + potMs : 0
      potSlideT[n] = nil
      if !reduceMotion && !fresh { potSlideDue.insert(n) } else { potSlideDue.remove(n) }
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
  /* the frames the pop-ups stand by (callMenuPlace, openElev): the power bar, the english pad and the stage, in the
     screen's own space (TableScreen.UI, before a phone on its side turns it a quarter), the column's [0] and the strip's [1] */
  var barUI: [CGRect] = [.zero, .zero]
  var padUI: [CGRect] = [.zero, .zero]
  var stageUI = CGRect.zero
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
    callTick()
  }
  /* a tap on a pocket: the called pocket (the ball from the aim when none is picked yet) */
  func pickPocket(_ k: Int) {
    guard callOn, !callLocked, let gm = g else { return }
    callSafe = false
    if callMan == nil || callMan!.ball == nil {
      let t = engine.legalTargets(gm)
      var c = ShotCall(); c.ball = obviousCall()?.ball ?? (t.count == 1 ? t[0] : nil); c.pocket = k; callMan = c
    } else { callMan!.pocket = k }
    callTick()
  }
  /* Change Call (or Clear): the aim's call goes, the player taps the ball and the pocket; a safety or push-out is undone */
  func changeCall() {
    guard callable else { return }
    if callPushOn { callPushOn = false; return }
    if callSafe { callSafe = false; return }
    if callLocked { return }
    callMan = ShotCall(); callAutoOff = true
    callTick()
  }
  func toggleFlag(_ f: String) {
    guard callOn, !callLocked else { return }
    if callMan == nil { var c = ShotCall(); if let h = humanCall(), h.ball != nil { c.ball = h.ball; c.pocket = h.pocket }; callMan = c }
    switch f { case "bank": callMan!.bank.toggle(); case "kick": callMan!.kick.toggle(); default: callMan!.combo.toggle() }
    callTick()
  }
  func toggleSafety() { guard callOn else { return }; callSafe.toggle(); callPushOn = false; callTick() }
  func togglePush() { guard pushOffer else { return }; callPushOn.toggle(); callSafe = false; callTick() }
  /* Called-Shot Sound (settings.calls.sound): a tap's tick for each pick */
  func callTick() { if Prefs.callUI.sound { sound.cue("tap") } }
  /* takeCall's confirmation (Show Declaration Confirmation): the call as committed, over the table a moment ("Called: 3
     in top left corner"); the CPU's says whose */
  func confirmCall(_ c: ShotCall?) {
    guard let c, let gm = g, POCKET_KINDS.contains(gm.kind), gm.mode == nil, tut == nil, Prefs.callUI.confirm, c.ball != nil || c.safety || c.push else { return }
    flashDue = (callName(c, words: { self.pocketWords($0, upright: self.uprightView) }).replacingOccurrences(of: "Calling: ", with: "Called: "), cpuTurn ? Words.nameOf(gm.turn) : "", 0.8)
  }
  /* Invalid-Shot Warnings (callSay's warnT): why the player's call cannot stand, "" when it can or the warnings are off */
  var callWarnNow: String { g.map { engine.callWarn($0, humanCall(), on: Prefs.callUI.warn) } ?? "" }
  /* hudCallHist (Declaration History): the pause menu's line on the calls so far, nil when off or none */
  var callHist: String? {
    guard Prefs.callUI.history, let gm = g, gm.mode == nil else { return nil }
    return callHistWords(gm.calls, cpu: Words.cpuMode, words: { self.pocketWords($0, upright: self.uprightView) })
  }
  /* setSetting('calls.*'): a game in progress follows the new calls, unless an event locked its own */
  func syncCallPrefs() {
    guard var gm = g, !gm.rules.locked, POCKET_KINDS.contains(gm.kind) else { return }
    let c = Prefs.callConfig
    if gm.rules.call != c { gm.rules.call = c; g = gm; resetCall() }
  }
  /* a pocket in words as the player sees the table (pocketWords): top-down from the screen, "top left corner", "right
     side"; in 3D from the player's camera (pocketFrame), "far left corner", "near side" */
  func pocketWords(_ k: Int, upright: Bool) -> String {
    if v3Live, let w = v3Words, w.count == sim.POCKET_AIM.count { return w[k] }
    let p = sim.POCKET_AIM[k]
    let f = upright ? p[0] - sim.TL / 2 : sim.TW / 2 - p[1], r = upright ? p[1] - sim.TW / 2 : p[0] - sim.TL / 2
    let e = 0.01, v = f > e ? "top" : f < -e ? "bottom" : "", h = r < -e ? "left" : r > e ? "right" : ""
    return k == 1 || k == 4 ? "\(v.isEmpty ? h : v) side" : "\(v) \(h) corner"
  }
  /* pocketCell: pocket k's cell [row, column] in a 3 x 3 picture of the table as the player sees it */
  func pocketCell(_ k: Int, upright: Bool) -> [Int] { V3.pocketCell(pocketWords(k, upright: upright)) }
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
    if gm.striker != n { gm.striker = n; g = gm; syncBalls(); picked = true; aimAtNearest(keep: true) }
    return true
  }

  /* railNext (6b2): the ball to play next on a human's turn while aiming. 9, 10 and rotation: the ball on; 8-ball,
     Chinese 8-ball and 14.1: the ball the aim meets first when it is a legal target */
  func railNext() -> Int? {
    /* none in practice (or any solo mode) */
    guard let gm = g, gm.mode == nil, gm.winner == nil, rolling == nil, stroke == nil, !cpuTurn, POCKET_KINDS.contains(gm.kind) else { return nil }
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
    let p = TablePainter(sim: sim, view: m.view, dpr: 1, rail: m.rail, look: TableLook.of(dress))
    potGeo = (p, m.k)
    return p
  }

  /* the guide (4d): aimTrace's first contact and the shot preview, run whole on a copy of the balls at
     the power the shot will have (the live pull, else the last shot's: markPower), cached on aim,
     power, spin and layout as shotPreview keys it */
  var markPower = 0.5
  /* shotPreview: the preview for this aim, power, spin and layout, double-buffered so the guide never shows a path half
     grown: pvDone is the last complete one, the one drawn; pvWork the next, run for at most PV_BUDGET ms a frame and
     swapped in only when done. A change of aim, power or spin restarts the work unless it has already run PV_STALE
     frames: then it finishes first (a sweep that never rests still updates the paths every couple of frames) and the
     newest aim starts after it. The key snaps the aim to PV_SNAP rad and the power and spin to fine steps; the layout
     (every ball but the cue ball, and the guide length) is the hard part: a preview of another layout is never drawn,
     and with none of this layout yet the work runs up to PV_SYNC ms at once, so a turn's first frame has its paths.
     The ghost ball and the aim line come from aimTrace every frame. pvShift: a preview a frame or two behind a moving
     aim that still meets the same ball or cushion moves its cue ball path with the ghost ball (guideLines' same). */
  static let PV_BUDGET = 3.0, PV_BUDGET_MAX = 5.0, PV_SYNC = 12.0, PV_STALE = 2, PV_SNAP = 2e-5
  final class PvWork {
    let P: Preview, key: [Double], lay: [Double], ang: Double, gx: Double, gy: Double, hk: String, hb: Int
    var frames = 0
    init(P: Preview, key: [Double], lay: [Double], ang: Double, gx: Double, gy: Double, hk: String, hb: Int) { self.P = P; self.key = key; self.lay = lay; self.ang = ang; self.gx = gx; self.gy = gy; self.hk = hk; self.hb = hb }
  }
  @ObservationIgnored private var pvDone: PvWork?
  @ObservationIgnored private var pvWork: PvWork?
  @ObservationIgnored private var pvFrame = -1
  @ObservationIgnored private var pvLast: (AimHit, Preview)?
  @ObservationIgnored private(set) var pvShift = (0.0, 0.0)
  /* this frame's aimTrace: the line and the ghost follow the aim even while no complete preview of the layout exists */
  @ObservationIgnored private(set) var aimHit: AimHit?
  func guide() -> (AimHit, Preview)? {
    let gt0 = CACurrentMediaTime()
    defer { if TableModel.touchBench || TableModel.aimBench { let d = (CACurrentMediaTime() - gt0) * 1000; if d > 8 { print(String(format: "felt-bench slow guide %.1f ms", d)) } } }
    guard rolling == nil, let c = cue else { return nil }
    /* once a frame: the loupe asks again in the same frame */
    if pvFrame == frame { return pvLast }
    pvFrame = frame
    let pw = power > 0 ? power : markPower, q = { (v: Double, s: Double) in (v / s).rounded() }
    let lens = game == .carom ? PV_CAROM : guideMode == "short" ? PV_SHORT : PV_FULL
    var lay = [lens[0]]
    for b in balls where b.n != cueN { lay += b.on ? [b.x, b.y] : [-1] }
    let key = [q(aim, TableModel.PV_SNAP), q(pw, 0.001), q(spin.x, 0.005), q(spin.y, 0.005), q(spin.e, 0.002), c.x, c.y]
    let dx = JSMath.cos(aim), dy = JSMath.sin(aim)
    let h = sim.aimTrace(balls, c.x, c.y, dx, dy, skip: [cueN], far: 6)
    let have = pvDone.map { $0.lay == lay } ?? false
    if have, pvDone!.key == key { pvWork = nil }
    else {
      let t0 = CACurrentMediaTime()
      if pvWork == nil || pvWork!.lay != lay || (pvWork!.key != key && (!have || pvWork!.frames < TableModel.PV_STALE)) {
        let P = sim.previewStart(balls, cueN: cueN, aim, pw, spin, h, lens, caromNeed: game == .carom ? (g?.need ?? 3) : 0)
        pvWork = PvWork(P: P, key: key, lay: lay, ang: aim, gx: c.x + dx * h.t, gy: c.y + dy * h.t, hk: h.kind, hb: h.ball?.n ?? -1)
      }
      /* the budget: 55% of the frame, 3 to 5 ms (at 120 Hz 4.6 of 8.3 ms, the draw about 1.5): at 1.5 ms a long
         preview took 10-16 frames on the phone and the paths ran 16 deg behind a sweep */
      let W = pvWork!, ms = have ? min(TableModel.PV_BUDGET_MAX, max(TableModel.PV_BUDGET, frameGap * 1000 * 0.55)) : TableModel.PV_SYNC
      W.frames += 1
      sim.previewRun(W.P) { (CACurrentMediaTime() - t0) * 1000 > ms }
      if TableModel.aimBench || TableModel.touchBench { Bench.pvMs += (CACurrentMediaTime() - t0) * 1000 }
      if W.P.done { if TableModel.aimBench || TableModel.touchBench { Bench.pvFrames.append(W.frames) }; pvDone = W; pvWork = nil }
    }
    aimHit = h
    guard let D = pvDone, D.lay == lay else { pvLast = nil; pvShift = (0, 0); return nil }
    let gx = c.x + dx * h.t, gy = c.y + dy * h.t
    let same = D.hb == (h.ball?.n ?? -1) && D.hk == h.kind && (h.kind == "ball" || h.kind == "rail") && D.P.cuePot < 0 && abs(D.ang - aim) < 0.03
    pvShift = same ? (gx - D.gx, gy - D.gy) : (0, 0)
    if TableModel.aimBench || TableModel.touchBench { Bench.pvLag = max(Bench.pvLag, abs(AimFeel.wrap(D.ang - aim)) * 180 / .pi); Bench.pvN += 1 }
    pvLast = (h, D.P)
    return pvLast
  }
}

/* the aim bench: how many times each counted view's body ran (`-felt-aimbench`) */
@MainActor enum Bench {
  static var bodies: [String: Int] = [:]
  static func hit(_ k: String) { if TableModel.aimBench || TableModel.touchBench { bodies[k, default: 0] += 1 } }
  /* the table canvas's draw times since the last print (seconds) */
  static var draws: [Double] = []
  static func draw(_ d: Double) { draws.append(d) }
  static var pvFrames: [Int] = [], pvLag = 0.0, pvMs = 0.0, pvN = 0
  static func pvWords() -> String {
    defer { pvFrames = []; pvLag = 0; pvMs = 0; pvN = 0 }
    let f = pvFrames.sorted()
    return String(format: "previews %d (frames each median %d, max %d), worst lag %.2f deg, preview work %.1f ms/frame", f.count, f.isEmpty ? 0 : f[f.count / 2], f.last ?? 0, pvLag, pvMs / Double(max(1, pvN)))
  }
  static func drawWords() -> String {
    guard !draws.isEmpty else { return "no draws" }
    let s = draws.sorted(), mean = s.reduce(0, +) / Double(s.count)
    defer { draws = [] }
    return String(format: "draw mean %.2f ms, p95 %.2f ms, max %.2f ms", mean * 1000, s[Int(Double(s.count - 1) * 0.95)] * 1000, s.last! * 1000)
  }
}
