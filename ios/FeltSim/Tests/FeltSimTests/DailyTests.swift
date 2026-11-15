/* the daily shot against the page (tools/ios-golden.cjs: daily.json, the page's own dayNum and dailyTrick): 800 days
   across year ends, leap days and before 1970, each day's number and shot */
import Foundation
import Testing
@testable import FeltSim

@Suite struct DailyTests {
  @Test func days() throws {
    let url = try #require(Bundle.module.url(forResource: "daily.json", withExtension: nil, subdirectory: "Fixtures"))
    let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any], days = fx["days"] as! [[Any]]
    for r in days {
      let day = r[0] as! String
      #expect(dayNum(day) == (r[1] as! NSNumber).intValue && dailyTrick(day).id == r[2] as! String, "\(day): \(dayNum(day)) \(dailyTrick(day).id)")
    }
    #expect(days.count == 800)
  }
}
