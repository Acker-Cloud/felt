/* index.html 5d's drill records, the page's key and shape: felt.drills.v1 = { v: 1, d: { id: { best, n, hist: [[score,
   day]] (the last DRILL_HIST) } } }; anything malformed is dropped on load (loadDrills), never trusted. A medal is the
   drill's tier for the best score. */
import Foundation
import FeltSim

struct DrillRec { var best: Int, n: Int, hist: [(Int, String)] }
enum DrillStore {
  static let KEY = "felt.drills.v1", HIST = 20
  static func isScore(_ v: Any?) -> Int? { (v as? NSNumber).flatMap { $0.doubleValue == Double($0.intValue) && (0...100).contains($0.intValue) ? $0.intValue : nil } }
  static func realDay(_ s: String) -> Bool {
    guard s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
    let p = s.split(separator: "-").map { Int($0)! }
    var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    guard let d = cal.date(from: c) else { return false }
    let back = cal.dateComponents([.month, .day], from: d)
    return back.month == p[1] && back.day == p[2]
  }
  static var all: [String: DrillRec] {
    get {
      var out: [String: DrillRec] = [:]
      guard let s = UserDefaults.standard.string(forKey: KEY), let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
            (o["v"] as? NSNumber)?.intValue == 1, let d = o["d"] as? [String: Any] else { return out }
      for x in DRILL_LIB {
        guard let r = d[x.id] as? [String: Any] else { continue }
        let hist = ((r["hist"] as? [Any]) ?? []).compactMap { h -> (Int, String)? in
          guard let a = h as? [Any], a.count >= 2, let v = isScore(a[0]), let day = a[1] as? String, realDay(day) else { return nil }
          return (v, day)
        }.suffix(HIST)
        let best = max(isScore(r["best"]) ?? 0, hist.map(\.0).max() ?? 0)
        let n0 = (r["n"] as? NSNumber).flatMap { $0.doubleValue == Double($0.intValue) && $0.intValue > 0 ? $0.intValue : nil } ?? 0, n = max(n0, hist.count)
        if n > 0 { out[x.id] = DrillRec(best: best, n: n, hist: Array(hist)) }
      }
      return out
    }
    set {
      var d: [String: Any] = [:]
      for (k, r) in newValue { d[k] = ["best": r.best, "n": r.n, "hist": r.hist.map { [$0.0, $0.1] }] }
      if let j = try? JSONSerialization.data(withJSONObject: ["v": 1, "d": d], options: [.sortedKeys]) { UserDefaults.standard.set(String(decoding: j, as: UTF8.self), forKey: KEY) }
    }
  }
  static var medals: Int { let a = all; return DRILL_LIB.reduce(0) { sum, d in sum + (a[d.id].map { drillTier(d, $0.best) } ?? 0) } }
  /* dayWords: "15 Nov" */
  static func dayWords(_ s: String) -> String {
    let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(Int(s.suffix(2)) ?? 1) \(m[max(0, min(11, (Int(s.dropFirst(5).prefix(2)) ?? 1) - 1))])"
  }
}
