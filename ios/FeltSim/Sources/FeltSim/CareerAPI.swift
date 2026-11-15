/* index.html's career engine, the rest of its API line for line: a player's card, the AI's playing profile and its
   nearest CPU level, the player's next match as the table needs it, offers accepted and declined, the shop, practice,
   the live-play assist, options, the profile's edit and retirement. Answers are JV, shaped as the page's objects. */
import Foundation

private typealias M = JSMath

extension CareerEngine {
  static func shopBy(_ id: String) -> JV? { c("SHOP").a.first { $0["id"]?.str == id } }
  static func drillBy(_ id: String) -> JV? { c("DRILLS").a.first { $0["id"]?.str == id } }
  static func pct(_ n: Double, _ d: Double) -> JV { ["n": .n(n), "d": .n(d), "pct": d != 0 ? .n(CareerLib.round(1000 * n / d) / 10) : .null] }
  /* attributes as the page's object: AI players in ATTRS order, the player in humanAttrs' order */
  func attrsJV(_ id: Int) -> JV {
    var o = JObj()
    if id == Self.HUMAN {
      let h = humanAttrs()
      for k in ["acc", "cb", "brk", "safe", "bank", "tac", "agg", "con", "pres"] { o[k] = .n(h[k]!) }
    } else { let a = attrsOf(id); for k in CareerData.ATTRS { o[k] = .n(a[k]!) } }
    return .obj(o)
  }
  public func cardOf(_ id: Int) -> JV {
    let pr = S["profile"]!
    if id == Self.HUMAN {
      return ["id": .n(id), "human": true, "name": pr["name"]!, "nick": pr["nick"] ?? .null, "nat": pr["nat"]!, "town": pr["town"] ?? .null, "hand": pr["hand"] ?? .null,
              "tier": S["me"]!["tier"]!, "avatar": pr["avatar"] ?? .null, "attrs": attrsJV(id)]
    }
    let p = popAt(id), m = S["pop"]!["m"]![String(id)] ?? [:], at = attrsOf(id)
    let history: [JV] = (m["tl"]?.arr ?? []).map { x in
      let ser = x[1]!, name = S["ser"]!.a.first { $0["id"] == ser }?["name"] ?? "Event"
      return ["season": x[0]!, "event": name, "tier": x[2]!]
    }
    return ["id": .n(id), "name": .str(p.name), "nick": .str(p.nick), "nat": .str(p.nat), "town": .str(p.town), "hand": .str(p.hand), "age": .n(ageOf(id)), "arch": .str(p.arch),
            "archName": .str(CareerData.ARCH.first { $0.id == p.arch }!.name), "disc": .str(p.disc), "tier": m["t"] ?? 0, "rating": .n(CareerLib.round(CareerLib.rate(at, p.disc, p.disc))),
            "attrs": attrsJV(id), "avatar": ["ini": .str(p.ini), "col": .str(p.col)], "w": m["w"] ?? 0, "l": m["l"] ?? 0, "titles": m["ti"] ?? 0, "finals": m["fi"] ?? 0,
            "retired": .bool(m["x"] != nil), "hof": .bool(S["hof"]!.a.contains { $0[0]!.i == id }), "history": .arr(history)]
  }
  /* the AI's playing profile for the table: aim and power noise, leanings, its break, and the nearest CPU level */
  public func aiProfileOf(_ id: Int, _ diff: String? = nil) -> JV {
    let at = attrsOf(id), D = Self.c("DIFFS")
    let df = (D[diff ?? S["profile"]!["difficulty"]?.str ?? "medium"] ?? D["medium"]!)["noise"]!.d
    let a = { (k: String) in at[k]! }
    let breadth = Self.r2((a("tac") * 0.6 + a("cb") * 0.4) / 100)
    let aimNoise = CareerLib.round((0.0009 + M.pow(1 - a("acc") / 100, 1.3) * 0.0075) * df * 1e6) / 1e6
    let style = a("brk") >= 70 || a("agg") >= 65 ? "power" : a("safe") >= 65 ? "soft" : "controlled"
    var k: JV = ["breadth": .n(breadth), "aimNoise": .n(aimNoise), "powerNoise": .n(CareerLib.round((0.01 + (1 - a("con") / 100) * 0.05) * df * 1e4) / 1e4),
                 "safetyBias": .n(Self.r2(a("safe") / 100 * (1 - a("agg") / 200))), "riskTolerance": .n(Self.r2(a("agg") / 100)), "positionWeight": .n(Self.r2(a("cb") / 100)),
                 "bankWeight": .n(Self.r2(a("bank") / 100)), "hillNoise": .n(Self.r2(1 + (1 - a("pres") / 100) * 0.5)),
                 "breakChoice": ["power": .n(Self.r2(0.8 + a("brk") / 500)), "style": .str(style)]]
    k["level"] = .str(Self.levelOf(aimNoise, breadth))
    k["arch"] = .str(id != Self.HUMAN ? popAt(id).arch : "allround")
    return k
  }
  /* the nearest existing cpuSearch level: aim noise on a log scale, breadth as a tiebreak */
  static func levelOf(_ aimNoise: Double, _ breadth: Double) -> String {
    var best = "medium", bd = Double.infinity
    let LB = c("LEVEL_BREADTH")
    for lv in ["easy", "medium", "hard"] {
      let d = abs(M.log(aimNoise / CPUProfile.level(lv).noise)) + 0.5 * abs(breadth - (LB[lv]?.num ?? 0.5))
      if d < bd { bd = d; best = lv }
    }
    return best
  }
  public func roundName(_ ev: JV, _ T: CareerLib.Bracket, _ m: Int) -> String { CareerLib.roundName(ev["fmt"]!.s, T, m) }
  /* what the table needs to start the player's match: the opponent, the rules, the race, who breaks */
  public func nextMatch() -> JV {
    if S == .null || me("ret").truthy { return .null }
    guard let p = myPending() else { return .null }
    let opp = p.o.a == Self.HUMAN ? p.o.b! : p.o.a!, ai = aiProfileOf(opp), id = p.ev["id"]!.s
    let lag = Self.R([String(S["seed"]!.i), id, String(p.m), "lag"])() < 0.5 ? 0 : 1, race = p.ev["race"]!.i
    let h = S["h2h"]![String(opp)]?.a ?? [0, 0]
    return ["event": .str(id), "eventName": p.ev["name"]!, "match": .n(p.m), "round": .str(roundName(p.ev, p.T, p.m)), "final": .bool(p.T.M[p.m].fin), "day": S["day"]!,
            "opponent": cardOf(opp), "ai": ai, "level": ai["level"]!, "race": .n(race), "rules": p.ev["rules"]!, "breaker": .n(lag), "h2h": .arr(Array(h.prefix(2))),
            "fr": ["me": me("fr"), "opp": .n(frOf(opp)), "odds": .n(Self.raceOdds(Self.rackOdds(me("fr").d, frOf(opp)), race))]]
  }

