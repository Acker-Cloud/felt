/* fdlibm 5.3 in JS, the same code as ios/FeltSim/Sources/FeltSim/JSMath.swift (both ported from the
   JDK's FdLibm.java, StrictMath's reference). Engines differ in the last bit of Math.sin, cos, tan,
   atan, acos, exp and pow (V8 on arm64 fuses multiply-adds, JavaScriptCore calls the system libm),
   and felt's physics is chaotic, so the iOS port's goldens run index.html's sim on these instead
   (tools/ios-golden.cjs): one reference, the same on every machine. hypot is V8's own builtin
   (Kahan sum normalised to the largest), the same on every V8, so Math.hypot is kept.
   Only what the sim region calls (physics, rules and the CPU). Pure doubles; every operation is a single IEEE-754 rounding. */
'use strict';
const dv = new DataView(new ArrayBuffer(8));
const hi = x => { dv.setFloat64(0, x); return dv.getInt32(0); };
const lo = x => { dv.setFloat64(0, x); return dv.getInt32(4); };
const withLo = (x, l) => { dv.setFloat64(0, x); dv.setInt32(4, l); return dv.getFloat64(0); };
const withHi = (x, h) => { dv.setFloat64(0, x); dv.setInt32(0, h); return dv.getFloat64(0); };
const hiLo = (h, l) => { dv.setInt32(0, h); dv.setInt32(4, l); return dv.getFloat64(0); };
const trunc0 = x => Math.trunc(x) === 0;
const EXP_BITS = 0x7ff00000, SIGNIF = 0x7fffffff;

const S1 = -0x15555555555549 / 2 ** 55, S2 = 0x1111111110f8a6 / 2 ** 59, S3 = -0x1a01a019c161d5 / 2 ** 65,
  S4 = 0x171de357b1fe7d / 2 ** 71, S5 = -0x1ae5e68a2b9ceb / 2 ** 78, S6 = 0x15d93a5acfd57c / 2 ** 85;
/* hex-float literals as integer mantissa / power of two: exact, as JS has no 0x1.8p3 syntax */
const hf = (m, e) => m * 2 ** e;
function kSin(x, y, iy) {
  const ix = hi(x) & SIGNIF;
  if (ix < 0x3e400000 && trunc0(x)) return x;
  const z = x * x, v = z * x, r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
  if (iy === 0) return x + v * (S1 + z * r);
  return x - ((z * (0.5 * y - v * r) - y) - v * S1);
}
const C1 = 0x1555555555554c / 2 ** 57, C2 = -0x16c16c16c15177 / 2 ** 62, C3 = 0x1a01a019cb1590 / 2 ** 68,
  C4 = -0x127e4f809c52ad / 2 ** 74, C5 = 0x11ee9ebdb4b1c4 / 2 ** 81, C6 = -0x18fae9be8838d4 / 2 ** 89;
function kCos(x, y) {
  const ix = hi(x) & SIGNIF;
  if (ix < 0x3e400000 && trunc0(x)) return 1.0;
  const z = x * x, r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
  if (ix < 0x3FD33333) return 1.0 - (0.5 * z - (z * r - x * y));
  const qx = ix > 0x3fe90000 ? 0.28125 : hiLo(ix - 0x00200000, 0);
  const hz = 0.5 * z - qx, a = 1.0 - qx;
  return a - (hz - (z * r - x * y));
}
const T = [hf(0x15555555555563, -54), hf(0x1111111110fe7a, -55), hf(0x1ba1ba1bb341fe, -57), hf(0x1664f48406d637, -58),
  hf(0x1226e3e96e8493, -59), hf(0x1d6d22c9560328, -61), hf(0x17dbc8fee08315, -62), hf(0x1344d8f2f26501, -63), hf(0x1026f71a8d1068, -64),
  hf(0x147e88a03792a6, -66), hf(0x12b80f32f0a7e9, -66), -hf(0x1375cbdb605373, -68), hf(0x1b2a7074bf7ad4, -68)];
