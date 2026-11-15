/* index.html sim 1l, tutorials: each game's rules, played. One short tutorial per game, each a few steps: a fixed layout
   on the tutorial's own table built from table fractions and the trick shots' helpers, a game state for it (setup), and
   a goal judged by the real rules (goal(g, r, n): the game before the shot, its result and judge(g, r); nil when the step
   is done, else why not). Nothing here is a mode: the game is an ordinary game. Step fields as the page's: head, text(c)
   (c the context: 8-ball's group, solids until the first step picks it), balls, setup, goal, aim, pocket, pick, ring,
   done, then, demo, swap (8-ball: the numbers follow the group), places, flash, natural. TUT_SOLS: one stored winning
   shot per step. Line for line. */
import Foundation

private typealias M = JSMath

/* what the coach rings: a ball, a pocket, a colour's spot, an element ("snkBar"), the D, the rail's diamonds */
public struct TutRing: Equatable, Sendable { public var kind: String, n: Int = 0 }
public struct TutStep: Sendable {
  public var head: String
  public var text: @Sendable (String) -> String
  var balls: @Sendable (TrickHelpers, Sim) -> [(Int, [Double])]
  var setup: (@Sendable (inout Game, String) -> Void)? = nil
  var goal: @Sendable (RulesEngine, Game, RuleShot, Game) -> String?
  public var aim: Int? = nil, pocket: Int? = nil, pick: Int? = nil
  public var ring: @Sendable (Game, Bool) -> TutRing = { _, _ in TutRing(kind: "none") }
  public var done: (@Sendable (Game) -> [String])? = nil
  public var then: (text: @Sendable () -> String, ring: @Sendable (Game) -> TutRing)? = nil
  public var demo = false, swap = false, natural = false
  public var places: (@Sendable (TrickHelpers) -> [[Double]])? = nil
  public var flash: [String]? = nil
}
public struct Tutorial: Sendable {
  public let id: String, kind: String, name: String, table: [String], pockets: String
  public var steps: [TutStep]
  /* ctx: the group 8-ball's steps follow (solids until the first step picks it); nil for the rest */
  public var ctx: String? = nil
}

private func TUT_FOUL(_ v: Verdict) -> String { v.foul.map { "Foul: \($0)." } ?? "" }
private func nz(_ s: String) -> String? { s.isEmpty ? nil : s }
public func swapGroup(_ n: Int) -> Int { n > 0 && n < 8 ? n + 8 : n > 8 && n < 16 ? n - 8 : n }
private func legalPot(_ n: Game, _ ok: (Int) -> Bool) -> String? { let v = n.verdict!; return nz(TUT_FOUL(v)) ?? (v.potted.contains(where: ok) && n.turn == 0 ? nil : "Nothing of yours went down.") }
/* carom's "why no point", in words */
func caromNo(_ c: CaromCount, _ need: Int) -> String {
  c.balls.isEmpty ? "No ball hit." : c.balls.count < 2 ? "Only one ball." : "\(c.cushions) cushion\(c.cushions == 1 ? "" : "s") before the second ball: it needs \(need)."
}
/* snooker's layouts: k reds from n up in a loose pack past the blue, and the colours on their spots */
private func snkReds(_ T: TrickHelpers, _ n: Int, _ k: Int) -> [(Int, [Double])] {
  [[0.62, 0.38], [0.66, 0.5], [0.64, 0.64], [0.7, 0.42], [0.71, 0.58], [0.68, 0.3]].prefix(k).enumerated().map { i, f in (n + i, T.at(f[0], f[1])) }
}
private func snkColours(_ s: Sim) -> [(Int, [Double])] { S_COLS.map { ($0, s.SPOTS[$0]!) } }
private func other(_ c: String) -> String { c == "solids" ? "stripes" : "solids" }
private func groups(_ g: inout Game, _ c: String) { g.open = false; g.groups = [c, other(c)] }

