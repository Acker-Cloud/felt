/* The HTML canvas 2D context over CoreGraphics, so section 4's painters port line for line. What
   follows the canvas spec where CoreGraphics differs:
   - a path is built in device space: each point is transformed by the transform current when it
     is added (moveTo, arc, ...), as the canvas does;
   - a gradient or pattern is laid out in the transform current when it paints (fill, stroke);
   - a gradient interpolates unpremultiplied, extends its end colours both ways, and a radial one
     is the canvas's two-circle cone;
   - a shadow is the shape's alpha, blurred with a Gaussian of sigma shadowBlur / 2, tinted, offset
     by shadowOffsetX/Y in device pixels (the transform does not apply), painted before the shape
     and under the same clip;
   - a stroke's width scales with the transform (uniform scales and rotations only, which is all
     section 4 uses for strokes); the canvas's default miter limit 10, butt caps, miter joins;
   - colours are sRGB, composited in sRGB (no linear blending), as the canvas does.
   The bitmap is premultiplied RGBA, top-left origin, device pixels. */
#if canImport(CoreGraphics)
import Accelerate
import CoreGraphics
import CoreText
import Foundation

public struct RGBA: Equatable, Sendable {
  public var r, g, b, a: Double
  public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
  /* '#rgb', '#rrggbb', 'rgb(r,g,b)', 'rgba(r,g,b,a)' */
  public init(css s: String) {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("#") {
      var h = String(t.dropFirst())
      if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
      let v = UInt32(h, radix: 16) ?? 0
      self.init(Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255)
      return
    }
    if let o = t.firstIndex(of: "("), let c = t.lastIndex(of: ")") {
      let p = t[t.index(after: o)..<c].split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
      self.init(p[0] / 255, p[1] / 255, p[2] / 255, p.count > 3 ? p[3] : 1)
      return
    }
    self.init(0, 0, 0)
  }
}

public final class Gradient2D {
  enum Kind { case linear(Double, Double, Double, Double), radial(Double, Double, Double, Double, Double, Double) }
  let kind: Kind
  var stops: [(Double, RGBA)] = []
  init(_ k: Kind) { kind = k }
  public func addColorStop(_ t: Double, _ c: String) { stops.append((t, RGBA(css: c))) }
  public func addColorStop(_ t: Double, _ c: RGBA) { stops.append((t, c)) }
}

public final class Pattern2D {
  let image: CGImage
  init(_ i: CGImage) { image = i }
}

public enum Style {
  case color(RGBA), gradient(Gradient2D), pattern(Pattern2D)
}

public enum FillRule { case nonzero, evenodd }

public final class Canvas2D {
  public let width: Int, height: Int
  public let cg: CGContext
  private struct State {
    var fill: Style = .color(RGBA(0, 0, 0)), stroke: Style = .color(RGBA(0, 0, 0))
    var lineWidth = 1.0, lineCap = CGLineCap.butt, lineJoin = CGLineJoin.miter, alpha = 1.0
    var shadowColor = RGBA(0, 0, 0, 0), shadowBlur = 0.0, shadowX = 0.0, shadowY = 0.0
    var ctm = CGAffineTransform.identity, dash: [Double] = []
    var clipMask: CGImage? = nil   /* the clip as an alpha image, kept for shadows */
    var clipped = false
  }
  private var st = State()
  private var stack: [State] = []
  private var path = CGMutablePath()
  private var cur: CGPoint? = nil, subStart: CGPoint? = nil

