/* index.html's career engine (#region career), line for line, on its own state: S is the page's save as JV, every
   function reads and writes it as the page does, and Career.digest() (hashStr of JSON.stringify(S)) is the page's.
   Ported so far: the save's shape (newState), cleanProfile, the save index, the population (popAt, attrsOf, ageOf,
   rate, assignTiers), the series and calendar (genSeries, instEvent, genCalendar, the rules and requirements an event
   carries) and create up to the first season's calendar. CareerTests compares each checkpoint the page traced. */
import Foundation

private typealias M = JSMath

public final class CareerEngine {
  public var S: JV = .null
  /* memStore: getItem / setItem / removeItem (the page's localStorage) */
  public var store: [String: String] = [:]
  /* the boundaries crossed during the current call ("match", "event", "season") */
  public var bounds: [String] = []
  public init() {}
  static let C = CareerData.C
  static func c(_ k: String) -> JV { C[k]! }
  static let POP = CareerData.POP, YEAR = Int(c("YEAR").d), HUMAN = Int(c("HUMAN").d)

  /* the population cache (PC): generated players by id, the names taken so far */
  var PC: (seed: Int, list: [CareerLib.Player?], names: Set<String>)? = nil
  public func resetCaches() { PC = nil }

  // MARK: small helpers
  static func cl(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, v)) }
  static func r2(_ v: Double) -> Double { CareerLib.round(v * 100) / 100 }
  public func seasonOf(_ day: Int) -> Int { Int((Double(day) / Double(Self.YEAR)).rounded(.down)) + 1 }
  public var season: Int { seasonOf(S["day"]!.i) }

  // MARK: population
  public func popAt(_ id: Int) -> CareerLib.Player {
    let seed = S["seed"]!.i
    if PC == nil || PC!.seed != seed { PC = (seed, [nil], []) }
    while PC!.list.count <= id { let n = PC!.list.count; PC!.list.append(CareerLib.genPlayer(seed, n, &PC!.names)) }
    return PC!.list[id]!
  }
  /* mut(id): the player's saved fields, made when first written */
  func mut(_ id: Int, _ k: String, _ v: JV) {
    let key = String(id)
    if S["pop"]?["m"]?[key] == nil { S["pop"]?["m"]?[key] = [:] }
    S["pop"]?["m"]?[key]?[k] = v
  }
  func debutOf(_ id: Int) -> Int { S["pop"]?["m"]?[String(id)]?["d"].flatMap { $0.truthy ? $0.i : nil } ?? 1 }
  public func ageOf(_ id: Int, _ s0: Int? = nil) -> Int {
    let s = s0 ?? season
    if id == Self.HUMAN { return S["profile"]!["age"]!.i + s - 1 }
    return popAt(id).age0 + s - debutOf(id)
  }
  func ageFactor(_ p: CareerLib.Player, _ age: Int) -> Double {
    Self.cl(1 - 0.02 * Double(Swift.max(0, p.peak - age)) - 0.0009 * M.pow(Double(Swift.max(0, age - p.peak - 2)), 2), 0.4, 1)
  }
  /* an AI player's attributes at a season (0-99) */
  public func attrsOf(_ id: Int, _ s0: Int? = nil) -> [String: Double] {
    let s = s0 ?? season
    if id == Self.HUMAN { return humanAttrs() }
    let p = popAt(id), f = ageFactor(p, ageOf(id, s))
    var at: [String: Double] = [:]
    for a in CareerData.ATTRS {
      at[a] = a == "agg" ? p.base["agg"]!
        : a == "pres" ? CareerLib.round(Self.cl(p.base["pres"]! * (0.85 + 0.15 * f) + Double(Swift.min(10, ageOf(id, s) - 18)) * 0.5, 1, 99))
        : CareerLib.round(Self.cl(p.base[a]! * f, 1, 99))
    }
    return at
  }
  func humanAttrs() -> [String: Double] {
    let k = S["me"]!["sk"]!, sty = Self.c("STYLES")[S["profile"]!["style"]!.s] ?? Self.c("STYLES")["allround"]!
    return ["acc": k["aim"]!.d, "cb": (k["pos"]!.d + k["spin"]!.d) / 2, "brk": k["brk"]!.d, "safe": k["safety"]!.d, "bank": k["banks"]!.d, "tac": k["tactics"]!.d,
            "agg": sty["agg"]!.d, "con": (k["power"]!.d + k["aim"]!.d) / 2, "pres": k["pressure"]!.d]
  }
  func prefOf(_ id: Int) -> String { id == Self.HUMAN ? S["profile"]!["disc"]!.s : popAt(id).disc }
  public func ratingOf(_ id: Int, _ disc: String? = nil) -> Double { CareerLib.rate(attrsOf(id), disc ?? prefOf(id), prefOf(id)) }
  /* the first season's tiers: quotas from the top by rating */
  func assignTiers(_ ids: [Int], _ key: (Int) -> Double) {
    let k = Dictionary(uniqueKeysWithValues: ids.map { ($0, key($0)) })
    let sorted = ids.sorted { a, b in k[b]! - k[a]! != 0 ? k[b]! - k[a]! < 0 : a < b }, n = sorted.count
    var i = 0
    for t in stride(from: 11, through: 1, by: -1) {
      let q = t == 1 ? n - i : Int(CareerLib.round(Self.c("QUOTA")[t]!.d * Double(n) / Double(Self.POP)))
      var j = 0
      while j < q && i < n { mut(sorted[i], "t", .n(t)); j += 1; i += 1 }
    }
  }

  // MARK: creating a career
  static func jsSlice(_ s: String, _ max: Int) -> String { String(decoding: Array(s.utf16.prefix(max)), as: UTF16.self) }
  static func str(_ v: JV?, _ max: Int, _ dflt: JV) -> JV {
    if case .str(let s)? = v { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { return .str(jsSlice(t, max)) } }
    return dflt
  }
  /* a profile from untrusted input. prev: the profile being edited (start and age stay) */
  public func cleanProfile(_ p0: JV?, _ prev: JV?) -> JV {
    let p: JV = p0?.isObj == true ? p0! : [:]
    let C = Self.self
    let base: JV = prev ?? ["name": "Player", "nick": "", "nat": "US", "town": "", "hand": "right", "cue": "cue-house", "disc": "8", "style": "allround",
                            "difficulty": "medium", "start": "amateur", "age": 20, "experienced": false, "avatar": nil]
    let natOk = p["nat"]?.str.map { n in CareerData.NAT.contains { $0.id == n } } ?? false
    let shop = C.c("SHOP").a, cueOk = p["cue"]?.str.map { id in shop.contains { $0["id"]!.s == id && $0["slot"]!.s == "cue" } } ?? false
    let discs = C.c("DISCS").a.map { $0.s }
    let ageOk: Bool = { if let v = p["age"]?.num, v == v.rounded(), v >= 14, v <= 70 { return true }; return false }()
    var out: JV = [
      "name": C.str(p["name"], 24, base["name"]!),
      "nick": p["nick"]?.str.map { .str(C.jsSlice($0.trimmingCharacters(in: .whitespacesAndNewlines), 20)) } ?? base["nick"]!,
      "nat": natOk ? p["nat"]! : base["nat"]!,
      "hand": p["hand"] == "left" || p["hand"] == "right" ? p["hand"]! : base["hand"]!,
      "cue": cueOk ? p["cue"]! : base["cue"]!,
      "disc": p["disc"]?.str.map { discs.contains($0) } == true ? p["disc"]! : base["disc"]!,
      "style": p["style"]?.str.map { C.c("STYLES")[$0] != nil } == true ? p["style"]! : base["style"]!,
      "difficulty": p["difficulty"]?.str.map { C.c("DIFFS")[$0] != nil } == true ? p["difficulty"]! : base["difficulty"]!,
      "start": prev != nil ? prev!["start"]! : p["start"]?.str.map { C.c("STARTS")[$0] != nil } == true ? p["start"]! : base["start"]!,
      "age": prev != nil ? prev!["age"]! : ageOk ? p["age"]! : base["age"]!,
      "experienced": { if case .bool? = p["experienced"] { return p["experienced"]! }; return base["experienced"]! }(),
    ]
    let nat = CareerData.NAT.first { $0.id == out["nat"]!.s }!
    out["town"] = C.str(p["town"], 24, prev != nil && out["nat"] == prev!["nat"] ? base["town"]! : .str(nat.cities[0]))
    let pa: JV = p["avatar"]?.isObj == true ? p["avatar"]! : [:], ba: JV = base["avatar"]?.isObj == true ? base["avatar"]! : [:]
    let iniOk = pa["ini"]?.str.map { $0.range(of: "^[A-Za-z0-9]{1,3}$", options: .regularExpression) != nil } ?? false
    let name = out["name"]!.s
    let ini = iniOk ? pa["ini"]!.s.uppercased()
      : C.jsSlice(name.split(whereSeparator: { $0.isWhitespace }).map { String($0.utf16.first.map { String(decoding: [$0], as: UTF16.self) } ?? "") }.joined(), 2).uppercased()
    let colOk = pa["col"]?.str.map { $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil } ?? false
    let col: JV = colOk ? pa["col"]! : truthy(ba["col"]) ? ba["col"]! : .str(CareerData.AV_COLS[Int(CareerLib.hashStr(name) % UInt32(CareerData.AV_COLS.count))])
    out["avatar"] = ["ini": .str(ini), "col": col]
    return out
  }
  static func blankStat() -> JV {
    var o = JObj(); for k in ["m", "w", "l", "rw", "rl", "ti", "fi", "ev", "prize", "rk", "br", "lb", "bnr", "ro", "sa", "sp", "ca", "cm", "sf", "ss", "fo", "sc", "st", "bs", "ls"] { o[k] = 0 }; return .obj(o)
  }
  static func blankSeason() -> JV { ["m": 0, "w": 0, "l": 0, "ti": 0, "fi": 0, "ev": 0, "prize": 0, "tt": 0] }
  func newState(_ seed: Int, _ profile: JV, _ id: String) -> JV {
    let C = Self.self, st0 = C.c("STARTS")[profile["start"]!.s]!
    var sk = JObj()
    for k in C.c("SKILLS").a { sk[k.s] = st0["sk"]! }
    let diff = profile["difficulty"]!.s
    let own: [JV] = C.c("SHOP").a.filter { $0["price"]!.d == 0 && !truthy($0["need"]) }.map { $0["id"]! }
    return [
      "v": C.c("VERSION"), "id": .str(id), "seed": .n(seed), "day": 0, "profile": profile,
      "me": ["tier": st0["tier"]!, "t0": st0["tier"]!, "rep": 0, "money": st0["money"]!, "sk": .obj(sk), "mas": [:], "card": 0, "qual": [:],
             "opt": ["purity": .bool(diff == "hard" || diff == "pro" || profile["experienced"]!.truthy), "variance": true], "pd": 0, "pdDay": -1, "ret": 0, "hof": 0, "leg": 0, "tl": []],
      "pop": ["n": .n(Self.POP), "m": [:]], "ser": [], "cal": [], "es": [:], "aw": [], "awc": 0, "rh": [], "best": [:],
      "st": ["all": C.blankStat(), "d": [:]], "ss": C.blankSeason(), "h2h": [:], "obj": [], "off": [], "spons": [], "sph": [],
      "inv": ["own": .arr(own), "eq": C.c("DEFAULT_EQ")],
      "led": [], "tot": ["start": st0["money"]!], "arch": [], "ch": [:], "hof": [], "rb": [:], "news": [], "nx": 0, "legacy": nil, "recap": nil,
    ]
  }
  func readIndex() -> JV {
    let o = store[Self.c("K_INDEX").s].flatMap { JV.parse($0) }
    if let o, o.isObj, o["v"] == 1, o["slots"]?.isArr == true { return o }
    return ["v": 1, "n": 0, "slots": [], "active": nil, "v1": nil]
  }
  func writeIndex(_ idx: JV) { store[Self.c("K_INDEX").s] = idx.stringify() }
  /* create, as far as the port has reached: the state, the population and its tiers (the page's first checkpoint) */
  public func create(_ profile: JV, seed: Int? = nil) -> (ok: Bool, id: String?) {
    var idx = readIndex()
    if idx["slots"]!.count >= Int(Self.c("MAX_SLOTS").d) { return (false, nil) }
    let pr = cleanProfile(profile, nil)
    let sd = seed ?? Int(CareerLib.seedOf([pr["name"]!.s, pr["nat"]!.s, String(idx["n"]!.i + 1)]))
    idx["n"] = .n(idx["n"]!.i + 1)
    let id = "c\(idx["n"]!.i)"
    writeIndex(idx)
    S = newState(sd, pr, id)
    resetCaches()
    for i in 1...Self.POP { S["pop"]?["m"]?[String(i)] = ["t": 1] }
    assignTiers(S["pop"]!["m"]!.keys.map { Int($0)! }, { self.ratingOf($0, self.prefOf($0)) })
    trace.append(S.stringify())
    S["ser"] = genSeries(sd, pr["nat"]!.s, pr["town"]!.s)
    trace.append(S.stringify())
    S["cal"] = genCalendar(1)
    trace.append(S.stringify())
    weekly()
    sponsorOffers("season")
    upgrade()
    news("\(pr["name"]!.s) starts out as a \(Self.c("TIERS")[S["me"]!["tier"]!.i]!["name"]!.s).")
    trace.append(S.stringify())
    return (true, id)
  }
  /* the states at the page's checkpoints in create (the golden's __trace), for the tests */
  public var trace: [String] = []

  // MARK: the calendar
  static func R(_ k: [String]) -> () -> Double { CareerLib.R(k) }
  static func pick<T>(_ r: () -> Double, _ a: [T]) -> T { CareerLib.pick(r, a) }
  /* pickW over a JS object's keys in their order */
  static func pickW(_ r: () -> Double, _ w: JV) -> String { CareerLib.pickW(r, w.o.keys.map { ($0, w[$0]!.d) }) }
  func discW(_ tier: Int, _ kind: String) -> JV {
    if kind == "league" { return ["8": 3, "9": 2] }
    if kind == "finals" { return ["9": 1] }
    if tier <= 2 { return ["8": 6, "9": 3, "bumper": 1] }
    if tier <= 5 { return ["8": 5, "9": 4, "10": 1, "straight": 1, "snooker": 1, "carom": 0.5, "heyball": 0.6] }
    if tier <= 9 { return ["8": 3, "9": 4, "10": 2, "straight": 1, "rotation": 0.5, "snooker": 1.5, "carom": 1, "heyball": 1.2] }
    return ["8": 2, "9": 3, "10": 2, "snooker": 2, "carom": 1.5, "straight": 1, "heyball": 1.5]
  }
  func eventName(_ r: () -> Double, _ kind: String, _ tier: Int, _ disc: String, _ city: String, _ venue: String, _ natName: String, _ x: JV) -> String {
    let d = Self.c("SHORT")[disc]!.s, circ = { (t: Int) in Self.c("CIRC_NAMES")[Self.c("TIERS")[t]!["circ"]!.i]!.s }
    if kind == "open" {
      return tier <= 2 ? "\(venue) \(d) \(Self.pick(r, ["Night", "Shootout", "Weekly", "Cup", "Open"]))"
        : tier <= 7 ? "\(city) \(d) \(Self.pick(r, ["Open", "Classic", "Cup", "Grand Prix"]))" : "\(city) \(d) \(Self.pick(r, ["Open", "Grand Prix", "Masters", "International"]))"
    }
    if kind == "league" { return "\(venue) \(d) League" }
    if kind == "qualifier" { return truthy(x["card"]) ? "\(circ(x["card"]!.i)) Tour Card Qualifier" : "\(city) \(d) Qualifier" }
    if kind == "championship" { return tier <= 5 ? "\(city) Regional \(d) Championship" : "\(natName) National \(d) Championship" }
    if kind == "major" { return tier >= 11 ? Self.pick(r, ["World \(d) Championship", "\(city) Grand Masters"]) : "\(city) \(d) Masters" }
    if kind == "invitational" { return truthy(x["custom"]) ? "\(city) Elite Invitational" : "\(city) Invitational" }
    return "\(circ(tier)) Tour Finals"
  }
  static func nat(_ id: String) -> (id: String, name: String, first: [String], last: [String], cities: [String], w: Double, lean: [(String, Double)])? { CareerData.NAT.first { $0.id == id } }
  /* the career's event series: generated once from the seed and the player's home */
  func genSeries(_ seed: Int, _ natId: String, _ town: String) -> JV {
    let r = Self.R([String(seed), "series"]), home = Self.nat(natId) ?? CareerData.NAT[0]
    var out: [JV] = [], used = Set<String>()
    let hey = Self.c("HEY_NAT")
    for P in Self.c("PLAN").a {
      let tier = P[0]!.i, kind = P[1]!.s, fmt = P[2]!.s, size = P[3]!.i, len = P[4]!.i, per = P[5]!.i, x = P[6]!
      var disc = Self.pickW(r, discW(tier, kind))
      if disc == "bumper" && len > 1 { disc = "8" }
      var w = JObj()
      for n in CareerData.NAT { w[n.id] = .n(n.w * (disc == "heyball" ? (hey[n.id].flatMap { $0.truthy ? $0.d : nil } ?? 0.25) : (n.lean.first { $0.0 == disc }.map { $0.1 }.flatMap { $0 != 0 ? $0 : nil } ?? 1))) }
      let nat = tier >= 8 ? Self.nat(Self.pickW(r, .obj(w)))! : home
      let city = tier <= 3 && !town.isEmpty && r() < 0.4 ? town : Self.pick(r, nat.cities)
      let venue = tier <= 5 ? "\(Self.pick(r, Self.c("VEN_A").a.map { $0.s })) \(Self.pick(r, Self.c("VEN_B").a.map { $0.s }))" : "\(city) \(Self.pick(r, Self.c("VEN_BIG").a.map { $0.s }))"
      var name = ""
      for k in 0..<30 {
        name = eventName(r, kind, tier, disc, city, venue, nat.name, x)
        if !used.contains(name) { break }
        name += " " + ["II", "III", "IV"][k % 3]
        if !used.contains(name) { break }
      }
      used.insert(name)
      let bonus: Double = ["major", "championship", "finals"].contains(kind) ? 25 : kind == "invitational" ? 15 : 0
      let pres = CareerLib.round(Self.cl(40 + r() * 30 + bonus, 40, 100))
      let dow = len <= 1 ? 3 + Int((r() * 3).rounded(.down)) : len <= 3 ? 4 : 1
      var sv: JV = ["id": .n(out.count + 1), "tier": .n(tier), "kind": .str(kind), "fmt": .str(fmt), "size": .n(size), "len": .n(len), "per": .n(per), "disc": .str(disc),
                    "nat": .str(nat.id), "city": .str(city), "venue": .str(venue), "name": .str(name), "pres": .n(pres), "dow": .n(dow), "wk": []]
      for k in ["groups", "slots", "card", "top", "custom", "free", "tgtTier"] where truthy(x[k]) { sv[k] = x[k] }
      out.append(sv)
    }
    /* weeks: each tier's editions spread over weeks 2-48, a series' second edition half a season after its first */
    for t in 1...11 {
      var list = out.indices.filter { out[$0]["tier"]!.i == t && !["league", "finals", "qualifier"].contains(out[$0]["kind"]!.s) }
      var i = list.count - 1
      while i > 0 { let j = Int((r() * Double(i + 1)).rounded(.down)); list.swapAt(i, j); i -= 1 }
      var ins: [(Int, Int)] = []
      for ed in [0, 1] { for si in list where ed < out[si]["per"]!.i { ins.append((si, ed)) } }
      for (k, (si, ed)) in ins.enumerated() { let w = 2 + Int(((Double(k) + r() * 0.8) * 46 / Double(ins.count)).rounded(.down)); out[si]["wk"]?[ed] = .n(w) }
    }
    for si in out.indices {
      let kind = out[si]["kind"]!.s
      if kind == "league" { out[si]["wk"] = [.n(3 + Int((r() * 8).rounded(.down)))] }
      if kind == "finals" { out[si]["wk"] = [50] }
      if kind == "qualifier" && truthy(out[si]["card"]) { out[si]["wk"] = [.n(40 + Int((r() * 4).rounded(.down)))] }
      if kind == "qualifier" && truthy(out[si]["tgtTier"]) {
        let tt = out[si]["tgtTier"]!.i
        let tg = out.indices.first { out[$0]["tier"]!.i == tt && out[$0]["kind"]!.s == "championship" } ?? out.indices.first { out[$0]["tier"]!.i == tt && out[$0]["kind"]!.s == "open" }!
        let w0 = Swift.max(out[tg]["wk"]![0]!.i, 6)
        out[tg]["wk"]?[0] = .n(w0)
        out[si]["tgt"] = out[tg]["id"]!
        out[si]["wk"] = [.n(out[tg]["wk"]![0]!.i - 3)]
        out[si]["name"] = .str("\(out[tg]["name"]!.s) Qualifier")
        out[si]["tgtTier"] = nil
      }
    }
    return .arr(out)
  }
  static func isPool(_ d: String) -> Bool { !["snooker", "carom", "bumper"].contains(d) }
  func raceFor(_ disc: String, _ t: Int, _ kind: String) -> Int {
    let RU = Self.c("RACE_UNITS"), RACE = Self.c("RACE")
    var r = RU[disc] != nil ? RU[disc]![t]!.i : disc == "bumper" ? Swift.max(1, Int((RACE[t]!.d / 2).rounded(.up))) : RACE[t]!.i
    if (kind == "major" || kind == "finals") && RU[disc] == nil { r += 1 }
    return r
  }
  /* called shots tighten with the tier */
  func callFor(_ d: String, _ t: Int, _ kind: String, _ custom: Bool) -> JV {
    if custom { return ["require": "all", "detail": "strict"] }
    if d == "heyball" { return ["require": "off", "detail": "ball"] }
    if !Self.isPool(d) { return ["require": "off", "detail": "ball"] }
    if d == "straight" { return ["require": "all", "detail": t >= 8 ? "rails" : "pocket"] }
    if t <= 2 { return d == "8" ? ["require": "8ball", "detail": "pocket"] : ["require": "off", "detail": "ball"] }
    if kind == "league" { return ["require": "all", "detail": "pocket"] }
    if t <= 5 { return d == "8" ? ["require": "8ball", "detail": "pocket"] : d == "10" ? ["require": "official", "detail": "pocket"] : ["require": "off", "detail": "ball"] }
    return ["require": "official", "detail": "pocket"]
  }
  public func rulesFor(_ s: JV, _ race: Int) -> JV {
    let t = s["tier"]!.i, d = s["disc"]!.s
    let ruleset = d == "8" ? (t <= 2 ? "8-bar" : t <= 4 ? "8-league" : "8-wpa") : d == "9" ? (t <= 2 ? "9-bar" : "9-wpa") : d == "10" ? "10-wpa"
      : d == "straight" ? "14.1-wpa" : d == "rotation" ? "rotation-61" : d == "snooker" ? (t <= 5 ? "snooker-club" : "snooker-wpbsa") : d == "carom" ? "3c-umb" : d == "heyball" ? "heyball-masters" : "bumper-house"
    let table = d == "heyball" ? "heyball" : Self.isPool(d) ? (t <= 3 ? "7" : "9") : d == "snooker" ? (t <= 5 ? "compact" : "full") : d == "carom" ? "carom" : "octagon"
    var rules: JV = ["game": .str(d), "ruleset": .str(ruleset), "call": callFor(d, t, s["kind"]!.s, truthy(s["custom"])), "race": .n(race), "table": .str(table),
                     "pockets": .str(Self.isPool(d) && d != "heyball" && t <= 2 ? "generous" : "regulation")]
    if truthy(s["custom"]) { rules["custom"] = "Custom format: every shot called (ball, pocket and any rails), alternating breaks, no push-out" }
    return rules
  }
  func reqFor(_ s: JV) -> JV {
    let t = s["tier"]!.i, kind = s["kind"]!.s, lo = { (k: Int) in JV.n(Swift.max(1, t - k)) }
    if kind == "open" { return ["min": lo(2), "max": .n(t >= 10 ? 12 : t + 1)] }
    if kind == "league" { return ["min": lo(1), "max": .n(t + 1)] }
    if kind == "qualifier" { return ["min": lo(1), "max": .n(truthy(s["card"]) ? s["card"]!.i - 1 : t)] }
    if kind == "championship" || kind == "major" { return ["min": lo(1), "max": 12, "qual": 1] }
    if kind == "invitational" { return ["min": lo(1), "max": 12, "top": s["top"] ?? .null] }
    if kind == "finals" { return ["min": 1, "max": 12, "top": 8] }
    return ["min": 1, "max": 12]
  }
  /* one edition of a series in a season: dates, deadline, money, points, rules */
  public func instEvent(_ s: JV, _ sea: Int, _ ed: Int) -> JV {
    let seed = String(S["seed"]!.i), sid = String(s["id"]!.i), ser = S["ser"]!.a
    let r = Self.R([seed, "inst", sid, String(sea), String(ed)])
    var name = s["name"]!.s, city = s["city"]!.s, venue = s["venue"]!.s, pres0 = s["pres"]!.d
    let isTgt = ser.contains { $0["tgt"]?.num == s["id"]!.d }
    if sea > 1 {
      let h = Self.R([seed, "host", sid, String(sea), String(ed)]), to = Self.pick(h, Self.nat(s["nat"]!.s)!.cities), one = h()
      pres0 = CareerLib.round(Self.cl(s["pres"]!.d + (h() - 0.5) * 24, 30, 100))
      if s["tier"]!.i >= 3 && s["kind"]!.s != "finals" && s["tgt"] == nil {
        name = name.replacingOccurrences(of: s["city"]!.s, with: to); venue = venue.replacingOccurrences(of: s["city"]!.s, with: to); city = to
      }
      let oneOff = Self.c("ONE_OFF").a.map { $0.s }
      if one < 0.1 && !["qualifier", "finals", "league"].contains(s["kind"]!.s) && !isTgt {
        name = "\(oneOff[Int((one * 10 * Double(oneOff.count)).rounded(.down))]) \(name)"; pres0 = Swift.min(100, pres0 + 10)
      }
      if let tgt = s["tgt"]?.num, let tg = ser.first(where: { $0["id"]!.d == tgt }) { name = "\(instEvent(tg, sea, 0)["name"]!.s) Qualifier" }
    }
    var w = s["wk"]![ed]!.d
    if !["finals", "league", "qualifier"].contains(s["kind"]!.s) && !isTgt { w = Self.cl(w + (r() * 3).rounded(.down) - 1, 1, 49) }
    let dow = s["dow"]!.i, size = s["size"]!.i, len = s["len"]!.i, fmt = s["fmt"]!.s, kind = s["kind"]!.s
    let start = (sea - 1) * Self.YEAR + (Int(w) - 1) * 7 + dow
    let rounds = fmt == "league" ? 2 * (size - 1 + size % 2) : 0
    let end = fmt == "league" ? start + 7 * (rounds - 1) : start + Swift.max(1, len) - 1
    let t = s["tier"]!.i, presF = pres0 / 70, early = t >= 8 || ["major", "invitational", "finals"].contains(kind)
    let FEE = Self.c("FEE")[t]!.d, POT = Self.c("POT")[t]!.d
    let fee = truthy(s["free"]) || kind == "invitational" || kind == "finals" ? 0 : kind == "qualifier" ? CareerLib.round(FEE * 0.6) : FEE
    let purse = kind == "qualifier" ? CareerLib.round(Double(size) * fee * 0.5) : CareerLib.round((Double(size) * FEE * 0.9 + POT * Double(size) / 32) * presF / 5) * 5
    let race = raceFor(s["disc"]!.s, t, kind)
    var ev: JV = [
      "id": .str("\(sea).\(sid).\(ed)"), "ser": s["id"]!, "ed": .n(ed), "name": .str(name), "city": .str(city), "venue": .str(venue), "nat": s["nat"]!, "kind": .str(kind),
      "fmt": .str(fmt), "tier": .n(t), "circ": Self.c("TIERS")[t]!["circ"]!, "disc": s["disc"]!, "pres": .n(pres0), "start": .n(start), "end": .n(end), "dl": .n(start - (early ? 7 : 1)),
      "fee": .n(fee), "trav": .n(CareerLib.round(Self.c("TRAVEL")[t]!.d * (s["nat"]!.s != S["profile"]!["nat"]!.s ? 1.5 : 1))), "purse": .n(purse), "size": .n(size), "race": .n(race),
      "rules": rulesFor(s, race), "req": reqFor(s), "pts": .n(CareerLib.round(Self.c("BP")[t]!.d * presF * (kind == "qualifier" ? 0.5 : 1))),
    ]
    for k in ["groups", "slots", "card"] where truthy(s[k]) { ev[k] = s[k] }
    if let tgt = s["tgt"]?.num { ev["tgt"] = .str("\(sea).\(Int(tgt)).0") }
    return ev
  }
  public func genCalendar(_ sea: Int) -> JV {
    var out: [JV] = []
    for s in S["ser"]!.a { for ed in 0..<s["per"]!.i { out.append(instEvent(s, sea, ed)) } }
    return .arr(Self.sortCal(out))
  }
  static func sortCal(_ list: [JV]) -> [JV] {
    stableSorted(list) { a, b in
      let ds = a["start"]!.d - b["start"]!.d
      if ds != 0 { return ds < 0 }
      let dt = b["tier"]!.d - a["tier"]!.d
      if dt != 0 { return dt < 0 }
      return a["id"]!.s < b["id"]!.s
    }
  }

  // MARK: the player: money, news, stats
  func news(_ text: String) {
    var n = S["news"]!.a
    n.append([.n(S["day"]!.d), .str(text)])
    if n.count > 60 { n.removeFirst() }
    S["news"] = .arr(n)
  }
  /* every credit in or out: the ledger keeps the last 40, the totals keep all */
  func pay(_ amount: Double, _ kind: String, _ note: String) {
    if amount == 0 || amount.isNaN { return }
    let money = S["me"]!["money"]!.d + amount, tot = (S["tot"]![kind]?.num ?? 0) + abs(amount)
    S["me"]?["money"] = .n(money)
    S["tot"]?[kind] = .n(tot)
    var l = S["led"]!.a
    l.append([.n(S["day"]!.d), .n(amount), .str(kind), .str(note)])
    if l.count > 40 { l.removeFirst() }
    S["led"] = .arr(l)
  }
  func statD(_ d: String) -> JV {
    if S["st"]?["d"]?[d] == nil { S["st"]?["d"]?[d] = Self.blankStat() }
    return S["st"]!["d"]![d]!
  }
  func activeAI(_ id: Int) -> Bool { guard let m = S["pop"]?["m"]?[String(id)] else { return false }; return m["x"] == nil }
  func weekOf(_ day: Int) -> Int { Int((Double(day % Self.YEAR) / 7).rounded(.down)) + 1 }
  func gweek(_ day: Int) -> Int { Int((Double(day) / 7).rounded(.down)) }

  // MARK: rankings
  /* S.aw: [id, circuit, discipline index, points, global week, season]. key: a circuit index (0 local: this season only;
     1-4: the last 52 weeks), "d:<disc>" (52 weeks, every circuit) or "season" */
  public enum RankKey { case circ(Int), disc(String), season }
  func points(_ key: RankKey, _ gw0: Int? = nil) -> [(Int, Double)] {
    let gw = gw0 ?? gweek(S["day"]!.i), sNow = Int((Double(gw) / 52).rounded(.down)) + 1
    var order: [Int] = [], m: [Int: Double] = [:]
    let discs = Self.c("DISCS").a.map { $0.s }
    for a in S["aw"]!.a {
      if a[4]!.i > gw { continue }
      let ok: Bool
      switch key {
      case .season: ok = a[5]!.i == sNow
      case .circ(0): ok = a[1]!.i == 0 && a[5]!.i == sNow
      case .disc(let d): ok = a[2]!.i == (discs.firstIndex(of: d) ?? -1) && a[4]!.i > gw - 52
      case .circ(let c): ok = a[1]!.i == c && a[4]!.i > gw - 52
      }
      if ok { let id = a[0]!.i; if m[id] == nil { order.append(id) }; m[id] = (m[id] ?? 0) + a[3]!.d }
    }
    return order.map { ($0, m[$0]!) }
  }
  func rankList(_ key: RankKey, _ gw: Int? = nil) -> [(Int, Double)] {
    points(key, gw).filter { $0.1 > 0 }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
  }
  func rankOf(_ id: Int, _ key: RankKey, _ gw: Int? = nil) -> Int? { rankList(key, gw).firstIndex { $0.0 == id }.map { $0 + 1 } }

  // MARK: rivals
  /* a rivalry: how much of it there is, times how close it is */
  func rivalScore(_ h: JV) -> Double {
    let v = { (i: Int) in h[i]!.d }, n = v(0) + v(1), c = n != 0 ? 1 - abs(v(0) - v(1)) / n : 1
    return (n + 3 * (v(2) + v(3)) + 2 * (v(4) + v(5)) + v(6) + abs(v(7))) * (0.2 + 0.8 * c)
  }
  func rivalLive(_ id: Int) -> Bool { activeAI(id) && abs((S["pop"]!["m"]![String(id)]?["t"]?.num ?? 0) - S["me"]!["tier"]!.d) <= Self.c("RIVAL_GAP").d }
  func rivalList(_ n: Int = 10) -> [Int] {
    let ids: [Int] = S["h2h"]!.keys.map { Int($0)! }.filter { rivalLive($0) }
    var sc: [(Int, Double)] = []
    for id in ids { let v = rivalScore(S["h2h"]![String(id)]!); if v >= 3 { sc.append((id, v)) } }
    sc.sort { a, b in a.1 != b.1 ? a.1 > b.1 : a.0 < b.0 }
    return sc.prefix(n).map { $0.0 }
  }

  // MARK: offers: sponsors, challenges, exhibitions
  func nextId() -> String { let n = S["nx"]!.i + 1; S["nx"] = .n(n); return "o\(n)" }
  func sponsorOffers(_ why: String) {
    let open = S["off"]!.a.filter { $0["type"] == "sponsor" }.count
    if open >= 3 || (S["me"]!["tier"]!.i < 2 && S["me"]!["rep"]!.d < 10) { return }
    let r = Self.R([String(S["seed"]!.i), "spo", String(S["day"]!.i), why, String(S["nx"]!.i)]), t = Swift.min(11, S["me"]!["tier"]!.i), rep = S["me"]!["rep"]!.d
    let k = Swift.min(3 - open, why == "season" ? 2 : 1)
    for _ in 0..<Swift.max(0, k) {
      let cat = Self.pick(r, Self.c("SPONSOR_CATS").a.map { $0.s }), weeks = r() < 0.5 ? 26 : 52, circ = Self.c("TIERS")[t]!["circ"]!.i
      let sd = S["st"]!["d"]!
      let disc = sd.keys.sorted { a, b in let d = sd[b]!["w"]!.d - sd[a]!["w"]!.d; return d != 0 ? d < 0 : a < b }.first ?? S["profile"]!["disc"]!.s
      let tt = Double(t * t), w = Double(weeks)
      var pool: [JV] = [
        ["k": "wins", "n": .n(CareerLib.round((w / 26) * Double(6 + t))), "pay": .n(15 * tt)],
        ["k": "titles", "n": .n(weeks == 52 ? 2 : 1), "pay": .n(60 * tt)],
        ["k": "finals", "n": .n(weeks == 52 ? 3 : 2), "pay": .n(30 * tt)],
        ["k": "rank", "c": .n(circ), "n": .n(t >= 8 ? 16 : 8), "pay": .n(40 * tt)],
        ["k": "disc", "d": .str(disc), "n": .n(CareerLib.round((w / 26) * 4)), "pay": .n(20 * tt)],
        ["k": "events", "n": .n(CareerLib.round(w / 4)), "pay": .n(10 * tt)],
      ]
      var obj: [JV] = []
      while obj.count < 2 + (weeks == 52 ? 1 : 0) { obj.append(pool.remove(at: Int((r() * Double(pool.count)).rounded(.down)))) }
      let brand = "\(Self.pick(r, Self.c("BRANDS").a.map { $0.s })) \(cat)"
      let ret = CareerLib.round(3 * M.pow(Double(t), 1.7) * (1 + Swift.min(rep, 300) / 150) * formF(t))
      var off = S["off"]!.a
      let id = nextId()
      off.append(["id": .str(id), "type": "sponsor", "brand": .str(brand), "cat": .str(cat), "weeks": .n(weeks), "ret": .n(ret), "obj": .arr(obj), "bonus": .n(25 * tt), "exp": .n(S["day"]!.i + 28)])
      S["off"] = .arr(off)
    }
  }
  /* what the last 26 weeks are worth to a sponsor: 0.5 (cold) to 1.25 */
  func formF(_ t: Int) -> Double {
    let gw = gweek(S["day"]!.i)
    let pts = S["aw"]!.a.reduce(0.0) { $0 + ($1[0]!.i == Self.HUMAN && $1[4]!.i > gw - 26 ? $1[3]!.d : 0) }
    return 0.5 + 0.75 * Self.cl(pts / (Self.c("BP")[t]!.d * 2), 0, 1)
  }
  func objText(_ o: JV) -> String {
    let k = o["k"]!.s, n = o["n"]!.i
    switch k {
    case "wins": return "Win \(n) matches"
    case "titles": return "Win \(n) title\(n > 1 ? "s" : "")"
    case "finals": return "Reach \(n) finals"
    case "rank": return "Reach the top \(n) of the \(Self.c("CIRC_NAMES")[o["c"]!.i]!.s) rankings"
    case "disc": return "Win \(n) \(Self.c("SHORT")[o["d"]!.s]!.s) matches"
    default: return "Play \(n) events"
    }
  }
  func objNow(_ o: JV) -> Double {
    let a = S["st"]!["all"]!
    switch o["k"]!.s { case "wins": return a["w"]!.d; case "titles": return a["ti"]!.d; case "finals": return a["fi"]!.d; case "disc": return statD(o["d"]!.s)["w"]!.d; case "events": return a["ev"]!.d; default: return 0 }
  }
  /* a contract half met or better is offered again: the same brand, new objectives, more if all were met */
  func renewal(_ c: JV, _ met: Int) {
    let objN = c["obj"]!.count
    if met * 2 < objN || S["off"]!.a.contains(where: { $0["brand"] == c["brand"] }) || S["off"]!.a.filter({ $0["type"] == "sponsor" }).count >= 3 { return }
    let t = Swift.min(11, S["me"]!["tier"]!.i), weeks = CareerLib.round((c["to"]!.d - c["from"]!.d) / 7) == 52 ? 52 : 26
    let r = Self.R([String(S["seed"]!.i), "renew", String(S["day"]!.i), String(S["nx"]!.i)]), tt = Double(t * t), w = Double(weeks)
    var pool: [JV] = [["k": "wins", "n": .n(CareerLib.round((w / 26) * Double(6 + t))), "pay": .n(15 * tt)], ["k": "finals", "n": .n(weeks == 52 ? 3 : 2), "pay": .n(30 * tt)],
                      ["k": "events", "n": .n(CareerLib.round(w / 4)), "pay": .n(10 * tt)], ["k": "titles", "n": .n(weeks == 52 ? 2 : 1), "pay": .n(60 * tt)]], obj: [JV] = []
    while obj.count < 2 { obj.append(pool.remove(at: Int((r() * Double(pool.count)).rounded(.down)))) }
    var off = S["off"]!.a
    let id = nextId()
    off.append(["id": .str(id), "type": "sponsor", "renew": true, "brand": c["brand"]!, "cat": c["cat"]!, "weeks": .n(weeks),
                "ret": .n(CareerLib.round(c["ret"]!.d * (met == objN ? 1.15 : 1))), "obj": .arr(obj), "bonus": c["bonus"]!, "exp": .n(S["day"]!.i + 28)])
    S["off"] = .arr(off)
    news("\(c["brand"]!.s) offers to renew.")
  }
  func checkSponsors() {
    var sp = S["spons"]!.a
    for ci in sp.indices {
      if truthy(sp[ci]["end"]) { continue }
      var obj = sp[ci]["obj"]!.a
      for oi in obj.indices {
        if truthy(obj[oi]["done"]) { continue }
        let o = obj[oi]
        let ok = o["k"] == "rank" ? Double(rankOf(Self.HUMAN, .circ(o["c"]!.i)) ?? 1_000_000_000) <= o["n"]!.d : objNow(o) - o["base"]!.d >= o["n"]!.d
        if ok {
          let day = S["day"]!.d
          obj[oi]["done"] = .n(day)
          sp[ci]["obj"] = .arr(obj); S["spons"] = .arr(sp)
          pay(o["pay"]!.d, "spons", "\(sp[ci]["brand"]!.s): \(objText(o))"); news("\(sp[ci]["brand"]!.s) objective met: \(objText(o)).")
        }
      }
      sp[ci]["obj"] = .arr(obj)
    }
    S["spons"] = .arr(sp)
  }
  func closeContract(_ ci: Int) {
    let day = S["day"]!.d
    S["spons"]?[ci]?["end"] = .n(day)
    let c = S["spons"]![ci]!, met = c["obj"]!.a.filter { truthy($0["done"]) }.count, n = c["obj"]!.count
    if met == n { pay(c["bonus"]!.d, "spons", "\(c["brand"]!.s): every objective met") }
    news("\(c["brand"]!.s) contract ended: \(met) of \(n) objectives met.")
    var h = S["sph"]!.a
    h.append([c["brand"]!, c["from"]!, c["to"]!, .n(met), .n(n)])
    if h.count > 20 { h.removeFirst() }
    S["sph"] = .arr(h)
    renewal(c, met)
  }
  /* a rival's challenge or an exhibition: a two-player event of its own, best of legs */
  func matchOffer(_ type: String, _ opp: Int, _ r: () -> Double) {
    let sea = season, t = Swift.min(11, S["me"]!["tier"]!.i), start = S["day"]!.i + 14 + Int((r() * 10).rounded(.down))
    if seasonOf(start + 3) != sea || weekOf(start) > 49 { return }
    let disc = S["profile"]!["disc"]!.s
    let race = Self.isPool(disc) && disc != "straight" ? Self.c("RACE")[t]!.i : 3
    var off = S["off"]!.a
    let id = nextId()
    off.append(["id": .str(id), "type": .str(type), "opp": .n(opp), "start": .n(start), "end": .n(start + (type == "exhibition" ? 1 : 0)), "legs": .n(type == "exhibition" ? 3 : 1),
                "disc": .str(["8", "9"].contains(disc) ? disc : "9"), "race": .n(race), "tier": .n(t), "purse": .n(Double((type == "exhibition" ? 60 : 30) * t * t)), "exp": .n(S["day"]!.i + 10)])
    S["off"] = .arr(off)
  }
  func weekly() {
    let day = S["day"]!.i
    for ci in S["spons"]!.a.indices {
      let c = S["spons"]![ci]!
      if truthy(c["end"]) { continue }
      if Double(day) >= c["to"]!.d { closeContract(ci) } else { pay(c["ret"]!.d, "spons", "\(c["brand"]!.s) retainer") }
    }
    S["spons"] = .arr(S["spons"]!.a.filter { !truthy($0["end"]) })
    S["off"] = .arr(S["off"]!.a.filter { $0["exp"]!.d > Double(day) })
    checkSponsors()
    let circ = Self.c("TIERS")[S["me"]!["tier"]!.i]!["circ"]!.i
    if let rk = rankOf(Self.HUMAN, .circ(circ)) {
      var rh = S["rh"]!.a
      rh.append([.n(gweek(day)), .n(circ), .n(rk)])
      if rh.count > 260 { rh.removeFirst() }
      S["rh"] = .arr(rh)
      let b = S["best"]![String(circ)]
      if b == nil || Double(rk) < b![0]!.d { let v: JV = [.n(rk), .n(season), .n(weekOf(day))]; S["best"]?[String(circ)] = v }
    }
    let r = Self.R([String(S["seed"]!.i), "week", String(gweek(day))])
    if let rv = rivalList(1).first, activeAI(rv), rivalScore(S["h2h"]![String(rv)]!) >= 6, !S["off"]!.a.contains(where: { $0["type"] == "challenge" }),
       (S["ss"]!["ch"]?.num ?? 0) < Self.c("CHALLENGES").d, r() < 0.25 {
      let before = S["off"]!.count
      matchOffer("challenge", rv, r)
      if S["off"]!.count > before { let ch = (S["ss"]!["ch"]?.num ?? 0) + 1; S["ss"]?["ch"] = .n(ch) }
    }
    if S["me"]!["rep"]!.d >= 60 && !S["off"]!.a.contains(where: { $0["type"] == "exhibition" }) && r() < 0.12 {
      if let star = rankList(.circ(Swift.min(4, circ + 1))).map({ $0.0 }).first(where: { $0 != Self.HUMAN && activeAI($0) }) { matchOffer("exhibition", star, r) }
    }
  }
  /* a save of any age gains what it lacks */
  func upgrade() {
    if !truthy(S["ml"]) { S["ml"] = [:] }
    if S["rev"] == nil { let n = S["arch"]!.count; S["rev"] = .n(n) }
    if S["me"]!["fr"] == nil { let d = S["profile"]!["disc"]!.s, fr = CareerLib.round(CareerLib.rate(humanAttrs(), d, d) * Self.c("FR_K").d); S["me"]?["fr"] = .n(fr) }
    if S["me"]!["cardAt"] == nil { let sea = season; S["me"]?["cardAt"] = .n(sea) }
  }

  /* the season's end (rollSeason): not ported yet, the golden stays in season 1 */
  func rollSeason() { fatalError("Career: rollSeason is not ported yet") }

  public func digest() -> String { String(CareerLib.hashStr(S.stringify()), radix: 36) }
}
