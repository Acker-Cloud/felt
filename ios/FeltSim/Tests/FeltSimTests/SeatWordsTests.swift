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