  public init(width: Int, height: Int) {
    self.width = width; self.height = height
    cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    /* a canvas starts transparent black; CG does not promise that of memory it allocates */
    cg.clear(CGRect(x: 0, y: 0, width: width, height: height))
    /* top-left origin, y down: the canvas's device space */
    cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: 1, y: -1)
    cg.setShouldAntialias(true); cg.interpolationQuality = .high
  }

  public func image() -> CGImage { cg.makeImage()! }

  // MARK: state

  public var fillStyle: Style { get { st.fill } set { st.fill = newValue } }
  public var strokeStyle: Style { get { st.stroke } set { st.stroke = newValue } }
  public func fillStyle(_ css: String) { st.fill = .color(RGBA(css: css)) }
  public func strokeStyle(_ css: String) { st.stroke = .color(RGBA(css: css)) }
  public var lineWidth: Double { get { st.lineWidth } set { if newValue > 0 && newValue.isFinite { st.lineWidth = newValue } } }
  public var lineCap: CGLineCap { get { st.lineCap } set { st.lineCap = newValue } }
  public var lineJoin: CGLineJoin { get { st.lineJoin } set { st.lineJoin = newValue } }
  public var globalAlpha: Double { get { st.alpha } set { if newValue >= 0 && newValue <= 1 { st.alpha = newValue } } }
  public func shadow(_ color: String, blur: Double, x: Double, y: Double) {
    st.shadowColor = RGBA(css: color); st.shadowBlur = blur; st.shadowX = x; st.shadowY = y
  }
  public var shadowColor: String { get { "" } set { st.shadowColor = RGBA(css: newValue) } }
  public var shadowBlur: Double { get { st.shadowBlur } set { st.shadowBlur = newValue } }
  public var shadowOffsetX: Double { get { st.shadowX } set { st.shadowX = newValue } }
  public var shadowOffsetY: Double { get { st.shadowY } set { st.shadowY = newValue } }
  public func setLineDash(_ d: [Double]) { st.dash = d }

  public func save() { stack.append(st); cg.saveGState() }
  public func restore() {
    guard let s = stack.popLast() else { return }
    st = s; cg.restoreGState()
  }

  // MARK: transforms

  public func setTransform(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
    st.ctm = CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f)
  }
  public func translate(_ x: Double, _ y: Double) { st.ctm = CGAffineTransform(translationX: x, y: y).concatenating(st.ctm) }
  public func scale(_ x: Double, _ y: Double) { st.ctm = CGAffineTransform(scaleX: x, y: y).concatenating(st.ctm) }
  public func transform(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
    st.ctm = CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f).concatenating(st.ctm)
  }
  public func rotate(_ a: Double) { st.ctm = CGAffineTransform(rotationAngle: a).concatenating(st.ctm) }
  public var transform: CGAffineTransform { st.ctm }

  // MARK: paths (device space)

  private func dev(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y).applying(st.ctm) }
  public func beginPath() { path = CGMutablePath(); cur = nil; subStart = nil }
  public func moveTo(_ x: Double, _ y: Double) { let p = dev(x, y); path.move(to: p); cur = p; subStart = p }
  public func lineTo(_ x: Double, _ y: Double) {
    let p = dev(x, y)
    if cur == nil { path.move(to: p); subStart = p } else { path.addLine(to: p) }
    cur = p
  }
  public func closePath() { if cur != nil { path.closeSubpath(); cur = subStart } }
  public func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    moveTo(x, y); lineTo(x + w, y); lineTo(x + w, y + h); lineTo(x, y + h); closePath()
    moveTo(x, y)
  }
  public func quadraticCurveTo(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
    if cur == nil { moveTo(cx, cy) }
    let p = dev(x, y); path.addQuadCurve(to: p, control: dev(cx, cy)); cur = p
  }
  public func bezierCurveTo(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
    if cur == nil { moveTo(c1x, c1y) }
    let p = dev(x, y); path.addCurve(to: p, control1: dev(c1x, c1y), control2: dev(c2x, c2y)); cur = p
  }
  /* the canvas arc: a line from the current point to the arc's start, then the arc, built in user
     space and transformed, so it stays a true (possibly turned) circle */
  public func arc(_ x: Double, _ y: Double, _ r: Double, _ a0: Double, _ a1: Double, _ ccw: Bool = false) {
    var sweep = a1 - a0
    let tau = 2 * Double.pi
    if !ccw {
      if sweep >= tau { sweep = tau } else { sweep = sweep.truncatingRemainder(dividingBy: tau); if sweep < 0 { sweep += tau } }
    } else {
      if -sweep >= tau { sweep = -tau } else { sweep = sweep.truncatingRemainder(dividingBy: tau); if sweep > 0 { sweep -= tau } }
    }
    let n = max(1, Int(ceil(abs(sweep) / (Double.pi / 2))))
    let start = dev(x + r * cos(a0), y + r * sin(a0))
    if cur == nil { path.move(to: start); subStart = start } else { path.addLine(to: start) }
    let step = sweep / Double(n)
    var a = a0
    for _ in 0..<n {
      /* one cubic per quarter or less */
      let b = a + step, k = 4.0 / 3 * tan((b - a) / 4)
      let p1 = (x + r * (cos(a) - k * sin(a)), y + r * (sin(a) + k * cos(a)))
      let p2 = (x + r * (cos(b) + k * sin(b)), y + r * (sin(b) - k * cos(b)))
      path.addCurve(to: dev(x + r * cos(b), y + r * sin(b)), control1: dev(p1.0, p1.1), control2: dev(p2.0, p2.1))
      a = b
    }
    cur = dev(x + r * cos(a1), y + r * sin(a1))
  }
  /* arcTo in user space (the canvas's tangent arc from the current point's user position) */
  public func arcTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ r: Double) {
    guard let c = cur else { moveTo(x1, y1); return }
    let inv = st.ctm.inverted(), p0 = c.applying(inv)
    let x0 = Double(p0.x), y0 = Double(p0.y)
    let v1 = (x0 - x1, y0 - y1), v2 = (x2 - x1, y2 - y1)
    let l1 = (v1.0 * v1.0 + v1.1 * v1.1).squareRoot(), l2 = (v2.0 * v2.0 + v2.1 * v2.1).squareRoot()
    let cross = v1.0 * v2.1 - v1.1 * v2.0
    if r == 0 || l1 == 0 || l2 == 0 || abs(cross) < 1e-12 { lineTo(x1, y1); return }
    let u1 = (v1.0 / l1, v1.1 / l1), u2 = (v2.0 / l2, v2.1 / l2)
    let cosT = u1.0 * u2.0 + u1.1 * u2.1, theta = acos(max(-1, min(1, cosT)))
    let t = r / tan(theta / 2)
    let tp1 = (x1 + u1.0 * t, y1 + u1.1 * t), tp2 = (x1 + u2.0 * t, y1 + u2.1 * t)
    let bis = (u1.0 + u2.0, u1.1 + u2.1), bl = (bis.0 * bis.0 + bis.1 * bis.1).squareRoot(), d = r / sin(theta / 2)
    let cx = x1 + bis.0 / bl * d, cy = y1 + bis.1 / bl * d
    let a0 = atan2(tp1.1 - cy, tp1.0 - cx), a1 = atan2(tp2.1 - cy, tp2.0 - cx)
    lineTo(tp1.0, tp1.1)
    /* the short way round */
    var dlt = a1 - a0
    while dlt > Double.pi { dlt -= 2 * Double.pi }
    while dlt <= -Double.pi { dlt += 2 * Double.pi }
    arc(cx, cy, r, a0, a1, dlt < 0)
  }

  // MARK: painting

  private func cgColor(_ c: RGBA, _ alpha: Double = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [c.r, c.g, c.b, c.a * alpha])!
  }
  private func cgGradient(_ g: Gradient2D) -> CGGradient? {
    if g.stops.isEmpty { return nil }
    /* the canvas sorts stops by offset, keeping the order of equal ones */
    let s = g.stops.enumerated().sorted { $0.element.0 != $1.element.0 ? $0.element.0 < $1.element.0 : $0.offset < $1.offset }.map { $0.element }
    var comps: [CGFloat] = [], locs: [CGFloat] = []
    for (t, c) in s { comps += [c.r, c.g, c.b, c.a]; locs.append(CGFloat(max(0, min(1, t)))) }
    return CGGradient(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colorComponents: comps, locations: locs, count: s.count)
  }
  /* paint `style` over the current clip, in the current transform (the clip is already set) */
  private func paint(_ style: Style, in ctx: CGContext, ctm: CGAffineTransform) {
    switch style {
    case .color(let c):
      ctx.setFillColor(cgColor(c)); ctx.fill(CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6))
    case .gradient(let g):
      guard let cgg = cgGradient(g) else { return }
      ctx.concatenate(ctm)
      switch g.kind {
      case .linear(let x0, let y0, let x1, let y1):
        if x0 == x1 && y0 == y1 { return }
        ctx.drawLinearGradient(cgg, start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
      case .radial(let x0, let y0, let r0, let x1, let y1, let r1):
        ctx.drawRadialGradient(cgg, startCenter: CGPoint(x: x0, y: y0), startRadius: r0, endCenter: CGPoint(x: x1, y: y1), endRadius: r1,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
      }
    case .pattern(let p):
      ctx.concatenate(ctm)
      /* CG draws images y-up; the canvas's tile is y-down from its origin */
      let w = CGFloat(p.image.width), h = CGFloat(p.image.height)
      ctx.translateBy(x: 0, y: h); ctx.scaleBy(x: 1, y: -1)
      ctx.draw(p.image, in: CGRect(x: 0, y: 0, width: w, height: h), byTiling: true)
    }
  }

  /* a shape (given as a clip on `ctx`) painted with its shadow first, as the canvas does */
  private func draw(_ style: Style, setClip: (CGContext) -> Void) {
    if st.shadowColor.a > 0 && (st.shadowBlur > 0 || st.shadowX != 0 || st.shadowY != 0) { drawShadow(setClip) }
    cg.saveGState()
    cg.setAlpha(st.alpha)
    setClip(cg)
    paint(style, in: cg, ctm: st.ctm)
    cg.restoreGState()
  }
  /* the shape's coverage into an alpha buffer, blurred, tinted, offset, then drawn under the clip */
  private func drawShadow(_ setClip: (CGContext) -> Void) {
    let sigma = st.shadowBlur / 2, pad = Int(ceil(sigma * 3)) + 2
    let W = width + 2 * pad, H = height + 2 * pad
    guard let m = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return }
    /* a context made on data: nil is not promised to start clear: whatever the memory held would read as coverage
       outside the clip (seen as a rare, load-dependent mismatch in TableImageTests) */
    m.clear(CGRect(x: 0, y: 0, width: W, height: H))
    m.translateBy(x: CGFloat(pad), y: CGFloat(H - pad)); m.scaleBy(x: 1, y: -1)
    m.setShouldAntialias(true)
    setClip(m)
    m.setFillColor(gray: 0, alpha: 1); m.fill(CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6))
    guard let data = m.data else { return }
    let buf = data.bindMemory(to: UInt8.self, capacity: W * H)
    var a = [Float](repeating: 0, count: W * H)
    for i in 0..<(W * H) { a[i] = Float(buf[i]) / 255 }
    if sigma > 0.01 { gaussian(&a, W, H, Float(sigma)) }
    var out = [UInt8](repeating: 0, count: W * H)
    let sa = Float(st.shadowColor.a * st.alpha)
    for i in 0..<(W * H) { out[i] = UInt8(max(0, min(255, (a[i] * sa * 255).rounded()))) }
    let provider = CGDataProvider(data: Data(out) as CFData)!
    /* a gray image: clip(to:mask:) reads its samples as coverage */
    guard let img = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
    let rect = CGRect(x: -Double(pad) + st.shadowX, y: -Double(pad) + st.shadowY, width: Double(W), height: Double(H))
    cg.saveGState()
    cg.translateBy(x: rect.minX, y: rect.minY + rect.height); cg.scaleBy(x: 1, y: -1)
    cg.clip(to: CGRect(x: 0, y: 0, width: rect.width, height: rect.height), mask: img)
    let c = st.shadowColor
    cg.setFillColor(cgColor(RGBA(c.r, c.g, c.b, 1)))
    cg.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    cg.restoreGState()
  }
  /* separable Gaussian, rows then columns (through a transpose), on Accelerate's convolution; the
     edges see zero beyond the buffer, which the shadow's padding keeps clear of any coverage */
  private func gaussian(_ a: inout [Float], _ W: Int, _ H: Int, _ s: Float) {
    let r = Int(ceil(s * 3)), n = 2 * r + 1
    var k = [Float](repeating: 0, count: n)
    var sum: Float = 0
    for i in -r...r { let v = exp(-Float(i * i) / (2 * s * s)); k[i + r] = v; sum += v }
    for i in 0..<n { k[i] /= sum }
    func rows(_ src: [Float], _ w: Int, _ h: Int) -> [Float] {
      var padded = [Float](repeating: 0, count: w + 2 * r)
      var out = [Float](repeating: 0, count: w * h)
      src.withUnsafeBufferPointer { sp in
        out.withUnsafeMutableBufferPointer { op in
          for y in 0..<h {
            padded.withUnsafeMutableBufferPointer { pp in
              for x in 0..<w { pp[r + x] = sp[y * w + x] }
              vDSP_conv(pp.baseAddress!, 1, k, 1, op.baseAddress! + y * w, 1, vDSP_Length(w), vDSP_Length(n))
            }
          }
        }
      }
      return out
    }
    var t = rows(a, W, H)
    var tt = [Float](repeating: 0, count: W * H)
    vDSP_mtrans(t, 1, &tt, 1, vDSP_Length(W), vDSP_Length(H))
    t = rows(tt, H, W)
    vDSP_mtrans(t, 1, &a, 1, vDSP_Length(H), vDSP_Length(W))
  }

  public func fill(_ rule: FillRule = .nonzero) {
    let p = path.copy()!
    draw(st.fill) { c in c.addPath(p); c.clip(using: rule == .evenodd ? .evenOdd : .winding) }
  }
  public func stroke() {
    let w = st.lineWidth * sqrt(abs(st.ctm.a * st.ctm.d - st.ctm.b * st.ctm.c))
    var p: CGPath = path.copy()!
    if !st.dash.isEmpty {
      let scale = sqrt(abs(st.ctm.a * st.ctm.d - st.ctm.b * st.ctm.c))
      p = p.copy(dashingWithPhase: 0, lengths: st.dash.map { CGFloat($0 * scale) })
    }
    let outline = p.copy(strokingWithWidth: w, lineCap: st.lineCap, lineJoin: st.lineJoin, miterLimit: 10)
    draw(st.stroke) { c in c.addPath(outline); c.clip(using: .winding) }
  }
  public func clip(_ rule: FillRule = .nonzero) {
    cg.addPath(path); cg.clip(using: rule == .evenodd ? .evenOdd : .winding)
  }
  public func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    let keep = path, kc = cur, ks = subStart
    beginPath(); rect(x, y, w, h); fill()
    path = keep; cur = kc; subStart = ks
  }
  public func strokeRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    let keep = path, kc = cur, ks = subStart
    beginPath(); rect(x, y, w, h); stroke()
    path = keep; cur = kc; subStart = ks
  }

  // MARK: styles

  public func createLinearGradient(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Gradient2D { Gradient2D(.linear(x0, y0, x1, y1)) }
  public func createRadialGradient(_ x0: Double, _ y0: Double, _ r0: Double, _ x1: Double, _ y1: Double, _ r1: Double) -> Gradient2D {
    Gradient2D(.radial(x0, y0, r0, x1, y1, r1))
  }
  /* an RGBA (unpremultiplied, as getImageData gives) tile, repeated */
  public func createPattern(rgba: [UInt8], width w: Int, height h: Int) -> Pattern2D {
    var pm = rgba
    for i in stride(from: 0, to: pm.count, by: 4) {
      let a = Int(pm[i + 3])
      /* the canvas premultiplies on putImageData, rounding */
      for j in 0..<3 { pm[i + j] = UInt8((Int(pm[i + j]) * a + 127) / 255) }
    }
    let provider = CGDataProvider(data: Data(pm) as CFData)!
    let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Pattern2D(img)
  }
  // MARK: images and text

  /* drawImage(source, dx, dy, dw, dh) in the current transform, at globalAlpha */
  public func drawImage(_ img: CGImage, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    cg.saveGState()
    cg.setAlpha(st.alpha)
    cg.concatenate(st.ctm)
    cg.translateBy(x: x, y: y + h); cg.scaleBy(x: 1, y: -1)
    cg.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    cg.restoreGState()
  }
  public func drawImage(_ src: Canvas2D, _ x: Double, _ y: Double, _ w: Double, _ h: Double) { drawImage(src.image(), x, y, w, h) }
  /* drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh): the source rect (cut to whole pixels and the image) into the dest */
  public func drawImage(_ img: CGImage, _ sx: Double, _ sy: Double, _ sw: Double, _ sh: Double, _ dx: Double, _ dy: Double, _ dw: Double, _ dh: Double) {
    let x0 = Swift.max(0, sx.rounded(.down)), y0 = Swift.max(0, sy.rounded(.down)), x1 = Swift.min(Double(img.width), (sx + sw).rounded(.up)), y1 = Swift.min(Double(img.height), (sy + sh).rounded(.up))
    guard x1 > x0, y1 > y0, let c = img.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return }
    let kx = dw / sw, ky = dh / sh
    drawImage(c, dx + (x0 - sx) * kx, dy + (y0 - sy) * ky, (x1 - x0) * kx, (y1 - y0) * ky)
  }
  /* ellipse(x, y, rx, ry, rotation, a0, a1, ccw), as the canvas's (rotation 0 here) */
  public func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ ccw: Bool = false) {
    let keep = st.ctm
    st.ctm = CGAffineTransform(a: rx, b: 0, c: 0, d: ry, tx: x, ty: y).concatenating(keep)
    arc(0, 0, 1, a0, a1, ccw)
    st.ctm = keep
  }
  nonisolated(unsafe) private static var fonts: [Double: CTFont] = [:]
  private static let fontLock = NSLock()
  static func font(_ size: Double, _ weight: CGFloat) -> CTFont {
    fontLock.lock(); defer { fontLock.unlock() }
    let key = size * 10 + Double(weight)
    if let f = fonts[key] { return f }
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let d = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight] as CFDictionary] as CFDictionary)
    let f = CTFontCreateWithFontDescriptor(d, size, nil)
    fonts[key] = f
    return f
  }
  /* fillText with textAlign 'center' and textBaseline 'middle', a bold system face of `size` px (the
     page's 700 system-ui, which Chrome on Apple resolves to the same face: its widths agree to 0.005 px) */
  public func fillTextCentered(_ text: String, _ x: Double, _ y: Double, size: Double, weight: CGFloat = 0.4) {
    guard case .color(let c) = st.fill else { return }
    let font = Canvas2D.font(size, weight)
    let attr = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: cgColor(c)] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attr))
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    let asc = CTFontGetAscent(font), desc = CTFontGetDescent(font)
    cg.saveGState()
    cg.setAlpha(st.alpha)
    cg.concatenate(st.ctm)
    /* 'middle' is the middle of the em square: the font's ascent and descent scaled to the em (as Blink
       does; measured against Chrome's measureText, 8.475 px above the baseline at 26.4 px) */
    let mid = (asc - desc) / 2 * size / (asc + desc)
    cg.translateBy(x: x - w / 2, y: y + mid); cg.scaleBy(x: 1, y: -1)
    cg.setShouldSmoothFonts(false); cg.setAllowsFontSmoothing(false)
    cg.textPosition = .zero
    CTLineDraw(line, cg)
    cg.restoreGState()
  }
}
#endif
