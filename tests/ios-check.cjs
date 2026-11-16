/* ios-check: the iOS port's goldens are current. ios/FeltSim (Swift) is index.html's sim 1a-1d bit
   for bit, proven by its GoldenTests against fixtures that tools/ios-golden.cjs makes from the
   page's own sim region. A change to the physics that is not re-run there leaves the port proving
   itself against an old sim, so this rebuilds the fixtures in memory and requires the committed
   ones to match: change the physics, run `node tools/ios-golden.cjs`, then `swift test` in
   ios/FeltSim. Also checks tools/fdlibm.cjs against the engine's Math (within 2 ulp: the engines
   differ only in the last bit, which is why the goldens use fdlibm). */
'use strict';
const fs = require('fs');
const path = require('path');
const { check, done } = require('./lib.cjs');
const { build, OUT } = require('../tools/ios-golden.cjs');
const F = require('../tools/fdlibm.cjs');

const b = build();
const read = f => { try { return fs.readFileSync(path.join(OUT, f), 'utf8'); } catch { return null; } };
const golden = read('golden.json'), math = read('math.txt'), rules = read('rules.json'), cpu = read('cpu.json');
let firstOff = '';
if (golden && golden !== b.golden) {
  const old = JSON.parse(golden).cases, i = old.findIndex((c, k) => JSON.stringify(c) !== JSON.stringify(b.cases[k]));
  firstOff = i < 0 ? 'tables differ' : `first stale shot: ${old[i] ? old[i].name : b.cases[i].name}`;
}
check('ios goldens match the current sim (re-run node tools/ios-golden.cjs and swift test after a physics change)', golden === b.golden, firstOff);
check('ios math fixture matches tools/fdlibm.cjs', math === b.math);
check('ios rules goldens match the current rules (sim 1e)', rules === b.rules, rules ? '' : 'rules.json missing');
check('ios CPU goldens match the current CPU (sim 1f)', cpu === b.cpu, cpu ? '' : 'cpu.json missing');
/* the career library (the quick tournament's brackets, match model and players) and its constants, generated as Swift */
const careerData = (() => { try { return fs.readFileSync(path.join(__dirname, '..', 'ios', 'FeltSim', 'Sources', 'FeltSim', 'CareerData.swift'), 'utf8'); } catch { return null; } })();
check('ios JV goldens match V8 (Number#toString, JSON.stringify)', read('jv.json') === b.jv, read('jv.json') ? '' : 'jv.json missing');
check('ios 3D camera goldens match the page (4o: poses, projection, overview)', read('v3.json') === b.v3, read('v3.json') ? 'v3.json is stale' : 'v3.json missing');
check('ios hero goldens match the page (1n, 4m: the shots and their recorded rolls)', read('hero.json') === b.hero, read('hero.json') ? 'hero.json is stale' : 'hero.json missing');
check('ios practice goldens match the page (1e+: the racks, the scatter, the judge, the editing)', read('practice.json') === b.practice, read('practice.json') ? 'practice.json is stale' : 'practice.json missing');
check('ios trick shot goldens match the page (1h: layouts, stored solutions, the judge, the program)', read('tricks.json') === b.tricks, read('tricks.json') ? 'tricks.json is stale' : 'tricks.json missing');
check('ios drill goldens match the page (1m: layouts along each run, scores and words, totals, tiers)', read('drills.json') === b.drills, read('drills.json') ? 'drills.json is stale' : 'drills.json missing');
check('ios rail row goldens match the page (6b2: placeRail\'s steps and the score keeper\'s fallback)', read('rail.json') === b.rail, read('rail.json') ? 'rail.json is stale' : 'rail.json missing');
check('ios daily shot goldens match the page (5s: dayNum and the day\'s shot)', read('daily.json') === b.daily, read('daily.json') ? 'daily.json is stale' : 'daily.json missing');
check('ios tutorial goldens match the page (1l: every step laid, solved and judged)', read('tutorials.json') === b.tutorials, read('tutorials.json') ? 'tutorials.json is stale' : 'tutorials.json missing');
{
  /* How to play's words in the app (ios/Felt/help.json) are the page's own, taken by tools/ios-help.cjs */
  const H = require('../tools/ios-help.cjs'), have = fs.existsSync(H.OUT) ? fs.readFileSync(H.OUT, 'utf8') : null;
  check('ios How to play words match the page (#howList and each topic)', have === H.build(), have ? 'help.json is stale: node tools/ios-help.cjs' : 'help.json missing');
}
check('ios career goldens and CareerData.swift match the career engine', read('career.json') === b.career && careerData === b.careerData,
  read('career.json') === b.career ? 'CareerData.swift is stale' : 'career.json is stale');
check('the goldens cover every ported table and pot balls', b.tables.length === 10 && b.cases.length >= 150 && b.cases.some(c => c.result.potted.length > 3)
  && ['octagon', 'rect'].every(sh => b.cases.some(c => c.table === 'bumper' && c.shape === sh && c.result.potted.length)), `${b.tables.length} tables, ${b.cases.length} shots`);
check('the rules goldens play bumper pool to a win on both shapes, with a foul\'s penalty ball', ['octagon', 'rect'].every(sh => b.games.some(g => g.kind === 'bumper' && g.shape === sh
  && g.steps[g.steps.length - 1].out.winner !== null && g.steps.some(s => s.out.verdict.dropped !== null))), `${b.games.filter(g => g.kind === 'bumper').length} bumper games`);
check('the rules goldens play games to a win and reach the choices', b.games.filter(g => g.steps.length && g.steps[g.steps.length - 1].out.winner !== null).length >= 20 && b.games.some(g => g.steps.some(s => s.choice)), `${b.games.length} games`);
const ulp = x => { const a = Math.abs(x); return a === 0 ? Number.MIN_VALUE : 2 ** (Math.floor(Math.log2(a)) - 52); };
let worst = 0;
for (let i = 0; i < 20000; i++) {
  const x = (i / 20000 - 0.5) * 40, y = i / 4000, c = i / 10000 - 1;
  for (const [f, g] of [[F.sin(x), Math.sin(x)], [F.cos(x), Math.cos(x)], [F.atan(x), Math.atan(x)], [F.tan(x / 16), Math.tan(x / 16)],
    [F.exp(-y), Math.exp(-y)], [F.pow(y, 1.7), y ** 1.7], [F.acos(c), Math.acos(c)]]) worst = Math.max(worst, Math.abs(f - g) / ulp(g));
}
check('tools/fdlibm.cjs agrees with the engine\'s Math to 2 ulp', worst <= 2, `worst ${worst} ulp`);
done();
