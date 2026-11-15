/* index.html 4m's recorded roll (heroRunStart, heroSample, heroRunOn): the hero's shot struck and stepped, positions every
   HERO_SUB steps, each ball's turn rolled from its path (from artTilt's orientation), where each went down; the rest
   positions are simulateShot's exactly. */
import Foundation
import FeltSim

public let HERO_SUB = 6
/* artTilt: a ball's resting orientation in the art, by its number */
public func artTilt(_ n: Int) -> Mat3 { rotate(rotate(IDENT, [0, 0, 1], (Double(n) * 2.39).truncatingRemainder(dividingBy: 6.28)), [1, 0.2, 0], 0.32) }

public final class HeroRun {
  public let tab: Tab, n: Int, s: Sim
  public var m: [Mat3]
  public var pos: [[Double]] = [], on: [[Bool]] = [], rot: [[Float]] = []
  public var pots: [Int: (t: Double, k: Int, at: [Double])] = [:]
  public var moveT = 0.0, done = false, S = 0.0
  /* how many of the roll's hits had happened by each sample (the opening's sound and its cut, 6o) */
  public var hitN: [Int] = []
  public init(_ s: Sim, balls: [Ball], ball: Int, angle: Double, power: Double, spin: Spin) {
    self.s = s
    tab = s.strike(s.newTable(balls, cue: ball), angle, power, spin); n = tab.balls.count
    m = tab.balls.map { artTilt($0.n) }
    sample()
  }
  func sample() {
    let B = tab.balls
    var p = [Double](repeating: 0, count: 2 * n), o = [Bool](repeating: false, count: n), r = [Float](repeating: 0, count: 9 * n)
    let last = pos.last, lastOn = on.last
    var moved = false
    for i in 0..<n {
      let b = B[i]
      p[2 * i] = b.x; p[2 * i + 1] = b.y; o[i] = b.on
      if let last, let lastOn {
        let dx = b.x - last[2 * i], dy = b.y - last[2 * i + 1]
        if dx != 0 || dy != 0 { moved = true }
        let d = JSMath.hypot(dx, dy)
        if b.on && d > 0 { m[i] = rotate(m[i], [-dy, dx, 0], d / s.BALL_R) }
        if lastOn[i] && !b.on { pots[i] = (tab.t, tab.pocketOf[b.n] ?? -1, [last[2 * i], last[2 * i + 1]]) }
      }
      for k in 0..<9 { r[9 * i + k] = Float(m[i][k]) }
    }
    if moved { moveT = tab.t }
    pos.append(p); on.append(o); rot.append(r); hitN.append(tab.hits.count)
  }
  /* heroRunOn, unsliced: to the end (the page slices it by wall time; the steps are the same) */
  public func runAll() {
    while !done {
      var go = true, k = 0
      while k < HERO_SUB && go { go = s.stepTable(tab); k += 1 }
      sample()
      if !go { done = true; S = Swift.max(0.4, moveT) }
    }
  }
}
