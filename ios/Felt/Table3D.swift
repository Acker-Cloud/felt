/* the 3D view (index.html 4o) on Metal: the camera is V3 (FeltSim, the page's to the bit), the table is V3Geo (the 2D
   art laid on the bed and the tops, the faces and posts), and the page's programs in MSL: tex (the planes, the tops cut
   where the art's alpha is under 0.75), mesh (the faces unlit, the posts lit), shadow (drawCast's two pools on the bed)
   and ball (each ball ray-traced in a quad: its paint, caps and number, the lamp's diffuse and highlights, the cloth's
   bounce, the rim). Not yet: the room, the cue, the overlays, the flashes, the loupe, the drops. */
import FeltRender
import FeltSim
import MetalKit
import SwiftUI

private let SHADERS = """
#include <metal_stdlib>
using namespace metal;
struct TexIn { float3 p [[attribute(0)]]; float2 uv [[attribute(1)]]; };
struct TexOut { float4 pos [[position]]; float2 v; };
vertex TexOut texV(TexIn i [[stage_in]], constant float4x4 &M [[buffer(1)]]) { TexOut o; o.v = i.uv; o.pos = M * float4(i.p, 1.0); return o; }
fragment float4 texF(TexOut i [[stage_in]], texture2d<float> T [[texture(0)]], sampler s [[sampler(0)]], constant float &rail [[buffer(0)]]) {
  float4 c = T.sample(s, i.v); if (rail > 0.5 && c.a < 0.75) discard_fragment(); return float4(c.rgb, 1.0);
}
struct MeshIn { float3 p [[attribute(0)]]; float3 n [[attribute(1)]]; float4 c [[attribute(2)]]; };
struct MeshOut { float4 pos [[position]]; float4 vc; float3 vn; float3 vp; };
vertex MeshOut meshV(MeshIn i [[stage_in]], constant float4x4 &M [[buffer(1)]]) { MeshOut o; o.vc = i.c; o.vn = i.n; o.vp = i.p; o.pos = M * float4(i.p, 1.0); return o; }
struct MeshU { float3 L; float3 E; float lit; float alpha; };
fragment float4 meshF(MeshOut i [[stage_in]], constant MeshU &u [[buffer(0)]]) {
  if (u.lit < 0.5) return float4(i.vc.rgb, i.vc.a * u.alpha);
  float3 n = normalize(i.vn), l = normalize(u.L - i.vp), v = normalize(u.E - i.vp), h = normalize(l + v);
  float d = max(dot(n, l), 0.0), s = pow(max(dot(n, h), 0.0), 36.0);
  return float4(i.vc.rgb * (0.38 + 0.72 * d) + 0.22 * s, i.vc.a * u.alpha);
}
struct ShU { float4x4 M; float3 S; float ext; float2 A; float2 B; float R; float grow; float ao; float ca; };
struct ShOut { float4 pos [[position]]; float2 vw; };
vertex ShOut shadowV(uint id [[vertex_id]], constant float2 *q [[buffer(0)]], constant ShU &u [[buffer(1)]]) {
  ShOut o; float3 w = u.S + float3(q[id] * u.ext, 0.0); o.vw = w.xy; o.pos = u.M * float4(w, 1.0); return o;
}
fragment float4 shadowF(ShOut i [[stage_in]], constant ShU &u [[buffer(1)]]) {
  float d1 = length(i.vw - u.A) / u.R, d2 = length(i.vw - u.B) / (u.R * u.grow * 1.5);
  float a1 = u.ao * 0.55 * (1.0 - smoothstep(0.8, 1.16, d1));
  float a2 = u.ca * (d2 < 0.5 ? mix(0.56, 0.36, d2 / 0.5) : d2 < 0.78 ? mix(0.36, 0.1, (d2 - 0.5) / 0.28) : d2 < 1.0 ? mix(0.1, 0.0, (d2 - 0.78) / 0.22) : 0.0);
  float a = 1.0 - (1.0 - a1) * (1.0 - a2);
  if (a < 0.004) discard_fragment();
  return float4(0.0, 0.0, 0.0, a);
}
struct BallU { float4x4 V; float4x4 P; float3x3 Vi; float3 C; float3 Cv; float R; float3 Ax0; float3 Ax1; float3 Ax2; float3 base;
  float4 cap0; float4 cap1; float4 cap2; float3 capC0; float3 capC1; float3 capC2; float num; float3 Lv; float3 bounce; float alpha; float rim; };
struct BallOut { float4 pos [[position]]; float3 vp; float2 vq; };
vertex BallOut ballV(uint id [[vertex_id]], constant float2 *q [[buffer(0)]], constant BallU &u [[buffer(1)]]) {
  BallOut o; float4 c = u.V * float4(u.C, 1.0); float3 pv = c.xyz + float3(q[id] * u.R * 1.35, 0.0); o.vp = pv; o.vq = q[id] * 1.35; o.pos = u.P * float4(pv, 1.0); return o;
}
float3 paintCap(float3 c, float4 cp, float3 col, float3 l) { if (cp.w < 0.5) return c; float a = cp.x < 0.5 ? l.x : cp.x < 1.5 ? l.y : l.z; return abs(a) >= cp.y ? col : c; }
struct BallFrag { float4 color [[color(0)]]; float depth [[depth(any)]]; };
fragment BallFrag ballF(BallOut i [[stage_in]], constant BallU &u [[buffer(1)]], texture2d<float> N [[texture(0)]], sampler s [[sampler(0)]]) {
  float3 d = normalize(i.vp);
  float b = dot(d, u.Cv), pr2 = dot(u.Cv, u.Cv) - b * b, pr = sqrt(max(pr2, 0.0)), edge = u.R - pr, fw = max(fwidth(pr), 1e-6);
  float cov = clamp(edge / fw + 0.5, 0.0, 1.0);
  if (cov <= 0.0) discard_fragment();
  float disc = max(u.R * u.R - pr2, 0.0), t = b - sqrt(disc);
  float3 hit = d * t, nv = (hit - u.Cv) / u.R;
  float3 nr = u.Vi * nv, np = float3(nr.x, nr.y, -nr.z), l = float3(dot(u.Ax0, np), dot(u.Ax1, np), dot(u.Ax2, np));
  float3 c = u.base;
  c = paintCap(c, u.cap0, u.capC0, l); c = paintCap(c, u.cap1, u.capC1, l); c = paintCap(c, u.cap2, u.capC2, l);
  if (u.num > 0.5 && abs(l.z) >= 0.866) {
    float uu = l.x / (u.num > 9.5 ? 0.82 : 1.0), w = l.y * sign(l.z);
    float2 cell = float2(uu + 0.5, w + 0.5);
    if (cell.x > 0.0 && cell.x < 1.0 && cell.y > 0.0 && cell.y < 1.0) c = mix(c, float3(0.078), N.sample(s, float2((u.num + cell.x) / 16.0, cell.y)).a);
  }
  float3 lv = normalize(u.Lv - hit), vv = -d, h = normalize(lv + vv);
  float df = max(dot(nv, lv), 0.0), sp = pow(max(dot(nv, h), 0.0), 120.0), sh = pow(max(dot(nv, h), 0.0), 14.0), fr = pow(1.0 - max(dot(nv, vv), 0.0), 3.0);
  float3 col = c * (0.3 + 0.78 * df) + u.bounce * 0.2 * max(-np.z, 0.0) * c + float3(1.0) * (0.95 * sp + 0.07 * sh) + float3(0.06) * fr;
  col *= 1.0 - 0.35 * smoothstep(0.2, 0.95, -np.z);
  if (u.rim > 0.5 && edge < u.R * 0.09) col = mix(col, float3(0.77), 0.85);
  float4 cl = u.P * float4(hit, 1.0);
  BallFrag o; o.color = float4(col, u.alpha * cov); o.depth = clamp(cl.z / cl.w, 0.0, 1.0); return o;
}
"""

