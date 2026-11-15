/* index.html sim 1h, trick shots: hand-made challenges, a fixed layout and one shot, the goal judged from the shot's result.
   Layouts are built for the current table at call time from table fractions and pocket-relative helpers (trickHelpers),
   so they fit 7 ft and 9 ft. check(r, P) returns nil on success or why it failed, in words; a scratch fails unless the
   shot has scratchOk (cueIn: the cue ball's own pocket is the goal). TRICK_SOLS holds one known solution per challenge
   and table setting ('7r', '9r', '7g', '9g') as [angle, power, side, vertical(, elevation in degrees)]. The program
   (TRICK_PROGRAM, T6.3): seven disciplines, slots for difficulty 6 to 10; trickPts scores a run's attempt. Line for line. */
import Foundation

private typealias M = JSMath
public let TRICK_ZONE = 0.07, TRICK_RUN = 3

public struct TrickHelpers: @unchecked Sendable {
  let s: Sim
  var R: Double { s.BALL_R }
  var F: Double { 2 * R + RACK_GAP }
  func unit(_ a: [Double], _ b: [Double]) -> [Double] { let dx = b[0] - a[0], dy = b[1] - a[1]; var d = M.hypot(dx, dy); if d == 0 { d = 1 }; return [dx / d, dy / d] }
  public func at(_ fx: Double, _ fy: Double) -> [Double] { [fx * s.TL, fy * s.TW] }
  /* d radii in from the middle of pocket k's mouth, along its inward normal */
  public func lip(_ k: Int, _ d: Double) -> [Double] { [s.POCKET_AIM[k][0] + s.CPU_MOUTH_N[k][0] * d * R, s.POCKET_AIM[k][1] + s.CPU_MOUTH_N[k][1] * d * R] }
  /* frozen to the ball at p, in direction deg */
  public func touch(_ p: [Double], _ deg: Double) -> [Double] { [p[0] + M.cos(deg * Double.pi / 180) * F, p[1] + M.sin(deg * Double.pi / 180) * F] }
  /* on the line from pocket k's mouth through p, d radii past p */
  public func line(_ p: [Double], _ k: Int, _ d: Double) -> [Double] { let u = unit(s.POCKET_AIM[k], p); return [p[0] + u[0] * d * R, p[1] + u[1] * d * R] }
  public func frozen(_ p: [Double], _ k: Int) -> [Double] { let u = unit(s.POCKET_AIM[k], p); return [p[0] + u[0] * F, p[1] + u[1] * F] }
  /* u of the way from p to q, then d radii to the left of that line */
  public func along(_ p: [Double], _ q: [Double], _ u: Double, _ d: Double = 0) -> [Double] { let e = unit(p, q); return [p[0] + (q[0] - p[0]) * u - e[1] * d * R, p[1] + (q[1] - p[1]) * u + e[0] * d * R] }
  public func off(_ p: [Double], _ dx: Double, _ dy: Double) -> [Double] { [p[0] + dx * R, p[1] + dy * R] }
  /* d radii out from the ghost ball for pocket k, along that line turned deg */
  public func cut(_ p: [Double], _ k: Int, _ deg: Double, _ d: Double) -> [Double] {
    let u = unit(s.POCKET_AIM[k], p), g = [p[0] + u[0] * 2 * R, p[1] + u[1] * 2 * R], a = M.atan2(u[1], u[0]) + deg * Double.pi / 180
    return [g[0] + M.cos(a) * d * R, g[1] + M.sin(a) * d * R]
  }
  /* on the cloth against the bottom rail: x as a fraction of the length, gap radii off the cushion line */
  public func rail(_ fx: Double, _ gap: Double) -> [Double] { [fx * s.TL, s.TW - (1 + gap) * R] }
}

