"""Bygger index.html (fristående app för GitHub Pages) från src/forever-fitness.html.

src-filen är samma innehåll som publiceras som Claude-artifact (utan <html>/<head>).
Kör: python3 tools/build.py
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
body = (root / "src" / "forever-fitness.html").read_text(encoding="utf-8")

head = """<!doctype html>
<html lang="sv">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#10121a">
<meta name="description" content="Träningskompanjon för WoW-kvällar: spelhändelser blir korta set med XP, nivåer och veckoboss.">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" href="icons/icon-192.png">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Forever Fitness">
</head>
<body>
"""
tail = """
<script>
if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js').catch(function () {});
}
</script>
</body>
</html>
"""
(root / "index.html").write_text(head + body + tail, encoding="utf-8")
print("index.html byggd")
