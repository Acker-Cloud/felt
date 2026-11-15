/* index.html's career engine, its seasons (rollSeason, aiSeason), line for line on S: the season's end settles
   anything unfinished, moves the player and every AI player between tiers by their form, keeps or takes a tour card
   on the money list, writes the season's line in the archive and the press, retires and replaces AI players, and
   draws the next season's calendar. */
import Foundation

extension CareerEngine {
  func me(_ k: String) -> JV { S["me"]![k]! }
  func setMe(_ k: String, _ v: JV) { S["me"]?[k] = v }

  func rollSeason() {
    let old = season - 1
    /* anything unfinished ends now (an unplayed match of the player's is forfeited) */
    for ev in S["cal"]!.a {
      guard let e = es(ev), e["f"] != nil, !truthy(e["done"]) else { continue }
      while truthy(es(ev)!["en"]) && forfeitPending() {}
      resolveEvent(ev, Int.max)
    }
    let spts = pointsMap(.season, gweek(S["day"]!.i) - 1)
    var played: [Int: Int] = [:]
    for ev in S["cal"]!.a { if let e = es(ev), truthy(e["done"]), truthy(ev["pts"]) { for p in e["f"]!.a { played[p.i, default: 0] += 1 } } }
    let form = { (id: Int) -> Double in (spts[id] ?? 0) / Double(Swift.max(3, played[id] ?? 0)) }
    let tier0 = me("tier").i, ss = S["ss"]!, ssm = ss["m"]!.d, wr = ssm != 0 ? ss["w"]!.d / ssm : 0, tt = ss["tt"]!.d
    let pool = activeIds().filter { S["pop"]!["m"]![String($0)]!["t"]!.i == tier0 }, mine = form(Self.HUMAN)
    let better = pool.filter { form($0) > mine }.count, frac = Double(better) / Double(Swift.max(1, pool.count))
    let t0 = tier0
    var moved = "stay"
    let TIERS = Self.c("TIERS")
    /* a title promotes only below tier 7: above it the step up is earned over a season */
    if tier0 < 11 && ((tier0 < 7 && tt >= Double(tier0)) || (frac <= 0.15 && wr >= 0.5 && ssm >= 6)) {
      let to = tier0 + 1
      if (to == 8 || to == 10) && me("card").d < Double(to) { news("Promotion to \(TIERS[to]!["name"]!.s) needs a tour card from the qualifier.") }
      else { setMe("tier", .n(to)); moved = "up"; if to >= 8 { setMe("cardAt", .n(old + 1)) } }
    } else if tier0 > 1 && tier0 < 12 && tt < Double(tier0) && ((ssm >= 4 && frac >= 0.6 && wr < 0.4) || (ssm == 0 && tier0 >= 4)) { setMe("tier", .n(tier0 - 1)); moved = "down" }
    /* the stakes: from tier 8, a card is kept on the two-year money list, after one full season to earn on it */
    let mlr = moneyRank(old)
    let hofDue = !me("hof").truthy && me("leg").d >= Self.c("HOF_LEG").d && t0 >= 11
    let tier1 = me("tier").i
    if moved == "stay" && !hofDue && tier1 >= 8 && tier1 < 12 && Double(old) > me("cardAt").d && (mlr == 0 || Double(mlr) > Self.c("CARD_KEEP").d) {
      setMe("tier", .n(tier1 >= 10 ? 9 : 7)); setMe("card", 0); moved = "down"
      news("Tour card lost: \(mlr != 0 ? "number \(mlr)" : "not") on the money list. The qualifier is the way back.")
    }
    let gw1 = gweek(S["day"]!.i) - 1
    let circRank: [JV] = Self.c("CIRCUITS").a.indices.map { i in rankOf(Self.HUMAN, .circ(i), gw1).map { .n($0) } ?? .null }
    let bestEv = stableSorted(me("tl").a.filter { $0[0]!.i == old }) { $0[2]!.d > $1[2]!.d }.first
    /* the press: a line on the season and one on the top rival */
    let name = S["profile"]!["name"]!.s, ti = ss["ti"]!.i, w = ss["w"]!.i, l = ss["l"]!.i
    news(ti != 0 ? "\(name) took \(ti) title\(ti == 1 ? "" : "s") in season \(old), \(w)-\(l) in matches." : "\(name) goes \(w)-\(l) in season \(old)\(ssm != 0 ? ", no title" : "").")
    if let rv = rivalList(1).first {
      let h = S["h2h"]![String(rv)]!.a.map { $0.i }, nm = nameOf(rv)
      news(h[0] == h[1] ? "The rivalry with \(nm) stands level at \(h[0])-\(h[1])." : "\(h[0] > h[1] ? "\(name) leads \(nm)" : "\(nm) leads \(name)") \(Swift.max(h[0], h[1]))-\(Swift.min(h[0], h[1])) in their rivalry.")
    }
    let row: JV = ["s": .n(old), "ml": .n(mlr), "t0": .n(t0), "t1": me("tier"), "moved": .str(moved), "m": ss["m"]!, "w": ss["w"]!, "l": ss["l"]!, "ti": ss["ti"]!, "fi": ss["fi"]!,
                   "ev": ss["ev"]!, "prize": ss["prize"]!, "rk": .arr(circRank), "best": bestEv?[1] ?? .null, "age": .n(ageOf(Self.HUMAN, old))]
    var arch = S["arch"]!.a; arch.append(row); S["arch"] = .arr(arch)
    var rb = S["rb"]!
    if ss["ti"]!.d > (rb["titlesSeason"]?[0]?.num ?? 0) { rb["titlesSeason"] = [ss["ti"]!, .n(old)] }
    if ss["prize"]!.d > (rb["prizeSeason"]?[0]?.num ?? 0) { rb["prizeSeason"] = [ss["prize"]!, .n(old)] }
    S["rb"] = rb
    let tierN = me("tier").i
    if moved != "stay" { news(moved == "up" ? "Promoted to tier \(tierN): \(TIERS[tierN]!["name"]!.s)." : "Relegated to tier \(tierN): \(TIERS[tierN]!["name"]!.s). Time for a comeback.") }
    /* the Hall of Fame: the player once the legacy is there at the top tier */
    if !me("hof").truthy && me("leg").d >= Self.c("HOF_LEG").d && Swift.max(t0, tierN) >= 11 {
      setMe("hof", .n(old)); setMe("tier", 12)
      var hof = S["hof"]!.a; hof.append([.n(Self.HUMAN), .n(old), me("leg")]); S["hof"] = .arr(hof)
      news("Inducted into the Hall of Fame. Tier 12: Legacy.")
    }
    if me("card").truthy && me("card").d <= me("tier").d { setMe("card", 0) }
    /* skills fade a little after 38 */
    if ageOf(Self.HUMAN, old + 1) > 38 { for k in Self.c("SKILLS").a { let v = Self.r2(Swift.max(1, S["me"]!["sk"]![k.s]!.d - 1)); S["me"]?["sk"]?[k.s] = .n(v) } }
    aiSeason(old, form)
    /* rolling points: keep 52 weeks */
    let gw = gweek(S["day"]!.i)
    S["aw"] = .arr(S["aw"]!.a.filter { $0[4]!.i > gw - 52 })
    let awc = S["awc"]!.d + 1; S["awc"] = .n(awc)
    let cal = genCalendar(old + 1)
    S["cal"] = cal
    S["es"] = [:]
    S["ss"] = Self.blankSeason()
    setMe("qual", [:])
    setMe("t0", me("tier"))
    sponsorOffers("season")
    bound("season")
  }
  /* the AI at a season's end: retirement, the Hall of Fame, a new generation, then tiers from each player's proposed move
     filled into the quotas from the top */
  func aiSeason(_ old: Int, _ form: (Int) -> Double) {
    let r = Self.R([String(S["seed"]!.i), "aiseason", String(old)]), HOF = Self.c("HOF_LEG").d
    for id in activeIds() {
      let p = popAt(id), u = S["pop"]!["m"]![String(id)]!, age = ageOf(id, old + 1)
      if age >= p.retire || (age >= 35 && u["t"]!.d <= 2 && r() < 0.1) {
        mut(id, "x", .n(old))
        let lg = u["lg"]?.num ?? 0, ti = u["ti"]?.num ?? 0
        if lg >= HOF { var hof = S["hof"]!.a; hof.append([.n(id), .n(old), u["lg"]!]); S["hof"] = .arr(hof); news("\(p.name) retires and enters the Hall of Fame.") }
        else if ti >= 5 { news("\(p.name) retires with \(Int(ti)) titles.") }
      }
    }
    var act = activeIds()
    while act.count < Self.POP {
      let id = S["pop"]!["n"]!.i + 1
      S["pop"]?["n"] = .n(id)
      S["pop"]?["m"]?[String(id)] = ["t": 1, "d": .n(old + 1)]
      _ = popAt(id); act.append(id)
    }
    var prop: [Int: Double] = [:], str: [Int: Double] = [:]
    let BAND = Self.c("BAND")
    for t in 1..<12 {
      let ids = act.filter { S["pop"]!["m"]![String($0)]!["t"]!.i == t }
      let sorted = ids.sorted { a, b in let d = form(b) - form(a); return d != 0 ? d < 0 : a < b }
      for (i, id) in sorted.enumerated() {
        let rt = ratingOf(id, prefOf(id)), f = Double(i) / Double(Swift.max(1, sorted.count)), band = BAND[t]!.d
        var pt = Double(t)
        if (f < 0.15 && form(id) > 0) || rt > band + 10 { pt = Double(t + 1) }
        else if (f >= 0.85 && !(form(id) > 0)) || rt < band - 10 { pt = Double(t - 1) }
        prop[id] = Self.cl(pt, 1, 11)
        str[id] = rt + 5 * (1 - f)
      }
    }
    let sorted = act.sorted { a, b in
      if prop[b]! != prop[a]! { return prop[b]! < prop[a]! }
      if str[b]! != str[a]! { return str[b]! < str[a]! }
      return a < b
    }, n = sorted.count
    var i = 0
    for t in stride(from: 11, through: 1, by: -1) {
      let q = t == 1 ? n - i : Int(CareerLib.round(Self.c("QUOTA")[t]!.d * Double(n) / Double(Self.POP)))
      var k = 0
      while k < q && i < n { S["pop"]?["m"]?[String(sorted[i])]?["t"] = .n(t); k += 1; i += 1 }
    }
  }
}
