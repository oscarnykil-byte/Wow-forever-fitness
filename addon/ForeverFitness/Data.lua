-- Forever Fitness: övningar, händelser och svårighet.
-- Speglar EX, EVENTS, DIFF och target() i src/forever-fitness.html.
-- Ändras något där ska det ändras här också.
local _, ns = ...

-- Samma id:n som i webbappen. eq = kräver redskap.
ns.EX = {
  pushup    = { n = "Armhävningar",          cat = "str",    unit = "reps", base = 10 },
  dips      = { n = "Dips mot stol",         cat = "str",    unit = "reps", base = 10 },
  pike      = { n = "Pike-armhävningar",     cat = "str",    unit = "reps", base = 8 },
  rowdb     = { n = "Hantelrodd",            cat = "str",    unit = "reps", base = 12, eq = true },
  pressdb   = { n = "Hantelpress",           cat = "str",    unit = "reps", base = 10, eq = true },
  bandrow   = { n = "Gummibandsrodd",        cat = "str",    unit = "reps", base = 15, eq = true },
  pullapart = { n = "Band pull-apart",       cat = "str",    unit = "reps", base = 15, eq = true },
  squat     = { n = "Knäböj",                cat = "leg",    unit = "reps", base = 15 },
  lunge     = { n = "Utfall (per ben)",      cat = "leg",    unit = "reps", base = 10 },
  bridge    = { n = "Höftlyft",              cat = "leg",    unit = "reps", base = 15 },
  wallsit   = { n = "Väggsittning",          cat = "leg",    unit = "sec",  base = 30 },
  jumpsquat = { n = "Upphopp-knäböj",        cat = "leg",    unit = "reps", base = 10 },
  goblet    = { n = "Goblet squat",          cat = "leg",    unit = "reps", base = 12, eq = true },
  swing     = { n = "Kettlebell-sving",      cat = "leg",    unit = "reps", base = 15, eq = true },
  plank     = { n = "Planka",                cat = "core",   unit = "sec",  base = 30 },
  sideplank = { n = "Sidoplanka (per sida)", cat = "core",   unit = "sec",  base = 20 },
  situp     = { n = "Situps",                cat = "core",   unit = "reps", base = 15 },
  superman  = { n = "Superman",              cat = "core",   unit = "reps", base = 12 },
  hollow    = { n = "Hollow hold",           cat = "core",   unit = "sec",  base = 20 },
  twist     = { n = "Rysk twist",            cat = "core",   unit = "reps", base = 20 },
  jacks     = { n = "Jumping jacks",         cat = "cardio", unit = "reps", base = 25 },
  burpee    = { n = "Burpees",               cat = "cardio", unit = "reps", base = 8 },
  climber   = { n = "Mountain climbers",     cat = "cardio", unit = "reps", base = 20 },
  knees     = { n = "Höga knän",             cat = "cardio", unit = "sec",  base = 30 },
  rope      = { n = "Hopprep",               cat = "cardio", unit = "sec",  base = 60, eq = true },
  shadow    = { n = "Skuggboxning",          cat = "cardio", unit = "sec",  base = 45 },
}

-- Fast ordning för listor i inställningarna.
ns.EX_ORDER = {
  "pushup", "dips", "pike", "rowdb", "pressdb", "bandrow", "pullapart",
  "squat", "lunge", "bridge", "wallsit", "jumpsquat", "goblet", "swing",
  "plank", "sideplank", "situp", "superman", "hollow", "twist",
  "jacks", "burpee", "climber", "knees", "rope", "shadow",
}

ns.DIFF = {
  easy   = { n = "Lätt",   m = 0.6 },
  normal = { n = "Normal", m = 1 },
  hard   = { n = "Hård",   m = 1.4 },
}
ns.DIFF_ORDER = { "easy", "normal", "hard" }

