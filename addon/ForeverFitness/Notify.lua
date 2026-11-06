-- Forever Fitness: notiser. Spärrtid, kö, strid och den flyttbara rutan.
-- Regler:
--  * Ingen notis under strid. De köas och visas efter PLAYER_REGEN_ENABLED.
--  * Högst en notis i taget, övriga köas.
--  * Rutan skapas när addonet laddas, aldrig under strid, och använder inga
--    skyddade funktioner, så addonet orsakar ingen taint.
local _, ns = ...

ns.queue = {}
ns.current = nil
ns.lastFire = {}   -- [appens händelse-id] = GetTime() när notisen senast skapades
ns.MAX_QUEUE = 5
ns.SNOOZE = 300    -- "Om 5 min"
ns.MAX_LOG = 5000

function ns.InCombat()
  if InCombatLockdown and InCombatLockdown() then return true end
  return false
end

---------------------------------------------------------------------------
-- Logik
---------------------------------------------------------------------------

-- Skapar en notis för en händelse om den inte är avstängd eller spärrad.
-- opts.force = hoppa över avstängning och spärrtid (används av /fit test).
-- Returnerar true, eller false och en orsak.
function ns.Fire(key, opts)
  opts = opts or {}
  local def = ns.TRIGGERS[key]
  if not def then return false, "okänd" end
  if not opts.force and not ns.TriggerOn(key) then return false, "av" end
  local now = ns.Now()
  local cd = (ns.db and ns.db.cooldown) or ns.DEFAULTS.cooldown
  local last = ns.lastFire[def.ev]
  if not opts.force and last and now - last < cd then return false, "spärrad" end
  ns.lastFire[def.ev] = now
  local ex, f = ns.ExerciseFor(key)
  local item = {
    key = key, ev = def.ev, ex = ex, amt = ns.Amount(ex, f),
    src = def.src or "event", title = def.title, test = opts.force or nil,
  }
  ns.Enqueue(item)
  return true
end

