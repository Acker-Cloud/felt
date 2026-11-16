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
  /* placeRail's row for a party (.many): the seats by group() (party), then the 3D switch (side(viewBtn, pw, false): pw
     its glyph's width, nil when not shown) in the first gap from the left with room for its whole 44 px target, else for
     its glyph, clear of the bottom rail's seats; no room: the switch gives way (STEPS' sw 0). The seats packed nowhere:
     the score keeper keeps off the pockets alone (pockets: the bottom rail's gaps between them) and the switch gives way */
  public static func many(_ ws: [Double], near: [[Double]], far: [[Double]]?, pockets: [[Double]], mid: Double, pw: Double?) -> (seats: [(x: Double, far: Bool)]?, sw: Double?) {
    guard let pos = party(ws, near: near, far: far, mid: mid) else { return (party(ws, near: pockets, far: far, mid: mid), nil) }
    var used: [[Double]] = []
    for (i, q) in pos.enumerated() where !q.far { used.append([q.x - ws[i] / 2, q.x + ws[i] / 2]) }
    guard let pw else { return (pos, nil) }
    for g in near { for w in pw < 44 ? [44, pw] : [pw] { if let x = fitIn(g, w, used) { return (pos, x) } } }
    return (pos, nil)
  }
}
