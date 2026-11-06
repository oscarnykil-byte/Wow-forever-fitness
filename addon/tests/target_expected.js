// Skriver ut antal reps enligt webbappens egen target(), så att Lua-testerna
// kan jämföra addonet mot appen. Körs av run_tests.lua om node finns.
// Utdata: en rad per fall: "<övning> <svårighet> <nivå> <faktor> <antal>"
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', '..', 'src', 'forever-fitness.html'), 'utf8');

function grab(re, what) {
  const m = html.match(re);
  if (!m) throw new Error('Hittar inte ' + what + ' i webbappen');
  return m[0];
}
const ex = grab(/const EX=\{[\s\S]*?\n\};/, 'EX');
const diff = grab(/const DIFF=\{.*\};/, 'DIFF');
const target = grab(/function target\(ex,f=1\)\{.*\}/, 'target()');
const events = grab(/const EVENTS=\[[\s\S]*?\n\];/, 'EVENTS');

const body = `${ex}\n${diff}\n${events}\nlet CUR={diff:'normal',L:1};\n` +
  `const P=()=>({diff:CUR.diff});const totalXP=()=>0;const levelInfo=()=>({L:CUR.L});\n${target}\n` +
  `return {EX,DIFF,EVENTS,target,CUR};`;
const app = new Function(body)();

const out = [];
for (const id of Object.keys(app.EX)) {
  for (const d of Object.keys(app.DIFF)) {
    for (const L of [1, 7, 12, 30, 45, 60]) {
      for (const f of [1, 0.6]) {
        app.CUR.diff = d; app.CUR.L = L;
        out.push(`${id} ${d} ${L} ${f} ${app.target(id, f)}`);
      }
    }
  }
}
for (const e of app.EVENTS) out.push(`event ${e.id} ${e.ex} ${e.f}`);
process.stdout.write(out.join('\n') + '\n');
