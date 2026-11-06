# Prompt: WoW-addon för Forever Fitness

Klistra in texten nedan i Claude Code, startad i det här repot, så att den kan läsa
övningarna och reglerna i webbappen.

**Tips**
- Testa fas 1 i spelet med `/fit test death` innan du går vidare till nästa fas.
- Om Claude Code inte hittar säkra uppgifter om WoW Forevers addon-API ber den dig köra
  kommandon i spelet och berätta vad som händer. Det är meningen, den ska inte gissa.
- Kopiera själv mappen `addon/ForeverFitness` till WoW:s AddOns-mapp (Claude Code i molnet
  når inte din dator). Kör du Claude Code lokalt på speldatorn kan den göra det åt dig.

---

```text
Jag vill bygga ett World of Warcraft-addon som heter "Forever Fitness" och
som spelaren kör i WoW Forever (släpptes 4 november 2026, maxnivå 60, nio
klassiska klasser). Addonet ska upptäcka händelser i spelet och visa en
notis med en kort kroppsviktsövning, så att jag och min 13-åring tränar
medan vi spelar. Det kompletterar webbappen i det här repot.

## Bakgrund
- Webbappen ligger i src/forever-fitness.html (byggs till index.html med
  tools/build.py). Läs den först. Övningarna (EX), spelhändelserna (EVENTS),
  svårighetsnivåerna (DIFF) och formeln för antal reps (target()) ska
  addonet spegla, så att samma händelse ger samma övning och antal i båda.
- Addons kan inte prata med internet. Kopplingen till webbappen sker med en
  exportkod (se fas 3).
- All text i addonet ska vara på svenska.

## Gör detta först, innan du skriver kod
1. Ta reda på vilken klientversion och vilket addon-API WoW Forever
   använder: Interface-numret till .toc-filen, vilken AddOns-mapp addonet
   ska installeras i, och vilka events och funktioner som finns.
   Klienten är ny, så gissa inte. Om du inte hittar säkra uppgifter: skriv
   koden så att den klarar sig när ett API saknas (kontrollera att
   funktioner och C_-namnrymder finns innan de anropas). Skriv också ner
   exakt vad jag ska kontrollera i spelet, till exempel
   /dump (select(4, GetBuildInfo())) för Interface-numret.
2. Ge mig en kort plan och lista dina antaganden. Vänta på mitt OK innan
   du bygger.

## Fas 1: Händelser och notiser (MVP)
Upptäck följande och koppla dem till samma övningar som i webbappen:
- Död: PLAYER_DEAD → burpees
- Level up: PLAYER_LEVEL_UP → armhävningar
- Laddningsskärm: LOADING_SCREEN_DISABLED → knäböj
- Flygresa: när UnitOnTaxi("player") blir sant → knäböj
- Bossdöd: ENCOUNTER_END med success=1 (eller BOSS_KILL om det saknas) → utfall
- Wipe: ENCOUNTER_END med success=0 → planka
- Bra loot: eget loot med kvalitet sällsynt eller bättre (via CHAT_MSG_LOOT
  eller motsvarande) → jumping jacks
- AFK: när UnitIsAFK("player") blir sant → mountain climbers
- Raidvarning: pausalarm var N:e minut medan man är inloggad (standard 30)
  → slumpad övning

Notisernas regler:
- Visa aldrig en notis under strid. Köa den och visa den efter
  PLAYER_REGEN_ENABLED. Använd inga skyddade funktioner, och skapa inga
  ramar under strid, så att addonet inte orsakar taint.
- Egen flyttbar ruta (inte modal) med övning, antal och tre knappar:
  "Klart!", "Om 5 min" och "Hoppa över". Rutans position sparas.
- Ljud och en kort text i RaidWarningFrame eller motsvarande. Ljudet ska
  gå att stänga av. Kontrollera att SOUNDKIT-id:n finns, annars används
  ett säkert standardljud.
- Spärrtid per händelse, så att till exempel tre dödsfall i rad ger en
  notis och inte tre. Standard: 2 minuter, och högst en notis i taget.
  Övriga köas.
- Svårighet Lätt, Normal eller Hård (0,6 / 1 / 1,4), samma som i appen.

## Fas 2: Inställningar och statistik
- Snabbkommandon: /fit (visa/dölj), /fit config, /fit test <händelse>,
  /fit stats, /fit export, /fit reset.
- Inställningspanel: slå av och på varje händelse, välj övning per händelse,
  svårighet, intervall för raidvarningen, ljud av/på och spärrtid. Använd
  Settings-API:t om det finns, annars InterfaceOptions_AddCategory.
- SavedVariables: inställningar per konto, logg per karaktär med tid,
  händelse, övning, antal och om setet gjordes eller hoppades över.
- /fit stats: set i dag, i veckan och totalt, plus mest gjorda övningar.

## Fas 3: Export till webbappen
- /fit export visar en ruta med en kod som går att markera och kopiera.
  Koden ska börja med "WFFA-" och innehålla base64-kodad JSON med alla
  avklarade set sedan förra exporten: tid, övnings-id från appen och antal.
  Skriv egen JSON-serialisering och base64 i Lua 5.1.
- Lägg till import i webbappen: en ruta under Hjälte → Inställningar där
  koden klistras in. Seten loggas som källa "addon" och ger XP med samma
  regler som spelhändelser. Samma kod får inte kunna importeras två gånger
  (spara exportens id).

## Struktur och kvalitet
- Lägg addonet i addon/ForeverFitness/ med .toc, Core.lua, Events.lua,
  Notify.lua, Config.lua, Export.lua och Data.lua (övningar och händelser).
- Gör en enkel testmiljö i Lua 5.1 som låtsas vara WoW (mock av
  CreateFrame, events och tid). Testa logiken för spärrtid, strid-kö,
  antal reps och export/JSON/base64 utan att spelet körs. Kör luacheck om
  det finns.
- Skriv addon/README.md på svenska: installation (vilken mapp i
  World of Warcraft-katalogen), kommandon, och hur man testar i spelet
  med /fit test.
- Addonet får bara visa information. Det får inte automatisera något i
  spelet (inga tangenttryck, inga klick, ingen rörelse), så att det följer
  Blizzards regler.
- Arbeta på en egen gren och committa per fas. Ändra inte webbappen
  förutom importen i fas 3. Kör sedan tools/build.py.

När varje fas är klar: berätta vad som fungerar, vad som är otestat i
spelet, och exakt vad jag ska prova när jag loggar in.
```