private let EIGHT: [TutStep] = [
  TutStep(head: "Open table", text: { _ in "The table is open: pot any ball but the 8, and its group is yours." },
    balls: { T, _ in [(0, T.at(0.55, 0.5)), (3, T.lip(2, 5)), (11, T.lip(5, 5)), (8, T.at(0.3, 0.3)), (1, T.at(0.2, 0.75)), (6, T.at(0.38, 0.84)), (10, T.at(0.13, 0.22)), (14, T.at(0.42, 0.14))] },
    goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? (n.groups[0] != nil ? nil : "Nothing went down.") },
    aim: 3, pocket: 2, ring: { _, _ in TutRing(kind: "ball", n: 3) }, done: { n in ["You're \(n.groups[0] ?? "")", "and you shoot again"] }),
  TutStep(head: "Your group first", text: { c in "You're \(c): hit one of yours first. The \(c == "solids" ? "stripe" : "solid") nearest you is not yours." },
    balls: { T, _ in [(0, T.at(0.3, 0.5)), (12, T.at(0.4, 0.66)), (4, T.lip(2, 5)), (9, T.at(0.7, 0.82)), (15, T.at(0.12, 0.22)), (8, T.at(0.78, 0.7)), (6, T.at(0.2, 0.85))] },
    setup: { g, c in groups(&g, c) },
    goal: { E, g, _, n in legalPot(n) { E.groupOf($0) == g.groups[0] } },
    aim: 4, pocket: 2, ring: { _, _ in TutRing(kind: "ball", n: 4) }, done: { _ in ["Your ball, first", "that is a legal shot"] }, swap: true),
  TutStep(head: "Ball in hand", text: { c in "Your opponent fouled, so you have ball in hand. Drag the cue ball anywhere, then pot a \(c == "solids" ? "solid" : "stripe")." },
    balls: { T, _ in [(0, T.at(0.035, 0.6)), (5, T.lip(5, 4)), (14, T.at(0.1, 0.5)), (10, T.at(0.1, 0.64)), (2, T.at(0.45, 0.25)), (8, T.at(0.62, 0.5)), (13, T.at(0.8, 0.2))] },
    setup: { g, c in groups(&g, c); g.inHand = "table" },
    goal: { E, g, _, n in legalPot(n) { E.groupOf($0) == g.groups[0] } },
    aim: 5, pocket: 5, ring: { _, moved in moved ? TutRing(kind: "ball", n: 5) : TutRing(kind: "ball", n: 0) }, done: { _ in ["Ball in hand", "put it where the shot is easy"] }, swap: true,
    places: { T in let b = T.lip(5, 4); return [T.line(b, 5, 12), T.line(b, 5, 16), T.line(b, 5, 9)] }, flash: ["Foul by your opponent", "Ball in hand anywhere"]),
  TutStep(head: "The 8 last", text: { c in "Your \(c) are all down, so the 8 is yours. Pot it to win the rack." },
    balls: { T, _ in [(0, T.at(0.62, 0.4)), (8, T.lip(2, 6)), (9, T.at(0.3, 0.75)), (13, T.at(0.18, 0.3)), (15, T.at(0.5, 0.85))] },
    setup: { g, c in groups(&g, c) },
    goal: { _, _, _, n in n.winner == 0 ? nil : n.winner == 1 ? "The 8 went down on a foul: that loses the rack." : nz(TUT_FOUL(n.verdict!)) ?? "The 8 stayed up." },
    aim: 8, pocket: 2, ring: { _, _ in TutRing(kind: "ball", n: 8) }, swap: true),
]