const PIO4 = hf(0x1921fb54442d18, -53), PIO4LO = hf(0x11a62633145c07, -107);
function kTan(x, y, iy) {
  let z, r, v, w, s;
  const hx = hi(x), ix = hx & SIGNIF;
  if (ix < 0x3e300000 && trunc0(x)) {
    if (((ix | lo(x)) | (iy + 1)) === 0) return 1.0 / Math.abs(x);
    if (iy === 1) return x;
    w = x + y; z = withLo(w, 0); v = y - (z - x);
    const a = -1.0 / w, t = withLo(a, 0); s = 1.0 + t * z;
    return t + a * (s + t * v);
  }
  if (ix >= 0x3FE59428) {
    if (hx < 0) { x = -x; y = -y; }
    z = PIO4 - x; w = PIO4LO - y; x = z + w; y = 0.0;
  }
  z = x * x; w = z * z;
  r = T[1] + w * (T[3] + w * (T[5] + w * (T[7] + w * (T[9] + w * T[11]))));
  v = z * (T[2] + w * (T[4] + w * (T[6] + w * (T[8] + w * (T[10] + w * T[12])))));
  s = z * x;
  r = y + z * (s * (r + v) + y);
  r += T[0] * s;
  w = x + r;
  if (ix >= 0x3FE59428) { v = iy; return (1 - ((hx >> 30) & 2)) * (v - 2.0 * (x - (w * w / (w + v) - r))); }
  if (iy === 1) return w;
  z = withLo(w, 0); v = r - (z - x);
  const a = -1.0 / w, t = withLo(a, 0); s = 1.0 + t * z;
  return t + a * (s + t * v);
}
const NPIO2HW = [0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB, 0x402921FB, 0x402C463A,
  0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A, 0x403DD85A,
  0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C, 0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB,
  0x40478FDB, 0x404858EB, 0x404921FB];
const INVPIO2 = hf(0x145f306dc9c883, -53), PIO2_1 = hf(0x1921fb544, -32), PIO2_1T = hf(0x10b4611a626331, -86),
  PIO2_2 = hf(0x10b4611a6, -66), PIO2_2T = hf(0x13198a2e037073, -121), PIO2_3 = hf(0x13198a2e, -97), PIO2_3T = hf(0x1b839a252049c1, -156);
function remPio2(x) {
  const hx = hi(x), ix = hx & SIGNIF;
  if (ix <= 0x3fe921fb) return [0, x, 0];
  if (ix < 0x4002d97c) {
    if (hx > 0) {
      let z = x - PIO2_1;
      if (ix !== 0x3ff921fb) { const y0 = z - PIO2_1T; return [1, y0, (z - y0) - PIO2_1T]; }
      z -= PIO2_2; const y0 = z - PIO2_2T; return [1, y0, (z - y0) - PIO2_2T];
    }
    let z = x + PIO2_1;
    if (ix !== 0x3ff921fb) { const y0 = z + PIO2_1T; return [-1, y0, (z - y0) + PIO2_1T]; }
    z += PIO2_2; const y0 = z + PIO2_2T; return [-1, y0, (z - y0) + PIO2_2T];
  }
  if (ix > 0x413921fb) throw new Error('fdlibm: angle too large for the ported reduction');
  let t = Math.abs(x);
  const n = Math.trunc(t * INVPIO2 + 0.5), fn = n;
  let r = t - fn * PIO2_1, w = fn * PIO2_1T, y0;
  if (n < 32 && ix !== NPIO2HW[n - 1]) y0 = r - w;
  else {
    const j = ix >> 20;
    y0 = r - w;
    let i = j - ((hi(y0) >> 20) & 0x7ff);
    if (i > 16) {
      t = r; w = fn * PIO2_2; r = t - w; w = fn * PIO2_2T - ((t - r) - w); y0 = r - w;
      i = j - ((hi(y0) >> 20) & 0x7ff);
      if (i > 49) { t = r; w = fn * PIO2_3; r = t - w; w = fn * PIO2_3T - ((t - r) - w); y0 = r - w; }
    }
  }
  const y1 = (r - y0) - w;
  return hx < 0 ? [-n, -y0, -y1] : [n, y0, y1];
}
function sin(x) {
  const ix = hi(x) & SIGNIF;
  if (ix <= 0x3fe921fb) return kSin(x, 0, 0);
  if (ix >= EXP_BITS) return x - x;
  const [n, a, b] = remPio2(x);
  switch (n & 3) { case 0: return kSin(a, b, 1); case 1: return kCos(a, b); case 2: return -kSin(a, b, 1); default: return -kCos(a, b); }
}
function cos(x) {
  const ix = hi(x) & SIGNIF;
  if (ix <= 0x3fe921fb) return kCos(x, 0);
  if (ix >= EXP_BITS) return x - x;
  const [n, a, b] = remPio2(x);
  switch (n & 3) { case 0: return kCos(a, b); case 1: return -kSin(a, b, 1); case 2: return -kCos(a, b); default: return kSin(a, b, 1); }
}
function tan(x) {
  const ix = hi(x) & SIGNIF;
  if (ix <= 0x3fe921fb) return kTan(x, 0, 1);
  if (ix >= EXP_BITS) return x - x;
  const [n, a, b] = remPio2(x);
  return kTan(a, b, 1 - ((n & 1) << 1));
}
const ATANHI = [hf(0x1dac670561bb4f, -54), hf(0x1921fb54442d18, -53), hf(0x1f730bd281f69b, -53), hf(0x1921fb54442d18, -52)];
const ATANLO = [hf(0x1a2b7f222f65e2, -108), hf(0x11a62633145c07, -107), hf(0x1007887af0cbbd, -108), hf(0x11a62633145c07, -106)];
const AT = [hf(0x1555555555550d, -54), -hf(0x1999999998ebc4, -55), hf(0x124924920083ff, -55), -hf(0x1c71c6fe231671, -56),
  hf(0x1745cdc54c206e, -56), -hf(0x13b0f2af749a6d, -56), hf(0x110d66a0d03d51, -56), -hf(0x1dde2d52defd9a, -57), hf(0x197b4b24760deb, -57),
  -hf(0x12b4442c6a6c2f, -57), hf(0x10ad3ae322da11, -58)];
