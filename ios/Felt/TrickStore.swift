/* index.html 5s's trick shot records, in the page's shapes and keys: the old stars (felt.tricks, { id: 1..3 }), the
   lifetime tries (felt.trickTries.v1, { v: 1, n: { id: k } }, audit F12) and the program's scores (felt.trickScore.v2,
   { v: 2, pts: { id: best }, run: { id: attempts this run } }; made once from the stars when missing). Each is cleaned
   as it loads (loadTricks, loadTries, loadScore). */
import Foundation
import FeltSim

enum TrickStore {
  static let TRICKS_KEY = "felt.tricks", TRIES_KEY = "felt.trickTries.v1", SCORE_KEY = "felt.trickScore.v2"
  static func json(_ k: String) -> Any? { UserDefaults.standard.string(forKey: k).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } }
  static func put(_ k: String, _ o: Any) { if let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) { UserDefaults.standard.set(String(decoding: d, as: UTF8.self), forKey: k) } }
  static func int(_ a: Any?) -> Int? { (a as? NSNumber).flatMap { $0.doubleValue == Double($0.intValue) ? $0.intValue : nil } }
  static var best: [String: Int] {
    get { let o = json(TRICKS_KEY) as? [String: Any] ?? [:]; var out: [String: Int] = [:]; for c in TRICKS { if let k = int(o[c.id]), [1, 2, 3].contains(k) { out[c.id] = k } }; return out }
    set { put(TRICKS_KEY, newValue) }
  }
  static var tries: [String: Int] {
    get {
      var out: [String: Int] = [:]
      if let o = json(TRIES_KEY) as? [String: Any], int(o["v"]) == 1, let n = o["n"] as? [String: Any] { for c in TRICKS { if let k = int(n[c.id]), k > 0, k < 1_000_000 { out[c.id] = k } } }
      return out
    }
    set { put(TRIES_KEY, ["v": 1, "n": newValue]) }
  }
  static var score: (pts: [String: Int], run: [String: Int]) {
    get {
      if let o = json(SCORE_KEY) as? [String: Any], int(o["v"]) == 2 {
        var pts: [String: Int] = [:], run: [String: Int] = [:]
        let P = o["pts"] as? [String: Any] ?? [:], R = o["run"] as? [String: Any] ?? [:]
        for (id, v) in TRICK_VAL {
          if let p = int(P[id]), p > 0, p <= v.val { pts[id] = p }
          if let n = int(R[id]), n > 0, n < TRICK_RUN { run[id] = n }
        }
        return (pts, run)
      }
      let out = (pts: trickScoreFromStars(best), run: [String: Int]())
      score = out
      return out
    }
    set { put(SCORE_KEY, ["v": 2, "pts": newValue.pts, "run": newValue.run]) }
  }
}
