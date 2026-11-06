-- luacheck för Forever Fitness. Kör: cd addon && luacheck .
std = "lua51"
max_line_length = false
files["ForeverFitness"] = {
  globals = {
    "ForeverFitnessDB", "ForeverFitnessCharDB", "SlashCmdList",
    "SLASH_FOREVERFITNESS1", "SLASH_FOREVERFITNESS2",
  },
  read_globals = {
    "CreateFrame", "UIParent", "GetTime", "time", "InCombatLockdown",
    "UnitOnTaxi", "UnitIsAFK", "PlaySound", "SOUNDKIT", "RaidNotice_AddMessage",
    "RaidWarningFrame", "ChatTypeInfo", "UIErrorsFrame", "DEFAULT_CHAT_FRAME",
    "BackdropTemplateMixin", "C_Item", "GetItemInfo", "issecretvalue",
    "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "C_Timer", "Settings",
    "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "IsShiftKeyDown", "Mixin", "date",
  },
}
files["tests"] = { globals = { "_G" }, allow_defined_top = true, ignore = { "212", "213" } }
