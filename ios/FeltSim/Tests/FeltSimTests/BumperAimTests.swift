/* auto aim at bumper pool (suggestBumper) against the page's, at the opening rack on both shapes, for each player:
   red's a clear line (a bank on the octagon), white's on the octagon the 'hint' CPU search's shot (no line clear).
   The page's numbers come from index.html's sim region run in Node (native Math), so angles agree to 1e-12. */
import Testing
@testable import FeltSim

@Suite struct BumperAimTests {
  static let page: [String: [(Double, Int, Int)]] = [
    "octagon": [(-0.9851318853336855, 21, 1), (5.872825611019266, 31, 0)],
    "rect": [(-0.8124228774937587, 21, 1), (-2.3280814652201043, 31, 0)],
  ]
  @Test(arguments: ["octagon", "rect"])
  func opening(_ shape: String) {
    let sim = Sim(); sim.setTable("bumper", shape)
    let E = RulesEngine(sim: sim), cpu = CPU(engine: E)
    var g = E.newGame("bumper")
    for (i, want) in Self.page[shape]!.enumerated() {
      if i == 1 { g.turn = 1; g.opening = 0; g.striker = 31 }
      let s = cpu.suggestBumper(g)!
      #expect(abs(s.angle - want.0) < 1e-12 && s.n == want.1 && s.k == want.2, "\(shape) player \(i): \(s) vs \(want)")
    }
  }
}
