/* index.html 5s's trick shot records, in the page's shapes and keys: the old stars (felt.tricks, { id: 1..3 }), the
   lifetime tries (felt.trickTries.v1, { v: 1, n: { id: k } }, audit F12) and the program's scores (felt.trickScore.v2,
   { v: 2, pts: { id: best }, run: { id: attempts this run } }; made once from the stars when missing). Each is cleaned
   as it loads (loadTricks, loadTries, loadScore). */
import Foundation
import FeltSim

/* felt.daily.v1: the day last scored, the streak, the best streak, whether that day's try was made (loadDaily: cleaned) */
struct DailyRec { var last: String? = nil, streak = 0, best = 0, made = false }
enum DailyStore {
  static let KEY = "felt.daily.v1"
  static var rec: DailyRec {
    get {
      var d = DailyRec()
      guard let o = TrickStore.json(KEY) as? [String: Any] else { return d }
      if let l = o["last"] as? String, DrillStore.realDay(l) { d.last = l }
      if let s = TrickStore.int(o["streak"]), s > 0, d.last != nil { d.streak = s }
      if let b = TrickStore.int(o["best"]), b > 0 { d.best = b }
      d.best = max(d.best, d.streak); d.made = (o["made"] as? Bool) == true
      return d
    }
    set { TrickStore.put(KEY, ["last": newValue.last as Any? ?? NSNull(), "streak": newValue.streak, "best": newValue.best, "made": newValue.made]) }
  }
  /* the streak as it stands on day: one whose last day is before yesterday has lapsed (a last day after today is none) */
  static func streak(_ day: String = Rec.today()) -> Int { let r = rec; guard let l = r.last else { return 0 }; let g = dayNum(day) - dayNum(l); return g == 0 || g == 1 ? r.streak : 0 }
  static func done(_ day: String = Rec.today()) -> Bool { rec.last == day }
}
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

/* felt.tutorials.v1: { v: 1, done: { id: true }, skipped: { id: true }, never } (loadTut: anything unreadable starts fresh) */
enum TutStore {
  static let KEY = "felt.tutorials.v1", IDS = ["8", "9", "bumper", "carom", "snooker", "heyball"]
  static var rec: (done: Set<String>, skipped: Set<String>, never: Bool) {
    get {
      guard let o = TrickStore.json(KEY) as? [String: Any], TrickStore.int(o["v"]) == 1 else { return ([], [], false) }
      let d = o["done"] as? [String: Any] ?? [:], k = o["skipped"] as? [String: Any] ?? [:]
      return (Set(IDS.filter { (d[$0] as? Bool) == true }), Set(IDS.filter { (k[$0] as? Bool) == true }), (o["never"] as? Bool) == true)
    }
    set { TrickStore.put(KEY, ["v": 1, "done": Dictionary(uniqueKeysWithValues: newValue.done.map { ($0, true) }), "skipped": Dictionary(uniqueKeysWithValues: newValue.skipped.map { ($0, true) }), "never": newValue.never]) }
  }
  static let WORD = ["8": "8-ball", "9": "9-ball", "bumper": "bumper pool", "carom": "three-cushion", "snooker": "snooker", "heyball": "Chinese 8-ball"]
  static let RECAP = [
    "8": "Open table, your group first, ball in hand after a foul, and the 8 last. The full rules are in How to play.",
    "9": "The lowest ball first, any pot counts, and a legal 9 wins whenever it drops. The full rules are in How to play.",
    "bumper": "Your marked ball first, round the posts to the far cup, and never your own cup. The full rules are in How to play.",
    "carom": "Both balls, with three cushions before the second, and the cushions can come first. The full rules are in How to play.",
    "snooker": "A red, then a colour, and again; ball in hand in the D after an in-off; then the colours in order. The full rules are in How to play.",
    "heyball": "A legal break, an open table until the first pot after it, ball in hand anywhere after a foul, and the 8 last, in any pocket. The full rules are in How to play."]
  /* maybeOfferTut: a game whose tutorial is neither done nor turned down */
  static func offer(_ kind: String) -> Bool { let r = rec; return tutById(kind) != nil && !r.done.contains(kind) && !r.skipped.contains(kind) && !r.never }
}

/* felt.mouseTip.v1: { v: 1, seen }; anything unreadable is unseen */
enum MouseTipStore {
  static let KEY = "felt.mouseTip.v1"
  static var seen: Bool {
    get { guard let o = TrickStore.json(KEY) as? [String: Any], TrickStore.int(o["v"]) == 1 else { return false }; return (o["seen"] as? Bool) == true }
    set { TrickStore.put(KEY, ["v": 1, "seen": newValue]) }
  }
}

/* felt.lesson.v1: { v: 1, seen (the first-run offer was shown), done }; anything unreadable is a first run */
enum LessonStore {
  static let KEY = "felt.lesson.v1"
  static var rec: (seen: Bool, done: Bool) {
    get { guard let o = TrickStore.json(KEY) as? [String: Any], TrickStore.int(o["v"]) == 1 else { return (false, false) }
          let d = (o["done"] as? Bool) == true; return ((o["seen"] as? Bool) == true || d, d) }
    set { TrickStore.put(KEY, ["v": 1, "seen": newValue.seen, "done": newValue.done]) }
  }
}
