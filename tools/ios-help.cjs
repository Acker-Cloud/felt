#!/usr/bin/env node
/* How to play's words for the iOS app, taken from index.html's own markup (the topics' list, #howList, and each topic's
   page, .pan: the rules' rows, the fine print, the pinned action), the touch variants where the page has keys and touch.
   Writes ios/Felt/help.json; tests/ios-check.cjs rebuilds it in memory and requires the committed file to match, so the
   app never drifts from the page's words. */
'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..'), OUT = path.join(ROOT, 'ios', 'Felt', 'help.json');
const ENT = { '&larr;': '←', '&rarr;': '→', '&uarr;': '↑', '&darr;': '↓', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&nbsp;': ' ', '&deg;': '°', '&times;': '×', '&middot;': '·' };
const text = h => h.replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]+>/g, '').replace(/&[a-z]+;|&#\d+;/g, e => ENT[e] ?? e).replace(/\s+/g, ' ').trim();
function build() {
  const src = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
  const list = src.slice(src.indexOf('<div class="howList" id="howList">'), src.indexOf('<!-- a page per topic'));
  const topics = [];
  for (const m of list.matchAll(/<button class="topic" id="(tab\w+)" aria-controls="(pan\w+)">([\s\S]*?)<\/button>/g)) {
    const [, tab, pan, body] = m, b = body.match(/<b>([\s\S]*?)<\/b>/), sm = body.match(/<small>([\s\S]*?)<\/small>/);
    const at = src.indexOf(`<section class="pan" id="${pan}"`), sec = src.slice(at, src.indexOf('</section>', at));
    /* a group or fine print given for keys and touch: the touch one */
    const pick = (re) => [...sec.matchAll(re)].filter(g => !/\bkeys\b/.test(g[1])).map(g => g[2]);
    const rules = pick(/<ul class="group rules([^"]*)"[^>]*>([\s\S]*?)<\/ul>/g).flatMap(u => [...u.matchAll(/<li(?: class="touch")?>([\s\S]*?)<\/li>/g)].map(li => {
      const h = li[1].match(/<b>([\s\S]*?)<\/b>/), p = li[1].match(/<p>([\s\S]*?)<\/p>/);
      return [h ? text(h[1]) : '', p ? text(p[1]) : text(li[1])];
    }));
    const fine = pick(/<ul class="fine([^"]*)"[^>]*>([\s\S]*?)<\/ul>/g).flatMap(u => [...u.matchAll(/<li(?: class="touch")?>([\s\S]*?)<\/li>/g)].map(li => text(li[1])));
    const act = sec.match(/<div class="howAct"><button class="([^"]*)" id="(\w+)"(?: data-tut="(\w+)")?>([\s\S]*?)<\/button>/);
    topics.push({ id: tab.replace(/^tab/, ''), title: text(b[1]), sub: sm ? text(sm[1]) : '', rules, fine,
      act: act ? { id: act[2], tut: act[3] || null, text: text(act[4]) } : null });
  }
  return JSON.stringify({ topics }, null, 1) + '\n';
}
module.exports = { build, OUT };
if (require.main === module) { const s = build(); fs.writeFileSync(OUT, s); console.log(`ios-help: ${JSON.parse(s).topics.length} topics -> ${path.relative(ROOT, OUT)}`); }
