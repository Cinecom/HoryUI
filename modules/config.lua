-- HoryUI :: settings window (rebuilt)
-- A single framed window: header (brand + version) / left category nav
-- (General, Modules, Addons) / content area / footer (author + Reload).
-- Lua 5.0 / WoW 1.12 -- handlers use this/event/arg1.

HoryUI:RegisterModule("config", true, function()
  local C = HoryUI.color
  local getn = table.getn
  local format = string.format
  local W, H = 420, 410

  -- =========================================================================
  -- window
  -- =========================================================================
  local win = CreateFrame("Frame", "HoryUIConfig", UIParent)
  win:SetWidth(W); win:SetHeight(H)
  win:SetFrameStrata("DIALOG")
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  win:EnableMouse(true)
  win:SetMovable(true)
  win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", function() this:StartMoving() end)
  win:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  HoryUI.CreateBackdrop(win)

  -- ---- header -------------------------------------------------------------
  local brand = win:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(brand, HoryUI.font.normal, 15, "OUTLINE")
  brand:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -11)
  brand:SetText("HoryUI")
  brand:SetTextColor(C.accent_hi[1], C.accent_hi[2], C.accent_hi[3])

  local brandSub = win:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(brandSub, HoryUI.font.normal, 11, "OUTLINE")
  brandSub:SetPoint("BOTTOMLEFT", brand, "BOTTOMRIGHT", 6, 0)
  brandSub:SetText("settings")
  brandSub:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

  local ver = (GetAddOnMetadata and GetAddOnMetadata("!HoryUI", "Version")) or HoryUI.version
  local hver = win:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(hver, HoryUI.font.number, 10, "OUTLINE")
  hver:SetPoint("TOPRIGHT", win, "TOPRIGHT", -30, -13)
  hver:SetText("v" .. (ver or "?"))
  hver:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

  local close = HoryUI.CreateButton(win, "x", function() win:Hide() end)
  close:SetWidth(18); close:SetHeight(18)
  close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)

  local rule = win:CreateTexture(nil, "ARTWORK")
  rule:SetTexture(HoryUI.tex.white)
  rule:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -32)
  rule:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -32)

  -- vertical divider between nav and content
  local vdiv = win:CreateTexture(nil, "ARTWORK")
  vdiv:SetTexture(HoryUI.tex.white)
  vdiv:SetVertexColor(0.16, 0.17, 0.19, 0.9)
  vdiv:SetWidth(1)
  vdiv:SetPoint("TOPLEFT", win, "TOPLEFT", 118, -40)
  vdiv:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 118, 38)

  -- =========================================================================
  -- left nav
  -- =========================================================================
  local ShowTab          -- forward declaration (nav handlers call it)

  local function MakeNav(label, which, y)
    local b = CreateFrame("Button", nil, win)
    b:SetWidth(100); b:SetHeight(24)
    b:SetPoint("TOPLEFT", win, "TOPLEFT", 12, y)

    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetTexture(HoryUI.tex.white)
    b.bar:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    b.bar:SetWidth(2)
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -3)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 3)
    b.bar:Hide()

    b.text = b:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(b.text, HoryUI.font.normal, 12, "OUTLINE")
    b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.text:SetText(label)
    b.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

    b:SetScript("OnClick", function() ShowTab(which) end)
    b:SetScript("OnEnter", function()
      if not this.active then this.text:SetTextColor(C.text2[1], C.text2[2], C.text2[3]) end
    end)
    b:SetScript("OnLeave", function()
      if not this.active then this.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3]) end
    end)
    return b
  end

  local navGeneral = MakeNav("General", "general", -42)
  local navMods    = MakeNav("Modules", "modules", -70)
  local navAddons  = MakeNav("Addons",  "addons",  -98)
  local navPfui    = MakeNav("PfUI",    "pfui",    -126)
  local navAbars   = MakeNav("Actionbars", "actionbars", -154)
  local navLoad    = MakeNav("Load Times", "loadtimes", -182)

  local function HLNav(b, active)
    b.active = active
    if active then
      b.bar:Show()
      b.text:SetTextColor(C.text[1], C.text[2], C.text[3])
    else
      b.bar:Hide()
      b.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
    end
  end

  -- =========================================================================
  -- content : General
  -- =========================================================================
  local general = CreateFrame("Frame", nil, win)
  general:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -44)
  general:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 42)

  local function Desc(text, anchorTo, dy, parent)
    local d = (parent or general):CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(d, HoryUI.font.normal, 10, "OUTLINE")
    d:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, dy)
    d:SetText(text)
    d:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
    return d
  end

  local unlock = HoryUI.CreateToggle(general,
    function() return not HoryUI.locked end,
    function(v) HoryUI.SetLocked(not v) end)
  unlock:SetPoint("TOPLEFT", general, "TOPLEFT", 2, -8)

  local unlockLbl = general:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(unlockLbl, HoryUI.font.normal, 12, "OUTLINE")
  unlockLbl:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
  unlockLbl:SetText("Unlock panels")
  unlockLbl:SetTextColor(C.text[1], C.text[2], C.text[3])
  Desc("Reveal the movers, drag panels into place, then toggle off.", unlock, -6)

  local reset = HoryUI.CreateButton(general, "Reset positions",
    function() HoryUIDB.pos = {}; ReloadUI() end)
  reset:SetWidth(130)
  reset:SetPoint("TOPLEFT", general, "TOPLEFT", 2, -56)
  Desc("Send every HoryUI panel back to its default spot (reloads).", reset, -6)

  -- ---- HoryUI profiles (ALL settings: every frame position + module flags +
  -- the vendored Bongos bar layout) ----------------------------------------
  -- A profile snapshots HoryUIDB (minus the profiles container itself) plus the
  -- four Bongos saved-var tables, so one named profile restores the entire UI.
  local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deepcopy(v) end
    return r
  end

  local function HProfSnapshotDB()
    local snap = {}
    for k, v in pairs(HoryUIDB) do
      if k ~= "profiles" then snap[k] = deepcopy(v) end
    end
    return snap
  end

  local function HProfSave(name)
    HoryUIDB.profiles = HoryUIDB.profiles or {}
    HoryUIDB.profiles[name] = {
      db = HProfSnapshotDB(),
      bongos = {
        BongosSets   = deepcopy(BongosSets),
        BActionSets  = deepcopy(BActionSets),
        BStanceSets  = deepcopy(BStanceSets),
        BContextSets = deepcopy(BContextSets),
      },
    }
  end

  local function HProfLoad(name)
    local p = HoryUIDB.profiles and HoryUIDB.profiles[name]
    if not p then return end
    local keep = HoryUIDB.profiles                 -- never clobber the profile store
    for k in pairs(HoryUIDB) do if k ~= "profiles" then HoryUIDB[k] = nil end end
    for k, v in pairs(p.db) do HoryUIDB[k] = deepcopy(v) end
    HoryUIDB.profiles = keep
    if p.bongos then
      BongosSets   = deepcopy(p.bongos.BongosSets)
      BActionSets  = deepcopy(p.bongos.BActionSets)
      BStanceSets  = deepcopy(p.bongos.BStanceSets)
      BContextSets = deepcopy(p.bongos.BContextSets)
    end
    ReloadUI()                                      -- positions/bars apply on reload
  end

  local hpHdr = general:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(hpHdr, HoryUI.font.normal, 12, "OUTLINE")
  hpHdr:SetPoint("TOPLEFT", general, "TOPLEFT", 2, -104)
  hpHdr:SetText("Profiles")
  hpHdr:SetTextColor(C.accent_hi[1], C.accent_hi[2], C.accent_hi[3])
  Desc("Save / load the whole HoryUI setup.", hpHdr, -4)

  local hpName = CreateFrame("EditBox", nil, general)
  hpName:SetWidth(150); hpName:SetHeight(18)
  hpName:SetAutoFocus(false)
  hpName:SetFont(HoryUI.font.normal, 11, "OUTLINE")
  hpName:SetTextColor(C.text[1], C.text[2], C.text[3])
  hpName:SetTextInsets(4, 4, 0, 0)
  hpName:SetPoint("TOPLEFT", general, "TOPLEFT", 2, -136)
  HoryUI.CreateBackdrop(hpName)
  hpName:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  hpName:SetScript("OnEnterPressed", function() this:ClearFocus() end)

  local hpData, hpSel = {}, nil
  local RefreshHProf

  local hpSave = HoryUI.CreateButton(general, "Save", function()
    local n = hpName:GetText()
    if n and n ~= "" then HProfSave(n); hpSel = n; RefreshHProf() end
  end)
  hpSave:SetWidth(60); hpSave:SetPoint("LEFT", hpName, "RIGHT", 6, 0)

  local hpList = HoryUI.CreateScrollFrame(general, 240, 4, 23)
  hpList:SetPoint("TOPLEFT", general, "TOPLEFT", 2, -160)
  hpList.OnUpdateRow = function(row, idx)
    row.label:SetText(hpData[idx])
    row.SetOn(hpSel == hpData[idx])
  end
  hpList.OnClickRow = function(idx)
    hpSel = hpData[idx]; hpName:SetText(hpSel); hpList.Update()
  end

  local hpLoad = HoryUI.CreateButton(general, "Load", function()
    if hpSel then HProfLoad(hpSel) end
  end)
  hpLoad:SetWidth(80); hpLoad:SetPoint("TOPLEFT", general, "TOPLEFT", 2, -256)
  local hpDel = HoryUI.CreateButton(general, "Delete", function()
    if hpSel and HoryUIDB.profiles then HoryUIDB.profiles[hpSel] = nil; hpSel = nil; RefreshHProf() end
  end)
  hpDel:SetWidth(80); hpDel:SetPoint("LEFT", hpLoad, "RIGHT", 6, 0)

  RefreshHProf = function()
    hpData = {}
    if HoryUIDB.profiles then
      for name in pairs(HoryUIDB.profiles) do tinsert(hpData, name) end
      table.sort(hpData)
    end
    hpList.SetTotal(getn(hpData))
  end

  -- =========================================================================
  -- content : Modules
  -- =========================================================================
  local mods = {
    { id = "unitframes",   name = "Unit Frames" },
    { id = "castbar",      name = "Cast Bars" },
    { id = "auras",        name = "Auras (buffs / debuffs)" },
    { id = "rangetracker", name = "Range Tracker" },
    { id = "party",        name = "Party Frames" },
    { id = "raid",         name = "Raid Frames" },
    { id = "xprep",        name = "XP / Reputation Bar" },
    { id = "weaponpoison", name = "Weapon Poison" },
    { id = "chat",         name = "Chat Tweaks" },
    { id = "minimap",      name = "Minimap" },
    { id = "bags",         name = "Bags (one-bag)" },
    { id = "character",    name = "Character Panel" },
    { id = "outfitter",    name = "Outfitter Integration" },
  }

  local modList = HoryUI.CreateScrollFrame(win, 278, 11, 23)
  modList:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -44)
  modList.OnUpdateRow = function(row, idx)
    local m = mods[idx]
    row.label:SetText(m.name)
    row.SetOn(HoryUI:IsModuleEnabled(m.id, true))
  end
  modList.OnClickRow = function(idx)
    local m = mods[idx]
    HoryUI:SetModuleEnabled(m.id, not HoryUI:IsModuleEnabled(m.id, true))
    modList.Update()
  end

  -- =========================================================================
  -- content : Addons
  -- =========================================================================
  -- 1.12 signature: name, title, notes, enabled, loadable, reason, security
  local function AddonEnabled(i)
    local _, _, _, enabled = GetAddOnInfo(i)
    return enabled and enabled ~= 0
  end

  local addonList = HoryUI.CreateScrollFrame(win, 278, 11, 23)
  addonList:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -44)
  addonList.OnUpdateRow = function(row, idx)
    local name, title = GetAddOnInfo(idx)
    row.label:SetText((title and title ~= "") and title or name)
    row.SetOn(AddonEnabled(idx))
  end
  addonList.OnClickRow = function(idx)
    if AddonEnabled(idx) then DisableAddOn(idx) else EnableAddOn(idx) end
    addonList.Update()
  end

  -- =========================================================================
  -- content : PfUI  (the vendored pfskin engine -- window skins + nameplates)
  -- =========================================================================
  local pfui = CreateFrame("Frame", nil, win)
  pfui:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -44)
  pfui:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 42)

  -- window skins. Toggling reloads so the skins apply/unapply cleanly.
  local skin = HoryUI.CreateToggle(pfui,
    function() return (not HoryUIDB) or HoryUIDB.pfskinEnabled ~= false end,
    function(v)
      if HoryUIDB then HoryUIDB.pfskinEnabled = v and true or false end
      ReloadUI()
    end)
  skin:SetPoint("TOPLEFT", pfui, "TOPLEFT", 2, -8)

  local skinLbl = pfui:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(skinLbl, HoryUI.font.normal, 12, "OUTLINE")
  skinLbl:SetPoint("LEFT", skin, "RIGHT", 8, 0)
  skinLbl:SetText("pfUI window skins")
  skinLbl:SetTextColor(C.text[1], C.text[2], C.text[3])
  Desc("Skin Blizzard windows in the pfUI style (reloads).", skin, -6, pfui)

  -- nameplates (ported pfUI nameplates module: castbars + debuff timers).
  local plates = HoryUI.CreateToggle(pfui,
    function() return (not HoryUIDB) or HoryUIDB.pfnameplatesEnabled ~= false end,
    function(v)
      if HoryUIDB then HoryUIDB.pfnameplatesEnabled = v and true or false end
      ReloadUI()
    end)
  plates:SetPoint("TOPLEFT", pfui, "TOPLEFT", 2, -56)

  local platesLbl = pfui:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(platesLbl, HoryUI.font.normal, 12, "OUTLINE")
  platesLbl:SetPoint("LEFT", plates, "RIGHT", 8, 0)
  platesLbl:SetText("pfUI nameplates")
  platesLbl:SetTextColor(C.text[1], C.text[2], C.text[3])
  Desc("Enemy castbars + debuff timers (reloads).", plates, -6, pfui)

  local pfnote = pfui:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(pfnote, HoryUI.font.normal, 10, "OUTLINE")
  pfnote:SetPoint("BOTTOMLEFT", pfui, "BOTTOMLEFT", 2, 4)
  pfnote:SetText("Both apply only when pfUI itself is not installed.")
  pfnote:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

  -- =========================================================================
  -- content : Load Times  (per-addon startup file-load cost, ms)
  -- =========================================================================
  -- Data comes from core\loadtimer.lua (built in): !HoryUI loads first and records
  -- debugprofilestop() at each ADDON_LOADED, so it can time every addon. We only
  -- READ its globals here -- if they're missing we say so rather than invent numbers.
  local loadtab = CreateFrame("Frame", nil, win)
  loadtab:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -44)
  loadtab:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 42)

  local measure = HoryUI.CreateButton(loadtab, "Reload & Measure", function() ReloadUI() end)
  measure:SetWidth(120)
  measure:SetPoint("TOPLEFT", loadtab, "TOPLEFT", 2, -2)

  local loadSum = loadtab:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(loadSum, HoryUI.font.number, 10, "OUTLINE")
  loadSum:SetPoint("TOPLEFT", loadtab, "TOPLEFT", 2, -28)
  loadSum:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
  loadSum:SetText("")

  local loadMsg = loadtab:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(loadMsg, HoryUI.font.normal, 11, "OUTLINE")
  loadMsg:SetPoint("TOPLEFT", loadtab, "TOPLEFT", 2, -50)
  loadMsg:SetWidth(264); loadMsg:SetJustifyH("LEFT")
  loadMsg:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
  loadMsg:Hide()

  local loadData = {}                                  -- sorted display copy
  local loadList = HoryUI.CreateScrollFrame(loadtab, 276, 9, 23)
  loadList:SetPoint("TOPLEFT", loadtab, "TOPLEFT", 0, -46)
  loadList.OnUpdateRow = function(row, idx)
    if not row.value then                              -- first use: repurpose the row (no toggle)
      row.toggle:Hide()
      row.value = row:CreateFontString(nil, "OVERLAY")
      HoryUI.SetFont(row.value, HoryUI.font.number, 11, "OUTLINE")
      row.value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", 2, 0)
      row.label:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    end
    local e = loadData[idx]
    if not e then return end
    row.label:SetText(e.name)
    row.value:SetText(format("%.1f", e.ms))
    local c = C.health                                 -- green fast / amber mid / red slow
    if e.ms >= 20 then c = C.health_low
    elseif e.ms >= 5 then c = C.threat end
    row.value:SetTextColor(c[1], c[2], c[3])
  end

  -- read the companion's globals, sort slowest-first, refresh list + summary
  local function RefreshLoad()
    loadData = {}
    local src = HoryUILoadTimes
    local info = HoryUILoadInfo
    if info and info.missing then
      loadMsg:SetText("This client has no high-res timer (debugprofilestop), so per-addon load times can't be measured.")
      loadMsg:Show(); loadSum:SetText(""); loadList.SetTotal(0)
      return
    end
    if not src or getn(src) == 0 then
      loadMsg:SetText("No load-time data yet. Make sure the addon folder is named \"!HoryUI\" so it loads first, then Reload & Measure.")
      loadMsg:Show(); loadSum:SetText(""); loadList.SetTotal(0)
      return
    end
    loadMsg:Hide()
    local total = 0
    for i = 1, getn(src) do
      loadData[i] = { name = src[i].name, ms = src[i].ms }
      total = total + src[i].ms
    end
    table.sort(loadData, function(a, b) return a.ms > b.ms end)
    local note = ""
    if info and info.reset then note = "  (timer reset mid-load; values approximate)" end
    loadSum:SetText(format("%d addons  -  %.0f ms total, file load only", getn(loadData), total) .. note)
    loadList.SetTotal(getn(loadData))
  end

  -- =========================================================================
  -- content : Actionbars  (drives the vendored Bongos engine -- see bongos/)
  -- =========================================================================
  local abars = CreateFrame("Frame", nil, win)
  abars:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -44)
  abars:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 42)

  -- shown instead of the controls when the standalone Bongos addon is still on
  local abDormant = abars:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(abDormant, HoryUI.font.normal, 11, "OUTLINE")
  abDormant:SetPoint("TOPLEFT", abars, "TOPLEFT", 2, -8)
  abDormant:SetWidth(264); abDormant:SetJustifyH("LEFT")
  abDormant:SetTextColor(C.threat[1], C.threat[2], C.threat[3])
  abDormant:Hide()

  -- horizontal sub-tab strip (Garnet underline = active, matching the chat tabs)
  local abCurrent = "global"
  local abSub = {}
  local ShowSub
  local function MakeSub(label, key, x, w)
    local b = CreateFrame("Button", nil, abars)
    b:SetHeight(16); b:SetWidth(w)
    b:SetPoint("TOPLEFT", abars, "TOPLEFT", x, -2)
    b.text = b:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(b.text, HoryUI.font.normal, 11, "OUTLINE")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetText(label)
    b.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetTexture(HoryUI.tex.white)
    b.bar:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    b.bar:SetHeight(2)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, -3)
    b.bar:SetPoint("BOTTOMRIGHT", b.text, "BOTTOMRIGHT", 0, -3)
    b.bar:Hide()
    b:SetScript("OnClick", function() ShowSub(key) end)
    b:SetScript("OnEnter", function() if abCurrent ~= key then this.text:SetTextColor(C.text2[1], C.text2[2], C.text2[3]) end end)
    b:SetScript("OnLeave", function() if abCurrent ~= key then this.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3]) end end)
    abSub[key] = b
    return b
  end
  -- (Profiles live in the General tab now -- it captures the whole UI incl. bars.)
  MakeSub("Global", "global", 2, 44)
  MakeSub("Bars", "bars", 56, 32)
  MakeSub("Paging", "paging", 100, 44)

  local abRule = abars:CreateTexture(nil, "ARTWORK")
  abRule:SetTexture(HoryUI.tex.white)
  abRule:SetVertexColor(C.border_soft[1], C.border_soft[2], C.border_soft[3], 0.9)
  abRule:SetHeight(1)
  abRule:SetPoint("TOPLEFT", abars, "TOPLEFT", 2, -22)
  abRule:SetPoint("TOPRIGHT", abars, "TOPRIGHT", -2, -22)

  local function MakeSubPanel()
    local p = CreateFrame("Frame", nil, abars)
    p:SetPoint("TOPLEFT", abars, "TOPLEFT", 2, -30)
    p:SetPoint("BOTTOMRIGHT", abars, "BOTTOMRIGHT", -2, 2)
    p:Hide()
    return p
  end
  local pGlobal, pBars, pPaging = MakeSubPanel(), MakeSubPanel(), MakeSubPanel()

  -- ---- Global ----  (two columns of checkboxes + dropdowns + slider + swatch)
  -- get closures are nil-safe: CreateCheckbox calls get() at BUILD time (during
  -- HoryUI:Init), but the Bongos engine may populate BActionSets a frame later.
  local function ag() return BActionSets and BActionSets.g end          -- engine ready?
  local gChecks = {
    { "Sticky bars",        function() return BongosSets and BongosSets.sticky end,        function(v) Bongos_SetStickyBars(v) end },
    { "Lock buttons",       function() return ag() and BActionSets_ButtonsLocked() end,    function(v) BActionSets_SetButtonsLocked(v) end },
    { "Show empty slots",   function() return ag() and BActionSets_ShowGrid() end,         function(v) BActionSets_SetShowGrid(v) end },
    { "Show tooltips",      function() return ag() and BActionSets_TooltipsShown() end,    function(v) BActionSets_SetTooltips(v) end },
    { "Range coloring",     function() return ag() and BActionSets_ColorOutOfRange() end,  function(v) BActionSets_SetColorOutOfRange(v) end },
    { "Hotkey text",        function() return ag() and BActionSets_HotkeysShown() end,     function(v) BActionSets_SetHotkeys(v) end },
    { "Macro text",         function() return ag() and BActionSets_MacrosShown() end,      function(v) BActionSets_SetMacroText(v) end },
    { "RMB self-cast",      function() return ag() and BActionSets_RightClickSelfCasts() end, function(v) BActionSets_SetRightClickSelfCast(v) end },
  }
  local gCheckObjs = {}
  for i = 1, getn(gChecks) do
    local c = gChecks[i]
    local chk = HoryUI.CreateCheckbox(pGlobal, c[1], c[2], c[3])
    chk:SetWidth(126)
    local col = (i <= 5) and 0 or 1
    local rowi = (i <= 5) and (i - 1) or (i - 6)
    chk:SetPoint("TOPLEFT", pGlobal, "TOPLEFT", col * 132, -rowi * 18)
    gCheckObjs[i] = chk
  end

  local scDD = HoryUI.CreateDropDown(pGlobal, 150, {
    { text = "Self-cast: None", value = 0 }, { text = "Self-cast: Alt", value = 1 },
    { text = "Self-cast: Ctrl", value = 2 }, { text = "Self-cast: Shift", value = 3 },
  }, function(v) BActionSets_SetSelfCastMode((v ~= 0) and v or nil) end)
  scDD:SetPoint("TOPLEFT", pGlobal, "TOPLEFT", 0, -98)

  local qmDD = HoryUI.CreateDropDown(pGlobal, 150, {
    { text = "Quick-move: None", value = 0 }, { text = "Quick-move: Shift", value = 1 },
    { text = "Quick-move: Ctrl", value = 2 }, { text = "Quick-move: Alt", value = 3 },
  }, function(v) BActionSets_SetQuickMoveMode((v ~= 0) and v or nil) end)
  qmDD:SetPoint("TOPLEFT", pGlobal, "TOPLEFT", 0, -120)

  local swatch = CreateFrame("Button", nil, pGlobal)
  swatch:SetWidth(16); swatch:SetHeight(16)
  swatch:SetPoint("TOPLEFT", pGlobal, "TOPLEFT", 168, -120)
  HoryUI.CreateBackdrop(swatch)
  swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
  swatch.tex:SetTexture(HoryUI.tex.white)
  swatch.tex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
  swatch.tex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
  local swatchLbl = pGlobal:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(swatchLbl, HoryUI.font.normal, 10, "OUTLINE")
  swatchLbl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
  swatchLbl:SetText("Range color")
  swatchLbl:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
  swatch:SetScript("OnClick", function()
    local r, g, b = BActionSets_GetRangeColor()
    r = r or 1; g = g or 0.5; b = b or 0.5
    ColorPickerFrame.func = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      BActionSets_SetRangeColor(nr, ng, nb); swatch.tex:SetVertexColor(nr, ng, nb)
    end
    ColorPickerFrame.cancelFunc = function()
      local p = ColorPickerFrame.previousValues
      BActionSets_SetRangeColor(p.r, p.g, p.b); swatch.tex:SetVertexColor(p.r, p.g, p.b)
    end
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame:SetColorRGB(r, g, b)
    ShowUIPanel(ColorPickerFrame)
  end)

  -- Hover-to-bind keybind mode (Bongos hoverbind). Closes the settings window so
  -- the bars are clickable, then shows the keybind overlay over every button.
  local kbBtn = HoryUI.CreateButton(pGlobal, "Enter keybind mode", function()
    if not Bongos_ToggleKeyBindMode then return end
    win:Hide()
    Bongos_ToggleKeyBindMode()
  end)
  kbBtn:SetWidth(150)
  kbBtn:SetPoint("TOPLEFT", pGlobal, "TOPLEFT", 0, -150)
  local kbNote = pGlobal:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(kbNote, HoryUI.font.normal, 10, "OUTLINE")
  kbNote:SetPoint("TOPLEFT", kbBtn, "BOTTOMLEFT", 0, -4)
  kbNote:SetWidth(260); kbNote:SetJustifyH("LEFT")
  kbNote:SetText("Hover a button and press a key to bind it. Esc on a button clears it; Esc on empty space exits.")
  kbNote:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

  local function RefreshGlobal()
    for i = 1, getn(gCheckObjs) do gCheckObjs[i].Refresh() end
    scDD.SetValue(BActionSets_GetSelfCastMode() or 0)
    qmDD.SetValue(BActionSets_GetQuickMoveMode() or 0)
    local r, g, b = BActionSets_GetRangeColor()
    swatch.tex:SetVertexColor(r or 1, g or 0.5, b or 0.5)
  end

  -- ---- Bars ----  (per-bar show/hide)
  local barData = {}
  local barList = HoryUI.CreateScrollFrame(pBars, 264, 11, 23)
  barList:SetPoint("TOPLEFT", pBars, "TOPLEFT", 0, -2)
  barList.OnUpdateRow = function(row, idx)
    local d = barData[idx]
    row.label:SetText(d.label)
    local bar = BBar.IDToBar(d.id)
    row.SetOn(bar and bar:IsShown() and true or false)
  end
  barList.OnClickRow = function(idx)
    local bar = BBar.IDToBar(barData[idx].id)
    if bar then BBar.Toggle(bar, 1); barList.Update() end
  end
  local function RefreshBars()
    barData = {}
    for i = 1, BActionBar.GetNumber() do tinsert(barData, { id = i, label = "Action Bar " .. i }) end
    tinsert(barData, { id = "pet",   label = "Pet Bar" })
    tinsert(barData, { id = "class", label = "Class Bar" })
    tinsert(barData, { id = "bags",  label = "Bag Bar" })
    tinsert(barData, { id = "menu",  label = "Menu Bar" })
    tinsert(barData, { id = "key",   label = "Key Bar" })
    barList.SetTotal(getn(barData))
  end

  -- ---- Paging ----  (per-bar manual paging + page-skip; stance uses defaults)
  local pageData = {}
  local pageList = HoryUI.CreateScrollFrame(pPaging, 264, 7, 23)
  pageList:SetPoint("TOPLEFT", pPaging, "TOPLEFT", 0, -2)
  pageList.OnUpdateRow = function(row, idx)
    row.label:SetText("Action Bar " .. pageData[idx])
    row.SetOn(BActionBar.CanPage(pageData[idx]) and true or false)
  end
  pageList.OnClickRow = function(idx)
    local id = pageData[idx]
    BActionBar.SetPaging(id, not BActionBar.CanPage(id))
    pageList.Update()
  end
  local skipSlider = HoryUI.CreateSlider(pPaging, 240)
  skipSlider:SetPoint("TOPLEFT", pPaging, "TOPLEFT", 0, -172)
  local pageNote = pPaging:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(pageNote, HoryUI.font.normal, 10, "OUTLINE")
  pageNote:SetPoint("TOPLEFT", pPaging, "TOPLEFT", 0, -206)
  pageNote:SetWidth(260); pageNote:SetJustifyH("LEFT")
  pageNote:SetText("Stance / stealth paging follows Bongos defaults automatically.")
  pageNote:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
  local function RefreshPaging()
    pageData = {}
    for i = 1, BActionBar.GetNumber() do tinsert(pageData, i) end
    pageList.SetTotal(getn(pageData))
    if BActionSets and BActionSets.g then BActionSets.g.skip = BActionSets.g.skip or 0 end
    skipSlider.Configure("Page skip", 0, 10, 1, (BActionSets.g.skip or 0),
      function(v) BActionSets.g.skip = v end)
  end

  ShowSub = function(key)
    abCurrent = key
    for k, b in pairs(abSub) do
      if k == key then b.bar:Show(); b.text:SetTextColor(C.text[1], C.text[2], C.text[3])
      else b.bar:Hide(); b.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3]) end
    end
    pGlobal:Hide(); pBars:Hide(); pPaging:Hide()
    if key == "global" then RefreshGlobal(); pGlobal:Show()
    elseif key == "bars" then RefreshBars(); pBars:Show()
    elseif key == "paging" then RefreshPaging(); pPaging:Show() end
  end

  -- =========================================================================
  -- footer
  -- =========================================================================
  local fdiv = win:CreateTexture(nil, "ARTWORK")
  fdiv:SetTexture(HoryUI.tex.white)
  fdiv:SetVertexColor(0.16, 0.17, 0.19, 0.9)
  fdiv:SetHeight(1)
  fdiv:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 34)
  fdiv:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 34)

  local auth = (GetAddOnMetadata and GetAddOnMetadata("!HoryUI", "Author")) or "Horyoshi"
  local footer = win:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(footer, HoryUI.font.normal, 10, "OUTLINE")
  footer:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 12)
  footer:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
  footer:SetText("HoryUI v" .. (ver or "?") .. "   -   by " .. (auth or "?"))

  local reload = HoryUI.CreateButton(win, "Reload UI", function() ReloadUI() end)
  reload:SetWidth(90)
  reload:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 9)

  -- =========================================================================
  -- tab switching
  -- =========================================================================
  win.tab = "general"
  ShowTab = function(which)
    win.tab = which
    general:Hide(); modList:Hide(); addonList:Hide(); pfui:Hide(); loadtab:Hide(); abars:Hide()
    HLNav(navGeneral, which == "general")
    HLNav(navMods, which == "modules")
    HLNav(navAddons, which == "addons")
    HLNav(navPfui, which == "pfui")
    HLNav(navLoad, which == "loadtimes")
    HLNav(navAbars, which == "actionbars")
    if which == "modules" then
      modList:Show(); modList.SetTotal(getn(mods))
    elseif which == "addons" then
      addonList:Show(); addonList.SetTotal(GetNumAddOns())
    elseif which == "pfui" then
      pfui:Show()
    elseif which == "loadtimes" then
      RefreshLoad(); loadtab:Show()
    elseif which == "actionbars" then
      -- dormant (standalone Bongos still on) or the engine isn't ready: show a note.
      -- (BActionBar exists at file-load; BActionSets.g is only populated at the
      -- engine's PLAYER_LOGIN startup -- so gate on the data, not the table.)
      if HoryUI._bongosActive or not (BActionBar and BActionSets and BActionSets.g) then
        if HoryUI._bongosActive then
          abDormant:SetText("The standalone Bongos addon is enabled, so HoryUI's action bars are dormant. Disable Bongos in the Addons tab and reload to use them here.")
        else
          abDormant:SetText("The action bar engine isn't loaded.")
        end
        abDormant:Show(); abRule:Hide()
        for k, b in pairs(abSub) do b:Hide() end
        pGlobal:Hide(); pBars:Hide(); pPaging:Hide()
      else
        abDormant:Hide(); abRule:Show()
        for k, b in pairs(abSub) do b:Show() end
        ShowSub(abCurrent)
      end
      abars:Show()
    else
      RefreshHProf(); general:Show()
    end
  end

  win:SetScript("OnShow", function()
    if unlock.Refresh then unlock.Refresh() end
    if skin.Refresh then skin.Refresh() end
    if plates.Refresh then plates.Refresh() end
    ShowTab(this.tab)
  end)

  win:Hide()

  HoryUI.configFrame = win
  function HoryUI.ToggleConfig()
    if win:IsShown() then win:Hide() else win:Show() end
  end
end)