function atan(x) {
  const hx = hi(x), ix = hx & SIGNIF;
  let id;
  if (ix >= 0x44100000) {
    if (ix > EXP_BITS || (ix === EXP_BITS && lo(x) !== 0)) return x + x;
    return hx > 0 ? ATANHI[3] + ATANLO[3] : -ATANHI[3] - ATANLO[3];
  }
  if (ix < 0x3fdc0000) {
    if (ix < 0x3e200000) return x;
    id = -1;
  } else {
    x = Math.abs(x);
    if (ix < 0x3ff30000) {
      if (ix < 0x3fe60000) { id = 0; x = (2.0 * x - 1.0) / (2.0 + x); } else { id = 1; x = (x - 1.0) / (x + 1.0); }
    } else if (ix < 0x40038000) { id = 2; x = (x - 1.5) / (1.0 + 1.5 * x); } else { id = 3; x = -1.0 / x; }
  }
  let z = x * x;
  const w = z * z;
  const s1 = z * (AT[0] + w * (AT[2] + w * (AT[4] + w * (AT[6] + w * (AT[8] + w * AT[10])))));
  const s2 = w * (AT[1] + w * (AT[3] + w * (AT[5] + w * (AT[7] + w * AT[9]))));
  if (id < 0) return x - x * (s1 + s2);
  z = ATANHI[id] - ((x * (s1 + s2) - ATANLO[id]) - x);
  return hx < 0 ? -z : z;
}
const PIO2_HI = hf(0x1921fb54442d18, -52), PIO2_LO = hf(0x11a62633145c07, -106),
  PS0 = hf(0x15555555555555, -55), PS1 = -hf(0x14d61203eb6f7d, -54), PS2 = hf(0x19c1550e884455, -55), PS3 = -hf(0x148228b5688f3b, -57),
  PS4 = hf(0x19efe07501b288, -63), PS5 = hf(0x123de10dfdf709, -67),
  QS1 = -hf(0x133a271c8a2d4b, -51), QS2 = hf(0x102ae59c598ac8, -51), QS3 = -hf(0x16066c1b8d0159, -53), QS4 = hf(0x13b8c5b12e9282, -56);
