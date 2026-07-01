-- HoryUI :: Character panel (full rebuild) -- replaces Blizzard's CharacterFrame
-- entirely with a native HoryUI window. Nothing Blizzard/Turtle-original shows:
--   * Character tab REPARENTS the native equipment slots + 3D model (so equip /
--     drag / tooltip / cooldown stay native) and REBUILDS the stat block from
--     scratch via UnitStat/UnitArmor/UnitResistance/... (Blizzard's stat frames
--     are never shown).
--   * Reputation / Skills / PvP are rebuilt from the same game data APIs.
-- Architecture mirrors the one-bag (modules/bags.lua): one window, reparent the
-- interactive pieces, hook the Blizzard openers, hide the original frame.
-- Lua 5.0 / WoW 1.12 -- handlers use this/event/arg1. See CLAUDE.md.

HoryUI:RegisterModule("character", true, function()
  if HoryUI.charBuilt then return end
  HoryUI.charBuilt = true

  local C = HoryUI.color
  local getn = table.getn
  local format, floor, ceil, mmax = string.format, math.floor, math.ceil, math.max

  -- ---- layout constants (one place to tune spacing) ----------------------
  local W, H   = 368, 478
  local PAD    = 10
  local SLOT   = 30
  local SGAP   = 4
  local STEP   = SLOT + SGAP          -- vertical slot pitch (34)
  local NAVW   = 88                   -- left category-nav width
  local CONX   = 108                  -- content left edge (right of nav + divider)
  local cW     = W - CONX - PAD       -- character content width

  -- forward declarations (ShowTab + the driver reference these before they're set)
  local ShowTab
  local RefreshStats, RefreshRep, RefreshSkills, RefreshPvP
  local RefreshHeader, RefreshSlots
  local model            -- the reparented 3D model (Show/Hide explicitly per tab)

  -- =========================================================================
  -- window
  -- =========================================================================
  local win = CreateFrame("Frame", "HoryUICharacter", UIParent)
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
  tinsert(UISpecialFrames, "HoryUICharacter")   -- Esc closes
  win:Hide()
  HoryUI.characterFrame = win

  -- header: name + level/race/class + garnet rule
  local nameFS = win:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(nameFS, HoryUI.font.normal, 15, "OUTLINE")
  nameFS:SetPoint("TOP", win, "TOP", 0, -10)
  nameFS:SetTextColor(C.text[1], C.text[2], C.text[3])

  local subFS = win:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(subFS, HoryUI.font.normal, 11, "OUTLINE")
  subFS:SetPoint("TOP", nameFS, "BOTTOM", 0, -2)
  subFS:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

  HoryUI.TitleRule(win, -44)

  local close = HoryUI.CreateButton(win, "x", function() win:Hide() end)
  close:SetWidth(18); close:SetHeight(18)
  close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -6, -6)

  RefreshHeader = function()
    nameFS:SetText(UnitName("player") or "")
    local lvl = UnitLevel("player") or 0
    local race = UnitRace("player") or ""
    local class = UnitClass("player") or ""
    subFS:SetText("Level " .. lvl .. " " .. race .. " " .. class)
  end

  -- =========================================================================
  -- tab strip (custom, built from scratch -- flat + garnet active-underline)
  -- =========================================================================
  local tabKeys   = { "char", "rep", "skill", "pvp" }
  local tabLabels = { char = "Character", rep = "Reputation", skill = "Skills", pvp = "PvP" }
  local tabs    = {}
  local content = {}
  local current

  -- left vertical nav (same language as the settings window): a garnet left-bar
  -- marks the active tab; text goes muted -> primary.
  local function MakeTab(key, i)
    local b = CreateFrame("Button", nil, win)
    b:SetWidth(NAVW); b:SetHeight(24)
    b:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -54 - (i - 1) * 28)

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
    b.text:SetText(tabLabels[key])
    b.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

    b:SetScript("OnClick", function() ShowTab(key) end)
    b:SetScript("OnEnter", function()
      if current ~= key then b.text:SetTextColor(C.text2[1], C.text2[2], C.text2[3]) end
    end)
    b:SetScript("OnLeave", function()
      if current ~= key then b.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3]) end
    end)
    tabs[key] = b
  end

  -- one content frame per tab, filling the area to the right of the nav
  local function MakeContent(key)
    local f = CreateFrame("Frame", nil, win)
    f:SetPoint("TOPLEFT", win, "TOPLEFT", CONX, -52)
    f:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, PAD)
    f:Hide()
    content[key] = f
    return f
  end

  for i = 1, getn(tabKeys) do MakeTab(tabKeys[i], i) end
  local charContent  = MakeContent("char")
  local repContent   = MakeContent("rep")
  local skillContent = MakeContent("skill")
  local pvpContent   = MakeContent("pvp")

  -- vertical divider between the nav and the content (settings-window language)
  local vdiv = win:CreateTexture(nil, "ARTWORK")
  vdiv:SetTexture(HoryUI.tex.white)
  vdiv:SetVertexColor(0.16, 0.17, 0.19, 0.9)
  vdiv:SetWidth(1)
  vdiv:SetPoint("TOPLEFT", win, "TOPLEFT", NAVW + 14, -52)
  vdiv:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", NAVW + 14, PAD + 2)

  ShowTab = function(key)
    current = key
    for i = 1, getn(tabKeys) do
      local k = tabKeys[i]
      if content[k] then if k == key then content[k]:Show() else content[k]:Hide() end end
      local t = tabs[k]
      if t then
        if k == key then
          t.bar:Show(); t.text:SetTextColor(C.text[1], C.text[2], C.text[3])
        else
          t.bar:Hide(); t.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
        end
      end
    end
    -- 3D models keep rendering when only their parent is hidden -> Hide explicitly
    if model then if key == "char" then model:Show() else model:Hide() end end
    if key == "char"  and RefreshStats  then RefreshStats()  end
    if key == "char"  and RefreshSlots  then RefreshSlots()  end
    if key == "rep"   and RefreshRep    then RefreshRep()    end
    if key == "skill" and RefreshSkills then RefreshSkills() end
    if key == "pvp"   and RefreshPvP    then RefreshPvP()    end
  end

  -- =========================================================================
  -- CHARACTER TAB : reparent slots + model, rebuilt stat block
  -- =========================================================================
  local leftSlots  = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
  local rightSlots = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }
  local weaponSlots = { "MainHand", "SecondaryHand", "Ranged" }   -- ammo placed separately (half size)

  local allSlots = {}    -- reparented equipment buttons (for the quality-border refresh)

  -- colour a slot's border by the equipped item's quality (uncommon+), else black.
  -- 1.12 exposes no reliable GetInventoryItemQuality, so read the link and resolve
  -- via GetItemInfo (equipped items are always cached).
  -- colour a slot border from the equipped item LINK's quality hex (|cffRRGGBB) --
  -- reliable on Turtle (GetInventoryItemQuality/GetItemInfo quality are flaky). Only
  -- uncommon+ get a colour; common/poor/empty keep the plain dark border.
  local function PaintSlotQuality(b)
    if not b or not b.backdrop then return end
    local r, g, bl
    local link = GetInventoryItemLink("player", b:GetID())
    if link then
      local _, _, hex = string.find(link, "|c%x%x(%x%x%x%x%x%x)")
      if hex then
        hex = string.lower(hex)
        if hex ~= "ffffff" and hex ~= "9d9d9d" then
          r  = tonumber(string.sub(hex, 1, 2), 16) / 255
          g  = tonumber(string.sub(hex, 3, 4), 16) / 255
          bl = tonumber(string.sub(hex, 5, 6), 16) / 255
        end
      end
    end
    if r then b.backdrop:SetBackdropBorderColor(r, g, bl, 1)
    else b.backdrop:SetBackdropBorderColor(0, 0, 0, 1) end
  end

  local function reparentSlot(suffix, point, x, y)
    local b = getglobal("Character" .. suffix .. "Slot")
    if not b then return end
    b:SetParent(charContent)
    b:ClearAllPoints()
    b:SetPoint(point, charContent, point, x, y)
    b:SetWidth(SLOT); b:SetHeight(SLOT)
    HoryUI.SkinItemButton(b)
    PaintSlotQuality(b)
    allSlots[getn(allSlots) + 1] = b
    b:Show()
  end

  for i = 1, getn(leftSlots) do
    reparentSlot(leftSlots[i], "TOPLEFT", 0, -(i - 1) * STEP)
  end
  for i = 1, getn(rightSlots) do
    reparentSlot(rightSlots[i], "TOPRIGHT", 0, -(i - 1) * STEP)
  end
  -- weapons row: the 3 weapon slots + a half-size ammo slot to their right, the
  -- whole group centred under the content.
  local AMMO = SLOT / 2
  local wRowW = 3 * SLOT + 2 * SGAP + SGAP + AMMO     -- 3 weapons + gap + half ammo
  local wStart = (cW - wRowW) / 2
  for i = 1, getn(weaponSlots) do
    reparentSlot(weaponSlots[i], "TOPLEFT", wStart + (i - 1) * STEP, -266)
  end
  -- ammo: half size, vertically centred on the row, just right of the ranged slot
  local ammoBtn, rangedBtn = getglobal("CharacterAmmoSlot"), getglobal("CharacterRangedSlot")
  if ammoBtn and rangedBtn then
    ammoBtn:SetParent(charContent)
    ammoBtn:ClearAllPoints()
    ammoBtn:SetWidth(AMMO); ammoBtn:SetHeight(AMMO)
    ammoBtn:SetPoint("LEFT", rangedBtn, "RIGHT", SGAP, 0)
    HoryUI.SkinItemButton(ammoBtn)
    PaintSlotQuality(ammoBtn)
    allSlots[getn(allSlots) + 1] = ammoBtn
    ammoBtn:Show()
  end
  -- re-skin + re-colour the quality border after Blizzard repaints a slot
  HoryUI.HookFunc("PaperDollItemSlotButton_Update", function()
    if this and this.horySlot then HoryUI.SkinItemButton(this); PaintSlotQuality(this) end
  end)

  RefreshSlots = function()
    for i = 1, getn(allSlots) do
      HoryUI.SkinItemButton(allSlots[i])
      PaintSlotQuality(allSlots[i])
    end
  end

  -- 3D model (reparented native CharacterModelFrame). A PlayerModel's APPARENT size
  -- is driven by SetModelScale -- the frame only CLIPS it, which is why every earlier
  -- frame-resize did nothing. So we (a) widen the frame to sit BEHIND the equipment
  -- columns (native-paperdoll style, so the whole character is visible, not a clipped
  -- strip) with its frame level dropped below the slots, and (b) SetModelScale to zoom.
  model = CharacterModelFrame
  if model then
    model:SetParent(charContent)
    model:ClearAllPoints()
    model:SetPoint("TOPLEFT", charContent, "TOPLEFT", 0, -2)
    model:SetWidth(218); model:SetHeight(258)
    model:SetFrameLevel(charContent:GetFrameLevel() + 1)   -- behind the columns
    if model.SetUnit then model:SetUnit("player") end
    if model.SetModelScale then pcall(model.SetModelScale, model, 1.3) end
    model:Show()
    if CharacterModelFrameRotateLeftButton then CharacterModelFrameRotateLeftButton:Hide() end
    if CharacterModelFrameRotateRightButton then CharacterModelFrameRotateRightButton:Hide() end
    -- drag to rotate (preserve any existing OnUpdate for animation)
    model.facing = 0
    model:EnableMouse(true)
    local oldOU = model:GetScript("OnUpdate")
    model:SetScript("OnMouseDown", function() this.rotating = true; this.lastX = nil end)
    model:SetScript("OnMouseUp", function() this.rotating = false end)
    model:SetScript("OnUpdate", function()
      if oldOU then oldOU() end
      if this.rotating then
        local x = GetCursorPosition()
        if this.lastX and this.SetFacing then
          this.facing = this.facing + (x - this.lastX) * 0.02
          this:SetFacing(this.facing)
        end
        this.lastX = x
      end
    end)
    -- keep the equipment columns on top of the (now wider) model
    local lvl = charContent:GetFrameLevel() + 6
    for i = 1, getn(allSlots) do allSlots[i]:SetFrameLevel(lvl) end
  end

  -- ---- resistances : a vertical column of 5 school icons right of the 3D
  -- model. The value sits INSIDE each (bigger) icon and hovering shows the
  -- Blizzard resistance tooltip (name + level rating, recipe from FrameXML
  -- PaperDollFrame_SetResistances). ----------------------------------------
  local RES_TEX = "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons"
  local RES = {                                  -- atlas TexCoord bands (from FrameXML)
    { id = 2, c = { 0, 1, 0,          0.11328125 } },  -- Fire
    { id = 3, c = { 0, 1, 0.11328125, 0.2265625  } },  -- Nature
    { id = 4, c = { 0, 1, 0.33984375, 0.453125   } },  -- Frost
    { id = 5, c = { 0, 1, 0.453125,   0.56640625 } },  -- Shadow
    { id = 6, c = { 0, 1, 0.2265625,  0.33984375 } },  -- Arcane
  }
  local RES_SIZE = 28
  -- OnEnter: rebuild Blizzard's resistance tooltip from live values
  local function resTooltip()
    local id = this.resId
    local _, res = UnitResistance("player", id)
    res = res or 0
    local rname = getglobal("RESISTANCE" .. id .. "_NAME") or ""
    local lvl = UnitLevel("player"); if lvl < 20 then lvl = 20 end
    local ratio = res / lvl
    local band
    if ratio > 5 then band = RESISTANCE_EXCELLENT
    elseif ratio > 3.75 then band = RESISTANCE_VERYGOOD
    elseif ratio > 2.5 then band = RESISTANCE_GOOD
    elseif ratio > 1.25 then band = RESISTANCE_FAIR
    elseif ratio > 0 then band = RESISTANCE_POOR
    else band = RESISTANCE_NONE end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(rname .. " " .. RESISTANCE_LABEL .. " " .. res, 1, 1, 1)
    GameTooltip:AddLine(format(RESISTANCE_TOOLTIP_SUBTEXT, rname, lvl, band),
      NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1)
    GameTooltip:Show()
  end
  local resCells = {}
  for i = 1, 5 do
    local cell = CreateFrame("Frame", nil, charContent)
    cell:SetWidth(RES_SIZE); cell:SetHeight(RES_SIZE)
    -- snug against the right equipment column (cW - rightcol 30 - gap 4 - size)
    cell:SetPoint("TOPLEFT", charContent, "TOPLEFT", cW - 34 - RES_SIZE, -6 - (i - 1) * (RES_SIZE + 4))
    cell:EnableMouse(true)
    cell.resId = RES[i].id
    cell:SetFrameLevel(charContent:GetFrameLevel() + 6)   -- above the (wider) model
    HoryUI.CreateBackdrop(cell)
    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(RES_TEX)
    local cc = RES[i].c
    icon:SetTexCoord(cc[1], cc[2], cc[3], cc[4])
    icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    -- value at the bottom-right of the icon (like a stack count)
    local v = cell:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(v, HoryUI.font.number, 11, "OUTLINE")
    v:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    v:SetTextColor(C.text[1], C.text[2], C.text[3])
    cell:SetScript("OnEnter", resTooltip)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    resCells[i] = v
  end

  -- ---- stats : two columns, each a category dropdown + rows ----------------
  -- Driven by BetterCharacterStats getters when present (crit/hit/dodge/spell/...)
  -- with vanilla fallbacks; "-" when a value needs BCS and it isn't installed.
  -- Mirrors BCS's category dropdowns in HoryUI style. BCS gates its own updates
  -- on PaperDollFrame visibility (which we hide), so we drive BCS:RunScans ourselves.
  local function pct(v) if not v then return "-" end return format("%.1f", v) .. "%" end
  local function vstat(i) local _, e = UnitStat("player", i); return e or 0 end
  local function ap() local b, p, nn = UnitAttackPower("player"); return (b or 0) + (p or 0) + (nn or 0) end
  local function armor() local _, a = UnitArmor("player"); return a or 0 end
  local function dmg()
    local minD, maxD, _, _, bp, bn, pc = UnitDamage("player")
    if not minD then return "-" end
    local base = (minD + maxD) * 0.5
    local tb = (base + (bp or 0) + (bn or 0)) * (pc or 1) - base
    return mmax(floor(minD + tb), 1) .. " - " .. mmax(ceil(maxD + tb), 1)
  end
  -- guarded BCS getter (cross-addon boundary -> pcall, "-" on absence/error)
  local function bcsv(method, a1)
    if not BCS or not BCS[method] then return "-" end
    local ok, v = pcall(BCS[method], BCS, a1)
    if ok and v then return v end
    return "-"
  end
  local function bcspct(method, a1)
    if not BCS or not BCS[method] then return "-" end
    local ok, v = pcall(BCS[method], BCS, a1)
    if ok and v then return pct(v) end
    return "-"
  end

  local STAT_CATS = {
    { name = "Base Stats", rows = {
      { "Strength", function() return vstat(1) end }, { "Agility", function() return vstat(2) end },
      { "Stamina", function() return vstat(3) end }, { "Intellect", function() return vstat(4) end },
      { "Spirit", function() return vstat(5) end }, { "Armor", armor },
    } },
    { name = "Melee", rows = {
      { "Attack Power", ap }, { "Damage", dmg },
      { "Speed", function() local s = UnitAttackSpeed("player"); return s and format("%.1f", s) or "-" end },
      { "Hit", function() return bcspct("GetHitRating") end },
      { "Crit", function() return bcspct("GetCritChance") end },
      { "Weapon Skill", function() return bcsv("GetMHWeaponSkill") end },
    } },
    { name = "Ranged", rows = {
      { "Attack Power", function() local b = UnitRangedAttackPower("player"); return b or "-" end },
      { "Hit", function() return bcspct("GetRangedHitRating") end },
      { "Crit", function() return bcspct("GetRangedCritChance") end },
    } },
    { name = "Spell", rows = {
      { "Spell Power", function() return bcsv("GetSpellPower") end },
      { "Hit", function() return bcspct("GetSpellHitRating") end },
      { "Crit", function() return bcspct("GetSpellCritChance") end },
      { "Healing", function() return bcsv("GetHealingPower") end },
    } },
    { name = "Defense", rows = {
      { "Armor", armor }, { "Defense", function() return UnitDefense("player") or 0 end },
      { "Dodge", function() return bcspct("GetEffectiveDodgeChance", 0) end },
      { "Parry", function() return bcspct("GetEffectiveParryChance", 0) end },
      { "Block", function() return bcspct("GetEffectiveBlockChance", 0) end },
    } },
  }

  local STAT_ROWS = 6
  local colW2 = cW / 2
  local statTop = -300
  local statCols = {}
  local function makeRow(x, y)
    local r = CreateFrame("Frame", nil, charContent)
    r:SetWidth(colW2 - 6); r:SetHeight(14)
    r:SetPoint("TOPLEFT", charContent, "TOPLEFT", x, y)
    r.label = r:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(r.label, HoryUI.font.normal, 11, "OUTLINE")
    r.label:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.label:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
    r.val = r:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(r.val, HoryUI.font.number, 11, "OUTLINE")
    r.val:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.val:SetTextColor(C.text[1], C.text[2], C.text[3])
    return r
  end
  local function makeStatCol(idx, x, defCat)
    local col = { cat = defCat, rows = {} }
    for i = 1, STAT_ROWS do col.rows[i] = makeRow(x, statTop - 22 - (i - 1) * 15) end
    col.refresh = function()
      local cat = STAT_CATS[col.cat]
      for i = 1, STAT_ROWS do
        local r, def = col.rows[i], cat.rows[i]
        if def then r.label:SetText(def[1]); r.val:SetText(def[2]()); r:Show() else r:Hide() end
      end
    end
    local opts = {}
    for i = 1, getn(STAT_CATS) do opts[i] = { text = STAT_CATS[i].name, value = i } end
    col.dd = HoryUI.CreateDropDown(charContent, colW2 - 6, opts, function(v) col.cat = v; col.refresh() end)
    col.dd:SetPoint("TOPLEFT", charContent, "TOPLEFT", x, statTop)
    col.dd.SetValue(defCat)
    statCols[idx] = col
  end
  makeStatCol(1, 0, 1)        -- left  -> Base Stats
  makeStatCol(2, colW2, 2)    -- right -> Melee

  local lastScan = 0
  local function RescanBCS()
    if not (BCS and BCS.RunScans) then return end
    local t = GetTime()
    if t - lastScan < 0.25 then return end
    lastScan = t
    pcall(BCS.RunScans, BCS)
  end

  RefreshStats = function()
    if not win:IsShown() then return end
    RescanBCS()
    statCols[1].refresh(); statCols[2].refresh()
    for i = 1, 5 do
      local _, res = UnitResistance("player", RES[i].id)
      resCells[i]:SetText(res or 0)
    end
  end

  -- =========================================================================
  -- shared scrolling list  (name + right value + thin bar + collapsible header)
  -- caller sets sf.OnRow(row, dataIndex) then sf.SetTotal(n)
  -- =========================================================================
  local function MakeListScroll(parent, rowH, visN, buildRow)
    local sf = CreateFrame("Frame", nil, parent)
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    sf.offset = 0; sf.total = 0; sf.rows = {}
    for i = 1, visN do
      local row = CreateFrame("Button", nil, sf)
      row:SetHeight(rowH - 2)
      row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * rowH)
      row:SetPoint("RIGHT", sf, "RIGHT", -10, 0)
      buildRow(row)
      sf.rows[i] = row
    end
    local slider = CreateFrame("Slider", nil, sf)
    slider:SetWidth(8)
    slider:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    slider:SetOrientation("VERTICAL"); slider:SetMinMaxValues(0, 0); slider:SetValueStep(1); slider:SetValue(0)
    HoryUI.CreateBackdrop(slider)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(HoryUI.tex.white)
    thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    thumb:SetWidth(8); thumb:SetHeight(24)
    slider:SetThumbTexture(thumb)
    sf.slider = slider
    sf.Update = function()
      local maxoff = sf.total - visN; if maxoff < 0 then maxoff = 0 end
      if sf.offset > maxoff then sf.offset = maxoff end
      if sf.offset < 0 then sf.offset = 0 end
      for i = 1, visN do
        local row = sf.rows[i]
        local di = sf.offset + i
        if di <= sf.total then row.dataIndex = di; row:Show(); if sf.OnRow then sf.OnRow(row, di) end
        else row.dataIndex = nil; row:Hide() end
      end
    end
    slider:SetScript("OnValueChanged", function() sf.offset = floor(arg1 + 0.5); sf.Update() end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function() slider:SetValue(slider:GetValue() - arg1) end)
    sf.SetTotal = function(t)
      sf.total = t
      local maxoff = t - visN; if maxoff < 0 then maxoff = 0 end
      slider:SetMinMaxValues(0, maxoff)
      if maxoff <= 0 then slider:Hide() else slider:Show() end
      sf.Update()
    end
    return sf
  end

  -- =========================================================================
  -- REPUTATION TAB
  -- =========================================================================
  -- barValue is already a 0..1 fraction (ReputationBarTemplate is minVal/maxVal 0/1).
  local repData = {}

  local repScroll = MakeListScroll(repContent, 24, 15, function(row)
    row.name = row:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(row.name, HoryUI.font.normal, 11, "OUTLINE")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -1)
    row.name:SetJustifyH("LEFT")
    row.stand = row:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(row.stand, HoryUI.font.normal, 10, "OUTLINE")
    row.stand:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
    row.stand:SetJustifyH("RIGHT")
    row.bar = HoryUI.CreateStatusBar(row, C.accent)
    row.bar:SetHeight(3)
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 2)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
    row:SetScript("OnClick", function()
      local d = repData[this.dataIndex]
      if d and d.header then
        -- toggle without trusting isCollapsed (unreliable on Turtle): try expand;
        -- if the visible count didn't grow it was already expanded -> collapse.
        local before = GetNumFactions()
        ExpandFactionHeader(d.index)
        if GetNumFactions() == before then CollapseFactionHeader(d.index) end
        RefreshRep()
      end
    end)
  end)

  repScroll.OnRow = function(row, di)
    local d = repData[di]
    if not d then return end
    if d.header then
      row.name:SetText((d.collapsed and "+ " or "- ") .. (d.name or ""))
      row.name:SetTextColor(C.accent_hi[1], C.accent_hi[2], C.accent_hi[3])
      row.stand:SetText("")
      row.bar:Hide()
    else
      row.name:SetText(d.name or "")
      row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
      row.stand:SetText(getglobal("FACTION_STANDING_LABEL" .. (d.sid or 4)) or "")
      row.stand:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
      row.bar:SetMinMaxValues(d.min or 0, d.max or 1)
      row.bar:SetValue(d.val or 0)
      local col = FACTION_BAR_COLORS and FACTION_BAR_COLORS[d.sid]
      if col then row.bar:SetStatusBarColor(col.r, col.g, col.b, 1) end
      row.bar:Show()
    end
  end

  local repInit = false
  RefreshRep = function()
    if not repInit then           -- first open: expand every header so factions show
      repInit = true
      local i = 1
      while i <= GetNumFactions() do
        local _, _, _, _, _, _, _, _, isH = GetFactionInfo(i)   -- isHeader = field 9
        if isH then ExpandFactionHeader(i) end
        i = i + 1
      end
    end
    local n = GetNumFactions()
    for i = 1, n do
      -- Turtle uses the standard 11-value signature (verified against pfUI/xpbar):
      -- name, description, standingID, barMin, barMax, barValue, atWar, canToggle, isHeader, isCollapsed, isWatched
      local name, _, sid, barMin, barMax, val, _, _, isHeader, isCollapsed = GetFactionInfo(i)
      local d = repData[i] or {}
      d.name = name; d.sid = sid; d.min = barMin; d.max = barMax; d.val = val
      d.header = isHeader; d.collapsed = isCollapsed; d.index = i
      repData[i] = d
    end
    repData[n + 1] = nil          -- boundary so the last row's expand-detection is correct
    repScroll.SetTotal(n)
  end

  -- =========================================================================
  -- SKILLS / PvP  (stubs -- fleshed out below)
  -- =========================================================================
  local function placeholder(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(fs, HoryUI.font.normal, 12, "OUTLINE")
    fs:SetPoint("TOP", parent, "TOP", 0, -20)
    fs:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
    fs:SetText(text)
    return fs
  end
  -- ---- Skills ----
  local skillData = {}
  local skillScroll = MakeListScroll(skillContent, 24, 15, function(row)
    row.name = row:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(row.name, HoryUI.font.normal, 11, "OUTLINE")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -1)
    row.name:SetJustifyH("LEFT")
    row.rank = row:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(row.rank, HoryUI.font.number, 10, "OUTLINE")
    row.rank:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
    row.rank:SetJustifyH("RIGHT")
    row.bar = HoryUI.CreateStatusBar(row, C.energy)
    row.bar:SetHeight(3)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 2)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
    -- Unlearn button -- only shown for abandonable skills (professions). Reuses
    -- the native UNLEARN_SKILL confirmation popup -> AbandonSkill(index).
    row.unlearn = CreateFrame("Button", nil, row)
    row.unlearn:SetWidth(14); row.unlearn:SetHeight(14)
    row.unlearn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
    local ux = row.unlearn:CreateTexture(nil, "ARTWORK")
    ux:SetTexture(HoryUI.tex.white)
    ux:SetAllPoints(row.unlearn)
    ux:SetVertexColor(C.health_low[1], C.health_low[2], C.health_low[3], 0.28)
    row.unlearn.bg = ux
    row.unlearn.x = row.unlearn:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(row.unlearn.x, HoryUI.font.normal, 11, "OUTLINE")
    row.unlearn.x:SetPoint("CENTER", row.unlearn, "CENTER", 0, 0)
    row.unlearn.x:SetText("x")
    row.unlearn.x:SetTextColor(C.health_low[1], C.health_low[2], C.health_low[3])
    row.unlearn:SetScript("OnEnter", function()
      this.bg:SetVertexColor(C.health_low[1], C.health_low[2], C.health_low[3], 0.55)
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(UNLEARN_SKILL_TOOLTIP or "Unlearn")
      GameTooltip:Show()
    end)
    row.unlearn:SetScript("OnLeave", function()
      this.bg:SetVertexColor(C.health_low[1], C.health_low[2], C.health_low[3], 0.28)
      GameTooltip:Hide()
    end)
    row.unlearn:SetScript("OnClick", function()
      if not this.skillIndex then return end
      local dialog = StaticPopup_Show("UNLEARN_SKILL", this.skillName)
      if dialog then dialog.data = this.skillIndex end
    end)
    row.unlearn:Hide()
    row:SetScript("OnClick", function()
      local d = skillData[this.dataIndex]
      if d and d.header then
        if d.expanded then CollapseSkillHeader(d.index) else ExpandSkillHeader(d.index) end
        RefreshSkills()
      end
    end)
  end)

  skillScroll.OnRow = function(row, di)
    local d = skillData[di]
    if not d then return end
    if d.header then
      row.name:SetText((d.expanded and "- " or "+ ") .. (d.name or ""))
      row.name:SetTextColor(C.accent_hi[1], C.accent_hi[2], C.accent_hi[3])
      row.rank:SetText("")
      row.bar:Hide()
      row.unlearn:Hide()
    else
      row.name:SetText(d.name or "")
      row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
      if d.max and d.max > 1 then
        row.rank:SetText(d.rank .. "/" .. d.max)
        row.bar:SetMinMaxValues(0, d.max); row.bar:SetValue(d.rank); row.bar:Show()
      else
        row.rank:SetText("")
        row.bar:Hide()
      end
      row.rank:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
      row.rank:ClearAllPoints()
      if d.abandonable then
        row.unlearn.skillIndex = d.index
        row.unlearn.skillName  = d.name
        row.unlearn:Show()
        row.rank:SetPoint("TOPRIGHT", row.unlearn, "TOPLEFT", -6, 0)
      else
        row.unlearn:Hide()
        row.rank:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
      end
    end
  end

  RefreshSkills = function()
    local n = GetNumSkillLines()
    for i = 1, n do
      local name, header, isExpanded, rank, temp, _, maxRank, isAbandonable = GetSkillLineInfo(i)
      local d = skillData[i] or {}
      d.name = name; d.header = header; d.expanded = isExpanded
      d.rank = (rank or 0) + (temp or 0); d.max = maxRank; d.index = i
      d.abandonable = isAbandonable
      skillData[i] = d
    end
    skillScroll.SetTotal(n)
  end

  -- =========================================================================
  -- PvP / HONOR TAB  (classic honor API -- every call guarded, "-" if absent)
  -- =========================================================================
  local pvpRows = {}

  local rankFS = pvpContent:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(rankFS, HoryUI.font.normal, 14, "OUTLINE")
  rankFS:SetPoint("TOPLEFT", pvpContent, "TOPLEFT", 4, -2)
  rankFS:SetTextColor(C.accent_hi[1], C.accent_hi[2], C.accent_hi[3])

  local rankBar = HoryUI.CreateStatusBar(pvpContent, C.accent)
  rankBar:SetHeight(4)
  rankBar:SetPoint("TOPLEFT", pvpContent, "TOPLEFT", 4, -24)
  rankBar:SetPoint("TOPRIGHT", pvpContent, "TOPRIGHT", -4, -24)
  rankBar:SetMinMaxValues(0, 1)

  local yoff = -36
  local function pvpHeader(label)
    local h = pvpContent:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(h, HoryUI.font.normal, 12, "OUTLINE")
    h:SetPoint("TOPLEFT", pvpContent, "TOPLEFT", 2, yoff)
    h:SetText(label)
    h:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
    yoff = yoff - 18
  end
  local function pvpRow(key, label)
    local l = pvpContent:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(l, HoryUI.font.normal, 11, "OUTLINE")
    l:SetPoint("TOPLEFT", pvpContent, "TOPLEFT", 14, yoff)
    l:SetText(label)
    l:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
    local v = pvpContent:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(v, HoryUI.font.number, 11, "OUTLINE")
    v:SetPoint("TOPRIGHT", pvpContent, "TOPRIGHT", -4, yoff)
    v:SetTextColor(C.text[1], C.text[2], C.text[3])
    pvpRows[key] = v
    yoff = yoff - 16
  end

  pvpHeader("Today");      pvpRow("todayHK", "Honorable Kills");    pvpRow("todayDK", "Dishonorable Kills")
  pvpHeader("Yesterday");  pvpRow("ydHK", "Honorable Kills");       pvpRow("ydHonor", "Honor")
  pvpHeader("This Week");  pvpRow("twHK", "Honorable Kills");       pvpRow("twHonor", "Honor")
  pvpHeader("Last Week");  pvpRow("lwHK", "Honorable Kills");       pvpRow("lwHonor", "Honor"); pvpRow("lwStanding", "Standing")
  pvpHeader("Lifetime");   pvpRow("ltHK", "Honorable Kills");       pvpRow("ltDK", "Dishonorable Kills"); pvpRow("ltRank", "Highest Rank")

  RefreshPvP = function()
    local function set(key, v) if pvpRows[key] then pvpRows[key]:SetText(v ~= nil and v or "-") end end
    local rank = UnitPVPRank and UnitPVPRank("player")
    local rankName, rankNum
    if GetPVPRankInfo and rank then rankName, rankNum = GetPVPRankInfo(rank) end
    rankFS:SetText((rankName or "None") .. "   (Rank " .. (rankNum or 0) .. ")")
    if GetPVPRankProgress then rankBar:SetValue(GetPVPRankProgress() or 0) else rankBar:SetValue(0) end

    if GetPVPSessionStats then local hk, dk = GetPVPSessionStats(); set("todayHK", hk); set("todayDK", dk) end
    if GetPVPYesterdayStats then local hk, h = GetPVPYesterdayStats(); set("ydHK", hk); set("ydHonor", h) end
    if GetPVPThisWeekStats then local hk, h = GetPVPThisWeekStats(); set("twHK", hk); set("twHonor", h) end
    if GetPVPLastWeekStats then local hk, h, st = GetPVPLastWeekStats(); set("lwHK", hk); set("lwHonor", h); set("lwStanding", st) end
    if GetPVPLifetimeStats then
      local hk, dk, hr = GetPVPLifetimeStats()
      set("ltHK", hk); set("ltDK", dk)
      local hrName = (hr and GetPVPRankInfo and GetPVPRankInfo(hr)) or "None"
      set("ltRank", hrName)
    end
  end

  -- =========================================================================
  -- hooks : route the Blizzard openers to our window, hide CharacterFrame
  -- =========================================================================
  HoryUI.charOrig = HoryUI.charOrig or {}
  HoryUI.charOrig.ToggleCharacter = ToggleCharacter
  ToggleCharacter = function(tab)
    local key = "char"
    if tab == "ReputationFrame" then key = "rep"
    elseif tab == "SkillFrame" then key = "skill"
    elseif tab == "PVPFrame" then key = "pvp" end
    if win:IsShown() and current == key then
      win:Hide()
    else
      win:Show(); ShowTab(key)
    end
  end

  -- suppress Blizzard's CharacterFrame (we've reparented its slots + model out)
  if CharacterFrame then
    CharacterFrame:UnregisterAllEvents()
    CharacterFrame:Hide()
    CharacterFrame:SetScript("OnShow", function() this:Hide() end)
  end

  -- =========================================================================
  -- event driver : keep the visible tab + header fresh; defuse on logout
  -- =========================================================================
  local driver = CreateFrame("Frame")
  driver:RegisterEvent("PLAYER_LOGIN")
  driver:RegisterEvent("PLAYER_LOGOUT")
  driver:RegisterEvent("UNIT_INVENTORY_CHANGED")
  driver:RegisterEvent("UNIT_STATS")
  driver:RegisterEvent("UNIT_RESISTANCES")
  driver:RegisterEvent("UNIT_DAMAGE")
  driver:RegisterEvent("UNIT_ATTACK_POWER")
  driver:RegisterEvent("UNIT_ATTACK")
  driver:RegisterEvent("PLAYER_LEVEL_UP")
  driver:RegisterEvent("UNIT_NAME_UPDATE")
  driver:RegisterEvent("UPDATE_FACTION")
  driver:RegisterEvent("SKILL_LINES_CHANGED")
  driver:RegisterEvent("CHARACTER_POINTS_CHANGED")
  driver:RegisterEvent("PLAYER_AURAS_CHANGED")
  driver:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      if model then model:SetScript("OnUpdate", nil) end
      return
    end
    if not win:IsShown() then
      if event == "PLAYER_LOGIN" then RefreshHeader() end
      return
    end
    if event == "UNIT_NAME_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_LOGIN" then
      RefreshHeader()
    end
    if current == "char" then RefreshStats() end
    if current == "rep" and RefreshRep then RefreshRep() end
    if current == "skill" and RefreshSkills then RefreshSkills() end
    if current == "pvp" and RefreshPvP then RefreshPvP() end
  end)

  RefreshHeader()
  ShowTab("char")
end)
