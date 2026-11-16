/* the page's words for a pocket game (index.html 5 and 6): nameOf, turnOf, isOf, handWords, callWords,
   OPT_WORDS and overLine, two players on one device. */
import FeltSim

@MainActor
enum Words {
  /* against the CPU the page says "You" and "CPU" (nameOf, turnOf, isOf, handWords) */
  static var cpuMode = false
  /* an exhibition's players by name (exhib.names); else You and the CPU, or Player 1 and 2 */
  static var names: [String]? = nil
  static func nameOf(_ p: Int) -> String { names.map { $0[min(p, $0.count - 1)] } ?? (cpuMode ? (p == 0 ? "You" : "CPU") : "Player \(p + 1)") }
  static func turnOf(_ p: Int) -> String { cpuMode ? (p == 0 ? "Your turn" : "CPU to shoot") : "\(nameOf(p)) to shoot" }
  static func isOf(_ p: Int) -> String { "\(nameOf(p)) \(cpuMode && p == 0 ? "are" : "is")" }
  static func handWords(_ p: Int, kitchen: Bool) -> String {
    let w = kitchen ? " behind the head string" : ""
    return cpuMode ? "Ball in hand for \(p == 0 ? "you" : "the CPU")\(w)" : "\(nameOf(p)): ball in hand\(w)"
  }
  static let handHint = ["kitchen": "Ball in hand behind the line: drag the cue ball to move it, pull the bar to shoot."]
  static func hint(_ inHand: String?) -> String { handHint[inHand ?? ""] ?? "Ball in hand: drag the cue ball to move it, pull the bar to shoot." }

