// Läser QR-matriser från Lua (rader med 0/1, block åtskilda av "--") och
// avkodar dem med jsQR. Skriver "ok" eller felet per block.
// Används av run_tests.lua. Kräver: npm install --no-save jsqr@1.4.0 (i addon/tests)
let jsQR;
try { jsQR = require('jsqr'); } catch (e) { process.stdout.write('SKIP\n'); process.exit(0); }
const input = require('fs').readFileSync(0, 'utf8').trim().split('\n--\n');
const out = [];
for (const block of input) {
  const lines = block.split('\n');
  const want = Buffer.from(lines.shift(), 'hex').toString('latin1');
  const n = lines.length, quiet = 4, scale = 4, W = (n + quiet * 2) * scale;
  const px = new Uint8ClampedArray(W * W * 4).fill(255);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (lines[y][x] === '1') {
    for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) {
      const i = (((y + quiet) * scale + dy) * W + (x + quiet) * scale + dx) * 4;
      px[i] = px[i + 1] = px[i + 2] = 0;
    }
  }
  const r = jsQR(px, W, W);
  if (!r) out.push('kunde inte läsas (storlek ' + n + ')');
  else {
    const got = Buffer.from(r.binaryData).toString('latin1');
    out.push(got === want ? 'ok' : 'fel text (storlek ' + n + ')');
  }
}
process.stdout.write(out.join('\n') + '\n');