/* the result's facts the checks read */
private func potIn(_ r: ShotResult, _ n: Int, _ ks: [Int]? = nil) -> Bool { r.potted.contains(n) && (ks == nil || ks!.contains(r.pocketOf[n] ?? -99)) }
private func touched(_ r: ShotResult, _ n: Int) -> Bool { r.contacts.contains { $0[0] == n || $0[1] == n } }
private func upWhy(_ r: ShotResult, _ ns: Int...) -> String? { let up = ns.filter { !r.potted.contains($0) }; return up.isEmpty ? nil : "The \(up.map(String.init).joined(separator: " and the ")) stayed up." }
private func jumped(_ r: ShotResult, _ ns: Int...) -> Bool { ns.allSatisfy { (r.over ?? []).contains($0) } }
private func wallWhy(_ r: ShotResult, _ ns: [Int]) -> String? { ns.first { touched(r, $0) }.map { "The \($0) was touched." } }
private func curveWhy(_ r: ShotResult, _ n: Int) -> String? { touched(r, n) ? "The \(n) was touched." : jumped(r, n) ? "Curve round the \(n), not over it." : (r.kick ?? 0) != 0 ? "No rail first: curve the cue ball to the 1." : nil }
private func rails(_ r: ShotResult, _ n: Int) -> Int { r.rails[n] ?? 0 }
private func inRing(_ r: ShotResult, _ P: [Int: [Double]], _ rad: Double) -> Bool { M.hypot(r.balls[0].x - P[-1]![0], r.balls[0].y - P[-1]![1]) <= rad }
private func into(_ r: ShotResult, _ n: Int, _ k: Int) -> String? { potIn(r, n, [k]) ? nil : r.potted.contains(n) ? "The \(n) went in the wrong pocket." : "The \(n) stayed up." }

public struct Trick: Sendable {
  public let id: String, title: String, goal: String
  public var group: String? = nil, level: String? = nil, elev: Int? = nil, pocket: Int? = nil, cueIn = false, scratchOk = false
  public var zoneR: Double? = nil
  let balls: @Sendable (TrickHelpers) -> [(Int, [Double])]
  var zone: (@Sendable (TrickHelpers, [Int: [Double]]) -> [Double])? = nil
  /* P: the layout's points by ball number, the zone's centre at -1 */
  let check: @Sendable (ShotResult, [Int: [Double]]) -> String?
}