  // MARK: offers
  @discardableResult public func accept(_ offerId: String) -> String? {
    if let no = live() { return no }
    var off = S["off"]!.a
    guard let i = off.firstIndex(where: { $0["id"]?.str == offerId }) else { return "no such offer" }
    let o = off[i]
    if o["type"]!.s == "sponsor" {
      let act = S["spons"]!.a.filter { !truthy($0["end"]) }
      if act.count >= 2 { return "two contracts already" }
      if act.contains(where: { $0["cat"] == o["cat"] }) { return "already sponsored for \(o["cat"]!.s)" }
      let day = S["day"]!.d
      let obj: [JV] = o["obj"]!.a.map { x in var y = x; y["base"] = .n(objNow(x)); y["done"] = 0; return y }
      var sp = S["spons"]!.a
      sp.append(["id": o["id"]!, "brand": o["brand"]!, "cat": o["cat"]!, "from": .n(day), "to": .n(day + o["weeks"]!.d * 7), "ret": o["ret"]!, "bonus": o["bonus"]!, "obj": .arr(obj)])
      S["spons"] = .arr(sp)
      news("Signed with \(o["brand"]!.s) for \(o["weeks"]!.i) weeks.")
    } else {
      let type = o["type"]!.s, opp = o["opp"]!.i, tier = o["tier"]!, pr = S["profile"]!
      let name = type == "challenge" ? "Challenge: \(nameOf(opp))" : "Exhibition with \(nameOf(opp))"
      let ev: JV = ["id": .str("x" + String(offerId.dropFirst())), "ser": 0, "ed": 0, "name": .str(name), "city": pr["town"] ?? .null, "venue": "Exhibition table", "nat": pr["nat"]!,
                    "kind": .str(type), "fmt": "series", "tier": tier, "circ": Self.c("TIERS")[tier.i]!["circ"]!, "disc": o["disc"]!, "pres": 50, "start": o["start"]!, "end": o["end"]!,
                    "dl": .n(o["start"]!.d - 1), "fee": 0, "trav": 0, "purse": o["purse"]!, "size": 2, "race": o["race"]!,
                    "rules": rulesFor(["tier": tier, "disc": o["disc"]!, "kind": .str(type)], o["race"]!.i), "req": ["min": 1, "max": 12], "pts": 0, "legs": o["legs"]!, "opp": .n(opp)]
      if S["cal"]!.a.contains(where: { x in es(x).map { truthy($0["en"]) && !truthy($0["done"]) } == true && overlaps(x, ev) }) { return "clashes with an event you entered" }
      if !activeAI(opp) { return "the opponent has retired" }
      var cal = S["cal"]!.a; cal.append(ev); S["cal"] = .arr(Self.sortCal(cal))
      S["es"]?[ev["id"]!.s] = ["en": 1]
      news("\(name) set for week \(weekOf(o["start"]!.i)).")
    }
    off = S["off"]!.a
    off.remove(at: i)
    S["off"] = .arr(off)
    return nil
  }
  @discardableResult public func decline(_ offerId: String) -> Bool {
    if live() != nil { return false }
    var off = S["off"]!.a
    guard let i = off.firstIndex(where: { $0["id"]?.str == offerId }) else { return false }
    off.remove(at: i); S["off"] = .arr(off)
    return true
  }

