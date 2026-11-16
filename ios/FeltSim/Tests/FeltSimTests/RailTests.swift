/* the bottom rail's row against the page (tools/ios-golden.cjs: rail.json): placeRail's own lines run in node over its
   whole STEPS (the seats set closer, the replay bare, the badge given way, the scoreboard cut part by part, the switch,
   the scoreboard) and the score keeper's fallback, on the page's own gaps and widths at 375x667, 667x375 and 393x852
   (8-ball, snooker's scoreboard, 14.1, rotation, carom, a match's tally pips, a party), with the replay and in 3D and on
   narrower gaps: every seat's centre (and far rail), the scoreboard's, the replay's items', the switch's, the step it
   stood at, and that step's tight, bare and cut */
import Foundation
import Testing
@testable import FeltSim

@Suite struct RailTests {
  @Test func placeRail() throws {
    let url = try #require(Bundle.module.url(forResource: "rail.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let gaps = { (v: Any?) -> [[Double]]? in (v as? [[NSNumber]])?.map { $0.map(\.doubleValue) } }
    let num = { (v: Any?) -> Double? in (v as? NSNumber)?.doubleValue }
    var n = 0, levels = Set<Int>()
    for c in fx["cases"] as! [[String: Any]] {
      let name = c["name"] as! String, i = c["in"] as! [String: Any], o = c["out"] as! [String: Any]
      let chips = (i["chips"] as! [[NSNumber]]).map { RailRow.Chip(w: $0[0].doubleValue, tight: $0[1].doubleValue) }
      var rpl: [RailRow.Rpl] = []
      if let r = i["rpl"] as? [String: Any] {
        if let w = num(r["offer"]) { rpl = [RailRow.Rpl(w: w)] }
        else { rpl = [RailRow.Rpl(w: num(r["skip"])!), RailRow.Rpl(w: num(r["badge"])!, bare: num(r["bare"])!, badge: true)] }
      }
      let top = gaps(i["top"])
      let row = RailRow.place(gaps(i["segs"])!, top: top, pockets: gaps(i["pk"])!, live: top == nil, mid: num(i["mid"])!, chips: chips,
                              turn: (i["turn"] as! NSNumber).intValue, snk: (i["snk"] as? [NSNumber])?.map(\.doubleValue), rpl: rpl, pw: num(i["pw"]))
      let seats = (o["seats"] as! [Any]).map { s -> [Double]? in (s as? [Any]).map { [($0[0] as! NSNumber).doubleValue, ($0[1] as! Bool) ? 1 : 0] } }
      #expect(row.seats.map { $0.map { [$0.x, $0.far ? 1 : 0] } } == seats, "\(name): seats \(row.seats)")
      #expect(row.snk == num(o["snk"]), "\(name): scoreboard \(String(describing: row.snk))")
      #expect(row.rpl == (o["rpl"] as! [Any]).map { num($0) }, "\(name): replay \(row.rpl)")
      #expect(row.sw == num(o["sw"]), "\(name): switch \(String(describing: row.sw))")
      #expect(row.level == (o["level"] as! NSNumber).intValue, "\(name): step \(row.level)")
      #expect(row.tight == (o["tight"] as! Bool) && row.bare == (o["bare"] as! Bool) && row.cut == (o["cut"] as! NSNumber).intValue, "\(name): tight \(row.tight), bare \(row.bare), cut \(row.cut)")
      levels.insert(row.level); n += 1
    }
    /* every step reached, and the score keeper alone */
    #expect(n >= 500 && levels == Set(Array(0..<RailRow.ALL_STEPS.count) + [99]), "\(n) cases, steps \(levels.sorted())")
  }
}