public let TRICKS: [Trick] = [
  Trick(id: "long", title: "Long Pot", goal: "Pot the 1 in the marked corner.", pocket: 2,
    balls: { T in [(0, T.at(0.25, 0.62)), (1, T.at(0.72, 0.3))] },
    check: { r, _ in potIn(r, 1, [2]) ? nil : r.potted.contains(1) ? "The 1 went in the wrong pocket." : "The 1 stayed up." }),
  Trick(id: "stun", title: "Stop Shot", goal: "Pot the 1 and stop the cue ball in the ring.", zoneR: TRICK_ZONE,
    balls: { T in let b = T.at(0.7, 0.32); return [(0, T.line(b, 2, 14)), (1, b)] },
    zone: { T, P in T.line(P[1]!, 2, 2) },
    check: { r, P in upWhy(r, 1) ?? (inRing(r, P, TRICK_ZONE) ? nil : "The cue ball stopped outside the ring.") }),
  Trick(id: "combo", title: "Frozen Combo", goal: "Hit the 3 into the 4 and pot the 4.",
    balls: { T in let b = T.lip(5, 9); return [(0, T.at(0.45, 0.35)), (4, b), (3, T.frozen(b, 5))] },
    check: { r, _ in r.first != 3 ? "Hit the 3 first." : upWhy(r, 4) }),
  Trick(id: "draw", title: "Draw Back", goal: "Pot the 1 in the side, draw back and pot the 2 in the other side.",
    balls: { T in [(0, T.at(0.5, 0.5)), (1, T.at(0.5, 0.28)), (2, T.at(0.5, 0.76))] },
    check: { r, _ in upWhy(r, 1, 2) ?? (r.pocketOf[1] == r.pocketOf[2] ? "Both went in the same side." : nil) }),
  Trick(id: "kiss", title: "Kiss Shot", goal: "The 1 and 2 are frozen. Hit the 2 and let the kiss send it in.",
    balls: { T in let b = T.at(0.8, 0.4); return [(0, T.at(0.42, 0.58)), (2, b), (1, T.touch(b, 45))] },
    check: { r, _ in r.first != 2 ? "Hit the 2 first." : upWhy(r, 2) ?? (r.potted.contains(1) ? "The 1 went down too: only the 2." : nil) }),
  Trick(id: "carom", title: "Carom", goal: "Glance off the 1 and pot the 2 with the cue ball.",
    balls: { T in [(0, T.at(0.3, 0.55)), (1, T.at(0.62, 0.42)), (2, T.lip(2, 3))] },
    check: { r, _ in r.first != 1 ? "Hit the 1 first." : !r.contacts.contains { $0[0] == 0 && $0[1] == 2 } ? "The cue ball never reached the 2." : upWhy(r, 2) }),
  Trick(id: "cross", title: "Cross Side", goal: "Bank the 9 off the near rail into the far side pocket.", pocket: 1,
    balls: { T in [(0, T.at(0.4, 0.32)), (9, T.at(0.47, 0.72))] },
    check: { r, _ in upWhy(r, 9) ?? (r.pocketOf[9] != 1 ? "The 9 has to go in the far side." : rails(r, 9) < 1 ? "No bank: the 9 must hit a rail." : nil) }),
  Trick(id: "needle", title: "Thread the Needle", goal: "Pot the 1 between the 3 and the 4. Touch neither.",
    balls: { T in let c = T.at(0.22, 0.5), b = T.lip(2, 6), g = T.line(b, 2, 2); return [(0, c), (1, b), (3, T.along(c, g, 0.5, 2.2)), (4, T.along(c, g, 0.5, -2.2))] },
    check: { r, _ in (touched(r, 3) || touched(r, 4) ? "A blocker was touched." : nil) ?? upWhy(r, 1) }),
  Trick(id: "around", title: "Around the 3", goal: "Pot the 5 without touching the 3.",
    balls: { T in let c = T.at(0.35, 0.55), b = T.lip(2, 5); return [(0, c), (5, b), (3, T.along(c, b, 0.55, 0.4))] },
    check: { r, _ in touched(r, 3) ? "The 3 was touched." : upWhy(r, 5) }),
  Trick(id: "kick", title: "Kick", goal: "The 2 is in the way. Kick off a rail, hit the 1 first and pot it.",
    balls: { T in let c = T.at(0.55, 0.62), b = T.lip(2, 2.5); return [(0, c), (1, b), (2, T.along(c, b, 0.5))] },
    check: { r, _ in r.first != 1 ? "Hit the 1 first." : !((r.kick ?? 0) >= 1) ? "Rail first: kick the cue ball off a cushion." : upWhy(r, 1) }),
  Trick(id: "two", title: "Two in One", goal: "Pot the 1 and the 2 in one shot.",
    balls: { T in [(0, T.at(0.55, 0.5)), (1, T.lip(2, 4)), (2, T.lip(5, 4))] },
    check: { r, _ in upWhy(r, 1, 2) }),
  Trick(id: "world", title: "Around the World", goal: "Pot the 1, then send the cue ball round four rails.",
    balls: { T in [(0, T.at(0.3, 0.62)), (1, T.lip(1, 3))] },
    check: { r, _ in upWhy(r, 1) ?? (rails(r, 0) - (r.kick ?? 0) < 4 ? "The cue ball found \(rails(r, 0) - (r.kick ?? 0)) rails after the 1: it needs four." : nil) }),
  Trick(id: "bank2", title: "Two Rails", goal: "Pot the 8 off two rails.",
    balls: { T in [(0, T.at(0.25, 0.35)), (8, T.at(0.5, 0.5))] },
    check: { r, _ in upWhy(r, 8) ?? (rails(r, 8) < 2 ? "The 8 hit \(rails(r, 8)) rail\(r.rails[8] == 1 ? "" : "s"): it needs two." : nil) }),
  Trick(id: "three", title: "Three in One", goal: "Pot the 1, the 2 and the 3 in one shot.",
    balls: { T in let b = T.lip(2, 1.8); return [(0, T.at(0.75, 0.6)), (1, b), (2, T.frozen(b, 2)), (3, T.lip(5, 2))] },
    check: { r, _ in upWhy(r, 1, 2, 3) }),
  /* Jump and Massé (group jump): level, elev (the hint's degrees); a jump read from r.over, a curve from r.kick */
  Trick(id: "jhop", title: "Jump Shot", goal: "Jump the cue ball over the 2 and pot the 1 in the marked corner.", group: "jump", level: "easy", elev: 50, pocket: 2,
    balls: { T in let b = T.lip(2, 10), c = T.cut(b, 2, 25, 30); return [(0, c), (1, b), (2, T.along(c, b, 0.22))] },
    check: { r, _ in touched(r, 2) ? "The 2 was touched." : !jumped(r, 2) ? "No jump: the cue ball has to fly over the 2." : into(r, 1, 2) }),
  Trick(id: "jwall", title: "Over the Wall", goal: "Jump the wall of three and pot the 1 in the marked corner. Touch no wall ball.", group: "jump", level: "medium", elev: 50, pocket: 2,
    balls: { T in let b = T.lip(2, 10), c = T.cut(b, 2, 30, 30); return [(0, c), (1, b), (2, T.along(c, b, 0.22, 2.0004)), (3, T.along(c, b, 0.22)), (4, T.along(c, b, 0.22, -2.0004))] },
    check: { r, _ in wallWhy(r, [2, 3, 4]) ?? (!jumped(r, 3) && !jumped(r, 2) && !jumped(r, 4) ? "No jump: fly the cue ball over the wall." : into(r, 1, 2)) }),
  Trick(id: "jknievel", title: "Over the Row", goal: "Clear the row of four in one jump and pot the 1 in the marked corner.", group: "jump", level: "hard", elev: 45, pocket: 2,
    balls: { T in let b = T.lip(2, 8), c = T.cut(b, 2, 15, 44); return [(0, c), (1, b)] + [2, 3, 4, 5].enumerated().map { i, n in (n, T.along(c, b, 0.22 + Double(i) * 0.075)) } },
    check: { r, _ in wallWhy(r, [2, 3, 4, 5]) ?? (!jumped(r, 2, 3, 4, 5) ? "Clear every ball in the row." : into(r, 1, 2)) }),
  Trick(id: "jbank", title: "Jump and Bank", goal: "Jump the cue ball over the 2, then bank the 1 off a rail into any pocket.", group: "jump", level: "hard", elev: 55,
    balls: { T in let b = T.at(0.55, 0.12), c = T.at(0.35, 0.3); return [(0, c), (1, b), (2, T.along(c, b, 0.35))] },
    check: { r, _ in touched(r, 2) ? "The 2 was touched." : !jumped(r, 2) ? "No jump: the cue ball has to fly over the 2." : upWhy(r, 1) ?? (rails(r, 1) < 1 ? "No bank: the 1 must hit a rail." : nil) }),
  Trick(id: "jswerve", title: "Half-Ball Swerve", goal: "The 2 hides half the 1. Swerve round it and pot the 1 in the marked corner, no rail first.", group: "jump", level: "hard", elev: 20, pocket: 2,
    balls: { T in let b = T.lip(2, 8), c = T.cut(b, 2, 0, 30); return [(0, c), (1, b), (2, T.along(c, b, 0.5, 1))] },
    check: { r, _ in curveWhy(r, 2) ?? into(r, 1, 2) }),
  Trick(id: "jmingaud", title: "Mingaud Massé", goal: "The 2 sits right on the line. Massé round it, hard side and a little draw, and pot the 1.", group: "jump", level: "medium", elev: 55, pocket: 2,
    balls: { T in let b = T.lip(2, 4), c = T.cut(b, 2, 0, 16); return [(0, c), (1, b), (2, T.along(c, b, 0.3))] },
    check: { r, _ in curveWhy(r, 2) ?? into(r, 1, 2) }),
  Trick(id: "jrail", title: "Rail Massé", goal: "The 2 is frozen to the rail. Massé out round it and back along the rail to pot the 1.", group: "jump", level: "easy", elev: 30, pocket: 5,
    balls: { T in [(0, T.rail(0.62, 0.25)), (1, T.lip(5, 2.5)), (2, T.rail(0.76, 0.05))] },
    check: { r, _ in curveWhy(r, 2) ?? into(r, 1, 5) }),
  Trick(id: "jescape", title: "Escape Massé", goal: "The cue ball is trapped between the rail and the 2. Massé out without moving the 2 and pot the 1.", group: "jump", level: "easy", elev: 40, pocket: 3,
    balls: { T in let c = T.rail(0.25, 0.02); return [(0, c), (1, T.lip(3, 3)), (2, [c[0], c[1] - 2.0004 * T.R])] },
    check: { r, _ in touched(r, 2) ? "The 2 moved." : jumped(r, 2) ? "Massé round the 2, not over it." : into(r, 1, 3) }),
  Trick(id: "jboot", title: "Into the Corner", goal: "Fly the cue ball over both guards into the marked corner, touching nothing.", group: "jump", level: "medium", elev: 40, pocket: 2, cueIn: true,
    balls: { T in [(0, T.lip(2, 30)), (1, T.lip(2, 5.0002)), (2, T.lip(2, 2.9998))] },
    check: { r, _ in !r.contacts.isEmpty ? "A ball was touched: the cue ball goes in on the fly." : !jumped(r, 1) && !jumped(r, 2) ? "No jump: fly the cue ball over the guards." : potIn(r, 0, [2]) ? nil : r.potted.contains(0) ? "The cue ball went in the wrong pocket." : "The cue ball missed the pocket." }),
  /* the program's own shots (group program); scratchOk: WPA allows a scratch unless the shot says otherwise */
  Trick(id: "kick3", title: "Three-Rail Kick", goal: "Three rails or more first, then the 1 into the marked corner. Leave the 2 alone.", group: "program", pocket: 2, scratchOk: true,
    balls: { T in [(0, T.at(0.3, 0.3)), (1, T.lip(2, 2)), (2, T.at(0.62, 0.17))] },
    check: { r, _ in touched(r, 2) ? "The 2 was touched." : r.first != 1 ? "Hit the 1 first." : (r.kick ?? 0) < 3 ? "The cue ball found \(r.kick ?? 0) rails first: it needs three." : potIn(r, 1, [2]) ? nil : "The 1 stayed up." }),
  Trick(id: "kick5", title: "Five-Rail Kick", goal: "Five rails or more first, then the 1 into the marked corner. Leave the 2 alone.", group: "program", pocket: 2, scratchOk: true,
    balls: { T in [(0, T.at(0.3, 0.3)), (1, T.lip(2, 2)), (2, T.at(0.62, 0.17))] },
    check: { r, _ in touched(r, 2) ? "The 2 was touched." : r.first != 1 ? "Hit the 1 first." : (r.kick ?? 0) < 5 ? "The cue ball found \(r.kick ?? 0) rails first: it needs five." : potIn(r, 1, [2]) ? nil : "The 1 stayed up." }),
  Trick(id: "longstop", title: "Long Stop", goal: "A long straight pot: stop the cue ball dead in the ring.", group: "program", zoneR: 0.08,
    balls: { T in let b = T.at(0.75, 0.2); return [(0, T.line(b, 2, 40)), (1, b)] },
    zone: { T, P in T.line(P[1]!, 2, 2) },
    check: { r, P in upWhy(r, 1) ?? (inRing(r, P, 0.08) ? nil : "The cue ball stopped outside the ring.") }),
  Trick(id: "fring", title: "Follow to the Ring", goal: "Pot the 1 and roll on through its place into the ring.", group: "program", zoneR: 0.07,
    balls: { T in let b = T.lip(2, 12); return [(0, T.line(b, 2, 16)), (1, b)] },
    zone: { T, P in T.along(P[1]!, T.lip(2, 0), 0.55) },
    check: { r, P in upWhy(r, 1) ?? (r.potted.contains(0) ? "Scratch: the cue ball went down." : inRing(r, P, 0.07) ? nil : "The cue ball stopped outside the ring.") }),
  Trick(id: "cpair", title: "Corner Pair", goal: "Both corners at this end: pot the 1 and carry the cue ball on to pot the 2.", group: "program", scratchOk: true,
    balls: { T in [(0, T.at(0.62, 0.5)), (1, T.lip(2, 1.6)), (2, T.lip(5, 1.6))] },
    check: { r, _ in r.first != 1 ? "Hit the 1 first." : !r.contacts.contains { $0[0] == 0 && $0[1] == 2 } ? "The cue ball never reached the 2." : upWhy(r, 1, 2) }),
  Trick(id: "sdraw", title: "Side Draw", goal: "Pot the 1 in the side, then draw back into the ring, touching no rail.", group: "program", zoneR: 0.1,
    balls: { T in [(0, T.at(0.5, 0.55)), (1, T.at(0.5, 0.25))] },
    zone: { T, _ in T.at(0.5, 0.72) },
    check: { r, P in !potIn(r, 1, [1]) ? "The 1 goes in the side." : rails(r, 0) != 0 ? "No rails: draw straight back." : inRing(r, P, 0.1) ? nil : "The cue ball stopped outside the ring." }),
  Trick(id: "rdraw", title: "Ring Draw", goal: "Pot the 1, then draw straight back into the ring, touching no rail.", group: "program", zoneR: 0.1,
    balls: { T in let b = T.at(0.75, 0.2); return [(0, T.line(b, 2, 22)), (1, b)] },
    zone: { T, P in T.line(P[1]!, 2, 14) },
    check: { r, P in upWhy(r, 1) ?? (rails(r, 0) != 0 ? "No rails: draw straight back." : inRing(r, P, 0.1) ? nil : "The cue ball stopped outside the ring.") }),
  Trick(id: "lmasse", title: "Long Massé", goal: "The 2 stands halfway down a long line. Massé round it and pot the 1 in the marked corner.", group: "program", level: "hard", elev: 50, pocket: 2,
    balls: { T in let b = T.at(0.82, 0.14), c = T.line(b, 2, 44); return [(0, c), (1, b), (2, T.along(c, b, 0.5))] },
    check: { r, _ in curveWhy(r, 2) ?? into(r, 1, 2) }),
]

