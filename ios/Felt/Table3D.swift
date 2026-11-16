/* the 3D view (index.html 4o) on Metal: the camera is V3 (FeltSim, the page's to the bit), the table is V3Geo (the 2D
   art laid on the bed and the tops, the faces and posts), and the page's programs in MSL: tex (the planes, the tops cut
   where the art's alpha is under 0.75), mesh (the faces unlit, the posts lit), shadow (drawCast's two pools on the bed)
   and ball (each ball ray-traced in a quad: its paint, caps and number, the lamp's diffuse and highlights, the cloth's
   bounce, the rim). Then the room (v3RoomTex: the wall, the floor, the neighbours' cards, the lamp), the cue, the
   overlays (v3Overlays through Sink3D: the 2D code's paths as ribbons and fills at one height each), the hit flashes, the
   loupe (v3Loupe) and the drops (v3Drops). */
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
struct MeshV { float4x4 M; float4x4 W; };
vertex MeshOut meshV(MeshIn i [[stage_in]], constant MeshV &u [[buffer(1)]]) {
  MeshOut o; float4 w = u.W * float4(i.p, 1.0); o.vc = i.c; o.vn = float3x3(u.W[0].xyz, u.W[1].xyz, u.W[2].xyz) * i.n; o.vp = w.xyz; o.pos = u.M * w; return o;
}
struct OverIn { float3 P [[attribute(0)]]; float3 Q [[attribute(1)]]; float3 N [[attribute(2)]]; float2 sw [[attribute(3)]]; float4 c [[attribute(4)]]; };
struct OverOut { float4 pos [[position]]; float4 vc; float vs; float vw; };
struct OverU { float4x4 M; float2 VP; };
vertex OverOut overV(OverIn i [[stage_in]], constant OverU &u [[buffer(1)]]) {
  OverOut o; float4 p = u.M * float4(i.P, 1.0);
  o.vc = i.c; o.vs = i.sw.x; o.vw = i.sw.y;
  if (i.sw.y <= 0.0) { o.pos = p; return o; }
  float4 q = u.M * float4(i.Q, 1.0), n = u.M * float4(i.N, 1.0);
  float2 sp = p.xy / p.w * u.VP, t0 = sp - q.xy / q.w * u.VP, t1 = n.xy / n.w * u.VP - sp;
  bool h0 = dot(t0, t0) > 1e-8, h1 = dot(t1, t1) > 1e-8;
  t0 = h0 ? normalize(t0) : float2(0.0); t1 = h1 ? normalize(t1) : float2(0.0);
  if (!h0) t0 = t1; if (!h1) t1 = t0;
  float2 n0 = float2(-t0.y, t0.x), n1 = float2(-t1.y, t1.x), m = n0 + n1;
  m = dot(m, m) > 1e-8 ? normalize(m) : n1;
  float hw = i.sw.y * 0.5 + 1.0, l = hw / max(dot(m, n1), 0.4);
  p.xy += m * l * i.sw.x / u.VP * p.w;
  o.pos = p; return o;
}
struct FxU { float4x4 V; float4x4 P; float3 C; float ext; float kind; float rad; float lw; float4 col; };
struct FxOut { float4 pos [[position]]; float2 vq; };
vertex FxOut fxV(uint id [[vertex_id]], constant float2 *q [[buffer(0)]], constant FxU &u [[buffer(1)]]) {
  FxOut o; float4 c = u.V * float4(u.C, 1.0); o.vq = q[id] * u.ext; o.pos = u.P * float4(c.xyz + float3(o.vq, 0.0), 1.0); return o;
}
fragment float4 fxF(FxOut i [[stage_in]], constant FxU &u [[buffer(1)]]) {
  float d = length(i.vq), a;
  if (u.kind > 0.5) a = u.col.a * clamp(1.0 - d / u.rad, 0.0, 1.0);
  else a = u.col.a * clamp(u.lw + 0.5 - abs(d - u.rad) / max(fwidth(d), 1e-7), 0.0, 1.0);
  if (a < 0.002) discard_fragment();
  return float4(u.col.rgb * a, a);
}
struct LensU { float4 box; float r; float pad; float sc; float a; };
struct LensOut { float4 pos [[position]]; float2 vq; };
vertex LensOut lensV(uint id [[vertex_id]], constant float2 *q [[buffer(0)]], constant LensU &u [[buffer(1)]]) { LensOut o; o.vq = q[id]; o.pos = float4(u.box.xy + q[id] * u.box.zw, 0.0, 1.0); return o; }
fragment float4 lensF(LensOut i [[stage_in]], constant LensU &u [[buffer(1)]], texture2d<float> T [[texture(0)]], sampler s [[sampler(0)]]) {
  float2 p = i.vq * (u.r + u.pad);
  float d = length(p), w = max(fwidth(d), 1e-4), ds = length(p + float2(0.0, 3.0 * u.sc));
  float inside = clamp(u.r - d + 0.5 * w, 0.0, w) / w;
  float2 uv = p / u.r * 0.5 + 0.5; uv.y = 1.0 - uv.y;
  float3 c = T.sample(s, uv).rgb;
  float bright = clamp(0.625 * u.sc + 0.5 - abs(d - u.r) / w, 0.0, 1.0) * 0.85, darkR = clamp(1.5 * u.sc + 0.5 - abs(d - u.r - 0.5 * u.sc) / w, 0.0, 1.0) * 0.45;
  float4 col = float4(c * inside, inside);
  col = darkR * float4(0.0, 0.0, 0.0, 1.0) + (1.0 - darkR) * col;
  col = bright * float4(1.0) + (1.0 - bright) * col;
  float sh = 0.55 * (1.0 - smoothstep(u.r - 4.0 * u.sc, u.r + 14.0 * u.sc, ds)) * (1.0 - col.a);
  col = float4(col.rgb, col.a + sh);
  return col * u.a;
}
struct CardIn { float3 p [[attribute(0)]]; float2 uv [[attribute(1)]]; float4 c [[attribute(2)]]; };
struct CardOut { float4 pos [[position]]; float2 v; float4 vc; };
vertex CardOut cardV(CardIn i [[stage_in]], constant float4x4 &M [[buffer(1)]]) { CardOut o; o.v = i.uv; o.vc = i.c; o.pos = M * float4(i.p, 1.0); return o; }
fragment float4 cardF(CardOut i [[stage_in]], texture2d<float> T [[texture(0)]], sampler s [[sampler(0)]]) { return T.sample(s, i.v) * i.vc; }
fragment float4 overF(OverOut i [[stage_in]]) {
  float a = 1.0;
  if (i.vw > 0.0) { float d = abs(i.vs) * (i.vw * 0.5 + 1.0); a = clamp(i.vw * 0.5 + 0.5 - d, 0.0, 1.0); }
  return float4(i.vc.rgb * i.vc.a * a, i.vc.a * a);
}
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
  float4 cap0; float4 cap1; float4 cap2; float3 capC0; float3 capC1; float3 capC2; float num; float3 Lv; float3 bounce; float alpha; float rim; float4 hole; float3 bedN; float dark; float mark; };
