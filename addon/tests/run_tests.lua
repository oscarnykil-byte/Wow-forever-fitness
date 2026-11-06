-- Kör: lua5.1 addon/tests/run_tests.lua (från repots rot)
-- Testar addonets logik utan spelet, med låtsas-WoW i wowmock.lua.
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local mock = require("wowmock")
local ADDON_DIR = here .. "/../ForeverFitness"
local FILES = { "Data.lua", "Core.lua", "Notify.lua", "Events.lua", "Config.lua", "Export.lua" }

local passed, failed = 0, 0


local function fail(msg, level)
  error({ msg = msg }, (level or 1) + 1)
end
local function eq(a, b, what)
  if a ~= b then fail(string.format("%s: väntade %s, fick %s", what or "värde", tostring(b), tostring(a)), 2) end
end
local function ok(v, what) if not v then fail(what or "väntade sant", 2) end end

local function start()
  mock.reset()
  local ns = mock.load(ADDON_DIR, FILES)
  mock.login()
  return ns
end

local function test(name, fn)

  local okc, err = pcall(fn)
  if okc then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FEL  " .. name .. ": " .. (type(err) == "table" and err.msg or tostring(err)))
  end
end

print("Forever Fitness – tester")

---------------------------------------------------------------------------
-- Antal reps
---------------------------------------------------------------------------
test("target() ger samma antal som webbappen", function()
  local ns = start()
  local p = io.popen("node " .. here .. "/target_expected.js 2>/dev/null")
  local data = p and p:read("*a") or ""
  if p then p:close() end
  if data == "" then
    print("       (node saknas, jämför mot inbyggda värden i stället)")
    eq(ns.Target("burpee", 0.6, "normal", 1), 5, "burpees död nivå 1")
    eq(ns.Target("squat", 1, "normal", 1), 15, "knäböj nivå 1")
    eq(ns.Target("plank", 1, "hard", 60), 65, "planka hård nivå 60")
    return
  end
  local n = 0
  for line in data:gmatch("[^\n]+") do
    local id, d, L, f, want = line:match("^(%S+) (%S+) (%S+) (%S+) ?(%S*)$")
    if id == "event" then
      -- d = appens händelse-id, L = övning, f = faktor
      local found = false
      for _, t in pairs(ns.TRIGGERS) do
        if t.ev == d then found = true; eq(t.ex, L, "övning för " .. d); eq(t.f, tonumber(f), "faktor för " .. d) end
      end
      if d ~= "queue" and d ~= "walk" then ok(found, "händelsen " .. d .. " saknas i addonet") end
    else
      ok(ns.EX[id], "övningen " .. id .. " saknas i addonet")
      eq(ns.Target(id, tonumber(f), d, tonumber(L)), tonumber(want), string.format("%s %s nivå %s f=%s", id, d, L, f))
      n = n + 1
    end
  end
  ok(n > 100, "för få fall från webbappen")
end)

test("antal följer svårighet och hjältenivå i inställningarna", function()
  local ns = start()
  ns.db.diff = "easy"; ns.db.heroLevel = 20
  ns.Fire("death")
  eq(ns.current.amt, ns.Target("burpee", 0.6, "easy", 20), "antal")
  eq(ns.ui.amount:GetText(), ns.current.amt .. " st", "text i rutan")
end)

test("egen övning för en händelse ger faktor 1, som i appen", function()
  local ns = start()
  ns.db.triggers.death.ex = "squat"
  ns.Fire("death")
  eq(ns.current.ex, "squat", "övning")
  eq(ns.current.amt, ns.Target("squat", 1, "normal", 1), "antal")
end)

