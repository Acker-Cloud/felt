/* 6b2's and 6b3's words for VoiceOver (issue #4): a seat read as a group (seatWords: "Player 1, stripes, 2 of 5
   racks, shooting, next: the 12, stripe"), the turn spoken once (railSayTurn: "Your turn, solids", "Player 2's turn,
   on the 3"), the potted windows (#potSay: "Potted: 1, 3, 9") and the status line's own turn words left unspoken
   while the turn is (say: railWillSay). Names come from the caller (nameOf), the rest from the game. */
public enum SeatWords {
  public static func lcFirst(_ t: String) -> String { t.isEmpty ? t : t.prefix(1).lowercased() + t.dropFirst() }
  /* nextWords: the ball to play, "Next: the 12, stripe" */
  public static func nextWords(_ n: Int?) -> String {
    guard let n else { return "" }
    return "Next: the \(n)" + (n >= 1 && n <= 7 ? ", solid" : n >= 9 && n <= 15 ? ", stripe" : "")
  }
  public static func ptsWord(_ n: Int) -> String { "\(n) point\(n == 1 ? "" : "s")" }
  /* snooker's onWords: the ball on */
  public static func onWords(_ g: Game) -> String {
    let S = g.snk!
    if let f = S.free { return "the free \(snkName(f))" }
    switch S.on { case .red: return "a red"; case .colour: return "a colour"; case .ball(let b): return "the \(snkName(b))"; case .none: return "nothing" }
  }
  /* bumper pool's card line (cardOf): "Red, 3 left, marked first" */
  public static func bumperMeta(_ g: Game, _ p: Int) -> String {
    let mine = g.balls.filter { $0.on && $0.n > 0 && bOwner($0.n) == p }.map { $0.n }
    return "\(p != 0 ? "White" : "Red"), \(mine.count) left" + (mine.contains(B_MARK[p]) && mine.count > 1 ? ", marked first" : "")
  }
  /* onTwo: a third foul in a row loses (9, 10 and 14.1 under the three-foul rule) */
  public static func onTwo(_ g: Game, _ p: Int) -> Bool {
    ["9", "10", "straight"].contains(g.kind) && g.rules.threeFoul != nil && g.winner == nil && g.fouls[p] >= 2
  }
  /* seatSum: what player p is on and their score; tally a match's racks won and its race (rackTally) */
  public static func sum(_ g: Game, _ p: Int, tally: (Int, Int)? = nil) -> [String] {
    let k = g.kind, up = p == g.turn && g.winner == nil, on = g.balls.filter { $0.on && $0.n > 0 }.map { $0.n }.sorted()
    var w: [String] = []
    if is8(k) {
      let gr = g.groups[p]
      w.append(gr == nil ? "open table" : on.contains { ($0 < 8 ? "solids" : $0 > 8 ? "stripes" : nil) == gr } ? gr! : "on the 8")
    } else if k == "bumper" { w.append(lcFirst(bumperMeta(g, p))) }
    else if k == "carom" { w.append(p != 0 ? "yellow" : "white") }
    if ["9", "10", "rotation"].contains(k) && up, let f = on.first { w.append("on the \(f)") }
    if ["straight", "rotation", "carom"].contains(k) { w.append("\(g.score![p]) of \(g.race!) points") }
    if k == "snooker" {
      w.append(ptsWord(g.score![p]))
      if up { w.append("on \(onWords(g))") }
      if up && g.snk!.brk > 0 { w.append("break \(g.snk!.brk)") }
    }
    if let t = tally { w.append("\(t.0) of \(t.1) racks") }
    if onTwo(g, p) { w.append("two fouls") }
    return w
  }
  /* seatWords: the player, their sum, "shooting" on the shooter's, then the ball to play */
  public static func seat(_ g: Game, _ p: Int, name: String, next: Int?, tally: (Int, Int)? = nil) -> String {
    var w = [name] + sum(g, p, tally: tally)
    if p == g.turn && g.winner == nil { w.append("shooting") }
    if let n = next, !w.contains("on the \(n)") { w.append(lcFirst(nextWords(n))) }
    return w.joined(separator: ", ")
  }
  /* railSayTurn's words: who (cpuMode: "Your turn" or "CPU's turn", else "Player 2's turn") and their sum */
  public static func turn(_ g: Game, _ p: Int, who: String, tally: (Int, Int)? = nil) -> String {
    ([who] + sum(g, p, tally: tally)).joined(separator: ", ")
  }
  /* #potSay: the balls down, in pot order */
  public static func potted(_ order: [Int]) -> String { order.isEmpty ? "" : "Potted: " + order.map(String.init).joined(separator: ", ") }
  /* say(): the status line as VoiceOver hears it while the turn will be spoken: the turn's words (turnOf, "Player 2 to
     shoot") and what runs on from them to the sentence's end (snooker's ", on the reds.") left out */
  public static func unspoken(_ t: String, turn ph: String) -> String {
    guard !ph.isEmpty, let r = t.range(of: ph) else { return t }
    let rest = t[r.upperBound...]
    var j = rest.startIndex
    if rest.hasPrefix(", "), let dot = rest.firstIndex(of: ".") { j = rest.index(after: dot) }
    else if let c = rest.first, c == "." || c == ":" { j = rest.index(after: j) }
    while j < rest.endIndex, rest[j].isWhitespace { j = rest.index(after: j) }
    return String(t[..<r.lowerBound]) + String(rest[j...])
  }
  /* chipCount: a seat per player in a party of three or four (in turn order, seat i player i) playing a game; else two */
  public static func seats(party n: Int?, mode: String?) -> Int { (n ?? 2) > 2 && mode == nil ? n! : 2 }
}

