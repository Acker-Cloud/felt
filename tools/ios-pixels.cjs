/* Pixel references for the iOS port's renderer (ios/FeltSim's FeltRender). The page paints its static
   table (4a's paintTable, plus the game screen's vignette) into a fixed view for each game's look,
   upright and on its side, and saves each as a PNG with the view it was painted in. FeltRender's
   tests paint the same views and measure the difference pixel by pixel. napCache is cleared before
   each paint, so the cloth's nap comes from that paint's own rng(0x5eed) sequence, as FeltRender's
   does. Re-run after any change to section 4a:   node tools/ios-pixels.cjs                       */
'use strict';
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const OUT = path.join(__dirname, '..', 'ios', 'FeltSim', 'Tests', 'FeltRenderTests', 'Fixtures');
const PORT = 4187;
/* [game, table, shape]: the table each game is dressed for (GAME_LOOK) */
const GAMES = [['8', '7'], ['9', '9'], ['straight', '7'], ['rotation', '7'], ['heyball', 'heyball'], ['snooker', 'snooker', 'compact'], ['carom', 'carom'], ['bumper', 'bumper', 'octagon'], ['bumper', 'bumper', 'rect']];
/* views: a phone upright (portrait, the table turned) and on its side, in CSS px at dpr; every game
   upright, 8-ball on its side too (the nap is noise and does not compress: about 2 MB an image) */
/* the shop's looks (a career's equipped items, lookCareer), on 8-ball's 7 ft table upright: every cloth and rail the
   game looks do not cover, and the Pro and Vintage ball sets on the cloths with a rim */
const SHOP = [{ cloth: 'red', rail: 'cherry', balls: 'pro' }, { cloth: 'grey', rail: 'oak', balls: 'vintage' }, { cloth: 'teal', rail: 'ebony', balls: 'classic' },
  { cloth: 'midnight', rail: 'walnut', balls: 'pro' }, { cloth: 'plum', rail: 'cherry', balls: 'vintage' }];
const VIEWS = [{ name: 'up', w: 390, h: 760, dpr: 2, portrait: true }, { name: 'side', w: 760, h: 390, dpr: 2, portrait: false }];

