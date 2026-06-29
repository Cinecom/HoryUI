-- HoryUI :: vendored pfUI skin engine (boot / host)
-- ---------------------------------------------------------------------------
-- The other files in this folder are a NEAR-VERBATIM copy of pfUI's skin
-- subsystem + the nameplates module and its libs (compat + api + ui-widgets +
-- config + skins/*.lua + lib{tipscan,spell,throttle,debuff,cast}.lua +
-- nameplates.lua + img/), with the single mechanical rename `pfUI` -> `pfSkin`
-- so the engine owns its own namespace and runs WITHOUT pfUI installed. This
-- file replaces the slice of pfUI.lua they depend on (namespace,
-- GetEnvironment/setfenv, RegisterSkin/RegisterModule, config bootstrap).
--
-- DORMANCY: while real pfUI is present AND enabled, this whole engine does
-- nothing -- every vendored file bails on `HoryUI._pfuiActive` (set below) so we
-- never double-skin a frame or double-wrap the shared GetItemInfo/hooksecurefunc.
-- Disable or delete pfUI and HoryUI applies the identical skins on next /reload.
--
-- UPDATING: do not hand-edit the copied files. Re-copy from pfUI, re-run the
-- `pfUI`->`pfSkin` rename, and re-prepend the `HoryUI._pfuiActive` guard.
-- See CLAUDE.md "Blizzard window skins" notes.
-- ---------------------------------------------------------------------------

-- [ dormancy gate ] is real pfUI an installed+enabled addon?
-- Checked at FILE-LOAD time, so IsAddOnLoaded is unreliable (HoryUI sorts before
-- pfUI and loads first) -- fall back to GetAddOnInfo's enabled/loadable flags,
-- which are valid regardless of load order.
local function pfUIActive()
  if IsAddOnLoaded and IsAddOnLoaded("pfUI") then return true end
  if GetAddOnInfo then
    local _, title, _, enabled, loadable = GetAddOnInfo("pfUI")
    if title and (enabled == 1 or enabled == "1" or loadable == 1 or loadable == "1") then
      return true
    end
  end
  return false
end

HoryUI = HoryUI or {}
HoryUI._pfuiActive = pfUIActive()
if HoryUI._pfuiActive then return end   -- pfUI is here; stay completely dormant

-- [ namespace ] the slice of pfUI.lua the skin engine reads.
pfSkin = CreateFrame("Frame", "pfSkinHost", UIParent)
pfSkin.api          = {}
pfSkin.env          = {}
pfSkin.skin         = {}
pfSkin.skins        = {}
pfSkin.module       = {}
pfSkin.modules      = {}
pfSkin.hooks        = {}
pfSkin.cache        = {}   -- used by character/inspect skins (item-quality cache)
pfSkin.movables     = {}   -- used by Update/RemoveMovable (miscellaneous, help skins)
pfSkin.bootup       = true
pfSkin.expansion    = "vanilla"
pfSkin.client       = 11200
pfSkin.path         = "Interface\\AddOns\\!HoryUI\\pfskin"
pfSkin.version      = { string = "pfUI-skins (vendored)" }
pfSkin.font_default = "Fonts\\FRIZQT__.TTF"
pfSkin.font_unit    = "Fonts\\FRIZQT__.TTF"   -- nameplates: used when C.nameplates.use_unitfonts == "1"

-- runtime config table (NOT a SavedVariable -- the skins only read defaults,
-- which LoadConfig (config.lua) fills in below). Pre-seed the one key read by an
-- OnUpdate at load time so it can never index a nil before LoadConfig runs.
pfSkin_config = { unitframes = { animation_speed = "5" } }

-- locale data (spell cast times, debuff durations, totem/critter names, ...).
-- Populated by locales_enUS.lua; the nameplate libs (libcast/libdebuff) are
-- data-driven off it. Created here so the locale file can index it on load.
pfSkin_locale = {}

-- libunitscan caches scanned unit data (class/level/elite/guild keyed by name)
-- here and assigns it to its players table on PLAYER_ENTERING_WORLD; must be a
-- table or GetUnitData indexes nil. Runtime-only (not persisted across sessions).
pfSkin_playerDB = {}

-- valid unit tokens, from pfUI's env/tables.lua (libcast indexes pfValidUnits[unit]).
-- The rest of that 312KB file (pfSellData / pfMapOverlayData / pfGridmath) isn't used
-- by the nameplate closure, so only this small table is reproduced here. Defined as a
-- real global (no setfenv in boot) so the env's _G fallback resolves it.
pfValidUnits = {}
pfValidUnits["pet"]                = true
pfValidUnits["player"]             = true
pfValidUnits["target"]             = true
pfValidUnits["mouseover"]          = true
pfValidUnits["pettarget"]          = true
pfValidUnits["playertarget"]       = true
pfValidUnits["targettarget"]       = true
pfValidUnits["mouseovertarget"]    = true
pfValidUnits["targettargettarget"] = true
for i = 1, 4  do pfValidUnits["party" .. i]              = true end
for i = 1, 4  do pfValidUnits["partypet" .. i]           = true end
for i = 1, 40 do pfValidUnits["raid" .. i]               = true end
for i = 1, 40 do pfValidUnits["raidpet" .. i]            = true end
for i = 1, 4  do pfValidUnits["party" .. i .. "target"]    = true end
for i = 1, 4  do pfValidUnits["partypet" .. i .. "target"] = true end
for i = 1, 40 do pfValidUnits["raid" .. i .. "target"]     = true end
for i = 1, 40 do pfValidUnits["raidpet" .. i .. "target"]  = true end

-- pfUI.media analogue. Window skins use stock textures (WHITE8X8), but the
-- vendored nameplates pull real textures from pfskin/img/. Resolve the three
-- forms pfUI uses: "img:x", "font:x", and full "Interface\AddOns\pfSkin\..."
-- paths (the pfUI->pfSkin rename turned config's pfUI paths into pfSkin ones).
pfSkin.media = setmetatable({}, { __index = function(tab, key)
  local value = tostring(key)
  if string.find(value, "img:") then
    value = string.gsub(value, "img:", pfSkin.path .. "\\img\\")
  elseif string.find(value, "font:") then
    value = string.gsub(value, "font:", pfSkin.path .. "\\fonts\\")
  else
    value = string.gsub(value, "Interface\\AddOns\\pfSkin\\", pfSkin.path .. "\\")
  end
  rawset(tab, key, value)
  return value
end })

-- [ environment ] injected into every api/skin chunk via setfenv. Mirrors
-- pfUI:GetEnvironment(): api functions become globals, real globals fall through,
-- C = config, T = key-returning translation stub (matches pfUI's fallback), and
-- L = the real enUS locale data (spell/debuff database the nameplate libs need).
setmetatable(pfSkin.env, { __index = getfenv(0) })
local keyReturn = setmetatable({}, { __index = function(t, k)
  local v = tostring(k); rawset(t, k, v); return v
end })
function pfSkin:GetEnvironment()
  for m, func in pairs(pfSkin.api or {}) do pfSkin.env[m] = func end
  pfSkin.env._G = getfenv(0)
  pfSkin.env.C  = pfSkin_config
  pfSkin.env.T  = keyReturn
  pfSkin.env.L  = pfSkin_locale[GetLocale()] or pfSkin_locale["enUS"] or keyReturn
  return pfSkin.env
end

-- [ skin registry ] mirrors pfUI:RegisterSkin / LoadSkin. The version string is
-- matched against pfSkin.expansion, so TBC-only skins simply never register here.
function pfSkin:RegisterSkin(name, a2, a3)
  if pfSkin.skin[name] then return end
  local hasv    = type(a2) == "string"
  local func    = hasv and a3 or a2
  local version = hasv and a2 or "vanilla:tbc:wotlk"
  if not string.find(version, pfSkin.expansion) then return end
  pfSkin.skin[name] = func
  table.insert(pfSkin.skins, name)
  if not pfSkin.bootup then pfSkin:LoadSkin(name) end
end

function pfSkin:LoadSkin(s)
  if not pfSkin.skin[s] then return end
  setfenv(pfSkin.skin[s], pfSkin:GetEnvironment())
  pfSkin.skin[s]()
end

-- [ module registry ] mirrors pfUI:RegisterModule / LoadModule. Used by the
-- vendored nameplates module (a module, not a window skin).
function pfSkin:RegisterModule(name, a2, a3)
  if pfSkin.module[name] then return end
  local hasv    = type(a2) == "string"
  local func    = hasv and a3 or a2
  local version = hasv and a2 or "vanilla:tbc:wotlk"
  if not string.find(version, pfSkin.expansion) then return end
  pfSkin.module[name] = func
  table.insert(pfSkin.modules, name)
  if not pfSkin.bootup then pfSkin:LoadModule(name) end
end

function pfSkin:LoadModule(m)
  if not pfSkin.module[m] then return end
  setfenv(pfSkin.module[m], pfSkin:GetEnvironment())
  pfSkin.module[m]()
end

-- [ select() polyfill ] a few skins call select(); base Lua 5.0 lacks it.
if not select then
  function select(n, ...)
    if n == "#" then return arg.n end
    local out = {}
    for i = n, arg.n do table.insert(out, arg[i]) end
    return unpack(out)
  end
end

-- [ boot ] fill config defaults early (ADDON_LOADED, before any OnUpdate ticks),
-- then apply every registered skin at login. Defuse on logout (Error 132, §5).
pfSkin:RegisterEvent("ADDON_LOADED")
pfSkin:RegisterEvent("PLAYER_LOGIN")
pfSkin:RegisterEvent("PLAYER_LOGOUT")
pfSkin:SetScript("OnEvent", function()
  if event == "PLAYER_LOGOUT" then
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)
    return
  end

  if event == "ADDON_LOADED" then
    if arg1 == "!HoryUI" and pfSkin.LoadConfig and not pfSkin.configured then
      pfSkin.configured = true
      pfSkin:LoadConfig()
    end
    return
  end

  -- PLAYER_LOGIN: config is a backstop in case ADDON_LOADED was missed, then apply
  if pfSkin.LoadConfig and not pfSkin.configured then
    pfSkin.configured = true
    pfSkin:LoadConfig()
  end
  pfSkin.bootup = false

  -- window skins -- master "pfUI window skins" toggle (default on). Both toggles
  -- live in HoryUI settings -> PfUI and take effect on /reload.
  if not (HoryUIDB and HoryUIDB.pfskinEnabled == false) then
    local n = table.getn(pfSkin.skins)
    for i = 1, n do pfSkin:LoadSkin(pfSkin.skins[i]) end
  end

  -- nameplates module -- separate "pfUI nameplates" toggle (default on)
  if not (HoryUIDB and HoryUIDB.pfnameplatesEnabled == false) then
    local m = table.getn(pfSkin.modules)
    for i = 1, m do pfSkin:LoadModule(pfSkin.modules[i]) end
  end
end)