public let TRICK_SOLS: [String: [String: [Double]]] = [
    "long": ["7r": [-0.305433, 0.5, 0.6, 0], "9r": [-0.322886, 0.72, 0, 0], "7g": [-0.322886, 0.32, 0, 0], "9g": [-0.322886, 0.72, 0, 0]],
    "stun": ["7r": [-0.462512, 0.4, 0, -0.6], "9r": [-0.471239, 0.4, 0, -0.6], "7g": [-0.462512, 0.4, 0, -0.6], "9g": [-0.471239, 0.4, 0, -0.6]],
    "combo": ["7r": [0.445059, 0.25, 0, 0], "9r": [0.427606, 0.32, 0, 0], "7g": [0.401426, 0.25, 0, 0], "9g": [0.427606, 0.32, 0, 0]],
    "draw": ["7r": [-1.570796, 0.5, 0, -1], "9r": [-1.570796, 0.6, 0, -0.6], "7g": [-1.570796, 0.5, 0, -1], "9g": [-1.570796, 0.5, 0, -1]],
    "kiss": ["7r": [-0.218166, 0.32, 0, 0], "9r": [-0.235619, 0.32, 0, 0], "7g": [-0.235619, 0.32, 0, 0], "9g": [-0.226893, 0.4, 0, 0]],
    "carom": ["7r": [-2.661627, 1, 0, 0], "9r": [-0.253073, 0.72, 0.6, 0], "7g": [-2.661627, 1, 0, 0], "9g": [-1.45735, 1, 0.6, -0.6]],
    "cross": ["7r": [1.291544, 0.85, 0, 0.6], "9r": [1.195551, 0.5, 0, 0], "7g": [1.30027, 1, 0.6, 0.6], "9g": [1.27409, 1, 0, 0]],
    "needle": ["7r": [-0.226893, 0.32, -0.6, 0], "9r": [-0.253073, 0.32, -0.6, 0], "7g": [-0.20944, 0.32, 0, 0], "9g": [-0.235619, 0.32, 0, 0]],
    "around": ["7r": [-0.575959, 0.5, 0.6, 0], "9r": [-1.32645, 0.5, 0.6, 0.6], "7g": [-2.70526, 0.6, 0, -0.6], "9g": [-2.83616, 0.6, 0, 0]],
    "kick": ["7r": [1.029744, 0.32, 0, 0], "9r": [-2.897247, 0.5, 0, 0], "7g": [0.977384, 0.5, 0, 0], "9g": [-2.96706, 0.6, 0, 0]],
    "two": ["7r": [-0.418879, 1, 0, -0.6], "9r": [-0.637045, 0.6, 0.6, 0], "7g": [-0.427606, 1, 0, -1], "9g": [-0.628319, 0.6, 0, 0.6]],
    "world": ["7r": [-0.855211, 0.85, 0, 0], "9r": [-0.898845, 0.6, 0, 0.6], "7g": [-0.855211, 0.85, 0, 0], "9g": [-0.890118, 0.72, 0, -0.6]],
    "bank2": ["7r": [0.314159, 0.72, 0, 0.6], "9r": [0.322886, 0.85, 0.6, 0.6], "7g": [0.314159, 0.72, 0, 0.6], "9g": [0.296706, 0.85, -0.6, 0.6]],
    "three": ["7r": [-0.829031, 1, 0.6, 0], "9r": [-1.064651, 1, 0, 0], "7g": [-0.951204, 0.85, 0, 0.6], "9g": [-0.942478, 0.72, 0, 1]],
    "jhop": ["7r": [-0.349066, 0.6, 0, -0.3, 50], "9r": [-0.349066, 0.6, 0, -0.3, 50], "7g": [-0.349066, 0.6, 0, -0.3, 50], "9g": [-0.349066, 0.6, 0, -0.3, 50]],
    "jwall": ["7r": [-0.261799, 0.56, 0, 0, 55], "9r": [-0.261799, 0.56, 0, 0, 45], "7g": [-0.261799, 0.56, 0, 0, 55], "9g": [-0.261799, 0.56, 0, 0, 50]],
    "jknievel": ["7r": [-0.523599, 0.72, 0, -0.3, 45], "9r": [-0.523599, 0.72, 0, -0.3, 45], "7g": [-0.523599, 0.72, 0, -0.3, 40], "9g": [-0.523599, 0.72, 0, -0.3, 40]],
    "jbank": ["7r": [-0.453786, 0.6, 0, -0.3, 55], "9r": [-0.453786, 0.6, 0, -0.3, 55], "7g": [-0.453786, 0.56, 0, 0, 55], "9g": [-0.453786, 0.6, 0, -0.3, 55]],
    "jswerve": ["7r": [-0.925025, 0.44, 0.8, -0.6, 20], "9r": [-0.925025, 0.44, 0.8, -0.6, 20], "7g": [-0.925025, 0.44, 0.8, -0.6, 20], "9g": [-0.925025, 0.44, 0.8, -0.6, 20]],
    "jmingaud": ["7r": [-1.553343, 0.52, 0.8, -0.6, 55], "9r": [-1.553343, 0.52, 0.8, -0.6, 55], "7g": [-1.361357, 0.44, 0.6, -0.8, 45], "9g": [-1.361357, 0.44, 0.6, -0.8, 45]],
    "jrail": ["7r": [-0.279253, 0.4, 0.6, 0, 30], "9r": [-0.244346, 0.56, 0.6, 0, 30], "7g": [-0.279253, 0.4, 0.6, 0, 30], "9g": [-0.261799, 0.4, 0.6, 0, 30]],
    "jescape": ["7r": [3.036873, 0.28, 0.6, 0, 40], "9r": [3.054326, 0.28, 0.6, 0, 30], "7g": [3.01942, 0.28, 0.6, 0, 40], "9g": [3.054326, 0.24, 0.6, 0, 30]],
    "jboot": ["7r": [-0.802851, 0.72, 0, 0, 40], "9r": [-0.802851, 0.72, 0, 0, 40], "7g": [-0.820305, 0.72, 0, 0, 40], "9g": [-0.820305, 0.72, 0, 0, 40]],
    "kick3": ["7r": [-2.591814, 0.5, 0, 0], "9r": [-2.574361, 0.6, 0, 0], "7g": [-2.591814, 0.5, 0, 0], "9g": [-2.565634, 0.6, 0, 0]],
    "kick5": ["7r": [2.80998, 0.85, 0, 0], "9r": [0.497419, 1, 0, -1], "7g": [2.80998, 0.85, 0, 0], "9g": [0.497419, 1, 0, -1]],
    "longstop": ["7r": [-0.349066, 0.6, -0.6, -0.6], "9r": [-0.357792, 0.6, -0.6, -0.6], "7g": [-0.340339, 0.6, -0.6, -0.6], "9g": [-0.322886, 0.6, 0.6, -0.6]],
    "fring": ["7r": [-0.785398, 0.25, 0, 0.6], "9r": [-0.785398, 0.25, 0, 0.6], "7g": [-0.785398, 0.25, 0, 0.6], "9g": [-0.785398, 0.25, 0, 0.6]],
    "cpair": ["7r": [-0.523599, 1, 0, -0.6], "9r": [-0.541052, 1, 0, -0.6], "7g": [-0.523599, 0.85, 0, -0.6], "9g": [-0.541052, 1, 0, -0.6]],
    "sdraw": ["7r": [-1.579523, 0.4, 0, -1], "9r": [-1.570796, 0.5, 0, -0.6], "7g": [-1.579523, 0.4, 0, -1], "9g": [-1.570796, 0.5, 0, -0.6]],
    "rdraw": ["7r": [-0.331613, 0.5, 0, -1], "9r": [-0.340339, 0.5, 0, -1], "7g": [-0.322886, 0.5, 0, -1], "9g": [-0.340339, 0.5, 0, -1]],
    "lmasse": ["7r": [0.10472, 0.6, -0.6, -0.8, 40], "9r": [0.087266, 0.6, -0.6, -0.8, 40], "7g": [-0.610865, 0.56, 0.6, -0.8, 35], "9g": [0.017453, 0.56, -0.6, -0.8, 35]]

]

