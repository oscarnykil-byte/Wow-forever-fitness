-- Låtsas-WoW för tester i vanlig Lua 5.1. Inget här körs i spelet.
local M = {}

local function noop() end

local function newObject(kind)
  local o = { kind = kind, scripts = {}, events = {}, shown = true, text = nil, points = {} }
  local methods = {}
  function methods:SetScript(k, fn) self.scripts[k] = fn end
  function methods:GetScript(k) return self.scripts[k] end
  function methods:RegisterEvent(ev)
    if M.unknownEvents[ev] then error("Attempt to register unknown event \"" .. ev .. "\"") end
    self.events[ev] = true
  end
  function methods:UnregisterEvent(ev) self.events[ev] = nil end
  function methods:Show() self.shown = true end
  function methods:Hide() self.shown = false end
  function methods:IsShown() return self.shown end
  function methods:SetText(t) self.text = t end
  function methods:GetText() return self.text end
  function methods:SetPoint(...) self.points = { ... } end
  function methods:ClearAllPoints() self.points = {} end
  function methods:GetPoint()
    local p = self.points
    return p[1], p[2], p[3], p[4], p[5]
  end
  function methods:CreateFontString() return newObject("FontString") end
  function methods:CreateTexture()
    local t = newObject("Texture")
    M.textures = (M.textures or 0) + 1
    return t
  end
  function methods:SetSize(w, h) self.w, self.h = w, h end
  function methods:StartMoving() end
  function methods:StopMovingOrSizing() self.points = { "CENTER", nil, "CENTER", 12, 34 } end
  function methods:Click()
    local fn = self.scripts.OnClick
    if fn then fn(self) end
  end
  return setmetatable(o, { __index = function(_, k) return methods[k] or noop end })
end

function M.reset()
  M.now = 1000
  M.clock = 1762300000
  M.combat = false
  M.taxi = false
  M.afk = false
  M.frames = {}
  M.textures = 0
  M.sounds = {}
  M.warnings = {}
  M.chat = {}
  M.unknownEvents = {}

  _G.GetTime = function() return M.now end
  _G.time = function() return M.clock end
  _G.InCombatLockdown = function() return M.combat end
  _G.UnitOnTaxi = function() return M.taxi end
  _G.UnitIsAFK = function() return M.afk end
  _G.CreateFrame = function(kind)
    local f = newObject(kind)
    f.shown = true
    M.frames[#M.frames + 1] = f
    return f
  end
  _G.UIParent = newObject("Frame")
  _G.BackdropTemplateMixin = {}
  _G.SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960 }
  _G.PlaySound = function(id) M.sounds[#M.sounds + 1] = id; return true end
  _G.RaidWarningFrame = {}
  _G.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
  _G.RaidNotice_AddMessage = function(_, text) M.warnings[#M.warnings + 1] = text end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) M.chat[#M.chat + 1] = t end }
  _G.SlashCmdList = {}
  _G.LOOT_ITEM_SELF = "You receive loot: %s."
  _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
  _G.ForeverFitnessDB = nil
  _G.ForeverFitnessCharDB = nil
  _G.issecretvalue = nil
  _G.UnitName = function() return "Ollon" end
  _G.GetRealmName = function() return "Gillestugan" end
end

-- Läser in addonets filer i samma ordning som .toc-filen.
function M.load(dir, files)
  local ns = {}
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(dir .. "/" .. f))
    chunk("ForeverFitness", ns)
  end
  return ns
end

function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- Låter tiden gå och kör OnUpdate i halvsekunderssteg.
function M.advance(sec)
  local step = 0.5
  local left = sec
  while left > 0 do
    local d = math.min(step, left)
    M.now = M.now + d
    M.clock = M.clock + d
    left = left - d
    for _, f in ipairs(M.frames) do
      if f.scripts.OnUpdate then f.scripts.OnUpdate(f, d) end
    end
  end
end

-- Startar addonet som när man loggar in.
function M.login()
  M.fire("ADDON_LOADED", "ForeverFitness")
  M.fire("PLAYER_LOGIN")
  M.fire("PLAYER_ENTERING_WORLD", true, false)
  M.fire("LOADING_SCREEN_DISABLED")
end

return M