  // MARK: the shop
  func needMet(_ k: String?) -> Bool {
    guard let k, !k.isEmpty else { return true }
    switch k {
    case "hof": return me("hof").truthy
    case "title": return S["st"]!["all"]!["ti"]!.d >= 1
    case "wins100": return S["st"]!["all"]!["w"]!.d >= 100
    case "drillGold": let mas = S["me"]!["mas"] ?? [:]; return mas.keys.contains { (mas[$0]?["lv"]?.num ?? 0) >= 3 }
    default: return false
    }
  }
  /* owned: bought, or free to everyone */
  public func owns(_ id: String) -> Bool {
    if S["inv"]!["own"]!.a.contains(.str(id)) { return true }
    guard let it = Self.shopBy(id) else { return false }
    return it["price"]!.d == 0 && !truthy(it["need"])
  }
  /* what is worn per slot: the equipped item if it is still one this build knows and owns, else the default */
  public func equipped() -> JV {
    let eq = S["inv"]!["eq"] ?? [:], D = Self.c("DEFAULT_EQ")
    var out = JObj()
    for sj in Self.c("SHOP_SLOTS").a {
      let s = sj.s
      if let id = eq[s]?.str, let it = Self.shopBy(id), it["slot"]?.str == s, owns(id) { out[s] = .str(id) } else { out[s] = D[s] ?? .null }
    }
    return .obj(out)
  }
  @discardableResult public func buy(_ itemId: String) -> String? {
    if let no = live() { return no }
    guard let it = Self.shopBy(itemId) else { return "no such item" }
    if owns(itemId) { return "owned" }
    if !needMet(it["need"]?.str) { return Self.c("NEED_WORDS")[it["need"]!.s]?.str ?? "locked" }
    if me("money").d < it["price"]!.d { return "not enough credits" }
    if it["price"]!.truthy { pay(-it["price"]!.d, "shop", it["name"]!.s) }
    var own = S["inv"]!["own"]!.a; own.append(.str(itemId)); S["inv"]?["own"] = .arr(own)
    return nil
  }
  @discardableResult public func equip(_ itemId: String) -> Bool {
    guard let it = Self.shopBy(itemId), owns(itemId) else { return false }
    S["inv"]?["eq"]?[it["slot"]!.s] = .str(itemId)
    return true
  }