async function main() {
  const server = spawn('python3', ['-m', 'http.server', String(PORT), '--bind', '127.0.0.1'], { cwd: path.join(__dirname, '..'), stdio: 'ignore' });
  process.env.FELT_URL = `http://127.0.0.1:${PORT}/index.html`;
  await new Promise(r => setTimeout(r, 600));
  const { open } = require('../tests/lib.cjs');
  const { browser, page, errors } = await open('', { viewport: { width: 400, height: 800 } });
  fs.mkdirSync(OUT, { recursive: true });
  const index = [];
  try {
    for (const [game, table, shape] of GAMES) {
      for (const V of VIEWS.filter(v => v.name === 'up' || game === '8')) {
        const r = await page.evaluate(({ game, table, shape, V }) => {
          setPockets('regulation'); setTable(table, shape);
          /* the bed with its rails fitted to the view, centred: RAIL as layout() picks it for that size */
          RAIL = railFor(V.w, V.h);
          const L = TL + 2 * RAIL, W = TW + 2 * RAIL, sw = V.portrait ? W : L, sh = V.portrait ? L : W;
          const k = Math.min(V.w / sw, V.h / sh);
          view = { k, portrait: V.portrait, ox: (V.w - sw * k) / 2 + RAIL * k, oy: (V.h - sh * k) / 2 + RAIL * k, tray: null };
          dpr = V.dpr; napCache = null;
          const c = lookIn(game, () => { const c = paintTable(V.w * V.dpr, V.h * V.dpr); paintVignette(c.getContext('2d')); return c; });
          return { png: c.toDataURL('image/png'), view, RAIL, dpr, page: pageColor(), look: lookIn(game, () => look()), room: lookIn(game, () => roomId()) };
        }, { game, table, shape, V });
        const file = `table-${game}${game === 'bumper' ? '-' + shape : ''}-${V.name}.png`;
        fs.writeFileSync(path.join(OUT, file), Buffer.from(r.png.split(',')[1], 'base64'));
        index.push({ file, game, table, shape: shape || null, w: V.w * V.dpr, h: V.h * V.dpr, dpr: r.dpr, RAIL: r.RAIL, view: r.view, page: r.page, look: r.look, room: r.room });
      }
    }
    for (const L of SHOP) {
      const V = VIEWS[0];
      const r = await page.evaluate(({ L, V }) => {
        setPockets('regulation'); setTable('7');
        lookCareer = () => ({ cloth: L.cloth, cue: 'house', chalk: 'blue', rail: L.rail, balls: L.balls, ring: null });
        try {
          RAIL = railFor(V.w, V.h);
          const sw = TW + 2 * RAIL, sh = TL + 2 * RAIL, k = Math.min(V.w / sw, V.h / sh);
          view = { k, portrait: true, ox: (V.w - sw * k) / 2 + RAIL * k, oy: (V.h - sh * k) / 2 + RAIL * k, tray: null };
          dpr = V.dpr; napCache = null;
          const c = lookIn('8', () => { const c = paintTable(V.w * V.dpr, V.h * V.dpr); paintVignette(c.getContext('2d')); return c; });
          return { png: c.toDataURL('image/png'), view, RAIL, dpr, page: pageColor(), look: lookIn('8', () => look()), room: lookIn('8', () => roomId()) };
        } finally { lookCareer = () => null; }
      }, { L, V });
      const file = `table-shop-${L.cloth}-up.png`;
      fs.writeFileSync(path.join(OUT, file), Buffer.from(r.png.split(',')[1], 'base64'));
      index.push({ file, game: '8', table: '7', shape: null, w: V.w * V.dpr, h: V.h * V.dpr, dpr: r.dpr, RAIL: r.RAIL, view: r.view, page: r.page, look: r.look, room: r.room });
    }
    /* balls: each look's set in a grid, at a phone's size and large, on the cloth, with their shadows */
    const BALLS = GAMES.filter(g => !['bumper', 'straight', 'rotation'].includes(g[0])).map(g => [...g, null]).concat(SHOP.filter(L => L.balls !== 'classic').map(L => ['8', '7', undefined, L]));
    for (const [game, table, shape, L] of BALLS) {
      const r = await page.evaluate(({ game, table, shape, L }) => {
        if (L) lookCareer = () => ({ cloth: L.cloth, cue: 'house', chalk: 'blue', rail: L.rail, balls: L.balls, ring: null });
        try {
        setPockets('regulation'); setTable(table, shape);
        const W = 960, H = 400, nums = table === 'snooker' ? [0, 41, 42, 57, 58, 59, 60, 61, 62] : table === 'carom' ? [70, 71, 72] : [...Array(16).keys()];
        const R = rng(0x0ba11), balls = [];
        nums.forEach((n, i) => [18.5, 44].forEach((rad, j) => {
          let m = IDENT;
          for (let q = 0; q < 3; q++) m = rotate(m, [R() - 0.5, R() - 0.5, R() - 0.5], R() * 6.3);
          const per = j ? 8 : 16, X = j ? 60 + (i % per) * 110 : 32 + (i % per) * 58, Y = j ? 150 + Math.floor(i / per) * 110 : 40 + Math.floor(i / per) * 52;
          balls.push({ n, X, Y, r: rad, m, x: X / W * TL, y: Y / H * TW });
        }));
        view = { k: 100, portrait: false, ox: 0, oy: 0, tray: null }; dpr = 2;
        const out = lookIn(game, () => {
          const c = document.createElement('canvas'); c.width = W; c.height = H;
          const g = c.getContext('2d'); g.fillStyle = CLOTH; g.fillRect(0, 0, W, H);
          artCtx = g;
          try { for (const b of balls) drawCast(b.x, b.y, b.X, b.Y, b.r); for (const b of balls) drawBall(b.n, b.X, b.Y, b.r, axesOf(b.m)); } finally { artCtx = null; }
          return { png: c.toDataURL('image/png'), cloth: CLOTH, bounce: CL.bounce, lowRim: !!CL.lowRim, rim: !!CL.rim, balls: look().balls };
        });
        return Object.assign(out, { W, H, list: balls, TL, TW, R: BALL_R });
        } finally { lookCareer = () => null; }
      }, { game, table, shape, L });
      const name = L ? `shop-${L.cloth}-${L.balls}` : game, file = `balls-${name}.png`;
      fs.writeFileSync(path.join(OUT, file), Buffer.from(r.png.split(',')[1], 'base64'));
      delete r.png;
      fs.writeFileSync(path.join(OUT, `balls-${name}.json`), JSON.stringify(Object.assign({ file, game, table, shape: shape || null }, r)));
    }
  } finally {
    await browser.close();
    server.kill();
  }
  if (errors.length) throw new Error('page errors: ' + errors.join(' | '));
  fs.writeFileSync(path.join(OUT, 'tables.json'), JSON.stringify(index, null, 1));
  console.log(`ios-pixels: ${index.length} table images -> ${path.relative(process.cwd(), OUT)}`);
}
main().catch(e => { console.error(e); process.exit(1); });
