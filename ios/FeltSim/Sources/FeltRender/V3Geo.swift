/* index.html 4o's v3Geo, line for line: the table's art (drawTableImage, the posts left out) laid flat at K px a metre
   with the tops' cut (alpha halved over the bed, the mouths and the holes), the two planes (the bed as a fan from the
   middle at height 0, the tops as the ring between the outline and the bed at h), and the faces (the apron, the body
   under it to the floor, the cushions' noses and jaws) and bumper pool's posts as lit vertices. Render frame: z = -height.
   planes: [x, y, z, u, v] per vertex; mesh: [x, y, z, nx, ny, nz, r, g, b, a] per vertex. */
#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import FeltSim

public struct V3Geo {
  public let image: CGImage, planes: [Float], nBed: Int, nTop: Int, mesh: [Float], nFaces: Int, nPosts: Int, h: Double, co: Double, bounce: [Double]
  public static let FLOOR = 0.76

  /* heroOutline: the table's outline at the rails' outer edge (the octagon, or the rectangle with rounded corners) */
  static func outline(_ s: Sim, _ P: TablePainter, _ co: Double) -> [[Double]] {
    let RAIL = P.RAIL
    if s.BED_LINES != nil { return s.octagon(RAIL) }
    let r = s.MOUTHS.isEmpty ? Swift.min(0.045, RAIL) : Swift.min(P.pocketShape(0, co).rc + P.capGap(co), RAIL + co)
    let x0 = -RAIL, y0 = -RAIL, x1 = s.TL + RAIL, y1 = s.TW + RAIL
    var out: [[Double]] = []
    for c in [[x1 - r, y0 + r, -Double.pi / 2], [x1 - r, y1 - r, 0], [x0 + r, y1 - r, Double.pi / 2], [x0 + r, y0 + r, Double.pi]] {
      for i in 0...6 { let a = c[2] + Double(i) * Double.pi / 12; out.append([c[0] + r * JSMath.cos(a), c[1] + r * JSMath.sin(a)]) }
    }
    return out
  }
  /* mixRgb(hex, k, to): a colour k of the way to `to` (black by default), as 0-1 */
  static func mix(_ hex: String, _ k: Double, _ to: [Double] = [0, 0, 0]) -> [Double] {
    let c = RGBA(css: hex), v = [c.r * 255, c.g * 255, c.b * 255]
    return (0..<3).map { (v[$0] + (to[$0] - v[$0]) * k + 0.5).rounded(.down) / 255 }
  }

