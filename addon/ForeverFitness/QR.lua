-- Forever Fitness: QR-kod i ren Lua 5.1 (inga bitoperationer behövs).
-- Följer ISO/IEC 18004: byte-läge, felkorrigering L, version 1–20.
-- Byggd efter samma uppläggning som Project Nayukis QR-kodbibliotek (MIT).
local _, ns = ...

local floor = math.floor

local function bit(x, i) return floor(x / 2 ^ i) % 2 end

local function bxor(a, b)
  local r, p = 0, 1
  while a > 0 or b > 0 do
    if a % 2 ~= b % 2 then r = r + p end
    a, b, p = floor(a / 2), floor(b / 2), p * 2
  end
  return r
end

-- Galoiskropp GF(256) med polynomet 0x11D.
local EXP, LOG = {}, {}
do
  local x = 1
  for i = 0, 254 do
    EXP[i] = x
    LOG[x] = i
    x = x * 2
    if x >= 256 then x = bxor(x, 0x11D) end
  end
end
local function gmul(a, b)
  if a == 0 or b == 0 then return 0 end
  return EXP[(LOG[a] + LOG[b]) % 255]
end

local function rsDivisor(degree)
  local r = {}
  for i = 1, degree - 1 do r[i] = 0 end
  r[degree] = 1
  local root = 1
  for _ = 1, degree do
    for j = 1, degree do
      r[j] = gmul(r[j], root)
      if j < degree then r[j] = bxor(r[j], r[j + 1]) end
    end
    root = gmul(root, 2)
  end
  return r
end

local function rsRemainder(data, div)
  local n = #div
  local r = {}
  for i = 1, n do r[i] = 0 end
  for _, b in ipairs(data) do
    local factor = bxor(b, table.remove(r, 1))
    r[n] = 0
    for i = 1, n do r[i] = bxor(r[i], gmul(div[i], factor)) end
  end
  return r
end

-- Felkorrigering L: kodord per block och antal block för version 1–20.
local ECC_PER_BLOCK = { 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28 }
local NUM_BLOCKS = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8 }
ns.QR_MAX_VERSION = 20

local function rawModules(v)
  local r = (16 * v + 128) * v + 64
  if v >= 2 then
    local na = floor(v / 7) + 2
    r = r - (25 * na - 10) * na + 55
    if v >= 7 then r = r - 36 end
  end
  return r
end

local function dataCodewords(v)
  return floor(rawModules(v) / 8) - ECC_PER_BLOCK[v] * NUM_BLOCKS[v]
end

-- Största antal byte som ryms i en version.
function ns.QRCapacity(v)
  local countBits = v <= 9 and 8 or 16
  return floor((dataCodewords(v) * 8 - 4 - countBits) / 8)
end

local function alignPositions(v)
  if v == 1 then return {} end
  local na = floor(v / 7) + 2
  local size = v * 4 + 17
  local step = math.ceil((v * 4 + 4) / (na * 2 - 2)) * 2
  local r = { 6 }
  local pos = size - 7
  while #r < na do
    table.insert(r, 2, pos)
    pos = pos - step
  end
  return r
end

local MASKS = {
  [0] = function(x, y) return (x + y) % 2 == 0 end,
  function(_, y) return y % 2 == 0 end,
  function(x) return x % 3 == 0 end,
  function(x, y) return (x + y) % 3 == 0 end,
  function(x, y) return (floor(x / 3) + floor(y / 2)) % 2 == 0 end,
  function(x, y) return x * y % 2 + x * y % 3 == 0 end,
  function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
  function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end,
}