/* the program: seven disciplines, a shot at difficulty 6 to 10 each (nil: no shot the solver could prove) */
public let TRICK_PROGRAM: [(id: String, title: String, slots: [String?])] = [
  ("fancy", "Trick and Fancy", ["kiss", "carom", "two", "needle", "three"]),
  ("drawn", "Draw", ["draw", "sdraw", "rdraw", nil, nil]),
  ("follow", "Follow", ["fring", nil, nil, "cpair", nil]),
  ("bank", "Bank and Kick", ["kick", "cross", "bank2", "kick3", "kick5"]),
  ("stroke", "Stroke", ["long", "stun", "longstop", "world", nil]),
  ("jump", "Jump", ["jhop", "jboot", "jwall", "jbank", "jknievel"]),
  ("masse", "Massé", ["jrail", "jescape", "jmingaud", "jswerve", "lmasse"]),
]
public let TRICK_VAL: [String: (disc: String, val: Int)] = {
  var o: [String: (disc: String, val: Int)] = [:]
  for d in TRICK_PROGRAM { for (i, id) in d.slots.enumerated() { if let id { o[id] = (d.id, 6 + i) } } }
  return o
}()
public func trickVal(_ id: String) -> Int { TRICK_VAL[id]?.val ?? 0 }
/* what a make on attempt n of a run scores */
public func trickPts(_ val: Int, _ n: Int) -> Int { n >= 1 && n <= TRICK_RUN ? val - (n - 1) : 0 }
public func discTotal(_ pts: [String: Int], _ slots: [String?]) -> Int { slots.reduce(0) { a, id in a + (id.flatMap { pts[$0] } ?? 0) } }
public func discMax(_ slots: [String?]) -> Int { slots.enumerated().reduce(0) { a, e in a + (e.element != nil ? 6 + e.offset : 0) } }
public func programTotal(_ pts: [String: Int]) -> Int { TRICK_PROGRAM.reduce(0) { $0 + discTotal(pts, $1.slots) } }
public func programMax() -> Int { TRICK_PROGRAM.reduce(0) { $0 + discMax($1.slots) } }
/* stars by the attempt that succeeded: 3 on the first, 2 within three, 1 after that */
public func trickStars(_ attempts: Int) -> Int { attempts <= 1 ? 3 : attempts <= 3 ? 2 : 1 }
/* an old save's stars as scores, once: 3 stars is full value, 2 minus 1, 1 minus 2; never lowers a score */
public func trickScoreFromStars(_ stars: [String: Int], _ pts: [String: Int] = [:]) -> [String: Int] {
  var out = pts
  for (id, v) in TRICK_VAL { if let k = stars[id], [1, 2, 3].contains(k) { out[id] = max(out[id] ?? 0, trickPts(v.val, 4 - k)) } }
  return out
}
public func trickById(_ id: String) -> Trick? { TRICKS.first { $0.id == id } }
/* the classics: the daily shot's pool (no group) */
public let DAILY_TRICKS = TRICKS.filter { $0.group == nil }
/* trickHint: the elevation to set, in a sentence */
public func trickHint(_ c: Trick) -> String { c.elev.map { "Raise the cue to about \($0)°." } ?? "" }