-- Händelser i addonet. ev = händelsens id i webbappen (EVENTS),
-- f = faktor från appen. Spärrtiden gäller per ev, så laddningsskärm
-- och flygresa delar spärr precis som de delar händelse i appen.
ns.TRIGGERS = {
  death = { n = "Död",            title = "Du dog! Dödsstraff",        ev = "death", ex = "burpee",  f = 0.6 },
  ding  = { n = "Level up",       title = "Ding! Mot 60",              ev = "ding",  ex = "pushup",  f = 1 },
  load  = { n = "Laddningsskärm", title = "Laddningsskärm. Res inte stilla", ev = "load", ex = "squat", f = 1 },
  taxi  = { n = "Flygresa",       title = "Flygresa. Res inte stilla", ev = "load",  ex = "squat",   f = 1 },
  boss  = { n = "Bossdöd",        title = "Bossen föll! Segerdans",    ev = "boss",  ex = "lunge",   f = 1 },
  wipe  = { n = "Wipe",           title = "Wipe! Hela gruppen lider",  ev = "wipe",  ex = "plank",   f = 1 },
  loot  = { n = "Bra loot",       title = "Bra loot! Fira",            ev = "loot",  ex = "jacks",   f = 1 },
  afk   = { n = "AFK",            title = "AFK. Rör på dig",           ev = "afk",   ex = "climber", f = 1 },
  alarm = { n = "Raidvarning",    title = "Raidvarning! Pausa när du kan", ev = "alarm", ex = nil,   f = 1, src = "alarm" },
}
ns.TRIGGER_ORDER = { "death", "ding", "load", "taxi", "boss", "wipe", "loot", "afk", "alarm" }

-- JavaScripts Math.round: avrundar .5 uppåt, även för negativa tal.
local function jsround(x) return math.floor(x + 0.5) end
ns.jsround = jsround

-- Samma formel som target() i webbappen:
-- base * svårighet * (1 + nivå * 0,01) * faktor,
-- sekunder avrundas till närmaste 5 (minst 10), reps till heltal (minst 3).
function ns.Target(exId, f, diff, level)
  local e = ns.EX[exId]
  if not e then return 0 end
  local m = (ns.DIFF[diff] or ns.DIFF.normal).m
  local L = tonumber(level) or 1
  if L > 60 then L = 60 end
  if L < 1 then L = 1 end
  local a = e.base * m * (1 + L * 0.01) * (f or 1)
  if e.unit == "sec" then
    return math.max(10, jsround(a / 5) * 5)
  end
  return math.max(3, jsround(a))
end

-- Övningar utan redskap (addonet vet inte vilka redskap ni har).
function ns.BodyweightPool()
  local out = {}
  for _, id in ipairs(ns.EX_ORDER) do
    if not ns.EX[id].eq then out[#out + 1] = id end
  end
  return out
end

function ns.FormatAmount(exId, amt)
  local e = ns.EX[exId]
  if e and e.unit == "sec" then return amt .. " sekunder" end
  return amt .. " st"
end

-- Ljud. Varje val har en lista med SOUNDKIT-namn som provas i ordning.
-- Klienten är ny, så det som saknas hoppas över och till sist används
-- raidvarningens ljud (8959). /fit ljudlista visar vad som finns i spelet.
ns.SOUNDS = {
  raid    = { n = "Raidvarning",     kit = { "RAID_WARNING" } },
  ready   = { n = "Ready check",     kit = { "READY_CHECK" } },
  whisper = { n = "Bossvarning",     kit = { "UI_RAID_BOSS_WHISPER_WARNING", "RAID_WARNING" } },
  quest   = { n = "Uppdrag klart",   kit = { "IG_QUEST_LIST_COMPLETE", "READY_CHECK" } },
  epic    = { n = "Episkt loot",     kit = { "UI_EPICLOOT_TOAST", "UI_LEGENDARY_LOOT_TOAST", "READY_CHECK" } },
  legend  = { n = "Legendariskt",    kit = { "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST", "READY_CHECK" } },
  clock   = { n = "Väckarklocka",    kit = { "ALARM_CLOCK_WARNING_3", "ALARM_CLOCK_WARNING_2", "RAID_WARNING" } },
  toast   = { n = "Pling",           kit = { "UI_BNET_TOAST", "TELL_MESSAGE", "READY_CHECK" } },
  none    = { n = "Tyst",            kit = {} },
}
ns.SOUND_ORDER = { "raid", "ready", "whisper", "quest", "epic", "legend", "clock", "toast", "none" }

-- Standardljud per händelse.
ns.TRIGGER_SOUND = {
  death = "whisper", ding = "quest", load = "ready", taxi = "ready",
  boss = "epic", wipe = "raid", loot = "legend", afk = "toast", alarm = "clock",
}
