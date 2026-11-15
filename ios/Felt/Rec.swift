/* index.html's record (section 6, above 6s): games played and won, and the human shots' numbers, kept for Stats and
   records. Per game kind: played, two-player games, wins and losses against each CPU opponent; the human shots (yours
   against the CPU, both players' in a two-player game): shots, legal pots (carom: points), fouls, breaks taken and
   breaks that went well (a ball down, no foul), the best run (legal pots in one visit; carom's high run) and the
   longest pot (cm from where the ball lay to its pocket), each best with its date; snooker's frames and highest break.
   Over all kinds: the current and best run of wins against the CPU and the recent form (the last FORM_MAX results
   against the CPU). The page's v2 shape and cleaning (cleanRec), stored as JSON under the page's key, the record it
   replaces kept first (REC_PREV) and read back when the main one will not parse. Dates are the device's day. */
import Foundation
import FeltSim

struct RecBest: Codable { var v = 0; var d: String? = nil }
struct RecLevel: Codable { var w = 0, l = 0 }
struct RecKind: Codable {
  var played = 0, two = 0
  var cpu: [String: RecLevel] = ["easy": RecLevel(), "medium": RecLevel(), "hard": RecLevel()]
  var sh = 0, pot = 0, fo = 0, br = 0, brOk = 0
  var run = RecBest(), lp = RecBest()
  var frames = 0, high = 0, highD: String? = nil
}
struct RecForm: Codable { var kind: String, wl: String, level: String, d: String? }

struct Rec: Codable {
  static let KEY = "felt.record.v1", PREV = "felt.record.prev", FORM_MAX = 40, LEVELS = ["easy", "medium", "hard"]
  static let KINDS = ["8", "9", "10", "straight", "rotation", "bumper", "carom", "snooker", "heyball"]
  static let FOES = ["easy": "Rookie", "medium": "Regular", "hard": "Hustler"]
  var v = 2
  var kinds: [String: RecKind] = Dictionary(uniqueKeysWithValues: KINDS.map { ($0, RecKind()) })
  var streak = 0, best = 0, bestD: String? = nil
  var form: [RecForm] = []

