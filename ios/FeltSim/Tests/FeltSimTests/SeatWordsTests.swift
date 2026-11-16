/* the seats', the turn's and the potted windows' words for VoiceOver (6b2, 6b3: seatWords, railSayTurn, #potSay) and the
   status line's turn words left out while the turn is spoken (say), against the page's own words */
import Testing
@testable import FeltSim

@Suite struct SeatWordsTests {
  let E = RulesEngine(sim: Sim())
  func off(_ g: inout Game, _ ns: [Int]) { for i in g.balls.indices where ns.contains(g.balls[i].n) { g.balls[i].on = false } }

  @Test func eightBall() {
    var g = E.newGame("8")
    #expect(SeatWords.seat(g, 0, name: "Player 1", next: nil) == "Player 1, open table, shooting")
    #expect(SeatWords.seat(g, 1, name: "Player 2", next: nil) == "Player 2, open table")
    g.groups = ["stripes", "solids"]
    #expect(SeatWords.seat(g, 0, name: "Player 1", next: 12, tally: (2, 5)) == "Player 1, stripes, 2 of 5 racks, shooting, next: the 12, stripe")
    #expect(SeatWords.turn(g, 0, who: "Your turn") == "Your turn, stripes")
    g.turn = 1
    #expect(SeatWords.turn(g, 1, who: "Player 2's turn") == "Player 2's turn, solids")
    off(&g, [1, 2, 3, 4, 5, 6, 7])
    /* on the 8, the 8 next: said once */
    #expect(SeatWords.seat(g, 1, name: "CPU", next: 8) == "CPU, on the 8, shooting")
  }

  @Test func nineBall() {
    var g = E.newGame("9")
    off(&g, [1, 2])
    /* the ball on is said once: the next ball is the ball on */
    #expect(SeatWords.seat(g, 0, name: "You", next: 3) == "You, on the 3, shooting")
    #expect(SeatWords.turn(g, 0, who: "Your turn") == "Your turn, on the 3")
    #expect(SeatWords.seat(g, 1, name: "CPU", next: nil) == "CPU")
    g.rules.threeFoul = "loss"; g.fouls = [0, 2]
    #expect(SeatWords.seat(g, 1, name: "CPU", next: nil) == "CPU, two fouls")
  }

  @Test func scoredGames() {
    var g = E.newGame("straight")
    g.score = [12, 3]
    #expect(SeatWords.seat(g, 0, name: "Player 1", next: 5) == "Player 1, \(12) of \(g.race!) points, shooting, next: the 5, solid")
    func on(_ t: String, _ sh: String? = nil) -> RulesEngine { let sim = Sim(); sim.setTable(t, sh); return RulesEngine(sim: sim) }
    let c = on("carom").caromGame(race: 10, cushions: 3)
    #expect(SeatWords.seat(c, 1, name: "Player 2", next: nil) == "Player 2, yellow, 0 of 10 points")
    let b = on("bumper", "octagon").bumperGame()
    #expect(SeatWords.seat(b, 0, name: "Player 1", next: nil) == "Player 1, red, 5 left, marked first, shooting")
    var s = on("snooker", "full").snookerGame(frames: 1, first: 0)
    s.score = [1, 0]; s.snk!.brk = 1; s.snk!.on = .colour
    #expect(SeatWords.seat(s, 0, name: "You", next: nil) == "You, 1 point, on a colour, break 1, shooting")
    #expect(SeatWords.seat(s, 1, name: "CPU", next: nil) == "CPU, 0 points")
  }

