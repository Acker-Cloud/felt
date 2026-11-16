/* 6b3's words for VoiceOver (#potSay): every ball down in pot order (potTick's pw.order), both sides, whatever the
   windows show; potSeats and potGame against the page's (expected values from index.html's own lines run in node) */
import Testing
@testable import FeltSim

@Suite struct PotSayTests {
  @Test func order() {
    var o: [Int] = []
    let steps: [([Int], [Int], String)] = [
      ([3], [3], "Potted: 3"),
      ([3, 1, 12], [3, 1, 12], "Potted: 3, 1, 12"),
      ([1, 12, 3, 9, 10], [3, 1, 12, 9, 10], "Potted: 3, 1, 12, 9, 10"),
      ([12, 9, 10, 15, 2, 8], [12, 9, 10, 2, 8, 15], "Potted: 12, 9, 10, 2, 8, 15"),
      ([12, 15, 2, 8], [12, 2, 8, 15], "Potted: 12, 2, 8, 15"),
    ]
    for (off, want, words) in steps {
      o = PotRail.order(o, off: off)
      #expect(o == want)
      #expect(SeatWords.potted(o) == words)
    }
    #expect(SeatWords.potted(PotRail.order(o, off: [])) == "")
  }

  @Test func seats() {
    func S(_ o: [Int], _ e: Bool, _ r: Bool, _ c: [Int]) -> [[Int]] { PotRail.seats(o, eight: e, eightRight: r, counts: c).map { [$0.n, $0.side, $0.i] } }
    /* a full left side: the 2 has no window, and is still read */
    #expect(S([3, 1, 12, 9, 10, 8, 2], true, true, [2, 8]) == [[3, 0, 0], [1, 0, 1], [12, 1, 0], [9, 1, 1], [10, 1, 2], [8, 1, 3]])
    #expect(S([3, 1, 12, 9, 10, 8, 2], true, false, [8, 8]) == [[3, 0, 0], [1, 0, 1], [12, 1, 0], [9, 1, 1], [10, 1, 2], [8, 0, 2], [2, 0, 3]])
    #expect(S([9, 1, 2, 3, 4, 5], false, false, [3, 2]) == [[9, 0, 0], [1, 0, 1], [2, 0, 2], [3, 1, 0], [4, 1, 1]])
    #expect(SeatWords.potted([9, 1, 2, 3, 4, 5]) == "Potted: 9, 1, 2, 3, 4, 5")
  }

  /* potGame: 8, 9, 10 and Chinese 8-ball, a game or practice; never a trick shot, a drill, the lesson or a tutorial */
  @Test func on() {
    for k in ["8", "9", "10", "heyball"] {
      #expect(PotRail.on(kind: k, mode: nil, tutorial: false, lesson: false))
      #expect(PotRail.on(kind: k, mode: "practice", tutorial: false, lesson: false))
      #expect(!PotRail.on(kind: k, mode: "trick", tutorial: false, lesson: false))
      #expect(!PotRail.on(kind: k, mode: "drill", tutorial: false, lesson: false))
      #expect(!PotRail.on(kind: k, mode: nil, tutorial: true, lesson: false))
      #expect(!PotRail.on(kind: k, mode: "practice", tutorial: false, lesson: true))
    }
    for k in ["straight", "rotation", "snooker", "carom", "bumper"] { #expect(!PotRail.on(kind: k, mode: nil, tutorial: false, lesson: false)) }
  }

  /* the element's frame: the shown windows of the first side showing any, else the planned ones; never both sides */
  @Test func sayBox() {
    let a = [0.0, 100, 10, 110], b = [0.0, 80, 10, 90], c = [300.0, 100, 310, 110]
    #expect(PotRail.sayBox(shown: [[a, b], [c]], planned: [[a, b], [c]]) == [0, 80, 10, 110])
    #expect(PotRail.sayBox(shown: [[], [c]], planned: [[a], [c]]) == c)
    #expect(PotRail.sayBox(shown: [[], []], planned: [[], [c]]) == c)
    #expect(PotRail.sayBox(shown: [[], []], planned: [[a, b], [c]]) == [0, 80, 10, 110])
    #expect(PotRail.sayBox(shown: [[], []], planned: [[], []]) == nil)
  }

  /* zoomed (cam.z > 1.02) the windows hide and the words hold: potTick writes #potSay before vis; the element stands
     where the windows do unzoomed (the fitted view's slots) */
  @Test func zoomed() {
    #expect(PotRail.windows(replay: false, live: false, z: 1) && PotRail.windows(replay: false, live: false, z: 1.02))
    #expect(!PotRail.windows(replay: false, live: false, z: 1.03) && !PotRail.windows(replay: false, live: false, z: 3))
    #expect(PotRail.windows(replay: false, live: true, z: 3))
    let s = Sim()
    s.setTable("9")
    let k = 393 / (s.TW + 2 * 0.1), P = PotRail.plan(s, k: k, ox: 0.1 * k, oy: 40, portrait: true, live: false, rail: 0.1, co: 0.05, sights: [])
    let order = PotRail.order([], off: [9, 1, 12])
    let q = PotRail.seats(order, eight: false, eightRight: false, counts: P.sides.map(\.count)), plan = PotRail.planned(P, q)
    #expect(q.count == 3 && plan[0].count == 3 && plan[1].isEmpty)
    let box = PotRail.sayBox(shown: [[], []], planned: plan)!
    let sl = P.sides[0]
    #expect(box == [sl[0].x - P.s / 2, sl[2].y - P.s / 2, sl[0].x + P.s / 2, sl[0].y + P.s / 2])
    #expect(SeatWords.potted(order) == "Potted: 1, 9, 12")
  }

  /* a replay (potTick's !rp): the windows hide whatever the view, top-down or 3D, zoomed or not; the words hold */
  @Test func replay() {
    for live in [false, true] { for z in [1.0, 1.02, 3] { #expect(!PotRail.windows(replay: true, live: live, z: z)) } }
    #expect(PotRail.windows(replay: false, live: false, z: 1))
    #expect(SeatWords.potted(PotRail.order([1, 9], off: [9, 1, 12])) == "Potted: 1, 9, 12")
  }
}