function ns.Enqueue(item, front)
  if front then table.insert(ns.queue, 1, item) else ns.queue[#ns.queue + 1] = item end
  while #ns.queue > ns.MAX_QUEUE do table.remove(ns.queue, 1) end
  ns.Pump()
end

-- Visar nästa notis om ingen visas och vi inte är i strid.
function ns.Pump()
  if ns.current or #ns.queue == 0 or ns.InCombat() then return end
  ns.current = table.remove(ns.queue, 1)
  ns.ShowNotice(ns.current)
end

function ns.Record(item, done)
  if not ns.char then return end
  local log = ns.char.log
  log[#log + 1] = {
    t = ns.Clock(), ev = item.ev, ex = item.ex, amt = item.amt,
    src = item.src, done = done and true or false,
  }
  while #log > ns.MAX_LOG do table.remove(log, 1) end
end

-- result: "done", "snooze" eller "skip"
function ns.Finish(result)
  local item = ns.current
  if not item then return end
  ns.current = nil
  ns.HideNotice()
  if result == "snooze" then
    ns.After(ns.SNOOZE, function() ns.Enqueue(item) end)
  elseif not item.test then
    ns.Record(item, result == "done")
  end
  if result == "done" then
    ns.Print("Bra jobbat! " .. ns.FormatAmount(item.ex, item.amt) .. " " .. ns.EX[item.ex].n:lower() .. ".")
  elseif result == "snooze" then
    ns.Print("Påminner igen om 5 minuter.")
  end
  ns.Pump()
end

-- Strid börjar: göm notisen och lägg den först i kön.
function ns.EnterCombat()
  if ns.current then
    local item = ns.current
    ns.current = nil
    ns.HideNotice()
    table.insert(ns.queue, 1, item)
  end
end

function ns.LeaveCombat()
  -- Liten fördröjning så att man hinner andas efter striden.
  ns.After(1, ns.Pump)
end

---------------------------------------------------------------------------
-- Ljud och raidvarningstext
---------------------------------------------------------------------------
local FALLBACK_SOUND = 8959 -- RAID_WARNING i vanliga WoW

-- Vilket ljud en händelse har: eget val i inställningarna eller standard.
function ns.SoundFor(key)
  local t = ns.db and ns.db.triggers[key]
  local choice = t and t.sound
  if not ns.SOUNDS[choice or ""] then choice = ns.TRIGGER_SOUND[key] or "raid" end
  return choice
end

-- SOUNDKIT-id för ett ljudval. nil = tyst. Saknas alla namn i klienten
-- används reservljudet.
function ns.SoundId(choice)
  local s = ns.SOUNDS[choice]
  if not s or #s.kit == 0 then return nil end
  local kit = type(SOUNDKIT) == "table" and SOUNDKIT or {}
  for _, name in ipairs(s.kit) do
    if type(kit[name]) == "number" then return kit[name], name end
  end
  return FALLBACK_SOUND, nil
end

function ns.PlaySoundChoice(choice)
  if type(PlaySound) ~= "function" then return end
  local id = ns.SoundId(choice)
  if not id then return end
  if not ns.call(PlaySound, id, "Master") and id ~= FALLBACK_SOUND then
    ns.call(PlaySound, FALLBACK_SOUND, "Master")
  end
end

function ns.PlayAlert(key)
  if not (ns.db and ns.db.sound) then return end
  ns.PlaySoundChoice(ns.SoundFor(key))
end

function ns.Announce(text)
  if type(RaidNotice_AddMessage) == "function" and RaidWarningFrame then
    local color = (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.5, b = 0 }
    local ok = pcall(RaidNotice_AddMessage, RaidWarningFrame, text, color)
    if ok then return end
  end
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(text, 1, 0.5, 0)
  else
    ns.Print(text)
  end
end

---------------------------------------------------------------------------
-- Rutan
---------------------------------------------------------------------------
local function savePos(f)
  if not ns.db then return end
  local point, _, relPoint, x, y = f:GetPoint()
  if point then ns.db.pos = { point, relPoint, x, y } end
end

local function button(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(92, 24)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

function ns.PlaceUI(f)
  f = f or ns.ui
  if not f then return end
  f:ClearAllPoints()
  local pos = ns.db and ns.db.pos
  if type(pos) == "table" and pos[1] then
    f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
  end
end

function ns.CreateUI()
  if ns.ui then return ns.ui end
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "ForeverFitnessNotice", UIParent, template)
  f:SetSize(310, 150)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)
  ns.PlaceUI(f)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.06, 0.1, 0.94)
    f:SetBackdropBorderColor(0.56, 0.39, 0.94, 1)
  end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOP", f, "TOP", 0, -12)
  f.amount = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.amount:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
  f.exercise = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.exercise:SetPoint("TOP", f.amount, "BOTTOM", 0, -6)
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.hint:SetPoint("TOP", f.exercise, "BOTTOM", 0, -6)
  f.hint:SetText("Dra i rutan för att flytta den.")

  f.done = button(f, "Klart!", function() ns.Finish("done") end)
  f.done:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
  f.snooze = button(f, "Om 5 min", function() ns.Finish("snooze") end)
  f.snooze:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
  f.skip = button(f, "Hoppa över", function() ns.Finish("skip") end)
  f.skip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)

  f:Hide()
  ns.ui = f
  return f
end

function ns.ShowNotice(item)
  local e = ns.EX[item.ex]
  local amountText = ns.FormatAmount(item.ex, item.amt)
  local f = ns.ui
  if f then
    f.title:SetText(item.title or "Forever Fitness")
    f.amount:SetText(amountText)
    f.exercise:SetText(e.n)
    f:Show()
  end
  ns.PlayAlert(item.key)
  ns.Announce("Forever Fitness: " .. amountText .. " " .. e.n:lower() .. "!")
end

function ns.HideNotice()
  if ns.ui then ns.ui:Hide() end
end

-- /fit visar eller gömmer rutan.
ns.commands[""] = function()
  if ns.ui and ns.ui:IsShown() then
    ns.ui:Hide()
    ns.Print("Rutan är dold. Skriv /fit för att visa den igen.")
  elseif ns.current and ns.ui and not ns.InCombat() then
    ns.ui:Show()
  else
    local n = #ns.queue
    ns.Print(n > 0 and (n .. " övning(ar) i kö, visas efter striden.") or "Inga övningar väntar. Prova /fit test death")
  end
end

table.insert(ns.onLoad, ns.CreateUI)
ns.On("PLAYER_REGEN_DISABLED", ns.EnterCombat)
ns.On("PLAYER_REGEN_ENABLED", ns.LeaveCombat)