/* 6b2's placeRail for a party of three or four (chipCount > 2): the seats packed in order along the bottom rail's gaps
   (pack), and with too many for it the first ones there and the rest along the far rail's (top-down only). Units:
   screen px (the page's CSS px), RAIL_GAP between items. */
public enum RailRow {
  public static let GAP = 6.0
  /* pack: items ws wide laid in order into the gaps gs ([a, b], left to right), a gap each run (never back to an earlier
     gap), each run centred in its gap; of every way that fits, the one scored least by how far their middle is from the
     rail's (mid), how many gaps they take (12 a gap) and how far apart they spread (a quarter); the first found on a tie.
     Their centres, or nil */
  public static func pack(_ ws: [Double], _ gs: [[Double]], mid: Double, gap: Double = GAP) -> [Double]? {
    if ws.isEmpty { return [] }
    var best: (pos: [Double], score: Double)? = nil
    var idx = [Int](repeating: 0, count: ws.count)
    func walk(_ i: Int, _ g0: Int) {
      if i == ws.count {
        /* the runs in first-seen order (the page's Map), each gap's items */
        var order: [Int] = [], runs: [Int: [Int]] = [:]
        for (j, g) in idx.enumerated() { if runs[g] == nil { order.append(g); runs[g] = [] }; runs[g]!.append(j) }
        var pos = [Double](repeating: 0, count: ws.count)
        for g in order {
          let r = runs[g]!, len = r.reduce(0.0) { $0 + ws[$1] } + gap * Double(r.count - 1)
          if len > gs[g][1] - gs[g][0] { return }
          var x = (gs[g][0] + gs[g][1]) / 2 - len / 2
          for j in r { pos[j] = x + ws[j] / 2; x += ws[j] + gap }
        }
        let score = abs(pos.reduce(0, +) / Double(pos.count) - mid) + 12 * Double(order.count) + 0.25 * (pos.max()! - pos.min()!)
        if best == nil || score < best!.score { best = (pos, score) }
        return
      }
      var g = g0
      while g < gs.count { idx[i] = g; walk(i + 1, g); g += 1 }
    }
    walk(0, 0)
    return best?.pos
  }
  /* group() for the party's seats: all on the bottom rail (near) if they pack, else the first n there and the rest on
     the far rail (far: top-down's; nil in 3D), n from the most down to 1. Each seat's centre and whether on the far rail */
  public static func party(_ ws: [Double], near: [[Double]], far: [[Double]]?, mid: Double) -> [(x: Double, far: Bool)]? {
    if let pos = pack(ws, near, mid: mid) { return pos.map { ($0, false) } }
    guard let far else { return nil }
    var n = ws.count - 1
    while n >= 1 {
      if let a = pack(Array(ws[0..<n]), near, mid: mid), let b = pack(Array(ws[n...]), far, mid: mid) { return a.map { ($0, false) } + b.map { ($0, true) } }
      n -= 1
    }
    return nil
  }
  /* placeRail's free and fitIn: the spans of gap g left after what is placed (used, [x0, x1]), and a pill w wide in it as
     near its middle as they allow */
  public static func free(_ g: [Double], _ used: [[Double]], gap: Double = GAP) -> [[Double]] {
    used.reduce([g]) { f, u in f.flatMap { [[$0[0], Swift.min($0[1], u[0] - gap)], [Swift.max($0[0], u[1] + gap), $0[1]]] }.filter { $0[1] - $0[0] > 1 } }
  }
  public static func fitIn(_ g: [Double], _ w: Double, _ used: [[Double]]) -> Double? {
    let c = (g[0] + g[1]) / 2
    var best: Double? = nil
    for f in free(g, used) where f[1] - f[0] >= w { let x = Swift.min(Swift.max(c, f[0] + w / 2), f[1] - w / 2); if best == nil || abs(x - c) < abs(best! - c) { best = x } }
    return best
  }
  /* placeRail's side(): a control in the first gap with room (from the right for the replay's, from the left for the
     switch) for its whole 44 px target, else for its pill (pw wide), as near the gap's middle as the room allows; taken
     from the room left (used). nil: no room */
  public static func side(_ gs: [[Double]], _ pw: Double, right: Bool, _ used: inout [[Double]]) -> Double? {
    for g in right ? gs.reversed() : gs {
      for w in pw < 44 ? [44, pw] : [pw] { if let x = fitIn(g, w, used) { used.append([x - w / 2, x + w / 2]); return x } }
    }
    return nil
  }
  /* the replay's items on the rail (#replayBtn, the offer; while one plays #replaySkip, then #replayBadge): each its pill's
     width (wOf: the glyph, 2 px padding either side and 1), the badge's bare its width with .bare (its words, Slow motion,
     dropped) */
  public struct Rpl: Equatable {
    public let w: Double, bare: Double, badge: Bool
    public init(w: Double, bare: Double? = nil, badge: Bool = false) { self.w = w; self.bare = bare ?? w; self.badge = badge }
  }
  /* STEPS as they touch the replay and the switch: [bare, badge kept, switch kept], cheapest first */
  public static let STEPS: [(bare: Bool, badge: Bool, sw: Bool)] = [(false, true, true), (true, true, true), (true, false, true), (true, false, false)]
  /* placeRail after group(): the replay's items on the right (side(el, wOf, true)), then the 3D switch on the left (pw its
     pill's width, nil when not shown), over STEPS until all fit (the last step stands whatever fits). Each one's centre
     (nil: given way), and whether the replay went bare */
  public static func ends(_ gs: [[Double]], used u0: [[Double]], rpl: [Rpl], pw: Double?) -> (rpl: [Double?], sw: Double?, bare: Bool) {
    var last: (rpl: [Double?], sw: Double?, bare: Bool) = ([], nil, false)
    for (i, st) in STEPS.enumerated() {
      var used = u0, ok = true, xs: [Double?] = []
      for r in rpl {
        if r.badge && !st.badge { xs.append(nil); continue }
        let x = side(gs, st.bare ? r.bare : r.w, right: true, &used)
        ok = ok && x != nil; xs.append(x)
      }
      var sx: Double? = nil
      if let pw, st.sw { sx = side(gs, pw, right: false, &used); ok = ok && sx != nil }
      last = (xs, sx, st.bare)
      if ok || i == STEPS.count - 1 { break }
    }
    return last
  }
  /* placeRail's STEPS whole, cheapest first: the seats set closer (tight: Caption 2, the race left to the pause menu), the
     replay bare, the badge kept, the scoreboard cut to (its parts with data-p from this up dropped; under 4 it is set
     closer too), the switch kept, the scoreboard kept */
  public static let ALL_STEPS: [(tight: Bool, bare: Bool, badge: Bool, cut: Int, sw: Bool, snk: Bool)] = [
    (false, false, true, 4, true, true), (true, false, true, 4, true, true), (true, true, true, 4, true, true), (true, true, false, 4, true, true),
    (true, true, false, 3, true, true), (true, true, false, 2, true, true), (true, true, false, 1, true, true), (true, true, false, 1, false, true),
    (true, true, false, 1, false, false)]
  /* a seat's width (wOf: its offsetWidth and 1) as laid out and with #turnChip.tight */
  public struct Chip: Equatable {
    public let w: Double, tight: Double
    public init(w: Double, tight: Double? = nil) { self.w = w; self.tight = tight ?? w }
  }
  /* the row as placeRail leaves it: each seat's centre and whether on the far rail (nil: not placed), the scoreboard's
     centre (nil: given way or not shown), the replay's items' and the switch's, the step it stood at (its index in
     ALL_STEPS; 99 the score keeper alone), and that step's tight, bare and cut */
  public struct Row {
    public var seats: [(x: Double, far: Bool)?] = [], snk: Double? = nil, rpl: [Double?] = [], sw: Double? = nil
    public var level = 0, tight = false, bare = false, cut = 4
  }
  /* placeRail's seat(): a seat w wide in the gap nearest the rail's middle on its left (player 1) or its right (player 2);
     a gap across the middle gives each its half, the two meeting at the middle */
  static func seat(_ segs: [[Double]], _ w: Double, left: Bool, mid: Double, _ used: inout [[Double]]) -> Double? {
    var best: (x: Double, d: Double)? = nil
    for g in segs { for f in free(g, used) {
      let a = left ? f[0] : Swift.max(f[0], mid + GAP / 2), b = left ? Swift.min(f[1], mid - GAP / 2) : f[1]
      if b - a < w { continue }
      let across = g[0] < mid && g[1] > mid, c = (g[0] + g[1]) / 2
      let x = across ? (left ? b - w / 2 : a + w / 2) : Swift.max(a + w / 2, Swift.min(b - w / 2, c)), d = abs(x - mid)
      if best == nil || d < best!.d { best = (x, d) }
    } }
    guard let b = best else { return nil }
    used.append([b.x - w / 2, b.x + w / 2])
    return b.x
  }
  /* placeRail's group(): two seats by seat() and the scoreboard (sw: its width, nil when not shown) beside the player to
     shoot (turn: their seat); else, or two that do not both fit, the seats and the scoreboard packed in order (pack),
     the seats alone too many for the bottom rail carrying on along the far rail's gaps (top; nil in 3D) */
  static func group(_ segs: [[Double]], top: [[Double]]?, mid: Double, ws: [Double], snk sw: Double?, turn: Int, _ used: inout [[Double]], _ row: inout Row) -> Bool {
    row.seats = ws.map { _ in nil }; row.snk = nil
    let items = ws + (sw.map { [$0] } ?? [])
    if ws.count == 2 {
      if let a = seat(segs, ws[0], left: true, mid: mid, &used), let b = seat(segs, ws[1], left: false, mid: mid, &used) {
        row.seats = [(a, false), (b, false)]
        guard let w2 = sw else { return true }
        let sx = turn == 1 ? b : a
        var best: Double? = nil
        for g in segs { for f in free(g, used) where f[1] - f[0] >= w2 {
          let x = Swift.max(f[0] + w2 / 2, Swift.min(f[1] - w2 / 2, sx)); if best == nil || abs(x - sx) < abs(best! - sx) { best = x }
        } }
        guard let x = best else { return false }
        used.append([x - w2 / 2, x + w2 / 2]); row.snk = x
        return true
      }
      used = []
    }
    var pos = pack(items, segs, mid: mid)
    var far: [(Int, Double)] = []
    if pos == nil, let top {
      var n = ws.count - 1
      while pos == nil && n >= 1 {
        if let a = pack(Array(items[0..<n]), segs, mid: mid), let b = pack(Array(items[n..<ws.count]), top, mid: mid), items.count == ws.count {
          pos = a; far = b.enumerated().map { (n + $0.offset, $0.element) }
        }
        n -= 1
      }
    }
    guard let pos else { return false }
    for (i, x) in pos.enumerated() {
      used.append([x - items[i] / 2, x + items[i] / 2])
      if i < ws.count { row.seats[i] = (x, false) } else { row.snk = x }
    }
    for (i, x) in far { row.seats[i] = (x, true) }
    return true
  }
  /* placeRail whole: over ALL_STEPS until everything fits (the last stands whatever fits) group() (the seats, chips; the
     scoreboard, snk: its width at each cut, 4 to 1, or nil), then the replay's items on the right and the 3D switch on
     the left (side()). A seat still not placed: the score keeper never gives way, so with everything else hidden it keeps
     off the pockets alone (pockets: the bottom rail's gaps between them; in 3D, live, the row's own gaps) */
  public static func place(_ segs: [[Double]], top: [[Double]]?, pockets: [[Double]], live: Bool = false, mid: Double, chips: [Chip], turn: Int = 0,
                           snk: [Double]? = nil, rpl: [Rpl] = [], pw: Double?) -> Row {
    var row = Row()
    for (lv, st) in ALL_STEPS.enumerated() {
      var used: [[Double]] = []
      row = Row(); row.level = lv; row.tight = st.tight; row.bare = st.bare && !rpl.isEmpty; row.cut = st.cut
      var ok = group(segs, top: top, mid: mid, ws: chips.map { st.tight ? $0.tight : $0.w }, snk: st.snk ? snk.map { $0[4 - st.cut] } : nil, turn: turn, &used, &row)
      for r in rpl {
        if r.badge && !st.badge { row.rpl.append(nil); continue }
        let x = side(segs, st.bare ? r.bare : r.w, right: true, &used)
        ok = x != nil && ok; row.rpl.append(x)
      }
      if let pw { if st.sw { row.sw = side(segs, pw, right: false, &used); ok = row.sw != nil && ok } }
      if ok || lv == ALL_STEPS.count - 1 { break }
    }
    if row.seats.contains(where: { $0 == nil }) {
      var used: [[Double]] = []
      row.rpl = rpl.map { _ in nil }; row.sw = nil; row.snk = nil
      _ = group(live ? segs : pockets, top: top, mid: mid, ws: chips.map(\.tight), snk: nil, turn: turn, &used, &row)
      row.level = 99
    }
    return row
  }
  /* placeRail's row for a party (.many) whose seats are as wide set closer: place() with no scoreboard; the seats packed
     nowhere at all: nil */
  public static func many(_ ws: [Double], near: [[Double]], far: [[Double]]?, pockets: [[Double]], mid: Double, pw: Double?, rpl: [Rpl] = []) -> (seats: [(x: Double, far: Bool)]?, sw: Double?, rpl: [Double?], bare: Bool) {
    let r = place(near, top: far, pockets: pockets, mid: mid, chips: ws.map { Chip(w: $0) }, rpl: rpl, pw: pw)
    let seats = r.seats.contains { $0 == nil } ? nil : r.seats.map { $0! }
    return (seats, r.sw, r.rpl, r.bare)
  }
}