  // MARK: practice, assist, options, the profile
  /* a practice drill's score (0-100): mastery milestones and a little skill; three sessions a day */
  public func practice(_ drillId: String, _ score: Int) -> JV {
    if let no = live() { return ["ok": false, "why": .str(no)] }
    guard let d = Self.drillBy(drillId), score >= 0, score <= 100 else { return ["ok": false, "why": "bad drill or score"] }
    let day = S["day"]!
    if me("pdDay") != day { setMe("pdDay", day); setMe("pd", 0) }
    if me("pd").d >= 3 { return ["ok": false, "why": "three sessions a day"] }
    let pd = me("pd").d + 1; setMe("pd", .n(pd))
    var m = S["me"]!["mas"]![drillId] ?? ["best": 0, "n": 0, "lv": 0]
    m["n"] = .n(m["n"]!.d + 1); m["best"] = .n(Swift.max(m["best"]!.d, Double(score)))
    let MS = Self.c("MILESTONES").a, best = m["best"]!.d
    let lv = MS.filter { best >= $0[0]!.d }.count, milestone: JV = Double(lv) > m["lv"]!.d ? MS[lv - 1][1]! : .null
    m["lv"] = .n(lv)
    S["me"]?["mas"]?[drillId] = m
    if let ms = milestone.str { news("\(d["name"]!.s): \(ms) mastery.") }
    addSkill(d["skill"]!.s, Double(score) / 25)
    return ["ok": true, "mastery": m, "milestone": milestone]
  }
  /* what the career changes in live play: nothing with simulation purity on; otherwise SKILL_EFFECTS */
  public func assist() -> JV {
    let k = { (s: String) in self.S["me"]!["sk"]![s]!.d }, o = me("opt")
    if o["purity"]!.truthy {
      return ["purity": true, "guide": nil, "autoAim": nil, "bankGuide": false, "safetyHint": false, "aimNoise": 0, "powerNoise": 0, "breakNoise": 0, "spinNoise": 0, "hillNoise": 1]
    }
    let v = o["variance"]!.truthy ? 1.0 : 0
    return ["purity": false, "guide": .str(k("pos") < 30 ? "none" : k("pos") < 60 ? "short" : "long"), "autoAim": .bool(k("tactics") >= 40), "bankGuide": .bool(k("banks") >= 50),
            "safetyHint": .bool(k("safety") >= 60), "aimNoise": .n(Self.r2(v * 0.004 * (1 - k("aim") / 100) * 1e4) / 1e4),
            "powerNoise": .n(Self.r2(v * 0.05 * (1 - k("power") / 100) * 1e3) / 1e3), "breakNoise": .n(Self.r2(v * 0.08 * (1 - k("brk") / 100) * 1e3) / 1e3),
            "spinNoise": .n(Self.r2(v * 0.15 * (1 - k("spin") / 100) * 1e3) / 1e3), "hillNoise": .n(Self.r2(1 + 0.5 * (1 - k("pressure") / 100)))]
  }
  @discardableResult public func setOptions(purity: Bool? = nil, variance: Bool? = nil) -> JV {
    if let purity { S["me"]?["opt"]?["purity"] = .bool(purity) }
    if let variance { S["me"]?["opt"]?["variance"] = .bool(variance) }
    return me("opt")
  }
  @discardableResult public func editProfile(_ patch: JV) -> JV {
    let pr = cleanProfile(patch, S["profile"]!)
    S["profile"] = pr
    return pr
  }

  // MARK: retirement
  @discardableResult public func retire() -> JV {
    if me("ret").truthy { return S["recap"]! }
    for ev in S["cal"]!.a {
      let id = ev["id"]!.s
      if let e = es(ev), truthy(e["en"]), e["f"] == nil { S["es"]?[id]?["en"] = nil; pay(ev["fee"]!.d, "refund", ev["name"]!.s) }
    }
    while forfeitPending() { resolveAll() }
    let day = S["day"]!.i
    setMe("ret", .n(day != 0 ? day : 1))
    if !me("hof").truthy && me("leg").d >= Self.c("HOF_LEG").d {
      setMe("hof", .n(season))
      var hof = S["hof"]!.a; hof.append([.n(Self.HUMAN), .n(season), me("leg")]); S["hof"] = .arr(hof)
    }
    let a = S["st"]!["all"]!, CIRC = Self.c("CIRCUITS")
    let peak = S["arch"]!.a.reduce(me("tier").d) { Swift.max($0, $1["t0"]!.d, $1["t1"]!.d) }
    var ranks = JObj()
    for c in S["best"]!.keys { ranks[CIRC[Int(c)!]!.s] = S["best"]![c]![0]! }
    let titles: [JV] = me("tl").a.map { ["season": $0[0]!, "name": $0[1]!, "tier": $0[2]!] }
    let recap: JV = ["name": S["profile"]!["name"]!, "seasons": .n(season), "retiredAt": ["season": .n(season), "week": .n(weekOf(day)), "age": .n(ageOf(Self.HUMAN))],
                     "peakTier": .n(peak), "tier": me("tier"), "matches": a["m"]!, "won": a["w"]!, "lost": a["l"]!, "winPct": Self.pct(a["w"]!.d, a["m"]!.d), "titles": .arr(titles),
                     "finals": a["fi"]!, "prize": a["prize"]!, "bestRanks": .obj(ranks), "hallOfFame": .bool(me("hof").truthy), "legacy": me("leg"), "records": S["rb"]!]
    S["recap"] = recap
    news("\(S["profile"]!["name"]!.s) retires.")
    save()
    return recap
  }