  static let OPT: [String: [String: String]] = [
    "push": ["head": "Push out", "sub": "Shoot it from here, or hand it back.", "take": "Shoot it", "pass": "Hand it back"],
    "uncalled": ["head": "A ball dropped on a missed call", "sub": "Shoot from here, or hand it back.", "take": "Shoot it", "pass": "Hand it back"],
    "badBreak": ["head": "Illegal break", "sub": "Take the table as it lies, or have the balls racked again.", "take": "Take the table", "rebreak": "They break again", "break": "Re-rack, I break"],
    "eightBreak": ["head": "The 8 on the break", "sub": "Spot it and carry on, or re-rack and break again.", "spot": "Spot the 8", "rerack": "Re-rack"],
    "breakFoul": ["head": "Foul on the break", "sub": "Take ball in hand behind the head string, or have the balls racked again.", "take": "Ball in hand", "rebreak": "They break again", "break": "Re-rack, I break"],
    "breakOff": ["head": "Ball off the table on the break", "sub": "Take the table as it lies, or ball in hand behind the head string.", "take": "Take the table", "kitchen": "Ball in hand"],
    "threeBall": ["head": "Three-ball rule", "sub": "Fewer than three balls dropped or stopped past the head string. Shoot from here, or hand it back.", "take": "Shoot it", "pass": "Hand it back"],
    "breakMiss": ["head": "No ball hit on the break", "sub": "The balls are racked again: break yourself, or they break again.", "rebreak": "They break again", "break": "I break"],
    "kitchenSpot": ["head": "Your balls are behind the head string", "sub": "Have the nearest spotted on the foot spot, or play it from here.", "spot": "Spot the nearest", "play": "Play it"],
    "snkFoul": ["head": "Foul", "sub": "Play from where the balls lie, or make them play again.", "play": "Play it", "again": "Make them play again from here"],
    "snkMiss": ["head": "Foul and a miss", "sub": "Play from here, or have the balls put back for them to play again.", "play": "Play it", "replace": "Put it back and they play again",
                "again": "Make them play again from here", "free": "Free ball: nominate"],
    "snkFree": ["head": "Free ball", "sub": "Snookered after a foul: nominate any colour as the ball on, or play on.", "play": "Play it", "again": "Make them play again from here", "free": "Free ball: nominate"],
    "respot": ["head": "Balls touching", "sub": "Your cue ball touches a ball. Play on, but not straight into it, or have the touching balls spotted.", "play": "Play it", "respot": "Spot them"],
    "snkBlack": ["head": "Re-spotted black", "sub": "Level on points. You won the draw: play the black from the D, or have them play it.", "play": "Play it", "pass": "They play it"],
  ]
  /* carom's (page 5): caromWhy and caromWords */
  static let NUMW = ["No", "One", "Two", "Three"]
  static func caromWhy(_ c: CaromCount) -> String {
    c.balls.isEmpty ? "No ball hit" : c.balls.count < 2 ? "Only one ball" : "\(c.cushions < NUMW.count ? NUMW[c.cushions] : String(c.cushions)) cushion\(c.cushions == 1 ? "" : "s") before the second ball"
  }
  static func carom(_ v: Verdict, _ g: Game, _ shooter: Int, _ who: Int) -> (msg: String, banner: (String, String, Double)) {
    if let f = v.foul { return ("Foul: \(f). \(turnOf(who)).", ("Foul: \(f)", turnOf(who), 1.5)) }
    let cv = v.carom!
    if cv.point {
      let sc = "\(g.score![shooter]) of \(g.race!)", run = (g.run ?? 0) > 1 ? ", a run of \(g.run!)" : ""
      return ("Point: \(sc)\(run). \(nameOf(shooter)) \(cpuMode && shooter == 0 ? "go" : "goes") again.",
              ("Point: \(sc)", "\(nameOf(shooter)) \(cpuMode && shooter == 0 ? "shoot" : "shoots") again\(run)", 0.9))
    }
    let why = caromWhy(cv.count)
    return ("\(why). \(turnOf(who)).", (turnOf(who), why, 1.1))
  }
  /* bumper pool's (page 5): bumperWords, a banner only where the page flashes one */
  static func colourOf(_ p: Int) -> String { p != 0 ? "White" : "Red" }
  static func bumper(_ v: Verdict, _ g: Game, _ shooter: Int, _ who: Int) -> (msg: String, banner: (String, String, Double)?) {
    let left = { (p: Int) in g.balls.filter { $0.on && bOwner($0.n) == p }.count }
    let tail = "\(colourOf(who).lowercased()), \(left(who)) left", bv = v.bumper!
    if let f = v.foul {
      let pen = bv.dropped != nil ? "\(nameOf(1 - shooter)) \(cpuMode && shooter == 1 ? "drop" : "drops") a ball in" : ""
      return ("Foul: \(f). \(pen.isEmpty ? "" : pen + ". ")\(turnOf(who)): \(tail).", ("Foul: \(f)", [pen, turnOf(who)].filter { !$0.isEmpty }.joined(separator: "\n"), 1.7))
    }
    if bv.opening == 1 { return ("\(turnOf(who)): the opening shot, the marked ball.", (turnOf(who), "Opening shot: the marked ball", 1.1)) }
    if who != shooter || bv.opening == 2 {
      return ("\(turnOf(who)): \(tail).", (turnOf(who), bv.opening == 2 ? "The opening is over" : "\(colourOf(who)), \(left(who)) left", 1.0))
    }
    return ("\(nameOf(who)) \(cpuMode && who == 0 ? "go" : "goes") again: \(left(who)) left.", nil)
  }
  /* snooker's (page 5k): onWords, ptsWord, dWords, frameHead */
  static func onWords(_ g: Game) -> String { SeatWords.onWords(g) }
  static func ptsWord(_ n: Int) -> String { SeatWords.ptsWord(n) }
  static func dWords(_ p: Int) -> String { cpuMode ? "Ball in hand in the D for \(p == 0 ? "you" : "the CPU")" : "\(nameOf(p)): ball in hand in the D" }
  static func frameHead(_ w: Int) -> String { cpuMode ? (w == 0 ? "You win the frame" : "The CPU wins the frame") : "\(nameOf(w)) wins the frame" }
  /* snookerWords: the banner and the status line after a shot at snooker */
  static func snooker(_ v: Verdict, _ g: Game, _ shooter: Int, _ who: Int, chose: (who: Int, kind: String, choice: String)? = nil) -> (msg: String, banner: (String, String, Double)?) {
    guard let sv = v.snk else { return ("", nil) }
    if let fo = sv.frameOver {
      let sc = fo.score, line = fo.forfeit != nil ? "Three misses" : fo.conceded ? "Conceded" : "\(max(sc[0], sc[1]))-\(min(sc[0], sc[1]))"
      let brk = cpuMode ? (who == 0 ? "You break" : "The CPU breaks") : "\(nameOf(who)) breaks"
      return ("\(frameHead(fo.winner)), \(line). Frames \(fo.won[0])-\(fo.won[1]). \(brk) frame \(g.snk!.frame).", (frameHead(fo.winner), "\(line), frames \(fo.won[0])-\(fo.won[1])\n\(brk) frame \(g.snk!.frame)", 2.6))
    }
    if sv.reblack { return ("Level at \(g.score![0]): the black is re-spotted. \(dWords(who)).", ("Re-spotted black", "Level at \(g.score![0])\n\(dWords(who))", 2.2)) }
    if let f = v.foul {
      let head = sv.miss == true ? "Foul and a miss" : "Foul: \(f)", warn = sv.warn == true ? "A third miss loses the frame" : ""
      let then = chose.map { "\(nameOf($0.who)): \(optLabel($0.kind, $0.choice))" } ?? ""
      let lines = ["\(ptsWord(sv.pen)) to \(nameOf(1 - shooter))", warn, then, g.inHand != nil ? dWords(who) : ""].filter { !$0.isEmpty }
      return ("\(head)\(sv.miss == true ? ": \(f)" : ""). \(ptsWord(sv.pen)) to \(nameOf(1 - shooter)). \(warn.isEmpty ? "" : warn + ". ")\(then.isEmpty ? "" : then + ". ")\(turnOf(who)), on \(onWords(g)).",
              (head, lines.joined(separator: "\n"), then.isEmpty && warn.isEmpty ? 1.7 : 2.4))
    }
    if who == shooter { return ("\(nameOf(who)): \(ptsWord(sv.pts)), break \(sv.brk). On \(onWords(g)).", nil) }
    return ("\(sv.ended > 0 ? "Break of \(sv.ended). " : "")\(turnOf(who)), on \(onWords(g)).", (turnOf(who), sv.ended > 0 ? "Break of \(sv.ended)" : "On \(onWords(g))", 1.0))
  }
  static func optLabel(_ kind: String, _ choice: String) -> String { choice.hasPrefix("free:") ? "Free ball: the \(snkName(Int(choice.dropFirst(5)) ?? 0))" : OPT[kind]?[choice] ?? choice }

