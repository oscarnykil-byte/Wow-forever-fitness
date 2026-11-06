-- Forever Fitness: export till webbappen.
-- Koden är "WFFA-" + base64(JSON). Addons kan inte prata med internet, så
-- koden kopieras för hand och klistras in under Hjälte → Inställningar.
--
-- JSON-format (v = 1):
--   { "v":1, "id":"<unik exportid>", "c":"<karaktär-realm>",
--     "sets":[ { "u":<löpnummer>, "t":<unix-sekunder>, "ex":"<övnings-id>",
--               "amt":<antal>, "ev":"<händelse-id>", "src":"event"|"alarm" } ] }
-- Löpnumret u gör att appen aldrig räknar samma set två gånger, även om
-- två exporter skulle överlappa.
local _, ns = ...

ns.EXPORT_PREFIX = "WFFA-"
ns.EXPORT_MAX = 400 -- set per kod, så att koden inte blir för lång

---------------------------------------------------------------------------
-- JSON (bara det som behövs: tabeller, strängar, tal och sant/falskt)
---------------------------------------------------------------------------
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESC[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  return n == #t
end

local function encode(v)
  local ty = type(v)
  if ty == "string" then return encString(v) end
  if ty == "boolean" then return v and "true" or "false" end
  if ty == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v % 1 == 0 and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
    return string.format("%.14g", v)
  end
  if ty == "table" then
    local out = {}
    if next(v) == nil then
      return v.__object and "{}" or "[]"
    end
    if isArray(v) then
      for i = 1, #v do out[i] = encode(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do if k ~= "__object" then keys[#keys + 1] = tostring(k) end end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local val = v[k]
      if val == nil then val = v[tonumber(k)] end
      out[#out + 1] = encString(k) .. ":" .. encode(val)
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end
ns.JSONEncode = encode

-- Avkodare, används av testerna för att kontrollera exporten.
function ns.JSONDecode(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
  local val
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = s:sub(pos, pos)
      if c == "" then error("slut på text") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = s:sub(pos + 1, pos + 1)
        local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if n == "u" then
          out[#out + 1] = string.char(tonumber(s:sub(pos + 2, pos + 5), 16) % 256)
          pos = pos + 6
        else
          out[#out + 1] = map[n] or n
          pos = pos + 2
        end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end
  function val()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        ws()
        local k = str()
        ws(); pos = pos + 1 -- :
        t[k] = val()
        ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      local t = {}
      pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
      while true do
        t[#t + 1] = val()
        ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return t end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
    end
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    pos = pos + #num
    return tonumber(num)
  end
  return val()
end

---------------------------------------------------------------------------
-- Base64 i Lua 5.1 (utan bitoperationer)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function ns.Base64Encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
      .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

function ns.Base64Decode(s)
  local map = {}
  for i = 1, 64 do map[B64:sub(i, i)] = i - 1 end
  s = s:gsub("[^%w%+/=]", "")
  local out = {}
  for i = 1, #s, 4 do
    local q = { s:byte(i, i + 3) }
    local v, pad = 0, 0
    for j = 1, 4 do
      local ch = q[j] and string.char(q[j]) or "="
      if ch == "=" then pad = pad + 1; v = v * 64 else v = v * 64 + map[ch] end
    end
    local b1 = math.floor(v / 65536) % 256
    local b2 = math.floor(v / 256) % 256
    local b3 = v % 256
    out[#out + 1] = string.char(b1)
    if pad < 2 then out[#out + 1] = string.char(b2) end
    if pad < 1 then out[#out + 1] = string.char(b3) end
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
function ns.CharKey()
  local name = (type(UnitName) == "function" and ns.call(UnitName, "player")) or "Okänd"
  local realm = (type(GetRealmName) == "function" and ns.call(GetRealmName)) or ""
  if realm ~= "" then return name .. "-" .. realm end
  return name
end

-- Ger varje loggpost ett löpnummer (äldre poster saknar det).
function ns.NumberLog()
  local c = ns.char
  c.seq = c.seq or 0
  for _, e in ipairs(c.log) do
    if not e.u then c.seq = c.seq + 1; e.u = c.seq end
  end
end

-- Bygger en exportkod med avklarade set efter förra exporten.
-- Returnerar kod, antal set och om det finns fler kvar.
function ns.BuildExport(all)
  ns.NumberLog()
  local c = ns.char
  local from = all and 0 or (c.exported or 0)
  local sets, last = {}, from
  local more = false
  for _, e in ipairs(c.log) do
    if e.done and e.u > from then
      if #sets >= ns.EXPORT_MAX then more = true break end
      sets[#sets + 1] = { u = e.u, t = e.t, ex = e.ex, amt = e.amt, ev = e.ev, src = e.src or "event" }
      last = e.u
    end
  end
  if #sets == 0 then return nil, 0, false, last end
  local key = ns.CharKey()
  local payload = {
    v = 1,
    id = string.format("%s:%d:%d-%d", key, ns.Clock(), sets[1].u, last),
    c = key,
    sets = sets,
  }
  return ns.EXPORT_PREFIX .. ns.Base64Encode(encode(payload)), #sets, more, last
end

-- Läser en exportkod (används av testerna).
function ns.ParseExport(code)
  if type(code) ~= "string" or code:sub(1, #ns.EXPORT_PREFIX) ~= ns.EXPORT_PREFIX then return nil end
  return ns.JSONDecode(ns.Base64Decode(code:sub(#ns.EXPORT_PREFIX + 1)))
end

---------------------------------------------------------------------------
-- Exportrutan
---------------------------------------------------------------------------
function ns.CreateExportUI()
  if ns.exportUI then return ns.exportUI end
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "ForeverFitnessExport", UIParent, template)
  f:SetSize(460, 240)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.06, 0.1, 0.96)
    f:SetBackdropBorderColor(0.56, 0.39, 0.94, 1)
  end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOP", f, "TOP", 0, -12)
  f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
  f.info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -32)
  f.info:SetJustifyH("LEFT")

  local scroll = CreateFrame("ScrollFrame", "ForeverFitnessExportScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -70)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  box:SetWidth(400)
  box:SetMaxLetters(0)
  box:SetScript("OnEscapePressed", function() f:Hide() end)
  -- Koden går att markera men inte ändra.
  box:SetScript("OnTextChanged", function(self, user)
    if user and f.code then self:SetText(f.code); self:HighlightText() end
  end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  scroll:SetScrollChild(box)
  f.box = box

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(100, 24)
  close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
  close:SetText("Stäng")
  close:SetScript("OnClick", function() f:Hide() end)
  local sel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sel:SetSize(120, 24)
  sel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
  sel:SetText("Markera allt")
  sel:SetScript("OnClick", function() box:SetFocus(); box:HighlightText() end)

  f:Hide()
  ns.exportUI = f
  return f
end

function ns.ShowExport(code, count, more)
  local f = ns.CreateExportUI()
  f.code = code
  f.title:SetText("Export till webbappen")
  f.info:SetText(string.format(
    "%d set. Tryck Markera allt och sedan Ctrl+C. Klistra in under Hjälte → Inställningar i webbappen.%s",
    count, more and " Det finns fler set: kör /fit export igen efteråt." or ""))
  f.box:SetText(code)
  f:Show()
  f.box:SetFocus()
  f.box:HighlightText()
end

ns.commands.export = function(arg)
  if not ns.char then return end
  arg = (arg or ""):lower()
  if arg == "igen" then
    if ns.char.lastExport then
      ns.ShowExport(ns.char.lastExport.code, ns.char.lastExport.count, false)
    else
      ns.Print("Ingen tidigare export finns.")
    end
    return
  end
  local code, count, more, last = ns.BuildExport(arg == "allt")
  if not code then
    ns.Print("Inga nya avklarade set sedan förra exporten. /fit export igen visar förra koden, /fit export allt tar med alla.")
    return
  end
  ns.char.exported = math.max(ns.char.exported or 0, last)
  ns.char.lastExport = { code = code, count = count }
  ns.ShowExport(code, count, more)
end

table.insert(ns.onLoad, ns.CreateExportUI)
