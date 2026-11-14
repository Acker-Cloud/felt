/* Goldens for the iOS port (ios/FeltSim). Runs index.html's own sim region (tests/sim.cjs's
   regionSource) in a vm whose Math has fdlibm's transcendental functions (tools/fdlibm.cjs), the
   same code as the Swift port's JSMath, so the reference is one set of doubles on every machine.
   speedOf and powerFor's `**` (the engine's pow, not Math.pow) are rewritten to Math.pow; `** 2` is
   left, as every engine squares exactly. Writes, under ios/FeltSim/Tests/FeltSimTests/Fixtures/:
     math.txt     inputs and fdlibm outputs, hex bits, for JSMath's own test
     golden.json  per table its geometry, per shot the input, the full resultOf, the hits and a
                  hash of every ball every HASH_EVERY steps (the first step that differs, found)
   Every double is its IEEE-754 bit pattern in hex. Re-run after any change to sim 1a-1d:
     node tools/ios-golden.cjs                                                              */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { regionSource } = require('../tests/sim.cjs');
const F = require('./fdlibm.cjs');

const OUT = path.join(__dirname, '..', 'ios', 'FeltSim', 'Tests', 'FeltSimTests', 'Fixtures');
const HASH_EVERY = 240;

/* 4d's geometry and preview, the page's own source, cut from index.html (they read game, cueBall and
   performance, which the shim gives them) */
function guideSource() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const cut = (a, b) => { const i = html.indexOf(a), j = html.indexOf(b, i); if (i < 0 || j < 0) throw new Error('ios-golden: 4d moved: ' + a); return html.slice(i, j); };
  return cut('function aimSweep(', '/* polylines and rings') + cut('const PV_CAP = ', '/* the preview for this aim');
}
function loadFd() {
  let src = regionSource() + '\n;let game = null; const cueBall = () => game.balls.find(b => b.n === game.cue); const performance = { now: () => 0 };\n' + guideSource();
  const pw = [['clamp(power, 0, 1) ** POWER_EXP', 'Math.pow(clamp(power, 0, 1), POWER_EXP)'],
    ['clamp((v - MIN_V) / (MAX_V - MIN_V), 0, 1) ** (1 / POWER_EXP)', 'Math.pow(clamp((v - MIN_V) / (MAX_V - MIN_V), 0, 1), 1 / POWER_EXP)']];
  for (const [a, b] of pw) { if (!src.includes(a)) throw new Error('ios-golden: sim changed, update the pow rewrite: ' + a); src = src.replace(a, b); }
  const ctx = vm.createContext({});
  ctx.__fd = F.fdMath(vm.runInContext('Math', ctx));
  const names = ['setTable', 'setPockets', 'rack', 'snookerRack', 'newBall', 'newTable', 'strike', 'stepTable', 'resultOf', 'spinOf',
    'aimTrace', 'previewStart', 'previewRun', 'PV_FULL', 'PV_SHORT', 'PV_CAROM', 'setGame', 'TL', 'TW', 'HEAD_X', 'FOOT', 'BALL_R', 'CUSH', 'POCKETS', 'POCKET_R', 'POCKET_AIM', 'JAW_ARCS', 'CUSHION_POLYS', 'SPOTS', 'D_R'];
  src += '\n;function setGame(g) { game = g; }';
  const exp = names.map(n => `get ${n}() { return typeof ${n} === 'undefined' ? undefined : ${n}; }`).join(',');
  vm.runInContext(`globalThis.__sim = (function () { 'use strict'; const Math = globalThis.__fd; const { Object, JSON, Number, Array } = globalThis;\n${src}\n;return { ${exp} }; })();`, ctx);
  return ctx.__sim;
}

const dv = new DataView(new ArrayBuffer(8));
const hx = v => { dv.setFloat64(0, v); return dv.getBigUint64(0).toString(16).padStart(16, '0'); };
/* FNV-1a, 32 bit, over a ball list's state, in the Swift test's order */
function fnv(h, w) { h ^= w; return Math.imul(h, 16777619) >>> 0; }
function hashBalls(B) {
  let h = 2166136261;
  for (const b of B) {
    h = fnv(h, b.n); h = fnv(h, b.on ? 1 : 0);
    for (const v of [b.x, b.y, b.vx, b.vy, b.wx, b.wy, b.wz]) { dv.setFloat64(0, v); h = fnv(h, dv.getUint32(0)); h = fnv(h, dv.getUint32(4)); }
    for (const v of [b.z, b.vz]) { if (v === undefined) h = fnv(h, 0xffffffff); else { dv.setFloat64(0, v); h = fnv(h, dv.getUint32(0)); h = fnv(h, dv.getUint32(4)); } }
  }
  return h;
}
function hashHits(H) {
  let h = 2166136261;
  for (const [k, v, e] of H) {
    for (const c of k) h = fnv(h, c.charCodeAt(0));
    dv.setFloat64(0, v); h = fnv(h, dv.getUint32(0)); h = fnv(h, dv.getUint32(4));
    h = fnv(h, e === undefined ? 0xffffffff : (e | 0) >>> 0);
  }
  return h;
}
const ballOut = b => Object.assign({ n: b.n, on: b.on, x: hx(b.x), y: hx(b.y), vx: hx(b.vx), vy: hx(b.vy), wx: hx(b.wx), wy: hx(b.wy), wz: hx(b.wz) },
  b.z === undefined ? {} : { z: hx(b.z) }, b.vz === undefined ? {} : { vz: hx(b.vz) });

