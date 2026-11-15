/* index.html sim 1n: the setup hero's signature shot per table (HERO_SHOTS: the struck ball's spot as table fractions,
   the angle, power and english, re-solved by tools/hero-solver.cjs), heroKey and heroSetup (the game's layout with the
   struck ball moved, and its shot). A table with no stored shot breaks straight up the table at the foot spot (bumper
   pool: at the far cup). */
import Foundation

public enum Hero {
  public struct Shot: Sendable { public let c: [Double]?, a: Double, p: Double, s: [Double] }
  public static let SHOTS: [String: Shot] = [
    "8|7|regulation": Shot(c: [0.25, 0.26], a: 0.219952, p: 0.94, s: [0, -0.25]),
    "8|7|generous": Shot(c: [0.21, 0.58], a: -0.087066, p: 0.94, s: [0, 0]),
    "8|9|regulation": Shot(c: [0.25, 0.58], a: -0.090302, p: 1, s: [0, 0.2]),
    "8|9|generous": Shot(c: [0.25, 0.66], a: -0.163891, p: 1, s: [0, -0.25]),
    "9|7|regulation": Shot(c: [0.25, 0.5], a: -0.010472, p: 0.94, s: [0, 0.2]),
    "9|7|generous": Shot(c: [0.25, 0.34], a: 0.16397, p: 0.88, s: [0, 0.2]),
    "9|9|regulation": Shot(c: [0.21, 0.34], a: 0.128752, p: 1, s: [0, -0.25]),
    "9|9|generous": Shot(c: [0.25, 0.5], a: 0.002618, p: 0.94, s: [0, 0]),
    "10|7|regulation": Shot(c: [0.21, 0.58], a: -0.08183, p: 1, s: [0, 0.2]),
    "10|7|generous": Shot(c: [0.21, 0.34], a: 0.131444, p: 1, s: [0, 0.2]),
    "10|9|regulation": Shot(c: [0.21, 0.34], a: 0.141842, p: 0.88, s: [0, 0]),
    "10|9|generous": Shot(c: [0.21, 0.34], a: 0.141842, p: 0.88, s: [0, 0]),
    "straight|7|regulation": Shot(c: [0.21, 0.66], a: -0.162859, p: 0.88, s: [0, -0.25]),
    "straight|7|generous": Shot(c: [0.21, 0.58], a: -0.087066, p: 0.94, s: [0, 0]),
    "straight|9|regulation": Shot(c: [0.25, 0.58], a: -0.090302, p: 1, s: [0, 0.2]),
    "straight|9|generous": Shot(c: [0.25, 0.66], a: -0.163891, p: 1, s: [0, -0.25]),
    "rotation|7|regulation": Shot(c: [0.25, 0.26], a: 0.219952, p: 0.94, s: [0, -0.25]),
    "rotation|7|generous": Shot(c: [0.21, 0.58], a: -0.087066, p: 0.94, s: [0, 0]),
    "rotation|9|regulation": Shot(c: [0.25, 0.58], a: -0.090302, p: 1, s: [0, 0.2]),
    "rotation|9|generous": Shot(c: [0.25, 0.66], a: -0.163891, p: 1, s: [0, -0.25]),
    "heyball": Shot(c: [0.21, 0.34], a: 0.135465, p: 1, s: [0, 0]),
    "snooker|compact": Shot(c: [0.196414, 0.570208], a: -0.001708, p: 0.85, s: [0.4, 0]),
    "snooker|full": Shot(c: [0.198095, 0.570208], a: -0.007422, p: 1, s: [0, -0.3]),
    "bumper|octagon": Shot(c: nil, a: -2.805617, p: 0.7, s: [0, 0]),
    "bumper|rect": Shot(c: nil, a: -2.207842, p: 0.55, s: [0, 0]),
    "carom": Shot(c: nil, a: -0.061087, p: 0.6, s: [0.8, 0]),
  ]
  public static func key(_ kind: String, _ s: Sim) -> String {
    kind == "heyball" ? "heyball" : POCKET_KINDS.contains(kind) ? "\(kind)|\(s.TABLE)|\(s.POCKETS_STYLE)" : kind == "snooker" ? "snooker|" + s.SNOOKER_SIZE
      : kind == "bumper" ? "bumper|" + s.BUMPER_SHAPE : "carom"
  }
  /* the struck ball: the cue ball, carom's white, bumper pool's marked red */
  public static func ball(_ kind: String) -> Int { kind == "bumper" ? B_MARK[0] : kind == "carom" ? C_CUE[0] : 0 }
  /* heroSetup on the table now set: the layout and the shot */
  public static func setup(_ kind: String, _ E: RulesEngine) -> (balls: [Ball], ball: Int, angle: Double, power: Double, spin: Spin) {
    let s = E.sim, sh = SHOTS[key(kind, s)], n = ball(kind), balls = E.newGame(kind).balls.map { gb -> Ball in let b = Ball(gb.n, gb.x, gb.y); b.on = gb.on; return b }
    let b = balls.first { $0.n == n }!
    if let c = sh?.c { b.x = c[0] * s.TL; b.y = c[1] * s.TW }
    let T = kind == "bumper" ? s.POCKETS[1] : s.FOOT, angle = sh?.a ?? JSMath.atan2(T[1] - b.y, T[0] - b.x)
    return (balls, n, angle, sh?.p ?? 0.9, sh.map { Spin(x: $0.s[0], y: $0.s[1]) } ?? Spin())
  }
}