  public static func build(_ s: Sim, look: TableLook, soft: Bool = false) -> V3Geo {
    let TL = s.TL, TW = s.TW
    let probe = TablePainter(sim: s, view: TableView2D(k: 1, ox: 0, oy: 0, portrait: false), dpr: 1, rail: RAIL_MAX, look: look)
    let co = probe.cushionDepth(), h = s.BALL_R * 1.42, out = outline(s, probe, co), RAIL = RAIL_MAX, ext = RAIL + 0.02
    let K = Swift.min(soft ? 560 : 1000, (soft ? 2048 : 4096) / (TL + 2 * ext)), w = Int((TL + 2 * ext) * K + 0.999999), hh = Int((TW + 2 * ext) * K + 0.999999)
    var P = TablePainter(sim: s, view: TableView2D(k: K, ox: ext * K, oy: ext * K, portrait: false), dpr: 1, rail: RAIL, look: look)
    P.noPosts = true
    let g = P.paint(width: w, height: hh, vignette: true)
    /* the tops' cut: alpha halved over the bed, the mouths and the holes */
    g.setTransform(K, 0, 0, K, ext * K, ext * K)
    g.globalAlpha = 0.5; g.fillStyle("#000")
    g.beginPath()
    if s.BED_LINES != nil { P.polyPath(g, s.octagon(0)) } else { g.rect(0, 0, TL, TW) }
    for m in s.MOUTHS { let a = m[0], b = m[1]; g.moveTo(a.p[0], a.p[1]); g.lineTo(a.e[0], a.e[1]); g.lineTo(b.e[0], b.e[1]); g.lineTo(b.p[0], b.p[1]); g.closePath() }
    for (i, Q) in s.POCKETS.enumerated() { g.moveTo(Q[0] + s.POCKET_R[i], Q[1]); g.arc(Q[0], Q[1], s.POCKET_R[i], 0, Double.pi * 2); g.closePath() }
    g.cg.setBlendMode(.destinationOut)
    g.fill(.nonzero)
    g.cg.setBlendMode(.normal)
    g.setTransform(1, 0, 0, 1, 0, 0); g.globalAlpha = 1
    let image = g.image()
    /* the two planes: the outline as a fan from the bed's middle at 0, and the tops' ring at h */
    let uv = { (x: Double, y: Double) -> [Float] in [Float((x + ext) * K / Double(w)), Float((y + ext) * K / Double(hh))] }
    var bed: [Float] = [], ring: [Float] = []
    let m0 = [TL / 2, TW / 2]
    for i in out.indices {
      let a = out[i], b = out[(i + 1) % out.count]
      for q in [m0, a, b] { bed += [Float(q[0]), Float(q[1]), 0] + uv(q[0], q[1]) }
    }
    let inner = s.BED_LINES != nil ? s.octagon(0) : [[0, 0], [TL, 0], [TL, TW], [0, TW]]
    func toEdge(_ q: [Double]) -> [Double] {
      let dx = q[0] - m0[0], dy = q[1] - m0[1]
      var best = 1.0
      for i in inner.indices {
        let a = inner[i], b = inner[(i + 1) % inner.count], ex = b[0] - a[0], ey = b[1] - a[1], den = dx * ey - dy * ex
        if abs(den) < 1e-12 { continue }
        let t = ((a[0] - m0[0]) * ey - (a[1] - m0[1]) * ex) / den, u = ((a[0] - m0[0]) * dy - (a[1] - m0[1]) * dx) / den
        if t > 0 && u >= -1e-9 && u <= 1 + 1e-9 { best = Swift.min(best, t) }
      }
      return [m0[0] + dx * best, m0[1] + dy * best]
    }
    for i in out.indices {
      let a = out[i], b = out[(i + 1) % out.count], ai = toEdge(a), bi = toEdge(b)
      for q in [a, b, bi, a, bi, ai] { ring += [Float(q[0]), Float(q[1]), Float(-h)] + uv(q[0], q[1]) }
    }
    /* the faces: the apron, the body under it, the noses and jaws */
    let RW = look.rail, cushion = look.cloth.cushion
    var faces: [Float] = []
    func quad(_ a: [Double], _ b: [Double], _ z0: Double, _ z1: Double, _ c0: [Double], _ c1: [Double], _ n: [Double]) {
      func v(_ q: [Double], _ z: Double, _ c: [Double]) { faces += [Float(q[0]), Float(q[1]), Float(-z), Float(n[0]), Float(n[1]), 0, Float(c[0]), Float(c[1]), Float(c[2]), 1] }
      v(a, z0, c0); v(b, z0, c0); v(b, z1, c1); v(a, z0, c0); v(b, z1, c1); v(a, z1, c1)
    }
    for i in out.indices {
      let a = out[i], b = out[(i + 1) % out.count]
      var L = JSMath.hypot(b[0] - a[0], b[1] - a[1]); if L == 0 { L = 1 }
      quad(a, b, h, -0.15, mix(RW.base, 0.3), mix(RW.base, 0.9), [(b[1] - a[1]) / L, (a[0] - b[0]) / L])
    }
    let cx = TL / 2, cy = TW / 2
    let sx = Swift.max(0.2, TL / 2 - 0.14) / (TL / 2 + RAIL), sy = Swift.max(0.2, TW / 2 - 0.14) / (TW / 2 + RAIL), body = out.map { [cx + ($0[0] - cx) * sx, cy + ($0[1] - cy) * sy] }
    for i in body.indices {
      let a = body[i], b = body[(i + 1) % body.count]
      var L = JSMath.hypot(b[0] - a[0], b[1] - a[1]); if L == 0 { L = 1 }
      quad(a, b, -0.15, -FLOOR, mix(RW.base, 0.72), mix(RW.base, 0.9), [(b[1] - a[1]) / L, (a[0] - b[0]) / L])
    }
    for poly in s.CUSHION_POLYS {
      let ea = poly[0], pa = poly[1], pb = poly[2], eb = poly[3]
      for (a, b) in s.MOUTHS.isEmpty ? [(pa, pb)] : [(pa, pb), (ea, pa), (pb, eb)] {
        let mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2
        var L = JSMath.hypot(b[0] - a[0], b[1] - a[1]); if L == 0 { L = 1 }
        var nx = (b[1] - a[1]) / L, ny = (a[0] - b[0]) / L
        if nx * (cx - mx) + ny * (cy - my) < 0 { nx = -nx; ny = -ny }
        quad(a, b, h, 0, mix(cushion, 0.05, [255, 255, 255]), mix(cushion, 0.6), [nx, ny])
      }
    }
    /* the bumper posts: a black rubber ring round a nickel cap, lit */
    var posts: [Float] = []
    let HP = 0.052, N = 20
    for q in s.BUMPERS {
      let px = q[0], py = q[1]
      for i in 0..<N {
        let a0 = Double(i) / Double(N) * 2 * Double.pi, a1 = Double(i + 1) / Double(N) * 2 * Double.pi
        let Pt = { (a: Double) in [px + BUMPER_R * JSMath.cos(a), py + BUMPER_R * JSMath.sin(a)] }
        let p0 = Pt(a0), p1 = Pt(a1), rub = [0.13, 0.13, 0.14], cap = [0.68, 0.67, 0.65]
        func v(_ q: [Double], _ z: Double, _ n: [Double], _ c: [Double]) { posts += [Float(q[0]), Float(q[1]), Float(-z), Float(n[0]), Float(n[1]), Float(n[2]), Float(c[0]), Float(c[1]), Float(c[2]), 1] }
        let n0 = [JSMath.cos(a0), JSMath.sin(a0), 0], n1 = [JSMath.cos(a1), JSMath.sin(a1), 0]
        v(p0, HP, n0, rub); v(p1, HP, n1, rub); v(p1, 0, n1, rub); v(p0, HP, n0, rub); v(p1, 0, n1, rub); v(p0, 0, n0, rub)
        v([px, py], HP, [0, 0, -1], cap); v(p0, HP, [0, 0, -1], cap); v(p1, HP, [0, 0, -1], cap)
      }
    }
    let b = look.cloth.bounce.split(separator: ",").map { (Double($0.trimmingCharacters(in: .whitespaces)) ?? 0) / 255 }
    return V3Geo(image: image, planes: bed + ring, nBed: bed.count / 5, nTop: ring.count / 5, mesh: faces + posts, nFaces: faces.count / 10, nPosts: posts.count / 10, h: h, co: co, bounce: b)
  }
}
#endif
#if canImport(CoreGraphics)
/* v3NumArt: the numbers 1 to 15 as drawBall writes them (0.6 of the radius, bold), one 128 px cell each */
public enum V3Art {
  public static func numbers() -> CGImage {
    let S = 128.0, g = Canvas2D(width: 16 * 128, height: 128)
    g.fillStyle("#fff")
    for n in 1...15 { g.fillTextCentered(String(n), (Double(n) + 0.5) * S, S * 0.54, size: 0.6 * S, weight: 0.4) }
    return g.image()
  }
}
#endif
