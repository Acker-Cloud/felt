/* JV against V8 (tools/ios-golden.cjs: jv.json): Number#toString for every double in the fixture by its bits, strings
   quoted as JSON.stringify quotes them, and objects parsed and written back in JS's key order */
import Foundation
import Testing
@testable import FeltSim

@Suite struct JVTests {
  nonisolated(unsafe) static let fx: [String: Any] = {
    let url = Bundle.module.url(forResource: "jv.json", withExtension: nil, subdirectory: "Fixtures")!
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  }()
  @Test func numbers() {
    var bad: [String] = []
    for p in Self.fx["nums"] as! [[String]] {
      let d = Double(bitPattern: UInt64(p[0], radix: 16)!), s = JV.numberString(d)
      if s != p[1] && !(d.isNaN) { bad.append("\(p[0]): \(s) vs \(p[1])") }
    }
    #expect(bad.isEmpty, "\(bad.count) numbers differ: \(bad.prefix(8))")
  }
  @Test func strings() {
    for p in Self.fx["strs"] as! [[String]] { #expect(JV.str(p[0]).stringify() == p[1], "\(p[1])") }
  }
  @Test func objects() {
    for p in Self.fx["objs"] as! [[String]] {
      let v = JV.parse(p[0])
      #expect(v?.stringify() == p[1], "\(p[0].prefix(80)) -> \(v?.stringify().prefix(80) ?? "nil") vs \(p[1].prefix(80))")
    }
  }
}
