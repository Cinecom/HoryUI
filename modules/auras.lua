-- HoryUI :: auras -- player buffs (with timers + right-click cancel) + target
-- debuffs/buffs.
--
-- Target auras read Nampower GetUnitField("aura") (slots 1-32 buffs, 33-48
-- debuffs) for icon + stacks. Durations come from Nampower AURA_CAST_ON_*
-- events (arg8 = ms), so any aura we witnessed being applied shows a real
-- countdown; auras already active before we saw the unit show no timer.
--
-- Player buffs instead use the Blizzard player-buff API (GetPlayerBuff /
-- GetPlayerBuffTexture / GetPlayerBuffApplications / GetPlayerBuffTimeLeft /
-- CancelPlayerBuff). Nampower's GetUnitField exposes no duration, and we want a
-- countdown timer + a right-click cancel; these are direct API calls, not the
-- tooltip scans CLAUDE.md sec.3 forbids.

HoryUI:RegisterModule("auras", true, function()
  if not HoryUI.np.OK() then return end
  local C = HoryUI.color
  local floor = math.floor
  local GetPlayerBuff, GetPlayerBuffTexture = GetPlayerBuff, GetPlayerBuffTexture
  local GetPlayerBuffApplications, GetPlayerBuffTimeLeft = GetPlayerBuffApplications, GetPlayerBuffTimeLeft
  local CancelPlayerBuff = CancelPlayerBuff
  local BSTART = PLAYER_BUFF_START_ID or -1      -- 1.12 buff-index base; -1 = vanilla
                                                 -- (don't depend on pfUI's global being set)

  local GAP = 2
  -- target groups: compact icons with an in-icon countdown (more per row)
  local T_SIZE, T_PERROW = 16, 12
  -- player buffs: bigger icons, 3 rows, a timer line reserved under each cell
  local P_SIZE, P_PERROW, P_TIMER = 28, 8, 15
  local P_ROWSTEP = P_SIZE + P_TIMER + 3         -- icon + timer + gaps
  local P_COUNT = P_PERROW * 3                   -- 24 (3 rows of 8)

  -- hover tooltips. Player buffs use the Blizzard player-buff id; target auras
  -- use the compacted display index (== UnitBuff/UnitDebuff ordinal), the same
  -- way pfUI feeds SetUnitBuff/SetUnitDebuff. Mouse is captured only while
  -- locked -- the mover overlay sits above these icons when unlocked.
  local function IconOnEnter()
    local kind = this.tipKind
    if kind == "player" then
      if not this.bidx then return end
      local bid = GetPlayerBuff(BSTART + this.bidx, "HELPFUL")
      if not bid or bid < 0 then return end
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      GameTooltip:SetPlayerBuff(bid)
    elseif this.auraIndex and UnitExists("target") then
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      if kind == "buff" then
        GameTooltip:SetUnitBuff("target", this.auraIndex)
      else
        GameTooltip:SetUnitDebuff("target", this.auraIndex)
      end
    end
  end
  local function IconOnLeave()
    GameTooltip:Hide()
  end

  local function CreateIcon(parent, size, kind)
    local b = CreateFrame("Frame", nil, parent)
    b:SetWidth(size); b:SetHeight(size)
    HoryUI.CreateBackdrop(b)
    b.tipKind = kind
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(b.count, HoryUI.font.number, 10, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.count:SetTextColor(C.text[1], C.text[2], C.text[3])
    b:EnableMouse(true)
    b:SetScript("OnEnter", IconOnEnter)
    b:SetScript("OnLeave", IconOnLeave)
    b.timer = b:CreateFontString(nil, "OVERLAY")
    b.timer:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
    if kind == "player" then
      -- player buffs: a roomy timer line reserved under the (larger) icon
      HoryUI.SetFont(b.timer, HoryUI.font.number, 13, "OUTLINE")
      b.timer:SetPoint("TOP", b, "BOTTOM", 0, -1)
      -- right-click cancels the buff; re-fetch the id at click time so it stays
      -- correct as buffs come and go.
      b:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" and this.bidx then
          CancelPlayerBuff(GetPlayerBuff(BSTART + this.bidx, "HELPFUL"))
        end
      end)
    else
      -- target auras: countdown overlaid inside the (small) icon to stay compact
      HoryUI.SetFont(b.timer, HoryUI.font.number, 9, "OUTLINE")
      b.timer:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    b:Hide()
    return b
  end

  local function MakeGroup(name, count, size, perrow, rowstep, kind, bottomUp)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetWidth(perrow * (size + GAP))
    local totalRows = math.ceil(count / perrow)
    f:SetHeight(totalRows * rowstep)
    f:SetFrameStrata("MEDIUM")
    f.icons = {}
    for i = 1, count do
      local ic = CreateIcon(f, size, kind)
      local col = math.mod(i - 1, perrow)
      local row = floor((i - 1) / perrow)
      -- bottomUp groups fill the bottom row first, then grow upward, so the
      -- first slot sits on the lowest row of the (fixed) panel box.
      if bottomUp then row = totalRows - 1 - row end
      ic:SetPoint("TOPLEFT", f, "TOPLEFT", col * (size + GAP), -row * rowstep)
      f.icons[i] = ic
    end
    return f
  end

  local pbuffs   = MakeGroup("HoryUIPlayerAuras", P_COUNT, P_SIZE, P_PERROW, P_ROWSTEP, "player")
  local tdebuffs = MakeGroup("HoryUITargetDebuffs", 16, T_SIZE, T_PERROW, T_SIZE + GAP, "debuff")
  local tbuffs   = MakeGroup("HoryUITargetBuffs", 16, T_SIZE, T_PERROW, T_SIZE + GAP, "buff", true)

  -- target debuffs + buffs are independently movable panels (default: stacked
  -- under the target frame). Unlock to drag them anywhere.
  HoryUI.RegisterPanel(tdebuffs, "targetdebuffs", "Tgt Debuffs", "CENTER", 40, -212)
  HoryUI.RegisterPanel(tbuffs, "targetbuffs", "Tgt Buffs", "CENTER", 40, -264)

  ----------------------------------------------------------------------------
  -- shared: countdown formatting. below 5 min -> orange, below 1 min -> red
  -- (+ bare seconds); calm above that.
  ----------------------------------------------------------------------------
  local function SetTimer(fs, t)
    if t >= 3600 then
      fs:SetText(floor(t / 3600) .. "h")
    elseif t >= 60 then
      fs:SetText(floor(t / 60) .. "m")
    else
      fs:SetText(floor(t))
    end
    if t < 60 then
      fs:SetTextColor(C.name_hostile[1], C.name_hostile[2], C.name_hostile[3])
    elseif t < 300 then
      fs:SetTextColor(C.threat[1], C.threat[2], C.threat[3])
    else
      fs:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
    end
  end

  ----------------------------------------------------------------------------
  -- target auras: Nampower GetUnitField (icon + stacks); durations come from
  -- Nampower AURA_CAST_ON_* events (arg8 = duration ms), which carry the real
  -- remaining time for any aura we witnessed being applied. Keyed by
  -- targetGuid + spell NAME (the cast spellId and the resulting aura's spellId
  -- can differ, so we bridge by name -- same approach pfUI's libdebuff uses).
  -- Auras already active before we saw them have no entry and simply show no
  -- timer.
  ----------------------------------------------------------------------------
  local auraDur = {}                       -- [guid][spellName] = { start, dur }

  local function SpellName(spellId)
    return GetSpellRecField and GetSpellRecField(spellId, "name")
  end

  local function StoreAura(targetGuid, spellId, durMs)
    if not targetGuid or not spellId then return end
    local dur = durMs and durMs / 1000 or 0
    if dur <= 0 then return end
    local name = SpellName(spellId)
    if not name then return end
    local t = auraDur[targetGuid]
    if not t then t = {}; auraDur[targetGuid] = t end
    t[name] = t[name] or {}
    t[name].start = GetTime()
    t[name].dur = dur
  end

  -- drop expired entries (and fully-empty guid tables) so the store stays bounded
  local function PruneAuras(now)
    for g, t in pairs(auraDur) do
      local any = false
      for n, d in pairs(t) do
        if (d.start + d.dur) <= now then t[n] = nil else any = true end
      end
      if not any then auraDur[g] = nil end
    end
  end

  local function AuraTimeLeft(guid, spellId)
    local t = guid and auraDur[guid]
    local d = t and t[SpellName(spellId)]
    if not d then return nil end
    local tl = d.start + d.dur - GetTime()
    if tl > 0 then return tl end
    return nil
  end

  local function IconTexture(spellId)
    if GetSpellRecField and GetSpellIconTexture then
      local iconID = GetSpellRecField(spellId, "spellIconID")
      if iconID then
        local tex = GetSpellIconTexture(iconID)
        if tex then return tex end
      end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end

  local function Scan(guid, fromSlot, toSlot, icons)
    local auras = guid and GetUnitField(guid, "aura")
    local stacks = guid and GetUnitField(guid, "auraApplications")
    local shown = 0
    local total = table.getn(icons)
    if auras then
      for slot = fromSlot, toSlot do
        local spellId = auras[slot]
        if spellId and spellId > 0 and shown < total then
          shown = shown + 1
          local ic = icons[shown]
          ic.auraIndex = shown            -- == UnitBuff/UnitDebuff ordinal (for tooltip)
          ic.tex:SetTexture(IconTexture(spellId))
          local st = stacks and stacks[slot]
          if st and st > 1 then ic.count:SetText(st) else ic.count:SetText("") end
          local tl = AuraTimeLeft(guid, spellId)
          if tl then SetTimer(ic.timer, tl) else ic.timer:SetText("") end
          ic:Show()
        end
      end
    end
    for i = shown + 1, total do icons[i]:Hide() end
  end

  ----------------------------------------------------------------------------
  -- player buffs: Blizzard API (icon + stacks + timer + right-click cancel)
  ----------------------------------------------------------------------------
  local function ScanPlayerBuffs(icons)
    local total = table.getn(icons)
    -- profession tracking (Find Herbs / Find Minerals / ...) shows up as a player
    -- buff whose icon == the active tracking texture; skip it so the bar isn't
    -- cluttered with a permanent tracking aura. Nil when nothing is tracked.
    local track = GetTrackingTexture and GetTrackingTexture()
    local shown = 0
    local i = 1
    while shown < total do
      local bid = GetPlayerBuff(BSTART + i, "HELPFUL")
      if not bid or bid < 0 then break end       -- buffs are contiguous from 1
      local tex = GetPlayerBuffTexture(bid)
      if track and tex == track then
        i = i + 1                                 -- a tracking buff: skip, keep scanning
      else
        shown = shown + 1
        local ic = icons[shown]
        ic.bidx = i                               -- real buff index (for tooltip + cancel)
        ic.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        local st = GetPlayerBuffApplications(bid)
        if st and st > 1 then ic.count:SetText(st) else ic.count:SetText("") end
        local tl = GetPlayerBuffTimeLeft(bid)
        if tl and tl > 0 then SetTimer(ic.timer, tl) else ic.timer:SetText("") end
        ic:Show()
        i = i + 1
      end
    end
    for j = shown + 1, total do icons[j]:Hide() end
  end

  local function Placeholders(icons, n)
    for i = 1, table.getn(icons) do
      if i <= n then
        icons[i].tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icons[i].count:SetText("")
        if icons[i].timer then icons[i].timer:SetText("") end
        icons[i].bidx = nil
        icons[i]:Show()
      else
        icons[i]:Hide()
      end
    end
  end

  local acc, pruneAcc = 0, 0
  local poller = CreateFrame("Frame")
  poller:RegisterEvent("PLAYER_LOGOUT")
  -- Nampower aura-cast events feed real target-aura durations (arg1 spellId,
  -- arg3 targetGuid, arg8 duration ms). Requires NP_EnableAuraCastEvents (set
  -- by HoryUI.np.EnableEvents). pcall the registration so a missing event on an
  -- older Nampower can't abort module load.
  local function reg(e) pcall(function() poller:RegisterEvent(e) end) end
  reg("AURA_CAST_ON_SELF")
  reg("AURA_CAST_ON_OTHER")
  poller:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      this:SetScript("OnUpdate", nil)
      return
    end
    -- AURA_CAST_ON_SELF / _ON_OTHER: record the witnessed aura's duration
    StoreAura(arg3, arg1, arg8)
  end)
  poller:SetScript("OnUpdate", function()
    acc = acc + arg1
    if acc < 0.2 then return end                 -- also paces the buff countdown
    acc = 0

    -- sweep expired duration entries every ~5s so the store can't grow without
    -- bound across a session (one entry per witnessed guid+aura)
    pruneAcc = pruneAcc + 0.2
    if pruneAcc >= 5 then pruneAcc = 0; PruneAuras(GetTime()) end

    if HoryUI.showAll then
      Placeholders(pbuffs.icons, 10)
      Placeholders(tdebuffs.icons, 4)
      Placeholders(tbuffs.icons, 3)
      return
    end

    ScanPlayerBuffs(pbuffs.icons)
    if UnitExists("target") then
      local tguid = HoryUI.np.GUID("target")
      Scan(tguid, 33, 48, tdebuffs.icons)   -- target debuffs
      Scan(tguid, 1, 32, tbuffs.icons)      -- target buffs
    else
      for i = 1, table.getn(tdebuffs.icons) do tdebuffs.icons[i]:Hide() end
      for i = 1, table.getn(tbuffs.icons) do tbuffs.icons[i]:Hide() end
    end
  end)

  HoryUI.RegisterPanel(pbuffs, "playerauras", "Buffs", "TOPRIGHT", -20, -20)
  HoryUI.HideBlizzard(BuffFrame)
end)