  /* today(): the device's day, yyyy-mm-dd */
  static func today() -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
  }
  /* cleanRec: a count that is not a count reads as zero, a date that is not a date as none, the form's bad rows dropped */
  func cleaned() -> Rec {
    var r = Rec(), n = { (v: Int) in max(0, v) }
    let day = { (d: String?) -> String? in d.flatMap { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil ? $0 : nil } }
    for k in Rec.KINDS {
      guard let a = kinds[k] else { continue }
      var b = RecKind()
      b.played = n(a.played); b.two = n(a.two)
      for lv in Rec.LEVELS { if let o = a.cpu[lv] { b.cpu[lv] = RecLevel(w: n(o.w), l: n(o.l)) } }
      b.sh = n(a.sh); b.pot = n(a.pot); b.fo = n(a.fo); b.br = n(a.br); b.brOk = min(n(a.brOk), b.br)
      b.run = a.run.v > 0 ? RecBest(v: a.run.v, d: day(a.run.d)) : RecBest(); b.lp = a.lp.v > 0 ? RecBest(v: a.lp.v, d: day(a.lp.d)) : RecBest()
      if k == "snooker" { b.frames = n(a.frames); b.high = n(a.high); b.highD = b.high > 0 ? day(a.highD) : nil }
      r.kinds[k] = b
    }
    r.streak = n(streak); r.best = max(n(best), r.streak); r.bestD = r.best > 0 ? day(bestD) : nil
    r.form = form.filter { Rec.KINDS.contains($0.kind) && ($0.wl == "W" || $0.wl == "L") && Rec.LEVELS.contains($0.level) }.suffix(Rec.FORM_MAX).map { RecForm(kind: $0.kind, wl: $0.wl, level: $0.level, d: day($0.d)) }
    return r
  }
  static func read(_ s: String?) -> Rec? { s.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(Rec.self, from: $0) } }
  static func load() -> Rec {
    let D = UserDefaults.standard, raw = D.string(forKey: KEY)
    var o = read(raw)
    if o == nil && raw != nil { o = read(D.string(forKey: PREV)) }
    var r = (o ?? Rec()).cleaned()
    /* T7.61's interim record (wins and losses against the CPU) folds in once */
    if let old = D.dictionary(forKey: "felt.record.cpu") {
      for (k, v) in old { let p = k.split(separator: "."), a = v as? [Int] ?? []
        if p.count == 2, Rec.KINDS.contains(String(p[0])), Rec.LEVELS.contains(String(p[1])), a.count == 2 {
          r.kinds[String(p[0])]!.cpu[String(p[1])]!.w += a[0]; r.kinds[String(p[0])]!.cpu[String(p[1])]!.l += a[1]; r.kinds[String(p[0])]!.played += a[0] + a[1]
        } }
      D.removeObject(forKey: "felt.record.cpu"); r.save()
    }
    return r
  }
  func save() {
    let D = UserDefaults.standard
    if let old = D.string(forKey: Rec.KEY), Rec.read(old) != nil { D.set(old, forKey: Rec.PREV) }
    if let d = try? JSONEncoder().encode(self) { D.set(String(decoding: d, as: UTF8.self), forKey: Rec.KEY) }
  }
  /* recBest */
  static func better(_ b: inout RecBest, _ v: Int) { if v > b.v { b.v = v; b.d = today() } }
  mutating func formAdd(_ kind: String, _ won: Bool, _ level: String) {
    form.append(RecForm(kind: kind, wl: won ? "W" : "L", level: level, d: Rec.today()))
    if form.count > Rec.FORM_MAX { form.removeFirst(form.count - Rec.FORM_MAX) }
  }

  /* audit F5: a game against the CPU left before it ends (Quit, Restart, or the app closed) counts as a loss once the
     player has taken a shot in it. The first shot leaves a marker (ABANDON_KEY) that the game's end removes; one still
     there at launch is a game left by closing the app, and counts the same */
  static let ABANDON = "felt.abandon.v1"
  static func markBegun(_ kind: String, _ level: String) { UserDefaults.standard.set([kind, level], forKey: ABANDON) }
  static func dropAbandon() { UserDefaults.standard.removeObject(forKey: ABANDON) }
  @discardableResult static func countLoss(_ kind: String, _ level: String) -> Bool {
    guard KINDS.contains(kind), LEVELS.contains(level) else { return false }
    var r = load()
    r.kinds[kind]!.played += 1; r.kinds[kind]!.cpu[level]!.l += 1; r.streak = 0
    r.formAdd(kind, false, level)
    r.save()
    return true
  }
  /* boot: a game left by closing the app */
  static func abandonedAtBoot() -> Bool {
    let o = UserDefaults.standard.stringArray(forKey: ABANDON)
    dropAbandon()
    guard let o, o.count == 2 else { return false }
    return countLoss(o[0], o[1])
  }
  /* recordGame: a game's end (an exhibition or a solo mode is nobody's game) */
  static func game(_ g: Game, level: String?) {
    guard g.mode == nil, let w = g.winner else { return }
    dropAbandon()
    var r = load()
    guard r.kinds[g.kind] != nil else { return }
    r.kinds[g.kind]!.played += 1
    if let lv = level {
      if w == 0 { r.kinds[g.kind]!.cpu[lv]!.w += 1; r.streak += 1; if r.streak > r.best { r.best = r.streak; r.bestD = today() } }
      else { r.kinds[g.kind]!.cpu[lv]!.l += 1; r.streak = 0 }
      r.formAdd(g.kind, w == 0, level ?? "medium")
    } else { r.kinds[g.kind]!.two += 1 }
    r.save()
  }
  /* shotMoments' legal count: the balls down legally for the shooter (none on a foul, a push, a safety or a missed call) */
  static func legal(_ g0: Game, _ r: RuleShot, _ n: Game) -> Int {
    guard let v = n.verdict, g0.kind != "carom" else { return 0 }
    let me = g0.turn, down = (g0.kind == "snooker" ? r.potted : v.potted).filter { $0 != 0 }
    if v.foul != nil || v.call.push || v.call.safety || (v.call.need && v.call.made != true) { return 0 }
    if g0.kind == "bumper" { return down.count }
    if (g0.kind == "8" || g0.kind == "heyball") && g0.mode == nil {
      let mine = g0.groups[me]
      return down.filter { $0 == 8 ? v.win == me : g0.open || ($0 < 8 ? "solids" : "stripes") == mine }.count
    }
    return down.count
  }
  /* recordShot: a human shot's numbers. vis: the legal pots of this visit so far, this shot's included */
  static func shot(_ g0: Game, _ r: RuleShot, _ n: Game, p: Int, vis: Int, pockets: [[Double]]) {
    guard g0.mode == nil, Rec.KINDS.contains(g0.kind) else { return }
    var R = load()
    var k = R.kinds[g0.kind]!
    let v = n.verdict
    k.sh += 1
    if v?.foul != nil { k.fo += 1 }
    let m = legal(g0, r, n)
    k.pot += g0.kind == "carom" ? (v?.carom?.point == true && v?.foul == nil ? 1 : 0) : m
    if g0.breakShot { k.br += 1; if v?.foul == nil && (v?.potted ?? []).contains(where: { $0 != 0 }) { k.brOk += 1 } }
    better(&k.run, g0.kind == "carom" ? (n.high ?? [])[safe: p] ?? 0 : vis)
    /* the longest pot: a legal pot's distance from where the ball lay to its pocket */
    if m > 0 && !pockets.isEmpty {
      for x in (v?.potted ?? []).filter({ $0 != 0 }) {
        if let b = g0.balls.first(where: { $0.n == x }), let pi = r.pocketOf[x], pi >= 0, pi < pockets.count {
          better(&k.lp, Int((100 * JSMath.hypot(b.x - pockets[pi][0], b.y - pockets[pi][1])).rounded()))
        }
      }
    }
    R.kinds[g0.kind] = k
    R.save()
  }
  /* recordFrame: every finished snooker frame, and the highest break (yours against the CPU, either's with two) */
  static func frame(_ n: Game, cpu: Bool) {
    guard n.mode == nil, n.verdict?.snk?.frameOver != nil else { return }
    var R = load()
    R.kinds["snooker"]!.frames += 1
    let hi = cpu ? (n.high ?? [0])[0] : (n.high ?? [0]).max() ?? 0
    if hi > R.kinds["snooker"]!.high { R.kinds["snooker"]!.high = hi; R.kinds["snooker"]!.highD = today() }
    R.save()
  }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