  // MARK: views: stats, rankings, the season's review
  static func statView(_ b: JV) -> JV {
    let v = { (k: String) in b[k]!.d }
    return ["matches": b["m"]!, "won": b["w"]!, "lost": b["l"]!, "winPct": pct(v("w"), v("m")), "titles": b["ti"]!, "finals": b["fi"]!, "events": b["ev"]!, "prize": b["prize"]!,
            "racks": ["won": b["rw"]!, "lost": b["rl"]!, "pct": pct(v("rw"), v("rw") + v("rl"))], "breakAndRun": pct(v("bnr"), v("br")), "legalBreak": pct(v("lb"), v("br")),
            "runout": pct(v("ro"), v("rk")), "shotAccuracy": pct(v("sp"), v("sa")), "calledShot": pct(v("cm"), v("ca")), "safety": pct(v("ss"), v("sf")), "fouls": b["fo"]!,
            "scratches": b["sc"]!, "foulsPerRack": pct(v("fo"), v("rk")), "streak": b["st"]!, "bestStreak": b["bs"]!, "worstStreak": b["ls"]!]
  }
  public func stats() -> JV {
    var by = JObj()
    for d in S["st"]!["d"]!.keys { by[d] = Self.statView(S["st"]!["d"]![d]!) }
    let lg = S["legacy"] ?? .null
    var legacy: JV = .null
    if lg.truthy { legacy = lg; legacy["winPct"] = Self.pct(lg["won"]!.d, lg["played"]!.d) }
    return ["all": Self.statView(S["st"]!["all"]!), "byDisc": .obj(by), "season": S["ss"]!, "legacy": legacy, "mastery": S["me"]!["mas"]!, "skills": S["me"]!["sk"]!]
  }
  /* circuit: "local", "regional", ... (CIRCUITS), a discipline, or "season": rank, id, name, nat, pts, tier, human, move */
  public func rankings(_ circuit: String = "local", top: Int = 50) -> JV {
    let CI = Self.c("CIRCUITS").a.map { $0.s }, key: RankKey = CI.contains(circuit) ? .circ(CI.firstIndex(of: circuit)!) : Self.DISCS.contains(circuit) ? .disc(circuit) : .season
    let gw = gweek(S["day"]!.i)
    var prev: [Int: Int] = [:]
    for (i, x) in rankList(key, gw - 1).enumerated() where prev[x.0] == nil { prev[x.0] = i + 1 }
    return .arr(rankList(key, gw).prefix(top).enumerated().map { i, x in
      let cd = cardOf(x.0)
      return ["rank": .n(i + 1), "id": .n(x.0), "name": cd["name"]!, "nat": cd["nat"]!, "pts": .n(x.1), "tier": cd["tier"]!, "human": .bool(x.0 == Self.HUMAN),
              "move": prev[x.0].map { .n($0 - (i + 1)) } ?? .null]
    })
  }
  public var reviewDue: Bool { S["rev"]!.d < Double(S["arch"]!.count) }
  public func reviewSeen() { let n = S["arch"]!.count; S["rev"] = .n(n) }
  /* the season just ended: its row, the verdict, the card, next season's targets */
  public func review() -> JV {
    guard let a = S["arch"]!.a.last else { return .null }
    let t = me("tier").i
    var targets: [JV] = []
    if t >= 8 && t < 12 { targets.append(.str("Finish in the top \(Self.c("CARD_KEEP").i) of the two-year money list to keep your card")) }
    if t < 11 {
      let to = t + 1
      targets.append(.str((to == 8 || to == 10) && me("card").d < Double(to) ? "Win the qualifier for a tour card, then finish in the top 15% of tier \(t)"
        : "Finish in the top 15% of tier \(t) and win half your matches\(t < 7 ? ", or win a title at tier \(t) or above" : "")"))
    }
    if let rv = rivalList(1).first { targets.append(.str("Settle it with \(nameOf(rv))")) }
    return ["season": a["s"]!, "t0": a["t0"]!, "t1": a["t1"]!, "moved": a["moved"]!, "m": a["m"]!, "w": a["w"]!, "l": a["l"]!, "ti": a["ti"]!, "fi": a["fi"]!, "ev": a["ev"]!,
            "prize": a["prize"]!, "rk": a["rk"]!, "tier": Self.c("TIERS")[t]!["name"]!, "moneyRank": a["ml"]!.truthy ? a["ml"]! : 0, "fr": me("fr"), "targets": .arr(targets)]
  }
}