public let TUTORIALS: [Tutorial] = [
  Tutorial(id: "8", kind: "8", name: "8-ball", table: ["7"], pockets: "regulation", steps: EIGHT, ctx: "solids"),
  Tutorial(id: "9", kind: "9", name: "9-ball", table: ["7"], pockets: "regulation", steps: [
    TutStep(head: "Lowest ball first", text: { _ in "Hit the lowest ball on the table first: here, the 2. Pot it." },
      balls: { T, _ in [(0, T.at(0.45, 0.6)), (2, T.lip(5, 5)), (5, T.at(0.42, 0.3)), (7, T.at(0.76, 0.24)), (9, T.at(0.25, 0.25)), (4, T.at(0.2, 0.8))] },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? (!n.verdict!.potted.isEmpty ? nil : "Nothing went down.") },
      aim: 2, pocket: 5, ring: { _, _ in TutRing(kind: "ball", n: 2) }, done: { _ in ["The 2, first", "now the lowest is the 4"] }),
    TutStep(head: "Combination", text: { _ in "Any ball you pot counts, as long as you hit the lowest first. Play the 3 into the 6." },
      balls: { T, _ in let b = T.lip(2, 3), a = T.line(b, 2, 6); return [(0, T.line(a, 2, 16)), (3, a), (6, b), (9, T.at(0.25, 0.8)), (8, T.at(0.2, 0.3)), (5, T.at(0.6, 0.85))] },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? (n.verdict!.potted.contains(6) ? nil : "The 6 stayed up.") },
      aim: 3, pocket: 2, ring: { _, _ in TutRing(kind: "ball", n: 6) }, done: { _ in ["Combination", "the 6 counts: the 3 was hit first"] }),
    TutStep(head: "The 9 wins", text: { _ in "The 9 wins the rack whenever it drops on a legal shot. Hit the 4 into the 9." },
      balls: { T, _ in let b = T.lip(5, 3), a = T.line(b, 5, 6); return [(0, T.off(T.line(a, 5, 14), 0, -2)), (4, a), (9, b), (7, T.at(0.25, 0.25)), (6, T.at(0.3, 0.8))] },
      goal: { _, _, _, n in n.winner == 0 ? nil : nz(TUT_FOUL(n.verdict!)) ?? "The 9 stayed up." },
      aim: 4, pocket: 5, ring: { _, _ in TutRing(kind: "ball", n: 9) }),
  ]),
  Tutorial(id: "bumper", kind: "bumper", name: "Bumper pool", table: ["bumper", "octagon"], pockets: "regulation", steps: [
    TutStep(head: "The marked ball", text: { _ in "You play red, and your marked ball (the spot) goes first: tap it to strike it. Send it to the far cup." },
      balls: { _, _ in [(22, [0.3, 0.27]), (21, [0.93, 0.32]), (23, [0.22, 0.74]), (24, [0.45, 0.2]), (25, [0.4, 0.8]), (31, [0.62, 0.8]), (32, [0.75, 0.25]), (33, [0.92, 0.75]), (34, [0.32, 0.65]), (35, [0.68, 0.7])] },
      setup: { g, _ in g.striker = 22 },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? (n.verdict!.potted.contains(21) ? nil : "The marked red stayed up.") },
      aim: 21, pocket: 1, pick: 21, ring: { g, _ in g.striker == 21 ? TutRing(kind: "pocket", n: 1) : TutRing(kind: "ball", n: 21) }, done: { _ in ["Marked ball down", "now any red may go"] }),
    TutStep(head: "Round the posts", text: { _ in "The posts guard the cup: straight in is blocked. Bank off a cushion and come in from the back." },
      balls: { _, _ in [(22, [0.62, 0.2]), (23, [0.22, 0.74]), (24, [0.45, 0.16]), (25, [0.4, 0.8]), (31, [0.62, 0.8]), (33, [0.8, 0.84]), (34, [0.32, 0.65]), (35, [0.68, 0.7])] },
      setup: { g, _ in g.striker = 22 },
      goal: { _, _, r, n in nz(TUT_FOUL(n.verdict!)) ?? (!n.verdict!.potted.contains(22) ? "The red stayed up." : (r.rails?[22] ?? 0) < 1 ? "In, but no bank: off a cushion this time." : nil) },
      pocket: 1, ring: { _, _ in TutRing(kind: "pocket", n: 1) }, done: { _ in ["Banked in", "round the posts"] }),
    TutStep(head: "Your own cup", text: { _ in "The cup behind you is your own: a ball in it is a foul. Tap Show me to see what it costs." },
      balls: { _, _ in [(23, [0.21, 0.25]), (24, [0.45, 0.16]), (25, [0.4, 0.8]), (31, [0.62, 0.8]), (33, [0.8, 0.84]), (34, [0.32, 0.65]), (35, [0.68, 0.7])] },
      setup: { g, _ in g.striker = 23 },
      goal: { _, _, _, n in n.verdict!.foul == "into your own cup" ? nil : "Tap Show me to watch it." },
      pocket: 0, ring: { _, _ in TutRing(kind: "pocket", n: 0) },
      then: ({ "Foul. Your red comes back to your marked spot, white drops one of theirs in for free, and the turn passes." }, { n in TutRing(kind: "ball", n: n.verdict?.bumper?.back.first ?? 0) }), demo: true),
    TutStep(head: "The right way", text: { _ in "Now pot a red in the far cup, coming in from behind the posts." },
      balls: { _, _ in [(23, [0.93, 0.72]), (24, [0.45, 0.16]), (25, [0.4, 0.8]), (31, [0.62, 0.8]), (33, [0.7, 0.9]), (34, [0.32, 0.65]), (35, [0.68, 0.7])] },
      setup: { g, _ in g.striker = 23 },
      goal: { _, _, _, n in legalPot(n) { _ in true } },
      aim: 23, pocket: 1, ring: { _, _ in TutRing(kind: "pocket", n: 1) }),
  ]),
  Tutorial(id: "carom", kind: "carom", name: "Three-cushion", table: ["carom"], pockets: "regulation", steps: [
    TutStep(head: "One cushion", text: { _ in "A point: your white meets both other balls, with a cushion before the second. The guide's dots show the cushions." },
      balls: { T, _ in [(70, T.at(0.4, 0.45)), (72, T.at(0.62, 0.12)), (71, T.at(0.74, 0.12))] },
      setup: { g, _ in g.need = 1 },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? (n.verdict!.carom!.point ? nil : caromNo(n.verdict!.carom!.count, 1)) },
      aim: 72, ring: { _, _ in TutRing(kind: "ball", n: 71) }, done: { _ in ["Point", "one cushion before the second ball"] }),
    TutStep(head: "Three cushions", text: { _ in "The real game: three cushions before the second ball. Follow the guide's line round the table." },
      balls: { T, _ in [(70, T.at(0.3, 0.3)), (72, T.at(0.45, 0.22)), (71, T.at(0.08, 0.86))] },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? (n.verdict!.carom!.point ? nil : caromNo(n.verdict!.carom!.count, 3)) },
      aim: 72, ring: { _, _ in TutRing(kind: "ball", n: 71) }, done: { _ in ["Point", "three cushions"] }, natural: true),
    TutStep(head: "A system shot", text: { _ in "Cushions first: aim at the ringed spot by the diamonds, and the table brings it round to both balls." },
      balls: { T, _ in [(70, T.at(0.2, 0.2)), (72, T.at(0.86, 0.84)), (71, T.at(0.93, 0.72))] },
      goal: { _, _, r, n in nz(TUT_FOUL(n.verdict!)) ?? (!((r.seq.first ?? 0) < 0) ? "Cushion first this time." : n.verdict!.carom!.point ? nil : caromNo(n.verdict!.carom!.count, 3)) },
      ring: { _, _ in TutRing(kind: "rail") }),
  ]),
  Tutorial(id: "snooker", kind: "snooker", name: "Snooker", table: ["snooker", "compact"], pockets: "regulation", steps: [
    TutStep(head: "On a red", text: { _ in "You're on a red: the bar on the top rail says so. Pot a red for 1 point." },
      balls: { T, s in [(0, T.at(0.62, 0.58)), (41, T.lip(5, 5))] + snkReds(T, 42, 5) + snkColours(s) },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? ((n.verdict!.snk?.pts ?? 0) > 0 ? nil : "Nothing went down.") },
      aim: 41, pocket: 5, ring: { _, _ in TutRing(kind: "el") }, done: { _ in ["1 point", "now you are on a colour"] }),
    TutStep(head: "Then a colour", text: { _ in "After a red you're on a colour: the first one you hit. Pot the black for 7." },
      balls: { T, s in let b = T.lip(2, 6); return [(0, T.off(T.line(b, 2, 14), 0, 1.5)), (62, b)] + snkReds(T, 42, 5) + snkColours(s).filter { $0.0 != 62 } },
      setup: { g, _ in g.snk!.on = .colour; g.score = [1, 0]; g.snk!.brk = 1 },
      goal: { _, _, _, n in let v = n.verdict!; return nz(TUT_FOUL(v)) ?? (v.snk?.nom == 62 && v.snk?.pts == 7 ? nil : (v.snk?.pts ?? 0) != 0 ? "A colour, but the black this time." : "The black stayed up.") },
      aim: 62, pocket: 2, ring: { _, _ in TutRing(kind: "ball", n: 62) },
      then: ({ "Seven. While reds are left, a potted colour goes back on its spot, and you are on a red again." }, { _ in TutRing(kind: "spot", n: 62) })),
    TutStep(head: "In-off", text: { _ in "Your opponent went in-off: 4 points to you, and ball in hand in the D. Place the cue ball in the D, then pot a red." },
      balls: { T, s in
        let c: (Int, [Double]) = (0, [s.HEAD_X - 0.02, s.TW / 2 - 0.5 * s.D_R]), r: (Int, [Double]) = (41, T.lip(3, 6))
        return [c, r] + snkReds(T, 42, 5) + snkColours(s)
      },
      setup: { g, _ in g.inHand = "D"; g.score = [4, 0] },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? ((n.verdict!.snk?.pts ?? 0) > 0 ? nil : "Nothing went down.") },
      aim: 41, pocket: 3, ring: { _, moved in moved ? TutRing(kind: "ball", n: 41) : TutRing(kind: "d") }, done: { _ in ["From the D", "a red, 1 point"] },
      places: { T in let b = T.lip(3, 6); return [T.line(b, 3, 23), T.line(b, 3, 22), T.line(b, 3, 24)] }, flash: ["In-off by your opponent", "Ball in hand in the D"]),
    TutStep(head: "Colours in order", text: { _ in "The reds are gone: now the colours in order, yellow first. Pot the yellow." },
      balls: { T, s in let b = T.lip(3, 5); return [(0, T.off(T.line(b, 3, 16), 2, 0)), (57, b)] + snkColours(s).filter { $0.0 != 57 } },
      setup: { g, _ in g.snk!.on = .ball(57); g.score = [40, 22] },
      goal: { _, _, _, n in nz(TUT_FOUL(n.verdict!)) ?? (n.verdict!.potted.contains(57) ? nil : "The yellow stayed up.") },
      aim: 57, pocket: 3, ring: { _, _ in TutRing(kind: "ball", n: 57) }),
  ]),
  /* Chinese 8-ball: its own table and its rules' differences, on 8-ball's own layouts where the lesson is the same */
  Tutorial(id: "heyball", kind: "heyball", name: "Chinese 8-ball", table: ["heyball"], pockets: "regulation", steps: [
    TutStep(head: "The break", text: { _ in "Break from behind the line: pot a ball or drive four to the cushions. Whatever drops, the table stays open." },
      balls: { _, s in s.rack("heyball").map { b in (b.n, b.n != 0 ? [b.x, b.y] : [s.HEAD_X * 0.8, s.TW / 2]) } },
      setup: { g, _ in g.breakShot = true; g.shots = 0 },
      goal: { _, _, _, n in n.verdict!.illegalBreak ? "Not a legal break: four balls to the cushions, or a pot." : nz(TUT_FOUL(n.verdict!)) ?? (n.option != nil ? "The 8 went down on the break." : nil) },
      aim: 1, ring: { _, _ in TutRing(kind: "ball", n: 1) }, done: { _ in ["Legal break", "and the table is still open"] }),
    { var s = EIGHT[0]; s.text = { _ in "After the break the table is open: pot any ball but the 8, and its group is yours." }; return s }(),
    EIGHT[2],
    { var s = EIGHT[3]; s.head = "The 8, any pocket"; s.text = { c in "Your \(c) are down. Pot the 8 in any pocket: nothing is called, and a fluke counts." }
      s.goal = { _, _, _, n in n.winner == 0 ? nil : n.winner == 1 ? "The 8 went down on a foul: that loses the rack." : nz(TUT_FOUL(n.verdict!)) ?? "The 8 stayed up." }; return s }(),
  ], ctx: "solids"),
]
public func tutById(_ id: String) -> Tutorial? { TUTORIALS.first { $0.id == id } }
/* a step's number (aim, pocket's ball, pick) as the context has it */
public func tutNum(_ t: Tutorial, _ i: Int, _ c: String?, _ n: Int?) -> Int? { n.map { t.steps[i].swap && c == "stripes" ? swapGroup($0) : $0 } }

