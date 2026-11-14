/* The sim's math, the same bits on every platform. felt's physics is chaotic (a break amplifies one
   ulp into a different rack), so "the same physics" means the same doubles. Apple's libm, V8's
   (clang fuses multiply-adds on arm64; trig may be glibc's) and JavaScriptCore all differ in the
   last bit. This is fdlibm 5.3, ported from the JDK's FdLibm.java (StrictMath's reference code),
   and V8's Math.hypot (src/builtins/math.tq: Kahan sum of squares normalised to the largest).
   tools/fdlibm.cjs is the same code in JS; tools/ios-golden.cjs runs index.html's sim on it, so the
   goldens and this port share one reference. Only what sim 1a-1d calls is here. */
import Foundation

@inline(__always) private func hi(_ x: Double) -> Int32 { Int32(truncatingIfNeeded: Int64(bitPattern: x.bitPattern) >> 32) }
@inline(__always) private func lo(_ x: Double) -> Int32 { Int32(truncatingIfNeeded: Int64(bitPattern: x.bitPattern)) }
@inline(__always) private func withLo(_ x: Double, _ l: Int32) -> Double {
  Double(bitPattern: (x.bitPattern & 0xFFFF_FFFF_0000_0000) | UInt64(UInt32(bitPattern: l)))
}
@inline(__always) private func withHi(_ x: Double, _ h: Int32) -> Double {
  Double(bitPattern: (x.bitPattern & 0x0000_0000_FFFF_FFFF) | (UInt64(UInt32(bitPattern: h)) << 32))
}
@inline(__always) private func hiLo(_ h: Int32, _ l: Int32) -> Double {
  Double(bitPattern: (UInt64(UInt32(bitPattern: h)) << 32) | UInt64(UInt32(bitPattern: l)))
}
private let EXP_BITS: Int32 = 0x7ff0_0000, SIGNIF: Int32 = 0x7fff_ffff