/* Career.bracket(id) and Career.standings(id): an event's draw, every match (its round, day and outcome), the final
   placings once it is done; and the round robin's or the groups' tables */
extension CareerEngine {
  public struct BracketMatch: Sendable { public let m: Int, round: String, day: Int, o: CareerLib.Outcome }
  public struct BracketView: Sendable { public let drawn: Bool, week: Int, field: [Int], matches: [BracketMatch], placings: [[Int]]? }
  public func bracket(_ id: String) -> BracketView? {
    guard let ev = evById(id) else { return nil }
    guard let e = S["es"]![id], e["f"] != nil else { return BracketView(drawn: false, week: weekOf(ev["start"]!.i), field: [], matches: [], placings: nil) }
    let T = tplOf(ev, e), c = ctxOf(T, e)
    let f = e["f"]!.a.map { $0.i }
    return BracketView(drawn: true, week: weekOf(ev["start"]!.i), field: f,
                       matches: T.M.indices.map { BracketMatch(m: $0, round: roundName(ev, T, $0), day: dayOfMatch(ev, T, $0), o: CareerLib.outcome(c, $0)) },
                       placings: truthy(e["done"]) ? CareerLib.placings(T, f, resOf(e)) : nil)
  }
  public func standings(_ id: String) -> [(group: String?, rows: [CareerLib.Row])]? {
    guard let ev = evById(id), let e = S["es"]![id], e["f"] != nil else { return nil }
    let T = tplOf(ev, e), c = ctxOf(T, e), f = e["f"]!.a.map { $0.i }
    let done = { (ms: [Int]) in ms.map { CareerLib.outcome(c, $0) }.filter { $0.st == "done" } }
    let ix = { (p: Int) in f.firstIndex(of: p) ?? -1 }
    if let G = T.groups, let gm = T.gm {
      let L = Array("ABCDEFGH")
      return G.enumerated().map { gi, g in (String(L[gi]), CareerLib.standings(g.filter { $0 < f.count }.map { f[$0] }, done(gm[gi]), ix)) }
    }
    if T.fmt == "rr" || T.fmt == "league" { return [(nil, CareerLib.standings(f, done(Array(T.M.indices)), ix))] }
    return nil
  }
  public func weekOfDay(_ day: Int) -> Int { weekOf(day) }
}

/* Career.rivals(), headToHead(id) and player(id), as the page's: the rivals by rivalList, each with its head-to-head
   (S.h2h: won, lost, finals won, finals lost, upsets, upset by, close, streak, last season) */
extension CareerEngine {
  public func rivals() -> [JV] {
    rivalList(10).map { id in
      let h = S["h2h"]![String(id)]!
      return ["id": .n(id), "name": cardOf(id)["name"]!, "score": .n(rivalScore(h)), "won": h[0]!, "lost": h[1]!, "finalsWon": h[2]!, "finalsLost": h[3]!,
              "upsets": h[4]!, "upsetBy": h[5]!, "close": h[6]!, "streak": h[7]!, "lastSeason": h[8] ?? .null]
    }
  }
  public func headToHead(_ id: Int) -> JV {
    guard let h = S["h2h"]![String(id)] else { return .null }
    return ["won": h[0]!, "lost": h[1]!, "finalsWon": h[2]!, "finalsLost": h[3]!, "upsets": h[4]!, "upsetBy": h[5]!, "close": h[6]!, "streak": h[7]!]
  }
  public func player(_ id: Int) -> JV {
    guard id == Self.HUMAN || S["pop"]!["m"]![String(id)] != nil else { return .null }
    var c = cardOf(id)
    c["ai"] = id == Self.HUMAN ? .null : aiProfileOf(id)
    return c
  }
}