extension RulesEngine {
  /* trickPoints: the layout's points for the current table, the zone's centre at -1 */
  public func trickPoints(_ c: Trick) -> [Int: [Double]] {
    let T = TrickHelpers(s: sim)
    var P: [Int: [Double]] = [:]
    for (n, p) in c.balls(T) { P[n] = p }
    if let z = c.zone { P[-1] = z(T, P) }
    return P
  }
  public func trickBalls(_ c: Trick) -> [GBall] { c.balls(TrickHelpers(s: sim)).map { GBall(n: $0.0, x: $0.1[0], y: $0.1[1]) } }
  /* trickGame: the layout, no ball in hand, any ball first */
  public func trickGame(_ c: Trick) -> Game {
    var g = newGame("8")
    g.mode = "trick"; g.trick = c.id; g.balls = trickBalls(c); g.breakShot = false; g.inHand = nil
    return g
  }
  /* trickJudge: one attempt, (ok, why) */
  public func trickJudge(_ c: Trick, _ r: ShotResult) -> (ok: Bool, why: String) {
    if r.potted.contains(0) && !(c.cueIn && r.pocketOf[0] == c.pocket) && !(c.scratchOk && r.pocketOf[0] != -1) {
      return (false, r.pocketOf[0] == -1 ? "The cue ball flew off the table." : "Scratch: the cue ball went down.")
    }
    if let why = c.check(r, trickPoints(c)) { return (false, why) }
    return (true, "")
  }
  /* trickSol: the stored solution for the current table, as a shot */
  public func trickSol(_ c: Trick) -> Sim.Shot? {
    guard let s = TRICK_SOLS[c.id]?[sim.TABLE + (sim.POCKETS_STYLE == "generous" ? "g" : "r")] else { return nil }
    return Sim.Shot(angle: s[0], power: s[1], spin: s.count > 4 && s[4] != 0 ? Spin(x: s[2], y: s[3], e: s[4] * Double.pi / 180) : Spin(x: s[2], y: s[3]))
  }
}

/* the daily shot (page 5s): the day's number since the epoch (dayNum: a yyyy-mm-dd day as UTC midnight, in days) and its
   shot, five classics on from the day before, so every one comes round and none twice running */
public func dayNum(_ s: String) -> Int {
  let p = s.split(separator: "-").map { Int($0)! }
  var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
  var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
  return Int((cal.date(from: c)!.timeIntervalSince1970 * 1000 / 864e5).rounded())
}
public func dailyTrick(_ day: String) -> Trick { let L = DAILY_TRICKS.count; return DAILY_TRICKS[(((dayNum(day) * 5) % L) + L) % L] }