public let TUT_SOLS: [String: [[Double]]] = [
  "8": [[0.418879, 0.38, 0, 0], [1.980949, 0.3, 0, 0], [0.820305, 0.22, 0, 0, 1.615037, 0.625037], [-0.340339, 0.38, 0, 0]],
  "9": [[0.235619, 0.3, 0, 0], [-0.794125, 0.38, 0, 0], [0.890118, 0.3, 0, 0]],
  "bumper": [[1.492257, 0.55, -0.5, 0, 21], [0.506145, 0.22, 0, 0, 22], [1.937315, 0.15, 0, 0, 23], [-1.902409, 0.15, 0, 0, 23]],
  "carom": [[-0.829031, 0.38, 0, 0], [-1.37881, 1, 0, 0], [-2.975786, 0.65, 0.5, 0]],
  "snooker": [[0.445059, 0.38, 0, 0], [-0.872665, 0.22, 0, 0], [2.356194, 0.65, 0, 0, 0.570105, 0.911562], [2.443461, 0.22, 0, 0]],
  "heyball": [[-0.008727, 0.65, 0, 0], [0.436332, 0.3, 0, 0], [0.776672, 0.22, 0, 0, 2.184891, 0.904891], [-0.383972, 0.3, 0, 0]],
]
/* tutSol: the stored solution of a step as a shot, its placement (ball in hand) and the ball to strike (bumper pool) */
public func tutSol(_ id: String, _ i: Int) -> (shot: Sim.Shot, place: [Double]?, ball: Int?)? {
  guard let a = TUT_SOLS[id], i < a.count else { return nil }
  let s = a[i]
  return (Sim.Shot(angle: s[0], power: s[1], spin: Spin(x: s[2], y: s[3])), s.count >= 6 ? [s[4], s[5]] : nil, s.count == 5 ? Int(s[4]) : nil)
}