/* evView: an event as the page's Career.event and calendar().events show it (the event's own fields plus kindName,
   fmtName, tierName, circuit, game, live, week, status, entered, conflict, defending, champion) */
extension CareerEngine {
  public func evView(_ ev: JV) -> JV {
    let id = ev["id"]!.s, e = S["es"]![id] ?? [:]
    let conflict = S["cal"]!.a.first { o in o["id"]!.s != id && truthy(S["es"]![o["id"]!.s]?["en"]) && !truthy(S["es"]![o["id"]!.s]?["done"]) && overlaps(o, ev) }
    let status = truthy(e["x"]) ? "cancelled" : truthy(e["done"]) ? "done" : e["f"] != nil ? "live" : truthy(e["en"]) ? "entered" : S["day"]!.i <= ev["dl"]!.i ? "open" : "closed"
    let ch = ev["ser"].flatMap { $0.truthy ? S["ch"]![String($0.i)]?.arr?.last : nil }
    let C = { (k: String) in Self.c(k) }
    var v = ev
    v["kindName"] = C("EVENT_KINDS")[ev["kind"]!.s] ?? .null
    v["fmtName"] = C("FORMATS")[ev["fmt"]!.s] ?? .null
    v["tierName"] = C("TIERS")[ev["tier"]!.i]?["name"] ?? .null
    v["circuit"] = C("CIRCUITS")[ev["circ"]?.i ?? 0] ?? .null
    v["game"] = C("GAMES")[ev["disc"]!.s]?["name"] ?? .null
    v["live"] = C("GAMES")[ev["disc"]!.s]?["live"] ?? false
    v["week"] = .n(weekOf(ev["start"]!.i))
    v["status"] = .str(status)
    v["entered"] = .bool(truthy(e["en"]))
    v["conflict"] = conflict?["id"] ?? .null
    v["defending"] = .bool(ch.map { $0[1]!.i == Self.HUMAN && $0[0]!.i == season - 1 } ?? false)
    v["champion"] = ch.map { ["season": $0[0]!, "id": $0[1]!, "name": cardOf($0[1]!.i)["name"]!] } ?? .null
    return v
  }
}

/* Career.records(): personal bests (S.rb), your titles, the series' champions, the Hall of Fame, the seasons (S.arch)
   and the ten title leaders (active players, then the retired, then you; most titles, then id) */
extension CareerEngine {
  public func records() -> JV {
    let m = S["pop"]!["m"]!
    let retired = m.keys.compactMap { Int($0) }.filter { !activeAI($0) }.sorted()
    var lead: [(Int, Int)] = (activeIds() + retired).map { ($0, m[String($0)]?["ti"]?.i ?? 0) }
    lead.append((Self.HUMAN, S["st"]!["all"]!["ti"]?.i ?? 0))
    lead = Array(lead.filter { $0.1 > 0 }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(10))
    return ["personal": S["rb"]!,
            "titles": .arr(S["me"]!["tl"]!.a.map { ["season": $0[0]!, "name": $0[1]!, "tier": $0[2]!] }),
            "hallOfFame": .arr(S["hof"]!.a.map { ["id": $0[0]!, "name": cardOf($0[0]!.i)["name"]!, "season": $0[1]!, "legacy": $0[2]!] }),
            "seasons": S["arch"]!,
            "titleLeaders": .arr(lead.map { ["id": .n($0.0), "name": cardOf($0.0)["name"]!, "titles": .n($0.1)] })]
  }
}

/* sponsors()' objective progress: a rank objective's current place (nil unranked), else the count since the contract */
extension CareerEngine {
  public func objProgress(_ o: JV) -> Int? {
    if o["k"]!.s == "rank" { return rankOf(Self.HUMAN, .circ(o["c"]!.i)) }
    return Int(objNow(o) - (o["base"]?.d ?? 0))
  }
}

/* Career.shop(): every item with owned, equipped, locked (its achievement not reached) and needWords */
extension CareerEngine {
  public func shop() -> [JV] {
    let eq = equipped()
    return Self.c("SHOP").a.map { i in
      var v = i, id = i["id"]!.s, need = i["need"]?.str
      v["owned"] = .bool(owns(id)); v["equipped"] = .bool(eq[i["slot"]!.s]?.str == id)
      v["locked"] = .bool(!needMet(need)); v["needWords"] = need.flatMap { Self.c("NEED_WORDS")[$0] } ?? .null
      return v
    }
  }
}
