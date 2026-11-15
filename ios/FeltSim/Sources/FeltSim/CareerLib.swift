/* index.html's career engine, the pieces the quick tournament (6f) plays on (Career.lib), line for line:
   hashStr and seedOf, the population's genPlayer, rate, the match model (playModel, modelUnits), and the
   brackets (makeBracket's single and double elimination, ctxOf, outcome). The constants are the page's own
   (CareerData.swift, generated). career.json holds the page's results; CareerTests compares them bit for bit. */
import Foundation

private typealias M = JSMath

public enum CareerLib {
  /* FNV-1a over the string's UTF-16 units */
  public static func hashStr(_ s: String) -> UInt32 {
    var h: UInt32 = 0x811c9dc5
    for u in s.utf16 { h ^= UInt32(u); h = h &* 0x01000193 }
    return h
  }
  public static func seedOf(_ k: [String]) -> UInt32 { hashStr(k.joined(separator: "|")) }
  static func R(_ k: [String]) -> () -> Double { cpuRng(Double(seedOf(k))) }
  static func cl(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, v)) }
  static func pick<T>(_ r: () -> Double, _ a: [T]) -> T { a[Int((r() * Double(a.count)).rounded(.down)) % a.count] }
  /* pickW over keys in the page's object order */
  static func pickW(_ r: () -> Double, _ w: [(String, Double)]) -> String {
    let tot = w.reduce(0.0) { $0 + $1.1 }
    var x = r() * tot
    for (k, v) in w { x -= v; if x < 0 { return k } }
    return w[w.count - 1].0
  }
  static func gauss(_ r: () -> Double) -> Double { let u = Swift.max(1e-9, r()), v = r(); return (-2 * M.log(u)).squareRoot() * M.cos(2 * Double.pi * v) }
  /* Math.round: the nearest integer, halves up */
  static func round(_ v: Double) -> Double { (v + 0.5).rounded(.down) }
  static func r2(_ v: Double) -> Double { round(v * 100) / 100 }

  public struct Player: Sendable {
    public let id: Int, name: String, first: String, last: String, nick: String, nat: String, town: String, hand: String
    public let age0: Int, talent: Double, peak: Int, retire: Int, arch: String, disc: String, base: [String: Double], ini: String, col: String
  }
  /* genPlayer: everything about a generated player that never changes */
  public static func genPlayer(_ seed: Int, _ id: Int, _ names: inout Set<String>) -> Player {
    let D = CareerData.self, r = R([String(seed), "p", String(id)]), young = id > D.POP
    let natId = pickW(r, D.NAT.map { ($0.id, $0.w) }), nat = D.NAT.first { $0.id == natId }!
    var first = "", last = "", name = ""
    var salt = 0
    while true {
      let nr = R([String(seed), "pn", String(id), String(salt)])
      let nn = salt < 6 ? nat : D.NAT[Int((nr() * Double(D.NAT.count)).rounded(.down))]
      first = pick(nr, nn.first); last = pick(nr, nn.last); name = "\(first) \(last)"
      if !names.contains(name) || salt > 40 { break }
      salt += 1
    }
    names.insert(name)
    let age0 = young ? 16 + Int((r() * 5).rounded(.down)) : 17 + Int((M.pow(r(), 1.3) * 36).rounded(.down))
    let talent = M.pow(r(), 1.5), peak = 27 + Int((r() * 8).rounded(.down)), retire = 40 + Int((r() * 18).rounded(.down))
    let arch = pick(r, D.ARCH)
    var lean: [(String, Double)] = [("8", 30), ("9", 26), ("10", 10), ("straight", 5), ("rotation", 4), ("snooker", 12), ("carom", 7), ("bumper", 3)]
    for (k, f) in nat.lean { if let i = lean.firstIndex(where: { $0.0 == k }) { lean[i].1 *= f } }
    let disc = pickW(r, lean)
    let m = 24 + 72 * talent
    var base: [String: Double] = [:]
    for a in D.ATTRS { base[a] = round(cl(m + (arch.d[a] ?? 0) + gauss(r) * 6, 5, 99)) }
    base["agg"] = round(cl(50 + (arch.d["agg"] ?? 0) + gauss(r) * 10, 5, 95))
    let hand = r() < 0.12 ? "left" : "right", town = pick(r, nat.cities)
    let nick = r() < 0.4 ? pick(r, D.NICKS) : ""
    let col = pick(r, D.AV_COLS)
    var l2 = last
    if l2.hasPrefix("de ") || l2.hasPrefix("De ") { l2 = String(l2.dropFirst(3)) }
    let ini = (String(first.prefix(1)) + String(l2.prefix(1))).uppercased()
    return Player(id: id, name: name, first: first, last: last, nick: nick, nat: nat.id, town: town, hand: hand, age0: age0, talent: r2(talent),
                  peak: peak, retire: retire, arch: arch.id, disc: disc, base: base, ini: ini, col: col)
  }
  /* rate: a player's rating at a discipline, the weights summed in the page's order */
  public static func rate(_ at: [String: Double], _ disc: String, _ pref: String) -> Double {
    let w = CareerData.WEIGHTS[disc] ?? CareerData.WEIGHTS["8"]!
    var s = 0.0
    for (a, v) in w { s += v * (at[a] ?? 0) }
    let sp = CareerData.SPECIALIST
    return s + (pref == disc ? 4 : sp.contains(pref) != sp.contains(disc) ? -6 : 0)
  }
  public static func modelUnits(_ disc: String, _ race: Int) -> Int {
    disc == "straight" ? Int((Double(race) / 14).rounded(.up)) : disc == "carom" ? Int((Double(race) / 4).rounded(.up)) : race
  }
  public struct Side { public var at: [String: Double], pref: String, adj: Double = 0
    public init(at: [String: Double], pref: String, adj: Double = 0) { self.at = at; self.pref = pref; self.adj = adj } }
  /* playModel: the score drawn rack by rack; s in the race's units, first the breaker of the first rack */
  /* rackOf: one rack's numbers for side A, from its own stream */
  public struct Rack { public var won: Bool, broke: Bool, legal: Bool?, bnr: Bool, runout: Bool, att: Int, pot: Int, sf: Int, ss: Int, fo: Int, sc: Int }
  static func rackOf(_ r: () -> Double, _ won: Bool, _ broke: Bool, _ at: [String: Double], _ disc: String) -> Rack {
    let legal: Bool? = broke ? (disc == "snooker" || disc == "carom" || disc == "bumper" ? true : r() < 0.6 + 0.35 * at["brk"]! / 100) : nil
    let pb = cl(((at["acc"]! + at["cb"]!) / 2 - 30) / 120, 0.005, 0.6) * (CareerData.C["BNR_F"]![disc]?.num ?? 1)
    let bnr = broke && legal == true && won && r() < pb * 1.6
    let runout = won && (bnr || r() < pb * 1.4 + 0.1)
    let att = 3 + Int((r() * 6).rounded(.down)) + (won ? 3 : 0)
    let pot = Swift.min(att, Int(round(Double(att) * cl(0.35 + at["acc"]! / 180 + (r() - 0.5) * 0.2, 0.05, 0.98))))
    let sf = r() < 0.3 + at["safe"]! / 250 ? 1 + (r() < 0.3 ? 1 : 0) : 0
    var ss = 0
    for _ in 0..<sf { if r() < 0.2 + at["safe"]! / 140 { ss += 1 } }
    let fo = r() < 0.3 - at["con"]! / 400 ? 1 : 0, sc = fo == 1 && r() < 0.45 ? 1 : 0
    return Rack(won: won, broke: broke, legal: legal, bnr: bnr, runout: runout, att: att, pot: pot, sf: sf, ss: ss, fo: fo, sc: sc)
  }
  public static func playModel(_ A: Side, _ B: Side, _ disc: String, _ race: Int, _ seed: Double) -> (s: [Int], first: Int) {
    let o = playModel(A, B, disc, race, seed, detail: false); return (o.s, o.first)
  }
  public static func playModel(_ A: Side, _ B: Side, _ disc: String, _ race: Int, _ seed: Double, detail: Bool) -> (s: [Int], first: Int, racks: [Rack]) {
    let r = cpuRng(seed), units = modelUnits(disc, race)
    let dr: (() -> Double)? = detail ? cpuRng(Double(toUint32(seed) ^ 0x5bd1e995)) : nil
    var racks: [Rack] = []
    let ra = rate(A.at, disc, A.pref) + A.adj + gauss(r) * (100 - A.at["con"]!) / 12
    let rb = rate(B.at, disc, B.pref) + B.adj + gauss(r) * (100 - B.at["con"]!) / 12
    let adv0 = CareerData.BRK_ADV[disc] ?? 0
    var sa = 0, sb = 0, br = r() < 0.5 ? 0 : 1
    let first = br
    while sa < units && sb < units {
      var d = ra - rb
      if sa == units - 1 || sb == units - 1 { d += (A.at["pres"]! - B.at["pres"]!) / 8 }
      let adv = adv0 + ((br == 0 ? A.at["brk"]! : B.at["brk"]!) - 50) / 250
      let aw = r() < 1 / (1 + M.exp(-(d / 11 + (br == 0 ? adv : -adv))))
      if let dr { racks.append(rackOf(dr, aw, br == 0, A.at, disc)) }
      if aw { sa += 1 } else { sb += 1 }
      br ^= 1
    }
    var s = [sa, sb]
    if units != race {
      s = sa > sb ? [race, Swift.min(race - 1, Int(round(Double(sb * race) / Double(units))))] : [Swift.min(race - 1, Int(round(Double(sa * race) / Double(units)))), race]
    }
    return (s, first, racks)
  }

  // MARK: brackets

  /* a ref: ["s", i] seed i, ["w", m] / ["l", m] the winner / loser of match m, ["g", g, k] the k-th of group g once its
     games are done, ["n"] a bye */
  public enum Ref: Equatable, Sendable { case s(Int), w(Int), l(Int), g(Int, Int), n }
  public struct Match: Sendable {
    public var a: Ref, b: Ref, br: String, rd: Int, st: Int? = nil, el: String? = nil, fin = false, cond: String? = nil, of: Int? = nil, dep = 0
    public var g: Int? = nil, leg = 0, legs = 0
  }
  public struct Bracket: Sendable {
    public let fmt: String, n: Int, M: [Match], maxDep: Int
    public var groups: [[Int]]? = nil, gm: [[Int]]? = nil
  }
  public static func seedOrder(_ size: Int) -> [Int] {
    var p = [1]
    while p.count < size { let n = p.count * 2 + 1; p = p.flatMap { [$0, n - $0] } }
    return p
  }
  static func nextPow2(_ n: Int) -> Int { var s = 1; while s < n { s *= 2 }; return s }
  nonisolated(unsafe) static var TC: [String: Bracket] = [:]
  static let TCLock = NSLock()
  /* makeBracket: single, qualifier, double, rr, league, series, groups (o: groups, legs, slots) */
  public static func makeBracket(_ fmt: String, _ n: Int, groups gO: Int = 0, legs lO: Int = 0, slots sO: Int = 0) -> Bracket {
    let key = "\(fmt)|\(n)|\(gO)|\(lO)|\(sO)"
    TCLock.lock(); if let t = TC[key] { TCLock.unlock(); return t }; TCLock.unlock()
    var M: [Match] = [], groups: [[Int]]? = nil, gm: [[Int]]? = nil
    @discardableResult func add(_ a: Ref, _ b: Ref, _ br: String, _ rd: Int, st: Int? = nil, el: String? = nil, fin: Bool = false, cond: String? = nil, of: Int? = nil, g: Int? = nil, leg: Int = 0, legs: Int = 0) -> Int {
      M.append(Match(a: a, b: b, br: br, rd: rd, st: st, el: el, fin: fin, cond: cond, of: of, g: g, leg: leg, legs: legs)); return M.count - 1
    }
    func seedRef(_ refs: [Ref], _ k: Int) -> Ref { k - 1 < refs.count ? refs[k - 1] : .n }
    @discardableResult func elim(_ refs: [Ref], _ br: String, _ stop: Int, _ stage0: Int, _ rd0: Int) -> [Int] {
      let size = nextPow2(Swift.max(2, refs.count)), ord = seedOrder(size)
      var cur: [Int] = [], rd = 0
      for i in stride(from: 0, to: size, by: 2) { cur.append(add(seedRef(refs, ord[i]), seedRef(refs, ord[i + 1]), br, rd0, st: stage0, el: "true")) }
      while cur.count > stop {
        rd += 1
        var nx: [Int] = []
        for i in stride(from: 0, to: cur.count, by: 2) { nx.append(add(.w(cur[i]), .w(cur[i + 1]), br, rd0 + rd, st: stage0 + rd, el: "true")) }
        cur = nx
      }
      if stop == 1 { M[cur[0]].fin = true }
      return cur
    }
    @discardableResult func rr(_ idx: [Int], _ br: String, _ rd0: Int, _ legs: Int, g: Int? = nil) -> Int {
      var p = idx
      if p.count % 2 == 1 { p.append(-1) }
      let m = p.count, rounds = m - 1
      for leg in 0..<legs {
        for r in 0..<rounds {
          for i in 0..<(m / 2) {
            let u = p[i], v = p[m - 1 - i]
            if u == -1 || v == -1 { continue }
            let flip = (r + i + leg) % 2 == 1
            add(.s(flip ? v : u), .s(flip ? u : v), br, rd0 + leg * rounds + r, g: g)
          }
          if m > 1 { p = [p[0], p[m - 1]] + Array(p[1..<(m - 1)]) }
        }
      }
      return legs * rounds
    }
    let seeds = Array(0..<n), sref = seeds.map { Ref.s($0) }
    switch fmt {
    case "single": elim(sref, "W", 1, 0, 0)
    case "qualifier": elim(sref, "Q", Swift.max(1, sO != 0 ? sO : 2), 0, 0)
    case "double":
      let size = nextPow2(Swift.max(4, n)), k = Int(log2(Double(size)).rounded()), ord = seedOrder(size)
      var W: [[Int]] = [[]]
      for i in stride(from: 0, to: size, by: 2) { W[0].append(add(seedRef(sref, ord[i]), seedRef(sref, ord[i + 1]), "U", 0)) }
      for r in 1..<k { W.append([]); for i in stride(from: 0, to: W[r - 1].count, by: 2) { W[r].append(add(.w(W[r - 1][i]), .w(W[r - 1][i + 1]), "U", r)) } }
      var L: [Int] = [], ls = 0
      for i in stride(from: 0, to: W[0].count, by: 2) { L.append(add(.l(W[0][i]), .l(W[0][i + 1]), "L", 1, st: ls, el: "true")) }
      ls += 1
      for r in 1..<k {
        var drops = W[r]
        if r % 2 == 1 { drops.reverse() }
        L = L.enumerated().map { i, m in add(.w(m), .l(drops[i]), "L", r + 1, st: ls, el: "true") }
        ls += 1
        if r < k - 1 {
          var nx: [Int] = []
          for i in stride(from: 0, to: L.count, by: 2) { nx.append(add(.w(L[i]), .w(L[i + 1]), "L", r + 1, st: ls, el: "true")) }
          L = nx; ls += 1
        }
      }
      let gf = add(.w(W[k - 1][0]), .w(L[0]), "G", k + 1, st: ls, el: "gf", fin: true)
      add(.w(gf), .l(gf), "G2", k + 2, st: ls + 1, el: "true", fin: true, cond: "reset", of: gf)
    case "rr": rr(seeds, "R", 0, 1)
    case "league": rr(seeds, "R", 0, 2)
    case "series":
      let legs = Swift.max(1, lO)
      for i in 0..<legs { add(.s(0), .s(1), "S", i, cond: "leg", leg: i, legs: legs) }
    case "groups":
      let G = gO != 0 ? gO : 2
      var gr = Array(repeating: [Int](), count: G), gmm = Array(repeating: [Int](), count: G)
      for i in seeds { let row = i / G, col = i % G; gr[row % 2 == 1 ? G - 1 - col : col].append(i) }
      var grounds = 0
      for (gi, g) in gr.enumerated() { let at = M.count; grounds = Swift.max(grounds, rr(g, "P", 0, 1, g: gi)); for m in at..<M.count { gmm[gi].append(m) } }
      groups = gr; gm = gmm
      let refs = (0..<(2 * G)).map { j in j < G ? Ref.g(j, 0) : Ref.g(j - G, 1) }
      elim(refs, "K", 1, 1, grounds)
    default: fatalError("format \(fmt)")
    }
    /* depth: a match after everything it depends on (round robins: by round) */
    var dep: [Int] = []
    func depOf(_ r: Ref) -> Int {
      switch r { case .w(let m), .l(let m): return dep[m]; case .g(let g, _): return Swift.max(0, gm![g].map { dep[$0] }.max() ?? 0); default: return 0 }
    }
    for m in M.indices {
      var d = Swift.max(depOf(M[m].a), depOf(M[m].b))
      if M[m].cond == "reset", let o = M[m].of { d = Swift.max(d, dep[o]) }
      if ["R", "P", "S"].contains(M[m].br) { d = M[m].rd }
      dep.append(d + 1); M[m].dep = d + 1
    }
    let T = Bracket(fmt: fmt, n: n, M: M, maxDep: Swift.max(1, dep.max() ?? 1), groups: groups, gm: gm)
    TCLock.lock(); TC[key] = T; TCLock.unlock()
    return T
  }
  /* a match's state: wait, ready, done, bye, skip; a and b the entrants (nil unknown, NONE none: the page's null; not -1,
     which is the career's HUMAN), w and l */
  public static let NONE = Int.min
  public struct Outcome: Equatable, Sendable { public var st: String, a: Int? = nil, b: Int? = nil, w: Int? = nil, l: Int? = nil, s: [Int]? = nil }
  public final class Ctx {
    public let T: Bracket, f: [Int], res: [[Int]?]
    var memo: [Int: Outcome] = [:]
    var gt: [Int: [Int]?] = [:]
    public init(_ T: Bracket, _ f: [Int], _ res: [[Int]?]) { self.T = T; self.f = f; self.res = res }
  }
  /* entrants: nil while unknown (undefined), NONE for none (null) */
  static func ent(_ c: Ctx, _ ref: Ref) -> Int?? {
    switch ref {
    case .n: return .some(NONE)
    case .s(let i): return .some(i < c.f.count ? c.f[i] : NONE)
    case .g(let g, let k): guard let t = groupTable(c, g) else { return .none }; return .some(k < t.count ? t[k] : NONE)
    case .w(let m): let o = outcome(c, m); return o.st == "done" || o.st == "bye" ? .some(o.w ?? NONE) : o.st == "skip" ? .some(NONE) : .none
    case .l(let m): let o = outcome(c, m); return o.st == "done" || o.st == "bye" ? .some(o.l ?? NONE) : o.st == "skip" ? .some(NONE) : .none
    }
  }
  public static func outcome(_ c: Ctx, _ m: Int) -> Outcome {
    if let o = c.memo[m] { return o }
    let x = c.T.M[m]
    let o: Outcome
    if x.cond == "reset" {
      let g = outcome(c, x.of!)
      o = g.st == "done" || g.st == "bye" ? (g.w == g.a || g.l == nil || g.l == NONE ? Outcome(st: "skip") : sides(c, m, .some(g.w!), .some(g.l!))) : Outcome(st: "wait")
    } else if x.cond == "leg" {
      let need = x.legs / 2 + 1, a = ent(c, x.a), b = ent(c, x.b)
      var wa = 0, wb = 0, waiting = false
      for j in (m - x.leg)..<m {
        let p = outcome(c, j)
        if p.st == "wait" || p.st == "ready" { waiting = true } else if p.st == "done" || p.st == "bye" { if a != nil && p.w == a! { wa += 1 } else { wb += 1 } }
      }
      o = waiting ? Outcome(st: "wait") : wa >= need || wb >= need ? Outcome(st: "skip") : sides(c, m, a, b)
    } else { o = sides(c, m, ent(c, x.a), ent(c, x.b)) }
    c.memo[m] = o
    return o
  }
  static func sides(_ c: Ctx, _ m: Int, _ a: Int??, _ b: Int??) -> Outcome {
    guard let a, let b else { return Outcome(st: "wait", a: a ?? nil, b: b ?? nil) }
    if a == NONE || b == NONE { return Outcome(st: "bye", a: a, b: b, w: a == NONE ? b : a, l: NONE) }
    guard let r = c.res[m] else { return Outcome(st: "ready", a: a, b: b) }
    return Outcome(st: "done", a: a, b: b, w: r[0] > r[1] ? a : b, l: r[0] > r[1] ? b : a, s: r)
  }
  static func groupTable(_ c: Ctx, _ g: Int) -> [Int]? {
    if let t = c.gt[g] { return t }
    var games: [Outcome] = []
    for m in c.T.gm![g] {
      let o = outcome(c, m)
      if o.st == "wait" || o.st == "ready" { c.gt[g] = .some(nil); return nil }
      if o.st == "done" { games.append(o) }
    }
    let pids = c.T.groups![g].filter { $0 < c.f.count }.map { c.f[$0] }
    let t = standings(pids, games) { p in c.f.firstIndex(of: p) ?? -1 }.map { $0.p }
    c.gt[g] = .some(t)
    return t
  }
  /* a round robin table: wins; among players level on wins, wins against each other; rack difference; racks won; seeding */
  public struct Row { public var p: Int, pl = 0, w = 0, l = 0, rf = 0, ra = 0, h = 0 }
  public static func standings(_ pids: [Int], _ games: [Outcome], _ seedIx: (Int) -> Int) -> [Row] {
    var row: [Int: Row] = [:]
    for p in pids { row[p] = Row(p: p) }
    for g in games {
      guard row[g.a!] != nil, row[g.b!] != nil else { continue }
      row[g.a!]!.pl += 1; row[g.b!]!.pl += 1
      row[g.a!]!.rf += g.s![0]; row[g.a!]!.ra += g.s![1]; row[g.b!]!.rf += g.s![1]; row[g.b!]!.ra += g.s![0]
      if g.w == g.a { row[g.a!]!.w += 1; row[g.b!]!.l += 1 } else { row[g.b!]!.w += 1; row[g.a!]!.l += 1 }
    }
    var rows = pids.map { row[$0]! }
    var byW: [Int: Set<Int>] = [:]
    for x in rows { byW[x.w, default: []].insert(x.p) }
    for i in rows.indices { let tied = byW[rows[i].w]!; if tied.count > 1 { let p = rows[i].p; rows[i].h = games.filter { $0.w == p && tied.contains($0.a!) && tied.contains($0.b!) }.count } }
    rows.sort { x, y in
      if y.w != x.w { return y.w < x.w }
      if y.h != x.h { return y.h < x.h }
      if (y.rf - y.ra) != (x.rf - x.ra) { return (y.rf - y.ra) < (x.rf - x.ra) }
      if y.rf != x.rf { return y.rf < x.rf }
      return seedIx(x.p) < seedIx(y.p)
    }
    return rows
  }

  public static func complete(_ c: Ctx) -> Bool { c.T.M.indices.allSatisfy { let s = outcome(c, $0).st; return s == "done" || s == "bye" || s == "skip" } }
  /* final places, best first: knockouts by the stage each went out at (a shared place: 1 + how many went out later);
     round robins and leagues the table; groups the knockout, then those out in the groups by their group place */
  public static func placings(_ T: Bracket, _ f: [Int], _ res: [[Int]?]) -> [[Int]] {
    let c = Ctx(T, f, res), pids = f
    let seedIx = { (p: Int) in f.firstIndex(of: p) ?? -1 }
    if T.fmt == "rr" || T.fmt == "league" {
      let games = T.M.indices.map { outcome(c, $0) }.filter { $0.st == "done" }
      return standings(pids, games, seedIx).enumerated().map { [$0.element.p, $0.offset + 1] }
    }
    var st: [Int: Double] = Dictionary(pids.map { ($0, Double.infinity) }, uniquingKeysWith: { a, _ in a })
    for (m, x) in T.M.enumerated() {
      let o = outcome(c, m)
      if o.st != "done" { continue }
      if T.fmt == "series" { if m == T.M.count - 1 || outcome(c, m + 1).st == "skip" { st[o.l!] = 0 }; continue }
      if x.el == "true" { st[o.l!] = Double(x.st!) }
      else if x.el == "gf" && outcome(c, m + 1).st == "skip" { st[o.l!] = Double(x.st!) }
    }
    if T.fmt == "groups" { for gi in T.groups!.indices { let t = groupTable(c, gi) ?? []; for (k, p) in t.enumerated() where k >= 2 { st[p] = Double(-k) } } }
    let vals = pids.map { st[$0]! }
    let out = pids.map { p in [p, 1 + vals.filter { $0 > st[p]! }.count] }
    return out.sorted { a, b in a[1] != b[1] ? a[1] < b[1] : seedIx(a[0]) < seedIx(b[0]) }
  }
  public static func roundName(_ fmt: String, _ T: Bracket, _ m: Int) -> String {
    let x = T.M[m]
    if x.br == "S" { return "Leg \(x.leg + 1) of \(x.legs)" }
    if x.br == "R" { return fmt == "league" ? "Matchday \(x.rd + 1)" : "Round \(x.rd + 1)" }
    if x.br == "P" { return "Group \(Array("ABCDEFGH")[x.g!]), round \(x.rd + 1)" }
    if x.br == "G" { return "Grand final" }
    if x.br == "G2" { return "Grand final, deciding match" }
    if x.br == "L" { return "Losers bracket, round \((x.st ?? 0) + 1)" }
    let left = T.M.filter { $0.br == x.br && $0.rd == x.rd }.count
    if x.br == "Q" { return left == 1 ? "Qualifying match" : "Qualifier round \(x.rd + 1)" }
    return left == 1 ? "Final" : left == 2 ? "Semi-final" : left == 4 ? "Quarter-final" : "Round of \(left * 2)"
  }
}