function acos(x) {
  const hx = hi(x), ix = hx & SIGNIF;
  if (ix >= 0x3ff00000) {
    if (((ix - 0x3ff00000) | lo(x)) === 0) return hx > 0 ? 0.0 : Math.PI + 2.0 * PIO2_LO;
    return (x - x) / (x - x);
  }
  const P = z => z * (PS0 + z * (PS1 + z * (PS2 + z * (PS3 + z * (PS4 + z * PS5)))));
  const Q = z => 1.0 + z * (QS1 + z * (QS2 + z * (QS3 + z * QS4)));
  if (ix < 0x3fe00000) {
    if (ix <= 0x3c600000) return PIO2_HI + PIO2_LO;
    const z = x * x;
    return PIO2_HI - (x - (PIO2_LO - x * (P(z) / Q(z))));
  } else if (hx < 0) {
    const z = (1.0 + x) * 0.5, s = Math.sqrt(z), w = (P(z) / Q(z)) * s - PIO2_LO;
    return Math.PI - 2.0 * (s + w);
  }
  const z = (1.0 - x) * 0.5, s = Math.sqrt(z), df = withLo(s, 0), c = (z - df * df) / (s + df);
  const w = (P(z) / Q(z)) * s + c;
  return 2.0 * (df + w);
}
const P1 = hf(0x1555555555553e, -55), P2 = -hf(0x16c16c16bebd93, -61), P3 = hf(0x11566aaf25de2c, -66),
  P4 = -hf(0x1bbd41c5d26bf1, -72), P5 = hf(0x16376972bea4d0, -77);