/* the page's matrices are GL's (clip z -w..w); Metal's clip z is 0..w */
private func glToMetal(_ m: [Double]) -> simd_float4x4 {
  var a = simd_float4x4(); for c in 0..<4 { a[c] = SIMD4<Float>(Float(m[c * 4]), Float(m[c * 4 + 1]), Float(m[c * 4 + 2]), Float(m[c * 4 + 3])) }
  var z = matrix_identity_float4x4; z[2][2] = 0.5; z[3][2] = 0.5
  return z * a
}
private func m4(_ m: [Double]) -> simd_float4x4 { var a = simd_float4x4(); for c in 0..<4 { a[c] = SIMD4<Float>(Float(m[c * 4]), Float(m[c * 4 + 1]), Float(m[c * 4 + 2]), Float(m[c * 4 + 3])) }; return a }
private func f3(_ v: [Double]) -> SIMD3<Float> { SIMD3<Float>(Float(v[0]), Float(v[1]), Float(v[2])) }
private func rgb(_ s: String) -> SIMD3<Float> { let c = RGBA(css: s); return SIMD3<Float>(Float(c.r), Float(c.g), Float(c.b)) }

struct MeshU { var L: SIMD3<Float>; var E: SIMD3<Float>; var lit: Float; var alpha: Float }
struct ShU { var M: simd_float4x4; var S: SIMD3<Float>; var ext: Float; var A: SIMD2<Float>; var B: SIMD2<Float>; var R: Float; var grow: Float; var ao: Float; var ca: Float }
struct BallU {
  var V: simd_float4x4; var P: simd_float4x4; var Vi: simd_float3x3; var C: SIMD3<Float>; var Cv: SIMD3<Float>; var R: Float
  var Ax0: SIMD3<Float>; var Ax1: SIMD3<Float>; var Ax2: SIMD3<Float>; var base: SIMD3<Float>
  var cap0: SIMD4<Float>; var cap1: SIMD4<Float>; var cap2: SIMD4<Float>; var capC0: SIMD3<Float>; var capC1: SIMD3<Float>; var capC2: SIMD3<Float>
  var num: Float; var Lv: SIMD3<Float>; var bounce: SIMD3<Float>; var alpha: Float; var rim: Float
}