struct BallOut { float4 pos [[position]]; float3 vp; float2 vq; };
vertex BallOut ballV(uint id [[vertex_id]], constant float2 *q [[buffer(0)]], constant BallU &u [[buffer(1)]]) {
  BallOut o; float4 c = u.V * float4(u.C, 1.0); float3 pv = c.xyz + float3(q[id] * u.R * 1.35, 0.0); o.vp = pv; o.vq = q[id] * 1.35; o.pos = u.P * float4(pv, 1.0); return o;
}
float3 paintCap(float3 c, float4 cp, float3 col, float3 l) { if (cp.w < 0.5) return c; float a = cp.x < 0.5 ? l.x : cp.x < 1.5 ? l.y : l.z; return abs(a) >= cp.y ? col : c; }
struct BallFrag { float4 color [[color(0)]]; float depth [[depth(any)]]; };
fragment BallFrag ballF(BallOut i [[stage_in]], constant BallU &u [[buffer(1)]], texture2d<float> N [[texture(0)]], texture2d<float> K [[texture(1)]], sampler s [[sampler(0)]]) {
  float3 d = normalize(i.vp);
  float b = dot(d, u.Cv), pr2 = dot(u.Cv, u.Cv) - b * b, pr = sqrt(max(pr2, 0.0)), edge = u.R - pr, fw = max(fwidth(pr), 1e-6);
  float cov = clamp(edge / fw + 0.5, 0.0, 1.0);
  if (cov <= 0.0) discard_fragment();
  float disc = max(u.R * u.R - pr2, 0.0), t = b - sqrt(disc);
  float3 hit = d * t, nv = (hit - u.Cv) / u.R, dp = hit;
  /* a ball dropping into a pocket: under the bed it is seen only through the hole, at the depth where the eye's ray
     crosses the bed */
  if (u.hole.w > 0.0 && dot(hit - u.hole.xyz, u.bedN) > 0.0) {
    float dn = dot(d, u.bedN);
    if (dn <= 1e-6) discard_fragment();
    float3 pb = d * (dot(u.hole.xyz, u.bedN) / dn);
    if (length(pb - u.hole.xyz) > u.hole.w) discard_fragment();
    dp = pb * 0.996;
  }
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
  /* the colour-blind mark (settings.marks): an upright badge 0.6 of the ball across, on its face to the eye */
  if (u.mark > -0.5 && length(i.vq) < 0.62) {
    float2 m = i.vq / 1.24 + 0.5; m.y = 1.0 - m.y;
    float4 k = K.sample(s, float2((u.mark + m.x) / 32.0, m.y));
    col = mix(col, k.rgb, k.a);
  }
  if (u.rim > 0.5 && edge < u.R * 0.09) col = mix(col, float3(0.77), 0.85);
  col *= 1.0 - u.dark;
  float4 cl = u.P * float4(dp, 1.0);
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
struct MeshV { var M: simd_float4x4; var W: simd_float4x4 }
struct OverU { var M: simd_float4x4; var VP: SIMD2<Float> }
struct LensU { var box: SIMD4<Float>; var r: Float; var pad: Float; var sc: Float; var a: Float }
struct FxU { var V: simd_float4x4; var P: simd_float4x4; var C: SIMD3<Float>; var ext: Float; var kind: Float; var rad: Float; var lw: Float; var col: SIMD4<Float> }
struct ShU { var M: simd_float4x4; var S: SIMD3<Float>; var ext: Float; var A: SIMD2<Float>; var B: SIMD2<Float>; var R: Float; var grow: Float; var ao: Float; var ca: Float }
struct BallU {
  var V: simd_float4x4; var P: simd_float4x4; var Vi: simd_float3x3; var C: SIMD3<Float>; var Cv: SIMD3<Float>; var R: Float
  var Ax0: SIMD3<Float>; var Ax1: SIMD3<Float>; var Ax2: SIMD3<Float>; var base: SIMD3<Float>
  var cap0: SIMD4<Float>; var cap1: SIMD4<Float>; var cap2: SIMD4<Float>; var capC0: SIMD3<Float>; var capC1: SIMD3<Float>; var capC2: SIMD3<Float>
  var num: Float; var Lv: SIMD3<Float>; var bounce: SIMD3<Float>; var alpha: Float; var rim: Float
  var hole = SIMD4<Float>(0, 0, 0, 0); var bedN = SIMD3<Float>(0, 0, 0); var dark: Float = 0; var mark: Float = -1
}

@MainActor final class Renderer3D: NSObject, MTKViewDelegate {
  let model: TableModel
  let device: MTLDevice, queue: MTLCommandQueue
  var lensP: MTLRenderPipelineState!
  var fxP: MTLRenderPipelineState!, noDepth: MTLDepthStencilState!
  var cardP: MTLRenderPipelineState!, cards: (tex: MTLTexture, at: [String: [Double]])?
  var overP: MTLRenderPipelineState!, cueBuf: (key: String, b: MTLBuffer, n: Int)?
  var texP: MTLRenderPipelineState!, meshP: MTLRenderPipelineState!, shadowP: MTLRenderPipelineState!, ballP: MTLRenderPipelineState!
  var depthOn: MTLDepthStencilState!, depthRead: MTLDepthStencilState!
  var sampler: MTLSamplerState!
  var geo: (key: String, tex: MTLTexture, planes: MTLBuffer, nBed: Int, nTop: Int, mesh: MTLBuffer, nFaces: Int, nPosts: Int, bounce: [Double], outline: [[Double]])?
  /* the room (v3RoomTex, v3RoomGeo, v3FloorTex): painted off the main thread once, the floor's pools per table */
  var room: (key: String, wall: MTLTexture, floor: MTLTexture, wallB: MTLBuffer, floorB: MTLBuffer, lampB: MTLBuffer, G: V3Room.Geo)?
  var roomBusy = false
  var wrapSampler: MTLSamplerState!
  var numTex: MTLTexture!
  var markTex: MTLTexture!
  let quad: [SIMD2<Float>] = [[-1, -1], [1, -1], [-1, 1], [1, 1]]
  /* V3.geo.co: the cushions' depth the overview frames round the bed */
  var geoCo: Double? = nil
  /* V3's seat and moves (v3Update, v3Go): the pivot and yaw, what the seat was set for, the overview and a move */
  var px = Double.nan, py = Double.nan, yaw = 0.0, seatSet = false, seatShot = -1.0, seatTurn = -1, seatPlan: Double? = nil
  var ovOn = false, ovYaw = 0.0, ov: (key: String, o: V3.Overview)? = nil, mv: (from: V3.Orbit, t0: Double, ms: Double)? = nil, rolled = false
  var still: Bool { Prefs.reduceMotion }
  /* v3Go: a move to the overview (out) or back behind the cue ball; Reduce Motion, or no pose yet: a cut */
  func go(_ out: Bool, _ now: Double) {
    ovOn = out
    guard let (C, _) = model.v3Cam, !still else { mv = nil; return }
    mv = (V3.orbitOf(C.E, C.T), now, out ? V3.OUT_MS : V3.BACK_MS)
  }
  func cut(_ now: Double) { if ovOn { go(false, now) } else { mv = nil } }
  /* v3Update: the strike pulls back to the overview (After the Shot), held to the roll's end; the turn's cut is a move
     back down; the seat follows the player's aim, cuts on a new turn, a moved cue ball, the CPU's line */
  func update(_ now: Double) {
    let s = model.sim
    if model.rolling != nil {
      if !rolled {
        rolled = true
        let after = Prefs.viewAfter
        if after == "top" { model.v3Top2d = true } else if after != "stay" { ovYaw = yaw; ov = nil; go(true, now) }
      }
    } else { rolled = false }
    var cutTo: Double? = nil
    if let c = model.cue, model.rolling == nil {
      if !model.cpuTurn {
        /* the cue ball carried in hand (or sliding back): the camera holds still, and cuts on the let-go */
        if model.placeAt == nil {
          let moved = abs(c.x - px) > 1e-9 || abs(c.y - py) > 1e-9 || !px.isFinite
          if !seatSet || moved || seatShot != model.shotAt || seatTurn != (model.g?.turn ?? 0) || seatPlan != nil { cutTo = model.aim } else { yaw = model.aim }
          seatShot = model.shotAt; seatTurn = model.g?.turn ?? 0; seatPlan = nil
        }
      } else if model.stroke != nil || !model.cpuThinking {
        if seatPlan != model.aim { seatPlan = model.aim; cutTo = model.aim }
      } else if !seatSet { cutTo = model.aim }
      if let a = cutTo { px = c.x; py = c.y; yaw = a; seatSet = true; cut(now) }
    } else if model.cue == nil, !seatSet, let lc = model.lastCue { px = lc.x; py = lc.y; yaw = lc.ang; seatSet = true; cut(now) }
    if !seatSet { px = s.TL / 4; py = s.TW / 2; yaw = 0; seatSet = true }
  }
  /* v3Pose with the moves: the aim's pose, or the overview, or a move between them (an ease in and out) */
  func pose(_ box: V3.Box, _ now: Double) -> V3.Cam {
    let s = model.sim
    var C = V3.pose(s, box, px: px, py: py, yaw: yaw, pitch: model.v3Pitch, dist: model.v3Dist)
    if mv != nil || ovOn {
      var goal: V3.Orbit? = nil
      if ovOn {
        let key = "\(s.TL)|\(s.TW)|\(box.width)|\(box.height)|\(ovYaw)"
        if ov?.key != key { ov = (key, V3.overview(s, box, ovYaw, co: geoCo ?? 0.05)) }
        goal = ov!.o.o
      }
      if let m = mv {
        let u = min(1, max(0, (now - m.t0) / m.ms))
        if u >= 1 { mv = nil } else {
          let o = V3.lerp(m.from, goal ?? V3.orbitOf(C.E, C.T), 0.5 - 0.5 * cos(Double.pi * u)), q = V3.eyeOf(o)
          C = V3.mats(q.E, q.T, box.width, box.height); C.yaw = o.yaw; C.phase = goal != nil ? "out" : "back"; C.mu = u
        }
      }
      if mv == nil, let g = goal { let q = V3.eyeOf(g); C = V3.mats(q.E, q.T, box.width, box.height); C.yaw = g.yaw; C.phase = "ov" }
    }
    return C
  }

  init?(model: TableModel) {
    guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
    self.model = model; device = d; queue = q
    super.init()
    do { try build() } catch { print("3D: \(error)"); return nil }
  }
  func build() throws {
    let lib = try device.makeLibrary(source: SHADERS, options: nil)
    func pipe(_ v: String, _ f: String, _ vd: MTLVertexDescriptor?, blend: Bool, premul: Bool = false, add: Bool = false) throws -> MTLRenderPipelineState {
      let p = MTLRenderPipelineDescriptor()
      p.vertexFunction = lib.makeFunction(name: v); p.fragmentFunction = lib.makeFunction(name: f); p.vertexDescriptor = vd
      p.colorAttachments[0].pixelFormat = .bgra8Unorm; p.depthAttachmentPixelFormat = .depth32Float; p.rasterSampleCount = 4
      if blend { let c = p.colorAttachments[0]!; c.isBlendingEnabled = true; c.sourceRGBBlendFactor = premul ? .one : .sourceAlpha; c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.sourceAlphaBlendFactor = .sourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha }
      if add { let c = p.colorAttachments[0]!; c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .one }
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
    let ov = MTLVertexDescriptor()
    for (i, (f, o)) in [(MTLVertexFormat.float3, 0), (.float3, 12), (.float3, 24), (.float2, 36), (.float4, 44)].enumerated() { ov.attributes[i].format = f; ov.attributes[i].offset = o; ov.attributes[i].bufferIndex = 0 }
    ov.layouts[0].stride = 60
    overP = try pipe("overV", "overF", ov, blend: true, premul: true)
    let cv = MTLVertexDescriptor()
    for (i, (f, o)) in [(MTLVertexFormat.float3, 0), (.float2, 12), (.float4, 20)].enumerated() { cv.attributes[i].format = f; cv.attributes[i].offset = o; cv.attributes[i].bufferIndex = 0 }
    cv.layouts[0].stride = 36
    cardP = try pipe("cardV", "cardF", cv, blend: true, premul: true)
    fxP = try pipe("fxV", "fxF", nil, blend: true, add: true)
    lensP = try pipe("lensV", "lensF", nil, blend: true, premul: true)
    let nd = MTLDepthStencilDescriptor(); nd.depthCompareFunction = .always; nd.isDepthWriteEnabled = false
    noDepth = device.makeDepthStencilState(descriptor: nd)
    let A = V3Room.cardAtlas()
    if let t = texture(A.image) { cards = (t, A.at) }
    let dd = MTLDepthStencilDescriptor(); dd.depthCompareFunction = .lessEqual; dd.isDepthWriteEnabled = true
    depthOn = device.makeDepthStencilState(descriptor: dd)
    dd.isDepthWriteEnabled = false
    depthRead = device.makeDepthStencilState(descriptor: dd)
    let sd = MTLSamplerDescriptor(); sd.minFilter = .linear; sd.magFilter = .linear; sd.mipFilter = .linear; sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge; sd.maxAnisotropy = 8
    sampler = device.makeSamplerState(descriptor: sd)
    sd.sAddressMode = .repeat
    wrapSampler = device.makeSamplerState(descriptor: sd)
    numTex = texture(V3Art.numbers())
    markTex = texture(V3Art.marks())
  }
  func texture(_ img: CGImage) -> MTLTexture? {
    let l = MTKTextureLoader(device: device)
    return try? l.newTexture(cgImage: img, options: [.generateMipmaps: true, .SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue, .textureStorageMode: MTLStorageMode.private.rawValue])
  }
  func roomFor(_ G: (key: String, tex: MTLTexture, planes: MTLBuffer, nBed: Int, nTop: Int, mesh: MTLBuffer, nFaces: Int, nPosts: Int, bounce: [Double], outline: [[Double]])) {
    if room?.key == G.key || roomBusy { return }
    roomBusy = true
    let outline = G.outline, key = G.key, spec = model.spec, rid = model.dress.room
    Task.detached(priority: .userInitiated) {
      let sim = Sim(); TableModel.setUp(sim, spec)
      let geo = V3Room.geo(sim, outline: outline, lampH: BallPainter.LAMP_H, room: rid)
      let wall = V3Room.paintWall(1024, 224, rid), floor = V3Room.floorTex(V3Room.paintFloor(1024, rid), sim, geo)
      /* the wall is all blur: kept small (11 cm a texel at the wall, always magnified on screen) */
      let small = Canvas2D(width: 512, height: 112); small.drawImage(wall, 0, 0, 512, 112)
      let smallImg = small.image()
      await MainActor.run {
        self.roomBusy = false
        guard let wt = self.texture(smallImg), let ft = self.texture(floor),
              let wb = self.device.makeBuffer(bytes: geo.wall, length: geo.wall.count * 4), let fb = self.device.makeBuffer(bytes: geo.floor, length: geo.floor.count * 4),
              let lb = self.device.makeBuffer(bytes: geo.lamp, length: geo.lamp.count * 4) else { return }
        self.room = (key, wt, ft, wb, fb, lb, geo)
      }
    }
  }
  func geometry() -> (key: String, tex: MTLTexture, planes: MTLBuffer, nBed: Int, nTop: Int, mesh: MTLBuffer, nFaces: Int, nPosts: Int, bounce: [Double], outline: [[Double]])? {
    let s = model.sim, d = model.dress, key = "\(s.TL)|\(s.TW)|\(s.POCKET_R)|\(s.BALL_R)|\(d)"
    if let g = geo, g.key == key { return g }
    let G = V3Geo.build(s, look: TableLook.of(d))
    guard let tex = texture(G.image), let pb = device.makeBuffer(bytes: G.planes, length: G.planes.count * 4), let mb = device.makeBuffer(bytes: G.mesh.isEmpty ? [0] : G.mesh, length: max(4, G.mesh.count * 4)) else { return nil }
    geo = (key, tex, pb, G.nBed, G.nTop, mb, G.nFaces, G.nPosts, G.bounce, G.outline); geoCo = G.co
    return geo
  }

  /* v3Cue: a lathe of the look's parts from the tip (x 0) to the butt, 24 sides; four inlaid points round the forearm */
  func cue3() -> (key: String, b: MTLBuffer, n: Int)? {
    let G = CueGeo.of(game: model.game.table.2), (CU, tipCol) = CueLook.of(model.dress), key = "\(model.game.table.2)|\(model.dress)"
    if let c = cueBuf, c.key == key { return c }
    let parts = cueParts(CU, tipCol, G), LEN = G.len, SH0 = G.pool ? 0.027 : G.ferrule, SH1 = G.joint ?? (G.sleeve?[0] ?? 0.74), S = 24
    var cuts = Set([0.0, LEN])
    var x = 0.03; while x < SH1 { cuts.insert(x); x += 0.06 }
    for p in parts { cuts.insert(p.0); cuts.insert(p.1) }
    let pts: [Double]? = CU.pts != nil && G.pts != nil ? rgbaOf(css(CU.pts!)) : nil
    if pts != nil, let gp = G.pts { for i in 0...8 { cuts.insert(gp[0] + (gp[1] - gp[0]) * Double(i) / 8) } }
    let xs = cuts.filter { $0 >= 0 && $0 <= LEN }.sorted(), s0 = rgbaOf(css(CU.shaft[0])), s1 = rgbaOf(css(CU.shaft[1]))
    func colAt(_ x: Double) -> [Double] {
      var c: [Double]? = nil
      for (a, b, k) in parts where x >= a && x < b { c = rgbaOf(css(k)) }
      if let c { return c }
      let u = min(1, max(0, (x - SH0) / (SH1 - SH0)))
      return (0..<4).map { s0[$0] + (s1[$0] - s0[$0]) * u }
    }
    var out: [Float] = []
    for i in 0..<(xs.count - 1) {
      let x0 = xs[i], x1 = xs[i + 1], cx = colAt((x0 + x1) / 2), r0 = G.r(x0), r1 = G.r(x1), xm = (x0 + x1) / 2
      var ptW = 0.0
      if pts != nil, let gp = G.pts, xm >= gp[0] && xm < gp[1] { ptW = (xm - gp[0]) / (gp[1] - gp[0]) * Double.pi / 4.4 }
      for j in 0..<S {
        let a0 = Double(j) / Double(S) * 2 * Double.pi, a1 = Double(j + 1) / Double(S) * 2 * Double.pi, am = (a0 + a1) / 2
        let off = abs((am + Double.pi / 4).truncatingRemainder(dividingBy: Double.pi / 2) - Double.pi / 4), c = ptW > 0 && off < ptW ? pts! : cx
        func v(_ x: Double, _ r: Double, _ a: Double) { out += [Float(x), Float(r * cos(a)), Float(r * sin(a)), 0, Float(cos(a)), Float(sin(a)), Float(c[0]), Float(c[1]), Float(c[2]), 1] }
        v(x0, r0, a0); v(x1, r1, a0); v(x1, r1, a1); v(x0, r0, a0); v(x1, r1, a1); v(x0, r0, a1)
      }
    }
    guard let b = device.makeBuffer(bytes: out, length: out.count * 4) else { return nil }
    cueBuf = (key, b, out.count / 10)
    return cueBuf
  }
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  func draw(in view: MTKView) {
    guard let G = geometry(), let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
          let cb = queue.makeCommandBuffer() else { return }
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.016, blue: 0.016, alpha: 1)
    let s = model.sim, R = s.BALL_R, W = Double(view.bounds.width), H = Double(view.bounds.height)
    let box = V3.Box(left: 0, top: 0, width: W, height: H)
    let now = CACurrentMediaTime() * 1000
    update(now)
    let C = pose(box, now)
    model.v3Cam = (C, box); model.v3K = V3.k(C, px, py, R)
    /* pocketWords in 3D, from this camera: kept when they change, so the call's label and its menu follow the camera */
    let pw = s.POCKET_AIM.indices.map { V3.pocketWords(s, C, $0) }
    if model.v3Words != pw { model.v3Words = pw }
    let sc = Double(view.contentScaleFactor)
    /* the fine-aim loupe (v3Loupe): the same eye, looking at the ghost ball's middle, LOUPE_MAG times closer, rendered
       into a small target first (the room, the cue, the lamp and the flashes left out) */
    let tc = TableCanvas(model: model, look: Look.of(model.dress, game: model.game))
    let st = model.rolling == nil ? tc.loupeStep(pt: { x, y in V3.proj(C, box, x, y, R).map { CGPoint(x: $0[0], y: $0[1]) } ?? CGPoint(x: -1e5, y: -1e5) },
                                                 rect: (0, W, 0, H), rp: R * C.F / max(0.05, V3.dot(V3.sub([self.px, self.py, -R], C.Er), C.f))) : nil
    var lensTex: MTLTexture? = nil
    if let st, let c = model.cue {
      let n = max(8, Int((2 * st.L.r * sc).rounded())), gx = c.x + cos(model.aim) * st.h.t, gy = c.y + sin(model.aim) * st.h.t
      let Cl = V3.mats(C.E, [gx, gy, R], 2 * st.L.r, 2 * st.L.r, C.F * TableCanvas.LOUPE_MAG)
      if let (tex, lp) = loupeTarget(n), let le = cb.makeRenderCommandEncoder(descriptor: lp) {
        scene(le, Cl, G, full: false, sc: sc, vp: (Double(n), Double(n)), size: CGSize(width: 2 * st.L.r, height: 2 * st.L.r), ghostC: C)
        le.endEncoding()
        lensTex = tex
      }
    }
    guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
    model.potCue = nil
    scene(e, C, G, full: true, sc: sc, vp: (Double(view.drawableSize.width), Double(view.drawableSize.height)), size: view.bounds.size, ghostC: C)
    /* the lens on the view: a quad round the circle, out to the shadow's reach */
    if let st, let lt = lensTex {
      let pad = 16.0, Wp = Double(view.drawableSize.width), Hp = Double(view.drawableSize.height), x = st.L.x * sc, y = Hp - st.L.y * sc, ext = (st.L.r + pad) * sc
      var lu = LensU(box: SIMD4<Float>(Float(x / Wp * 2 - 1), Float(y / Hp * 2 - 1), Float(ext / Wp * 2), Float(ext / Hp * 2)), r: Float(st.L.r * sc), pad: Float(pad * sc), sc: Float(sc), a: Float(st.a))
      var q = quad
      e.setDepthStencilState(noDepth); e.setRenderPipelineState(lensP)
      e.setVertexBytes(&q, length: 32, index: 0); e.setVertexBytes(&lu, length: MemoryLayout<LensU>.stride, index: 1); e.setFragmentBytes(&lu, length: MemoryLayout<LensU>.stride, index: 1)
      e.setFragmentTexture(lt, index: 0); e.setFragmentSamplerState(sampler, index: 0)
      e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    e.endEncoding()
    cb.present(drawable)
    cb.commit()
  }
  /* the loupe's target: an n x n MSAA colour and depth, resolved into a texture the lens samples */
  var lfb: (n: Int, msaa: MTLTexture, tex: MTLTexture, depth: MTLTexture)?
  func loupeTarget(_ n: Int) -> (MTLTexture, MTLRenderPassDescriptor)? {
    if lfb?.n != n {
      let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: n, height: n, mipmapped: false)
      d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
      guard let tex = device.makeTexture(descriptor: d) else { return nil }
      d.textureType = .type2DMultisample; d.sampleCount = 4; d.usage = [.renderTarget]
      guard let ms = device.makeTexture(descriptor: d) else { return nil }
      let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: n, height: n, mipmapped: false)
      dd.textureType = .type2DMultisample; dd.sampleCount = 4; dd.usage = [.renderTarget]; dd.storageMode = .private
      guard let dep = device.makeTexture(descriptor: dd) else { return nil }
      lfb = (n, ms, tex, dep)
    }
    let p = MTLRenderPassDescriptor()
    p.colorAttachments[0].texture = lfb!.msaa; p.colorAttachments[0].resolveTexture = lfb!.tex
    p.colorAttachments[0].loadAction = .clear; p.colorAttachments[0].storeAction = .multisampleResolve
    p.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.016, blue: 0.016, alpha: 1)
    p.depthAttachment.texture = lfb!.depth; p.depthAttachment.loadAction = .clear; p.depthAttachment.storeAction = .dontCare; p.depthAttachment.clearDepth = 1
    return (lfb!.tex, p)
  }
  /* v3Scene: the table, its balls, shadows, overlays and flashes through camera C; full: the room, the cue and the lamp too
     (the main view; the loupe leaves them and the flashes out) */
  func scene(_ e: MTLRenderCommandEncoder, _ C: V3.Cam, _ G: (key: String, tex: MTLTexture, planes: MTLBuffer, nBed: Int, nTop: Int, mesh: MTLBuffer, nFaces: Int, nPosts: Int, bounce: [Double], outline: [[Double]]),
             full: Bool, sc: Double, vp: (Double, Double), size: CGSize, ghostC: V3.Cam) {
    let s = model.sim, R = s.BALL_R
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
      var mv = MeshV(M: M, W: matrix_identity_float4x4)
      e.setVertexBuffer(G.mesh, offset: 0, index: 0); e.setVertexBytes(&mv, length: MemoryLayout<MeshV>.stride, index: 1)
      var u = MeshU(L: f3(lamp), E: f3(C.Er), lit: 0, alpha: 1)
      e.setFragmentBytes(&u, length: MemoryLayout<MeshU>.stride, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: G.nFaces)
      if G.nPosts > 0 { u.lit = 1; e.setFragmentBytes(&u, length: MemoryLayout<MeshU>.stride, index: 0); e.drawPrimitives(type: .triangle, vertexStart: G.nFaces, vertexCount: G.nPosts) }
    }
    /* the room round it: the wall and the floor, opaque, after the table's solid parts, no depth writes */
    roomFor(G)
    if full, let Rm = room, Rm.key == G.key {
      e.setDepthStencilState(depthRead)
      e.setRenderPipelineState(texP)
      var r0: Float = 0
      e.setFragmentBytes(&r0, length: 4, index: 0); e.setVertexBytes(&Mv, length: 64, index: 1)
      e.setVertexBuffer(Rm.wallB, offset: 0, index: 0); e.setFragmentTexture(Rm.wall, index: 0); e.setFragmentSamplerState(wrapSampler, index: 0)
      e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: Rm.G.nWall)
      e.setVertexBuffer(Rm.floorB, offset: 0, index: 0); e.setFragmentTexture(Rm.floor, index: 0); e.setFragmentSamplerState(sampler, index: 0)
      e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: Rm.G.nFloor)
      /* the neighbours' soft cards, far to near, faded as the camera comes close; side on while the eye is low (v3Cards) */
      if let cd = cards, !Rm.G.near.isEmpty {
        var out: [Float] = []
        let E = C.E
        func push(_ k: String, _ t: Double, _ P: [[Double]]) {
          var m = 31
          for q in P {
            let w = V3.sub(q, C.Er), dd = V3.dot(w, C.f)
            if dd < V3.NEAR { m &= 16; continue }
            let sx = C.cx + C.F * V3.dot(w, C.r) / dd, sy = C.cy - C.F * V3.dot(w, C.u) / dd
            m &= (sx < 0 ? 1 : 0) | (sx > C.W ? 2 : 0) | (sy < 0 ? 4 : 0) | (sy > C.H ? 8 : 0)
          }
          if m != 0 { return }
          let a = cd.at[k]!, uv = [[a[0], a[1]], [a[2], a[1]], [a[2], a[3]], [a[0], a[3]]]
          for j in [0, 1, 2, 0, 2, 3] { out += [P[j][0], P[j][1], P[j][2], uv[j][0], uv[j][1], t, t, t, t].map { Float($0) } }
        }
        func flat(_ x: Double, _ y: Double, _ hx: Double, _ hy: Double, _ z: Double) -> [[Double]] { [[x - hx, y - hy, -z], [x + hx, y - hy, -z], [x + hx, y + hy, -z], [x - hx, y + hy, -z]] }
        func stand(_ x: Double, _ y: Double, _ w: Double, _ z0: Double, _ z1: Double) -> [[Double]] {
          var rx = -(y - E[1]), ry = x - E[0]
          var l = JSMath.hypot(rx, ry); if l == 0 { l = 1 }
          rx *= w / 2 / l; ry *= w / 2 / l
          return [[x - rx, y - ry, -z1], [x + rx, y + ry, -z1], [x + rx, y + ry, -z0], [x - rx, y - ry, -z0]]
        }
        func sm(_ u: Double) -> Double { let t = min(1, max(0, u)); return t * t * (3 - 2 * t) }
        let ns = Rm.G.near.map { n in (n[0], n[1], JSMath.hypot(n[0] - E[0], n[1] - E[1], E[2])) }.sorted { $0.2 > $1.2 }
        for (nx, ny, _) in ns {
          let f = sm((JSMath.hypot(nx - E[0], ny - E[1]) - 1.2) / 1.6)
          if f <= 0.01 || V3.dot(V3.sub([nx, ny, 0], C.Er), C.f) < -2 { continue }
          let el = atan2(E[2], JSMath.hypot(nx - E[0], ny - E[1])), fs = f * (1 - sm((el - V3Room.NSIDE_EL[0]) / (V3Room.NSIDE_EL[1] - V3Room.NSIDE_EL[0])))
          if fs > 0.01 { push("side", fs, stand(nx, ny, V3Room.NSIDE_W, V3Room.NSIDE[1], V3Room.NSIDE[0])) }
          push("top", f, flat(nx, ny, 1.7, 1.15, 0.035))
          push("lamp", f, stand(nx, ny, 1.9, BallPainter.LAMP_H - 0.39, BallPainter.LAMP_H + 0.27))
        }
        if !out.isEmpty, let cb = device.makeBuffer(bytes: out, length: out.count * 4) {
          e.setRenderPipelineState(cardP)
          e.setVertexBuffer(cb, offset: 0, index: 0); e.setVertexBytes(&Mv, length: 64, index: 1)
          e.setFragmentTexture(cd.tex, index: 0); e.setFragmentSamplerState(sampler, index: 0)
          e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: out.count / 9)
        }
      }
      e.setDepthStencilState(depthOn)
    }
    /* the balls on the table, far to near */
    /* the cue ball in hand (4f): carried, the ghost at placeAt lifted V3_LIFT x bih.h stands in for it on a legal spot
       (0.96), over an illegal one the ball stays on its last legal spot and the ghost is 0.5; let go, it settles (settleH) */
    let carried = model.rolling == nil && !model.cpuTurn ? model.placeAt : nil
    let ghostOk = carried.map { at in model.g.map { model.engine.canPlace($0, at.0, at.1) } ?? true } ?? false
    let balls = (model.rolling?.balls ?? model.balls).filter { $0.on && !(ghostOk && $0.n == model.cueN) }
    let sh = model.rolling == nil ? model.settleH(model.now) : 0
    /* v3Drops: each pot falls on toward the pocket's middle and below the bed, darkening and fading, over HERO_DROP_MS */
    /* a ball in the air (v3Air: a jump shot's b.z) drawn at its height */
    struct Drawn { let n: Int, x: Double, y: Double, z: Double, a: Double, dark: Double, drop: (k: Int, u: Double)?, air: Double }
    var drawn = balls.map { Drawn(n: $0.n, x: $0.x, y: $0.y, z: R + V3.air($0.z) + ($0.n == model.cueN && sh > 0 ? BallPainter.LIFT_H * sh : 0), a: 1, dark: 0, drop: nil, air: V3.air($0.z)) }
    if let at = carried { drawn.append(Drawn(n: model.cueN, x: at.0, y: at.1, z: R + BallPainter.LIFT_H * model.bihH, a: ghostOk ? 0.96 : 0.5, dark: 0, drop: nil, air: 0)) }
    let dur = 260 / model.speed, tnow = model.now
    for p in model.pots where p.k >= 0 && p.k < s.POCKETS.count && !balls.contains(where: { $0.n == p.n }) {
      let u = (tnow - p.t) * 1000 / dur, P = s.POCKETS[p.k]
      if !(u >= 0 && u < 1) { continue }
      let e1 = 1 - (1 - u) * (1 - u)
      drawn.append(Drawn(n: p.n, x: p.from.0 + (P[0] - p.from.0) * e1, y: p.from.1 + (P[1] - p.from.1) * e1, z: R * (1 - 2.6 * u * u), a: 1 - pow(u, 1.4), dark: min(1, 1.6 * u), drop: (p.k, u), air: 0))
    }
    var vis = drawn.map { b -> (Drawn, Double) in (b, V3.dot(V3.sub([b.x, b.y, -b.z], C.Er), C.f)) }.filter { $0.1 > V3.NEAR + R }
    vis.sort { $0.1 > $1.1 }
    /* their shadows on the bed (drawCast's lamp and lean); a lifted ball's leans further, grows and fades; a ball in the
       air casts a smaller, fainter one, further off (V3.cast) */
    e.setDepthStencilState(depthRead)
    e.setRenderPipelineState(shadowP)
    var q = quad
    e.setVertexBytes(&q, length: 32, index: 0)
    for (o, _) in vis {
      if let d = o.drop, d.u > 0.4 { continue }
      let fa = o.drop.map { max(0, 1 - 2.5 * $0.u) } ?? 1
      let (bx, by, grow, ao, ca) = V3.cast(s, x: o.x, y: o.y, z: o.z, air: o.air, a: fa * o.a, liftH: BallPainter.LIFT_H, lampH: BallPainter.LAMP_H, light: LIGHT)
      var u = ShU(M: M, S: SIMD3<Float>(Float((o.x + bx) / 2), Float((o.y + by) / 2), -0.0008), ext: Float(R * 1.6 * grow + JSMath.hypot(bx - o.x, by - o.y)),
                  A: SIMD2<Float>(Float(o.x), Float(o.y)), B: SIMD2<Float>(Float(bx), Float(by)), R: Float(R), grow: Float(grow), ao: Float(ao), ca: Float(ca))
      e.setVertexBytes(&u, length: MemoryLayout<ShU>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<ShU>.stride, index: 1)
      e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    /* the overlays (v3Overlays: the kitchen or the D, the halo, the hint, the solo marks, the call, the guide, ball in
       hand's marks; premultiplied), each at one height on the bed or the rail tops */
    let m2 = Mapper(size: size, TL: s.TL, TW: s.TW)
    let sink = Sink3D(C, s: s, m: m2, scale: sc, topH: R * 1.42)
    TableCanvas(model: model, look: Look.of(model.dress, game: model.game)).drawOverlays(sink, m2, balls: balls)
    if !sink.rib.v.isEmpty, let ob = device.makeBuffer(bytes: sink.rib.v, length: sink.rib.v.count * 4) {
      e.setRenderPipelineState(overP)
      var ou = OverU(M: M, VP: SIMD2<Float>(Float(vp.0 / 2), Float(vp.1 / 2)))
      e.setVertexBuffer(ob, offset: 0, index: 0); e.setVertexBytes(&ou, length: MemoryLayout<OverU>.stride, index: 1)
      e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: sink.rib.v.count / V3Ribbons.OVF)
    }
    /* the balls */
    e.setDepthStencilState(depthOn)
    e.setRenderPipelineState(ballP)
    e.setVertexBytes(&q, length: 32, index: 0)
    e.setFragmentTexture(numTex, index: 0); e.setFragmentTexture(markTex, index: 1); e.setFragmentSamplerState(sampler, index: 0)
    let toV = { (p: [Double]) -> SIMD3<Float> in let V = C.V; return SIMD3<Float>((0..<3).map { Float(V[$0] * p[0] + V[4 + $0] * p[1] + V[8 + $0] * p[2] + V[12 + $0]) }) }
    let Vi = simd_float3x3(f3(C.r), f3(C.u), -f3(C.f))
    let painter = model.ballPainter(upright: true, scale: CGFloat(sc))
    for (o, _) in vis {
      let p = painter.paintOf(o.n), m = model.orient[o.n] ?? IDENT, Cw = [o.x, o.y, -o.z]
      func cap(_ i: Int) -> (SIMD4<Float>, SIMD3<Float>) {
        guard i < p.caps.count else { return (SIMD4<Float>(0, 2, 0, 0), SIMD3<Float>(0, 0, 0)) }
        let c = p.caps[i]; return (SIMD4<Float>(Float(c.0), Float(c.1), 0, 1), rgb(c.2))
      }
      let c0 = cap(0), c1 = cap(1), c2 = cap(2)
      var u = BallU(V: Vm, P: P, Vi: Vi, C: f3(Cw), Cv: toV(Cw), R: Float(R), Ax0: SIMD3<Float>(Float(m[0]), Float(m[3]), Float(m[6])), Ax1: SIMD3<Float>(Float(m[1]), Float(m[4]), Float(m[7])),
                    Ax2: SIMD3<Float>(Float(m[2]), Float(m[5]), Float(m[8])), base: rgb(p.base), cap0: c0.0, cap1: c1.0, cap2: c2.0, capC0: c0.1, capC1: c1.1, capC2: c2.1,
                    num: Float(o.n > 0 && o.n < 16 ? o.n : 0), Lv: toV(lamp), bounce: f3(G.bounce), alpha: Float(o.a), rim: painter.rim3(o.n) ? 1 : 0)
      u.bedN = SIMD3<Float>(Float(C.V[8]), Float(C.V[9]), Float(C.V[10])); u.dark = Float(o.dark)
      /* v3MarkIdx: the ball's mark cell when settings.marks is on */
      u.mark = painter.marks ? Float(V3Art.markIdx(o.n)) : -1
      if let d = o.drop { let h = toV([s.POCKETS[d.k][0], s.POCKETS[d.k][1], 0]); u.hole = SIMD4<Float>(h.x, h.y, h.z, Float(s.POCKET_R[d.k])) }
      e.setVertexBytes(&u, length: MemoryLayout<BallU>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<BallU>.stride, index: 1)
      e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    /* the hit flashes (drawFx's, the same timing and colours) as billboards at the contact, added over the balls */
    let tn = model.now
    let fx = full ? model.effects.filter { tn - $0.t < $0.d } : []
    if !fx.isEmpty {
      e.setDepthStencilState(noDepth)
      e.setRenderPipelineState(fxP)
      e.setVertexBytes(&q, length: 32, index: 0)
      for f in fx {
        let u = min(1, max(0, (tn - f.t) / f.d)), a = min(1, f.v / 3) * (1 - u) * (1 - u)
        let rail = f.kind == "rail", rad = rail ? R * 2.2 : R * (f.kind == "cue" ? 0.25 + 0.5 * u : 0.3 + 1.1 * u)
        let col: SIMD4<Float> = rail ? [190 / 255, 1, 220 / 255, Float(0.2 * a)] : f.kind == "cue" ? [170 / 255, 205 / 255, 1, Float(0.6 * a)] : [1, 1, 1, Float(0.5 * a)]
        var fu = FxU(V: Vm, P: P, C: f3([f.x, f.y, -R]), ext: Float(rad * 1.15 + 0.004), kind: rail ? 1 : 0, rad: Float(rad), lw: Float(0.75 * vp.0 / max(1, C.W)), col: col)
        e.setVertexBytes(&fu, length: MemoryLayout<FxU>.stride, index: 1); e.setFragmentBytes(&fu, length: MemoryLayout<FxU>.stride, index: 1)
        e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
      }
      e.setDepthStencilState(depthOn)
    }
    /* the guide's ghost ball: a faint ball where the cue ball will meet, white or the illegal colour (V3_GHOST_A) */
    if let gh = sink.ghost, V3.dot(V3.sub([gh.x, gh.y, -R], C.Er), C.f) > V3.NEAR + R {
      e.setDepthStencilState(depthRead)
      let Cw = [gh.x, gh.y, -R], none = (SIMD4<Float>(0, 2, 0, 0), SIMD3<Float>(0, 0, 0))
      var u = BallU(V: Vm, P: P, Vi: Vi, C: f3(Cw), Cv: toV(Cw), R: Float(R), Ax0: [1, 0, 0], Ax1: [0, 1, 0], Ax2: [0, 0, 1], base: f3(gh.col), cap0: none.0, cap1: none.0, cap2: none.0,
                    capC0: none.1, capC1: none.1, capC2: none.1, num: 0, Lv: toV(lamp), bounce: f3(G.bounce), alpha: 0.34, rim: 0)
      e.setVertexBytes(&u, length: MemoryLayout<BallU>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<BallU>.stride, index: 1)
      e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
      e.setDepthStencilState(depthOn)
    }
    /* the cue: behind the ball on the aim, raised a little at least (it clears the rails), pulled back by power */
    if full, model.rolling == nil, !model.cpuThinking, carried == nil || ghostOk, let c = model.cue, let cb = cue3() {
      let rest = R + 0.012, back = 0.27
      var gap = rest + back * min(1, max(0, model.power))
      if let st = model.stroke {
        let u = min(1, max(0, (st.t0.map { model.now - $0 } ?? 0) / TableModel.STROKE_MS)), g0 = rest + back * min(1, max(0, st.power))
        gap = g0 + (R - g0) * u * u
      }
      /* the tip on the cue ball at its height in the air (v3Air) */
      let sp = model.spin, a = model.aim, dx = cos(a), dy = sin(a)
      let (tip, ax) = V3.cueTip(s, x: c.x, y: c.y, air: V3.air(c.z), aim: a, sx: sp.x, sy: sp.y, el: Swift.max(sp.e, 5 * Double.pi / 180), gap: gap)
      model.potCue = (tip, ax)   /* the rails' windows give way where it lies over them (6b3) */
      let side = [-dy, dx, 0.0], up = V3.norm(V3.cross(ax, side))
      var mv = MeshV(M: M, W: m4([ax[0], ax[1], ax[2], 0, side[0], side[1], side[2], 0, up[0], up[1], up[2], 0, tip[0], tip[1], tip[2], 1]))
      var u = MeshU(L: f3(lamp), E: f3(C.Er), lit: 1, alpha: 1)
      e.setRenderPipelineState(meshP)
      e.setVertexBuffer(cb.b, offset: 0, index: 0); e.setVertexBytes(&mv, length: MemoryLayout<MeshV>.stride, index: 1)
      e.setFragmentBytes(&u, length: MemoryLayout<MeshU>.stride, index: 0)
      e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cb.n)
    }
    /* this table's lamp, faded out as the camera rises to it (so it never hangs between the camera and the bed) */
    if full, let Rm = room, Rm.key == G.key {
      let u = min(1, max(0, (C.E[2] - (Rm.G.lampZ - 0.3)) / 0.28)), a = 1 - u * u * (3 - 2 * u)
      if a > 0.01 {
        e.setRenderPipelineState(meshP)
        var mv = MeshV(M: M, W: matrix_identity_float4x4), lu = MeshU(L: f3(lamp), E: f3(C.Er), lit: 0, alpha: Float(a))
        e.setVertexBuffer(Rm.lampB, offset: 0, index: 0); e.setVertexBytes(&mv, length: MemoryLayout<MeshV>.stride, index: 1)
        e.setFragmentBytes(&lu, length: MemoryLayout<MeshU>.stride, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: Rm.G.nLamp)
      }
    }
  }
}

/* the 3D table on screen: an MTKView drawing every frame while visible */
struct Table3DView: UIViewRepresentable {
  let model: TableModel
  func makeCoordinator() -> Renderer3D? { Renderer3D(model: model) }
  func makeUIView(context: Context) -> MTKView {
    let v = MTKView(frame: .zero, device: context.coordinator?.device)
    v.colorPixelFormat = .bgra8Unorm; v.depthStencilPixelFormat = .depth32Float; v.sampleCount = 4
    v.preferredFramesPerSecond = 120; v.delegate = context.coordinator; v.isUserInteractionEnabled = false
    return v
  }
  func updateUIView(_ v: MTKView, context: Context) {}
}
