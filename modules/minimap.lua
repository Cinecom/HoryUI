-- HoryUI :: square minimap + addon-button tray (Garnet)
--
-- Holder owns a squared Minimap; a tidy 4-column tray sits flush below it.
-- HoryUI's own button always leads the tray (opens settings); a slim handle
-- BELOW the tray collapses / expands it.
--
-- Collection contract (why there is no flicker): quest addons (pfQuest) drop
-- their own *buttons* on the Minimap (named "pfMiniMapPin1..N") and reposition
-- them every frame from player movement. We only ever collect *named, static*
-- addon buttons (or their mouse-enabled wrapper frames) and exclude known
-- dynamic pins, so there is never a tug-of-war over any frame.

HoryUI:RegisterModule("minimap", true, function()
  if not Minimap then return end
  local C = HoryUI.color

  local getn, tinsert, tsort = table.getn, table.insert, table.sort
  local floor, mod = math.floor, math.mod
  local strsub, strlen = string.sub, string.len

  local size = 140                 -- minimap edge in holder-local px
  local PAD, GAP, COLS = 4, 2, 4    -- tray outer pad / cell gap / fixed columns

  -- =========================================================================
  -- 1. strip Blizzard minimap chrome ----------------------------------------
  -- =========================================================================
  local hide = {
    "MinimapToggleButton", "MiniMapWorldMapButton", "MinimapBorderTop",
    "MinimapZoneTextButton", "MinimapZoomIn", "MinimapZoomOut",
    "MinimapNorthTag", "GameTimeFrame", "MiniMapMailBorder",
    "MiniMapBattlefieldBorder", "MiniMapTrackingButtonBorder",
  }
  for i = 1, getn(hide) do
    local f = getglobal(hide[i])
    if f then f:Hide() end
  end
  if MinimapBorder then MinimapBorder:SetTexture(nil) end

  -- =========================================================================
  -- 2. holder + squared minimap ---------------------------------------------
  -- =========================================================================
  local holder = CreateFrame("Frame", "HoryUIMinimap", UIParent)
  holder:SetWidth(size); holder:SetHeight(size)
  holder:SetFrameStrata("LOW")
  HoryUI.CreateBackdrop(holder)
  if HoryUIDB.minimapScale then holder:SetScale(HoryUIDB.minimapScale) end
  HoryUI.RegisterPanel(holder, "minimap", "Minimap", "TOPRIGHT", -16, -60)

  Minimap:SetParent(holder)
  Minimap:ClearAllPoints()
  Minimap:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  Minimap:SetWidth(size); Minimap:SetHeight(size)
  Minimap:SetFrameLevel(holder:GetFrameLevel() + 1)
  Minimap:SetMaskTexture(HoryUI.tex.white)     -- square mask
  local mlvl = Minimap:GetFrameLevel()

  Minimap:EnableMouseWheel(true)
  Minimap:SetScript("OnMouseWheel", function()
    if IsShiftKeyDown() then
      local s = (HoryUIDB.minimapScale or 1) + (arg1 > 0 and 0.05 or -0.05)
      if s < 0.6 then s = 0.6 elseif s > 2.0 then s = 2.0 end
      HoryUIDB.minimapScale = s
      holder:SetScale(s)
    elseif arg1 > 0 then
      Minimap_ZoomIn()
    else
      Minimap_ZoomOut()
    end
  end)

  -- consistent flat hover + tooltip for the tray controls
  local function ChromeTip(btn, tip)
    btn:SetScript("OnEnter", function()
      if this.backdrop then this.backdrop:SetBackdropBorderColor(C.accent_hi[1], C.accent_hi[2], C.accent_hi[3], 1) end
      if this.line then this.line:SetVertexColor(C.text[1], C.text[2], C.text[3], 1) end
      if tip then GameTooltip:SetOwner(this, "ANCHOR_LEFT"); GameTooltip:AddLine(tip); GameTooltip:Show() end
    end)
    btn:SetScript("OnLeave", function()
      if this.backdrop then this.backdrop:SetBackdropBorderColor(0, 0, 0, 1) end
      if this.line then this.line:SetVertexColor(C.text2[1], C.text2[2], C.text2[3], 1) end
      GameTooltip:Hide()
    end)
  end

  -- =========================================================================
  -- 3. button tray ----------------------------------------------------------
  -- =========================================================================
  local drawer = CreateFrame("Frame", "HoryUIMinimapDrawer", holder)
  drawer:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -3)
  drawer:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -3)
  drawer:SetHeight(8)
  HoryUI.CreateBackdrop(drawer)
  if HoryUIDB.drawerOpen == nil then HoryUIDB.drawerOpen = true end

  -- HoryUI's own button -- always the first tray cell; opens settings
  local horyBtn = CreateFrame("Button", "HoryUITrayButton", drawer)
  horyBtn:SetWidth(31); horyBtn:SetHeight(31)
  HoryUI.CreateBackdrop(horyBtn)
  local hicon = horyBtn:CreateTexture(nil, "ARTWORK")
  hicon:SetTexture("Interface\\Icons\\Ability_Stealth")
  hicon:SetPoint("TOPLEFT", horyBtn, "TOPLEFT", 2, -2)
  hicon:SetPoint("BOTTOMRIGHT", horyBtn, "BOTTOMRIGHT", -2, 2)
  hicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  horyBtn:SetScript("OnClick", function() if HoryUI.ToggleConfig then HoryUI.ToggleConfig() end end)
  ChromeTip(horyBtn, "HoryUI settings")

  -- slim handle BELOW the tray (re-anchored to map/tray bottom in RefreshDrawer).
  -- A simple centred grab-line reads cleaner than a chevron glyph.
  local handle = HoryUI.CreateButton(holder, "", nil)
  handle:SetWidth(36); handle:SetHeight(8)
  handle:SetFrameStrata("MEDIUM")
  handle:SetFrameLevel(mlvl + 10)
  handle.line = handle:CreateTexture(nil, "OVERLAY")
  handle.line:SetTexture(HoryUI.tex.white)
  handle.line:SetWidth(14); handle.line:SetHeight(2)
  handle.line:SetPoint("CENTER", handle, "CENTER", 0, 0)
  handle.line:SetVertexColor(C.text2[1], C.text2[2], C.text2[3], 1)

  -- =========================================================================
  -- 3b. left-border icon column ---------------------------------------------
  -- Blizzard's mail + profession-tracking (Find Herbs / Find Minerals / ...)
  -- buttons get a fixed square home flush against the minimap's LEFT edge,
  -- instead of being swept into the tray. The native art is round, so we
  -- HIDE the native icon and rebuild it as a crisp square: our own texture,
  -- fed the same image the native icon carries (the tracking icon changes
  -- with the active spell, so we re-mirror it each pass). The native frame
  -- is kept, sized to our square, only for its click + tooltip.
  -- =========================================================================
  local SIDE = 18                    -- square cell edge for a side icon (small)
  local sideOrder = {                -- top-to-bottom; tracking is always shown,
    { frame = "MiniMapTrackingFrame", icon = "MiniMapTrackingIcon" },
    { frame = "MiniMapMailFrame",     icon = "MiniMapMailIcon"     },  -- mail only when present
  }
  local sideCells = {}

  -- wipe every native texture off a side button (the gold border ring is on the
  -- ARTWORK layer -- pfUI's tracking skin uses the same DisableDrawLayer trick;
  -- it also catches button normal/highlight textures that :Hide() misses). Re-run
  -- each pass because Blizzard re-asserts these on tracking/mail updates.
  local artLayers = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY", "HIGHLIGHT" }
  local function StripNativeArt(f)
    local frames = { f, f:GetChildren() }   -- the frame + its inner button(s)
    for i = 1, getn(frames) do
      local fr = frames[i]
      if fr and fr.DisableDrawLayer then
        for j = 1, getn(artLayers) do fr:DisableDrawLayer(artLayers[j]) end
      end
    end
  end

  local function LayoutSide()
    local slot = 0
    for i = 1, getn(sideOrder) do
      local def = sideOrder[i]
      local f = getglobal(def.frame)
      if f and f:IsShown() then
        slot = slot + 1
        local cell = sideCells[slot]
        if not cell then
          cell = CreateFrame("Frame", nil, holder)
          cell:SetWidth(SIDE); cell:SetHeight(SIDE)
          cell:SetFrameStrata("LOW")
          cell:SetFrameLevel(mlvl + 5)
          HoryUI.CreateBackdrop(cell)
          cell.icon = cell:CreateTexture(nil, "ARTWORK")
          cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
          cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
          cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- crop to a clean square
          sideCells[slot] = cell
        end
        cell:ClearAllPoints()
        cell:SetPoint("TOPRIGHT", holder, "TOPLEFT", -3, -(slot - 1) * (SIDE + GAP))
        cell:Show()

        -- rebuild: read the native icon's image into our square, then strip ALL
        -- native art (border ring included) so only the crisp square shows
        local nat = getglobal(def.icon)
        if nat then
          local tex = nat:GetTexture()
          if tex then cell.icon:SetTexture(tex) end
        end
        StripNativeArt(f)

        -- keep the native frame purely for its click + tooltip, overlaying the cell
        if f:GetParent() ~= cell then
          f:SetParent(cell)
          f:SetFrameLevel(cell:GetFrameLevel() + 1)
        end
        f:SetScale(1)
        f:ClearAllPoints()
        f:SetAllPoints(cell)
      end
    end
    for i = slot + 1, getn(sideCells) do sideCells[i]:Hide() end
  end

  -- managed addon buttons + reusable cell frames
  local known, knownSet, cells = {}, {}, {}

  -- exact names we never collect (our own button + Blizzard minimap furniture)
  local skip = {
    HoryUITrayButton = true,
    MinimapZoomIn = true, MinimapZoomOut = true, MinimapBorder = true,
    MiniMapWorldMapButton = true, MiniMapMailFrame = true, MinimapBackdrop = true,
    MiniMapTracking = true, MiniMapTrackingButton = true, MiniMapTrackingFrame = true,
    GameTimeFrame = true,
    MiniMapBattlefieldFrame = true, MiniMapLFGFrame = true, MinimapPing = true,
    MiniMapVoiceChatFrame = true, MinimapZoneTextButton = true, MinimapToggleButton = true,
    MiniMapMeetingStoneFrame = true,
  }
  -- name prefixes of dynamically-positioned pins (quest/gather addons): never grab
  local badPrefix = {
    "pfMiniMapPin", "pfMapPin", "GatherMatePin", "GatherNote", "Gatherer_",
    "QuestieFrame", "Questie", "WorldMapPOI", "Cartographer", "DungeonMap",
  }

  local function collectible(ch)
    if not ch or ch == handle or ch == horyBtn then return false end
    if not ch.GetObjectType then return false end
    local nm = ch:GetName()
    if not nm then return false end          -- anonymous = blip/pin, never a tray button
    if skip[nm] then return false end
    for i = 1, getn(badPrefix) do
      local p = badPrefix[i]
      if strsub(nm, 1, strlen(p)) == p then return false end
    end
    -- a plain Button is always collectible; many addons (AtlasLoot, SmartLoot,
    -- SimpleActionSets) wrap their button in a mouse-enabled, icon-sized Frame
    -- parented to the Minimap -- collect those too, or they never grid.
    local t = ch:GetObjectType()
    if t == "Button" then return true end
    if t == "Frame" and ch.IsMouseEnabled and ch:IsMouseEnabled() then
      local w = ch:GetWidth()
      if w and w >= 12 and w <= 48 then return true end
    end
    return false
  end

  local function discover()
    local parents = { Minimap, MinimapCluster }
    for p = 1, getn(parents) do
      local pf = parents[p]
      if pf then
        local kids = { pf:GetChildren() }
        for i = 1, getn(kids) do
          local ch = kids[i]
          if collectible(ch) and not knownSet[ch] then
            knownSet[ch] = true
            tinsert(known, ch)
          end
        end
      end
    end
    tsort(known, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
  end

  local function layout()
    -- HoryUI button always leads, then discovered (currently-shown) addon buttons
    local shown = { horyBtn }
    for i = 1, getn(known) do
      if known[i]:IsShown() then tinsert(shown, known[i]) end
    end
    local n = getn(shown)

    local avail = size - 2 * PAD
    local cell = floor((avail - (COLS - 1) * GAP) / COLS)
    if cell < 16 then cell = 16 end
    local gridW = COLS * cell + (COLS - 1) * GAP
    local startX = floor((size - gridW) / 2)
    if startX < 0 then startX = 0 end
    local targetSz = cell - 6     -- icon size inside the cell (breathing room)

    for k = 1, n do
      local b = shown[k]
      local h = cells[k]
      if not h then
        h = CreateFrame("Frame", nil, drawer)
        cells[k] = h
      end
      h:SetWidth(cell); h:SetHeight(cell)
      local col = mod(k - 1, COLS)
      local row = floor((k - 1) / COLS)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", drawer, "TOPLEFT", startX + col * (cell + GAP), -(PAD + row * (cell + GAP)))
      h:Show()

      local w = b:GetWidth()
      if not w or w < 8 then w = 31 end
      local s = targetSz / w
      if s > 1.5 then s = 1.5 elseif s < 0.4 then s = 0.4 end

      -- re-parent only when needed (avoids z-order churn on toplevel buttons);
      -- always re-anchor so a button can never drift out of its cell.
      if b:GetParent() ~= h then
        b:SetParent(h)
        b:SetFrameLevel(h:GetFrameLevel() + 1)
      end
      b:SetScale(s)
      b:ClearAllPoints()
      b:SetPoint("CENTER", h, "CENTER", 0, 0)
    end
    for i = n + 1, getn(cells) do cells[i]:Hide() end

    local rows = floor((n - 1) / COLS) + 1
    drawer:SetHeight(PAD * 2 + rows * cell + (rows - 1) * GAP)
  end

  -- show/hide the tray; the handle lives at the bottom of whatever is visible
  local function RefreshDrawer()
    handle:ClearAllPoints()
    if HoryUIDB.drawerOpen then
      drawer:Show()
      handle:SetPoint("TOP", drawer, "BOTTOM", 0, -1)
    else
      drawer:Hide()
      handle:SetPoint("TOP", holder, "BOTTOM", 0, -3)
    end
  end

  -- one cheap pass: pick up any new buttons, then re-grid + reposition the handle
  local function scan()
    discover()
    layout()
    RefreshDrawer()
    LayoutSide()
  end

  handle:SetScript("OnClick", function()
    HoryUIDB.drawerOpen = not HoryUIDB.drawerOpen
    RefreshDrawer()
  end)
  ChromeTip(handle, "Show / hide button tray")

  -- =========================================================================
  -- 4. driver: fast scans early (catch late addon buttons with no visible
  --    jump), then a calm 2s heartbeat for toggled / nudged buttons ---------
  -- =========================================================================
  local driver = CreateFrame("Frame")
  driver:RegisterEvent("PLAYER_LOGOUT")
  driver.t = 0; driver.acc = 0
  driver:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      this:SetScript("OnUpdate", nil)
    end
  end)
  driver:SetScript("OnUpdate", function()
    driver.t = driver.t + arg1
    driver.acc = driver.acc + arg1
    local interval = (driver.t < 6) and 0.25 or 2.0
    if driver.acc >= interval then
      driver.acc = 0
      scan()
    end
  end)

  scan()   -- grid whatever already exists on the very first frame
end)
