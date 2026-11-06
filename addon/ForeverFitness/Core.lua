-- Forever Fitness: grund. Inställningar, timer, händelser och kommandon.
-- Addonet visar bara information. Det trycker inga tangenter, klickar inte
-- och flyttar inte karaktären.
local ADDON, ns = ...
ns.ADDON = ADDON or "ForeverFitness"
ns.VERSION = "0.1.0"

local function exists(name) return type(_G[name]) == "function" end
ns.exists = exists

-- Säkert anrop: returnerar nil om funktionen saknas eller felar.
function ns.call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(fn, ...)
  if ok then return a, b, c, d, e end
  return nil
end

function ns.Print(msg)
  local text = "|cffb493ffForever Fitness:|r " .. tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(text)
  elseif print then
    print(text)
  end
end

-- Monoton tid i sekunder (för spärrtid och timer) och väggklocka (för loggen).
function ns.Now() return (GetTime and GetTime()) or os.time() end
function ns.Clock() return (time and time()) or os.time() end

---------------------------------------------------------------------------
-- Inställningar (SavedVariables)
---------------------------------------------------------------------------
ns.DEFAULTS = {
  diff = "normal",
  heroLevel = 1,     -- hjältenivån i webbappen, styr antalet reps
  sound = true,
  cooldown = 120,    -- spärrtid per händelse i sekunder
  alarmMin = 30,     -- raidvarning var N:e minut
  minQuality = 3,    -- 3 = sällsynt (blå), 4 = episk, 5 = legendarisk
  triggers = {},     -- [nyckel] = { on = true/false, ex = "övnings-id" }
  pos = nil,         -- rutans position
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {}; fill(dst[k], v) else dst[k] = v end
    end
  end
end

function ns.InitDB()
  ForeverFitnessDB = type(ForeverFitnessDB) == "table" and ForeverFitnessDB or {}
  ForeverFitnessCharDB = type(ForeverFitnessCharDB) == "table" and ForeverFitnessCharDB or {}
  fill(ForeverFitnessDB, ns.DEFAULTS)
  for _, key in ipairs(ns.TRIGGER_ORDER) do
    local t = ForeverFitnessDB.triggers[key]
    if type(t) ~= "table" then t = {}; ForeverFitnessDB.triggers[key] = t end
    if t.on == nil then t.on = true end
  end
  fill(ForeverFitnessCharDB, { log = {}, exported = 0 })
  ns.db = ForeverFitnessDB
  ns.char = ForeverFitnessCharDB
end

function ns.TriggerOn(key)
  local t = ns.db and ns.db.triggers[key]
  return not t or t.on ~= false
end

-- Vilken övning och faktor en händelse ger. Byter man övning blir faktorn 1,
-- precis som eventsFor() i webbappen.
function ns.ExerciseFor(key)
  local def = ns.TRIGGERS[key]
  if not def then return nil end
  local chosen = ns.db and ns.db.triggers[key] and ns.db.triggers[key].ex
  if chosen and ns.EX[chosen] and chosen ~= def.ex then return chosen, 1 end
  if def.ex then return def.ex, def.f end
  local pool = ns.BodyweightPool()
  return pool[math.random(#pool)], def.f
end

function ns.Amount(exId, f)
  local db = ns.db or ns.DEFAULTS
  return ns.Target(exId, f, db.diff, db.heroLevel)
end

---------------------------------------------------------------------------
-- Timer. Egen schemaläggare som drivs av OnUpdate, så den fungerar även
-- om C_Timer saknas.
---------------------------------------------------------------------------
ns.timers = {}

function ns.After(sec, fn)
  local t = { at = ns.Now() + sec, fn = fn }
  ns.timers[#ns.timers + 1] = t
  return t
end

function ns.Every(sec, fn)
  local t = { at = ns.Now() + sec, fn = fn, every = sec }
  ns.timers[#ns.timers + 1] = t
  return t
end

function ns.Cancel(t) if t then t.dead = true end end

function ns.RunTimers()
  local now = ns.Now()
  local list = ns.timers
  ns.timers = {}
  local due = {}
  for _, t in ipairs(list) do
    if not t.dead then
      if t.at <= now then
        due[#due + 1] = t
        if t.every then t.at = now + t.every; ns.timers[#ns.timers + 1] = t end
      else
        ns.timers[#ns.timers + 1] = t
      end
    end
  end
  for _, t in ipairs(due) do
    local ok, err = pcall(t.fn)
    if not ok and ns.debug then ns.Print("Fel i timer: " .. tostring(err)) end
  end
end

---------------------------------------------------------------------------
-- Händelser
---------------------------------------------------------------------------
ns.handlers = {}
ns.onLoad = {}   -- körs efter ADDON_LOADED, när inställningarna finns
ns.onLogin = {}  -- körs vid PLAYER_LOGIN
ns.frame = CreateFrame("Frame", "ForeverFitnessEventFrame")

-- Registrerar en händelse om klienten känner till den. Returnerar true/false.
function ns.On(event, fn)
  local ok = pcall(ns.frame.RegisterEvent, ns.frame, event)
  if ok then ns.handlers[event] = fn end
  return ok
end

ns.frame:SetScript("OnEvent", function(_, event, ...)
  local fn = ns.handlers[event]
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok and ns.debug then ns.Print("Fel i " .. event .. ": " .. tostring(err)) end
end)

local acc = 0
ns.frame:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + (elapsed or 0)
  if acc < 0.25 then return end
  acc = 0
  ns.RunTimers()
end)

ns.On("ADDON_LOADED", function(name)
  if name ~= ns.ADDON then return end
  ns.InitDB()
  for _, fn in ipairs(ns.onLoad) do fn() end
end)

ns.On("PLAYER_LOGIN", function()
  for _, fn in ipairs(ns.onLogin) do fn() end
end)

---------------------------------------------------------------------------
-- Kommandon
---------------------------------------------------------------------------
ns.commands = {}

local function help()
  ns.Print("Kommandon:")
  ns.Print("/fit test <händelse>  visa en provnotis. Händelser: " .. table.concat(ns.TRIGGER_ORDER, ", "))
  ns.Print("/fit nivå <1-60>  hjältenivån i webbappen (styr antalet reps)")
  ns.Print("/fit ljud  slå på eller av ljudet")
  for _, c in ipairs(ns.commands) do ns.Print(c.help) end
end

ns.commands.test = function(arg)
  local key = (arg or ""):lower()
  if not ns.TRIGGERS[key] then
    ns.Print("Okänd händelse. Välj en av: " .. table.concat(ns.TRIGGER_ORDER, ", "))
    return
  end
  ns.Fire(key, { force = true })
end

local function setLevel(arg)
  local n = tonumber(arg)
  if not n or n < 1 or n > 60 then
    ns.Print("Hjältenivå just nu: " .. ns.db.heroLevel .. ". Skriv till exempel /fit nivå 12")
    return
  end
  ns.db.heroLevel = math.floor(n)
  ns.Print("Hjältenivå satt till " .. ns.db.heroLevel .. ".")
end
ns.commands["nivå"] = setLevel
ns.commands["niva"] = setLevel

ns.commands.ljud = function()
  ns.db.sound = not ns.db.sound
  ns.Print(ns.db.sound and "Ljudet är på." or "Ljudet är av.")
end

ns.commands.hjalp = help
ns.commands["hjälp"] = help
ns.commands.help = help

ns.commands.debug = function()
  ns.debug = not ns.debug
  ns.Print(ns.debug and "Felsökning på." or "Felsökning av.")
end

function ns.Slash(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if not ns.db then ns.InitDB() end
  local fn = ns.commands[cmd]
  if type(fn) == "function" then fn(rest) return end
  if cmd == "" and ns.commands[""] then ns.commands[""](rest) return end
  help()
end

SLASH_FOREVERFITNESS1 = "/fit"
SLASH_FOREVERFITNESS2 = "/foreverfitness"
if type(SlashCmdList) == "table" then
  SlashCmdList.FOREVERFITNESS = ns.Slash
end