  /* a party of three or four (chipCount): a seat per player in turn order (pchip0 to pchip3), each a group read from
     seatWords, the ball to play on the shooter's */
  @Test func party() {
    #expect(SeatWords.seats(party: nil, mode: nil) == 2 && SeatWords.seats(party: 2, mode: nil) == 2)
    #expect(SeatWords.seats(party: 3, mode: nil) == 3 && SeatWords.seats(party: 4, mode: nil) == 4)
    #expect(SeatWords.seats(party: 4, mode: "practice") == 2)
    var g = E.newGame("9", rules: makeRules("9", ruleset: "9-ring", players: 4))
    off(&g, [1, 2])
    g.turn = 2
    let names = ["Ann", "Bo", "Cy", "Di"]
    #expect((0..<4).map { SeatWords.seat(g, $0, name: names[$0], next: $0 == g.turn ? 3 : nil) } == ["Ann", "Bo", "Cy, on the 3, shooting", "Di"])
    var r = E.newGame("rotation", rules: makeRules("rotation", ruleset: "rotation-ring", players: 3))
    r.score = [5, 12, 0]; r.turn = 1
    off(&r, [1])
    #expect((0..<3).map { SeatWords.seat(r, $0, name: names[$0], next: $0 == r.turn ? 2 : nil) }
      == ["Ann, 5 of 61 points", "Bo, on the 2, 12 of 61 points, shooting", "Cy, 0 of 61 points"])
  }

  /* placeRail's pack and group()'s far rail for a party's seats, against the page's own lines run in node */
  @Test func partyRail() {
    let near = [[12, 70.5], [84.25, 180], [194, 300.75], [314.5, 381]], far = [[12, 70.5], [84.25, 186], [207, 300.75], [314.5, 381]]
    #expect(RailRow.pack([30, 22, 41, 18], near, mid: 196.5) == [118.125, 150.125, 235.375, 270.875])
    #expect(RailRow.pack([30, 22.5, 41], near, mid: 196.5) == [132.125, 223.875, 261.625])
    #expect(RailRow.pack([60, 60, 60, 60], near, mid: 196.5) == nil)
    let p = RailRow.party([60, 60, 60, 60], near: near, far: far, mid: 196.5)!
    #expect(p.map { $0.x } == [132.125, 247.375, 347.75, 253.875] && p.map { $0.far } == [false, false, false, true])
    #expect(RailRow.party([100, 100, 100, 100], near: near, far: far, mid: 196.5) == nil)
    #expect(RailRow.party([100, 100, 100], near: near, far: nil, mid: 196.5) == nil)
  }

  /* the row of a party of three or four drawn (T7.158): each seat's centre and the 3D switch's, against placeRail's own
     free, fitIn, pack, group and side run in node over its STEPS (the switch kept, then given way) and the score keeper's
     fallback, on the same gaps and widths (px: a seat its glyphs, the .pb gaps, its padding and wOf's 1; the switch its
     glyph and padding, wOf's 1) */
  @Test func partyRow() {
    let near = [[12, 70.5], [84.25, 180], [194, 300.75], [314.5, 381]], far = [[12, 70.5], [84.25, 186], [207, 300.75], [314.5, 381]], pk = [[12.0, 180], [194, 381]]
    func row(_ ws: [Double], _ n: [[Double]], _ f: [[Double]]?, _ p: [[Double]], _ mid: Double, _ pw: Double?) -> ([Double], [Bool], Double?)? {
      let r = RailRow.many(ws, near: n, far: f, pockets: p, mid: mid, pw: pw)
      return r.seats.map { ($0.map(\.x), $0.map(\.far), r.sw) }
    }
    /* 9-ball ring at 393 wide: the shooter's ball to play (27), the others' pips (13); the switch's glyph 21 */
    var r = row([27, 13, 13], near, far, pk, 196.5, 21)!
    #expect(r.0 == [132.125, 237.875, 256.875] && r.1 == [false, false, false] && r.2 == 41.25)
    r = row([27, 13, 13, 13], near, far, pk, 196.5, 21)!
    #expect(r.0 == [122.625, 148.625, 237.875, 256.875] && r.1 == [false, false, false, false] && r.2 == 41.25)
    /* too many for the bottom rail: the last on the far rail, the switch beside the near ones */
    r = row([60, 60, 60, 60], near, far, pk, 196.5, 21)!
    #expect(r.0 == [132.125, 247.375, 347.75, 253.875] && r.1 == [false, false, false, true] && r.2 == 41.25)
    r = row([50, 50, 50], [[10, 60], [70, 180], [190, 300]], nil, [[10, 180], [190, 300]], 155, 21)!
    #expect(r.0 == [97, 153, 245] && r.2 == 35)
    /* not shown (the lesson), or no room for it: the switch gives way, the seats stay */
    r = row([27, 13, 13], near, nil, pk, 196.5, nil)!
    #expect(r.0 == [132.125, 237.875, 256.875] && r.2 == nil)
    r = row([55, 55, 55], [[0, 15], [25, 205]], nil, [[0, 205]], 110, 21)!
    #expect(r.0 == [54, 115, 176] && r.2 == nil)
    /* no room even so: the pockets' gaps alone, no switch */
    r = row([60, 60, 60], [[0, 100], [110, 200]], nil, [[0, 200]], 100, 21)!
    #expect(r.0 == [34, 100, 166] && r.2 == nil)
    #expect(row([100, 100, 100, 100], near, far, pk, 196.5, 21) == nil)
  }

  /* .pchip.busy's chipPulse (1.1s ease-in-out infinite, opacity .6 at 50%) on a lit seat: the computed opacity Chromium
     gives the page's own rules (getAnimations()[0], currentTime set, getComputedStyle; 6 significant digits) */
  @Test func busyPulse() {
    let ts = [0, 0.05, 0.1, 0.2, 0.275, 0.4, 0.5, 0.55, 0.6, 0.7, 0.825, 0.9, 1.0, 1.05, 1.1, 1.21, 2.475, 3.3]
    let web = [1, 0.993504, 0.97315, 0.889768, 0.8, 0.661736, 0.606496, 0.6, 0.606496, 0.661736, 0.8, 0.889768, 0.97315, 0.993504, 1, 0.967336, 0.8, 1]
    for (t, v) in zip(ts, web) { #expect(abs(RailPulse.opacity(t) - v) < 1e-6, "t \(t): \(RailPulse.opacity(t)) vs \(v)") }
    /* Reduce Motion (data-motion reduce: the animation over at once): still at the seat's own */
    #expect(RailPulse.opacity(0.55, reduce: true) == 1)
    #expect(RailPulse.easeInOut(0.5) == 0.5)
  }

  @Test func potted() {
    #expect(SeatWords.potted([]) == "")
    #expect(SeatWords.potted([1, 3, 9]) == "Potted: 1, 3, 9")
    #expect(SeatWords.nextWords(8) == "Next: the 8")
  }

  /* say(): the turn's words and the rest of their sentence hidden, the news kept */
  @Test func unspoken() {
    #expect(SeatWords.unspoken("Stripes. Player 2 to shoot.", turn: "Player 2 to shoot") == "Stripes. ")
    #expect(SeatWords.unspoken("Player 2 to shoot. Ball on: the 3.", turn: "Player 2 to shoot") == "Ball on: the 3.")
    #expect(SeatWords.unspoken("Break of 12. CPU to shoot, on a red.", turn: "CPU to shoot") == "Break of 12. ")
    #expect(SeatWords.unspoken("Your turn: red, 4 left.", turn: "Your turn") == "red, 4 left.")
    #expect(SeatWords.unspoken("Player 1 to break.", turn: "Player 1 to shoot") == "Player 1 to break.")
  }
}