-- Bygger matrisen. m[y][x] = true för mörk modul (0-baserade index).
local function build(v, codewords, mask)
  local size = v * 4 + 17
  local m, fn = {}, {}
  for y = 0, size - 1 do m[y] = {}; fn[y] = {} end
  local function set(x, y, dark) m[y][x] = dark; fn[y][x] = true end

  for i = 0, size - 1 do
    set(6, i, i % 2 == 0)
    set(i, 6, i % 2 == 0)
  end
  local function finder(cx, cy)
    for dy = -4, 4 do
      for dx = -4, 4 do
        local x, y = cx + dx, cy + dy
        if x >= 0 and x < size and y >= 0 and y < size then
          local d = math.max(math.abs(dx), math.abs(dy))
          set(x, y, d ~= 2 and d ~= 4)
        end
      end
    end
  end
  finder(3, 3); finder(size - 4, 3); finder(3, size - 4)

  local al = alignPositions(v)
  local n = #al
  for i = 1, n do
    for j = 1, n do
      if not ((i == 1 and j == 1) or (i == 1 and j == n) or (i == n and j == 1)) then
        for dy = -2, 2 do
          for dx = -2, 2 do
            set(al[i] + dx, al[j] + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
          end
        end
      end
    end
  end

  local function formatBits(msk)
    local data = 1 * 8 + msk -- felkorrigering L = 01
    local rem = data
    for _ = 1, 10 do
      rem = bxor(rem * 2, floor(rem / 512) * 0x537)
    end
    local bits = bxor(data * 1024 + rem, 0x5412)
    for i = 0, 5 do set(8, i, bit(bits, i) == 1) end
    set(8, 7, bit(bits, 6) == 1)
    set(8, 8, bit(bits, 7) == 1)
    set(7, 8, bit(bits, 8) == 1)
    for i = 9, 14 do set(14 - i, 8, bit(bits, i) == 1) end
    for i = 0, 7 do set(size - 1 - i, 8, bit(bits, i) == 1) end
    for i = 8, 14 do set(8, size - 15 + i, bit(bits, i) == 1) end
    set(8, size - 8, true)
  end
  formatBits(0)

  if v >= 7 then
    local rem = v
    for _ = 1, 12 do rem = bxor(rem * 2, floor(rem / 2048) * 0x1F25) end
    local bits = v * 4096 + rem
    for i = 0, 17 do
      local b = bit(bits, i) == 1
      local a, c = size - 11 + i % 3, floor(i / 3)
      set(a, c, b); set(c, a, b)
    end
  end

  -- Data i sicksack från nedre högra hörnet.
  local i, total = 0, #codewords * 8
  local right = size - 1
  while right >= 1 do
    if right == 6 then right = 5 end
    for vert = 0, size - 1 do
      for j = 0, 1 do
        local x = right - j
        local upward = floor((right + 1) / 2) % 2 == 0
        local y = upward and (size - 1 - vert) or vert
        if not fn[y][x] then
          local dark = false
          if i < total then
            dark = bit(codewords[floor(i / 8) + 1], 7 - i % 8) == 1
            i = i + 1
          end
          m[y][x] = dark
        end
      end
    end
    right = right - 2
  end

  local f = MASKS[mask]
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      if not fn[y][x] and f(x, y) then m[y][x] = not m[y][x] end
    end
  end
  formatBits(mask)
  return m, size
end

-- Förenklad straffpoäng (regel 1, 2 och 4 i standarden) för att välja mask.
local function penalty(m, size)
  local p, dark = 0, 0
  for y = 0, size - 1 do
    local run, last = 0, nil
    for x = 0, size - 1 do
      local c = m[y][x]
      if c then dark = dark + 1 end
      if c == last then run = run + 1 else
        if run >= 5 then p = p + run - 2 end
        run, last = 1, c
      end
      if x < size - 1 and y < size - 1 and c == m[y][x + 1] and c == m[y + 1][x] and c == m[y + 1][x + 1] then
        p = p + 3
      end
    end
    if run >= 5 then p = p + run - 2 end
  end
  for x = 0, size - 1 do
    local run, last = 0, nil
    for y = 0, size - 1 do
      local c = m[y][x]
      if c == last then run = run + 1 else
        if run >= 5 then p = p + run - 2 end
        run, last = 1, c
      end
    end
    if run >= 5 then p = p + run - 2 end
  end
  local k = floor(math.abs(dark * 20 - size * size * 10) / (size * size))
  return p + k * 10
end

-- Kodar en sträng. Returnerar matris, storlek och version, eller nil om den
-- inte får plats i version 20.
function ns.QREncode(text, minVersion)
  local len = #text
  local v = minVersion or 1
  while v <= ns.QR_MAX_VERSION and ns.QRCapacity(v) < len do v = v + 1 end
  if v > ns.QR_MAX_VERSION then return nil end

  local bits = {}
  local function put(val, n) for k = n - 1, 0, -1 do bits[#bits + 1] = bit(val, k) end end
  put(4, 4) -- byte-läge
  put(len, v <= 9 and 8 or 16)
  for k = 1, len do put(text:byte(k), 8) end
  local cap = dataCodewords(v) * 8
  put(0, math.min(4, cap - #bits))
  put(0, (8 - #bits % 8) % 8)
  local data = {}
  for k = 1, #bits, 8 do
    local b = 0
    for j = 0, 7 do b = b * 2 + bits[k + j] end
    data[#data + 1] = b
  end
  local padByte = 0xEC
  while #data < dataCodewords(v) do
    data[#data + 1] = padByte
    padByte = padByte == 0xEC and 0x11 or 0xEC
  end

  -- Dela upp i block, lägg till felkorrigering och fläta ihop.
  local nb, eccLen = NUM_BLOCKS[v], ECC_PER_BLOCK[v]
  local raw = floor(rawModules(v) / 8)
  local numShort = nb - raw % nb
  local shortLen = floor(raw / nb)
  local div = rsDivisor(eccLen)
  local blocks, k = {}, 1
  for b = 0, nb - 1 do
    local n = shortLen - eccLen + (b < numShort and 0 or 1)
    local dat = {}
    for q = 1, n do dat[q] = data[k]; k = k + 1 end
    local ecc = rsRemainder(dat, div)
    local block = {}
    for q = 1, n do block[#block + 1] = dat[q] end
    if b < numShort then block[#block + 1] = false end -- platshållare
    for q = 1, eccLen do block[#block + 1] = ecc[q] end
    blocks[#blocks + 1] = block
  end
  local codewords = {}
  for q = 1, #blocks[1] do
    for b = 1, nb do
      local c = blocks[b][q]
      if c ~= false and c ~= nil then codewords[#codewords + 1] = c end
    end
  end

  local best, bestSize, bestScore
  for mask = 0, 7 do
    local m, size = build(v, codewords, mask)
    local score = penalty(m, size)
    if not bestScore or score < bestScore then best, bestSize, bestScore = m, size, score end
  end
  return best, bestSize, v
end
