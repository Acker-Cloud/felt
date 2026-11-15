/* index.html's career engine (#region career), line for line, on its own state: S is the page's save as JV, every
   function reads and writes it as the page does, and Career.digest() (hashStr of JSON.stringify(S)) is the page's.
   Ported so far: the save's shape (newState), cleanProfile, the save index, the population (popAt, attrsOf, ageOf,
   rate, assignTiers) and create up to the tiers. CareerTests compares each checkpoint the page traced. */
import Foundation

private typealias M = JSMath

public final class CareerEngine {
  public var S: JV = .null
  /* memStore: getItem / setItem / removeItem (the page's localStorage) */
  public var store: [String: String] = [:]
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
    return (true, id)
  }
  public func digest() -> String { String(CareerLib.hashStr(S.stringify()), radix: 36) }
}