---------------------------------------------------------------------------
-- Spärrtid och kö
---------------------------------------------------------------------------
test("tre dödsfall i rad ger en notis", function()
  local ns = start()
  mock.fire("PLAYER_DEAD"); mock.fire("PLAYER_DEAD"); mock.fire("PLAYER_DEAD")
  ok(ns.current, "ingen notis")
  eq(#ns.queue, 0, "köade notiser")
end)

test("spärrtiden släpper efter 2 minuter", function()
  local ns = start()
  mock.fire("PLAYER_DEAD")
  ns.Finish("done")
  mock.advance(60); mock.fire("PLAYER_DEAD")
  eq(ns.current, nil, "notis inom spärrtiden")
  mock.advance(61); mock.fire("PLAYER_DEAD")
  ok(ns.current, "ingen notis efter spärrtiden")
end)

test("laddningsskärm och flygresa delar spärrtid", function()
  local ns = start()
  mock.fire("LOADING_SCREEN_DISABLED")
  ok(ns.current and ns.current.key == "load", "laddningsskärm")
  mock.taxi = true; mock.advance(3)
  eq(#ns.queue, 0, "flygresan skulle vara spärrad")
end)

test("högst en notis i taget, övriga köas", function()
  local ns = start()
  mock.fire("PLAYER_DEAD"); mock.fire("PLAYER_LEVEL_UP")
  eq(ns.current.key, "death", "först")
  eq(#ns.queue, 1, "kö")
  ns.ui.done:Click()
  eq(ns.current.key, "ding", "nästa")
  eq(#ns.char.log, 1, "logg")
  eq(ns.char.log[1].done, true, "gjord")
  ns.ui.skip:Click()
  eq(ns.char.log[2].done, false, "hoppad")
  eq(ns.char.log[2].ex, "pushup", "övning i loggen")
  eq(ns.ui:IsShown(), false, "rutan stängd")
end)

test("kön har ett tak", function()
  local ns = start()
  ns.db.cooldown = 0
  for _ = 1, 12 do ns.Fire("death") end
  eq(#ns.queue, ns.MAX_QUEUE, "kölängd")
end)

test("Om 5 min visar notisen igen efter 5 minuter", function()
  local ns = start()
  mock.fire("PLAYER_DEAD")
  ns.ui.snooze:Click()
  eq(ns.current, nil, "dold")
  eq(#ns.char.log, 0, "inget loggat")
  mock.advance(299)
  eq(ns.current, nil, "för tidigt")
  mock.advance(2)
  ok(ns.current and ns.current.key == "death", "tillbaka")
end)

---------------------------------------------------------------------------
-- Strid
---------------------------------------------------------------------------
test("ingen notis under strid, visas efter striden", function()
  local ns = start()
  mock.combat = true; mock.fire("PLAYER_REGEN_DISABLED")
  mock.fire("PLAYER_DEAD")
  eq(ns.current, nil, "notis under strid")
  eq(ns.ui:IsShown(), false, "rutan syns under strid")
  eq(#mock.sounds, 0, "ljud under strid")
  mock.combat = false; mock.fire("PLAYER_REGEN_ENABLED")
  mock.advance(1.5)
  ok(ns.current and ns.current.key == "death", "notis efter strid")
  eq(ns.ui:IsShown(), true, "rutan syns")
end)

test("notis som visas göms när striden börjar och kommer tillbaka", function()
  local ns = start()
  mock.fire("PLAYER_LEVEL_UP")
  ok(ns.ui:IsShown(), "visas")
  mock.combat = true; mock.fire("PLAYER_REGEN_DISABLED")
  eq(ns.ui:IsShown(), false, "göms")
  eq(ns.queue[1].key, "ding", "först i kön")
  mock.combat = false; mock.fire("PLAYER_REGEN_ENABLED"); mock.advance(1.5)
  eq(ns.current.key, "ding", "tillbaka")
end)

test("inga ramar skapas efter inloggning", function()
  local ns = start()
  local before = #mock.frames
  mock.combat = true
  ns.Fire("death"); mock.combat = false; mock.fire("PLAYER_REGEN_ENABLED"); mock.advance(2)
  ns.Finish("done"); ns.Fire("ding")
  eq(#mock.frames, before, "antal ramar")
end)

---------------------------------------------------------------------------
-- Händelser
---------------------------------------------------------------------------
test("första laddningsskärmen (inloggning) räknas inte", function()
  local ns = start()
  eq(ns.current, nil, "notis vid inloggning")
  mock.fire("LOADING_SCREEN_DISABLED")
  ok(ns.current and ns.current.key == "load", "andra laddningsskärmen")
  eq(ns.current.ex, "squat", "knäböj")
end)

test("flygresa när UnitOnTaxi blir sant", function()
  local ns = start()
  mock.advance(3)
  eq(ns.current, nil, "ingen notis på marken")
  mock.taxi = true; mock.advance(3)
  ok(ns.current and ns.current.key == "taxi", "flygresa")
end)

test("inloggning mitt i en flygresa räknas inte", function()
  mock.reset()
  mock.taxi = true
  local ns = mock.load(ADDON_DIR, FILES)
  mock.login(); mock.advance(5)
  eq(ns.current, nil, "notis")
end)

test("AFK när UnitIsAFK blir sant", function()
  local ns = start()
  mock.afk = true; mock.advance(3)
  ok(ns.current and ns.current.ex == "climber", "mountain climbers")
end)

test("boss och wipe via ENCOUNTER_END", function()
  local ns = start()
  mock.fire("ENCOUNTER_END", 1, "Ragnaros", 9, 40, 1)
  eq(ns.current.key, "boss", "boss")
  eq(ns.current.ex, "lunge", "utfall")
  mock.fire("ENCOUNTER_END", 1, "Ragnaros", 9, 40, 0)
  eq(ns.queue[1].key, "wipe", "wipe")
  eq(ns.queue[1].ex, "plank", "planka")
end)

test("BOSS_KILL används om ENCOUNTER_END saknas", function()
  mock.reset()
  mock.unknownEvents.ENCOUNTER_END = true
  local ns = mock.load(ADDON_DIR, FILES)
  mock.login()
  eq(ns.hasEncounterEnd, false, "ENCOUNTER_END")
  mock.fire("BOSS_KILL", 1, "Onyxia")
  ok(ns.current and ns.current.key == "boss", "boss")
end)

test("okända händelser ger inga fel", function()
  mock.reset()
  mock.unknownEvents.LOADING_SCREEN_DISABLED = true
  mock.unknownEvents.CHAT_MSG_LOOT = true
  local ns = mock.load(ADDON_DIR, FILES)
  mock.login()
  mock.fire("PLAYER_DEAD")
  ok(ns.current, "död fungerar ändå")
end)

test("eget loot av kvalitet sällsynt eller bättre", function()
  local ns = start()
  mock.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:2:0|h[Grön sak]|h|r.")
  eq(ns.current, nil, "grönt räknas inte")
  mock.fire("CHAT_MSG_LOOT", "Bob receives loot: |cffa335ee|Hitem:3:0|h[Bobs sak]|h|r.")
  eq(ns.current, nil, "någon annans loot")
  mock.fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:1:0|h[Blått svärd]|h|r.")
  ok(ns.current and ns.current.ex == "jacks", "blått räknas")
end)

test("loot med antal och nytt färgformat", function()
  local ns = start()
  eq(ns.ParseSelfLoot("You receive loot: |cffa335ee|Hitem:9|h[X]|h|rx2."), "|cffa335ee|Hitem:9|h[X]|h|r", "antal")
  eq(ns.LinkQuality("|cnIQ4:|Hitem:9|h[X]|h|r"), 4, "|cnIQ-format")
  eq(ns.LinkQuality("|cffff8000|Hitem:9|h[X]|h|r"), 5, "legendarisk")
end)

test("lokaliserade lootmeddelanden", function()
  local ns = start()
  local p = ns.FormatToPattern("Du får byte: %s.")
  eq(("Du får byte: [A]."):match(p), "[A]", "svenska")
  p = ns.FormatToPattern("Vous recevez le butin : %1$s.")
  eq(("Vous recevez le butin : [B]."):match(p), "[B]", "positionsformat")
end)

test("hemliga värden ignoreras", function()
  local ns = start()
  _G.issecretvalue = function() return true end
  mock.fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:1:0|h[Blått]|h|r.")
  mock.fire("ENCOUNTER_END", 1, "X", 1, 5, 1)
  eq(ns.current, nil, "notis från hemligt värde")
end)

test("raidvarning var 30:e minut med övning utan redskap", function()
  local ns = start()
  mock.advance(29 * 60)
  eq(ns.current, nil, "för tidigt")
  mock.advance(61)
  ok(ns.current and ns.current.key == "alarm", "raidvarning")
  eq(ns.current.src, "alarm", "källa")
  eq(ns.EX[ns.current.ex].eq, nil, "övning utan redskap")
end)

---------------------------------------------------------------------------
-- Inställningar, ljud och kommandon
---------------------------------------------------------------------------
test("avstängd händelse ger ingen notis", function()
  local ns = start()
  ns.db.triggers.death.on = false
  mock.fire("PLAYER_DEAD")
  eq(ns.current, nil, "notis")
end)

test("ljud och raidvarningstext, ljud går att stänga av", function()
  local ns = start()
  mock.fire("PLAYER_DEAD")
  eq(mock.sounds[1], 8959, "ljud")
  ok(mock.warnings[1] and mock.warnings[1]:find("burpees"), "raidvarningstext")
  ns.Finish("skip")
  ns.Slash("ljud")
  mock.fire("PLAYER_LEVEL_UP")
  eq(#mock.sounds, 1, "ljud trots avstängt")
end)

test("reservljud om SOUNDKIT saknas", function()
  local ns = start()
  _G.SOUNDKIT = nil
  ns.Fire("death")
  eq(mock.sounds[1], 8959, "reservljud")
end)

test("/fit test visar notis trots spärrtid och loggas inte", function()
  local ns = start()
  mock.fire("PLAYER_DEAD"); ns.Finish("done")
  _G.SlashCmdList.FOREVERFITNESS("test death")
  ok(ns.current and ns.current.key == "death", "testnotis")
  ns.Finish("done")
  eq(#ns.char.log, 1, "testet loggades")
end)

test("/fit nivå ändrar hjältenivån", function()
  local ns = start()
  ns.Slash("nivå 25")
  eq(ns.db.heroLevel, 25, "nivå")
  ns.Slash("niva 99")
  eq(ns.db.heroLevel, 25, "ogiltig nivå")
end)

test("rutans position sparas", function()
  local ns = start()
  ns.ui.scripts.OnDragStop(ns.ui)
  eq(ns.db.pos[1], "CENTER", "punkt")
  eq(ns.db.pos[3], 12, "x")
end)

---------------------------------------------------------------------------
-- Fas 2: ljud, statistik, inställningar
---------------------------------------------------------------------------
local function findButton(prefix)
  for _, f in ipairs(mock.frames) do
    if f.kind == "Button" and type(f.text) == "string" and f.text:sub(1, #prefix) == prefix then return f end
  end
end

test("olika ljud per händelse", function()
  local ns = start()
  _G.SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960, IG_QUEST_LIST_COMPLETE = 618, UI_EPICLOOT_TOAST = 31578 }
  ns.Fire("ding"); ns.Finish("done")
  ns.Fire("boss"); ns.Finish("done")
  ns.Fire("load"); ns.Finish("done")
  eq(mock.sounds[1], 618, "level up")
  eq(mock.sounds[2], 31578, "boss")
  eq(mock.sounds[3], 8960, "laddningsskärm")
end)

test("ljud som saknas ger reservljud, tyst ger inget", function()
  local ns = start()
  _G.SOUNDKIT = {}
  ns.Fire("ding"); ns.Finish("done")
  eq(mock.sounds[1], 8959, "reservljud")
  ns.db.triggers.death.sound = "none"
  ns.Fire("death")
  eq(#mock.sounds, 1, "tyst händelse spelade ljud")
end)

test("veckan börjar på måndag", function()
  local ns = start()
  local thu = os.time({ year = 2026, month = 11, day = 5, hour = 0, min = 30 })
  local sun = os.time({ year = 2026, month = 11, day = 8, hour = 23, min = 59 })
  local mon = os.time({ year = 2026, month = 11, day = 2, hour = 0, min = 1 })
  eq(ns.WeekStartKey(thu), "2026-11-02", "torsdag")
  eq(ns.WeekStartKey(sun), "2026-11-02", "söndag")
  eq(ns.WeekStartKey(mon), "2026-11-02", "måndag")
end)

test("statistik: i dag, i veckan, totalt och mest gjorda", function()
  local ns = start()
  local now = os.time({ year = 2026, month = 11, day = 5, hour = 20 })
  local day = 86400
  local log = {
    { t = now - 60, ex = "burpee", amt = 5, done = true },
    { t = now - 120, ex = "burpee", amt = 6, done = true },
    { t = now - 2 * day, ex = "squat", amt = 15, done = true },   -- tisdag samma vecka
    { t = now - 5 * day, ex = "plank", amt = 30, done = true },   -- förra veckan
    { t = now - 30, ex = "jacks", amt = 25, done = false },
  }
  local s = ns.Stats(log, now)
  eq(s.today, 2, "i dag"); eq(s.week, 3, "i veckan"); eq(s.total, 4, "totalt"); eq(s.skipped, 1, "hoppade")
  eq(s.top[1].ex, "burpee", "mest gjord"); eq(s.top[1].amt, 11, "summa")
end)

test("/fit stats skriver ut statistik", function()
  local ns = start()
  mock.fire("PLAYER_DEAD"); ns.Finish("done")
  mock.chat = {}
  ns.Slash("stats")
  ok(mock.chat[1]:find("i dag: 1"), "rad 1: " .. tostring(mock.chat[1]))
  ok(mock.chat[3] and mock.chat[3]:find("Burpees: 1 set"), "mest gjorda")
end)

test("inställningspanelen byggs och ändrar inställningarna", function()
  local ns = start()
  ok(ns.panel, "panel")
  ns.RefreshPanel()
  local b = findButton("Svårighet:")
  ok(b, "svårighetsknapp")
  eq(b.text, "Svårighet: Normal", "text")
  b.scripts.OnClick(b, "LeftButton")
  eq(ns.db.diff, "hard", "nästa")
  b.scripts.OnClick(b, "RightButton"); b.scripts.OnClick(b, "RightButton")
  eq(ns.db.diff, "easy", "bakåt")
  local ex = findButton("Burpees")
  ok(ex, "övningsknapp för död")
  ex.scripts.OnClick(ex, "LeftButton")
  eq(ns.db.triggers.death.ex, "climber", "ny övning")
  ns.Fire("death")
  eq(ns.current.ex, "climber", "notisen följer valet")
end)

test("ändrat intervall startar om raidvarningen", function()
  local ns = start()
  ns.db.alarmMin = 5; ns.StartAlarm()
  mock.advance(5 * 60 + 1)
  ok(ns.current and ns.current.key == "alarm", "raidvarning efter 5 min")
end)

test("/fit config öppnar inte under strid", function()
  local ns = start()
  mock.combat = true
  ns.panel.shown = false
  ns.Slash("config")
  eq(ns.panel.shown, false, "öppnades under strid")
  mock.combat = false
  ns.Slash("config")
  eq(ns.panel.shown, true, "öppnades inte")
end)

test("Settings-API:t används om det finns", function()
  mock.reset()
  local registered = {}
  _G.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name, GetID = function() return 42 end } end,
    RegisterAddOnCategory = function(cat) registered[#registered + 1] = cat end,
    OpenToCategory = function(id) registered.opened = id end,
  }
  local ns = mock.load(ADDON_DIR, FILES)
  mock.login()
  eq(registered[1].name, "Forever Fitness", "registrerad")
  ns.Slash("config")
  eq(registered.opened, 42, "öppnad")
  _G.Settings = nil
end)

test("/fit reset ja återställer men behåller loggen", function()
  local ns = start()
  ns.db.diff = "hard"; ns.db.pos = { "LEFT", "LEFT", 1, 2 }; ns.db.triggers.death.on = false
  mock.fire("PLAYER_LEVEL_UP"); ns.Finish("done")
  ns.Slash("reset")
  eq(ns.db.diff, "hard", "återställt utan ja")
  ns.Slash("reset ja")
  eq(ns.db.diff, "normal", "svårighet"); eq(ns.db.pos, nil, "position"); eq(ns.db.triggers.death.on, true, "död på")
  eq(#ns.char.log, 1, "loggen finns kvar")
  ns.Slash("reset logg ja")
  eq(#ns.char.log, 0, "loggen tömd")
end)

test("/fit ljudlista och /fit hjälp ger inga fel", function()
  local ns = start()
  mock.chat = {}
  ns.Slash("ljudlista"); ns.Slash("hjälp"); ns.Slash("okänt")
  ok(#mock.chat > 10, "inga rader")
end)

test("inställningar sparas per konto, logg per karaktär", function()
  local ns = start()
  ns.db.diff = "easy"
  mock.fire("PLAYER_DEAD"); ns.Finish("done")
  eq(_G.ForeverFitnessDB.diff, "easy", "konto")
  eq(#_G.ForeverFitnessCharDB.log, 1, "karaktär")
  local e = _G.ForeverFitnessCharDB.log[1]
  ok(e.t and e.ev == "death" and e.ex == "burpee" and e.amt == ns.Target("burpee", 0.6, "easy", 1) and e.done == true, "loggpost")
end)

---------------------------------------------------------------------------
-- Fas 3: export
---------------------------------------------------------------------------
test("base64 enligt standarden", function()
  local ns = start()
  local cases = { [""] = "", f = "Zg==", fo = "Zm8=", foo = "Zm9v", foob = "Zm9vYg==", foobar = "Zm9vYmFy", ["å"] = "w6U=" }
  for plain, b64 in pairs(cases) do
    eq(ns.Base64Encode(plain), b64, "kodning av " .. plain)
    eq(ns.Base64Decode(b64), plain, "avkodning av " .. b64)
  end
  local all = {}
  for i = 0, 255 do all[#all + 1] = string.char(i) end
  all = table.concat(all)
  eq(ns.Base64Decode(ns.Base64Encode(all)), all, "alla bytes")
end)

test("JSON fram och tillbaka", function()
  local ns = start()
  local v = { a = 1, b = "Ollon \"Slayer\" på\n60", c = { 1, 2.5, -3 }, d = true, e = false, f = {} }
  local j = ns.JSONEncode(v)
  eq(j, '{"a":1,"b":"Ollon \\"Slayer\\" på\\n60","c":[1,2.5,-3],"d":true,"e":false,"f":[]}', "text")
  local back = ns.JSONDecode(j)
  eq(back.b, v.b, "sträng"); eq(back.c[2], 2.5, "decimaltal"); eq(back.d, true, "sant"); eq(back.e, false, "falskt")
end)

local function doSets(ns, n)
  ns.db.cooldown = 0
  for i = 1, n do
    ns.Fire(i % 2 == 0 and "death" or "ding")
    ns.Finish(i == 3 and "skip" or "done")
    mock.clock = mock.clock + 60
  end
end

test("export har bara avklarade set och rätt innehåll", function()
  local ns = start()
  doSets(ns, 4) -- set 3 hoppas över
  local code, n = ns.BuildExport()
  eq(code:sub(1, 5), "WFFA-", "prefix")
  eq(n, 3, "antal set")
  local o = ns.ParseExport(code)
  eq(o.v, 1, "version"); eq(o.c, "Ollon-Gillestugan", "karaktär")
  ok(type(o.id) == "string" and #o.id > 10, "exportid")
  eq(o.sets[1].ex, "pushup", "övning"); eq(o.sets[1].ev, "ding", "händelse")
  eq(o.sets[2].ex, "burpee", "övning 2"); eq(o.sets[2].amt, 5, "antal")
  eq(o.sets[3].u, 4, "löpnummer")
  ok(o.sets[1].t < o.sets[2].t, "tid")
end)

test("/fit export tar bara nya set, igen och allt fungerar", function()
  local ns = start()
  doSets(ns, 2)
  ns.Slash("export")
  ok(ns.exportUI:IsShown(), "rutan visas")
  local first = ns.exportUI.code
  eq(#ns.ParseExport(first).sets, 2, "första exporten")
  mock.chat = {}
  ns.Slash("export")
  ok(mock.chat[1]:find("Inga nya"), "ingen ny export")
  ns.Slash("export igen")
  eq(ns.exportUI.code, first, "samma kod igen")
  doSets(ns, 1)
  ns.Slash("export")
  local o = ns.ParseExport(ns.exportUI.code)
  eq(#o.sets, 1, "bara det nya setet"); eq(o.sets[1].u, 3, "rätt set")
  ns.Slash("export allt")
  eq(#ns.ParseExport(ns.exportUI.code).sets, 3, "alla set")
end)

test("långa exporter delas upp", function()
  local ns = start()
  for i = 1, ns.EXPORT_MAX + 5 do
    ns.char.log[#ns.char.log + 1] = { t = 1762300000 + i, ev = "death", ex = "burpee", amt = 5, src = "event", done = true }
  end
  local code, n, more = ns.BuildExport()
  ok(code, "kod"); eq(n, ns.EXPORT_MAX, "första delen"); eq(more, true, "fler kvar")
  ns.Slash("export")
  ns.Slash("export")
  eq(#ns.ParseExport(ns.exportUI.code).sets, 5, "resten")
end)

test("webbappen kan läsa koden (samma avkodning som appen)", function()
  local ns = start()
  _G.UnitName = function() return "Åsa" end
  doSets(ns, 2)
  local code = ns.BuildExport()
  local js = "const b64d=s=>JSON.parse(decodeURIComponent(escape(atob(s))));" ..
    "const o=b64d(process.argv[1].slice(5));process.stdout.write(o.c+'|'+o.sets.length+'|'+o.sets[1].ex)"
  local p = io.popen("node -e \"" .. js .. "\" '" .. code .. "' 2>&1")
  local out = p and p:read("*a") or ""
  if p then p:close() end
  if out == "" then print("       (node saknas, hoppar över)") return end
  eq(out, "Åsa-Gillestugan|2|burpee", "avkodat i node")
end)

print(string.format("\n%d ok, %d fel", passed, failed))
os.exit(failed == 0 and 0 or 1)
