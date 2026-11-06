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
  return ns.EXPORT_PREFIX .. ns.Base64Encode(encode(payload)), #sets, more, last, sets
end

-- Läser en exportkod (används av testerna).
function ns.ParseExport(code)
  if type(code) ~= "string" or code:sub(1, #ns.EXPORT_PREFIX) ~= ns.EXPORT_PREFIX then return nil end
  return ns.JSONDecode(ns.Base64Decode(code:sub(#ns.EXPORT_PREFIX + 1)))
end

---------------------------------------------------------------------------
-- QR-kod: adress till webbappen med koden efter "#i=".
-- Kortare format (v = 2) så att fler set ryms:
--   { "v":2, "id":"<tid>-<första>-<sista>", "c":"<karaktär>", "t":<starttid>,
--     "e":[övnings-id], "k":[händelse-id], "s":[[u, sekunder efter t, e-index, antal, k-index]] }
-- Base64url (- och _ i stället för + och /, utan =) så att adressen fungerar.
---------------------------------------------------------------------------
ns.DEFAULT_APP_URL = "https://oscarnykil-byte.github.io/Wow-forever-fitness/"

function ns.Base64Url(data)
  return (ns.Base64Encode(data):gsub("%+", "-"):gsub("/", "_"):gsub("=", ""))
end

local function compact(sets, key)
  local exIdx, evIdx, ex, ev, rows = {}, {}, {}, {}, {}
  local t0 = sets[1].t
  for _, e in ipairs(sets) do if e.t < t0 then t0 = e.t end end
  for _, e in ipairs(sets) do
    if not exIdx[e.ex] then ex[#ex + 1] = e.ex; exIdx[e.ex] = #ex - 1 end
    local k = e.ev or "event"
    if not evIdx[k] then ev[#ev + 1] = k; evIdx[k] = #ev - 1 end
    rows[#rows + 1] = { e.u, math.floor(e.t - t0 + 0.5), exIdx[e.ex], e.amt, evIdx[k] }
  end
  return {
    v = 2, c = key, t = math.floor(t0),
    id = string.format("%d-%d-%d", ns.Clock(), sets[1].u, sets[#sets].u),
    e = ex, k = ev, s = rows,
  }
end

function ns.QRUrl(sets, key, url)
  return (url or ns.DEFAULT_APP_URL) .. "#i=" .. ns.EXPORT_PREFIX .. ns.Base64Url(encode(compact(sets, key)))
end

-- Delar upp seten på så få QR-koder som möjligt. Returnerar en lista med adresser.
function ns.BuildQRPages(sets, url)
  local key = ns.CharKey()
  local cap = ns.QRCapacity(ns.QR_MAX_VERSION)
  local pages, i = {}, 1
  while i <= #sets do
    local chunk, best = {}, nil
    while i <= #sets do
      chunk[#chunk + 1] = sets[i]
      local u = ns.QRUrl(chunk, key, url)
      if #u > cap then
        chunk[#chunk] = nil
        break
      end
      best = u
      i = i + 1
    end
    if not best then break end -- ett enda set får inte plats (orimligt lång adress)
    pages[#pages + 1] = best
  end
  return pages
end

---------------------------------------------------------------------------
-- Exportrutan: QR-kod överst, textkoden under som reserv.
---------------------------------------------------------------------------
local QR_BOX = 420 -- QR-kodens storlek i punkter, med tyst zon

function ns.CreateExportUI()
  if ns.exportUI then return ns.exportUI end
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "ForeverFitnessExport", UIParent, template)
  f:SetSize(QR_BOX + 40, QR_BOX + 230)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
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
    f:SetBackdropColor(0.05, 0.06, 0.1, 0.97)
    f:SetBackdropBorderColor(0.56, 0.39, 0.94, 1)
  end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOP", f, "TOP", 0, -12)
  f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -30)
  f.info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -30)
  f.info:SetJustifyH("LEFT")

  -- Vit bakgrund för QR-koden. Mörka moduler ritas som svarta rutor ovanpå.
  f.qr = CreateFrame("Frame", nil, f)
  f.qr:SetSize(QR_BOX, QR_BOX)
  f.qr:SetPoint("TOP", f, "TOP", 0, -62)
  f.qr.bg = f.qr:CreateTexture(nil, "BACKGROUND")
  f.qr.bg:SetColorTexture(1, 1, 1, 1)
  f.qr.bg:SetPoint("CENTER")
  f.qr.pool = {}
  f.page = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.page:SetPoint("TOP", f.qr, "BOTTOM", 0, -6)

  f.prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.prev:SetSize(90, 22)
  f.prev:SetPoint("RIGHT", f.page, "LEFT", -10, 0)
  f.prev:SetText("Föregående")
  f.prev:SetScript("OnClick", function() ns.ShowQRPage(f.pageIndex - 1) end)
  f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.next:SetSize(90, 22)
  f.next:SetPoint("LEFT", f.page, "RIGHT", 10, 0)
  f.next:SetText("Nästa")
  f.next:SetScript("OnClick", function() ns.ShowQRPage(f.pageIndex + 1) end)

  f.textLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.textLabel:SetPoint("TOPLEFT", f.qr, "BOTTOMLEFT", 0, -34)
  f.textLabel:SetText("Eller kopiera koden och klistra in den i appen:")

  local scroll = CreateFrame("ScrollFrame", "ForeverFitnessExportScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f.textLabel, "BOTTOMLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 44)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  box:SetWidth(QR_BOX - 20)
  box:SetMaxLetters(0)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
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
  sel:SetSize(140, 24)
  sel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
  sel:SetText("Markera koden")
  sel:SetScript("OnClick", function() box:SetFocus(); box:HighlightText() end)

  f:Hide()
  ns.exportUI = f
  return f
end

-- Ritar en QR-matris. Mörka moduler i samma rad slås ihop till en ruta,
-- så att det blir färre texturer.
function ns.DrawQR(holder, m, size)
  local quiet = 4
  local px = math.max(2, math.floor(QR_BOX / (size + quiet * 2)))
  local full = (size + quiet * 2) * px
  holder.bg:SetSize(full, full)
  local used = 0
  for y = 0, size - 1 do
    local x = 0
    while x < size do
      if m[y][x] then
        local x0 = x
        while x < size and m[y][x] do x = x + 1 end
        used = used + 1
        local t = holder.pool[used]
        if not t then
          t = holder:CreateTexture(nil, "ARTWORK")
          t:SetColorTexture(0, 0, 0, 1)
          holder.pool[used] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", holder.bg, "TOPLEFT", (quiet + x0) * px, -(quiet + y) * px)
        t:SetSize((x - x0) * px, px)
        t:Show()
      else
        x = x + 1
      end
    end
  end
  for i = used + 1, #holder.pool do holder.pool[i]:Hide() end
  holder.used = used
  return used, px
end

function ns.ShowQRPage(i)
  local f = ns.exportUI
  local pages = f and f.pages
  if not pages or #pages == 0 then return end
  if i < 1 then i = 1 elseif i > #pages then i = #pages end
  f.pageIndex = i
  local m, size = ns.QREncode(pages[i])
  if m then ns.DrawQR(f.qr, m, size) end
  f.page:SetText(#pages > 1 and string.format("QR %d av %d", i, #pages) or "")
  if #pages > 1 then f.prev:Show(); f.next:Show() else f.prev:Hide(); f.next:Hide() end
  if f.prev.SetEnabled then f.prev:SetEnabled(i > 1); f.next:SetEnabled(i < #pages) end
end

function ns.ShowExport(code, count, more, pages)
  local f = ns.CreateExportUI()
  f.code = code
  f.pages = pages or {}
  f.title:SetText("Export till webbappen")
  local scan = #f.pages > 1 and "Skanna QR-koderna en i taget med telefonen." or "Skanna QR-koden med telefonen."
  f.info:SetText(string.format("%d set. %s Seten hamnar hos hjälten som är vald i appen.%s",
    count, scan, more and " Det finns fler set: kör /fit export igen efteråt." or ""))
  f.box:SetText(code)
  f:Show()
  ns.ShowQRPage(1)
end

function ns.AppUrl()
  local u = ns.db and ns.db.appUrl
  if type(u) ~= "string" or u == "" then u = ns.DEFAULT_APP_URL end
  return u
end

ns.commands.export = function(arg)
  if not ns.char then return end
  if ns.InCombat() then
    ns.Print("Exporten går inte att visa under strid. Försök igen efteråt.")
    return
  end
  arg = (arg or ""):lower()
  if arg == "igen" then
    local last = ns.char.lastExport
    if last then
      ns.ShowExport(last.code, last.count, false, last.pages)
    else
      ns.Print("Ingen tidigare export finns.")
    end
    return
  end
  local code, count, more, last, sets = ns.BuildExport(arg == "allt")
  if not code then
    ns.Print("Inga nya avklarade set sedan förra exporten. /fit export igen visar förra koden, /fit export allt tar med alla.")
    return
  end
  local pages = ns.BuildQRPages(sets, ns.AppUrl())
  ns.char.exported = math.max(ns.char.exported or 0, last)
  ns.char.lastExport = { code = code, count = count, pages = pages }
  ns.ShowExport(code, count, more, pages)
end

-- /fit adress visar eller ändrar webbappens adress i QR-koden.
ns.commands.adress = function(arg)
  arg = arg or ""
  if arg == "" then
    ns.Print("QR-koden öppnar: " .. ns.AppUrl())
    ns.Print("Ändra med /fit adress https://... eller återställ med /fit adress standard")
    return
  end
  if arg:lower() == "standard" then
    ns.db.appUrl = nil
  elseif arg:match("^https?://") then
    ns.db.appUrl = arg
  else
    ns.Print("Adressen ska börja med https://")
    return
  end
  ns.Print("QR-koden öppnar nu: " .. ns.AppUrl())
end

table.insert(ns.onLoad, ns.CreateExportUI)