/* 6f's quick tournament, its pure part, line for line (T_KINDS to tourneyNew): the field (the player and CPU entrants
   from genPlayer, each a level), the draw, every CPU match the model settles before the player's next, the places */
public struct Tourney: Codable, Sendable {
  /* ini and col: the generated player's avatar (tourneyNew's av: g.avatar); absent in a tournament saved before them */
  public struct Entrant: Codable, Sendable { public var name: String, first: String, me: Bool? = nil, arch: String? = nil, level: String? = nil, ini: String? = nil, col: String? = nil }
  public var v = 1, seed: Int, kind: String, ruleset: String, fmt: String, size: Int, race: Int, str: String
  public var field: [Entrant], f: [Int], res: [[Int]?], sim: [Bool], ff: [Bool], live: Int? = nil, done = false, places: [[Int]]? = nil, msg = ""
  public static let KINDS = ["8", "9", "10", "straight", "rotation", "heyball", "snooker", "carom"], SIZES = [4, 8, 16], FMTS = ["single", "double"], FIELDS = ["mixed", "easy", "medium", "hard"]
  public static func races(_ kind: String) -> [Int] { ["straight": [25, 50, 75, 100], "snooker": [1, 2, 3], "carom": [5, 10, 15]][kind] ?? [1, 2, 3, 5] }
  public static func points(_ kind: String) -> Bool { kind == "straight" || kind == "carom" }
  static let RACE_DEF = ["straight": 50, "snooker": 2, "carom": 10], BASE = ["easy": 40.0, "medium": 58, "hard": 76]
  /* tAttrs: an AI entrant's attributes for the model, its level's base moved by its archetype */
  static func attrs(_ level: String, _ arch: String) -> [String: Double] {
    let d = CareerData.ARCH.first { $0.id == arch }?.d ?? [:], b = BASE[level] ?? BASE["medium"]!
    var at: [String: Double] = [:]
    for k in CareerData.ATTRS { at[k] = Swift.min(99, Swift.max(5, CareerLib.round((k == "agg" ? 50 : b) + (d[k] ?? 0)))) }
    return at
  }
  public var bracket: CareerLib.Bracket { CareerLib.makeBracket(fmt, size) }
  public func ctx() -> CareerLib.Ctx { CareerLib.Ctx(bracket, f, res) }
  /* tMine: the player's (entrant 0) match ready to play, or nil */
  public func mine(_ c: CareerLib.Ctx? = nil) -> Int? {
    let c = c ?? ctx()
    for m in c.T.M.indices where res[m] == nil { let o = CareerLib.outcome(c, m); if o.st == "ready" && (o.a == 0 || o.b == 0) { return m } }
    return nil
  }
  func model(_ a: Int, _ b: Int, _ m: Int) -> [Int] {
    let side = { (id: Int) in CareerLib.Side(at: Tourney.attrs(self.field[id].level!, self.field[id].arch!), pref: self.kind) }
    return CareerLib.playModel(side(a), side(b), kind, race, Double(CareerLib.seedOf([String(seed), "m", String(m)]))).s
  }
  /* tSettle: every CPU match playable before the player's next (all once the player is out), then the end and places */
  public mutating func settle() {
    let T = bracket
    for _ in 0..<400 {
      let c = CareerLib.Ctx(T, f, res), my = mine(c), lim = my == nil ? Int.max : T.M[my!].dep
      var pickM = -1, o: CareerLib.Outcome? = nil
      for i in T.M.indices where pickM < 0 {
        if res[i] != nil || T.M[i].dep > lim { continue }
        let x = CareerLib.outcome(c, i)
        if x.st == "ready" && x.a != 0 && x.b != 0 { pickM = i; o = x }
      }
      if pickM < 0 { break }
      res[pickM] = model(o!.a!, o!.b!, pickM); sim[pickM] = true
    }
    let c = CareerLib.Ctx(T, f, res)
    done = CareerLib.complete(c)
    places = done ? CareerLib.placings(T, f, res) : nil
  }
  /* tourneyNew */
  public static func make(kind k: String, ruleset: String?, size s: Int, fmt fm: String, race r: Int, field fl: String, seed sd: Int) -> Tourney {
    let seed = sd == 0 ? 1 : sd, kind = KINDS.contains(k) ? k : "9", size = SIZES.contains(s) ? s : 8, fmt = FMTS.contains(fm) ? fm : "single"
    let race = races(kind).contains(r) ? r : RACE_DEF[kind] ?? 3
    let sets = RULESETS.values.filter { $0.game == kind && !$0.ring }.map { $0.id }
    let rs = ruleset.flatMap { sets.contains($0) ? $0 : nil } ?? DEFAULT_RULESET[kind]!, str = FIELDS.contains(fl) ? fl : "mixed"
    var names: Set<String> = ["You"], field = [Entrant(name: "You", first: "You", me: true)]
    for i in 1..<size {
      let g = CareerLib.genPlayer(seed, i, &names), u = cpuRng(Double(CareerLib.seedOf([String(seed), "lv", String(i)])))()
      field.append(Entrant(name: g.name, first: g.first, arch: g.arch, level: str != "mixed" ? str : u < 0.3 ? "easy" : u < 0.7 ? "medium" : "hard", ini: g.ini, col: g.col))
    }
    var f = Array(0..<field.count)
    let rr = cpuRng(Double(CareerLib.seedOf([String(seed), "draw"])))
    for i in stride(from: f.count - 1, to: 0, by: -1) { let j = Int((rr() * Double(i + 1)).rounded(.down)); f.swapAt(i, j) }
    let n = CareerLib.makeBracket(fmt, size).M.count
    var t = Tourney(seed: seed, kind: kind, ruleset: rs, fmt: fmt, size: size, race: race, str: str, field: field, f: f,
                    res: Array(repeating: nil, count: n), sim: Array(repeating: false, count: n), ff: Array(repeating: false, count: n))
    t.settle()
    return t
  }
  /* tReport: the player's match m, mine and theirs, oriented onto the bracket's sides */
  public mutating func report(_ m: Int, _ mineScore: Int, _ theirs: Int, forfeit: Bool) {
    let o = CareerLib.outcome(ctx(), m)
    res[m] = o.a == 0 ? [mineScore, theirs] : [theirs, mineScore]
    ff[m] = forfeit; live = nil
    settle()
  }
  /* tRound: the career's round name, a double elimination's winners side named as such */
  public func round(_ m: Int) -> String {
    let T = bracket, x = T.M[m], n = CareerLib.roundName(fmt, T, m)
    return x.br == "U" ? "Winners bracket, \(n.prefix(1).lowercased() + n.dropFirst())" : n
  }
  public func foe(_ m: Int) -> Entrant { let o = CareerLib.outcome(ctx(), m); return field[o.a == 0 ? o.b! : o.a!] }
  public var place: Int? { places.map { p in (p.first { $0[0] == 0 } ?? [0, size])[1] } }
}
