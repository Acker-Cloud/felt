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
check('the goldens cover every ported table and pot balls', b.tables.length === 8 && b.cases.length >= 120 && b.cases.some(c => c.result.potted.length > 3), `${b.tables.length} tables, ${b.cases.length} shots`);
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