public enum JSMath {
  /* JS Math.max / Math.min for two numbers: NaN wins, and +0 is above -0 */
  @inline(__always) public static func max(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return .nan }
    if a == b { return a == 0 ? (a.sign == .minus ? b : a) : a }
    return a > b ? a : b
  }
  @inline(__always) public static func min(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return .nan }
    if a == b { return a == 0 ? (a.sign == .minus ? a : b) : a }
    return a < b ? a : b
  }
  @inline(__always) public static func sqrt(_ x: Double) -> Double { x.squareRoot() }

  /* V8's Math.hypot */
  public static func hypot(_ a: Double, _ b: Double) -> Double {
    if a.isInfinite || b.isInfinite { return .infinity }
    if a.isNaN || b.isNaN { return .nan }
    let x = abs(a), y = abs(b), m = x > y ? x : y
    if m == 0 { return 0 }
    var sum = 0.0, comp = 0.0
    for v in [x, y] { let n = v / m, s = n * n - comp, p = sum + s; comp = (p - sum) - s; sum = p }
    return sum.squareRoot() * m
  }
  public static func hypot(_ a: Double, _ b: Double, _ c: Double) -> Double {
    if a.isInfinite || b.isInfinite || c.isInfinite { return .infinity }
    if a.isNaN || b.isNaN || c.isNaN { return .nan }
    let x = abs(a), y = abs(b), z = abs(c)
    var m = 0.0
    if x > m { m = x }; if y > m { m = y }; if z > m { m = z }
    if m == 0 { return 0 }
    var sum = 0.0, comp = 0.0
    for v in [x, y, z] { let n = v / m, s = n * n - comp, p = sum + s; comp = (p - sum) - s; sum = p }
    return sum.squareRoot() * m
  }

  // MARK: sin, cos, tan

  private static let S1 = -0x1.5555555555549p-3, S2 = 0x1.111111110f8a6p-7, S3 = -0x1.a01a019c161d5p-13,
    S4 = 0x1.71de357b1fe7dp-19, S5 = -0x1.ae5e68a2b9cebp-26, S6 = 0x1.5d93a5acfd57cp-33
  private static func kSin(_ x: Double, _ y: Double, _ iy: Int) -> Double {
    let ix = hi(x) & SIGNIF
    if ix < 0x3e40_0000 && x.rounded(.towardZero) == 0 { return x }
    let z = x * x, v = z * x, r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
    if iy == 0 { return x + v * (S1 + z * r) }
    return x - ((z * (0.5 * y - v * r) - y) - v * S1)
  }
  private static let C1 = 0x1.555555555554cp-5, C2 = -0x1.6c16c16c15177p-10, C3 = 0x1.a01a019cb159p-16,
    C4 = -0x1.27e4f809c52adp-22, C5 = 0x1.1ee9ebdb4b1c4p-29, C6 = -0x1.8fae9be8838d4p-37
  private static func kCos(_ x: Double, _ y: Double) -> Double {
    let ix = hi(x) & SIGNIF
    if ix < 0x3e40_0000 && x.rounded(.towardZero) == 0 { return 1.0 }
    let z = x * x, r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
    if ix < 0x3FD3_3333 { return 1.0 - (0.5 * z - (z * r - x * y)) }
    let qx = ix > 0x3fe9_0000 ? 0.28125 : hiLo(ix - 0x0020_0000, 0)
    let hz = 0.5 * z - qx, a = 1.0 - qx
    return a - (hz - (z * r - x * y))
  }
  private static let T: [Double] = [0x1.5555555555563p-2, 0x1.111111110fe7ap-3, 0x1.ba1ba1bb341fep-5, 0x1.664f48406d637p-6,
    0x1.226e3e96e8493p-7, 0x1.d6d22c9560328p-9, 0x1.7dbc8fee08315p-10, 0x1.344d8f2f26501p-11, 0x1.026f71a8d1068p-12,
    0x1.47e88a03792a6p-14, 0x1.2b80f32f0a7e9p-14, -0x1.375cbdb605373p-16, 0x1.b2a7074bf7ad4p-16]
  private static func kTan(_ x0: Double, _ y0: Double, _ iy: Int) -> Double {
    var x = x0, y = y0
    var z: Double, r: Double, v: Double, w: Double, s: Double
    let hx = hi(x), ix = hx & SIGNIF
    if ix < 0x3e30_0000 && x.rounded(.towardZero) == 0 {
      if ((ix | lo(x)) | Int32(iy + 1)) == 0 { return 1.0 / abs(x) }
      if iy == 1 { return x }
      w = x + y; z = withLo(w, 0); v = y - (z - x)
      let a = -1.0 / w, t = withLo(a, 0); s = 1.0 + t * z
      return t + a * (s + t * v)
    }
    if ix >= 0x3FE5_9428 {
      if hx < 0 { x = -x; y = -y }
      z = 0x1.921fb54442d18p-1 - x; w = 0x1.1a62633145c07p-55 - y; x = z + w; y = 0.0
    }
    z = x * x; w = z * z
    r = T[1] + w * (T[3] + w * (T[5] + w * (T[7] + w * (T[9] + w * T[11]))))
    v = z * (T[2] + w * (T[4] + w * (T[6] + w * (T[8] + w * (T[10] + w * T[12])))))
    s = z * x
    r = y + z * (s * (r + v) + y)
    r += T[0] * s
    w = x + r
    if ix >= 0x3FE5_9428 {
      v = Double(iy)
      return Double(1 - ((hx >> 30) & 2)) * (v - 2.0 * (x - (w * w / (w + v) - r)))
    }
    if iy == 1 { return w }
    z = withLo(w, 0); v = r - (z - x)
    let a = -1.0 / w, t = withLo(a, 0); s = 1.0 + t * z
    return t + a * (s + t * v)
  }
  private static let npio2hw: [Int32] = [0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C,
    0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB,
    0x403AB41B, 0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C, 0x4043A28C, 0x40446B9C,
    0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB]
  private static let invpio2 = 0x1.45f306dc9c883p-1, pio2_1 = 0x1.921fb544p0, pio2_1t = 0x1.0b4611a626331p-34,
    pio2_2 = 0x1.0b4611a6p-34, pio2_2t = 0x1.3198a2e037073p-69, pio2_3 = 0x1.3198a2ep-69, pio2_3t = 0x1.b839a252049c1p-104
  /* argument reduction for |x| up to 2^19 pi/2 (the sim's angles are a few radians); beyond, the
     multi-precision path (__kernel_rem_pio2) is not ported and this traps */
  private static func remPio2(_ x: Double) -> (Int, Double, Double) {
    let hx = hi(x), ix = hx & SIGNIF
    if ix <= 0x3fe9_21fb { return (0, x, 0) }
    if ix < 0x4002_d97c {
      if hx > 0 {
        var z = x - pio2_1
        if ix != 0x3ff9_21fb { let y0 = z - pio2_1t; return (1, y0, (z - y0) - pio2_1t) }
        z -= pio2_2; let y0 = z - pio2_2t; return (1, y0, (z - y0) - pio2_2t)
      } else {
        var z = x + pio2_1
        if ix != 0x3ff9_21fb { let y0 = z + pio2_1t; return (-1, y0, (z - y0) + pio2_1t) }
        z += pio2_2; let y0 = z + pio2_2t; return (-1, y0, (z - y0) + pio2_2t)
      }
    }
    precondition(ix <= 0x4139_21fb, "JSMath: angle too large for the ported reduction")
    var t = abs(x)
    let n = Int(Int32(t * invpio2 + 0.5)), fn = Double(n)
    var r = t - fn * pio2_1, w = fn * pio2_1t, y0: Double
    if n < 32 && ix != npio2hw[n - 1] {
      y0 = r - w
    } else {
      let j = ix >> 20
      y0 = r - w
      var i = j - ((hi(y0) >> 20) & 0x7ff)
      if i > 16 {
        t = r; w = fn * pio2_2; r = t - w; w = fn * pio2_2t - ((t - r) - w); y0 = r - w
        i = j - ((hi(y0) >> 20) & 0x7ff)
        if i > 49 { t = r; w = fn * pio2_3; r = t - w; w = fn * pio2_3t - ((t - r) - w); y0 = r - w }
      }
    }
    let y1 = (r - y0) - w
    return hx < 0 ? (-n, -y0, -y1) : (n, y0, y1)
  }
  public static func sin(_ x: Double) -> Double {
    let ix = hi(x) & SIGNIF
    if ix <= 0x3fe9_21fb { return kSin(x, 0, 0) }
    if ix >= EXP_BITS { return x - x }
    let (n, a, b) = remPio2(x)
    switch n & 3 { case 0: return kSin(a, b, 1); case 1: return kCos(a, b); case 2: return -kSin(a, b, 1); default: return -kCos(a, b) }
  }
  public static func cos(_ x: Double) -> Double {
    let ix = hi(x) & SIGNIF
    if ix <= 0x3fe9_21fb { return kCos(x, 0) }
    if ix >= EXP_BITS { return x - x }
    let (n, a, b) = remPio2(x)
    switch n & 3 { case 0: return kCos(a, b); case 1: return -kSin(a, b, 1); case 2: return -kCos(a, b); default: return kSin(a, b, 1) }
  }
  public static func tan(_ x: Double) -> Double {
    let ix = hi(x) & SIGNIF
    if ix <= 0x3fe9_21fb { return kTan(x, 0, 1) }
    if ix >= EXP_BITS { return x - x }
    let (n, a, b) = remPio2(x)
    return kTan(a, b, 1 - ((n & 1) << 1))
  }

  // MARK: atan, acos

  private static let atanhi = [0x1.dac670561bb4fp-2, 0x1.921fb54442d18p-1, 0x1.f730bd281f69bp-1, 0x1.921fb54442d18p0]
  private static let atanlo = [0x1.a2b7f222f65e2p-56, 0x1.1a62633145c07p-55, 0x1.007887af0cbbdp-56, 0x1.1a62633145c07p-54]
  private static let aT = [0x1.555555555550dp-2, -0x1.999999998ebc4p-3, 0x1.24924920083ffp-3, -0x1.c71c6fe231671p-4,
    0x1.745cdc54c206ep-4, -0x1.3b0f2af749a6dp-4, 0x1.10d66a0d03d51p-4, -0x1.dde2d52defd9ap-5, 0x1.97b4b24760debp-5,
    -0x1.2b4442c6a6c2fp-5, 0x1.0ad3ae322da11p-6]
  public static func atan(_ x0: Double) -> Double {
    var x = x0
    let hx = hi(x), ix = hx & SIGNIF, id: Int
    if ix >= 0x4410_0000 {
      if ix > EXP_BITS || (ix == EXP_BITS && lo(x) != 0) { return x + x }
      return hx > 0 ? atanhi[3] + atanlo[3] : -atanhi[3] - atanlo[3]
    }
    if ix < 0x3fdc_0000 {
      if ix < 0x3e20_0000 { return x }
      id = -1
    } else {
      x = abs(x)
      if ix < 0x3ff3_0000 {
        if ix < 0x3fe6_0000 { id = 0; x = (2.0 * x - 1.0) / (2.0 + x) } else { id = 1; x = (x - 1.0) / (x + 1.0) }
      } else {
        if ix < 0x4003_8000 { id = 2; x = (x - 1.5) / (1.0 + 1.5 * x) } else { id = 3; x = -1.0 / x }
      }
    }
    var z = x * x
    let w = z * z
    let s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))))
    let s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))))
    if id < 0 { return x - x * (s1 + s2) }
    z = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x)
    return hx < 0 ? -z : z
  }
  private static let pio2_hi = 0x1.921fb54442d18p0, pio2_lo = 0x1.1a62633145c07p-54,
    pS0 = 0x1.5555555555555p-3, pS1 = -0x1.4d61203eb6f7dp-2, pS2 = 0x1.9c1550e884455p-3, pS3 = -0x1.48228b5688f3bp-5,
    pS4 = 0x1.9efe07501b288p-11, pS5 = 0x1.23de10dfdf709p-15,
    qS1 = -0x1.33a271c8a2d4bp1, qS2 = 0x1.02ae59c598ac8p1, qS3 = -0x1.6066c1b8d0159p-1, qS4 = 0x1.3b8c5b12e9282p-4
  public static func acos(_ x: Double) -> Double {
    let hx = hi(x), ix = hx & SIGNIF
    if ix >= 0x3ff0_0000 {
      if ((ix - 0x3ff0_0000) | lo(x)) == 0 { return hx > 0 ? 0.0 : Double.pi + 2.0 * pio2_lo }
      return (x - x) / (x - x)
    }
    if ix < 0x3fe0_0000 {
      if ix <= 0x3c60_0000 { return pio2_hi + pio2_lo }
      let z = x * x
      let p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
      let q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
      return pio2_hi - (x - (pio2_lo - x * (p / q)))
    } else if hx < 0 {
      let z = (1.0 + x) * 0.5
      let p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
      let q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
      let s = z.squareRoot(), w = (p / q) * s - pio2_lo
      return Double.pi - 2.0 * (s + w)
    } else {
      let z = (1.0 - x) * 0.5, s = z.squareRoot(), df = withLo(s, 0), c = (z - df * df) / (s + df)
      let p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
      let q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
      let w = (p / q) * s + c
      return 2.0 * (df + w)
    }
  }

  // MARK: exp, pow

  private static let P1 = 0x1.555555555553ep-3, P2 = -0x1.6c16c16bebd93p-9, P3 = 0x1.1566aaf25de2cp-14,
    P4 = -0x1.bbd41c5d26bf1p-20, P5 = 0x1.6376972bea4d0p-25
  public static func exp(_ x0: Double) -> Double {
    var x = x0
    var hi_ = 0.0, lo_ = 0.0, k: Int32 = 0
    var hx = hi(x)
    let xsb = Int((hx >> 31) & 1)
    hx &= SIGNIF
    if hx >= 0x40862E42 {
      if hx >= 0x7ff00000 { return ((hx & 0xfffff) | lo(x)) != 0 ? x + x : (xsb == 0 ? x : 0.0) }
      if x > 0x1.62e42fefa39efp9 { return .infinity }
      if x < -0x1.74910d52d3051p9 { return 0 }
    }
    if hx > 0x3fd62e42 {
      if hx < 0x3FF0A2B2 {
        hi_ = x - (xsb == 0 ? 0x1.62e42feep-1 : -0x1.62e42feep-1)
        lo_ = xsb == 0 ? 0x1.a39ef35793c76p-33 : -0x1.a39ef35793c76p-33
        k = Int32(1 - xsb - xsb)
      } else {
        k = Int32(0x1.71547652b82fep0 * x + (xsb == 0 ? 0.5 : -0.5))
        let t = Double(k)
        hi_ = x - t * 0x1.62e42feep-1
        lo_ = t * 0x1.a39ef35793c76p-33
      }
      x = hi_ - lo_
    } else if hx < 0x3e300000 {
      return 1.0 + x
    }
    let t = x * x, c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
    if k == 0 { return 1.0 - ((x * c) / (c - 2.0) - x) }
    let y = 1.0 - ((lo_ - (x * c) / (2.0 - c)) - hi_)
    if k >= -1021 { return withHi(y, hi(y) &+ (k << 20)) }
    return withHi(y, hi(y) &+ ((k + 1000) << 20)) * 0x1.0p-1000
  }

  public static func pow(_ x: Double, _ y: Double) -> Double {
    if y == 0 { return 1.0 }
    if x.isNaN || y.isNaN { return x + y }
    let yAbs = abs(y)
    var xAbs = abs(x)
    if y == 2.0 { return x * x }
    if y == 0.5 { if x >= -Double.greatestFiniteMagnitude { return (x + 0.0).squareRoot() } }
    else if yAbs == 1.0 { return y == 1.0 ? x : 1.0 / x }
    else if yAbs == .infinity {
      if xAbs == 1.0 { return y - y }
      if xAbs > 1.0 { return y >= 0 ? y : 0.0 }
      return y < 0 ? -y : 0.0
    }
    let hx = hi(x)
    var ix = hx & SIGNIF
    var yIsInt: Int32 = 0
    if hx < 0 {
      if yAbs >= 0x1.0p53 { yIsInt = 2 }
      else if yAbs >= 1.0 { let l = Int64(yAbs); if Double(l) == yAbs { yIsInt = 2 - Int32(l & 1) } }
    }
    if xAbs == 0.0 || xAbs == .infinity || xAbs == 1.0 {
      var z = xAbs
      if y < 0.0 { z = 1.0 / z }
      if hx < 0 {
        if ((ix - 0x3ff00000) | yIsInt) == 0 { z = (z - z) / (z - z) } else if yIsInt == 1 { z = -1.0 * z }
      }
      return z
    }
    var n: Int32 = (hx >> 31) + 1
    if (n | yIsInt) == 0 { return (x - x) / (x - x) }
    var s = 1.0
    if (n | (yIsInt - 1)) == 0 { s = -1.0 }
    var t1: Double, t2: Double, t: Double, u: Double, v: Double, w: Double, r: Double, z: Double
    var pH: Double, pL: Double
    if yAbs > 0x1.00000ffffffffp31 {
      if xAbs < 0x1.fffff00000000p-1 { return y < 0.0 ? s * .infinity : s * 0.0 }
      if xAbs > 0x1.00000ffffffffp0 { return y > 0.0 ? s * .infinity : s * 0.0 }
      t = xAbs - 1.0
      w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25))
      u = 0x1.715476p0 * t
      v = t * 0x1.4ae0bf85ddf44p-26 - w * 0x1.71547652b82fep0
      t1 = withLo(u + v, 0)
      t2 = v - (t1 - u)
    } else {
      let CP = 0x1.ec709dc3a03fdp-1, CP_H = 0x1.ec709ep-1, CP_L = -0x1.e2fe0145b01f5p-28
      n = 0
      if ix < 0x00100000 { xAbs *= 0x1.0p53; n -= 53; ix = hi(xAbs) }
      n += (ix >> 20) - 0x3ff
      let j = ix & 0x000fffff
      ix = j | 0x3ff00000
      let k: Int
      if j <= 0x3988E { k = 0 } else if j < 0xBB67A { k = 1 } else { k = 0; n += 1; ix -= 0x00100000 }
      xAbs = withHi(xAbs, ix)
      let BP = [1.0, 1.5], DP_H = [0.0, 0x1.2b8034p-1], DP_L = [0.0, 0x1.cfdeb43cfd006p-27]
      let L1 = 0x1.3333333333303p-1, L2 = 0x1.b6db6db6fabffp-2, L3 = 0x1.55555518f264dp-2,
        L4 = 0x1.17460a91d4101p-2, L5 = 0x1.d864a93c9db65p-3, L6 = 0x1.a7e284a454eefp-3
      u = xAbs - BP[k]
      v = 1.0 / (xAbs + BP[k])
      let ss = u * v
      let sH = withLo(ss, 0)
      var tH = withHi(0.0, ((ix >> 1) | 0x20000000) + 0x00080000 + Int32(k << 18))
      var tL = xAbs - (tH - BP[k])
      let sL = v * ((u - sH * tH) - sH * tL)
      var s2 = ss * ss
      r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))))
      r += sL * (sH + ss)
      s2 = sH * sH
      tH = withLo(3.0 + s2 + r, 0)
      tL = r - ((tH - 3.0) - s2)
      u = sH * tH
      v = sL * tH + tL * ss
      pH = withLo(u + v, 0)
      pL = v - (pH - u)
      let zH = CP_H * pH, zL = CP_L * pH + pL * CP + DP_L[k]
      t = Double(n)
      t1 = withLo(((zH + zL) + DP_H[k]) + t, 0)
      t2 = zL - (((t1 - t) - DP_H[k]) - zH)
    }
    let y1 = withLo(y, 0)
    pL = (y - y1) * t1 + y * t2
    pH = y1 * t1
    z = pL + pH
    var j = hi(z)
    var i = lo(z)
    if j >= 0x40900000 {
      if ((j - 0x40900000) | i) != 0 { return s * .infinity }
      if pL + 8.0085662595372944372e-0017 > z - pH { return s * .infinity }
    } else if (j & SIGNIF) >= 0x4090cc00 {
      if ((j &- Int32(bitPattern: 0xc090cc00)) | i) != 0 { return s * 0.0 }
      if pL <= z - pH { return s * 0.0 }
    }
    let LG2 = 0x1.62e42fefa39efp-1, LG2_H = 0x1.62e43p-1, LG2_L = -0x1.05c610ca86c39p-29
    i = j & SIGNIF
    var k = (i >> 20) - 0x3ff
    n = 0
    if i > 0x3fe00000 {
      n = j &+ (0x00100000 >> (k + 1))
      k = ((n & SIGNIF) >> 20) - 0x3ff
      t = withHi(0.0, n & ~(0x000fffff >> k))
      n = ((n & 0x000fffff) | 0x00100000) >> (20 - k)
      if j < 0 { n = -n }
      pH -= t
    }
    t = withLo(pL + pH, 0)
    u = t * LG2_H
    v = (pL - (t - pH)) * LG2 + t * LG2_L
    z = u + v
    w = v - (z - u)
    t = z * z
    t1 = z - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
    r = (z * t1) / (t1 - 2.0) - (w + z * w)
    z = 1.0 - (r - z)
    j = hi(z)
    j = j &+ (n << 20)
    if (j >> 20) <= 0 { z = scalbn(z, Int(n)) } else { z = withHi(z, hi(z) &+ (n << 20)) }
    return s * z
  }
}
