-- HoryUI :: castbars (player + enemy target) via Nampower SPELL_* events
-- Enemy casts are tracked by GUID so targeting a unit mid-cast still shows the
-- bar (Kick timing). Requires Nampower -- the SPELL_* events don't exist without it.
-- Raw event args (from Nampower, confirmed against pfUI libdebuff):
--   SPELL_START_*  arg2=spellId arg3=casterGuid arg6=castTime(ms) arg7=channelDur arg8=type
--   SPELL_GO_*     arg3=casterGuid (cast completed)
--   SPELL_FAILED_OTHER arg1=casterGuid (interrupted/cancelled)

HoryUI:RegisterModule("castbar", true, function()
  if not HoryUI.np.OK() then return end
  local C = HoryUI.color

  -- Enemy-cast latency compensation. A SPELL_START_OTHER / UNIT_CASTEVENT packet
  -- reaches us ~one network round-trip after the cast truly began on the server,
  -- so an uncompensated bar starts (and finishes) late -- the spell lands before
  -- the bar fills. Shifting the start back by our latency makes the bar reach the
  -- end at the real last-interruptible moment (a Kick also needs the round-trip to
  -- arrive, so the full GetNetStats latency is the right amount). Enemy casts only;
  -- the player's own cast start is known locally and is left uncompensated.
  local function CastLag()
    local _, _, lag = GetNetStats()
    return (lag or 0) / 1000
  end

  -- Object-interaction and visual casts (opening chests/lockboxes, gathering,
  -- pickpocket, NPC visuals) resolve to real spell records, but their names
  -- carry Blizzard's dev-internal markers -- "Opening - No Text", "Heal Visual
  -- (DND)", "Pickpocket (PT)". They're correct, just unreadable on a castbar, so
  -- strip the markers and show the clean action name ("Opening", "Pickpocket").
  local function CleanName(n)
    if not n then return n end
    n = string.gsub(n, " %- No Text$", "")   -- text-less channel/interaction casts
    n = string.gsub(n, "%s*%(DND%)$", "")    -- "do not display" visual-only spells
    n = string.gsub(n, "%s*%(PT%)$", "")     -- internal placeholder-text marker
    n = string.gsub(n, "%s*%(Test%)$", "")   -- unfinished/test spells
    n = string.gsub(n, "%s*%(NYI%)$", "")    -- "not yet implemented" data spells
    n = string.gsub(n, "%s+DND$", "")        -- bare DND suffix (no parens)
    return n
  end

  local function SpellName(spellId)
    if HoryUI.HasSuperWoW then
      local n = HoryUI.sw.SpellInfo(spellId)
      if n and n ~= "" then return CleanName(n) end
    end
    if GetSpellRecField then
      local n = GetSpellRecField(spellId, "name")
      if n and n ~= "" then return CleanName(n) end
    end
    if GetSpellRec then
      local rec = GetSpellRec(spellId)
      if rec and rec.name then return CleanName(rec.name) end
    end
    return "Casting"
  end

  local function SpellIcon(spellId)
    -- Every "Opening ..." cast (chests, lockboxes, nodes) ships a placeholder
    -- icon; always show a gear/cog so the container interaction reads at a glance.
    if string.find(SpellName(spellId), "^Opening") then
      return "Interface\\Icons\\INV_Misc_Gear_01"
    end
    if HoryUI.HasSuperWoW then
      local _, icon = HoryUI.sw.SpellInfo(spellId)
      if icon then return icon end
    end
    if GetSpellRecField and GetSpellIconTexture then
      local iconID = GetSpellRecField(spellId, "spellIconID")
      if iconID then
        local tex = GetSpellIconTexture(iconID)
        if tex then return tex end
      end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end

  local function CastOnUpdate()
    local f = this
    if not f.active then return end
    f.acc = (f.acc or 0) + arg1
    if f.acc < 0.02 then return end
    f.acc = 0
    local now = GetTime()
    local remaining = f.duration - (now - f.start)
    if remaining <= 0 then
      f.active = false
      f:Hide()
      return
    end
    local frac = (now - f.start) / f.duration
    if f.channel then frac = 1 - frac end
    f.bar:SetValue(frac)
    f.timer:SetText(string.format("%.1f", remaining))
  end

  local function BuildCastbar(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetHeight(16)
    f:SetFrameStrata("MEDIUM")
    HoryUI.CreateBackdrop(f)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    f.icon:SetWidth(14)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.bar = HoryUI.CreateStatusBar(f, C.cast)
    f.bar:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 2, 0)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(0)

    f.timer = f.bar:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(f.timer, HoryUI.font.number, 11, "OUTLINE")
    f.timer:SetPoint("RIGHT", f.bar, "RIGHT", -4, 0)
    f.timer:SetTextColor(C.text[1], C.text[2], C.text[3])

    f.text = f.bar:CreateFontString(nil, "OVERLAY")
    HoryUI.SetFont(f.text, HoryUI.font.normal, 11, "OUTLINE")
    f.text:SetPoint("LEFT", f.bar, "LEFT", 4, 0)
    f.text:SetTextColor(C.text[1], C.text[2], C.text[3])

    f.active = false
    f:SetScript("OnUpdate", CastOnUpdate)
    f:Hide()
    return f
  end

  local function StartCast(f, spellId, startTime, duration, channel, name, icon)
    if not duration or duration <= 0 then return end
    f.icon:SetTexture(icon or SpellIcon(spellId))
    f.text:SetText(name or SpellName(spellId))
    f.start = startTime
    f.duration = duration
    f.channel = channel
    f.active = true
    f.acc = 0
    -- paint the starting fill immediately, otherwise the bar shows the previous
    -- cast's (or the preview's) value for one frame before the first OnUpdate -> flicker
    local now = GetTime()
    local frac = (now - startTime) / duration
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    if channel then frac = 1 - frac end
    f.bar:SetValue(frac)
    local remaining = duration - (now - startTime)
    if remaining < 0 then remaining = 0 end
    f.timer:SetText(string.format("%.1f", remaining))
    f:Show()
  end

  local function StopCast(f)
    f.active = false
    f:Hide()
  end

  ----------------------------------------------------------------------------
  local player_cb = BuildCastbar("HoryUIPlayerCast")
  local target_cb = BuildCastbar("HoryUITargetCast")

  -- independently movable panels (own movers + saved positions)
  player_cb:SetWidth(232)
  HoryUI.RegisterPanel(player_cb, "playercast", "Player Cast", "CENTER", -200, -188)

  target_cb:SetWidth(220)            -- match the target unit frame width (W in unitframes)
  HoryUI.RegisterPanel(target_cb, "targetcast", "Target Cast", "CENTER", 40, -188)

  ----------------------------------------------------------------------------
  -- enemy cast store, keyed by caster GUID
  local casts = {}
  local currentTargetGuid

  local function Prune()
    local now = GetTime()
    for g, c in pairs(casts) do
      if (c.start + c.duration) < now then casts[g] = nil end
    end
  end

  local function ShowTargetCast()
    local c = currentTargetGuid and casts[currentTargetGuid]
    if c and (c.start + c.duration) > GetTime() then
      StartCast(target_cb, c.spellId, c.start, c.duration, c.channel, c.name, c.icon)
    else
      StopCast(target_cb)
    end
  end

  local function ParseStart()
    -- returns spellId, castTime(s), isChannel from the current SPELL_START_* args
    local spellId = arg2
    local spellType = arg8 or 0
    local castTime = (arg6 and arg6 > 0) and arg6 or arg7
    local isChannel = (spellType == 1) and (not arg6 or arg6 == 0)
    local dur = castTime and castTime / 1000 or 0
    return spellId, dur, isChannel
  end

  -- SuperWoW exposes one unified UNIT_CASTEVENT; prefer it. Without SuperWoW,
  -- fall back to stitching Nampower's SPELL_START / SPELL_GO / SPELL_FAILED.
  local playerGuid
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:RegisterEvent("PLAYER_TARGET_CHANGED")
  ev:RegisterEvent("PLAYER_LOGOUT")
  local function reg(e) pcall(function() ev:RegisterEvent(e) end) end
  if HoryUI.HasSuperWoW then
    reg("UNIT_CASTEVENT")
  else
    reg("SPELL_START_SELF")
    reg("SPELL_START_OTHER")
    reg("SPELL_GO_SELF")
    reg("SPELL_GO_OTHER")
    reg("SPELL_FAILED_OTHER")
  end

  ev:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      player_cb:SetScript("OnUpdate", nil)
      target_cb:SetScript("OnUpdate", nil)
      return
    end

    if event == "PLAYER_ENTERING_WORLD" then
      playerGuid = HoryUI.np.GUID("player")
      currentTargetGuid = HoryUI.np.GUID("target")
      return
    end

    if event == "PLAYER_TARGET_CHANGED" then
      currentTargetGuid = HoryUI.np.GUID("target")
      ShowTargetCast()
      return
    end

    -- ----- SuperWoW: one event for every cast -----
    -- arg1 caster GUID, arg2 target GUID, arg3 type, arg4 spellId, arg5 ms
    if event == "UNIT_CASTEVENT" then
      local caster, etype, spellId, ms = arg1, arg3, arg4, arg5
      if etype == "START" or etype == "CHANNEL" then
        local dur = (ms or 0) / 1000
        if dur > 0 then
          local channel = (etype == "CHANNEL")
          if caster == playerGuid then
            StartCast(player_cb, spellId, GetTime(), dur, channel)
          else
            Prune()
            casts[caster] = {
              spellId = spellId, name = SpellName(spellId), icon = SpellIcon(spellId),
              start = GetTime() - CastLag(), duration = dur, channel = channel,
            }
            if caster == currentTargetGuid then ShowTargetCast() end
          end
        end
      elseif etype == "FAIL" then
        if caster == playerGuid then
          StopCast(player_cb)
        else
          casts[caster] = nil
          if caster == currentTargetGuid then StopCast(target_cb) end
        end
      end
      -- "CAST" (instant) needs no bar
      return
    end

    if event == "SPELL_START_SELF" then
      local spellId, dur, channel = ParseStart()
      StartCast(player_cb, spellId, GetTime(), dur, channel)
      return
    end

    if event == "SPELL_GO_SELF" then
      StopCast(player_cb)
      return
    end

    if event == "SPELL_START_OTHER" then
      local casterGuid = arg3
      local spellId, dur, channel = ParseStart()
      if casterGuid and spellId and dur > 0 then
        Prune()
        casts[casterGuid] = {
          spellId = spellId,
          name = SpellName(spellId),
          icon = SpellIcon(spellId),
          start = GetTime() - CastLag(),
          duration = dur,
          channel = channel,
        }
        if casterGuid == currentTargetGuid then ShowTargetCast() end
      end
      return
    end

    if event == "SPELL_GO_OTHER" then
      local casterGuid = arg3
      if casterGuid then casts[casterGuid] = nil end
      if casterGuid and casterGuid == currentTargetGuid then StopCast(target_cb) end
      return
    end

    if event == "SPELL_FAILED_OTHER" then
      local casterGuid = arg1
      if casterGuid then casts[casterGuid] = nil end
      if casterGuid and casterGuid == currentTargetGuid then StopCast(target_cb) end
      return
    end
  end)

  -- preview the castbars while panels are unlocked (they anchor under the
  -- unit frames, so they move with them -- this just makes them visible)
  local function ShowPreview(f)
    f.active = false
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.text:SetText("Casting...")
    f.timer:SetText("1.5")
    f.bar:SetValue(0.6)
    f:Show()
  end
  HoryUI.AddRefresher(function()
    if HoryUI.showAll then
      ShowPreview(player_cb)
      ShowPreview(target_cb)
    else
      if not player_cb.active then player_cb:Hide() end
      if not target_cb.active then target_cb:Hide() end
    end
  end)

  -- replaces the Blizzard player cast bar
  HoryUI.HideBlizzard(CastingBarFrame)
end)
