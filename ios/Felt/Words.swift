/* the page's words for a pocket game (index.html 5 and 6): nameOf, turnOf, isOf, handWords, callWords,
   OPT_WORDS and overLine, two players on one device. */
import FeltSim

@MainActor
enum Words {
  /* against the CPU the page says "You" and "CPU" (nameOf, turnOf, isOf, handWords) */
  static var cpuMode = false
  static func nameOf(_ p: Int) -> String { cpuMode ? (p == 0 ? "You" : "CPU") : "Player \(p + 1)" }
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
  ]
  static func optLabel(_ kind: String, _ choice: String) -> String { OPT[kind]?[choice] ?? choice }

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
