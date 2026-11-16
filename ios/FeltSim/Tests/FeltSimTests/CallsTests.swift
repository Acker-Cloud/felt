/* Settings > Gameplay > Called Shots (index.html 6, loadSettings; sim 1e makeCall, callScope, callNeed, callResult; 5c
   callName, callWarn, hudCallHist): the stored configuration checked as the page checks it, and each control's effect on
   what a shot must name and how its call is judged */
import Foundation
import Testing
@testable import FeltSim

@Suite struct CallsTests {
  let E = RulesEngine(sim: Sim())
  func game(_ kind: String, _ ruleset: String? = nil, _ f: (inout CallConfig) -> Void = { _ in }) -> Game {
    var c = CallConfig(); f(&c)
    var g = E.newGame(kind, rules: makeRules(kind, ruleset: ruleset, call: c)); g.breakShot = false
    return g
  }

  @Test func defaults() {
    let c = makeCall(nil), u = makeCallUI(nil)
    #expect(c.mode == "official" && c.detail == "pocket" && c.safety && !c.eight && c.obvious && c.change)
    #expect(u.highlight && u.confirm && u.sound && u.warn && u.history)
    #expect(makeCall([:]) == CallConfig() && makeCallUI([:]) == CallUI())
    #expect(CALL_KEYS == ["mode", "detail", "safety", "eight", "obvious", "change", "highlight", "confirm", "sound", "warn", "history"])
  }
  @Test func validation() {
    for m in CALL_MODES { #expect(makeCall(["mode": m]).mode == m) }
    for d in CALL_DETAILS { #expect(makeCall(["detail": d]).detail == d) }
    let bad: [String: Any] = ["mode": "sometimes", "detail": 3, "safety": "no", "eight": "yes", "obvious": 0.5, "change": NSNull(), "highlight": "off", "confirm": [false], "sound": "", "warn": 2.5, "history": "false"]
    #expect(makeCall(bad) == CallConfig() && makeCallUI(bad) == CallUI())
    #expect(Set(callsInvalid(bad)) == Set(CALL_KEYS))
    let good: [String: Any] = ["mode": "career", "detail": "strict", "safety": false, "eight": true, "obvious": false, "change": false, "highlight": false, "confirm": false, "sound": false, "warn": false, "history": false]
    let c = makeCall(good), u = makeCallUI(good)
    #expect(c.mode == "career" && c.detail == "strict" && !c.safety && c.eight && !c.obvious && !c.change)
    #expect(!u.highlight && !u.confirm && !u.sound && !u.warn && !u.history)
    #expect(callsInvalid(good).isEmpty && callsInvalid([:]).isEmpty)
    /* the legacy iOS value ("official" at felt.settings.calls) is a mode the page knows */
    #expect(callsInvalid(["mode": "all", "unknown": 1]).isEmpty)
  }

  /* Call: who must call (callScope) */
  @Test func mode() {
    #expect(E.callNeed(game("8")) == nil, "house 8-ball under the official rules calls nothing")
    #expect(E.callNeed(game("8", "8-wpa")) != nil, "WPA 8-ball calls every shot")
    #expect(E.callNeed(game("8", "8-wpa") { $0.mode = "off" }) == nil)
    #expect(E.callScope(game("8") { $0.mode = "eight" }) == "all", "8-Ball Only: an 8-ball game calls")
    #expect(E.callScope(game("10") { $0.mode = "eight" }) == "none")
    #expect(E.callScope(game("9") { $0.mode = "all" }) == "all")
    #expect(E.callScope(game("10") { $0.mode = "career" }) == E.callScope(game("10")), "Career Rules outside an event: the official rules")
    #expect(E.callScope(game("9") { $0.mode = "career" }) == "none")
    #expect(E.callScope(game("heyball") { $0.mode = "official" }) == "none" && E.callScope(game("heyball") { $0.mode = "all" }) == "all")
  }
  /* Require Called 8 Pocket: the 8 alone is called, once it is the ball to hit */
  @Test func eight() {
    var g = game("8") { $0.eight = true }
    #expect(E.callScope(g) == "game" && E.callNeed(g) == nil, "an open table: the 8 is not on")
    g.open = false; g.groups = ["solids", "stripes"]
    for i in g.balls.indices where (1...7).contains(g.balls[i].n) { g.balls[i].on = false }
    #expect(E.legalTargets(g) == [8] && E.callNeed(g) != nil)
    #expect(E.callScope(game("8")) == "none")
  }
  /* Declaration and the switches: what the call must name */
  @Test func need() throws {
    let all = { (f: (inout CallConfig) -> Void) in self.game("9") { $0.mode = "all"; f(&$0) } }
    let p = try #require(E.callNeed(all { _ in }))
    #expect(p.pocket && !p.flags && !p.strict && p.auto && p.safety && p.change)
    #expect(E.callNeed(all { $0.detail = "ball" })?.pocket == false)
    let r = try #require(E.callNeed(all { $0.detail = "rails" })), s = try #require(E.callNeed(all { $0.detail = "strict" }))
    #expect(r.pocket && r.flags && !r.strict && s.pocket && s.flags && s.strict)
    #expect(E.callNeed(all { $0.obvious = false })?.auto == false, "Auto-Call Obvious Shots off")
    #expect(E.callNeed(all { $0.safety = false })?.safety == false)
    #expect(E.callNeed(all { $0.change = false })?.change == false)
  }
  /* the call judged under each declaration */
  @Test func result() throws {
    func shot(_ g: Game, potted: [Int], at: [Int: Int], first: Int, rails: [Int: Int] = [:]) -> RuleShot {
      RuleShot(balls: g.balls, first: first, railAfter: true, crossed: nil, potted: potted, pocketOf: at, rails: rails, kick: 0)
    }
    var c = ShotCall(); c.ball = 1; c.pocket = 0
    var g = game("9") { $0.mode = "all"; $0.detail = "ball" }; g.call = c
    #expect(E.callResult(g, shot(g, potted: [1], at: [1: 3], first: 1), E.callNeed(g)).made == true, "Ball Only: any pocket")
    g = game("9") { $0.mode = "all" }; g.call = c
    #expect(E.callResult(g, shot(g, potted: [1], at: [1: 3], first: 1), E.callNeed(g)).made == false, "Ball and Pocket: the called pocket")
    #expect(E.callResult(g, shot(g, potted: [1, 4], at: [1: 0, 4: 2], first: 1), E.callNeed(g)).made == true)
    g = game("9") { $0.mode = "all"; $0.detail = "strict" }; g.call = c
    let st = E.callResult(g, shot(g, potted: [1, 4], at: [1: 0, 4: 2], first: 1), E.callNeed(g))
    #expect(st.made == false && st.why == "the 4 dropped too", "Strict: no other ball")
    g = game("9") { $0.mode = "all"; $0.detail = "rails" }; g.call = c
    let bk = E.callResult(g, shot(g, potted: [1], at: [1: 0], first: 1, rails: [1: 1]), E.callNeed(g))
    #expect(bk.made == false && bk.why == "an uncalled bank")
    g.call!.bank = true
    #expect(E.callResult(g, shot(g, potted: [1], at: [1: 0], first: 1, rails: [1: 1]), E.callNeed(g)).made == true)
    /* no call: a declared safety unless safeties must be declared, then a missed call */
    g = game("9") { $0.mode = "all" }; g.call = ShotCall()
    let miss = E.callResult(g, shot(g, potted: [], at: [:], first: 1), E.callNeed(g))
    #expect(!miss.safety && miss.missing == true && miss.why == "no call")
    g = game("9") { $0.mode = "all"; $0.safety = false }; g.call = ShotCall()
    #expect(E.callResult(g, shot(g, potted: [], at: [:], first: 1), E.callNeed(g)).safety)
  }

  /* Invalid-Shot Warnings */
  @Test func warn() {
    var c = ShotCall(); c.ball = 5
    let nine = game("9")
    #expect(E.callWarn(nine, c, on: true) == "The 5 is not on: hit the 1 first")
    #expect(E.callWarn(nine, c, on: false) == "")
    c.combo = true
    #expect(E.callWarn(nine, c, on: true) == "", "a combination off the ball on")
    c.combo = false; c.ball = 1
    #expect(E.callWarn(nine, c, on: true) == "")
    var g8 = game("8"); g8.open = false; g8.groups = ["solids", "stripes"]
    c.ball = 12
    #expect(E.callWarn(g8, c, on: true) == "The 12 is not yours to hit first")
    #expect(E.callWarn(game("straight"), c, on: true) == "")
    #expect(E.callWarn(nine, nil, on: true) == "" && E.callWarn(nine, ShotCall(), on: true) == "")
  }
  /* Show Declaration Confirmation's words, and Declaration History's */
  @Test func words() {
    let w = { (k: Int) in ["top left corner", "left side", "bottom left corner"][k % 3] }
    var c = ShotCall()
    #expect(callName(c, words: w) == "Call your shot")
    c.ball = 3
    #expect(callName(c, words: w) == "Calling the 3")
    c.pocket = 1
    #expect(callName(c, words: w) == "Calling: 3 in left side")
    c.safety = true
    #expect(callName(c, words: w) == "Safety")
    c.push = true
    #expect(callName(c, words: w) == "Push out")
    #expect(callHistWords([], cpu: false, words: w) == nil)
    let h = [CallRec(p: 0, ball: 1, pocket: 0, safety: false, push: false, made: true, auto: false),
             CallRec(p: 1, ball: nil, pocket: nil, safety: false, push: true, made: false, auto: false),
             CallRec(p: 0, ball: 2, pocket: 2, safety: false, push: false, made: false, auto: true),
             CallRec(p: 1, ball: nil, pocket: nil, safety: true, push: false, made: false, auto: false),
             CallRec(p: 0, ball: 3, pocket: nil, safety: false, push: false, made: true, auto: false)]
    #expect(callHistWords(h, cpu: false, words: w) == "Calls: 2 of 3 made. Last: 3, made; safety; 2 in bottom left corner, missed; push out.")
    #expect(callHistWords(Array(h.prefix(2)), cpu: true, words: w) == "Calls: 1 of 1 made. Last: push out (CPU); 1 in top left corner, made (you).")
  }
}
