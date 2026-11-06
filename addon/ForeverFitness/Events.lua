-- Forever Fitness: upptäcker händelser i spelet och skapar notiser.
-- Varje API kontrolleras innan det används. Klienten är ny, så det som
-- saknas hoppas över i stället för att ge fel.
local _, ns = ...

local POLL = 2 -- sekunder mellan kontroller av flygresa och AFK

-- I nya klienter kan vissa värden vara "hemliga" och går inte att läsa.
local function readable(v)
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if ok and secret then return false end
  end
  return true
end

---------------------------------------------------------------------------
-- Död, level up och laddningsskärm
---------------------------------------------------------------------------
ns.On("PLAYER_DEAD", function() ns.Fire("death") end)
ns.On("PLAYER_LEVEL_UP", function() ns.Fire("ding") end)

-- Den första laddningsskärmen är inloggningen eller /reload. Den räknas inte.
ns.skipLoad = true
ns.On("LOADING_SCREEN_DISABLED", function()
  if ns.skipLoad then ns.skipLoad = false return end
  ns.Fire("load")
end)

---------------------------------------------------------------------------
-- Boss och wipe
---------------------------------------------------------------------------
function ns.OnEncounterEnd(_, _, _, _, success)
  if not readable(success) then return end
  if success == 1 or success == true then ns.Fire("boss") else ns.Fire("wipe") end
end

ns.hasEncounterEnd = ns.On("ENCOUNTER_END", ns.OnEncounterEnd)
if not ns.hasEncounterEnd then
  ns.On("BOSS_KILL", function() ns.Fire("boss") end)
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------
-- Gör om en formatsträng som "You receive loot: %s." till ett Lua-mönster.
function ns.FormatToPattern(fmt)
  local p = fmt:gsub("%%%d%$s", "%%s"):gsub("%%%d%$d", "%%d")
  p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end

local function lootPatterns()
  if ns.lootPats then return ns.lootPats end
  local list = {}
  -- Den med antal först, annars fångar "%s" även "x2".
  local fmts = {
    LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.",
    LOOT_ITEM_SELF or "You receive loot: %s.",
  }
  for _, f in ipairs(fmts) do
    if type(f) == "string" then list[#list + 1] = ns.FormatToPattern(f) end
  end
  ns.lootPats = list
  return list
end

local HEX_QUALITY = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
  ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}

-- Kvaliteten läses från länkens färg. Om det inte går frågas spelet.
function ns.LinkQuality(link)
  local q = link:match("|cnIQ(%d+):")
  if q then return tonumber(q) end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  if hex and HEX_QUALITY[hex:lower()] then return HEX_QUALITY[hex:lower()] end
  if C_Item and C_Item.GetItemQualityByID then
    local r = ns.call(C_Item.GetItemQualityByID, link)
    if r then return r end
  end
  if type(GetItemInfo) == "function" then
    local _, _, r = ns.call(GetItemInfo, link)
    if r then return r end
  end
  return nil
end

-- Returnerar länken om meddelandet gäller eget loot, annars nil.
function ns.ParseSelfLoot(msg)
  if type(msg) ~= "string" then return nil end
  for _, p in ipairs(lootPatterns()) do
    local link = msg:match(p)
    if link then return link end
  end
  return nil
end

function ns.OnLoot(msg)
  if not readable(msg) then return end
  local link = ns.ParseSelfLoot(msg)
  if not link then return end
  local q = ns.LinkQuality(link)
  local min = (ns.db and ns.db.minQuality) or ns.DEFAULTS.minQuality
  if q and q >= min then ns.Fire("loot") end
end
ns.On("CHAT_MSG_LOOT", ns.OnLoot)

---------------------------------------------------------------------------
-- Flygresa och AFK: kontrolleras var 2:a sekund, notis när läget slår om.
---------------------------------------------------------------------------
local function flag(fnName)
  local fn = _G[fnName]
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, "player")
  if not ok or not readable(v) then return nil end
  return v and true or false
end

ns.state = { taxi = nil, afk = nil }

function ns.Poll()
  local taxi = flag("UnitOnTaxi")
  if taxi ~= nil then
    if taxi and ns.state.taxi == false then ns.Fire("taxi") end
    ns.state.taxi = taxi
  end
  local afk = flag("UnitIsAFK")
  if afk ~= nil then
    if afk and ns.state.afk == false then ns.Fire("afk") end
    ns.state.afk = afk
  end
end

---------------------------------------------------------------------------
-- Raidvarning var N:e minut medan man är inloggad
---------------------------------------------------------------------------
function ns.StartAlarm()
  ns.Cancel(ns.alarmTimer)
  local min = tonumber(ns.db and ns.db.alarmMin) or ns.DEFAULTS.alarmMin
  if min < 1 then min = 1 end
  ns.alarmTimer = ns.Every(min * 60, function() ns.Fire("alarm") end)
end

table.insert(ns.onLogin, function()
  -- Läs av nuvarande läge först, så att inloggning på en flygresa inte räknas.
  ns.state.taxi = flag("UnitOnTaxi")
  ns.state.afk = flag("UnitIsAFK")
  ns.Cancel(ns.pollTimer)
  ns.pollTimer = ns.Every(POLL, ns.Poll)
  ns.StartAlarm()
end)
