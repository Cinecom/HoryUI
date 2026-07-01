-- HoryUI :: selltrash -- a "Sell Trash" button on the merchant window that
-- vendors every grey (poor-quality) item in your bags in one click.
--
-- Grey detection uses the item LINK's colour hex (|cff9d9d9d) -- the same reliable
-- source bags.lua / vendorprice.lua use, since 1.12 (Turtle) leaves
-- GetContainerItemInfo's quality return unset. Selling is UseContainerItem while
-- the merchant window is open (vanilla treats that as a sell, not a use). The
-- reported total is summed from the vendored sell-price DB (HoryUI.sellData) when
-- the item is present; unknown items still sell, they just don't add to the total.
--
-- The button is a child of MerchantFrame, so it shows/hides with the merchant
-- window automatically -- no MERCHANT_SHOW/CLOSED wiring, no OnUpdate, no events,
-- so nothing to defuse on logout.

HoryUI:RegisterModule("selltrash", true, function()
  if not MerchantFrame then return end
  local C = HoryUI.color
  local strfind, strlower, tonumber = string.find, string.lower, tonumber
  local floor, mod = math.floor, math.mod
  local GetContainerNumSlots = GetContainerNumSlots
  local GetContainerItemLink, GetContainerItemInfo = GetContainerItemLink, GetContainerItemInfo
  local UseContainerItem = UseContainerItem
  local sellData = HoryUI.sellData

  local function Money(c)
    local g = floor(c / 10000)
    local s = floor(mod(c, 10000) / 100)
    local cop = mod(c, 100)
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if g > 0 or s > 0 then out = out .. s .. "s " end
    return out .. cop .. "c"
  end

  -- sell price (copper) for an item link from the vendored DB; 0 if unknown/none
  local function SellValue(link)
    if not sellData then return 0 end
    local _, _, id = strfind(link, "item:(%d+):")
    id = id and tonumber(id)
    local data = id and sellData[id]
    if not data then return 0 end
    local _, _, sell = strfind(data, "(%d+),")       -- "sell,buy" -> sell copper
    return (sell and tonumber(sell)) or 0
  end

  local function SellTrash()
    if not MerchantFrame:IsShown() then return end
    local count, value = 0, 0
    for bag = 0, 4 do
      local slots = GetContainerNumSlots(bag) or 0
      for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        -- poor quality (grey) = the |cff9d9d9d colour prefix on the link
        if link and strfind(strlower(link), "|cff9d9d9d") then
          local _, itemCount, locked = GetContainerItemInfo(bag, slot)
          if not locked then
            count = count + 1
            value = value + SellValue(link) * (itemCount or 1)
            UseContainerItem(bag, slot)                -- sells at an open merchant
          end
        end
      end
    end
    if count > 0 then
      local msg = "HoryUI: sold " .. count .. " trash item" .. (count == 1 and "" or "s")
      if value > 0 then msg = msg .. " for " .. Money(value) end
      DEFAULT_CHAT_FRAME:AddMessage(msg, C.accent_hi[1], C.accent_hi[2], C.accent_hi[3])
    else
      DEFAULT_CHAT_FRAME:AddMessage("HoryUI: no trash to sell.", C.text2[1], C.text2[2], C.text2[3])
    end
  end

  -- above the merchant window's top-left corner, so it never overlaps the item
  -- grid, page buttons, or the money frame regardless of the (pfskin) skin.
  local btn = HoryUI.CreateButton(MerchantFrame, "Sell Trash", SellTrash)
  btn:SetWidth(90)
  btn:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 12, 4)

  -- CreateButton wires a border-hover; re-wire it here to also carry a tooltip
  btn:SetScript("OnEnter", function()
    local a = C.accent_hi
    if this.backdrop then this.backdrop:SetBackdropBorderColor(a[1], a[2], a[3], 1) end
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Sell Trash")
    GameTooltip:AddLine("Sell every grey (poor) item in your bags.", C.text2[1], C.text2[2], C.text2[3], 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    if this.backdrop then this.backdrop:SetBackdropBorderColor(0, 0, 0, 1) end
    GameTooltip:Hide()
  end)
end)