extension RulesEngine {
  /* a step's balls for the current table, with 8-ball's numbers swapped for stripes */
  public func tutBalls(_ t: Tutorial, _ i: Int, _ c: String?) -> [GBall] {
    let st = t.steps[i], sw = st.swap && c == "stripes"
    return st.balls(TrickHelpers(s: sim), sim).map { GBall(n: sw ? swapGroup($0.0) : $0.0, x: $0.1[0], y: $0.1[1]) }
  }
  /* a step's game: an ordinary game of the tutorial's kind on its layout, player 0 to shoot, no break */
  public func tutGame(_ t: Tutorial, _ i: Int, _ c: String?) -> Game {
    let st = t.steps[i]
    var g = t.kind == "snooker" ? snookerGame() : t.kind == "carom" ? caromGame(cushions: 3) : newGame(t.kind)
    g.balls = tutBalls(t, i, c); g.turn = 0; g.breakShot = false; g.inHand = nil; g.shots = 1
    if t.kind == "bumper" { g.opening = 0; g.openPot = [true, true] }
    st.setup?(&g, c ?? "solids")
    return g
  }
  /* one shot of a step, judged: (ok, why, n = judge(g, r)); the game is not touched */
  public func tutJudge(_ t: Tutorial, _ i: Int, _ g: Game, _ r: RuleShot) -> (ok: Bool, why: String, n: Game) {
    let n = judge(g, r), why = t.steps[i].goal(self, g, r, n)
    return (why == nil, why ?? "", n)
  }
}