const LN2HI = hf(0x162e42fee, -33), LN2LO = hf(0x1a39ef35793c76, -85), INVLN2 = hf(0x171547652b82fe, -52);
function exp(x) {
  let hi_ = 0.0, lo_ = 0.0, k = 0;
  let hx = hi(x);
  const xsb = (hx >> 31) & 1;
  hx &= SIGNIF;
  if (hx >= 0x40862E42) {
    if (hx >= 0x7ff00000) return ((hx & 0xfffff) | lo(x)) !== 0 ? x + x : (xsb === 0 ? x : 0.0);
    if (x > hf(0x162e42fefa39ef, -43)) return Infinity;
    if (x < -hf(0x174910d52d3051, -43)) return 0;
  }
  if (hx > 0x3fd62e42) {
    if (hx < 0x3FF0A2B2) {
      hi_ = x - (xsb === 0 ? LN2HI : -LN2HI); lo_ = xsb === 0 ? LN2LO : -LN2LO; k = 1 - xsb - xsb;
    } else {
      k = Math.trunc(INVLN2 * x + (xsb === 0 ? 0.5 : -0.5));
      const t = k;
      hi_ = x - t * LN2HI; lo_ = t * LN2LO;
    }
    x = hi_ - lo_;
  } else if (hx < 0x3e300000) return 1.0 + x;
  const t = x * x, c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
  if (k === 0) return 1.0 - ((x * c) / (c - 2.0) - x);
  const y = 1.0 - ((lo_ - (x * c) / (2.0 - c)) - hi_);
  if (k >= -1021) return withHi(y, (hi(y) + (k << 20)) | 0);
  return withHi(y, (hi(y) + ((k + 1000) << 20)) | 0) * 2 ** -1000;
}
function scalbn(x, n) { return x * 2 ** n; }   /* only reached for a subnormal result, which the sim never makes */
function pow(x, y) {
  if (y === 0) return 1.0;
  if (Number.isNaN(x) || Number.isNaN(y)) return x + y;
  const yAbs = Math.abs(y);
  let xAbs = Math.abs(x);
  if (y === 2.0) return x * x;
  if (y === 0.5) { if (x >= -Number.MAX_VALUE) return Math.sqrt(x + 0.0); } else if (yAbs === 1.0) return y === 1.0 ? x : 1.0 / x;
  else if (yAbs === Infinity) {
    if (xAbs === 1.0) return y - y;
    if (xAbs > 1.0) return y >= 0 ? y : 0.0;
    return y < 0 ? -y : 0.0;
  }
  const hx = hi(x);
  let ix = hx & SIGNIF, yIsInt = 0;
  if (hx < 0) {
    if (yAbs >= 2 ** 53) yIsInt = 2;
    else if (yAbs >= 1.0) { const l = Math.trunc(yAbs); if (l === yAbs) yIsInt = 2 - (l % 2); }
  }
  if (xAbs === 0.0 || xAbs === Infinity || xAbs === 1.0) {
    let z = xAbs;
    if (y < 0.0) z = 1.0 / z;
    if (hx < 0) { if (((ix - 0x3ff00000) | yIsInt) === 0) z = (z - z) / (z - z); else if (yIsInt === 1) z = -1.0 * z; }
    return z;
  }
  let n = (hx >> 31) + 1;
  if ((n | yIsInt) === 0) return (x - x) / (x - x);
  let s = 1.0;
  if ((n | (yIsInt - 1)) === 0) s = -1.0;
  let t1, t2, t, u, v, w, r, z, pH, pL;
  if (yAbs > hf(0x100000ffffffff, -21)) {
    if (xAbs < hf(0x1fffff00000000, -53)) return y < 0.0 ? s * Infinity : s * 0.0;
    if (xAbs > hf(0x100000ffffffff, -52)) return y > 0.0 ? s * Infinity : s * 0.0;
    t = xAbs - 1.0;
    w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
    u = hf(0x1715476, -24) * t;
    v = t * hf(0x14ae0bf85ddf44, -78) - w * INVLN2;
    t1 = withLo(u + v, 0);
    t2 = v - (t1 - u);
  } else {
    const CP = hf(0x1ec709dc3a03fd, -53), CP_H = hf(0x1ec709e, -25), CP_L = -hf(0x1e2fe0145b01f5, -80);
    n = 0;
    if (ix < 0x00100000) { xAbs *= 2 ** 53; n -= 53; ix = hi(xAbs); }
    n += (ix >> 20) - 0x3ff;
    const j = ix & 0x000fffff;
    ix = j | 0x3ff00000;
    let k;
    if (j <= 0x3988E) k = 0; else if (j < 0xBB67A) k = 1; else { k = 0; n += 1; ix -= 0x00100000; }
    xAbs = withHi(xAbs, ix);
    const BP = [1.0, 1.5], DP_H = [0.0, hf(0x12b8034, -25)], DP_L = [0.0, hf(0x1cfdeb43cfd006, -79)];
    const L1 = hf(0x13333333333303, -53), L2 = hf(0x1b6db6db6fabff, -54), L3 = hf(0x155555518f264d, -54),
      L4 = hf(0x117460a91d4101, -54), L5 = hf(0x1d864a93c9db65, -55), L6 = hf(0x1a7e284a454eef, -55);
    u = xAbs - BP[k];
    v = 1.0 / (xAbs + BP[k]);
    const ss = u * v, sH = withLo(ss, 0);
    let tH = withHi(0.0, ((ix >> 1) | 0x20000000) + 0x00080000 + (k << 18));
    let tL = xAbs - (tH - BP[k]);
    const sL = v * ((u - sH * tH) - sH * tL);
    let s2 = ss * ss;
    r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))));
    r += sL * (sH + ss);
    s2 = sH * sH;
    tH = withLo(3.0 + s2 + r, 0);
    tL = r - ((tH - 3.0) - s2);
    u = sH * tH;
    v = sL * tH + tL * ss;
    pH = withLo(u + v, 0);
    pL = v - (pH - u);
    const zH = CP_H * pH, zL = CP_L * pH + pL * CP + DP_L[k];
    t = n;
    t1 = withLo(((zH + zL) + DP_H[k]) + t, 0);
    t2 = zL - (((t1 - t) - DP_H[k]) - zH);
  }
  const y1 = withLo(y, 0);
  pL = (y - y1) * t1 + y * t2;
  pH = y1 * t1;
  z = pL + pH;
  let j = hi(z), i = lo(z);
  if (j >= 0x40900000) {
    if (((j - 0x40900000) | i) !== 0) return s * Infinity;
    if (pL + 8.0085662595372944372e-0017 > z - pH) return s * Infinity;
  } else if ((j & SIGNIF) >= 0x4090cc00) {
    if ((((j - (0xc090cc00 | 0)) | 0) | i) !== 0) return s * 0.0;
    if (pL <= z - pH) return s * 0.0;
  }
  const LG2 = hf(0x162e42fefa39ef, -53), LG2_H = hf(0x162e43, -21), LG2_L = -hf(0x105c610ca86c39, -81);
  i = j & SIGNIF;
  let k = (i >> 20) - 0x3ff;
  n = 0;
  if (i > 0x3fe00000) {
    n = (j + (0x00100000 >> (k + 1))) | 0;
    k = ((n & SIGNIF) >> 20) - 0x3ff;
    t = withHi(0.0, n & ~(0x000fffff >> k));
    n = ((n & 0x000fffff) | 0x00100000) >> (20 - k);
    if (j < 0) n = -n;
    pH -= t;
  }
  t = withLo(pL + pH, 0);
  u = t * LG2_H;
  v = (pL - (t - pH)) * LG2 + t * LG2_L;
  z = u + v;
  w = v - (z - u);
  t = z * z;
  t1 = z - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
  r = (z * t1) / (t1 - 2.0) - (w + z * w);
  z = 1.0 - (r - z);
  j = (hi(z) + (n << 20)) | 0;
  if ((j >> 20) <= 0) z = scalbn(z, n); else z = withHi(z, (hi(z) + (n << 20)) | 0);
  return s * z;
}
const ASIN_PIO4 = PIO4;
function asin(x) {
  let t = 0, w, p, q, c, r, s;
  const hx = hi(x), ix = hx & SIGNIF;
  if (ix >= 0x3ff00000) {
    if (((ix - 0x3ff00000) | lo(x)) === 0) return x * PIO2_HI + x * PIO2_LO;
    return (x - x) / (x - x);
  } else if (ix < 0x3fe00000) {
    if (ix < 0x3e400000) return x;
    t = x * x;
    p = t * (PS0 + t * (PS1 + t * (PS2 + t * (PS3 + t * (PS4 + t * PS5)))));
    q = 1.0 + t * (QS1 + t * (QS2 + t * (QS3 + t * QS4)));
    w = p / q;
    return x + x * w;
  }
  w = 1.0 - Math.abs(x);
  t = w * 0.5;
  p = t * (PS0 + t * (PS1 + t * (PS2 + t * (PS3 + t * (PS4 + t * PS5)))));
  q = 1.0 + t * (QS1 + t * (QS2 + t * (QS3 + t * QS4)));
  s = Math.sqrt(t);
  if (ix >= 0x3FEF3333) { w = p / q; t = PIO2_HI - (2.0 * (s + s * w) - PIO2_LO); }
  else {
    w = withLo(s, 0); c = (t - w * w) / (s + w); r = p / q;
    p = 2.0 * s * r - (PIO2_LO - 2.0 * c); q = ASIN_PIO4 - 2.0 * w; t = ASIN_PIO4 - (p - q);
  }
  return hx > 0 ? t : -t;
}
const PI_LO = hf(0x11a62633145c07, -105), TINY = 1.0e-300;
function atan2(y, x) {
  const hx = hi(x), ix = hx & SIGNIF, lx = lo(x), hy = hi(y), iy = hy & SIGNIF, ly = lo(y);
  if (Number.isNaN(x) || Number.isNaN(y)) return x + y;
  if (((hx - 0x3ff00000) | lx) === 0) return atan(y);
  const m = ((hy >> 31) & 1) | ((hx >> 30) & 2);
  if ((iy | ly) === 0) { switch (m) { case 0: case 1: return y; case 2: return Math.PI + TINY; default: return -Math.PI - TINY; } }
  if ((ix | lx) === 0) return hy < 0 ? -PIO2_HI - TINY : PIO2_HI + TINY;
  if (ix === EXP_BITS) {
    if (iy === EXP_BITS) { switch (m) { case 0: return PIO4 + TINY; case 1: return -PIO4 - TINY; case 2: return 3.0 * PIO4 + TINY; default: return -3.0 * PIO4 - TINY; } }
    switch (m) { case 0: return 0.0; case 1: return -0.0; case 2: return Math.PI + TINY; default: return -Math.PI - TINY; }
  }
  if (iy === EXP_BITS) return hy < 0 ? -PIO2_HI - TINY : PIO2_HI + TINY;
  const k = (iy - ix) >> 20;
  let z;
  if (k > 60) z = PIO2_HI + 0.5 * PI_LO;
  else if (hx < 0 && k < -60) z = 0.0;
  else z = atan(Math.abs(y / x));
  switch (m) { case 0: return z; case 1: return -z; case 2: return Math.PI - (z - PI_LO); default: return (z - PI_LO) - Math.PI; }
}
const LP = [hf(0x15555555555593, -53), hf(0x1999999997fa04, -54), hf(0x12492494229359, -54), hf(0x1c71c51d8e78af, -55), hf(0x17466496cb03de, -55), hf(0x139a09d078c69f, -55), hf(0x12f112df3e5244, -55)];
function log1p(x) {
  let hfsq, f = 0, c = 0, s, z, R, u, k = 1, hu = 0;
  const hx = hi(x), ax = hx & SIGNIF;
  if (hx < 0x3FDA827A) {
    if (ax >= 0x3ff00000) return x === -1.0 ? -Infinity : NaN;
    if (ax < 0x3e200000) { if (2 ** 54 + x > 0.0 && ax < 0x3c900000) return x; return x - x * x * 0.5; }
    if (hx > 0 || hx <= (0xbfd2bec3 | 0)) { k = 0; f = x; hu = 1; }
  }
  if (hx >= EXP_BITS) return x + x;
  if (k !== 0) {
    if (hx < 0x43400000) { u = 1.0 + x; hu = hi(u); k = (hu >> 20) - 1023; c = k > 0 ? 1.0 - (u - x) : x - (u - 1.0); c /= u; }
    else { u = x; hu = hi(u); k = (hu >> 20) - 1023; c = 0; }
    hu &= 0x000fffff;
    if (hu < 0x6a09e) u = withHi(u, hu | 0x3ff00000);
    else { k += 1; u = withHi(u, hu | 0x3fe00000); hu = (0x00100000 - hu) >> 2; }
    f = u - 1.0;
  }
  hfsq = 0.5 * f * f;
  if (hu === 0) {
    if (f === 0.0) { if (k === 0) return 0.0; c += k * LN2LO; return k * LN2HI + c; }
    R = hfsq * (1.0 - 0.66666666666666666 * f);
    if (k === 0) return f - R;
    return k * LN2HI - ((R - (k * LN2LO + c)) - f);
  }
  s = f / (2.0 + f);
  z = s * s;
  R = z * (LP[0] + z * (LP[1] + z * (LP[2] + z * (LP[3] + z * (LP[4] + z * (LP[5] + z * LP[6]))))));
  if (k === 0) return f - (hfsq - s * (hfsq + R));
  return k * LN2HI - ((hfsq - (s * (hfsq + R) + (k * LN2LO + c))) - f);
}
/* e_log.c: __ieee754_log (FdLibm.java's Log), the career engine's gauss and levelOf */
function log(x) {
  let hx = hi(x), k = 0;
  const lx = lo(x);
  if (hx < 0x00100000) {
    if (((hx & SIGNIF) | lx) === 0) return -Infinity;
    if (hx < 0) return NaN;
    k -= 54; x *= 2 ** 54; hx = hi(x);
  }
  if (hx >= EXP_BITS) return x + x;
  k += (hx >> 20) - 1023;
  hx &= 0x000fffff;
  let i = (hx + 0x95f64) & 0x100000;
  x = withHi(x, hx | (i ^ 0x3ff00000));
  k += i >> 20;
  const f = x - 1.0;
  if ((0x000fffff & (2 + hx)) < 3) {
    if (f === 0.0) { if (k === 0) return 0.0; const dk = k; return dk * LN2HI + dk * LN2LO; }
    const R = f * f * (0.5 - 0.33333333333333333 * f);
    if (k === 0) return f - R;
    const dk = k; return dk * LN2HI - ((R - dk * LN2LO) - f);
  }
  const s = f / (2.0 + f), dk = k, z = s * s;
  i = hx - 0x6147a;
  const w = z * z, j = 0x6b851 - hx;
  const t1 = w * (LP[1] + w * (LP[3] + w * LP[5])), t2 = z * (LP[0] + w * (LP[2] + w * (LP[4] + w * LP[6])));
  i |= j;
  const R = t2 + t1;
  if (i > 0) {
    const hfsq = 0.5 * f * f;
    if (k === 0) return f - (hfsq - s * (hfsq + R));
    return dk * LN2HI - ((hfsq - (s * (hfsq + R) + dk * LN2LO)) - f);
  }
  if (k === 0) return f - s * (f - R);
  return dk * LN2HI - ((s * (f - R) - dk * LN2LO) - f);
}
const Q = [-hf(0x111111111110f4, -57), hf(0x1a01a019fe5585, -62), -hf(0x14ce199eaadbb7, -66), hf(0x10cfca86e65239, -70), -hf(0x1afdb76e09c32d, -75)];
function expm1(x) {
  let y, hi_, lo_, c = 0, t, e, hxs, hfx, r1, k;
  let hx = hi(x);
  const xsb = hx & (0x80000000 | 0);
  y = Math.abs(x);
  hx &= SIGNIF;
  if (hx >= 0x4043687A) {
    if (hx >= 0x40862E42) {
      if (hx >= 0x7ff00000) { if (((hx & 0xfffff) | lo(x)) !== 0) return x + x; return xsb === 0 ? x : -1.0; }
      if (x > hf(0x162e42fefa39ef, -43)) return Infinity;
    }
    if (xsb !== 0) { if (x + TINY < 0.0) return TINY - 1.0; }
  }
  if (hx > 0x3fd62e42) {
    if (hx < 0x3FF0A2B2) {
      if (xsb === 0) { hi_ = x - LN2HI; lo_ = LN2LO; k = 1; } else { hi_ = x + LN2HI; lo_ = -LN2LO; k = -1; }
    } else {
      k = Math.trunc(INVLN2 * x + (xsb === 0 ? 0.5 : -0.5));
      t = k; hi_ = x - t * LN2HI; lo_ = t * LN2LO;
    }
    x = hi_ - lo_;
    c = (hi_ - x) - lo_;
  } else if (hx < 0x3c900000) {
    t = 1.0e300 + x;
    return x - (t - (1.0e300 + x));
  } else k = 0;
  hfx = 0.5 * x;
  hxs = x * hfx;
  r1 = 1.0 + hxs * (Q[0] + hxs * (Q[1] + hxs * (Q[2] + hxs * (Q[3] + hxs * Q[4]))));
  t = 3.0 - r1 * hfx;
  e = hxs * ((r1 - t) / (6.0 - x * t));
  if (k === 0) return x - (x * e - hxs);
  e = (x * (e - c) - c);
  e -= hxs;
  if (k === -1) return 0.5 * (x - e) - 0.5;
  if (k === 1) { if (x < -0.25) return -2.0 * (e - (x + 0.5)); return 1.0 + 2.0 * (x - e); }
  if (k <= -2 || k > 56) { y = 1.0 - (e - x); y = withHi(y, (hi(y) + (k << 20)) | 0); return y - 1.0; }
  t = 1.0;
  if (k < 20) { t = withHi(t, 0x3ff00000 - (0x200000 >> k)); y = t - (e - x); y = withHi(y, (hi(y) + (k << 20)) | 0); }
  else { t = withHi(t, (0x3ff - k) << 20); y = x - (e + t); y += 1.0; y = withHi(y, (hi(y) + (k << 20)) | 0); }
  return y;
}
function tanh(x) {
  let t, z;
  const jx = hi(x), ix = jx & SIGNIF;
  if (ix >= EXP_BITS) return jx >= 0 ? 1.0 / x + 1.0 : 1.0 / x - 1.0;
  if (ix < 0x40360000) {
    if (ix < 0x3c800000) return x * (1.0 + x);
    if (ix >= 0x3ff00000) { t = expm1(2.0 * Math.abs(x)); z = 1.0 - 2.0 / (t + 2.0); }
    else { t = expm1(-2.0 * Math.abs(x)); z = -t / (t + 2.0); }
  } else z = 1.0 - TINY;
  return jx >= 0 ? z : -z;
}
/* fdlibm's e_atanh.c (the JDK has none): through log1p */
function atanh(x) {
  const hx = hi(x), lx = lo(x), ix = hx & SIGNIF;
  if ((ix | (lx !== 0 ? 1 : 0)) > 0x3ff00000) return (x - x) / (x - x);
  if (ix === 0x3ff00000) return x / 0;
  if (ix < 0x3e300000 && 1e300 + x > 0) return x;
  x = withHi(x, ix);
  let t;
  if (ix < 0x3fe00000) { t = x + x; t = 0.5 * log1p(t + t * x / (1.0 - x)); }
  else t = 0.5 * log1p((x + x) / (1.0 - x));
  return hx >= 0 ? t : -t;
}
/* a Math with the transcendental functions swapped; everything else (sqrt, hypot, max, ...) is the engine's, which is exact or V8's own */
function fdMath(base = Math) {
  const M = Object.create(null);
  for (const k of Object.getOwnPropertyNames(base)) M[k] = base[k];
  Object.assign(M, { sin, cos, tan, atan, acos, exp, pow, asin, atan2, tanh, atanh, log1p, expm1, log });
  return M;
}
module.exports = { sin, cos, tan, atan, acos, exp, pow, asin, atan2, tanh, atanh, log1p, expm1, log, fdMath };