@MainActor final class Renderer3D: NSObject, MTKViewDelegate {
  let model: TableModel
  let device: MTLDevice, queue: MTLCommandQueue
  var texP: MTLRenderPipelineState!, meshP: MTLRenderPipelineState!, shadowP: MTLRenderPipelineState!, ballP: MTLRenderPipelineState!
  var depthOn: MTLDepthStencilState!, depthRead: MTLDepthStencilState!
  var sampler: MTLSamplerState!
  var geo: (key: String, tex: MTLTexture, planes: MTLBuffer, nBed: Int, nTop: Int, mesh: MTLBuffer, nFaces: Int, nPosts: Int, bounce: [Double])?
  var numTex: MTLTexture!
  let quad: [SIMD2<Float>] = [[-1, -1], [1, -1], [-1, 1], [1, 1]]

  init?(model: TableModel) {
    guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
    self.model = model; device = d; queue = q
    super.init()
    do { try build() } catch { print("3D: \(error)"); return nil }
  }
  func build() throws {
    let lib = try device.makeLibrary(source: SHADERS, options: nil)
    func pipe(_ v: String, _ f: String, _ vd: MTLVertexDescriptor?, blend: Bool) throws -> MTLRenderPipelineState {
      let p = MTLRenderPipelineDescriptor()
      p.vertexFunction = lib.makeFunction(name: v); p.fragmentFunction = lib.makeFunction(name: f); p.vertexDescriptor = vd
      p.colorAttachments[0].pixelFormat = .bgra8Unorm; p.depthAttachmentPixelFormat = .depth32Float; p.rasterSampleCount = 4
      if blend { let c = p.colorAttachments[0]!; c.isBlendingEnabled = true; c.sourceRGBBlendFactor = .sourceAlpha; c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.sourceAlphaBlendFactor = .sourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha }
      return try device.makeRenderPipelineState(descriptor: p)
    }
    let tv = MTLVertexDescriptor()
    tv.attributes[0].format = .float3; tv.attributes[0].offset = 0; tv.attributes[1].format = .float2; tv.attributes[1].offset = 12; tv.layouts[0].stride = 20
    tv.attributes[0].bufferIndex = 0; tv.attributes[1].bufferIndex = 0
    let mv = MTLVertexDescriptor()
    mv.attributes[0].format = .float3; mv.attributes[0].offset = 0; mv.attributes[1].format = .float3; mv.attributes[1].offset = 12; mv.attributes[2].format = .float4; mv.attributes[2].offset = 24
    for i in 0..<3 { mv.attributes[i].bufferIndex = 0 }
    mv.layouts[0].stride = 40
    texP = try pipe("texV", "texF", tv, blend: false)
    meshP = try pipe("meshV", "meshF", mv, blend: true)
    shadowP = try pipe("shadowV", "shadowF", nil, blend: true)
    ballP = try pipe("ballV", "ballF", nil, blend: true)
    let dd = MTLDepthStencilDescriptor(); dd.depthCompareFunction = .lessEqual; dd.isDepthWriteEnabled = true
    depthOn = device.makeDepthStencilState(descriptor: dd)
    dd.isDepthWriteEnabled = false
    depthRead = device.makeDepthStencilState(descriptor: dd)
    let sd = MTLSamplerDescriptor(); sd.minFilter = .linear; sd.magFilter = .linear; sd.mipFilter = .linear; sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge; sd.maxAnisotropy = 8
    sampler = device.makeSamplerState(descriptor: sd)
    numTex = texture(V3Art.numbers())
  }
  func texture(_ img: CGImage) -> MTLTexture? {
    let l = MTKTextureLoader(device: device)
    return try? l.newTexture(cgImage: img, options: [.generateMipmaps: true, .SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue, .textureStorageMode: MTLStorageMode.private.rawValue])
  }
  func geometry() -> (key: String, tex: MTLTexture, planes: MTLBuffer, nBed: Int, nTop: Int, mesh: MTLBuffer, nFaces: Int, nPosts: Int, bounce: [Double])? {
    let s = model.sim, d = model.dress, key = "\(s.TL)|\(s.TW)|\(s.POCKET_R)|\(s.BALL_R)|\(d)"
    if let g = geo, g.key == key { return g }
    let G = V3Geo.build(s, look: TableLook.of(d))
    guard let tex = texture(G.image), let pb = device.makeBuffer(bytes: G.planes, length: G.planes.count * 4), let mb = device.makeBuffer(bytes: G.mesh.isEmpty ? [0] : G.mesh, length: max(4, G.mesh.count * 4)) else { return nil }
    geo = (key, tex, pb, G.nBed, G.nTop, mb, G.nFaces, G.nPosts, G.bounce)
    return geo
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  func draw(in view: MTKView) {
    guard let G = geometry(), let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
          let cb = queue.makeCommandBuffer() else { return }
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.016, blue: 0.016, alpha: 1)
    guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
    let s = model.sim, R = s.BALL_R, W = Double(view.bounds.width), H = Double(view.bounds.height)
    let box = V3.Box(left: 0, top: 0, width: W, height: H)
    let cue = model.cue, px = cue?.x ?? s.TL * 0.25, py = cue?.y ?? s.TW / 2
    let C = V3.pose(s, box, px: px, py: py, yaw: model.aim, pitch: model.v3Pitch, dist: model.v3Dist)
    model.v3Cam = (C, box)
    let M = glToMetal(C.M), P = glToMetal(C.P), Vm = m4(C.V)
    var Mv = M
    e.setDepthStencilState(depthOn)
    /* the bed and the tops */
    e.setRenderPipelineState(texP)
    e.setVertexBuffer(G.planes, offset: 0, index: 0); e.setVertexBytes(&Mv, length: 64, index: 1)
    e.setFragmentTexture(G.tex, index: 0); e.setFragmentSamplerState(sampler, index: 0)
    var rail: Float = 0
    e.setFragmentBytes(&rail, length: 4, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: G.nBed)
    rail = 1
    e.setFragmentBytes(&rail, length: 4, index: 0); e.drawPrimitives(type: .triangle, vertexStart: G.nBed, vertexCount: G.nTop)
    /* the faces and posts */
    let lamp = [s.TL / 2, s.TW / 2, -BallPainter.LAMP_H]
    if G.nFaces + G.nPosts > 0 {
      e.setRenderPipelineState(meshP)
      e.setVertexBuffer(G.mesh, offset: 0, index: 0); e.setVertexBytes(&Mv, length: 64, index: 1)
      var u = MeshU(L: f3(lamp), E: f3(C.Er), lit: 0, alpha: 1)
      e.setFragmentBytes(&u, length: MemoryLayout<MeshU>.stride, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: G.nFaces)
      if G.nPosts > 0 { u.lit = 1; e.setFragmentBytes(&u, length: MemoryLayout<MeshU>.stride, index: 0); e.drawPrimitives(type: .triangle, vertexStart: G.nFaces, vertexCount: G.nPosts) }
    }
    /* the balls on the table, far to near */
    let balls = (model.rolling?.balls ?? model.balls).filter { $0.on }
    var vis = balls.map { b -> (Ball, Double) in (b, V3.dot(V3.sub([b.x, b.y, -R], C.Er), C.f)) }.filter { $0.1 > V3.NEAR + R }
    vis.sort { $0.1 > $1.1 }
    /* their shadows on the bed (drawCast's lamp and lean) */
    e.setDepthStencilState(depthRead)
    e.setRenderPipelineState(shadowP)
    var q = quad
    e.setVertexBytes(&q, length: 32, index: 0)
    let key = [-LIGHT[0], -LIGHT[1]]
    for (o, _) in vis {
      let dx = o.x - s.TL / 2, dy = o.y - s.TW / 2, t = R / (BallPainter.LAMP_H - R), lean = R * 0.2
      let bx = o.x + dx * t + key[0] * lean, by = o.y + dy * t + key[1] * lean, grow = 1 + 0.1 * min(1, JSMath.hypot(dx, dy) / 1.2)
      var u = ShU(M: M, S: SIMD3<Float>(Float((o.x + bx) / 2), Float((o.y + by) / 2), -0.0008), ext: Float(R * 1.6 * grow + JSMath.hypot(bx - o.x, by - o.y)),
                  A: SIMD2<Float>(Float(o.x), Float(o.y)), B: SIMD2<Float>(Float(bx), Float(by)), R: Float(R), grow: Float(grow), ao: 1, ca: 1)
      e.setVertexBytes(&u, length: MemoryLayout<ShU>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<ShU>.stride, index: 1)
      e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    /* the balls */
    e.setDepthStencilState(depthOn)
    e.setRenderPipelineState(ballP)
    e.setVertexBytes(&q, length: 32, index: 0)
    e.setFragmentTexture(numTex, index: 0); e.setFragmentSamplerState(sampler, index: 0)
    let toV = { (p: [Double]) -> SIMD3<Float> in let V = C.V; return SIMD3<Float>((0..<3).map { Float(V[$0] * p[0] + V[4 + $0] * p[1] + V[8 + $0] * p[2] + V[12 + $0]) }) }
    let Vi = simd_float3x3(f3(C.r), f3(C.u), -f3(C.f))
    let painter = model.ballPainter(upright: true, scale: view.contentScaleFactor)
    for (o, _) in vis {
      let p = painter.paintOf(o.n), m = model.orient[o.n] ?? IDENT, Cw = [o.x, o.y, -R]
      func cap(_ i: Int) -> (SIMD4<Float>, SIMD3<Float>) {
        guard i < p.caps.count else { return (SIMD4<Float>(0, 2, 0, 0), SIMD3<Float>(0, 0, 0)) }
        let c = p.caps[i]; return (SIMD4<Float>(Float(c.0), Float(c.1), 0, 1), rgb(c.2))
      }
      let c0 = cap(0), c1 = cap(1), c2 = cap(2)
      var u = BallU(V: Vm, P: P, Vi: Vi, C: f3(Cw), Cv: toV(Cw), R: Float(R), Ax0: SIMD3<Float>(Float(m[0]), Float(m[3]), Float(m[6])), Ax1: SIMD3<Float>(Float(m[1]), Float(m[4]), Float(m[7])),
                    Ax2: SIMD3<Float>(Float(m[2]), Float(m[5]), Float(m[8])), base: rgb(p.base), cap0: c0.0, cap1: c1.0, cap2: c2.0, capC0: c0.1, capC1: c1.1, capC2: c2.1,
                    num: Float(o.n > 0 && o.n < 16 ? o.n : 0), Lv: toV(lamp), bounce: f3(G.bounce), alpha: 1, rim: painter.rim3(o.n) ? 1 : 0)
      e.setVertexBytes(&u, length: MemoryLayout<BallU>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<BallU>.stride, index: 1)
      e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    e.endEncoding()
    cb.present(drawable)
    cb.commit()
  }
}

/* the 3D table on screen: an MTKView drawing every frame while visible */
struct Table3DView: UIViewRepresentable {
  let model: TableModel
  func makeCoordinator() -> Renderer3D? { Renderer3D(model: model) }
  func makeUIView(context: Context) -> MTKView {
    let v = MTKView(frame: .zero, device: context.coordinator?.device)
    v.colorPixelFormat = .bgra8Unorm; v.depthStencilPixelFormat = .depth32Float; v.sampleCount = 4
    v.preferredFramesPerSecond = 60; v.delegate = context.coordinator; v.isUserInteractionEnabled = false
    return v
  }
  func updateUIView(_ v: MTKView, context: Context) {}
}
