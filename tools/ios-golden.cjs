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
/* 4o's camera, the page's own source: the matrices, the orbit, the overview's fit, the pose, the projection both ways
   (with its constants), cut from index.html; V3 and settings are the harness's */
function v3Source() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const line = a => { const i = html.indexOf('\n' + a); if (i < 0) throw new Error('ios-golden: 4o moved: ' + a); return html.slice(i + 1, html.indexOf('\n', i + 1)) + '\n'; };
  const cut = (a, b) => { const i = html.indexOf(a), j = html.indexOf(b, i); if (i < 0 || j < 0) throw new Error('ios-golden: 4o moved: ' + a); return html.slice(i, j); };
  return 'const LIFT_H = 0.045; const V3 = { box: null, geo: null }; let settings = { viewPitch: 24, viewDist: 1.1 }; const reducedMotion = () => true;\n' +
    line('const V3_PITCH = ') + line('const V3_PITCH_PX = ') + line('const V3_GHOST_A = ') + line('const V3_ROOM_R = ') +
    cut('const v3Sub = (a, b)', 'function v3Layout()') + cut('function v3Mats(', '/* the overview for this box') + cut('/* the camera\'s pose:', '/* a move to the overview') +
    cut('function v3Proj(', '/* once a frame (frameBody)');
}
/* 4m's recorded roll (heroRunStart, heroSample) with 4b's rotate and artTilt, the page's own source */
function heroSource() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const cut = (a, b) => { const i = html.indexOf(a), j = html.indexOf(b, i); if (i < 0 || j < 0) throw new Error('ios-golden: 4m moved: ' + a); return html.slice(i, j); };
  const line = a => { const i = html.indexOf('\n' + a); if (i < 0) throw new Error('ios-golden: 4m moved: ' + a); return html.slice(i + 1, html.indexOf('\n', i + 1)) + '\n'; };
  return 'const IDENT = [1, 0, 0, 0, 1, 0, 0, 0, 1];\n' + cut('function rotate(m, axis, ang) {', '\n}\n') + '\n}\n' + line('const artTilt = ') + cut('function heroRunStart(', 'function heroRunOn(');
}
function guideSource() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const cut = (a, b) => { const i = html.indexOf(a), j = html.indexOf(b, i); if (i < 0 || j < 0) throw new Error('ios-golden: 4d moved: ' + a); return html.slice(i, j); };
  return cut('function aimSweep(', '/* polylines and rings') + cut('const PV_CAP = ', '/* the preview for this aim');
}
/* 6f's quick tournament, its pure part: the field, the draw, the CPU matches settled by the model (T_KINDS to tSave) */
function tourneySource() {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8'), i = html.indexOf('const T_KINDS = '), j = html.indexOf('function tSave()', i);
  if (i < 0 || j < 0) throw new Error('ios-golden: 6f moved');
  return html.slice(i, j);
}
function loadFd() {
  let src = regionSource() + '\n;let game = null; const cueBall = () => game.balls.find(b => b.n === game.cue); const performance = { now: () => 0 };\n' + guideSource() + '\n' + tourneySource() + '\n' + v3Source() + '\n' + heroSource();
  const pw = [['clamp(power, 0, 1) ** POWER_EXP', 'Math.pow(clamp(power, 0, 1), POWER_EXP)'],
    ['clamp((v - MIN_V) / (MAX_V - MIN_V), 0, 1) ** (1 / POWER_EXP)', 'Math.pow(clamp((v - MIN_V) / (MAX_V - MIN_V), 0, 1), 1 / POWER_EXP)']];
  for (const [a, b] of pw) { if (!src.includes(a)) throw new Error('ios-golden: sim changed, update the pow rewrite: ' + a); src = src.replace(a, b); }
  /* the career engine's constants, which its IIFE keeps to itself: read out through lib, in this copy only */
  const libAt = '    lib: { hashStr, seedOf,';
  const apiAt = '    enter, withdraw, nextMatch, reportMatch, simMatch, advance,';
  if (!src.includes(apiAt)) throw new Error('ios-golden: the Career API moved');
  src = src.replace(apiAt, apiAt + ' __elig: id => eligibility(evById(id)).ok, __state: () => JSON.stringify(S),');
  if (!src.includes(libAt)) throw new Error('ios-golden: Career.lib moved');
  /* checkpoints inside create (this copy only): the state after each step the Swift port has reached */
  const at1 = '    assignTiers(Object.keys(S.pop.m).map(Number), i => ratingOf(i, prefOf(i)));';
  if (!src.includes(at1)) throw new Error('ios-golden: Career create moved');
  src = src.replace(at1, at1 + ' __trace.push(JSON.stringify(S));');
  for (const at of ['    S.ser = genSeries(seed, pr.nat, pr.town);', '    S.cal = genCalendar(1);', "    news(`${pr.name} starts out as a ${TIERS[S.me.tier].name}.`);"]) {
    if (!src.includes(at)) throw new Error('ios-golden: Career create moved: ' + at);
    src = src.replace(at, at + ' __trace.push(JSON.stringify(S));');
  }
  src = 'var __trace = [];\n' + src;
  src = src.replace(libAt, '    lib: { __data: () => ({ ATTRS, ARCH, WEIGHTS, BRK_ADV, SPECIALIST: [...SPECIALIST], NAT, NICKS, AV_COLS, POP }), __consts: () => ({ DISCS, GAMES, SHORT, RULESETS, CIRCUITS, CIRC_NAMES, TIERS, FEE, TRAVEL, POT, BP, RACE, BAND, QUOTA, RACE_UNITS, FORMATS, EVENT_KINDS, ATTR_NAMES, SKILLS, SKILL_NAMES, SKILL_EFFECTS, STYLES, DIFFS, STARTS, BNR_F, HEY_NAT, VEN_A, VEN_B, VEN_BIG, BRANDS, SPONSOR_CATS, SHOP, SHOP_SLOTS, DEFAULT_EQ, NEED_WORDS, DRILLS, MILESTONES, LEVEL_BREADTH, PLAN, ONE_OFF, HUMAN, YEAR, MAX_SLOTS, VERSION, HOF_LEG, K_INDEX, K_V1, K_V1_BAK, K_PRE, CARD_KEEP, INVITE_TOP, FR_K, FR_STEP, FR_RACKS, RIVAL_GAP, CHALLENGES }), hashStr, seedOf,');
  const ctx = vm.createContext({});
  ctx.__fd = F.fdMath(vm.runInContext('Math', ctx));
  const names = ['setTable', 'setPockets', 'rack', 'snookerRack', 'newBall', 'newTable', 'strike', 'stepTable', 'resultOf', 'spinOf',
    'caromGame', 'snookerGame', 'snkFreeBalls', 'D_R', 'cpuShot', 'cpuOption', 'newGame', 'judge', 'chooseOption', 'callNeed', 'legalTargets', 'canPlace', 'placeCue', 'simulateShot', 'makeRules', 'POCKET_AIM', 'aimTrace', 'previewStart', 'previewRun', 'PV_FULL', 'PV_SHORT', 'PV_CAROM', 'setGame', 'TL', 'TW', 'HEAD_X', 'FOOT', 'BALL_R', 'CUSH', 'POCKETS', 'POCKET_R', 'POCKET_AIM', 'JAW_ARCS', 'CUSHION_POLYS', 'SPOTS', 'D_R', 'BUMPERS', 'bumperRack', 'bumperFree', 'bumperStrikers', 'Career', 'tourneyNew', 'tSettle', 'tMine', 'tCtx', 'tTpl', 'cpuProfile', '__trace', 'V3', 'settings', 'v3Mats', 'v3Pose', 'v3Proj', 'v3Unproj', 'v3Overview', 'v3OrbitOf', 'v3EyeOf', 'v3Lerp', 'heroRunStart', 'heroSample', 'heroSetup', 'heroKey', 'resultOf', 'newPractice', 'practiceJudge', 'scatter', 'addBall', 'removeBall', 'rng', 'canDrop', 'onTable', 'TRICKS', 'trickJudge', 'trickPoints', 'trickSol', 'trickGame', 'programMax', 'TRICK_VAL', 'trickPts', 'trickScoreFromStars', 'trickStars', 'newBall', 'DRILL_LIB', 'drillRun', 'drillShot', 'drillTier', 'drillTotal', 'drillJudge', 'drillBalls', 'drillOver'];
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
    /* a string (a bumper post's 'post'): its characters, then a mark */
    if (typeof e === 'string') { for (const c of e) h = fnv(h, c.charCodeAt(0)); h = fnv(h, 0xfffffffe); }
    else h = fnv(h, e === undefined ? 0xffffffff : (e | 0) >>> 0);
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
      Math.hypot(x, y), Math.hypot(x, y, c), F.atan2(c, x), F.asin(c), F.tanh(x), F.atanh(c * 0.999), F.log1p(y - 0.3), F.expm1(x), F.log(y + 1e-3), F.log(Math.abs(x) + 0.5)].map(hx).join(' '));
  }
  const math = lines.join('\n') + '\n';

  const TABLES = [['7', null, 'regulation'], ['9', null, 'regulation'], ['7', null, 'generous'], ['9', null, 'generous'],
    ['heyball', null, 'regulation'], ['snooker', 'compact', 'regulation'], ['snooker', 'full', 'regulation'], ['carom', null, 'regulation'],
    ['bumper', 'octagon', 'regulation'], ['bumper', 'rect', 'regulation']];
  const tables = [], cases = [];
  /* the octagonal bumper table keeps the last table's SKIMS and HOLE_IN (buildOcta never sets them), so a bumper table
     is always reached from the 7 ft table, as the Swift test's fresh Sim is */
  const setT = ([t, shape, pk]) => { if (t === 'bumper') S.setTable('7'); S.setPockets(pk); S.setTable(t, shape === null ? undefined : shape); };
  for (const T of TABLES) {
    setT(T);
    const arr = a => a.map(v => Array.isArray(v) ? arr(v) : hx(v));
    tables.push({ table: T[0], shape: T[1], pockets: T[2], TL: hx(S.TL), TW: hx(S.TW), HEAD_X: hx(S.HEAD_X), FOOT: arr(S.FOOT), BALL_R: hx(S.BALL_R),
      CUSH: arr(S.CUSH), POCKETS: arr(S.POCKETS), POCKET_R: arr(S.POCKET_R), POCKET_AIM: arr(S.POCKET_AIM), JAW_ARCS: arr(S.JAW_ARCS), BUMPERS: arr(S.BUMPERS) });
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

  /* bumper pool (1g): each shape's rack shot at the far cup with the marked ball, and scattered balls (clear of the
     posts and cups: bumperFree) struck every way, hard into the posts and soft at the cups */
  /* its own stream, so the other fixtures' draws are as they were */
  let bseed = 1919;
  const brnd = () => { bseed = (Math.imul(bseed, 1103515245) + 12345) >>> 0; return bseed / 4294967296; };
  const bSpin = k => k % 4 === 0 ? 0 : k % 4 === 1 ? (brnd() * 2 - 1) : k % 4 === 2 ? { x: brnd() * 1.4 - 0.7, y: brnd() * 1.4 - 0.7 }
    : { x: brnd() * 1.2 - 0.6, y: brnd() * 1.2 - 0.6, e: brnd() * 1.0 };
  for (const T of TABLES.filter(t => t[0] === 'bumper')) {
    for (let k = 0; k < 6; k++) {
      setT(T);
      const balls = S.bumperRack(), m = balls.find(b => b.n === 21), cup = S.POCKETS[1];
      const a = Math.atan2(cup[1] - m.y, cup[0] - m.x) + (brnd() - 0.5) * 0.6;
      run(T, `bumper/${T[1]} rack ${k}`, balls, { ball: 21, angle: a, power: [0.9, 0.55, 0.35, 0.7, 0.45, 1][k], spin: bSpin(k) });
    }
    for (let k = 0; k < 10; k++) {
      setT(T);
      const nums = [21, 31, 22, 32, 23, 33, 24, 34, 25, 35], count = 2 + Math.floor(brnd() * 8), out = [];
      while (out.length < count) {
        const x = brnd() * S.TL, y = brnd() * S.TW;
        if (S.bumperFree(out, x, y, -1)) out.push(S.newBall(nums[out.length], x, y));
      }
      run(T, `bumper/${T[1]} scatter ${k}`, out, { ball: 21, angle: brnd() * 2 * Math.PI, power: 0.1 + brnd() * 0.85, spin: bSpin(k) });
    }
  }
  for (const T of TABLES.filter(t => t[0] !== 'snooker' && t[0] !== 'carom' && t[0] !== 'bumper')) {
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
  for (const T of TABLES.filter(t => t[0] !== 'bumper')) {
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
  /* the rules: whole games played by the page's own judge on fdlibm physics, every shot and choice
     recorded as the game in, the shot's facts, and the game out (JSON, as copyGame sees a game) */
  const games = [];
  const RULE_GAMES = [['8', '8-house', 'official'], ['8', '8-wpa', 'official'], ['8', '8-wpa', 'all'], ['heyball', 'heyball', 'official'], ['9', '9-house', 'official'],
    ['9', '9-wpa', 'official'], ['10', '10-wpa', 'official'], ['rotation', 'rotation', 'official'], ['straight', 'straight-wpa', 'official'], ['9', '9-ring', 'official']];
  for (const [kind, ruleset, mode] of RULE_GAMES) {
    for (let gi = 0; gi < 3; gi++) {
      setT(kind === 'heyball' ? ['heyball', null, 'regulation'] : [gi === 2 ? '9' : '7', null, 'regulation']);
      let g = S.newGame(kind, { rules: { ruleset, call: { mode }, race: kind === 'straight' ? 12 : kind === 'rotation' ? 40 : undefined } });
      const steps = [], bare = x => { const o = JSON.parse(JSON.stringify(x)); delete o.rules; return o; }, g0 = bare(g);
      for (let k = 0; k < 140 && g.winner === null; k++) {
        if (g.option) {
          const choice = g.option.choices[Math.floor(rnd() * g.option.choices.length)], out = S.chooseOption(g, choice);
          steps.push({ choice, out: bare(out) });
          g = out; continue;
        }
        const step = {};
        if (g.inHand) {
          for (let t = 0; t < 400; t++) {
            const x = S.BALL_R + rnd() * (S.TL - 2 * S.BALL_R), y = S.BALL_R + rnd() * (S.TW - 2 * S.BALL_R);
            if (S.canPlace(g, x, y)) { g = S.placeCue(g, x, y); step.place = [x, y]; break; }
          }
        }
        const c = g.balls.find(b => b.n === 0), tg = S.legalTargets(g), on = g.balls.filter(b => b.on && b.n > 0);
        if (!on.length || !tg.length) break;
        const pick = rnd() < 0.85 ? tg[Math.floor(rnd() * tg.length)] : on[Math.floor(rnd() * on.length)].n, t = g.balls.find(b => b.n === pick);
        const ang = Math.atan2(t.y - c.y, t.x - c.x) + (rnd() - 0.5) * 0.08, power = g.breakShot ? 0.25 + rnd() * 0.75 : 0.2 + rnd() * 0.6;
        const need = S.callNeed(g);
        if (need || (kind === 'straight' && g.breakShot && rnd() < 0.5)) {
          const pk = Math.floor(rnd() * S.POCKET_AIM.length), roll = rnd();
          g = Object.assign({}, g, { call: roll < 0.1 ? { safety: true } : roll < 0.15 ? {} : { ball: t.n, pocket: pk } });
        } else if (g.pushAvail && rnd() < 0.3) g = Object.assign({}, g, { call: { push: true } });
        if (g.call) step.call = g.call;
        const shotIn = { angle: ang, power, spin: S.spinOf(rnd() < 0.5 ? 0 : { x: rnd() - 0.5, y: rnd() - 0.5 }) };
        step.shot = { angle: hx(ang), power: hx(power), spin: { x: hx(shotIn.spin.x), y: hx(shotIn.spin.y) } };
        const res = S.simulateShot(g.balls, shotIn);
        step.r = JSON.parse(JSON.stringify({ balls: res.balls, first: res.first, railAfter: res.railAfter, crossed: res.crossed, potted: res.potted, pocketOf: res.pocketOf, rails: res.rails, kick: res.kick }));
        const out = S.judge(g, res);
        step.out = bare(out);
        steps.push(step);
        g = out;
      }
      games.push({ name: `${ruleset}/${mode} game ${gi}`, kind, ruleset, mode, race: kind === 'straight' ? 12 : kind === 'rotation' ? 40 : null, table: kind === 'heyball' ? 'heyball' : gi === 2 ? '9' : '7', g0, steps });
    }
  }
  /* snooker: whole frames (one, and the best of three) by the page's judgeSnooker and chooseSnooker:
     ball in hand in the D, free balls nominated, put-backs after a miss, every choice at random */
  for (let gi = 0; gi < 6; gi++) {
    setT(['snooker', gi % 2 ? 'full' : 'compact', 'regulation']);
    let g = S.snookerGame(gi < 3 ? 1 : 3, gi % 2);
    const steps = [], bare = x => JSON.parse(JSON.stringify(x)), g0 = bare(g);
    for (let k = 0; k < 220 && g.winner === null; k++) {
      if (g.option) {
        let choice = g.option.choices[Math.floor(rnd() * g.option.choices.length)];
        if (choice === 'free') { const f = S.snkFreeBalls(g); choice = f.length ? 'free:' + f[Math.floor(rnd() * f.length)] : 'play'; }
        const out = S.chooseOption(g, choice);
        if (!out) break;
        steps.push({ choice, out: bare(out) }); g = out; continue;
      }
      const step = {};
      if (g.inHand) {
        for (let t = 0; t < 400; t++) {
          const x = S.HEAD_X - rnd() * S.D_R, y = S.TW / 2 + (rnd() * 2 - 1) * S.D_R;
          if (S.canPlace(g, x, y)) { g = S.placeCue(g, x, y); step.place = [x, y]; break; }
        }
      }
      const c = g.balls.find(b => b.n === 0), tg = S.legalTargets(g), on = g.balls.filter(b => b.on && b.n > 0);
      if (!on.length || !c.on) break;
      const pool = tg.length && rnd() < 0.85 ? tg : on.map(b => b.n), pick = pool[Math.floor(rnd() * pool.length)], t = g.balls.find(b => b.n === pick);
      const ang = Math.atan2(t.y - c.y, t.x - c.x) + (rnd() - 0.5) * 0.08, power = g.breakShot ? 0.45 + rnd() * 0.3 : 0.15 + rnd() * 0.55;
      const shotIn = { angle: ang, power, spin: S.spinOf(rnd() < 0.5 ? 0 : { x: rnd() - 0.5, y: rnd() - 0.5 }) };
      step.shot = { angle: hx(ang), power: hx(power), spin: { x: hx(shotIn.spin.x), y: hx(shotIn.spin.y) } };
      const res = S.simulateShot(g.balls, shotIn);
      step.r = JSON.parse(JSON.stringify({ balls: res.balls, first: res.first, railAfter: res.railAfter, crossed: res.crossed, potted: res.potted, pocketOf: res.pocketOf, rails: res.rails, kick: res.kick, seq: res.seq, over: res.over }));
      const out = S.judge(g, res);
      step.out = bare(out);
      steps.push(step);
      g = out;
    }
    games.push({ name: `snooker/${gi % 2 ? 'full' : 'compact'} ${gi < 3 ? 'frame' : 'best of three'} ${gi}`, kind: 'snooker', ruleset: 'snooker', mode: 'official', race: null,
      table: 'snooker', shape: gi % 2 ? 'full' : 'compact', g0, steps });
  }
  /* carom: whole games by the page's judgeCarom and chooseCarom, the striker's own cue ball, now and
     then the wrong one; the race short so they finish */
  for (let gi = 0; gi < 6; gi++) {
    setT(['carom', null, 'regulation']);
    let g = S.caromGame({ race: 5, cushions: gi % 3 === 2 ? 1 : 3, side: gi % 2 ? -1 : 1 });
    const steps = [], bare = x => JSON.parse(JSON.stringify(x)), g0 = bare(g);
    for (let k = 0; k < 160 && g.winner === null; k++) {
      if (g.option) {
        const choice = g.option.choices[Math.floor(rnd() * g.option.choices.length)], out = S.chooseOption(g, choice);
        steps.push({ choice, out: bare(out) }); g = out; continue;
      }
      const step = {}, ball = rnd() < 0.05 ? (g.striker === 70 ? 71 : 70) : g.striker, c = g.balls.find(b => b.n === ball);
      /* a CPU shot now and then, so points get made and the leave is played from */
      let shotIn;
      if (rnd() < 0.5) { const cs = S.cpuShot(g, gi * 1000 + k, 'easy'); shotIn = { angle: cs.angle, power: cs.power, spin: S.spinOf(cs.spin), ball: g.striker }; }
      else {
        const tg = S.legalTargets(g), pick = tg[Math.floor(rnd() * tg.length)], t = g.balls.find(b => b.n === pick);
        shotIn = { angle: Math.atan2(t.y - c.y, t.x - c.x) + (rnd() - 0.5) * 0.4, power: 0.3 + rnd() * 0.5, spin: S.spinOf({ x: rnd() - 0.5, y: rnd() * 0.5 }), ball };
      }
      step.shot = { angle: hx(shotIn.angle), power: hx(shotIn.power), spin: { x: hx(shotIn.spin.x), y: hx(shotIn.spin.y) }, ball: shotIn.ball };
      const res = S.simulateShot(g.balls, shotIn);
      step.r = JSON.parse(JSON.stringify({ balls: res.balls, first: res.first, railAfter: res.railAfter, crossed: res.crossed, potted: res.potted, pocketOf: res.pocketOf, rails: res.rails, kick: res.kick, seq: res.seq, over: res.over, cue: res.cue }));
      const out = S.judge(g, res);
      step.out = bare(out);
      steps.push(step);
      g = out;
    }
    games.push({ name: `carom ${gi % 3 === 2 ? 'one' : 'three'}-cushion ${gi}`, kind: 'carom', ruleset: 'carom', mode: 'official', race: 5, need: gi % 3 === 2 ? 1 : 3, side: gi % 2 ? -1 : 1,
      table: 'carom', shape: null, g0, steps });
  }
  /* bumper pool: whole games by the page's judgeBumper on both shapes, half the shots the page's own CPU (so balls
     drop and games end), the rest at the far cup with noise or anywhere, now and then with the wrong ball (a foul).
     Its own stream, so the other fixtures' draws are as they were. */
  let gseed = 4242;
  const grnd = () => { gseed = (Math.imul(gseed, 1103515245) + 12345) >>> 0; return gseed / 4294967296; };
  for (let gi = 0; gi < 6; gi++) {
    const shape = gi % 2 ? 'rect' : 'octagon';
    setT(['bumper', shape, 'regulation']);
    let g = S.newGame('bumper');
    const steps = [], bare = x => JSON.parse(JSON.stringify(x)), g0 = bare(g);
    for (let k = 0; k < 200 && g.winner === null; k++) {
      const step = {};
      let shotIn;
      if (grnd() < 0.5) { const cs = S.cpuShot(g, gi * 1000 + k, ['easy', 'medium'][gi % 2]); shotIn = { angle: cs.angle, power: cs.power, spin: S.spinOf(cs.spin), ball: cs.ball }; }
      else {
        const own = S.bumperStrikers(g), all = g.balls.filter(b => b.on).map(b => b.n);
        const ball = grnd() < 0.06 ? all[Math.floor(grnd() * all.length)] : own[Math.floor(grnd() * own.length)], c = g.balls.find(b => b.n === ball), T = S.POCKETS[1 - g.turn];
        const ang = grnd() < 0.7 ? Math.atan2(T[1] - c.y, T[0] - c.x) + (grnd() - 0.5) * 0.5 : grnd() * 2 * Math.PI;
        shotIn = { angle: ang, power: 0.15 + grnd() * 0.75, spin: S.spinOf(grnd() < 0.5 ? 0 : { x: grnd() - 0.5, y: grnd() - 0.5 }), ball };
      }
      step.shot = { ball: shotIn.ball, angle: hx(shotIn.angle), power: hx(shotIn.power), spin: { x: hx(shotIn.spin.x), y: hx(shotIn.spin.y) } };
      const res = S.simulateShot(g.balls, shotIn);
      step.r = JSON.parse(JSON.stringify({ balls: res.balls, cue: res.cue, first: res.first, railAfter: res.railAfter, crossed: res.crossed, potted: res.potted, pocketOf: res.pocketOf, rails: res.rails, kick: res.kick }));
      const out = S.judge(g, res);
      step.out = bare(out);
      steps.push(step);
      g = out;
    }
    games.push({ name: `bumper/${shape} game ${gi}`, kind: 'bumper', ruleset: 'bumper', mode: 'official', race: null, table: 'bumper', shape, g0, steps });
  }
  /* the CPU: from positions of those games, the page's cpuShot at each level (fixed seeds) and its
     cpuOption wherever a choice is pending; the state is game gi after step k (k -1: its opening) */
  const cpu = [];
  games.forEach((G, gi) => {
    setT([G.table, G.shape || null, 'regulation']);
    const R0 = G.kind === 'carom' || G.kind === 'snooker' ? null : S.newGame(G.kind, { rules: { ruleset: G.ruleset, call: { mode: G.mode }, race: G.race === null ? undefined : G.race } }).rules;
    const at = k => { const o = JSON.parse(JSON.stringify(k < 0 ? G.g0 : G.steps[k].out)); return R0 ? Object.assign(o, { rules: R0 }) : o; };
    const ks = [-1];
    for (let k = 3; k < G.steps.length && ks.length < 5; k += 7) ks.push(k);
    for (const k of ks) {
      const g = at(k);
      if (g.winner !== null) continue;
      if (g.option) { for (const level of ['easy', 'medium', 'hard']) cpu.push({ gi, k, level, option: S.cpuOption(g, level) }); continue; }
      for (const level of ['easy', 'medium', 'hard']) {
        const seed = gi * 1000 + k + 7, s1 = S.cpuShot(g, seed, level);
        cpu.push({ gi, k, level, seed, shot: { angle: hx(s1.angle), power: hx(s1.power), spin: { x: hx(s1.spin.x), y: hx(s1.spin.y), e: hx(s1.spin.e || 0) },
          place: s1.place ? s1.place.map(hx) : null, call: s1.call || null, intent: { type: s1.intent.type, q: hx(s1.intent.q) }, ball: s1.ball === undefined ? null : s1.ball, first: s1.first === undefined ? null : s1.first } });
      }
    }
    /* every option state too */
    G.steps.forEach((st, k) => { if (st.out.option && st.out.winner === null) cpu.push({ gi, k, level: 'medium', option: S.cpuOption(at(k), 'medium') }); });
  });
  /* personalities (cpuProfile({ level, arch }, { hill })): every archetype at the three levels, on and off the hill,
     from two positions of each game, by the page's cpuShot and cpuOption with that made profile */
  const ARCHS = ['allround', 'potter', 'shotmaker', 'defender', 'positional', 'breaker', 'banker', 'grinder', 'clutch'];
  games.forEach((G, gi) => {
    setT([G.table, G.shape || null, 'regulation']);
    const R0 = G.kind === 'carom' || G.kind === 'snooker' || G.kind === 'bumper' ? null : S.newGame(G.kind, { rules: { ruleset: G.ruleset, call: { mode: G.mode }, race: G.race === null ? undefined : G.race } }).rules;
    const at = k => { const o = JSON.parse(JSON.stringify(k < 0 ? G.g0 : G.steps[k].out)); return R0 ? Object.assign(o, { rules: R0 }) : o; };
    for (const k of [5, 12]) {
      if (k >= G.steps.length) continue;
      const g = at(k);
      if (g.winner !== null) continue;
      ARCHS.forEach((arch, i) => {
        if ((gi + k + i) % 3) return;   /* a third of them: every archetype is still met in every game kind */
        const level = ['easy', 'medium', 'hard'][(gi + i) % 3], hill = (gi + i) % 2 === 1, P = S.cpuProfile({ level, arch }, { hill });
        if (g.option) { cpu.push({ gi, k, level, arch, hill, option: S.cpuOption(g, P) }); return; }
        const seed = gi * 1000 + k + 31 + i, s1 = S.cpuShot(g, seed, P);
        cpu.push({ gi, k, level, arch, hill, seed, shot: { angle: hx(s1.angle), power: hx(s1.power), spin: { x: hx(s1.spin.x), y: hx(s1.spin.y), e: hx(s1.spin.e || 0) },
          place: s1.place ? s1.place.map(hx) : null, call: s1.call || null, intent: { type: s1.intent.type, q: hx(s1.intent.q) }, ball: s1.ball === undefined ? null : s1.ball, first: s1.first === undefined ? null : s1.first } });
      });
    }
  });
  /* banks and combinations proven where they matter: every other position of the 9-ball games (the lowest ball first,
     so a combination is often the pot), the shotmaker (combos) and the banker (banks) at medium */
  games.forEach((G, gi) => {
    if (G.kind !== '9') return;
    setT([G.table, G.shape || null, 'regulation']);
    const R0 = S.newGame(G.kind, { rules: { ruleset: G.ruleset, call: { mode: G.mode }, race: undefined } }).rules;
    for (let k = 1; k < Math.min(G.steps.length, 30); k += 2) {
      const g = Object.assign(JSON.parse(JSON.stringify(G.steps[k].out)), { rules: R0 });
      if (g.winner !== null || g.option) continue;
      for (const arch of ['shotmaker', 'banker']) {
        const P = S.cpuProfile({ level: 'medium', arch }), seed = gi * 1000 + k + 77, s1 = S.cpuShot(g, seed, P);
        cpu.push({ gi, k, level: 'medium', arch, hill: false, seed, shot: { angle: hx(s1.angle), power: hx(s1.power), spin: { x: hx(s1.spin.x), y: hx(s1.spin.y), e: hx(s1.spin.e || 0) },
          place: s1.place ? s1.place.map(hx) : null, call: s1.call || null, intent: { type: s1.intent.type, q: hx(s1.intent.q) }, ball: s1.ball === undefined ? null : s1.ball, first: s1.first === undefined ? null : s1.first } });
      }
    }
  });
  /* the career library (quick tournament, 6f): generated players, the match model, brackets played through. Its
     own stream. CareerData.swift is the page's constants as Swift, written from the page */
  const L = S.Career.lib, D = L.__data();
  let cseed = 777;
  const crnd = () => { cseed = (Math.imul(cseed, 1103515245) + 12345) >>> 0; return cseed / 4294967296; };
  const names = new Set(), players = [];
  for (const id of [...Array(80).keys()].map(i => i + 1).concat([301, 302, 303, 304, 305])) players.push(L.genPlayer(4242, id, names));
  const P = p => ({ at: p.base, pref: p.disc });
  const DISCS = ['8', '9', '10', 'straight', 'rotation', 'snooker', 'carom', 'bumper', 'heyball'];
  const models = [];
  for (let i = 0; i < 300; i++) {
    const a = players[Math.floor(crnd() * players.length)], b = players[Math.floor(crnd() * players.length)], disc = DISCS[Math.floor(crnd() * DISCS.length)];
    const race = disc === 'straight' ? [25, 50, 100][i % 3] : disc === 'carom' ? [5, 10, 15][i % 3] : 1 + (i % 7), seed = Math.floor(crnd() * 4294967296);
    const adj = i % 4 === 0 ? Math.round((crnd() - 0.5) * 16) : 0, m = L.playModel(Object.assign(P(a), { adj }), P(b), disc, race, seed);
    models.push({ a: a.id, b: b.id, adj, disc, race, seed, s: m.s, first: m.first });
  }
  const brackets = [];
  for (const fmt of ['single', 'double']) for (const n of [3, 4, 5, 8, 12, 16]) {
    const T = L.makeBracket(fmt, n), f = [...Array(n).keys()].map(i => 100 + i), res = T.M.map(() => null), steps = [];
    for (let guard = 0; guard < 200; guard++) {
      const c = L.ctxOf(T, f, res), st = T.M.map((_, m) => L.outcome(c, m));
      steps.push(st.map(o => [o.st, o.a === undefined ? -2 : o.a === null ? -1 : o.a, o.b === undefined ? -2 : o.b === null ? -1 : o.b, o.w === undefined ? -2 : o.w === null ? -1 : o.w]));
      const ready = st.findIndex(o => o.st === 'ready');
      if (ready < 0) break;
      const aw = crnd() < 0.5;
      res[ready] = aw ? [2, Math.floor(crnd() * 2)] : [Math.floor(crnd() * 2), 2];
    }
    brackets.push({ fmt, n, M: T.M.map(x => ({ a: x.a, b: x.b, br: x.br, rd: x.rd, dep: x.dep, st: x.st === undefined ? null : x.st, el: x.el === undefined ? null : x.el, fin: !!x.fin, cond: x.cond || null, of: x.of === undefined ? null : x.of })), steps, res });
  }
  /* whole tournaments by the page's tourneyNew and tSettle, the player's matches reported with drawn scores
     (oriented as tReport orients them), and the places and round names at the end */
  const tourneys = [];
  for (const [kind, size, fmt, race, field, seed] of [['9', 8, 'single', 3, 'mixed', 11], ['8', 16, 'double', 2, 'mixed', 2026], ['snooker', 4, 'single', 2, 'hard', 7],
    ['straight', 8, 'double', 50, 'easy', 99], ['carom', 16, 'single', 10, 'medium', 31337], ['heyball', 4, 'double', 1, 'mixed', 5]]) {
    const t = S.tourneyNew({ kind, size, fmt, race, field, seed, ruleset: undefined });
    const start = JSON.parse(JSON.stringify({ field: t.field, f: t.f, res: t.res, sim: t.sim, race: t.race, ruleset: t.ruleset }));
    const reports = [];
    for (let g = 0; g < 40; g++) {
      const m = S.tMine(t);
      if (m === null) break;
      const won = crnd() < 0.55, lose = Math.floor(crnd() * t.race), mine = won ? t.race : lose, theirs = won ? lose : t.race;
      const o = L.outcome(S.tCtx(t), m);
      t.res[m] = o.a === 0 ? [mine, theirs] : [theirs, mine];
      S.tSettle(t);
      reports.push({ m, mine, theirs, res: t.res.slice(), sim: t.sim.slice() });
    }
    const T = S.tTpl(t);
    tourneys.push({ kind, size, fmt, race, field, seed, start, reports, done: t.done, places: t.places, rounds: T.M.map((_, m) => L.roundName({ fmt }, T, m)) });
  }
  /* careers created on the page (Career.create, no save): the profile in, each checkpoint's state */
  const careers = [];
  for (const [profile, seed] of [[{ name: 'Zac Acker', nat: 'US', town: 'Indianapolis', disc: '9', style: 'potter', difficulty: 'medium', start: 'amateur', age: 34 }, 12345],
    [{ name: 'Mei Lin', nat: 'TW', disc: '8', style: 'defender', difficulty: 'hard', start: 'skilled', age: 22, hand: 'left' }, 777],
    [{ name: 'Siobhan', nat: 'IE', disc: 'snooker', style: 'positional', difficulty: 'easy', start: 'novice', age: 16, avatar: { ini: 'sk', col: '#123abc' } }, 2026]]) {
    S.__trace.length = 0;
    const r = S.Career.create(profile, { seed, save: false });
    const careersDigest0 = S.Career.digest();
    const play = [];
    /* then 40 steps of a season: enter the first event open to the player (its start ahead), advance a week, a match due
       settled by the model; the digest and the day after each, the whole state every tenth */
    for (let k = 0; k < 40; k++) {
      const st = JSON.parse(S.Career.__state()), ev = st.cal.find(e => e.start > st.day && S.Career.__elig(e.id));
      if (ev) S.Career.enter(ev.id);
      const a = S.Career.advance('week');
      let sims = 0;
      if (a.stopped === 'match') { S.Career.simMatch(); sims++; }
      play.push({ enter: ev ? ev.id : null, stop: a.stopped, sims, day: JSON.parse(S.Career.__state()).day, digest: S.Career.digest(), state: k % 10 === 9 ? S.Career.__state() : null });
    }
    /* then to the season's end and over it (rollSeason), every match due settled; then ten weeks of the next season */
    for (let k = 0; k < 400 && JSON.parse(S.Career.__state()).day < S.Career.YEAR; k++) {
      const a = S.Career.advance('season');
      if (a.stopped === 'match') S.Career.simMatch();
      play.push({ to: 'season', stop: a.stopped, day: JSON.parse(S.Career.__state()).day, digest: S.Career.digest(), state: null });
    }
    { const a = S.Career.advance(1); play.push({ to: 'day', stop: a.stopped, day: JSON.parse(S.Career.__state()).day, digest: S.Career.digest(), state: S.Career.__state() }); }
    for (let k = 0; k < 10; k++) {
      const st = JSON.parse(S.Career.__state()), ev = st.cal.find(e => e.start > st.day && S.Career.__elig(e.id));
      if (ev) S.Career.enter(ev.id);
      const a = S.Career.advance('week');
      if (a.stopped === 'match') S.Career.simMatch();
      play.push({ enter: ev ? ev.id : null, stop: a.stopped, day: JSON.parse(S.Career.__state()).day, digest: S.Career.digest(), state: k === 9 ? S.Career.__state() : null });
    }
    careers.push({ profile, seed, ok: r.ok, id: r.id, trace: S.__trace.slice(), digest: careersDigest0, play });
  }
  /* the rest of the API on the last career (in its second season): its next match, every offer accepted, every shop
     item bought and equipped, practice past its daily limit, the assist both ways, the profile edited, retirement */
  const api = [];
  {
    const C = S.Career, rec = (what, out) => api.push({ what, out: JSON.stringify(out === undefined ? null : out), digest: C.digest() });
    for (let k = 0; k < 10; k++) { const a = C.advance('week'); if (a.stopped === 'match') break; }
    rec('next', C.nextMatch());
    C.simMatch();
    for (const o of JSON.parse(C.__state()).off) rec('accept ' + o.id, C.accept(o.id));
    for (const it of C.SHOP) rec('buy ' + it.id, C.buy(it.id));
    for (const it of C.SHOP) rec('equip ' + it.id, C.equip(it.id));
    rec('equipped', C.equipped());
    for (const d of C.DRILLS.slice(0, 2)) for (const sc of [40, 85, 100, 60]) rec('practice ' + d.id + ' ' + sc, C.practice(d.id, sc));
    rec('assist', C.assist());
    rec('options', C.setOptions({ purity: false, variance: true }));
    rec('assist2', C.assist());
    rec('edit', C.editProfile(Object.assign(C.profile(), { name: 'Siobhan Two', nick: 'S2' })));
    for (let k = 0; k < 3; k++) { const a = C.advance('week'); if (a.stopped === 'match') C.simMatch(); }
    for (const o of JSON.parse(C.__state()).off) rec('decline ' + o.id, C.decline(o.id));
    rec('review', C.review());
    for (const c of ['local', 'regional', '9', 'season']) rec('rankings ' + c, C.rankings(c));
    rec('stats', C.stats());
    rec('retire', C.retire());
  }
  /* saves: a store of its own, a career created and played with autosave, its main save corrupted and recovered, a
     second career, the first deleted; the store's every key and value at each mark, and what each call answered */
  const saves = [];
  {
    const m = new Map(), st = { getItem: k => m.has(k) ? m.get(k) : null, setItem: (k, v) => { m.set(k, String(v)); }, removeItem: k => { m.delete(k); } };
    const C = S.Career, snap = (what, out) => saves.push({ what, out: out === undefined ? null : JSON.stringify(out), store: [...m].sort((a, b) => a[0] < b[0] ? -1 : 1) });
    C.useStore(st); C.setAutosave(true);
    snap('create', C.create({ name: 'Ada Save', nat: 'GB', disc: '8', style: 'potter', difficulty: 'medium', start: 'amateur', age: 28 }, { seed: 31337 }));
    for (let k = 0; k < 6; k++) {
      const s0 = JSON.parse(C.__state()), ev = s0.cal.find(e => e.start > s0.day && C.__elig(e.id));
      if (ev) C.enter(ev.id);
      const a = C.advance('week');
      if (a.stopped === 'match') C.simMatch();
    }
    snap('played');
    snap('slots', C.listSlots());
    m.set('felt.career.v2.c1', 'F2|junk');
    snap('slots-corrupt', C.listSlots());
    const l1 = C.load('c1'); snap('load-bak', { ok: l1.ok, recovered: l1.recovered, digest: C.digest() });
    m.set('felt.career.v2.c1', 'x'); m.delete('felt.career.v2.c1.bak');
    snap('load-none', C.load('c1'));
    C.load('c1');
    snap('create2', C.create({ name: 'Bo Two', nat: 'SE', disc: 'snooker', style: 'defender', difficulty: 'easy', start: 'novice', age: 19 }, { seed: 99 }));
    snap('delete', C.deleteSlot('c1'));
    snap('slots-end', C.listSlots());
  }
  const career = JSON.stringify({ seed: 4242, players, models, brackets, tourneys, careers, api, saves, consts: L.__consts(), hashes: ['', 'a', 'felt', 'Zhao|9|p'].map(x => [x, L.hashStr(x)]) });
  const q = v => JSON.stringify(v);
  const careerData = `/* GENERATED by tools/ios-golden.cjs from index.html's career engine (its constants, sim 1 career region).
   Do not edit: change the page and re-run the tool; tests/ios-check.cjs fails while this is stale. */
public enum CareerData {
  public static let ATTRS: [String] = ${q(D.ATTRS)}
  public static let ARCH: [(id: String, name: String, d: [String: Double])] = [
${D.ARCH.map(a => `    (${q(a.id)}, ${q(a.name)}, [${Object.entries(a.d).map(([k, v]) => `${q(k)}: ${v}`).join(', ') || ':'}]),`).join('\n')}
  ]
  /* rating weights by discipline, each in the page's key order (the sum's order) */
  public static let WEIGHTS: [String: [(String, Double)]] = [
${Object.entries(D.WEIGHTS).map(([k, w]) => `    ${q(k)}: [${Object.entries(w).map(([a, v]) => `(${q(a)}, ${v})`).join(', ')}],`).join('\n')}
  ]
  public static let BRK_ADV: [String: Double] = [${Object.entries(D.BRK_ADV).map(([k, v]) => `${q(k)}: ${v}`).join(', ')}]
  public static let SPECIALIST: Set<String> = ${q(D.SPECIALIST)}
  public static let POP = ${D.POP}
  /* nationalities: id, name, first and family names, cities, weight, leanings (in the page's key order) */
  public static let NAT: [(id: String, name: String, first: [String], last: [String], cities: [String], w: Double, lean: [(String, Double)])] = [
${D.NAT.map(n => `    (${q(n.id)}, ${q(n.name)}, ${q(n.first)}, ${q(n.last)}, ${q(n.cities)}, ${n.w}, [${Object.entries(n.lean).map(([k, v]) => `(${q(k)}, ${v})`).join(', ')}]),`).join('\n')}
  ]
  public static let NICKS: [String] = ${q(D.NICKS)}
  public static let AV_COLS: [String] = ${q(D.AV_COLS)}
  /* every data constant of the engine (DISCS, TIERS, FEE ... SHOP, PLAN), as the page holds them, read once as JV */
  public static let C: JObj = { guard case .obj(let o)? = JV.parse(CONSTS) else { fatalError("CareerData.C") }; return o }()
  static let CONSTS = ##"${JSON.stringify(L.__consts())}"##
}
`;
  /* JV (the career's save in Swift) against V8: Number#toString by bit pattern over the whole range, strings with
     every escape, and random nested objects (integer-like and plain keys, repeated keys), each as JSON.stringify writes it */
  let jseed = 99;
  const jrnd = () => { jseed = (Math.imul(jseed, 1103515245) + 12345) >>> 0; return jseed / 4294967296; };
  const nums = [0, -0, 1, -1, 0.1, 0.5, 1 / 3, 2 / 3, 100, 1e21, 1e20, 123456789012345680000, 1e-6, 1e-7, 1.5e-7, 5e-324, Number.MAX_VALUE, Number.MIN_VALUE,
    0.000001234, 1234.5678, 2 ** 53, 2 ** 53 + 2, 4294967295, 1e300, 1.7976931348623157e308, 9.999999999999999e20, 99.99, 0.30000000000000004];
  for (let i = 0; i < 3000; i++) { const e = Math.floor(jrnd() * 60) - 30, m = jrnd() * 10; nums.push((jrnd() < 0.5 ? -1 : 1) * m * 10 ** e); nums.push(Math.round(jrnd() * 1e6) / [1, 10, 100, 1000][i % 4]); }
  const dv2 = new DataView(new ArrayBuffer(8)), bits = v => { dv2.setFloat64(0, v); return dv2.getBigUint64(0).toString(16).padStart(16, '0'); };
  const strs = ['', 'plain', 'quote " and \\ back', 'tab\t nl\n cr\r ff\f bs\b', '\u0001\u001f ctrl', 'é ñ 中文 🎱', 'Zhao|9|p', "O'Brien de Vries"];
  const key = () => { const r = jrnd(); return r < 0.3 ? String(Math.floor(jrnd() * 300)) : r < 0.4 ? '0' + Math.floor(jrnd() * 9) : ['a', 'b', 'name', 'x', 'y', 'm', 'pop', 'seed', '-1', '1.5', 'é'][Math.floor(jrnd() * 11)]; };
  const val = d => { const r = jrnd(); if (d > 3 || r < 0.35) return [null, true, false, jrnd() * 1000, Math.round(jrnd() * 100), strs[Math.floor(jrnd() * strs.length)]][Math.floor(jrnd() * 6)];
    if (r < 0.65) { const o = {}; for (let i = Math.floor(jrnd() * 6); i > 0; i--) o[key()] = val(d + 1); return o; } return [...Array(Math.floor(jrnd() * 5))].map(() => val(d + 1)); };
  const objs = [...Array(200)].map(() => { const o = {}; for (let i = 0; i < 8; i++) o[key()] = val(0); return JSON.stringify(o); });
  /* a repeated key in the text: the first place, the last value */
  objs.push('{"b":1,"a":2,"b":3,"10":4,"2":5}');
  const jv = JSON.stringify({ nums: nums.map(v => [bits(v), String(v)]), strs: strs.map(s => [s, JSON.stringify(s)]), objs: objs.map(t => [t, JSON.stringify(JSON.parse(t))]) });
  /* 4o's camera: on each table and two boxes (a phone upright and on its side), poses behind the cue ball at several
     aims, pitches and distances (the matrices, F, the principal point), points projected and screen points unprojected
     through each, the orbit and its eye, a blend, and the overview for three shot directions */
  const v3cams = [];
  {
    const bits = v => v === null ? null : hx(v), arr = a => a.map(bits);
    for (const T of [['7', null, 'regulation'], ['9', null, 'generous'], ['snooker', 'compact', 'regulation'], ['carom', null, 'regulation'], ['bumper', 'octagon', 'regulation'], ['heyball', null, 'regulation']]) {
      S.setPockets(T[2]); S.setGame ? null : null; S.setTable(T[0], T[1]);
      for (const box of [{ left: 0, top: 0, width: 393, height: 700 }, { left: 40, top: 8, width: 760, height: 330 }]) {
        S.V3.box = box;
        const poses = [];
        for (const [px, py, yaw, pitch, dist] of [[S.TL * 0.25, S.TW * 0.5, 0, 24, 1.1], [S.TL * 0.6, S.TW * 0.3, 2.1, 8, 0.45], [S.TL * 0.1, S.TW * 0.9, -1.3, 70, 3.2], [S.TL * 0.5, S.TW * 0.5, 3.14, 40, 1.8]]) {
          Object.assign(S.V3, { px, py, yaw, mv: null, ovOn: false }); S.settings.viewPitch = pitch; S.settings.viewDist = dist;
          const C = S.v3Pose(0);
          const pts = [[S.TL / 2, S.TW / 2, 0], [px + 0.3, py, S.BALL_R], [0, 0, 0.04], [S.TL, S.TW, 0], [px - 0.2, py + 0.1, 0]].map(P => { const q = S.v3Proj(P[0], P[1], P[2]); return q ? arr(q) : null; });
          const back = [[box.left + 100, box.top + 200], [box.left + box.width / 2, box.top + box.height * 0.7], [box.left + 10, box.top + 10]].map(Q => { const q = S.v3Unproj(Q[0], Q[1], S.BALL_R); return q ? arr(q) : null; });
          const o = S.v3OrbitOf(C.E, C.T), e = S.v3EyeOf(o), l = S.v3Lerp(o, { T: [S.TL / 2, S.TW / 2, 0], yaw: o.yaw + 2.5, pitch: 0.9, dist: 2.4 }, 0.37);
          poses.push({ px: bits(px), py: bits(py), yaw: bits(yaw), pitch, dist, M: arr(C.M), F: bits(C.F), cx: bits(C.cx), cy: bits(C.cy), E: arr(C.E), T: arr(C.T), pts, back,
            orbit: [...arr(o.T), bits(o.yaw), bits(o.pitch), bits(o.dist)], eye: [...arr(e.E), ...arr(e.T)], lerp: [...arr(l.T), bits(l.yaw), bits(l.pitch), bits(l.dist)] });
        }
        const ovs = [0, 1.2, -2.6].map(y => { const o = S.v3Overview(y); return { yaw0: bits(y), T: arr(o.T), yaw: bits(o.yaw), pitch: bits(o.pitch), dist: bits(o.dist), fill: bits(o.fill), ok: o.ok }; });
        v3cams.push({ table: T[0], shape: T[1], pockets: T[2], box: [box.left, box.top, box.width, box.height], poses, ovs });
      }
    }
  }
  /* 4m: the hero's shot on every table it has one for (and the ones it breaks straight on), the roll recorded to rest:
     the samples, the pots (when, where, from), the last motion, the final positions and turns, a sample midway */
  const heroes = [];
  {
    const bits = v => hx(v), arr = a => Array.from(a, bits);
    for (const [kind, args] of [['8', ['7', null, 'regulation']], ['8', ['7', null, 'generous']], ['8', ['9', null, 'regulation']], ['9', ['9', null, 'regulation']], ['9', ['7', null, 'generous']],
      ['10', ['9', null, 'generous']], ['straight', ['7', null, 'regulation']], ['rotation', ['9', null, 'generous']], ['heyball', ['heyball', null, 'regulation']],
      ['snooker', ['snooker', 'compact', 'regulation']], ['snooker', ['snooker', 'full', 'regulation']], ['bumper', ['bumper', 'octagon', 'regulation']], ['bumper', ['bumper', 'rect', 'regulation']],
      ['carom', ['carom', null, 'regulation']]]) {
      S.setPockets(args[2]); S.setTable(args[0], args[1]);
      const d = S.heroSetup(kind), run = S.heroRunStart(d);
      for (;;) { let go = true; for (let k = 0; k < 6 && go; k++) go = S.stepTable(run.tab); S.heroSample(run); if (!go) { run.done = true; run.S = Math.max(0.4, run.moveT); break; } }
      const mid = run.pos[Math.floor(run.pos.length / 2)], last = run.pos[run.pos.length - 1];
      heroes.push({ kind, args, key: S.heroKey(kind), shot: [d.shot.ball, bits(d.shot.angle), bits(d.shot.power)], samples: run.pos.length, mid: arr(mid), last: arr(last),
        on: Array.from(run.on[run.on.length - 1]), pots: Object.entries(run.pots).map(([i, p]) => [+i, bits(p.t), p.k, arr(p.at)]), moveT: bits(run.moveT), S: bits(run.S),
        m: run.m.map(arr), rot: Array.from(run.rot[run.rot.length - 1]) });
    }
  }
  /* sim 1e+, practice: rng's draws, every layout's rack (the scatter by seed) on each pool table, practiceJudge on a
     shot's result (a pot, a scratch, the table cleared, the toggle on), and the free table's editing (addBall over a
     grid from the empty table, then removeBall) */
  const practice = { draws: [], tables: [] };
  {
    const bits = v => hx(v), lay = bs => bs.map(b => [b.n, bits(b.x), bits(b.y), b.on]);
    for (const sd of [1, 2, 42, 4000000000]) { const r = S.rng(sd); practice.draws.push([sd, ...Array.from({ length: 6 }, () => bits(r()))]); }
    for (const T of [['7', null, 'regulation'], ['9', null, 'generous'], ['heyball', null, 'regulation']]) {
      S.setPockets(T[2]); S.setTable(T[0], T[1]);
      /* newGame moves the table (a heyball game to its own, any other off it), so each rack is laid where the page lays
         it: Chinese 8-ball's on its table (beginSolo sets it), the rest on the pool tables */
      const racks = [], hey = T[0] === 'heyball';
      for (const [layout, seed] of hey ? [['heyball', 1]] : [['8', 1], ['9', 1], ['scatter', 1], ['scatter', 2], ['scatter', 42], ['scatter', 4000000000], ['empty', 1], ['nonsense', 3]]) {
        S.setPockets(T[2]); S.setTable(T[0], T[1]);
        const g = S.newPractice(layout, seed);
        racks.push({ layout, seed, kind: g.kind, glayout: g.layout, inHand: g.inHand, breakShot: g.breakShot, balls: lay(g.balls) });
      }
      if (hey) { practice.tables.push({ table: T, racks, judged: [], edits: [] }); continue; }
      /* the judge: from the scatter (seed 2) a pot of the 3, a scratch with a pot, everything down, and the toggle on */
      const g0 = S.newPractice('scatter', 2), mv = g0.balls.map(b => Object.assign({}, b, { x: b.x + 0.01, vx: 0.5 }));
      const judged = [];
      for (const [potted, hand] of [[[3], false], [[0, 5], false], [g0.balls.filter(b => b.n > 0).map(b => b.n), false], [[], true]]) {
        const g = Object.assign({}, g0, { hand, dry: 2 }), balls = mv.map(b => Object.assign({}, b, { on: !potted.includes(b.n) }));
        const n = S.practiceJudge(g, { balls, potted });
        judged.push({ potted, hand, inHand: n.inHand, dry: n.dry, shots: n.shots, turn: n.turn, breakShot: n.breakShot, v: [n.verdict.potted, n.verdict.scratch, n.verdict.cleared], balls: lay(n.balls) });
      }
      /* editing: drops over a grid from the empty table, then two removals and a bad one */
      let g = S.newPractice('empty', 1);
      const edits = [];
      for (let i = 0; i < 6; i++) for (let j = 0; j < 4; j++) {
        const x = S.TL * (0.04 + 0.18 * i), y = S.TW * (0.08 + 0.28 * j), n = S.addBall(g, x, y);
        edits.push(['add', bits(x), bits(y), n ? S.onTable(n) : null]);
        if (n) g = n;
      }
      for (const k of [3, 0, 99, 1]) { const n = S.removeBall(g, k); edits.push(['remove', k, n ? S.onTable(n) : null]); if (n) g = n; }
      edits.push(['final', lay(g.balls)]);
      practice.tables.push({ table: T, racks, judged, edits });
    }
  }
  /* sim 1h, trick shots: on each table setting every challenge's layout and zone, its stored solution simulated (the rest
     positions, the pots and their pockets) and judged (ok and the words), and the program's sums */
  const tricks = { sets: [], val: Object.entries(S.TRICK_VAL).map(([id, v]) => [id, v.disc, v.val]).sort(), max: S.programMax(),
    pts: [6, 7, 8, 9, 10].map(v => [0, 1, 2, 3, 4].map(n => S.trickPts(v, n))), stars: [1, 2, 3, 4, 9].map(n => S.trickStars(n)),
    fromStars: S.trickScoreFromStars({ kiss: 3, carom: 2, two: 1, long: 3, bad: 3, needle: 7 }, { carom: 9 }) };
  {
    const bits = v => hx(v);
    for (const [t, pk] of [['7', 'regulation'], ['9', 'regulation'], ['7', 'generous'], ['9', 'generous']]) {
      S.setPockets(pk); S.setTable(t);
      const rows = [];
      for (const c of S.TRICKS) {
        const P = S.trickPoints(c), sol = S.trickSol(c), g = S.trickGame(c);
        const res = S.simulateShot(g.balls, { angle: sol.angle, power: sol.power, spin: sol.spin });
        const j = S.trickJudge(c, res);
        /* and three misses, so the failures' words and thresholds are judged too: the angle off, soft, and turned back */
        /* (the tip kept on the ball, as the pad keeps it: the side only ever scaled down) */
        const miss = [[0.06, 1, 1], [0, 0.35, 1], [Math.PI, 1, 0.5]].map(([da, kp, ks]) => {
          const m = S.simulateShot(g.balls, { angle: sol.angle + da, power: sol.power * kp, spin: Object.assign({}, sol.spin, { x: sol.spin.x * ks }) }), mj = S.trickJudge(c, m);
          return [mj.ok, mj.why, m.potted];
        });
        rows.push({ id: c.id, pts: Object.entries(P).map(([k, p]) => [k, bits(p[0]), bits(p[1])]), balls: g.balls.map(b => b.n),
          rest: res.balls.map(b => [b.n, bits(b.x), bits(b.y), b.on]), potted: res.potted, pocketOf: res.pocketOf, ok: j.ok, why: j.why, miss });
      }
      tricks.sets.push({ table: t, pockets: pk, rows });
    }
  }
  /* sim 1m, drills: on each table setting every drill run with its 7 ft regulation solutions and with two misses (the
     angle 0.05 off, at 40% power), each shot's layout as the run reaches it, its score, words, count and balls left, the
     total, and the tiers */
  const drills = { sets: [] };
  {
    const bits = v => hx(v), sols = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'tests', 'drill-solutions.json'), 'utf8'))['7r'];
    const shotOf = a => ({ angle: a[0], power: a[1], spin: { x: a[2], y: a[3] } });
    for (const [t, pk] of [['7', 'regulation'], ['9', 'regulation'], ['7', 'generous'], ['9', 'generous']]) {
      S.setPockets(pk); S.setTable(t);
      const rows = [];
      for (const d of S.DRILL_LIB) {
        const base = sols[d.id].shots.map(shotOf), runs = [];
        for (const [da, kp] of [[0, 1], [0.05, 1], [0, 0.4]]) {
          const shots = base.map(x => ({ angle: x.angle + da, power: x.power * kp, spin: x.spin }));
          /* the layouts along the run (prev: the balls the last shot left) */
          const lays = []; let prev = null;
          for (let i = 0; i < d.shots; i++) {
            const Sh = S.drillShot(d, i, prev), r = S.simulateShot(S.drillBalls(Sh), shots[i]);
            lays.push({ balls: Sh.balls.map(([n, p]) => [n, bits(p[0]), bits(p[1])]), say: Sh.say, pocket: Sh.pocket === undefined ? null : Sh.pocket,
              zone: Sh.zone ? [bits(Sh.zone.at[0]), bits(Sh.zone.at[1]), bits(Sh.zone.full), bits(Sh.zone.zero)] : null,
              line: Sh.line ? [bits(Sh.line.x), bits(Sh.line.full), bits(Sh.line.zero), !!Sh.line.lag] : null, box: Sh.box ? Sh.box.map(bits) : null, target: Sh.target === undefined ? null : Sh.target });
            prev = r.balls;
          }
          const R = S.drillRun(d, shots);
          runs.push({ da, kp, js: R.js.map(j => [j.s, j.why, j.n, j.left]), total: R.total, lays });
        }
        rows.push({ id: d.id, shots: d.shots, tiers: d.tiers, runs, tierOf: [0, 33, 45, 50, 66, 85, 99, 100].map(x => S.drillTier(d, x)) });
      }
      drills.sets.push({ table: t, pockets: pk, rows });
    }
  }
  /* 5s, the daily shot: the page's own dayNum and dailyTrick (cut from section 5) over 800 days, across year ends,
     leap days and before 1970 */
  const daily = { days: [] };
  {
    const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8'), cut = re => { const m = src.match(re); if (!m) throw new Error('daily: ' + re); return m[0]; };
    const fn = new Function('TRICKS', cut(/const dayNum = [^\n]*/) + '\nconst DAILY_TRICKS = TRICKS.filter(c => !c.group);\n' + cut(/const dailyTrick = [^\n]*/).replace('(day = today())', '(day)') + '\nreturn { dayNum, dailyTrick };')(S.TRICKS);
    const pad = n => String(n).padStart(2, '0'), at = t => { const d = new Date(t); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`; };
    const starts = [Date.UTC(2026, 0, 1), Date.UTC(1999, 11, 20), Date.UTC(2028, 1, 20), Date.UTC(1969, 11, 25), Date.UTC(2038, 0, 10)];
    for (const t0 of starts) for (let i = 0; i < 160; i++) { const day = at(t0 + i * 864e5); daily.days.push([day, fn.dayNum(day), fn.dailyTrick(day).id]); }
  }
  return { math, career, careerData, jv, daily: JSON.stringify(daily), drills: JSON.stringify(drills), tricks: JSON.stringify(tricks), practice: JSON.stringify(practice), hero: JSON.stringify({ heroes }), v3: JSON.stringify({ cams: v3cams }), golden: JSON.stringify({ hashEvery: HASH_EVERY, tables, cases, guides }), rules: JSON.stringify({ games }), cpu: JSON.stringify({ cpu }), tables, cases, guides, games, cpuCases: cpu };
}
/* tests/ios-check.cjs rebuilds both in memory and requires the committed files to match */
module.exports = { build, OUT, loadFd };
if (require.main === module) {
  const b = build();
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'math.txt'), b.math);
  fs.writeFileSync(path.join(OUT, 'golden.json'), b.golden);
  fs.writeFileSync(path.join(OUT, 'rules.json'), b.rules);
  fs.writeFileSync(path.join(OUT, 'cpu.json'), b.cpu);
  fs.writeFileSync(path.join(OUT, 'career.json'), b.career);
  fs.writeFileSync(path.join(OUT, 'jv.json'), b.jv);
  fs.writeFileSync(path.join(OUT, 'v3.json'), b.v3);
  fs.writeFileSync(path.join(OUT, 'hero.json'), b.hero);
  fs.writeFileSync(path.join(OUT, 'practice.json'), b.practice);
  fs.writeFileSync(path.join(OUT, 'tricks.json'), b.tricks);
  fs.writeFileSync(path.join(OUT, 'drills.json'), b.drills);
  fs.writeFileSync(path.join(OUT, 'daily.json'), b.daily);
  fs.writeFileSync(path.join(__dirname, '..', 'ios', 'FeltSim', 'Sources', 'FeltSim', 'CareerData.swift'), b.careerData);
  const steps = b.cases.reduce((a, c) => a + c.result.steps, 0);
  console.log(`ios-golden: ${b.tables.length} tables, ${b.cases.length} shots, ${b.guides.length} guides, ${b.games.length} games (${b.games.reduce((a, g) => a + g.steps.length, 0)} judgements), ${b.cpuCases.length} CPU decisions, ${steps} steps, ${b.cases.reduce((a, c) => a + c.result.potted.length, 0)} pots -> ${path.relative(process.cwd(), OUT)}`);
}
