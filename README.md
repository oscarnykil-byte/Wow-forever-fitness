# Forever Fitness

Träningskompanjon för WoW-kvällar. Det som händer i spelet blir korta set i verkligheten:
dör du blir det burpees, en laddningsskärm blir knäböj, kötid blir väggsittning.
Du samlar XP, går upp i nivå (1–60), håller svitten vid liv och fäller veckans boss.

## Funktioner
- **Spelhändelser** med egna regler: välj övning per händelse och lägg till egna.
- **Raidvarning**: pausalarm som ger en slumpad övning medan du spelar.
- **Dungeon-runda**: fem rum, en boss, en kista. Cirka 10 minuter.
- **Dagens uppdrag** och **veckans boss**.
- **WoW-klasser** med egna XP-bonusar, bedrifter, butik och titlar.
- **Framsteg**: XP per dag, bästa set per övning och personbästa (+10 guld när du slår rekord).
- **Familjeduell** via kod, och säkerhetskopia för att flytta en hjälte mellan enheter.

Framstegen sparas i webbläsaren på varje enhet. Använd säkerhetskopian under fliken Hjälte
för att flytta en hjälte till en ny enhet.

## Slå på GitHub Pages
1. Gå till repot på GitHub → **Settings** → **Pages**.
2. Under *Build and deployment* välj **Deploy from a branch**.
3. Välj grenen **master** och mappen **/ (root)**, tryck **Save**.
4. Efter någon minut finns appen på `https://oscarnykil-byte.github.io/Wow-forever-fitness/`.

Med ett gratiskonto på GitHub måste repot vara publikt för att Pages ska fungera.

## Installera på mobilen
- **iPhone (Safari):** öppna adressen → Dela-knappen → **Lägg till på hemskärmen**.
- **Android (Chrome):** öppna adressen → menyn ⋮ → **Installera app** / **Lägg till på startskärmen**.
- **Dator (Chrome/Edge):** installationsikonen i adressfältet.

Appen fungerar sedan offline.

## Utveckling
- Källan finns i `src/forever-fitness.html` (samma innehåll publiceras som Claude-artifact).
- Bygg den fristående appen: `python3 tools/build.py` → skriver `index.html`.
- Höj `CACHE` i `sw.js` om en uppdatering inte syns i den installerade appen.
