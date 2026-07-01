-- HoryUI :: vendorprice -- appends an item's vendor SELL price to its tooltip.
--
-- 1.12 has no vendor-price API (see data/sellprices.lua), so the value comes
-- from the vendored static DB HoryUI.sellData ([itemID] = "sell,buy"). We can't
-- trust GameTooltip:GetItem() in vanilla, so -- exactly like pfUI's libtooltip --
-- we hook each GameTooltip Set* method to capture the item link (+ stack count
-- where the source exposes it). A child frame parented to GameTooltip rides its
-- parent's show/hide (a shown-by-default child gets OnShow/OnHide when the parent
-- shows/hides) and draws the sell value with native coin icons (SetTooltipMoney).
-- Chat/quest hyperlinks open ItemRefTooltip synchronously inside SetItemRef, so
-- that path is handled directly rather than via the OnShow watcher.
--
-- Dormant while real pfUI is active -- its own `sellvalue` module already does
-- this and we must not stack a second coin row.

HoryUI:RegisterModule("vendorprice", true, function()
  if HoryUI._pfuiActive then return end          -- pfUI's sellvalue handles it
  if not HoryUI.sellData then return end
  if not SetTooltipMoney then return end          -- native coin-row helper (FrameXML)

  local sellData = HoryUI.sellData
  local strfind, tonumber = string.find, tonumber

  -- shared: given a resolved item link + stack count, look up the sell price and
  -- draw it as a native coin row. Skipped while a merchant is open (vanilla
  -- already shows the sell price there, so a second row would duplicate it).
  local function AddSell(tt, link, count)
    if not link then return end
    if MerchantFrame and MerchantFrame:IsShown() then return end
    local _, _, id = strfind(link, "item:(%d+):")
    id = id and tonumber(id)
    local data = id and sellData[id]
    if not data then return end
    local _, _, sell = strfind(data, "(%d+),")     -- "sell,buy" -> sell copper
    sell = sell and tonumber(sell)
    if not sell or sell <= 0 then return end        -- 0 = no vendor value (quest/soulbound junk)
    SetTooltipMoney(tt, sell * (count or 1))
    tt:Show()                                       -- resize to fit the new coin row
  end

  ----------------------------------------------------------------------------
  -- GameTooltip: capture the link on each Set*, append on show.
  ----------------------------------------------------------------------------
  local curLink, curCount

  -- hook a GameTooltip Set* method (save + replace; no hooksecurefunc in 1.12).
  -- `resolve(a1,a2,a3)` returns link, count for that source (nil link = not an
  -- item, e.g. a spell/unit tooltip).
  local function hook(method, resolve)
    if not GameTooltip[method] then return end
    local orig = GameTooltip[method]
    GameTooltip[method] = function(self, a1, a2, a3)
      curLink, curCount = resolve(a1, a2, a3)
      return orig(self, a1, a2, a3)
    end
  end

  hook("SetBagItem", function(bag, slot)
    if not bag or not slot then return end
    local _, count = GetContainerItemInfo(bag, slot)
    return GetContainerItemLink(bag, slot), count
  end)
  hook("SetInventoryItem", function(unit, slot)
    return GetInventoryItemLink(unit, slot)
  end)
  hook("SetMerchantItem", function(i) return GetMerchantItemLink(i) end)
  hook("SetLootItem", function(slot) return GetLootSlotLink(slot) end)
  hook("SetLootRollItem", function(id) return GetLootRollItemLink(id) end)
  hook("SetQuestItem", function(t, i) return GetQuestItemLink(t, i) end)
  hook("SetQuestLogItem", function(t, i) return GetQuestLogItemLink(t, i) end)
  hook("SetTradePlayerItem", function(i) return GetTradePlayerItemLink(i) end)
  hook("SetTradeTargetItem", function(i) return GetTradeTargetItemLink(i) end)
  hook("SetCraftItem", function(sk, rg) return GetCraftReagentItemLink(sk, rg) end)
  hook("SetTradeSkillItem", function(sk, rg)
    if rg then return GetTradeSkillReagentItemLink(sk, rg) end
    return GetTradeSkillItemLink(sk)
  end)
  hook("SetAuctionItem", function(atype, i)
    local _, _, count = GetAuctionItemInfo(atype, i)
    return GetAuctionItemLink(atype, i), count
  end)
  hook("SetHyperlink", function(link)
    if not link then return end
    local _, _, ltype = strfind(link, "^(%a+):")   -- only item hyperlinks carry a vendor price
    if ltype == "item" then return link end
  end)

  -- a shown-by-default child of GameTooltip: it receives OnShow/OnHide whenever
  -- the tooltip itself shows/hides. Never Hide() it manually or the trick breaks.
  local watcher = CreateFrame("Frame", nil, GameTooltip)
  watcher:RegisterEvent("PLAYER_LOGOUT")
  watcher:SetScript("OnEvent", function()
    -- Error-132 safety: go inert on shutdown
    this:SetScript("OnShow", nil)
    this:SetScript("OnHide", nil)
    this:SetScript("OnEvent", nil)
  end)
  watcher:SetScript("OnShow", function()
    AddSell(GameTooltip, curLink, curCount)
  end)
  watcher:SetScript("OnHide", function()
    -- clear so a following non-item tooltip (spell/unit) can't reuse a stale link
    curLink, curCount = nil, nil
  end)

  ----------------------------------------------------------------------------
  -- ItemRefTooltip (chat / quest-log hyperlinks): SetItemRef shows the tooltip
  -- synchronously, so the OnShow watcher can't help -- append directly after.
  ----------------------------------------------------------------------------
  local origSetItemRef = SetItemRef
  SetItemRef = function(link, text, button)
    origSetItemRef(link, text, button)
    local _, _, ltype = strfind(link or "", "^(%a+):")
    if ltype == "item" then AddSell(ItemRefTooltip, link, 1) end
  end
end)
