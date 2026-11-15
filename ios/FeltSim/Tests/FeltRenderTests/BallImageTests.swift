/* 4b's balls against the page: each look's set at a phone's size and large, on its cloth, with the
   cast shadow and contact shade, the same orientation matrices. FELT_RENDER_OUT as TableImageTests. */
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeltRender
import FeltSim

@Suite struct BallImageTests {
  @Test(arguments: ["8", "9", "heyball", "snooker", "carom", "shop-red-pro", "shop-grey-vintage", "shop-midnight-pro", "shop-plum-vintage"])
  func balls(_ game: String) throws {
    let url = try #require(Bundle.module.url(forResource: "balls-\(game).json", withExtension: nil, subdirectory: "Fixtures"))
    let e = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let file = e["file"] as! String
    let ref = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fixtures")! as CFURL, nil)!, 0, nil)!
    let W = e["W"] as! Int, H = e["H"] as! Int
    let g = Canvas2D(width: W, height: H)
    g.fillStyle(e["cloth"] as! String); g.fillRect(0, 0, Double(W), Double(H))
    let cloth = RGBA(css: e["cloth"] as! String)
    let p = BallPainter(set: BallSet.all[e["balls"] as! String]!, bounce: e["bounce"] as! String, dpr: 2, portrait: false,
                        lowRim: e["lowRim"] as! Bool, rimAll: e["rim"] as! Bool, clothBase: [cloth.r * 255, cloth.g * 255, cloth.b * 255])
    let list = e["list"] as! [[String: Any]], TL = e["TL"] as! Double, TW = e["TW"] as! Double, R = e["R"] as! Double
    for b in list { p.drawCast(g, b["x"] as! Double, b["y"] as! Double, b["X"] as! Double, b["Y"] as! Double, b["r"] as! Double, tl: TL, tw: TW, ballR: R) }
    for b in list { p.drawBall(g, b["n"] as! Int, b["X"] as! Double, b["Y"] as! Double, b["r"] as! Double, p.axesOf(b["m"] as! [Double])) }
    let ours = g.image(), a = rgba(ours), s = compare(a, rgba(ref))
    print(String(format: "%@  mean %.2f  p99 %d  >16 %.2f%%  >48 %.3f%%", file, s.mean, s.p99, s.over16 * 100, s.over48 * 100))
    if let out = ProcessInfo.processInfo.environment["FELT_RENDER_OUT"] {
      let dir = URL(fileURLWithPath: out)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      writePNG(ours, dir.appendingPathComponent("ours-" + file))
    }
    /* measured 2026-11-14: plain sets mean 0.13 to 0.36, p99 2 to 4; numbered sets mean about 1.0, p99 13 to 14,
       0.17% over 48, all of it the number glyphs' edges (Skia against CoreText on the same SF face: widths agree
       to 0.005 px) and the near-black 8's rim against the cloth */
    #expect(s.mean < 1.2 && s.p99 <= 15 && s.over48 < 0.0025, "\(file): mean \(s.mean), p99 \(s.p99), over 48 \(s.over48)")
  }
}
#endif