  static func callWords(_ v: Verdict, _ kind: String, _ shooter: Int, chose: (who: Int, kind: String, choice: String)? = nil) -> String {
    var parts: [String] = []
    let c = v.call
    if c.push { parts.append("Push out") }
    else if c.need && v.foul == nil {
      if c.safety && c.missing != true { parts.append("Safety") }
      else if c.missing == true && c.safety { parts.append("No call: played as a safety") }
      else if c.made != true { parts.append("Missed call: \(c.why)") }
    }
    if v.illegalBreak && v.foul == nil { parts.append("Illegal break") }
    if v.scored != 0 && (kind == "straight" || kind == "rotation") { parts.append("\(v.scored > 0 ? "+" : "")\(v.scored) for \(nameOf(shooter))") }
    if v.threeFouls { parts.append("Three fouls: 15 more off") }
    if let r = v.rerack { parts.append(["stalemate": "Stalemate: the balls are racked again", "fourteen": "Fourteen down: re-rack", "fifteen": "All fifteen racked", "fouls": "Break a new rack"][r] ?? "") }
    if let ch = chose { parts.append("\(nameOf(ch.who)): \(optLabel(ch.kind, ch.choice).lowercased())") }
    return parts.joined(separator: ". ")
  }

  static func overLine(_ g: Game) -> String {
    guard let w = g.winner, let v = g.verdict, !v.why.isEmpty, v.why != "forced" else { return "Game over." }
    let l = 1 - w, why = v.why, who = { (p: Int) in cpuMode ? (p == 0 ? "You" : "The CPU") : nameOf(p) }
    if why.contains("all five") { return "\(who(w)) got all five \(cpuMode && w == 0 ? "of yours" : w != 0 ? "whites" : "reds") down\(v.foul != nil ? " (\(who(l)) fouled: \(v.foul!))" : "")." }
    if g.kind == "snooker", let S = g.snk {
      let fo = v.snk?.frameOver, sc = fo?.score ?? g.score!, won = S.won
      if fo?.conceded == true { return "\(who(l)) conceded\(S.frames > 1 ? ": \(won[w])-\(won[l]) in frames" : "")." }
      if fo?.forfeit != nil { return "\(who(l)) missed three times with a ball on in full view\(S.frames > 1 ? ": \(won[w])-\(won[l]) in frames" : "")." }
      return S.frames > 1 ? "\(who(w)) won the match \(won[w])-\(won[l]) in frames." : "\(who(w)) won the frame \(sc[w])-\(sc[l])."
    }
    func has(_ re: String) -> Bool { why.range(of: re, options: .regularExpression) != nil }
    if has("three fouls") { return "\(who(l)) fouled three times in a row." }
    if has("\\b8\\b") {
      if has("legal") { return "\(who(w)) potted the 8 to win." }
      if has("foul") { return v.scratch ? "\(who(l)) scratched while potting the 8." : "\(who(l)) potted the 8 on a foul\(v.foul.map { " (\($0))" } ?? "")." }
      if has("before|clear|early") { return "\(who(l)) potted the 8 before clearing \(cpuMode && l == 0 ? "your" : "their") group." }
      if has("uncalled") { return "\(who(l)) potted the 8 in a pocket not called." }
      if has("safety") { return "\(who(l)) potted the 8 on a safety." }
    }
    if has("\\b9\\b") { return "\(who(w)) potted the 9 to win." }
    if why == "the 10" { return "\(who(w)) potted the called 10 to win." }
    if has("points") { return "\(who(w)) reached \(why) first" + ((g.high?[w] ?? 0) > 1 ? ", with a best run of \(g.high![w])." : ".") }
    return "\(who(w)) won: \(why)."
  }
}
