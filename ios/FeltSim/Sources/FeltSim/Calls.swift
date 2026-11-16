/* index.html 5c and 6's called-shot settings, DOM-free: the page's own switches beside the rules' (CALL_UI: highlight,
   confirm, sound, warn, history, each on by default), loadSettings' check of a stored settings.calls (a field of the
   wrong type or an unknown mode or detail is dropped, its default taken), callName (the call in words), callWarn (the
   invalid-shot warning) and hudCallHist (the pause menu's declaration history). The caller gives a pocket's words
   (pocketWords: they follow the view). */
import Foundation

public struct CallUI: Sendable, Equatable {
  public var highlight = true, confirm = true, sound = true, warn = true, history = true
  public init() {}
}
public var CALL_UI_SWITCHES: [(String, WritableKeyPath<CallUI, Bool>)] { [("highlight", \.highlight), ("confirm", \.confirm), ("sound", \.sound), ("warn", \.warn), ("history", \.history)] }
/* every field of a stored settings.calls: mode, detail, the rules' switches and the page's */
public let CALL_KEYS = ["mode", "detail"] + CALL_SWITCHES.map { $0.0 } + CALL_UI_SWITCHES.map { $0.0 }
public func makeCallUI(_ c: [String: Any]?) -> CallUI {
  var o = CallUI()
  guard let c else { return o }
  for (k, p) in CALL_UI_SWITCHES { if let b = c[k] as? Bool { o[keyPath: p] = b } }
  return o
}
/* the stored fields loadSettings does not take (an unknown mode or detail, a switch that is not a boolean) */
public func callsInvalid(_ c: [String: Any]) -> [String] {
  CALL_KEYS.filter { k in
    guard let v = c[k] else { return false }
    if k == "mode" { return !((v as? String).map { CALL_MODES.contains($0) } ?? false) }
    if k == "detail" { return !((v as? String).map { CALL_DETAILS.contains($0) } ?? false) }
    return !(v is Bool)
  }
}
/* callName: "Push out", "Safety", "Call your shot", "Calling the 3", "Calling: 3 in top left corner" */
public func callName(_ c: ShotCall, words: (Int) -> String) -> String {
  c.push ? "Push out" : c.safety ? "Safety" : c.ball == nil ? "Call your shot" : c.pocket == nil ? "Calling the \(c.ball!)" : "Calling: \(c.ball!) in \(words(c.pocket!))"
}
extension RulesEngine {
  /* callWarn: why the call cannot stand as it is (a ball that may not be hit first, unless called as a combination off
     the ball on), or "" (and "" with the warnings off) */
  public func callWarn(_ g: Game, _ c: ShotCall?, on: Bool) -> String {
    guard on, let c, let b = c.ball else { return "" }
    let t = legalTargets(g)
    if g.kind == "straight" || t.contains(b) || (c.combo && b != t.first) { return "" }
    return is8(g.kind) ? "The \(b) is not yours to hit first" : "The \(b) is not on: hit the \(t.first.map(String.init) ?? "") first"
  }
}
/* hudCallHist: the declarations made, how many of the called ones went in and the last four, newest first ("Calls: 2 of
   3 made. Last: 3 in top left corner, made; safety."); against the CPU each says whose. nil with none */
public func callHistWords(_ calls: [CallRec], cpu: Bool, words: (Int) -> String) -> String? {
  guard !calls.isEmpty else { return nil }
  let called = calls.filter { $0.ball != nil }, made = called.filter { $0.made == true }.count
  let last = calls.suffix(4).reversed().map { c -> String in
    let w = c.push ? "push out" : c.safety ? "safety" : "\(c.ball.map(String.init) ?? "no call")\(c.pocket != nil ? " in " + words(c.pocket!) : ""), \(c.made == true ? "made" : "missed")"
    return w + (cpu ? " (\(c.p != 0 ? "CPU" : "you"))" : "")
  }
  return "Calls: \(made) of \(called.count) made. Last: \(last.joined(separator: "; "))."
}