let seed = 20261114;
const rnd = () => { seed = (Math.imul(seed, 1103515245) + 12345) >>> 0; return seed / 4294967296; };

function build() {
  seed = 20261114;
  const S = loadFd();

  /* math fixture: the ranges the sim calls with, and wider */
  const lines = [];
  for (let i = 0; i < 6000; i++) {
    const s = 10 ** (Math.floor(rnd() * 9) - 6), x = (rnd() - 0.5) * 2 * s * (i % 3 === 0 ? 30 : 1), y = rnd() * s * 5, p = i % 5 === 0 ? rnd() * 3 : 1.7, c = rnd() * 2 - 1;
    lines.push([x, y, p, c, F.sin(x), F.cos(x), F.tan(x), F.atan(x), F.acos(c), F.exp(-y * 1.088), F.exp(x), F.pow(y, p), F.pow(y, 1 / p),
      Math.hypot(x, y), Math.hypot(x, y, c)].map(hx).join(' '));
  }
  const math = lines.join('\n') + '\n';

  const TABLES = [['7', null, 'regulation'], ['9', null, 'regulation'], ['7', null, 'generous'], ['9', null, 'generous'],
    ['heyball', null, 'regulation'], ['snooker', 'compact', 'regulation'], ['snooker', 'full', 'regulation'], ['carom', null, 'regulation']];
  const tables = [], cases = [];
  const setT = ([t, shape, pk]) => { S.setPockets(pk); S.setTable(t, shape === null ? undefined : shape); };
  for (const T of TABLES) {
    setT(T);
    const arr = a => a.map(v => Array.isArray(v) ? arr(v) : hx(v));
    tables.push({ table: T[0], shape: T[1], pockets: T[2], TL: hx(S.TL), TW: hx(S.TW), HEAD_X: hx(S.HEAD_X), FOOT: arr(S.FOOT), BALL_R: hx(S.BALL_R),
      CUSH: arr(S.CUSH), POCKETS: arr(S.POCKETS), POCKET_R: arr(S.POCKET_R), POCKET_AIM: arr(S.POCKET_AIM), JAW_ARCS: arr(S.JAW_ARCS) });
  }
  const run = (T, name, balls, shot) => {
    setT(T);
    const sp = S.spinOf(shot.spin || 0);
    const tab = S.strike(S.newTable(balls, shot.ball || 0), shot.angle, shot.power, shot.spin || 0);
    const hashes = [];
    while (S.stepTable(tab)) if (tab.steps % HASH_EVERY === 0) hashes.push(hashBalls(tab.balls));
    const r = S.resultOf(tab);
    const obj = o => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, v]));
    cases.push({ name, table: T[0], shape: T[1], pockets: T[2], balls: balls.map(ballOut),
      shot: { angle: hx(shot.angle), power: hx(shot.power), ball: shot.ball || 0, spin: { x: hx(sp.x), y: hx(sp.y), e: hx(sp.e || 0) } },
      result: { balls: r.balls.map(ballOut), first: r.first, railAfter: r.railAfter, crossed: r.crossed, potted: r.potted, pocketOf: obj(r.pocketOf),
        end: r.end, t: hx(r.t), steps: r.steps, rails: obj(r.rails), kick: r.kick, contacts: r.contacts,
        railAt: Object.fromEntries(Object.entries(r.railAt).map(([k, p]) => [k, p.map(hx)])), seq: r.seq, railSeq: r.railSeq, over: r.over || null, escaped: tab.escaped },
      hits: tab.hits.length, hitsHash: hashHits(tab.hits), hashEvery: HASH_EVERY, hashes });
  };
  /* scattered balls, none touching, clear of the cushions */
  const scatter = (count, nums) => {
    const out = [], R = S.BALL_R;
    while (out.length < count) {
      const x = R * 2 + rnd() * (S.TL - 4 * R), y = R * 2 + rnd() * (S.TW - 4 * R);
      if (out.every(b => Math.hypot(b.x - x, b.y - y) > 2 * R + 0.002)) out.push(S.newBall(nums[out.length], x, y));
    }
    return out;
  };
  const randSpin = k => k % 4 === 0 ? 0 : k % 4 === 1 ? (rnd() * 2 - 1) : k % 4 === 2 ? { x: rnd() * 1.4 - 0.7, y: rnd() * 1.4 - 0.7 }
    : { x: rnd() * 1.2 - 0.6, y: rnd() * 1.2 - 0.6, e: rnd() * 1.0 };

  for (const T of TABLES.filter(t => t[0] !== 'snooker' && t[0] !== 'carom')) {
    for (const kind of ['8', '9', '10', 'rotation']) {
      setT(T);
      if (T[0] === 'heyball' && kind !== '8') continue;
      for (let k = 0; k < 3; k++) {
        setT(T);
        const balls = S.rack(kind === '8' && T[0] === 'heyball' ? 'heyball' : kind);
        run(T, `${T[0]}/${T[2]} ${kind}-ball break ${k}`, balls, { angle: (rnd() - 0.5) * 0.02, power: [1, 0.85, 0.6][k], spin: [0, -0.3, { x: 0.2, y: 0.1 }][k] });
      }
    }
    for (let k = 0; k < 8; k++) {
      setT(T);
      const balls = scatter(2 + Math.floor(rnd() * 7), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      run(T, `${T[0]}/${T[2]} scatter ${k}`, balls, { angle: rnd() * 2 * Math.PI, power: 0.15 + rnd() * 0.8, spin: randSpin(k) });
    }
  }
  /* jump shots and massé: a raised cue into a ball close ahead, and steep ones */
  for (const T of [TABLES[0], TABLES[1], TABLES[4]]) {
    for (let k = 0; k < 4; k++) {
      setT(T);
      const balls = [S.newBall(0, S.TL * 0.3, S.TW * 0.5), S.newBall(1, S.TL * 0.3 + 0.2, S.TW * 0.5 + 0.01 * k), S.newBall(2, S.TL * 0.75, S.TW * 0.52)];
      run(T, `${T[0]}/${T[2]} jump ${k}`, balls, { angle: 0.002 * k, power: 0.55 + 0.12 * k, spin: { x: 0.05 * k, y: 0.2, e: [0.6, 0.8, 0.95, 1.0][k] } });
    }
    setT(T);
    run(T, `${T[0]}/${T[2]} masse`, [S.newBall(0, S.TL * 0.5, S.TW * 0.3), S.newBall(5, S.TL * 0.7, S.TW * 0.5)], { angle: 0.4, power: 0.4, spin: { x: -0.7, y: -0.2, e: 1.0 } });
  }
  /* a ball frozen to the cushion (WPA 2.7) and a cue ball against it */
  for (const T of [TABLES[0], TABLES[4]]) {
    setT(T);
    const R = S.BALL_R;
    run(T, `${T[0]} frozen`, [S.newBall(0, S.TL * 0.5, S.TW * 0.5), S.newBall(3, S.TL * 0.7, R), S.newBall(4, S.TL - R, S.TW * 0.6)], { angle: -0.6, power: 0.5, spin: { x: 0.4, y: 0 } });
  }
  /* snooker: the break-off and scattered reds and colours */
  for (const T of TABLES.filter(t => t[0] === 'snooker')) {
    for (let k = 0; k < 3; k++) {
      setT(T);
      const balls = S.snookerRack(), c = balls[0], apex = balls[1];
      const ang = Math.atan2(apex.y + S.BALL_R * (0.5 + 0.3 * k) - c.y, apex.x - c.x);
      run(T, `snooker/${T[1]} break-off ${k}`, balls, { angle: ang, power: [0.55, 0.7, 0.9][k], spin: [{ x: -0.4, y: 0 }, -0.2, { x: 0.3, y: 0.3 }][k] });
    }
    for (let k = 0; k < 4; k++) {
      setT(T);
      run(T, `snooker/${T[1]} scatter ${k}`, scatter(6, [0, 41, 42, 57, 60, 62]), { angle: rnd() * 2 * Math.PI, power: 0.2 + rnd() * 0.6, spin: randSpin(k) });
    }
  }
  /* carom: the break and position shots, the struck ball the white (70) or the yellow (71) */
  const caromT = TABLES.find(t => t[0] === 'carom');
  for (let k = 0; k < 6; k++) {
    setT(caromT);
    const balls = k === 0 ? [S.newBall(70, S.HEAD_X, S.TW / 2 + 0.1524), S.newBall(71, S.HEAD_X, S.TW / 2), S.newBall(72, S.FOOT[0], S.FOOT[1])]
      : scatter(3, [70, 71, 72]);
    run(caromT, `carom ${k}`, balls, { ball: k % 2 ? 71 : 70, angle: k === 0 ? Math.atan2(S.FOOT[1] - S.TW / 2 - 0.1524, S.FOOT[0] - S.HEAD_X) + 0.03 : rnd() * 2 * Math.PI,
      power: 0.3 + rnd() * 0.5, spin: randSpin(k + 1) });
  }

  /* the guide: aimTrace and the shot preview, for racks and scatters on every table, both lengths */
  const guides = [];
  const pts = a => a ? a.map(q => q.map(hx)) : null;
  for (const T of TABLES) {
    for (let k = 0; k < 10; k++) {
      setT(T);
      const carom = T[0] === 'carom', snk = T[0] === 'snooker';
      let balls = k < 2 && !carom ? (snk ? S.snookerRack() : S.rack(T[0] === 'heyball' ? 'heyball' : '8')) : scatter(carom ? 3 : 2 + Math.floor(rnd() * 7), carom ? [70, 71, 72] : snk ? [0, 41, 42, 43, 57, 60, 62, 59] : [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      const cue = carom ? 70 : 0, c = balls.find(b => b.n === cue);
      /* aim at a ball, near it (a cut), or anywhere (a kick) */
      const tgt = balls.filter(b => b.n !== cue)[Math.floor(rnd() * (balls.length - 1))];
      const ang = k % 3 === 2 ? rnd() * 2 * Math.PI : Math.atan2(tgt.y - c.y, tgt.x - c.x) + (k % 3 ? (rnd() - 0.5) * 0.06 : 0);
      const pw = 0.15 + rnd() * 0.75, sp = S.spinOf(k % 4 === 0 ? 0 : k % 4 === 1 ? { x: rnd() - 0.5, y: rnd() - 0.5 } : k % 4 === 2 ? rnd() * 2 - 1 : { x: rnd() * 0.6 - 0.3, y: rnd() * 0.6, e: rnd() * 1.0 });
      const lens = carom ? S.PV_CAROM : k % 2 ? S.PV_SHORT : S.PV_FULL;
      S.setGame({ balls, cue, kind: carom ? 'carom' : '8', need: 3 });
      const h = S.aimTrace(c.x, c.y, Math.cos(ang), Math.sin(ang), [cue], 6);
      const P = S.previewStart(ang, pw, sp, h, lens);
      S.previewRun(P, Infinity);
      guides.push({ name: `${T[0]}/${T[2]} guide ${k}`, table: T[0], shape: T[1], pockets: T[2], balls: balls.map(ballOut), cue, carom: carom ? 3 : 0,
        ang: hx(ang), pw: hx(pw), spin: { x: hx(sp.x), y: hx(sp.y), e: hx(sp.e || 0) }, lens: lens === S.PV_CAROM ? 'carom' : lens === S.PV_SHORT ? 'short' : 'full',
        hit: { t: hx(h.t), kind: h.kind, ball: h.ball ? h.ball.n : null, nx: hx(h.nx), ny: hx(h.ny), k: h.k },
        P: { s: P.s, cue: pts(P.cue), obj: pts(P.obj), first: P.first, crossed: P.crossed, cuePot: P.cuePot === undefined ? -1 : P.cuePot, objPot: P.objPot === undefined ? -1 : P.objPot,
          objHit: P.objHit, cueStop: P.cueStop, air: pts(P.air), bounces: pts(P.bounces || null) } });
    }
  }
  return { math, golden: JSON.stringify({ hashEvery: HASH_EVERY, tables, cases, guides }), tables, cases, guides };
}
/* tests/ios-check.cjs rebuilds both in memory and requires the committed files to match */
module.exports = { build, OUT, loadFd };
if (require.main === module) {
  const b = build();
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'math.txt'), b.math);
  fs.writeFileSync(path.join(OUT, 'golden.json'), b.golden);
  const steps = b.cases.reduce((a, c) => a + c.result.steps, 0);
  console.log(`ios-golden: ${b.tables.length} tables, ${b.cases.length} shots, ${b.guides.length} guides, ${steps} steps, ${b.cases.reduce((a, c) => a + c.result.potted.length, 0)} pots -> ${path.relative(process.cwd(), OUT)}`);
}
