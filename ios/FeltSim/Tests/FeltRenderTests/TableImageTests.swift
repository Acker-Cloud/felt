/* FeltRender against the page, pixel by pixel. tools/ios-pixels.cjs saves the page's own table
   (paintTable plus the vignette) in fixed views; this paints the same views and measures the
   difference per channel. Two rasterisers (Skia, CoreGraphics) never agree on every anti-aliased
   edge, so the bound is on the error's size and spread, not on equality. FELT_RENDER_OUT=<dir>
   writes ours and an amplified difference beside each reference. */
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeltRender
import FeltSim

struct PixelStats { var mean: Double, p99: Int, over16: Double, over48: Double }

func rgba(_ img: CGImage) -> [UInt8] {
  let w = img.width, h = img.height
  var buf = [UInt8](repeating: 0, count: w * h * 4)
  let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  return buf
}
func compare(_ a: [UInt8], _ b: [UInt8]) -> PixelStats {
  var hist = [Int](repeating: 0, count: 256), sum = 0, n = 0
  for i in stride(from: 0, to: a.count, by: 4) {
    var d = 0
    for j in 0..<3 { d = max(d, abs(Int(a[i + j]) - Int(b[i + j]))) }
    hist[d] += 1; sum += d; n += 1
  }
  var acc = 0, p99 = 255
  for (v, c) in hist.enumerated() { acc += c; if Double(acc) >= 0.99 * Double(n) { p99 = v; break } }
  let over = { (t: Int) in Double(hist[(t + 1)...].reduce(0, +)) / Double(n) }
  return PixelStats(mean: Double(sum) / Double(n), p99: p99, over16: over(16), over48: over(48))
}
func writePNG(_ img: CGImage, _ url: URL) {
  let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

@Suite struct TableImageTests {
  nonisolated(unsafe) static let index: [[String: Any]] = {
    let url = Bundle.module.url(forResource: "tables.json", withExtension: nil, subdirectory: "Fixtures")!
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
  }()

  /* the look the page painted with (look() and roomId() recorded beside each image) */
  static func lookOf(_ e: [String: Any]) -> TableLook {
    guard let l = e["look"] as? [String: Any], let room = e["room"] as? String else { return TableLook.of(game: e["game"] as! String) }
    return TableLook.of(Dress(cloth: l["cloth"] as! String, cue: l["cue"] as! String, chalk: l["chalk"] as! String, rail: l["rail"] as! String, balls: l["balls"] as! String, room: room))
  }
  @Test(arguments: 0..<TableImageTests.index.count)
  func table(_ i: Int) throws {
    let e = Self.index[i], file = e["file"] as! String
    let url = try #require(Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fixtures"))
    let ref = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    let sim = Sim()
    sim.setTable(e["table"] as! String, e["shape"] as? String)
    let v = e["view"] as! [String: Any]
    let view = TableView2D(k: v["k"] as! Double, ox: v["ox"] as! Double, oy: v["oy"] as! Double, portrait: v["portrait"] as! Bool)
    let p = TablePainter(sim: sim, view: view, dpr: e["dpr"] as! Double, rail: e["RAIL"] as! Double,
                         look: Self.lookOf(e), pageColor: e["page"] as! String)
    let t0 = Date()
    let ours = p.paint(width: e["w"] as! Int, height: e["h"] as! Int).image()
    let ms = Date().timeIntervalSince(t0) * 1000
    let a = rgba(ours), b = rgba(ref), s = compare(a, b)
    print(String(format: "%@  mean %.2f  p99 %d  >16 %.2f%%  >48 %.3f%%  (%.0f ms)", file, s.mean, s.p99, s.over16 * 100, s.over48 * 100, ms))
    if let out = ProcessInfo.processInfo.environment["FELT_RENDER_OUT"] {
      let dir = URL(fileURLWithPath: out)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      writePNG(ours, dir.appendingPathComponent("ours-" + file))
      var d = [UInt8](repeating: 255, count: a.count)
      for i in stride(from: 0, to: a.count, by: 4) { for j in 0..<3 { d[i + j] = UInt8(min(255, abs(Int(a[i + j]) - Int(b[i + j])) * 8)) } }
      let img = CGImage(width: ours.width, height: ours.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ours.width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: CGDataProvider(data: Data(d) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
      writePNG(img, dir.appendingPathComponent("diff-" + file))
    }
    #expect(s.mean < 1.5 && s.p99 <= 8 && s.over48 < 0.001, "\(file): mean \(s.mean), p99 \(s.p99), over 48 \(s.over48)")
  }
}
#endif
