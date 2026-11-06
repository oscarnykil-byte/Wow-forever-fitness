# Forever Fitness – addon för WoW Forever

Addonet visar en kort kroppsviktsövning när något händer i spelet: du dör, får en
level, ser en laddningsskärm och så vidare. Samma händelse ger samma övning och
samma antal som i webbappen Forever Fitness.

Addonet visar bara information. Det trycker inga tangenter, klickar inte och
flyttar inte din karaktär.

## Installation

1. Stäng WoW.
2. Kopiera mappen `ForeverFitness` (den som ligger i `addon/` här i repot) till
   `AddOns`-mappen i WoW Forevers katalog:

   ```
   World of Warcraft/_forever_/Interface/AddOns/ForeverFitness
   ```

   Spelar du via Steam på Linux (Proton) ligger katalogen ungefär här:

   ```
   ~/.local/share/Steam/steamapps/compatdata/<id>/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/
   ```

   Finns inte mapparna `Interface` och `AddOns`, skapa dem. Mappen
   `ForeverFitness` ska innehålla `ForeverFitness.toc` direkt, inte en mapp till.
3. Starta WoW. Klicka på **AddOns** på karaktärsvalet och kontrollera att
   Forever Fitness är påslaget. Står det "Out of date", kryssa i
   **Load out of date AddOns**.

Addonet är byggt för Interface 16001. Kontrollera i spelet med:

```
/dump select(4, GetBuildInfo())
```

## Händelser

| Händelse | Upptäcks med | Övning |
|---|---|---|
| Död | `PLAYER_DEAD` | Burpees (0,6 av fullt antal) |
| Level up | `PLAYER_LEVEL_UP` | Armhävningar |
| Laddningsskärm | `LOADING_SCREEN_DISABLED` (inte den vid inloggning) | Knäböj |
| Flygresa | `UnitOnTaxi("player")` blir sant | Knäböj |
| Bossdöd | `ENCOUNTER_END` med success = 1, annars `BOSS_KILL` | Utfall |
| Wipe | `ENCOUNTER_END` med success = 0 | Planka |
| Bra loot | Eget loot, sällsynt (blått) eller bättre | Jumping jacks |
| AFK | `UnitIsAFK("player")` blir sant | Mountain climbers |
| Raidvarning | Var 30:e minut medan du är inloggad | Slumpad övning utan redskap |

Regler:

- Ingen notis under strid. Den sparas och visas när striden är slut.
- Bara en notis i taget. Resten väntar i kö.
- Spärrtid 2 minuter per händelse. Tre dödsfall i rad ger en notis.
  Laddningsskärm och flygresa delar spärrtid, precis som i webbappen.
- **Klart!** sparar setet, **Om 5 min** visar notisen igen om fem minuter,
  **Hoppa över** sparar att setet hoppades över.
- Dra i rutan för att flytta den. Positionen sparas.

## Antal reps

Antalet räknas med samma formel som i webbappen och beror på svårigheten och på
din **hjältenivå i webbappen** (inte karaktärens nivå i WoW). Addonet kan inte
läsa appen, så du ställer in nivån själv:

```
/fit nivå 12
```

## Kommandon

| Kommando | Vad det gör |
|---|---|
| `/fit` | Visa eller göm rutan |
| `/fit config` | Öppna inställningarna |
| `/fit test <händelse>` | Visa en provnotis. Spärrtid gäller inte och den sparas inte |
| `/fit stats` | Set i dag, i veckan och totalt, plus mest gjorda övningar |
| `/fit export` | Kod att klistra in i webbappen (fas 3) |
| `/fit nivå <1–60>` | Hjältenivån i webbappen |
| `/fit ljud` | Ljud på eller av |
| `/fit ljudlista` | Vilka ljud som finns i spelet |
| `/fit reset` | Visar hur du återställer. `/fit reset ja` återställer inställningar och rutans position, `/fit reset logg ja` tömmer loggen för karaktären |
| `/fit hjälp` | Lista kommandona |

Händelser för `/fit test`: `death`, `ding`, `load`, `taxi`, `boss`, `wipe`,
`loot`, `afk`, `alarm`.

## Inställningar

Öppna med `/fit config` eller **Esc → Options → AddOns → Forever Fitness**.

- **Svårighet:** Lätt, Normal eller Hård (0,6 / 1 / 1,4), samma som i appen.
- **Hjältenivå i appen:** styr antalet reps. Skift-klick på +/− tar tio steg.
- **Raidvarning var:** antal minuter mellan raidvarningarna.
- **Spärrtid:** hur länge samma händelse är spärrad efter en notis.
- **Ljud:** av eller på för alla händelser.
- **Loot från:** lägsta kvalitet som räknas som bra loot.
- **Händelser:** slå av eller på varje händelse, välj övning och ljud.
  Vänsterklick på en knapp byter till nästa, högerklick till föregående.
  **Lyssna** spelar ljudet.

Övningar med * kräver redskap. Byter du övning räknas antalet med faktor 1,
precis som när du byter övning i webbappen.

### Ljud

Varje händelse har ett eget ljud: bossvarning när du dör, "uppdrag klart" vid
level up, episkt loot-ljud vid bossdöd och så vidare. Klienten är ny, så alla
ljud finns kanske inte. Då används ett annat ljud. `/fit ljudlista` visar
vilka som finns.

## Sparad data

- Inställningar sparas per konto (`ForeverFitnessDB`).
- Loggen sparas per karaktär (`ForeverFitnessCharDB`): tid, händelse, övning,
  antal och om setet gjordes eller hoppades över.

## Testa i spelet

1. Logga in och skriv `/fit test death`. En ruta med burpees ska dyka upp, ett
   ljud spelas och en orange text syns mitt på skärmen.
2. Dra rutan någon annanstans, tryck **Klart!** och skriv `/reload`. Kör
   `/fit test ding`. Rutan ska komma tillbaka där du lade den.
3. Strid: gå in i strid med ett monster och skriv `/fit test boss` medan du
   slåss. Ingenting ska synas förrän striden är slut.
4. Kö: skriv `/fit test death` och sedan `/fit test ding`. Tryck **Klart!** på
   den första, då ska den andra dyka upp.
5. Riktiga händelser: ta en flygresa, gå igenom en portal (laddningsskärm),
   skriv `/afk`. Var och en ska ge en notis.
6. Inställningar: `/fit config`. Byt övning för Död, kör `/fit test death`
   och kontrollera att den nya övningen syns. Tryck **Lyssna** på några rader.
7. Statistik: gör ett par set och tryck **Klart!**, kör sedan `/fit stats`.
8. Felsökning: `/fit debug` skriver ut fel i chatten i stället för att tiga.

## Tester utan spelet

Logiken testas i vanlig Lua 5.1 med en låtsas-WoW (`tests/wowmock.lua`). Från
repots rot:

```
lua5.1 addon/tests/run_tests.lua
```

```
cd addon && luacheck .
```

Om `node` finns jämför testerna antalet reps mot webbappens egen `target()`.
