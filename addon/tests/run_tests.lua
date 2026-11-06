-- Kör: lua5.1 addon/tests/run_tests.lua (från repots rot)
-- Testar addonets logik utan spelet, med låtsas-WoW i wowmock.lua.
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local mock = require("wowmock")
local ADDON_DIR = here .. "/../ForeverFitness"
local FILES = { "Data.lua", "Core.lua", "Notify.lua", "Events.lua" }

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

print(string.format("\n%d ok, %d fel", passed, failed))
os.exit(failed == 0 and 0 or 1)