/* .pchip.busy (6b2, hudChip): the CPU's seat while it thinks (state thinking, no plan yet) pulses: chipPulse 1.1s
   ease-in-out infinite, its one keyframe opacity .6 at 50%, the seat's own (lit: 1) at either end. CSS eases each
   keyframe interval on its own: ease-in-out is cubic-bezier(.42, 0, .58, 1), solved for x as Blink's gfx::CubicBezier
   does (Newton, then bisection). Reduce Motion: still. t: seconds since the pulse began */
public enum RailPulse {
  public static let PERIOD = 1.1, LOW = 0.6
  /* cubic-bezier(x1, y1, x2, y2) at progress x */
  public static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
    func sx(_ s: Double) -> Double { ((ax * s + bx) * s + cx) * s }
    func dx(_ s: Double) -> Double { (3 * ax * s + 2 * bx) * s + cx }
    var s = x, found = false
    for _ in 0..<8 {
      let e = sx(s) - x
      if abs(e) < 1e-7 { found = true; break }
      let d = dx(s)
      if abs(d) < 1e-7 { break }
      s -= e / d
    }
    if !found {
      var lo = 0.0, hi = 1.0
      s = x
      while lo < hi {
        let v = sx(s)
        if abs(v - x) < 1e-7 { break }
        if x > v { lo = s } else { hi = s }
        s = (hi - lo) * 0.5 + lo
        if hi - lo < 1e-12 { break }
      }
    }
    return ((ay * s + by) * s + cy) * s
  }
  public static func easeInOut(_ x: Double) -> Double { bezier(x, 0.42, 0, 0.58, 1) }
  /* rplIn (.rpl, 5r): a replay item comes in over 0.2s ease-out (cubic-bezier(0, 0, .58, 1)) from opacity 0 and scale .94
     about its middle, from when it is shown (its hidden attribute dropped). Reduce Motion: none. t: seconds since then */
  public static let RPL_IN = 0.2
  public static func rplIn(_ t: Double, reduce: Bool = false) -> (opacity: Double, scale: Double) {
    if reduce || t >= RPL_IN { return (1, 1) }
    let p = bezier(Swift.max(0, t) / RPL_IN, 0, 0, 0.58, 1)
    return (p, 0.94 + 0.06 * p)
  }
  /* the seat's opacity t seconds into the pulse (base: the seat's own, 1 when lit) */
  public static func opacity(_ t: Double, base: Double = 1, reduce: Bool = false) -> Double {
    if reduce || t < 0 { return base }
    let p = t.truncatingRemainder(dividingBy: PERIOD) / PERIOD
    return p < 0.5 ? base + (LOW - base) * easeInOut(p / 0.5) : LOW + (base - LOW) * easeInOut((p - 0.5) / 0.5)
  }
}
