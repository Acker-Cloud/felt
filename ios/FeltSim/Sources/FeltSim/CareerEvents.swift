/* index.html's career engine, its events (busyIn to forfeitPending) and the player's side of them (eligibility, enter,
   withdraw, reportMatch, simMatch, advance), line for line on S. Reads of S are hoisted before each write into it
   (Swift's exclusivity), so the writes land in the page's order and JSON.stringify(S) stays the page's. */
import Foundation

private typealias M = JSMath

extension CareerEngine {
  static var DISCS: [String] { c("DISCS").a.map { $0.s } }

  // MARK: events: occupancy, the draw, the matches, the end
  func occ(_ ev: JV) -> [(Int, Int)] {
    let s = ev["start"]!.i, e = ev["end"]!.i
    if ev["fmt"]!.s != "league" { return [(s, e)] }
    var o: [(Int, Int)] = []
    var d = s
    while d <= e { o.append((d, d)); d += 7 }
    return o
  }
  func overlaps(_ x: JV, _ y: JV) -> Bool { let oy = occ(y); return occ(x).contains { a in oy.contains { c in a.0 <= c.1 && c.0 <= a.1 } } }
  func evById(_ id: String) -> JV? { S["cal"]!.a.first { $0["id"]!.s == id } }
  func es(_ ev: JV) -> JV? { S["es"]![ev["id"]!.s] }
  func activeIds() -> [Int] { S["pop"]!["m"]!.keys.compactMap { Int($0) }.filter { activeAI($0) }.sorted() }
  func busyIn(_ ev: JV) -> Set<Int> {
    var busy = Set<Int>()
    let id = ev["id"]!.s
    for o in S["cal"]!.a where o["id"]!.s != id {
      if let e = es(o), let f = e["f"]?.arr, overlaps(o, ev) { for p in f { busy.insert(p.i) } }
    }
    return busy
  }
  func sideOf(_ id: Int, _ vsHuman: Bool = false) -> CareerLib.Side {
    let D = Self.c("DIFFS"), adj = vsHuman && id != Self.HUMAN ? (D[S["profile"]!["difficulty"]?.str ?? "medium"] ?? D["medium"]!)["adj"]!.d : 0
    return CareerLib.Side(at: attrsOf(id), pref: prefOf(id), adj: adj)
  }
  func tplOf(_ ev: JV, _ e: JV) -> CareerLib.Bracket {
    let n = e["f"]!.count, fmt = ev["fmt"]!.s
    if fmt == "groups" {
      var G = ev["groups"]?.num.map { Int($0) } ?? 0
      if G == 0 { G = 2 }
      while G > 1 && n < G * 3 { G /= 2 }
      return G >= 2 ? CareerLib.makeBracket("groups", n, groups: G) : CareerLib.makeBracket("single", n)
    }
    if fmt == "qualifier" {
      var sl = CareerLib.nextPow2(ev["slots"]?.num.map { Int($0) } ?? 2)
      if sl == 0 { sl = 2 }
      while sl > 1 && sl * 2 > CareerLib.nextPow2(n) { sl /= 2 }
      return CareerLib.makeBracket("qualifier", n, slots: sl)
    }
    if fmt == "double" && n < 4 { return CareerLib.makeBracket("single", n) }
    return CareerLib.makeBracket(fmt, n, legs: ev["legs"]?.num.map { Int($0) } ?? 0)
  }
  func resOf(_ e: JV) -> [[Int]?] { e["r"]!.a.map { $0.arr?.map { $0.i } } }
  func ctxOf(_ T: CareerLib.Bracket, _ e: JV) -> CareerLib.Ctx { CareerLib.Ctx(T, e["f"]!.a.map { $0.i }, resOf(e)) }
  func dayOfMatch(_ ev: JV, _ T: CareerLib.Bracket, _ m: Int) -> Int {
    let s = ev["start"]!.i, dep = T.M[m].dep
    if ev["fmt"]!.s == "league" { return s + 7 * (dep - 1) }
    return s + (T.maxDep <= 1 ? 0 : Int((Double((dep - 1) * (ev["end"]!.i - s)) / Double(T.maxDep - 1)).rounded(.down)))
  }
  func pointsMap(_ key: RankKey) -> [Int: Double] { Dictionary(points(key).map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a }) }

  /* the field, at the event's start: the player if entered, any qualifiers, then AI players of the right tiers not busy
     elsewhere (invitations and finals: the circuit's top by points), seeded by circuit points, then rating */
  func draw(_ ev: JV) {
    let id = ev["id"]!.s
    if S["es"]![id] == nil { S["es"]?[id] = [:] }
    let e = S["es"]![id]!
    if e["f"] != nil || e["x"] != nil { return }
    let r = Self.R([String(S["seed"]!.i), "draw", id])
    var field: [Int] = []
    if truthy(e["en"]) { field.append(Self.HUMAN) }
    let pts = pointsMap(.circ(ev["circ"]!.i)), disc = ev["disc"]!.s
    if let opp = ev["opp"] { if activeAI(opp.i) { field.append(opp.i) } } else {
      let busy = busyIn(ev), act = activeIds().filter { !busy.contains($0) }
      for q in e["q"]?.arr ?? [] where act.contains(q.i) && !field.contains(q.i) { field.append(q.i) }
      let need = ev["size"]!.i - field.count, req = ev["req"]!, mn = req["min"]!.d
      var cands: [(Int, Double)]
      if truthy(req["top"]) {
        cands = act.filter { S["pop"]!["m"]![String($0)]!["t"]!.d >= mn && !field.contains($0) }.map { ($0, (pts[$0] ?? 0) * 1000 + ratingOf($0, disc)) }
      } else {
        let mx = req["max"]!.d, evPts = ev["pts"]!.d, tier = ev["tier"]!.d
        cands = []
        for i in act {
          let t = S["pop"]!["m"]![String(i)]!["t"]!.d
          if !(t >= mn && t <= mx && !field.contains(i)) { continue }
          let v = (pts[i] ?? 0) / Swift.max(1, evPts) * 4 + ratingOf(i, disc) + (prefOf(i) == disc ? 8 : 0) + (t == tier ? 6 : 0) + r() * 18
          cands.append((i, v))
        }
      }
      cands.sort { a, b in a.1 != b.1 ? a.1 > b.1 : a.0 < b.0 }
      var i = 0
      while i < need && i < cands.count { field.append(cands[i].0); i += 1 }
    }
    let key = { (i: Int) in (pts[i] ?? 0, self.ratingOf(i, disc)) }
    let keys = Dictionary(field.map { ($0, key($0)) }, uniquingKeysWith: { a, _ in a })
    field.sort { a, b in let ka = keys[a]!, kb = keys[b]!; return kb.0 != ka.0 ? kb.0 < ka.0 : kb.1 != ka.1 ? kb.1 < ka.1 : a < b }
    if field.count < 2 {
      S["es"]?[id]?["x"] = 1
      if truthy(e["en"]) { let name = ev["name"]!.s; pay(ev["fee"]!.d, "refund", name + " (cancelled)"); news("\(name) was cancelled. Entry fee refunded.") }
      return
    }
    let fv: JV = .arr(field.map { .n($0) })
    S["es"]?[id]?["f"] = fv
    let T = tplOf(ev, S["es"]![id]!), rv: JV = .arr(T.M.map { _ in .null })
    S["es"]?[id]?["r"] = rv
  }
  /* AI matches due by upto are played by the model (the player's wait for reportMatch); an event with nothing left ends */
  @discardableResult func resolveEvent(_ ev: JV, _ upto0: Int? = nil) -> Bool {
    let upto = upto0 ?? S["day"]!.i, id = ev["id"]!.s
    guard let e = S["es"]![id], e["f"] != nil, !truthy(e["done"]) else { return false }
    let T = tplOf(ev, e), f = e["f"]!.a.map { $0.i }
    var res = resOf(e)
    var c = CareerLib.Ctx(T, f, res), changed = true
    while changed {
      changed = false
      for m in T.M.indices {
        if res[m] != nil { continue }
        let o = CareerLib.outcome(c, m)
        if o.st != "ready" || o.a == Self.HUMAN || o.b == Self.HUMAN || dayOfMatch(ev, T, m) > upto { continue }
        let s = CareerLib.playModel(sideOf(o.a!), sideOf(o.b!), ev["disc"]!.s, ev["race"]!.i, Double(CareerLib.seedOf([String(S["seed"]!.i), id, String(m)]))).s
        res[m] = s
        let sv: JV = .arr(s.map { .n($0) })
        S["es"]?[id]?["r"]?[m] = sv
        c = CareerLib.Ctx(T, f, res); changed = true
      }
    }
    if !CareerLib.complete(c) { return false }
    finalize(ev)
    return true
  }
  func ptsShare(_ place: Int, _ n: Int, _ fmt: String) -> Double {
    let p = Double(place), nn = Double(n)
    if fmt == "rr" || fmt == "league" {
      return place == 1 ? 1 : place <= Int((nn / 2).rounded(.up)) ? Swift.max(0.1, 0.75 - 0.6 * (p - 2) / Swift.max(1, nn - 2)) : 0
    }
    return place == 1 ? 1 : place == 2 ? 0.65 : place <= 4 ? 0.42 : place <= 8 ? 0.26 : p > nn / 2 ? 0 : place <= 16 ? 0.14 : place <= 32 ? 0.07 : 0
  }
  func prizeW(_ place: Int) -> Double { place == 1 ? 0.32 : place == 2 ? 0.19 : place <= 4 ? 0.095 : place <= 8 ? 0.045 : place <= 16 ? 0.02 : place <= 32 ? 0.01 : 0 }
  /* the purse paid out by place, the remainder to the winner, so the payouts always add up to the purse */
  func payouts(_ ev: JV, _ pl: [[Int]]) -> [(Int, Double)] {
    var out: [(Int, Double)] = []
    let tot = pl.reduce(0.0) { $0 + prizeW($1[1]) }, purse = ev["purse"]?.num ?? 0
    if tot == 0 || purse == 0 { return out }
    var paid = 0.0
    for x in pl { let v = (purse * prizeW(x[1]) / tot).rounded(.down); if v != 0 { out.append((x[0], v)); paid += v } }
    let w = pl[0][0]
    if let i = out.firstIndex(where: { $0.0 == w }) { out[i].1 += purse - paid } else { out.append((w, purse - paid)) }
    return out
  }
  func ranked(_ ev: JV) -> Bool { !["challenge", "exhibition", "qualifier"].contains(ev["kind"]!.s) }
  func hasFinal(_ ev: JV) -> Bool { ["single", "double", "groups"].contains(ev["fmt"]!.s) }
  func legacyOf(_ ev: JV, _ place: Int) -> Double {
    let t = ev["tier"]!.d
    return !ranked(ev) ? 0 : place == 1 ? CareerLib.round(t * t * ev["pres"]!.d / 70) : place == 2 && hasFinal(ev) ? t * 2 : 0
  }
  func popNum(_ id: Int, _ k: String) -> Double { S["pop"]!["m"]![String(id)]?[k]?.num ?? 0 }
  func finalize(_ ev: JV) {
    let id = ev["id"]!.s
    if truthy(S["es"]![id]!["done"]) { return }
    S["es"]?[id]?["done"] = 1
    let e = S["es"]![id]!, T = tplOf(ev, e), f = e["f"]!.a.map { $0.i }, res = resOf(e)
    let pl = CareerLib.placings(T, f, res), n = pl.count, sea = seasonOf(ev["start"]!.i), di = Self.DISCS.firstIndex(of: ev["disc"]!.s) ?? -1
    if truthy(ev["pts"]) {
      var aw = S["aw"]!.a
      for x in pl { let v = CareerLib.round(ev["pts"]!.d * ptsShare(x[1], n, ev["fmt"]!.s)); if v > 0 { aw.append([.n(x[0]), ev["circ"]!, .n(di), .n(v), .n(gweek(ev["end"]!.i)), .n(sea)]) } }
      S["aw"] = .arr(aw)
      let awc = S["awc"]!.d + 1; S["awc"] = .n(awc)
    }
    let c = CareerLib.Ctx(T, f, res)
    for m in T.M.indices {
      let o = CareerLib.outcome(c, m)
      if o.st != "done" { continue }
      if o.w != Self.HUMAN { let v = popNum(o.w!, "w") + 1; mut(o.w!, "w", .n(v)) }
      if o.l != Self.HUMAN { let v = popNum(o.l!, "l") + 1; mut(o.l!, "l", .n(v)) }
    }
    if ranked(ev) {
      if let ser = ev["ser"], ser.truthy {
        let k = String(ser.i)
        var a = S["ch"]![k]?.arr ?? []
        a.append([.n(sea), .n(pl[0][0])])
        S["ch"]?[k] = .arr(a)
      }
      for x in pl {
        let p = x[0], place = x[1]
        if p == Self.HUMAN || place > 2 { continue }
        if S["pop"]!["m"]![String(p)] == nil { S["pop"]?["m"]?[String(p)] = [:] }
        if place == 1 {
          let ti = popNum(p, "ti") + 1; mut(p, "ti", .n(ti))
          var tl = S["pop"]!["m"]![String(p)]!["tl"]?.arr ?? []
          tl.append([.n(sea), .n(ev["ser"]?.num ?? 0), ev["tier"]!])
          if tl.count > 20 { tl.removeFirst() }
          mut(p, "tl", .arr(tl))
        }
        if place == 1 || hasFinal(ev) { let fi = popNum(p, "fi") + 1; mut(p, "fi", .n(fi)) }
        let lg = popNum(p, "lg") + legacyOf(ev, place); mut(p, "lg", .n(lg))
      }
    }
    if ev["kind"]!.s == "qualifier" {
      let q = pl.filter { $0[1] == 1 }.map { $0[0] }
      if let tgt = ev["tgt"], tgt.truthy {
        let tk = tgt.s
        if S["es"]![tk] == nil { S["es"]?[tk] = [:] }
        let qv: JV = .arr(q.filter { $0 != Self.HUMAN }.map { .n($0) })
        S["es"]?[tk]?["q"] = qv
      }
      if q.contains(Self.HUMAN) {
        if let tgt = ev["tgt"], tgt.truthy { S["me"]?["qual"]?[tgt.s] = 1; let t = evById(tgt.s); news("Qualified for \(t?["name"]?.s ?? "the main event").") }
        if let card = ev["card"], card.truthy {
          let v = Swift.max(S["me"]!["card"]!.d, card.d); S["me"]?["card"] = .n(v)
          news("Tour card won: \(Self.c("TIERS")[card.i]!["name"]!.s) next season, if your results earn the step up.")
        }
      }
    }
    mlAdd(ev, pl)
    if let mine = pl.first(where: { $0[0] == Self.HUMAN }) {
      humanFinish(ev, mine[1], n, payouts(ev, pl).first { $0.0 == Self.HUMAN }?.1 ?? 0); bound("event")
    } else if ranked(ev) && ev["tier"]!.i >= 9 { news("\(nameOf(pl[0][0])) wins the \(ev["name"]!.s).") }
  }

  // MARK: the money list and the rating
  func mlAdd(_ ev: JV, _ pl: [[Int]]) {
    if ev["tier"]!.i < 8 { return }
    let sea = seasonOf(ev["start"]!.i), sk = String(sea)
    if S["ml"]![sk] == nil { S["ml"]?[sk] = [:] }
    for (id, v) in payouts(ev, pl) { let k = String(id), nv = (S["ml"]![sk]![k]?.num ?? 0) + v; S["ml"]?[sk]?[k] = .n(nv) }
    for k in S["ml"]!.keys where Int(k)! < sea - 1 { S["ml"]?[k] = nil }
  }
  public func moneyList(_ sea0: Int? = nil) -> [(Int, Double)] {
    let sea = sea0 ?? season
    var t: [Int: Double] = [:], order: [Int] = []
    for y in [sea - 1, sea] { let row = S["ml"]![String(y)]; for k in row?.keys ?? [] { let id = Int(k)!; if t[id] == nil { order.append(id) }; t[id] = (t[id] ?? 0) + row![k]!.d } }
    return order.map { ($0, t[$0]!) }.filter { $0.0 == Self.HUMAN || activeAI($0.0) }.sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0 < b.0 }
  }
  public func moneyRank(_ sea: Int? = nil) -> Int { (moneyList(sea).firstIndex { $0.0 == Self.HUMAN }).map { $0 + 1 } ?? 0 }
  func inviteRank() -> Int {
    guard let row = S["ml"]![String(season - 1)], let mine = row[String(Self.HUMAN)]?.num, mine != 0 else { return 0 }
    return 1 + row.keys.filter { k in let id = Int(k)!; return id != Self.HUMAN && activeAI(id) && row[k]!.d > mine }.count
  }
  public static func rackOdds(_ a: Double, _ b: Double) -> Double { 1 / (1 + M.pow(2, (b - a) / 100)) }
  public static func raceOdds(_ p: Double, _ race: Int) -> Double {
    var out = 0.0, c = 1.0
    for k in 0..<race { out += c * M.pow(p, Double(race)) * M.pow(1 - p, Double(k)); c = c * Double(race + k) / Double(k + 1) }
    return out
  }
  func frOf(_ id: Int) -> Double { id == Self.HUMAN ? S["me"]!["fr"]!.d : CareerLib.round(CareerLib.rate(attrsOf(id), popAt(id).disc, popAt(id).disc) * Self.c("FR_K").d) }
  func frBook(_ opp: Int, _ my: Int, _ op: Int) {
    let n = my + op
    if n == 0 { return }
    let k = Swift.min(1, Self.c("FR_RACKS").d / Double(n)), e = Self.rackOdds(S["me"]!["fr"]!.d, frOf(opp))
    let v = CareerLib.round(Self.cl(S["me"]!["fr"]!.d + Self.c("FR_STEP").d * k * (Double(my) - e * Double(n)), 100, 1400))
    S["me"]?["fr"] = .n(v)
  }

  // MARK: the player
  func bound(_ k: String) { if !bounds.contains(k) { bounds.append(k) } }
  func addSkill(_ k: String, _ xp: Double) { let v = S["me"]!["sk"]![k]!.d, nv = Self.r2(Swift.min(99, v + xp * 0.14 / (1 + v / 20))); S["me"]?["sk"]?[k] = .n(nv) }
  public func nameOf(_ id: Int) -> String { id == Self.HUMAN ? S["profile"]!["name"]!.s : popAt(id).name }
  static func inc(_ b: inout JV, _ k: String, _ by: Double = 1) { let v = (b[k]?.num ?? 0) + by; b[k] = .n(v) }
  /* the player's side of a played match: stats, the season, head to head, skills, reputation, records, rivals, sponsors */
  func bookMatch(_ ev: JV, _ T: CareerLib.Bracket, _ m: Int, _ opp: Int, _ my: Int, _ op: Int, _ res: MatchReport) {
    let won = my > op, fin = T.M[m].fin, forfeit = res.forfeit, disc = ev["disc"]!.s
    if !forfeit { frBook(opp, my, op) }
    var racks = !forfeit ? res.racks : nil
    if let rk = racks, disc != "straight" && disc != "carom" && (rk.count != my + op || rk.filter { $0.won }.count != my) { racks = nil }
    let sh = !forfeit ? res.shots : nil
    _ = statD(disc)
    for path in [["st", "all"], ["st", "d", disc]] {
      var b = path.count == 2 ? S["st"]!["all"]! : S["st"]!["d"]![disc]!
      Self.inc(&b, "m")
      if won { Self.inc(&b, "w"); let st = b["st"]!.d; b["st"] = .n(st > 0 ? st + 1 : 1); b["bs"] = .n(Swift.max(b["bs"]!.d, b["st"]!.d)) }
      else { Self.inc(&b, "l"); let st = b["st"]!.d; b["st"] = .n(st < 0 ? st - 1 : -1); b["ls"] = .n(Swift.max(b["ls"]!.d, -b["st"]!.d)) }
      if !forfeit { Self.inc(&b, "rw", Double(my)); Self.inc(&b, "rl", Double(op)) }
      if let rk = racks { for k in rk { Self.inc(&b, "rk"); if k.broke { Self.inc(&b, "br"); if k.legal == true { Self.inc(&b, "lb") }; if k.bnr { Self.inc(&b, "bnr") } }; if k.runout { Self.inc(&b, "ro") } } }
      if let s = sh {
        let att = s.att, pot = Swift.min(s.pot, att), calls = s.calls, safe = s.safe
        Self.inc(&b, "sa", Double(att)); Self.inc(&b, "sp", Double(pot)); Self.inc(&b, "ca", Double(calls)); Self.inc(&b, "cm", Double(Swift.min(s.callsOk, calls)))
        Self.inc(&b, "sf", Double(safe)); Self.inc(&b, "ss", Double(Swift.min(s.safeOk, safe))); Self.inc(&b, "fo", Double(s.fouls)); Self.inc(&b, "sc", Double(Swift.min(s.scratches, s.fouls)))
      }
      if path.count == 2 { S["st"]?["all"] = b } else { S["st"]?["d"]?[disc] = b }
    }
    var ss = S["ss"]!
    Self.inc(&ss, "m"); if won { Self.inc(&ss, "w") } else { Self.inc(&ss, "l") }
    S["ss"] = ss
    let myR = ratingOf(Self.HUMAN, disc), opR = ratingOf(opp, disc), race = ev["race"]!.i
    let ok = String(opp)
    var h = S["h2h"]![ok]?.a.map { $0.d } ?? [0, 0, 0, 0, 0, 0, 0, 0, 0]
    h[won ? 0 : 1] += 1
    if fin { h[won ? 2 : 3] += 1 }
    if won && opR >= myR + 6 { h[4] += 1 }
    if !won && opR <= myR - 6 { h[5] += 1 }
    if !forfeit && Swift.min(my, op) == race - 1 { h[6] += 1 }
    h[7] = won ? (h[7] > 0 ? h[7] + 1 : 1) : (h[7] < 0 ? h[7] - 1 : -1)
    h[8] = Double(season)
    S["h2h"]?[ok] = .arr(h.map { .n($0) })
    if h[0] + h[1] == 10 { news("Ten meetings with \(nameOf(opp)): \(Int(h[0]))-\(Int(h[1])).") }
    if won && h[0] == 1 && h[1] >= 3 { news("First win over \(nameOf(opp)) at the \(Int(h[1]) + 1)th attempt.") }
    if !forfeit {
      let xp = won ? 2.0 : 1.4
      for k in Self.c("SKILLS").a { addSkill(k.s, xp * 0.4) }
      if let rk = racks { addSkill("brk", Double(rk.filter { $0.broke }.count) * 0.5); addSkill("pos", Double(rk.filter { $0.runout }.count) * 0.6) }
      if let s = sh { addSkill("aim", Double(s.pot) * 0.05); addSkill("safety", Double(s.safeOk) * 0.3) }
      if Swift.min(my, op) == race - 1 { addSkill("pressure", 1.5) }
      if won && opR > myR { addSkill("tactics", 1) }
    }
    if won { let rep = S["me"]!["rep"]!.d + Swift.max(1, CareerLib.round(ev["tier"]!.d / 3)) + (opR >= myR + 6 ? ev["tier"]!.d : 0); S["me"]?["rep"] = .n(rep) }
    var rb = S["rb"]!
    let sea = Double(season), evName = ev["name"]!
    if S["st"]!["all"]!["bs"]!.d > (rb["streak"]?[0]?.num ?? 0) { rb["streak"] = [S["st"]!["all"]!["bs"]!, .n(sea)] }
    if won && opR - myR > (rb["upset"]?[0]?.num ?? 0) { rb["upset"] = [.n(CareerLib.round(opR - myR)), .n(opp), .n(sea), evName] }
    if !forfeit && Double(my + op) > (rb["longest"]?[0]?.num ?? 0) { rb["longest"] = [.n(my + op), .n(opp), .n(sea), evName] }
    S["rb"] = rb
    rivalObjectives(opp, won, fin)
    checkSponsors()
  }
  func placeWords(_ p: Int) -> String {
    p == 1 ? "champion" : p == 2 ? "runner-up" : "\(p)\(p % 10 == 1 && p != 11 ? "st" : p % 10 == 2 && p != 12 ? "nd" : p % 10 == 3 && p != 13 ? "rd" : "th") place"
  }
  func humanFinish(_ ev: JV, _ place: Int, _ n: Int, _ prize: Double) {
    let t = ev["tier"]!.d, title = place == 1 && ranked(ev), final = (place == 1 || place == 2) && hasFinal(ev) && ranked(ev), disc = ev["disc"]!.s
    _ = statD(disc)
    for all in [true, false] {
      var b = all ? S["st"]!["all"]! : S["st"]!["d"]![disc]!
      Self.inc(&b, "ev"); if title { Self.inc(&b, "ti") }; if final { Self.inc(&b, "fi") }; Self.inc(&b, "prize", prize)
      if all { S["st"]?["all"] = b } else { S["st"]?["d"]?[disc] = b }
    }
    var ss = S["ss"]!
    Self.inc(&ss, "ev"); if title { Self.inc(&ss, "ti"); ss["tt"] = .n(Swift.max(ss["tt"]!.d, t)) }; if final { Self.inc(&ss, "fi") }; Self.inc(&ss, "prize", prize)
    S["ss"] = ss
    let name = ev["name"]!.s
    if prize != 0 { pay(prize, "prize", "\(name), \(placeWords(place))") }
    let presF = ev["pres"]!.d / 70
    let rep = S["me"]!["rep"]!.d + (title ? CareerLib.round(4 * t * presF) : final ? 2 * t : Double(place) <= Double(n) / 4 ? (t / 2).rounded(.up) : 0)
    S["me"]?["rep"] = .n(rep)
    let leg = S["me"]!["leg"]!.d + legacyOf(ev, place); S["me"]?["leg"] = .n(leg)
    if title {
      var tl = S["me"]!["tl"]!.a; tl.append([.n(season), .str(name), .n(t)]); S["me"]?["tl"] = .arr(tl)
      news("Champion: \(name).")
      sponsorOffers("title")
    } else { news("\(name): \(placeWords(place))\(prize != 0 ? ", \(JV.numberString(prize)) cr" : "").") }
    if S["rb"]!["finish"] == nil { S["rb"]?["finish"] = [:] }
    let tk = String(Int(t)), bf = S["rb"]!["finish"]![tk]
    if ranked(ev) && (bf == nil || Double(place) < bf![0]!.d) { let v: JV = [.n(place), .n(season), .str(name)]; S["rb"]?["finish"]?[tk] = v }
    checkSponsors()
  }

  // MARK: the player's next match
  public struct Pending { public let ev: JV, T: CareerLib.Bracket, m: Int, o: CareerLib.Outcome }
  func myPending(_ upto0: Int? = nil) -> Pending? {
    let upto = upto0 ?? S["day"]!.i
    for ev in S["cal"]!.a {
      guard let e = es(ev), truthy(e["en"]), e["f"] != nil, !truthy(e["done"]) else { continue }
      let T = tplOf(ev, e), c = ctxOf(T, e)
      for m in T.M.indices where e["r"]![m] == .null {
        let o = CareerLib.outcome(c, m)
        if o.st == "ready" && (o.a == Self.HUMAN || o.b == Self.HUMAN) && dayOfMatch(ev, T, m) <= upto { return Pending(ev: ev, T: T, m: m, o: o) }
      }
    }
    return nil
  }

  // MARK: rivals
  func rivalObjectives(_ opp: Int, _ won: Bool, _ fin: Bool) {
    var obj = S["obj"]!.a
    let day = S["day"]!.d
    for i in obj.indices {
      let o = obj[i]
      if truthy(o["done"]) || o["id"]!.i != opp { continue }
      let k = o["k"]!.s
      var done = false
      if k == "beat" && won { done = true }
      if k == "final" && won && fin { done = true }
      if k == "streak" && won && S["h2h"]![String(opp)]![7]!.d >= o["n"]!.d { done = true }
      if done {
        obj[i]["done"] = .n(day)
        S["obj"] = .arr(obj)
        pay(o["pay"]!.d, "reward", "Rivalry: \(o["text"]!.s)")
        let rep = S["me"]!["rep"]!.d + 5; S["me"]?["rep"] = .n(rep)
        news("Rivalry objective done: \(o["text"]!.s).")
      }
    }
    obj = obj.filter { !truthy($0["done"]) || $0["done"]!.d > day - 112 }
    S["obj"] = .arr(obj)
    for id in rivalList(3) {
      if S["obj"]!.a.contains(where: { $0["id"]!.i == id && (!truthy($0["done"]) || $0["done"]!.d > day - 56) }) { continue }
      let h = S["h2h"]![String(id)]!.a.map { $0.d }, name = nameOf(id), t = S["me"]!["tier"]!.d
      let k = h[1] > h[0] ? "beat" : h[2] + h[3] > 0 ? "final" : "streak"
      let text = k == "beat" ? "Beat \(name) at your next meeting" : k == "final" ? "Beat \(name) in a final" : "Beat \(name) three times running"
      var ob = S["obj"]!.a
      ob.append(["id": .n(id), "k": .str(k), "n": 3, "text": .str(text), "pay": .n(5 * t * t), "from": .n(day)])
      S["obj"] = .arr(ob)
    }
  }

  // MARK: days
  func enterDay(_ d: Int) {
    S["day"] = .n(d)
    if d % Self.YEAR == 0 && d > 0 { rollSeason() }
    if d % 7 == 0 { weekly() }
    for ev in S["cal"]!.a where ev["start"]!.i <= d {
      if let e = es(ev), e["f"] != nil || e["x"] != nil { continue }
      draw(ev)
    }
    resolveAll()
  }
  func resolveAll(_ upto: Int? = nil) {
    for ev in S["cal"]!.a { if let e = es(ev), e["f"] != nil, !truthy(e["done"]) { resolveEvent(ev, upto) } }
  }
  @discardableResult func forfeitPending() -> Bool {
    guard let p = myPending(Int.max) else { return false }
    let race = p.ev["race"]!.i, side = p.o.a == Self.HUMAN ? 0 : 1, id = p.ev["id"]!.s
    let rv: JV = side == 0 ? [0, .n(race)] : [.n(race), 0]
    S["es"]?[id]?["r"]?[p.m] = rv
    bookMatch(p.ev, p.T, p.m, side == 1 ? p.o.a! : p.o.b!, 0, race, MatchReport(forfeit: true))
    return true
  }

  // MARK: the API: entries, matches, time
  func live() -> String? { S["me"]!["ret"]!.truthy ? "retired" : nil }
  /* why the player may or may not enter an event */
  public func eligibility(_ ev: JV) -> [String] {
    var why: [String] = []
    let me = S["me"]!, e = es(ev) ?? [:], id = ev["id"]!.s, req = ev["req"]!, tier = me["tier"]!.d
    if me["ret"]!.truthy { why.append("retired") }
    if truthy(e["en"]) { why.append("already entered") }
    if S["day"]!.d > ev["dl"]!.d { why.append("entries closed") }
    if ev["opp"] != nil { why.append("by invitation") }
    let q = truthy(req["qual"]) && truthy(me["qual"]![id])
    if !q && tier < req["min"]!.d { why.append("tier \(req["min"]!.i) and up") }
    if tier > req["max"]!.d { why.append("tier \(req["max"]!.i) and below") }
    if let top = req["top"], top.truthy {
      let rk = rankOf(Self.HUMAN, .circ(ev["circ"]!.i)), ml = ev["kind"]!.s == "invitational" ? inviteRank() : 0
      if (rk == nil || Double(rk!) > top.d) && !(ml != 0 && Double(ml) <= Self.c("INVITE_TOP").d) { why.append("top \(top.i) of the \(Self.c("CIRC_NAMES")[ev["circ"]!.i]!.s) rankings") }
    }
    if let clash = S["cal"]!.a.first(where: { o in o["id"]!.s != id && es(o).map { truthy($0["en"]) && !truthy($0["done"]) } == true && overlaps(o, ev) }) { why.append("clashes with \(clash["name"]!.s)") }
    if me["money"]!.d < ev["fee"]!.d + ev["trav"]!.d { why.append("not enough credits") }
    return why
  }
  @discardableResult public func enter(_ id: String) -> [String] {
    if let no = live() { return [no] }
    guard let ev = evById(id) else { return ["no such event"] }
    let why = eligibility(ev)
    if !why.isEmpty { return why }
    let name = ev["name"]!.s
    pay(-ev["fee"]!.d, "fee", name)
    pay(-ev["trav"]!.d, "travel", name)
    if S["es"]![id] == nil { S["es"]?[id] = [:] }
    S["es"]?[id]?["en"] = 1
    return []
  }
  @discardableResult public func withdraw(_ id: String) -> String? {
    if let no = live() { return no }
    guard let ev = evById(id), let e = S["es"]![id], truthy(e["en"]), e["f"] == nil else { return "not entered or already drawn" }
    if S["day"]!.d > ev["dl"]!.d { return "entries closed" }
    S["es"]?[id]?["en"] = nil
    pay(ev["fee"]!.d, "refund", ev["name"]!.s)
    return nil
  }
  public struct MatchReport {
    public struct Shots { public var att = 0, pot = 0, calls = 0, callsOk = 0, safe = 0, safeOk = 0, fouls = 0, scratches = 0 }
    public var score: [Int]? = nil, racks: [CareerLib.Rack]? = nil, shots: Shots? = nil, forfeit = false
    public init(score: [Int]? = nil, racks: [CareerLib.Rack]? = nil, shots: Shots? = nil, forfeit: Bool = false) { self.score = score; self.racks = racks; self.shots = shots; self.forfeit = forfeit }
  }
  /* the player's match result: nil on success, else why not */
  @discardableResult public func reportMatch(_ res: MatchReport) -> String? {
    if let no = live() { return no }
    guard let p = myPending() else { return "no match to play" }
    let race = p.ev["race"]!.i
    var my = 0, op = race
    if !res.forfeit {
      guard let s = res.score, s.count == 2, s.allSatisfy({ $0 >= 0 && $0 <= race }) else { return "bad score" }
      my = s[0]; op = s[1]
      if Swift.max(my, op) != race || my == op { return "one side must reach \(race)" }
    }
    bounds = []
    let side = p.o.a == Self.HUMAN ? 0 : 1, opp = side == 1 ? p.o.a! : p.o.b!, id = p.ev["id"]!.s
    let rv: JV = side == 0 ? [.n(my), .n(op)] : [.n(op), .n(my)]
    S["es"]?[id]?["r"]?[p.m] = rv
    bookMatch(p.ev, p.T, p.m, opp, my, op, res)
    bound("match")
    resolveEvent(p.ev)
    return nil
  }
  /* the player's match settled by the match model (their skills against the opponent) */
  @discardableResult public func simMatch() -> String? {
    if let no = live() { return no }
    guard let p = myPending() else { return "no match to play" }
    let opp = p.o.a == Self.HUMAN ? p.o.b! : p.o.a!, id = p.ev["id"]!.s
    let r = CareerLib.playModel(sideOf(Self.HUMAN), sideOf(opp, true), p.ev["disc"]!.s, p.ev["race"]!.i, Double(CareerLib.seedOf([String(S["seed"]!.i), id, String(p.m), "me"])), detail: true)
    let sum = { (k: KeyPath<CareerLib.Rack, Int>) in r.racks.reduce(0) { $0 + $1[keyPath: k] } }
    let calls = p.ev["rules"]!["call"]!["require"]!.s == "off" ? 0 : sum(\.att)
    let sh = MatchReport.Shots(att: sum(\.att), pot: sum(\.pot), calls: calls, callsOk: calls != 0 ? sum(\.pot) : 0, safe: sum(\.sf), safeOk: sum(\.ss), fouls: sum(\.fo), scratches: sum(\.sc))
    return reportMatch(MatchReport(score: r.s, racks: r.racks, shots: sh))
  }
  /* time moves only here: days ahead, or "week". It stops early on a match of the player's that is due (unless forfeit).
     The stop: "match", "season" or nil */
  @discardableResult public func advance(days: Int? = nil, week: Bool = false, forfeit: Bool = false, stopAtSeason: Bool = false) -> String? {
    if live() != nil { return nil }
    bounds = []
    let day = S["day"]!.i
    let target = week ? (day / 7 + 1) * 7 : day + Swift.max(0, days ?? 1)
    while true {
      if myPending() != nil { if forfeit { while forfeitPending() { resolveAll() }; continue }; return "match" }
      if S["day"]!.i >= target { break }
      enterDay(S["day"]!.i + 1)
      if bounds.contains("season") && stopAtSeason { return "season" }
    }
    return nil
  }
}
