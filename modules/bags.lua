-- HoryUI :: one-bag (Garnet)
--
-- Replaces WoW's five separate ContainerFrames with a single movable, styled
-- grid showing every item from bags 0-4 (+ the keyring, container -2).
--
-- TECHNIQUE (borrowed from pfUI/modules/bags.lua, minimal HoryUI version):
-- we do NOT hand-roll item buttons. Each slot is a real Button built from
-- "ContainerFrameItemButtonTemplate" parented to a per-bag holder whose
-- :SetID(bag) the template reads; the button's :SetID(slot) does the rest.
-- That template carries all of Blizzard's behaviour for free -- left-click
-- use/equip, right-click, shift-click split/link, drag, GameTooltip, cooldown
-- swipe -- so we only ever skin the frame and drive its texture/count/lock.
--
-- Lua 5.0 / WoW 1.12 only -- see CLAUDE.md before editing.

HoryUI:RegisterModule("bags", true, function()
  local C = HoryUI.color
  local getn, floor, mod = table.getn, math.floor, math.mod
  local strfind, strlower, strsub = string.find, string.lower, string.sub

  -- the containers we present, in display order. -2 is the keyring (optional).
  local BACKPACK = { 0, 1, 2, 3, 4 }
  local KEYRING  = -2

  -- layout scale (CLAUDE.md spacing: 1/2/4/8/12/16)
  local SLOT   = 30          -- item button edge
  local GAP    = 2           -- gap between cells
  local PAD    = 8           -- frame inner padding
  local HEADER = 22          -- header strip height (search / money / controls)

  -- column clamp + default
  local MINCOL, MAXCOL, DEFCOL = 6, 16, 10
  if not HoryUIDB.bagCols then HoryUIDB.bagCols = DEFCOL end
  if HoryUIDB.showKeyring == nil then HoryUIDB.showKeyring = false end

  local function Cols()
    local n = HoryUIDB.bagCols or DEFCOL
    if n < MINCOL then n = MINCOL elseif n > MAXCOL then n = MAXCOL end
    return n
  end

  -- =========================================================================
  -- money / count formatting --------------------------------------------------
  -- =========================================================================
  -- GetMoney() returns copper. 1g = 10000c, 1s = 100c. Vanilla FontStrings do NOT
  -- render inline |T..|t texture escapes (that arrived in TBC -- Blizzard's own 1.12
  -- MoneyFrame uses textured buttons, not text), which is why the coin markup showed
  -- as raw text. We colour the g/s/c letters instead: compact, glanceable, reliable.
  local GOLD, SILVER, COPPER = "ffffd700", "ffc7c7cf", "ffeda55f"
  local function MoneyString(copper)
    copper = copper or 0
    local g = floor(copper / 10000)
    local s = floor(mod(copper, 10000) / 100)
    local c = mod(copper, 100)
    local out = ""
    if g > 0 then out = out .. g .. "|c" .. GOLD .. "g|r " end
    if g > 0 or s > 0 then out = out .. s .. "|c" .. SILVER .. "s|r " end
    out = out .. c .. "|c" .. COPPER .. "c|r"
    return out
  end

  -- the active container list (keyring appended only when toggled on)
  local containers = {}
  local function RebuildContainerList()
    for i = getn(containers), 1, -1 do containers[i] = nil end
    for i = 1, getn(BACKPACK) do containers[i] = BACKPACK[i] end
    if HoryUIDB.showKeyring then containers[getn(containers) + 1] = KEYRING end
  end
  RebuildContainerList()

  local function BagSize(bag)
    if bag == KEYRING then return GetKeyRingSize and GetKeyRingSize() or 0 end
    return GetContainerNumSlots(bag) or 0
  end

  -- =========================================================================
  -- main frame ---------------------------------------------------------------
  -- =========================================================================
  local bag = CreateFrame("Frame", "HoryUIBag", UIParent)
  bag:SetWidth(Cols() * (SLOT + GAP) - GAP + PAD * 2)
  bag:SetHeight(120)
  bag:SetFrameStrata("HIGH")
  bag:EnableMouse(true)              -- swallow clicks so they don't fall through
  HoryUI.CreateBackdrop(bag)
  HoryUI.RegisterPanel(bag, "bags", "Bags", "BOTTOMRIGHT", -180, 200)
  tinsert(UISpecialFrames, "HoryUIBag")   -- Esc closes it

  -- direct drag: grab the bag by its body (header / padding) to move it, in addition
  -- to the unlock-mover. RegisterPanel already made it SetMovable; persist on stop.
  bag:RegisterForDrag("LeftButton")
  bag:SetScript("OnDragStart", function() this:StartMoving() end)
  bag:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    HoryUI.SavePosition(this, "bags")
  end)

  -- per-bag holders (carry the bag id via :SetID for the item template) -------
  local holders = {}      -- holders[bag] = Frame
  local slots = {}        -- slots[bag][slot] = Button
  for i = 1, getn(BACKPACK) do
    local b = BACKPACK[i]
    holders[b] = CreateFrame("Frame", "HoryUIBagHolder" .. b, bag)
    holders[b]:SetID(b)
    holders[b]:SetAllPoints(bag)
    slots[b] = {}
  end
  -- keyring holder (a negative id reads awkwardly in a frame name; spell it out)
  holders[KEYRING] = CreateFrame("Frame", "HoryUIBagHolderKeyring", bag)
  holders[KEYRING]:SetID(KEYRING)
  holders[KEYRING]:SetAllPoints(bag)
  slots[KEYRING] = {}

  -- =========================================================================
  -- header: search + money + free + controls + close -------------------------
  -- =========================================================================
  -- money (bottom-right, like a wallet line)
  local money = bag:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(money, HoryUI.font.number, 11, "OUTLINE")
  money:SetPoint("BOTTOMRIGHT", bag, "BOTTOMRIGHT", -PAD, 6)
  money:SetJustifyH("RIGHT")
  money:SetTextColor(C.text[1], C.text[2], C.text[3])

  -- free-slot count (bottom-left)
  local freetext = bag:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(freetext, HoryUI.font.number, 11, "OUTLINE")
  freetext:SetPoint("BOTTOMLEFT", bag, "BOTTOMLEFT", PAD, 6)
  freetext:SetJustifyH("LEFT")
  freetext:SetTextColor(C.text2[1], C.text2[2], C.text2[3])

  -- close button (top-right) -- reuse the themed button, "x" glyph
  local close = HoryUI.CreateButton(bag, "x", function() bag:Hide() end)
  close:SetWidth(HEADER - 4); close:SetHeight(HEADER - 4)
  close:SetPoint("TOPRIGHT", bag, "TOPRIGHT", -PAD + 2, -PAD + 2)

  -- a tiny labelled square control (menu / keyring / sort / col steppers) ------
  -- parent defaults to the bag; the popup-menu controls pass `menu` as parent.
  local function MakeControl(label, tip, onclick, w, parent)
    local b = HoryUI.CreateButton(parent or bag, label, onclick)
    b:SetWidth(w or (HEADER - 4)); b:SetHeight(HEADER - 4)
    local oe, ol = b:GetScript("OnEnter"), b:GetScript("OnLeave")
    b:SetScript("OnEnter", function()
      if oe then oe() end
      if tip then GameTooltip:SetOwner(this, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function()
      if ol then ol() end
      GameTooltip:Hide()
    end)
    return b
  end

  -- defined below; the header + popup-menu controls need forward references
  local Relayout, SortBags, PaintQuality
  local menu, RefreshBagIcons, HighlightBag, ClearHighlight
  local colDown, colNum, colUp, PaintKey

  -- menu button (top-left) -- opens the options popup (columns / sort / bag icons)
  local menuBtn = MakeControl("", "Bag options", function()
    if menu:IsShown() then
      menu:Hide()
    else
      if RefreshBagIcons then RefreshBagIcons() end
      menu:Show()
    end
  end)
  menuBtn:SetPoint("TOPLEFT", bag, "TOPLEFT", PAD, -PAD + 2)
  -- hamburger glyph (three flat rules) so the button reads as a menu affordance
  for i = 1, 3 do
    local ln = menuBtn:CreateTexture(nil, "OVERLAY")
    ln:SetTexture("Interface\\Buttons\\WHITE8X8")
    ln:SetVertexColor(C.text2[1], C.text2[2], C.text2[3], 1)
    ln:SetWidth(8); ln:SetHeight(2)
    ln:SetPoint("CENTER", menuBtn, "CENTER", 0, (2 - i) * 3)
  end

  -- search box (between the menu button and the close button)
  local searchBox = CreateFrame("EditBox", "HoryUIBagSearch", bag)
  searchBox:SetHeight(HEADER - 6)
  searchBox:SetAutoFocus(false)
  searchBox:SetFont(HoryUI.font.normal, 11, "OUTLINE")
  searchBox:SetTextColor(C.text[1], C.text[2], C.text[3])
  searchBox:SetTextInsets(4, 4, 0, 0)
  HoryUI.CreateBackdrop(searchBox)

  local searchHint = searchBox:CreateFontString(nil, "ARTWORK")
  HoryUI.SetFont(searchHint, HoryUI.font.normal, 11, "OUTLINE")
  searchHint:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
  searchHint:SetText("Search")
  searchHint:SetTextColor(C.text3[1], C.text3[2], C.text3[3])

  searchBox:SetPoint("LEFT", menuBtn, "RIGHT", 6, 0)
  searchBox:SetPoint("RIGHT", close, "LEFT", -6, 0)
  searchBox:SetPoint("TOP", bag, "TOP", 0, -PAD + 1)

  -- =========================================================================
  -- search filter ------------------------------------------------------------
  -- =========================================================================
  -- dim items whose name doesn't contain the query; empty query = all normal.
  local function ApplySearch()
    local q = searchBox:GetText()
    if q == nil then q = "" end
    q = strlower(q)
    -- hint shows only when the box is empty AND unfocused (focus events drive it)
    if q == "" and not searchBox.focused then searchHint:Show() else searchHint:Hide() end
    local filtering = (q ~= "")
    for ci = 1, getn(containers) do
      local b = containers[ci]
      local list = slots[b]
      for s = 1, getn(list) do
        local btn = list[s]
        if btn and btn:IsShown() then
          if not filtering then
            btn.icon:SetAlpha(1)
          else
            local link = GetContainerItemLink(b, s)
            local match = false
            if link then
              -- item name is the bracketed segment of the link
              local _, _, nm = strfind(link, "%[(.+)%]")
              if nm and strfind(strlower(nm), q, 1, true) then match = true end
            end
            btn.icon:SetAlpha(match and 1 or 0.2)
          end
        end
      end
    end
  end

  searchBox:SetScript("OnTextChanged", function() ApplySearch() end)
  searchBox:SetScript("OnEscapePressed", function() this:SetText(""); this:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  searchBox:SetScript("OnEditFocusGained", function() searchBox.focused = true; searchHint:Hide() end)
  searchBox:SetScript("OnEditFocusLost", function() searchBox.focused = false; ApplySearch() end)

  -- =========================================================================
  -- options popup: columns + sort + the bag icons ----------------------------
  -- =========================================================================
  -- the strip always shows all six containers (backpack / bags 1-4 / keyring);
  -- hovering one focuses its items, and the keyring icon doubles as its toggle.
  local STRIP = { 0, 1, 2, 3, 4, KEYRING }
  local MENUPAD = 8
  local rowH = HEADER - 4
  local BAGICON = 24
  -- the strip's six icons set the menu width; rows above stretch to match.
  local STRIPW = getn(STRIP) * (BAGICON + GAP) - GAP
  local MENUW = STRIPW + MENUPAD * 2

  menu = CreateFrame("Frame", "HoryUIBagMenu", bag)
  menu:SetFrameStrata("DIALOG")
  menu:EnableMouse(true)               -- swallow clicks so they don't reach slots
  menu:SetWidth(MENUW)
  menu:SetHeight(MENUPAD * 2 + (rowH + 6) * 2 + BAGICON)
  HoryUI.CreateBackdrop(menu)
  -- ABOVE the bag so it never covers the grid (grows up from the menu button)
  menu:SetPoint("BOTTOMLEFT", menuBtn, "TOPLEFT", 0, 4)
  menu:Hide()
  -- close the popup with the bag (and drop any active highlight)
  bag:SetScript("OnHide", function() menu:Hide() end)

  -- row y-offsets (each row rowH tall, 6px gap); r3 = the bag-icon strip
  local r1 = -MENUPAD
  local r2 = -(MENUPAD + (rowH + 6))
  local r3 = -(MENUPAD + (rowH + 6) * 2)

  -- columns row: label (left) + steppers ( - [n] + ) on the right
  local colLabel = menu:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(colLabel, HoryUI.font.normal, 11, "OUTLINE")
  colLabel:SetPoint("TOPLEFT", menu, "TOPLEFT", MENUPAD, r1 - 3)
  colLabel:SetText("Columns")
  colLabel:SetTextColor(C.text2[1], C.text2[2], C.text2[3])

  colUp = MakeControl("+", "More columns", function()
    HoryUIDB.bagCols = Cols() + 1
    if HoryUIDB.bagCols > MAXCOL then HoryUIDB.bagCols = MAXCOL end
    if Relayout then Relayout() end
  end, nil, menu)
  colUp:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -MENUPAD, r1)

  colNum = menu:CreateFontString(nil, "OVERLAY")
  HoryUI.SetFont(colNum, HoryUI.font.number, 11, "OUTLINE")
  colNum:SetPoint("RIGHT", colUp, "LEFT", -4, 0)
  colNum:SetTextColor(C.text[1], C.text[2], C.text[3])
  colNum:SetWidth(18); colNum:SetJustifyH("CENTER")

  colDown = MakeControl("-", "Fewer columns", function()
    HoryUIDB.bagCols = Cols() - 1
    if HoryUIDB.bagCols < MINCOL then HoryUIDB.bagCols = MINCOL end
    if Relayout then Relayout() end
  end, nil, menu)
  colDown:SetPoint("RIGHT", colNum, "LEFT", -4, 0)

  -- sort row (full width)
  local sortBtn = MakeControl("Sort", "Compact bags (remove gaps)", function()
    if SortBags then SortBags() end
  end, nil, menu)
  sortBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", MENUPAD, r2)
  sortBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -MENUPAD, r2)

  -- the always-visible bag-icon strip
  local bagStrip = CreateFrame("Frame", nil, menu)
  bagStrip:SetWidth(STRIPW); bagStrip:SetHeight(BAGICON)
  bagStrip:SetPoint("TOPLEFT", menu, "TOPLEFT", MENUPAD, r3)

  -- a container is "active" only if it's in the live grid (keyring may be off);
  -- highlighting an inactive container would dim everything, so guard it.
  local function ContainerActive(hb)
    for ci = 1, getn(containers) do
      if containers[ci] == hb then return true end
    end
    return false
  end

  -- highlight = mark every cell of one bag (garnet border, even when empty) and
  -- dim the other bags' items so the focused bag pops. Clearing restores the
  -- quality borders + the search-filter dim state.
  HighlightBag = function(hb)
    if not ContainerActive(hb) then return end
    for ci = 1, getn(containers) do
      local b = containers[ci]
      local list = slots[b]
      for s = 1, getn(list) do
        local btn = list[s]
        if btn and btn:IsShown() then
          if b == hb then
            if btn.backdrop then btn.backdrop:SetBackdropBorderColor(C.accent_hi[1], C.accent_hi[2], C.accent_hi[3], 1) end
            if btn.icon then btn.icon:SetAlpha(1) end
          elseif btn.icon then
            btn.icon:SetAlpha(0.25)
          end
        end
      end
    end
  end
  ClearHighlight = function()
    for ci = 1, getn(containers) do
      local b = containers[ci]
      local list = slots[b]
      for s = 1, getn(list) do
        if list[s] then PaintQuality(list[s]) end
      end
    end
    ApplySearch()
  end

  -- resting border: garnet for the keyring while it's on, plain dark otherwise
  local function IconRestColor(b)
    if b == KEYRING and HoryUIDB.showKeyring then
      return C.accent[1], C.accent[2], C.accent[3], 1
    end
    return 0, 0, 0, 1
  end

  local bagIcons = {}      -- bagIcons[bag] = Button
  local function MakeBagIcon(b)
    local ib = CreateFrame("Button", nil, bagStrip)
    ib:SetWidth(BAGICON); ib:SetHeight(BAGICON)
    HoryUI.CreateBackdrop(ib)
    ib.tex = ib:CreateTexture(nil, "ARTWORK")
    ib.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ib.tex:SetPoint("TOPLEFT", ib, "TOPLEFT", 1, -1)
    ib.tex:SetPoint("BOTTOMRIGHT", ib, "BOTTOMRIGHT", -1, 1)
    ib:SetScript("OnEnter", function()
      HighlightBag(b)
      if ib.backdrop then ib.backdrop:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      if b == 0 then GameTooltip:SetText("Backpack")
      elseif b == KEYRING then
        GameTooltip:SetText("Keyring")
        GameTooltip:AddLine(HoryUIDB.showKeyring and "Click to hide" or "Click to show", 0.7, 0.7, 0.7)
      else GameTooltip:SetInventoryItem("player", ContainerIDToInventoryID(b)) end
      GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", function()
      ClearHighlight()
      if ib.backdrop then ib.backdrop:SetBackdropBorderColor(IconRestColor(b)) end
      GameTooltip:Hide()
    end)
    -- the keyring icon is its own on/off toggle (it replaces the old "K" button)
    if b == KEYRING then
      ib:SetScript("OnClick", function()
        HoryUIDB.showKeyring = not HoryUIDB.showKeyring
        RebuildContainerList()
        if Relayout then Relayout() end
        HighlightBag(KEYRING)        -- re-focus if it's now on (no-op if off)
      end)
    end
    return ib
  end

  RefreshBagIcons = function()
    for i = 1, getn(STRIP) do
      local b = STRIP[i]
      if not bagIcons[b] then bagIcons[b] = MakeBagIcon(b) end
      local ib = bagIcons[b]
      ib:ClearAllPoints()
      ib:SetPoint("LEFT", bagStrip, "LEFT", (i - 1) * (BAGICON + GAP), 0)
      local tex
      if b == 0 then tex = "Interface\\Buttons\\Button-Backpack-Up"
      elseif b == KEYRING then tex = "Interface\\ContainerFrame\\KeyRing-Bag-Icon"
      else
        -- a bag slot with no bag equipped shows the empty bag-slot art, not a
        -- backpack -- so it reads as "slot free" instead of a real container.
        tex = GetInventoryItemTexture("player", ContainerIDToInventoryID(b))
          or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
      end
      ib.tex:SetTexture(tex or "Interface\\Buttons\\Button-Backpack-Up")
      if ib.backdrop then ib.backdrop:SetBackdropBorderColor(IconRestColor(b)) end
      ib:Show()
    end
  end

  -- keep the keyring icon's active border in sync (called from Relayout)
  PaintKey = function()
    if bagIcons[KEYRING] and bagIcons[KEYRING].backdrop then
      bagIcons[KEYRING].backdrop:SetBackdropBorderColor(IconRestColor(KEYRING))
    end
  end

  menu:SetScript("OnHide", function() if ClearHighlight then ClearHighlight() end end)

  -- =========================================================================
  -- item buttons -------------------------------------------------------------
  -- =========================================================================
  -- (PaintQuality is forward-declared up top so ClearHighlight can call it)

  local function MakeSlot(b, s)
    local name = "HoryUIBagItem" .. (b == KEYRING and "K" or b) .. "_" .. s
    local btn = CreateFrame("Button", name, holders[b], "ContainerFrameItemButtonTemplate")
    btn:SetID(s)
    btn:SetWidth(SLOT); btn:SetHeight(SLOT)
    btn:SetNormalTexture("")          -- drop the chunky default border art
    HoryUI.CreateBackdrop(btn)

    -- keyring cells get a faint warm (gold) fill so they read as "keys" at a glance
    if b == KEYRING and btn.backdrop then
      btn.backdrop:SetBackdropColor(0.15, 0.13, 0.07, HoryUI.bg_alpha)
    end

    -- icon: trim the default art's transparent edge, inset inside our border
    btn.icon = getglobal(name .. "IconTexture")
    if btn.icon then
      btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      btn.icon:ClearAllPoints()
      btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
      btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end

    -- stack count -> tabular number, bottom-right
    btn.count = getglobal(name .. "Count")
    if btn.count then
      HoryUI.SetFont(btn.count, HoryUI.font.number, 11, "OUTLINE")
      btn.count:ClearAllPoints()
      btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end

    -- cooldown swipe comes with the template; just thin its art match
    btn.cd = getglobal(name .. "Cooldown")

    -- The template's own OnEnter/OnLeave already drive the GameTooltip + the native
    -- highlight glow, so we leave them untouched. (A garnet border-flash on hover used
    -- to live here, but it collided with the item-quality border -- removed.)

    return btn
  end

  -- colour a slot's border by item quality (uncommon+), else the soft default
  -- colour the border from the item LINK's quality hex (|cffRRGGBB). Turtle leaves
  -- GetContainerItemInfo's quality unset, so the link is the reliable source. Only
  -- uncommon+ get a colour; common (ffffff) / poor (9d9d9d) / empty keep the plain
  -- dark border so the grid stays calm and "rarity" actually reads.
  PaintQuality = function(btn)
    if not btn or not btn.backdrop then return end
    local r, g, bl
    if btn.hasItem and btn.link then
      local _, _, hex = strfind(btn.link, "|c%x%x(%x%x%x%x%x%x)")
      if hex then
        hex = strlower(hex)
        if hex ~= "ffffff" and hex ~= "9d9d9d" then
          r  = tonumber(strsub(hex, 1, 2), 16) / 255
          g  = tonumber(strsub(hex, 3, 4), 16) / 255
          bl = tonumber(strsub(hex, 5, 6), 16) / 255
        end
      end
    end
    if r then btn.backdrop:SetBackdropBorderColor(r, g, bl, 1)
    else btn.backdrop:SetBackdropBorderColor(0, 0, 0, 1) end
  end

  -- ensure slots[b][1..size] exist; hide any beyond the current size
  local function EnsureSlots(b)
    local size = BagSize(b)
    for s = 1, size do
      if not slots[b][s] then slots[b][s] = MakeSlot(b, s) end
    end
    for s = size + 1, getn(slots[b]) do
      if slots[b][s] then slots[b][s]:Hide() end
    end
    return size
  end

  -- =========================================================================
  -- per-slot content update --------------------------------------------------
  -- =========================================================================
  local function UpdateSlot(b, s)
    local btn = slots[b][s]
    if not btn then return end
    local texture, count, locked, quality = GetContainerItemInfo(b, s)
    btn.quality = quality
    btn.link = GetContainerItemLink(b, s)   -- the link carries the true quality colour
    SetItemButtonTexture(btn, texture)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked, 0.5, 0.5, 0.5)
    btn.hasItem = texture and 1 or nil
    -- cooldown swipe (template helper resolves <name>Cooldown itself)
    ContainerFrame_UpdateCooldown(b, btn)
    PaintQuality(btn)
    btn:Show()
  end

  local function UpdateBag(b)
    local size = EnsureSlots(b)
    for s = 1, size do UpdateSlot(b, s) end
  end

  -- =========================================================================
  -- layout: pack every shown slot into one Cols()-wide grid ------------------
  -- =========================================================================
  Relayout = function()
    local cols = Cols()
    colNum:SetText(cols)
    PaintKey()

    -- the keyring is the only container that can leave the active set; when it's
    -- off its buttons must be hidden or they'd linger from the last layout.
    if not HoryUIDB.showKeyring then
      for s = 1, getn(slots[KEYRING]) do
        if slots[KEYRING][s] then slots[KEYRING][s]:Hide() end
      end
    end

    local index = 0          -- running cell index across all containers
    for ci = 1, getn(containers) do
      local b = containers[ci]
      local size = EnsureSlots(b)
      for s = 1, size do
        local btn = slots[b][s]
        local col = mod(index, cols)
        local row = floor(index / cols)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bag, "TOPLEFT",
          PAD + col * (SLOT + GAP),
          -(PAD + HEADER + row * (SLOT + GAP)))
        UpdateSlot(b, s)
        index = index + 1
      end
    end

    -- size the frame to the grid (+ header + footer line for money/free)
    local rows = (index > 0) and (floor((index - 1) / cols) + 1) or 1
    local gridW = cols * (SLOT + GAP) - GAP
    local FOOTER = 18
    bag:SetWidth(gridW + PAD * 2)
    bag:SetHeight(PAD + HEADER + rows * (SLOT + GAP) - GAP + FOOTER + PAD)

    ApplySearch()
  end

  -- =========================================================================
  -- header readouts: money + free slots --------------------------------------
  -- =========================================================================
  local function UpdateMoney()
    money:SetText(MoneyString(GetMoney()))
  end

  local function UpdateFree()
    local free, total = 0, 0
    for ci = 1, getn(containers) do
      local b = containers[ci]
      local size = BagSize(b)
      total = total + size
      for s = 1, size do
        if not GetContainerItemInfo(b, s) then free = free + 1 end
      end
    end
    freetext:SetText(free .. " / " .. total .. " free")
  end

  -- =========================================================================
  -- sort: honest "compact" -- 1.12 exposes no SortBags(), and item moves are
  -- async (each is a server round-trip that briefly *locks* the item), so a
  -- synchronous in-frame reorder cannot be done reliably without scrambling.
  -- We therefore do the one move that is always safe: COMPACTION. Pull each
  -- item toward the first empty slot, removing gaps. Moving an item into a
  -- guaranteed-empty slot can never overwrite anything, so a locked item just
  -- no-ops and the user re-clicks. This is gap-removal, not type-grouping.
  -- (Stacks still merge naturally as the game auto-stacks on move.)
  -- =========================================================================
  SortBags = function()
    if not bag:IsShown() then return end
    -- flat ordered list of (bag,slot) cells across active containers (no keyring)
    local cells = {}
    for ci = 1, getn(containers) do
      local b = containers[ci]
      if b ~= KEYRING then
        local size = BagSize(b)
        for s = 1, size do
          cells[getn(cells) + 1] = { b, s }
        end
      end
    end
    local n = getn(cells)
    ClearCursor()

    -- walk forward; for each empty cell, find the next occupied cell after it and
    -- move that item back. One pass shifts everything toward the front by one gap
    -- run; the BAG_UPDATE this triggers refreshes the grid and the user can click
    -- again to settle the rest (locks resolve between clicks).
    local write = 1
    for read = 1, n do
      local br, sr = cells[read][1], cells[read][2]
      local texture, _, locked = GetContainerItemInfo(br, sr)
      if texture and not locked then
        local bw, sw = cells[write][1], cells[write][2]
        if write ~= read then
          local wtex, _, wlocked = GetContainerItemInfo(bw, sw)
          if not wtex and not wlocked then        -- destination is empty: safe move
            PickupContainerItem(br, sr)
            PickupContainerItem(bw, sw)
            ClearCursor()
          end
        end
        write = write + 1
      end
    end
  end

  -- =========================================================================
  -- open / close hooks -- route Blizzard's bag funcs to our frame ------------
  -- =========================================================================
  local function Open()  bag:Show() end
  local function Close() bag:Hide() end
  local function Toggle()
    if bag:IsShown() then bag:Hide() else bag:Show() end
  end

  -- preserve the pre-hook globals as HoryUI.bagOrig.* so the override is
  -- reversible (and any addon that hooked these can still reach the originals).
  HoryUI.bagOrig = {
    ToggleBackpack = ToggleBackpack, OpenBackpack = OpenBackpack,
    OpenAllBags = OpenAllBags, CloseAllBags = CloseAllBags,
    ToggleBag = ToggleBag, ToggleKeyRing = ToggleKeyRing,
  }

  ToggleBackpack = function() Toggle() end
  OpenBackpack   = function() Open() end
  OpenAllBags    = function() Toggle() end
  CloseAllBags   = function() Close() end
  ToggleBag      = function() Toggle() end          -- any bag click opens the one-bag
  ToggleKeyRing  = function()
    -- show the bag and force the keyring on (the in-frame "K" toggles it off)
    HoryUIDB.showKeyring = true
    RebuildContainerList()
    Relayout()
    bag:Show()
  end

  -- =========================================================================
  -- hide Blizzard's ContainerFrame1..5 so they never appear -------------------
  -- =========================================================================
  -- our hooks already route every open path to HoryUIBag, so ContainerFrameN are
  -- never told to show. Keep a light OnShow guard for any indirect :Show() (loot,
  -- merchant). We deliberately leave their events registered -- the FrameXML
  -- helpers we call (ContainerFrame_UpdateCooldown, SetItemButton*) act on the
  -- button we pass, not on these frames, so a hidden-but-live frame is harmless.
  for i = 1, 5 do
    local cf = getglobal("ContainerFrame" .. i)
    if cf then
      cf:Hide()
      cf:SetScript("OnShow", function() this:Hide() end)
    end
  end

  -- =========================================================================
  -- driver: events + throttled relayout --------------------------------------
  -- =========================================================================
  -- BAG_UPDATE can fire in bursts (loot, vendor) -- coalesce to one relayout.
  local driver = CreateFrame("Frame")
  driver.dirty = false
  driver.cdDirty = false
  driver.lockDirty = false
  driver.acc = 0
  driver:RegisterEvent("PLAYER_LOGOUT")
  driver:RegisterEvent("BAG_UPDATE")
  driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
  driver:RegisterEvent("ITEM_LOCK_CHANGED")
  driver:RegisterEvent("PLAYER_MONEY")

  driver:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      this:SetScript("OnUpdate", nil)
      return
    elseif event == "BAG_UPDATE" then
      this.dirty = true
    elseif event == "BAG_UPDATE_COOLDOWN" then
      this.cdDirty = true
    elseif event == "ITEM_LOCK_CHANGED" then
      this.lockDirty = true
    elseif event == "PLAYER_MONEY" then
      UpdateMoney()
    end
  end)

  driver:SetScript("OnUpdate", function()
    this.acc = this.acc + arg1
    if this.acc < 0.1 then return end
    this.acc = 0

    if this.dirty then
      this.dirty = false
      this.cdDirty = false
      this.lockDirty = false
      Relayout()
      UpdateMoney()
      UpdateFree()
      return
    end

    if this.cdDirty then
      this.cdDirty = false
      for ci = 1, getn(containers) do
        local b = containers[ci]
        local size = BagSize(b)
        for s = 1, size do
          local btn = slots[b][s]
          if btn and btn.hasItem then ContainerFrame_UpdateCooldown(b, btn) end
        end
      end
    end

    if this.lockDirty then
      this.lockDirty = false
      for ci = 1, getn(containers) do
        local b = containers[ci]
        local size = BagSize(b)
        for s = 1, size do
          local btn = slots[b][s]
          if btn and btn:IsShown() then
            local _, _, locked = GetContainerItemInfo(b, s)
            SetItemButtonDesaturated(btn, locked, 0.5, 0.5, 0.5)
          end
        end
      end
    end
  end)

  -- =========================================================================
  -- first build --------------------------------------------------------------
  -- =========================================================================
  for ci = 1, getn(containers) do UpdateBag(containers[ci]) end
  Relayout()
  UpdateMoney()
  UpdateFree()
  bag:Hide()         -- start closed; opens via the hooked bag keys
end)
