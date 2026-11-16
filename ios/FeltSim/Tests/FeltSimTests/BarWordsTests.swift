/* the power bar's label and idle, and the fine wheel's dimming (hudControls), against the page's own words */
import Testing
@testable import FeltSim

@Suite struct BarWordsTests {
  func lab(_ st: BarWords.State, human: Bool = true, replay: Bool = false, live: Bool = false, pct: Int = 0, call: String? = nil, ready: Bool = true) -> String {
    BarWords.lab(st, human: human, replay: replay, live: live, pct: pct, call: call, ready: ready)
  }

  @Test func turnWords() {
    #expect(lab(.aim) == "Pull to shoot")
    #expect(lab(.thinking, human: false) == "CPU thinking")
    #expect(lab(.stroke, human: false) == "Rolling")
    #expect(lab(.rolling) == "Rolling")
    #expect(lab(.choose) == "Your choice")
    #expect(lab(.over) == "")
    /* only the player's aim reads the call */
    #expect(lab(.thinking, human: false, call: "3 \u{00b7} Top Left") == "CPU thinking")
  }

  @Test func replayAndLive() {
    #expect(lab(.thinking, human: false, replay: true) == "Replay")
    #expect(lab(.aim, replay: true, live: true, pct: 40) == "Replay")
    #expect(lab(.aim, live: true, pct: 73) == "73%")
  }

  @Test func calls() {
    #expect(lab(.aim, ready: false) == "Call your shot")
    #expect(lab(.aim, call: "3", ready: false) == "Call your shot")
    #expect(lab(.aim, call: "3 \u{00b7} Tap a Pocket", ready: false) == "3 \u{00b7} Tap a Pocket")
    #expect(lab(.aim, call: "Bank: 3 \u{00b7} Top Left") == "Bank: 3 \u{00b7} Top Left")
    #expect(lab(.aim, call: "Safety") == "Safety")
  }

  @Test func idleOnlyReadyToPull() {
    #expect(BarWords.idle(lab(.aim)))
    for l in [lab(.thinking, human: false), lab(.rolling), lab(.choose), lab(.over), lab(.aim, ready: false), lab(.aim, replay: true)] { #expect(!BarWords.idle(l), "\(l)") }
  }

  @Test func wheel() {
    #expect(!BarWords.wheelOff(.aim, human: true, replay: false))
    #expect(BarWords.wheelOff(.aim, human: true, replay: true))
    #expect(BarWords.wheelOff(.thinking, human: false, replay: false))
    #expect(BarWords.wheelOff(.stroke, human: true, replay: false))
    #expect(BarWords.wheelOff(.rolling, human: true, replay: false))
    #expect(BarWords.wheelOff(.choose, human: true, replay: false))
    #expect(BarWords.wheelOff(.over, human: false, replay: false))
  }
}
