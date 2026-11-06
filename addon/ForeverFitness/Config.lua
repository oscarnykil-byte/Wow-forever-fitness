-- Forever Fitness: inställningspanel, statistik och kommandon.
local _, ns = ...

local DATE = date or (os and os.date)

---------------------------------------------------------------------------
-- Statistik
---------------------------------------------------------------------------
function ns.DayKey(t) return DATE("%Y-%m-%d", t) end

-- Måndagen i samma vecka, som weekStart() i webbappen.
-- Räknar från klockan 12 så att sommartid inte flyttar dagen.
function ns.WeekStartKey(t)
  local d = DATE("*t", t)
  local noon = t - (d.hour * 3600 + d.min * 60 + d.sec) + 12 * 3600
  local back = (d.wday + 5) % 7 -- wday: 1 = söndag
  return ns.DayKey(noon - back * 86400)
end

function ns.Stats(log, now)
  now = now or ns.Clock()
  local today, week = ns.DayKey(now), ns.WeekStartKey(now)
  local s = { today = 0, week = 0, total = 0, skipped = 0, byEx = {}, top = {} }
  for _, e in ipairs(log or {}) do
    if e.done then
      local d = ns.DayKey(e.t)
      s.total = s.total + 1
      if d == today then s.today = s.today + 1 end
      if d >= week and d <= today then s.week = s.week + 1 end
      local b = s.byEx[e.ex]
      if not b then b = { ex = e.ex, sets = 0, amt = 0 }; s.byEx[e.ex] = b; s.top[#s.top + 1] = b end
      b.sets = b.sets + 1
      b.amt = b.amt + (e.amt or 0)
    else
      s.skipped = s.skipped + 1
    end
  end
  table.sort(s.top, function(a, b)
    if a.sets ~= b.sets then return a.sets > b.sets end
    return a.amt > b.amt
  end)
  return s
end

ns.commands.stats = function()
  local s = ns.Stats(ns.char and ns.char.log)
  ns.Print(string.format("Set i dag: %d · i veckan: %d · totalt: %d · hoppade över: %d",
    s.today, s.week, s.total, s.skipped))
  if #s.top == 0 then
    ns.Print("Inga avklarade set än. Tryck Klart! när du har gjort ett.")
    return
  end
  ns.Print("Mest gjorda övningar:")
  for i = 1, math.min(3, #s.top) do
    local b = s.top[i]
    local e = ns.EX[b.ex]
    ns.Print(string.format("%d. %s: %d set (%s)", i, e and e.n or b.ex, b.sets, ns.FormatAmount(b.ex, b.amt)))
  end
end
ns.commands.statistik = ns.commands.stats

---------------------------------------------------------------------------
-- Återställning och ljudlista
---------------------------------------------------------------------------
function ns.ResetSettings()
  for k in pairs(ForeverFitnessDB) do ForeverFitnessDB[k] = nil end
  ns.InitDB()
  ns.PlaceUI()
  if ns.StartAlarm and ns.alarmTimer then ns.StartAlarm() end
  if ns.RefreshPanel then ns.RefreshPanel() end
end

ns.commands.reset = function(arg)
  arg = (arg or ""):lower()
  if arg == "ja" then
    ns.ResetSettings()
    ns.Print("Inställningarna är återställda. Loggen finns kvar.")
  elseif arg == "logg ja" then
    ns.char.log = {}
    ns.char.exported = 0
    ns.Print("Loggen för den här karaktären är tömd.")
  else
    ns.Print("Skriv /fit reset ja för att återställa inställningarna och rutans position. Loggen sparas.")
    ns.Print("Skriv /fit reset logg ja för att tömma loggen för den här karaktären.")
  end
end

ns.commands.ljudlista = function()
  ns.Print("Ljud i spelet:")
  for _, key in ipairs(ns.SOUND_ORDER) do
    local s = ns.SOUNDS[key]
    if #s.kit == 0 then
      ns.Print(s.n .. ": tyst")
    else
      local id, name = ns.SoundId(key)
      ns.Print(s.n .. ": " .. (name and (name .. " (" .. id .. ")") or "saknas, reservljud används"))
    end
  end
end

---------------------------------------------------------------------------
-- Inställningspanel
-- Bara knappar och kryssrutor med vanliga mallar, inga rullgardinsmenyer,
-- så att panelen fungerar oavsett vilken menyversion klienten har.
---------------------------------------------------------------------------
local refreshers = {}
local function onRefresh(fn) refreshers[#refreshers + 1] = fn end

function ns.RefreshPanel()
  for _, fn in ipairs(refreshers) do pcall(fn) end
end

local function label(parent, text, font, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function checkbox(parent, text, x, y, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + 4)
  cb:SetSize(26, 26)
  local fs = cb.Text or cb.text
  if type(fs) ~= "table" then
    fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  end
  fs:SetText(text)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  onRefresh(function() cb:SetChecked(get() and true or false) end)
  return cb
end

-- Knapp som byter värde: vänsterklick nästa, högerklick föregående.
local function cycle(parent, x, y, width, list, nameOf, get, set)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + 2)
  b:SetSize(width, 22)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  local function show() b:SetText(nameOf(get())) end
  b:SetScript("OnClick", function(_, button)
    local cur, idx = get(), 1
    for i, v in ipairs(list) do if v == cur then idx = i end end
    idx = idx + (button == "RightButton" and -1 or 1)
    if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
    set(list[idx])
    show()
  end)
  onRefresh(show)
  return b
end

-- Minus, värde, plus. Skift-klick tar större steg.
local function stepper(parent, text, x, y, step, bigStep, min, max, get, set, fmt)
  label(parent, text, "GameFontNormal", x, y)
  local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  minus:SetSize(24, 22); plus:SetSize(24, 22)
  minus:SetText("-"); plus:SetText("+")
  minus:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 150, y + 4)
  value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  value:SetWidth(70)
  plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
  local function show() value:SetText(fmt(get())) end
  local function change(dir)
    local s = (IsShiftKeyDown and IsShiftKeyDown()) and bigStep or step
    local v = get() + dir * s
    if v < min then v = min elseif v > max then v = max end
    set(v)
    show()
  end
  minus:SetScript("OnClick", function() change(-1) end)
  plus:SetScript("OnClick", function() change(1) end)
  onRefresh(show)
end

local QUALITY = { 3, 4, 5 }
local QUALITY_NAME = { [3] = "Sällsynt (blå)", [4] = "Episk (lila)", [5] = "Legendarisk" }

local function trig(key)
  local t = ns.db.triggers[key]
  if not t then t = { on = true }; ns.db.triggers[key] = t end
  return t
end

function ns.BuildPanel()
  if ns.panel then return ns.panel end
  local p = CreateFrame("Frame", "ForeverFitnessOptions", UIParent)
  p.name = "Forever Fitness"
  p:SetSize(640, 560)
  p:Hide()

  label(p, "Forever Fitness", "GameFontNormalLarge", 16, -16)
  label(p, "Övningar när något händer i spelet. Samma övningar och antal som i webbappen.",
    "GameFontHighlightSmall", 16, -40)

  local y = -72
  cycle(p, 16, y, 150, ns.DIFF_ORDER,
    function(v) return "Svårighet: " .. ns.DIFF[v].n end,
    function() return ns.db.diff end, function(v) ns.db.diff = v end)
  stepper(p, "Hjältenivå i appen", 320, y, 1, 10, 1, 60,
    function() return ns.db.heroLevel end, function(v) ns.db.heroLevel = v end,
    function(v) return tostring(v) end)

  y = y - 32
  stepper(p, "Raidvarning var", 16, y, 5, 15, 5, 180,
    function() return ns.db.alarmMin end,
    function(v) ns.db.alarmMin = v; if ns.alarmTimer then ns.StartAlarm() end end,
    function(v) return v .. " min" end)
  stepper(p, "Spärrtid", 320, y, 30, 60, 0, 1800,
    function() return ns.db.cooldown end, function(v) ns.db.cooldown = v end,
    function(v) return (v % 60 == 0) and (v / 60 .. " min") or (string.format("%.1f min", v / 60)) end)

  y = y - 32
  checkbox(p, "Ljud", 16, y, function() return ns.db.sound end, function(v) ns.db.sound = v end)
  label(p, "Loot från", "GameFontNormal", 320, y)
  cycle(p, 470, y, 140, QUALITY, function(v) return QUALITY_NAME[v] or tostring(v) end,
    function() return ns.db.minQuality end, function(v) ns.db.minQuality = v end)

  y = y - 44
  label(p, "Händelser", "GameFontNormalLarge", 16, y)
  label(p, "Klicka på en knapp för att byta. Högerklick går bakåt.", "GameFontHighlightSmall", 130, y - 4)
  y = y - 26
  label(p, "Övning", "GameFontNormal", 190, y)
  label(p, "Ljud", "GameFontNormal", 400, y)
  y = y - 22

  local exChoices = {}
  for _, id in ipairs(ns.EX_ORDER) do exChoices[#exChoices + 1] = id end

  for _, key in ipairs(ns.TRIGGER_ORDER) do
    local def = ns.TRIGGERS[key]
    checkbox(p, def.n, 16, y, function() return trig(key).on ~= false end,
      function(v) trig(key).on = v end)
    if def.ex then
      cycle(p, 190, y, 200, exChoices,
        function(v) return ns.EX[v].n .. (ns.EX[v].eq and " *" or "") end,
        function() return trig(key).ex or def.ex end,
        function(v) trig(key).ex = (v ~= def.ex) and v or nil end)
    else
      label(p, "Slumpad, utan redskap", "GameFontDisable", 196, y)
    end
    cycle(p, 400, y, 140, ns.SOUND_ORDER,
      function(v) return ns.SOUNDS[v].n end,
      function() return ns.SoundFor(key) end,
      function(v) trig(key).sound = (v ~= ns.TRIGGER_SOUND[key]) and v or nil end)
    local listen = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    listen:SetPoint("TOPLEFT", p, "TOPLEFT", 546, y + 2)
    listen:SetSize(70, 22)
    listen:SetText("Lyssna")
    listen:SetScript("OnClick", function() ns.PlaySoundChoice(ns.SoundFor(key)) end)
    y = y - 28
  end
  label(p, "* kräver redskap. Antalet räknas om med appens formel.", "GameFontHighlightSmall", 16, y - 4)

  p:SetScript("OnShow", ns.RefreshPanel)
  ns.panel = p
  ns.RegisterPanel(p)
  ns.RefreshPanel()
  return p
end

-- Registrerar panelen i spelets inställningar. Finns ingen sådan visas
-- panelen som en egen flyttbar ruta.
function ns.RegisterPanel(p)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, p.name)
    if ok and cat then
      pcall(Settings.RegisterAddOnCategory, cat)
      ns.category = cat
      return "settings"
    end
  end
  if type(InterfaceOptions_AddCategory) == "function" and pcall(InterfaceOptions_AddCategory, p) then
    ns.legacyOptions = true
    return "interface"
  end
  -- Egen ruta
  p:SetParent(UIParent)
  p:SetPoint("CENTER")
  p:SetFrameStrata("DIALOG")
  p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -4)
  if BackdropTemplateMixin and Mixin then Mixin(p, BackdropTemplateMixin) end
  if p.SetBackdrop then
    p:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 } })
  end
  ns.standalonePanel = true
  return "standalone"
end

function ns.OpenConfig()
  if ns.InCombat() then
    ns.Print("Inställningarna går inte att öppna under strid. Försök igen efteråt.")
    return
  end
  local p = ns.BuildPanel()
  if ns.category and Settings and Settings.OpenToCategory then
    local id = (ns.category.GetID and ns.category:GetID()) or ns.category.ID
    if pcall(Settings.OpenToCategory, id) then return end
  end
  if ns.legacyOptions and type(InterfaceOptionsFrame_OpenToCategory) == "function" then
    -- Måste anropas två gånger i gamla klienter för att hamna rätt.
    pcall(InterfaceOptionsFrame_OpenToCategory, p)
    pcall(InterfaceOptionsFrame_OpenToCategory, p)
    return
  end
  p:Show()
end

ns.commands.config = ns.OpenConfig
ns.commands.installningar = ns.OpenConfig
ns.commands["inställningar"] = ns.OpenConfig

table.insert(ns.onLoad, ns.BuildPanel)
