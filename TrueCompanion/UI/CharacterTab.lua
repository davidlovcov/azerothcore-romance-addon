--[[
  TrueCompanion - Character tab: the selected companion's level, XP, gold,
  bags, gear, quests and spells (real game data from the server).
  Refreshes while the tab is open.
]]

local TC = _G.TrueCompanion
local W = TC.W
local UI = TC.UI

local REFRESH_SECONDS = 10

local QUALITY_COLORS = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "e6cc80",
}

local function money(copper)
    copper = tonumber(copper) or 0
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then table.insert(out, ("|cffffd100%dg|r"):format(g)) end
    if s > 0 or g > 0 then table.insert(out, ("|cffc7c7cf%ds|r"):format(s)) end
    table.insert(out, ("|cffeda55f%dc|r"):format(c))
    return table.concat(out, " ")
end

-- A titled, scrollable text list.
local function makeList(parent, title, w, h)
    local box = W.Panel(parent, w, h, 0.35)
    local head = W.Label(box, title, 12, W.GOLD)
    head:SetPoint("TOPLEFT", 8, -6)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -24)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(w - 36)
    child:SetHeight(h)
    scroll:SetScrollChild(child)
    local text = W.Label(child, "", 11, W.TEXT)
    text:SetPoint("TOPLEFT", 2, 0)
    text:SetWidth(w - 40)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    box.head = head
    box.text = text
    function box:SetLines(lines, count)
        text:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff888888(nothing)|r")
        child:SetHeight(math.max(h - 30, (#lines + 1) * 14))
        head:SetText(count and ("%s (%d)"):format(title, count) or title)
    end
    return box
end

local function build(f)
    local name = W.Label(f, "", 16, W.GOLD, "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 2, -2)
    local info = W.Label(f, "", 11, W.MUTED)
    info:SetPoint("TOPLEFT", 2, -24)
    info:SetWidth(470)
    local xp = W.Bar(f, "Experience", 250, { 0.55, 0.35, 0.85 })
    xp:SetPoint("TOPRIGHT", -4, -2)
    local gold = W.Label(f, "", 12, W.TEXT)
    gold:SetPoint("TOPRIGHT", -4, -34)

    local bags = makeList(f, "Bags", 250, 196)
    bags:SetPoint("TOPLEFT", 0, -52)
    local quests = makeList(f, "Quests", 250, 196)
    quests:SetPoint("TOPLEFT", 254, -52)
    local spells = makeList(f, "Spells & abilities", 248, 196)
    spells:SetPoint("TOPLEFT", 508, -52)
    f.spellsBox = spells
    local gear = makeList(f, "Equipped", 502, 150)
    gear:SetPoint("TOPLEFT", 0, -252)

    local hint = W.Label(f, "Ask in chat: \"what's in your bags?\", \"give me your linen cloth\", \"share your quests\", " ..
        "\"lead the way\"... See COMMANDS.md for the full list.\n\nNew spells: tell her \"learn your spells\"; she goes to " ..
        "her class trainer and comes back.", 10, W.MUTED)
    hint:SetPoint("TOPLEFT", 508, -256)
    hint:SetWidth(248)

    local status = W.Label(f, "", 11, W.MUTED)
    status:SetPoint("BOTTOMLEFT", 2, 10)
    local refresh = W.Button(f, "Refresh", 90, 22)
    refresh:SetPoint("BOTTOMRIGHT", -4, 6)
    local orderButton = W.Button(f, "Group quests", 100, 22, function() UI:ShowTab("quests") end)
    orderButton:SetPoint("BOTTOMRIGHT", -208, 6)
    W.Tooltip(orderButton, "Group quests", "The quests of the whole group: order, lead, ignore, abandon (Quests tab).")
    f.orderButton = orderButton
    -- same as typing "share your quests" in the chat: she shares every quest you don't have yet
    local share = W.Button(f, "Share quests", 100, 22, function()
        local g = TC.state.selected
        if not g then return end
        TC:SetTyping(g, true)
        TC:Request("chat", { guid = g, text = "share your quests" })
        status:SetText("Asked her to share her quests.")
    end)
    share:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
    W.Tooltip(share, "Share quests", "She shares every quest of hers that you don't have yet and can take.\nSame as saying \"share your quests\" in the chat.")

    local sheet
    local elapsed = 0

    function f:Render()
        local g, comp, char = TC:Selected()
        sheet = g and TC.state.sheets[g]
        if not g then
            name:SetText("No companion selected")
            info:SetText("Select a companion on the Companion tab first.")
            return
        end
        name:SetText((char and char.name) or (comp and comp.name) or "?")
        if not sheet then
            info:SetText("Loading...")
            return
        end
        local follow = sheet.follow == "lead" and ("|cffffd100leading|r" .. (sheet.leadQuest and (" to \"" .. sheet.leadQuest .. "\"") or ""))
            or sheet.follow == "behind" and ("walking behind |cffffd100" .. (sheet.leader or "?") .. "|r")
            or sheet.follow == "stay" and "waiting" or sheet.follow == "follow" and "following you" or "-"
        info:SetText(("Level %d  |  %d%% health  |  bags %d/%d free  |  %s"):format(sheet.level or 0, sheet.health or 0,
            sheet.freeSlots or 0, sheet.totalSlots or 0, follow))
        local next = tonumber(sheet.xpNext) or 0
        if next > 0 then
            xp:Set(math.floor(100 * (tonumber(sheet.xp) or 0) / next))
            xp.value:SetText(("%d / %d"):format(sheet.xp or 0, next))
        else
            xp:Set(100)
            xp.value:SetText("max level")
        end
        gold:SetText(money(sheet.money))

        local lines = {}
        for _, it in ipairs(sheet.items or {}) do
            local color = QUALITY_COLORS[tonumber(it.quality) or 1] or "ffffff"
            table.insert(lines, ("|cff%s%s|r%s%s"):format(color, it.name or "?", (tonumber(it.count) or 1) > 1 and (" x" .. it.count) or "",
                it.soulbound and " |cff888888(bound)|r" or ""))
        end
        bags:SetLines(lines, #(sheet.items or {}))

        lines = {}
        for _, q in ipairs(sheet.quests or {}) do
            local mark = q.complete and "|cff60ff60done|r" or (q.shared and "|cffffd100shared|r" or "|cff888888companion only|r")
            table.insert(lines, ("|cffffd100[%d]|r %s  %s"):format(q.level or 0, q.title or "?", mark))
            if q.progress and q.progress ~= "" and not q.complete then
                table.insert(lines, "   |cffaaaaaa" .. q.progress .. "|r")
            end
        end
        if sheet.available and #sheet.available > 0 then
            table.insert(lines, " ")
            table.insert(lines, "|cffffd100Available nearby|r |cff888888(say \"pick up your quests\")|r")
            for _, q in ipairs(sheet.available) do
                table.insert(lines, ("|cffffd100[%d]|r %s%s"):format(q.level or 0, q.title or "?", q.classQuest and " |cff9ad2ff(class)|r" or ""))
                table.insert(lines, ("   |cffaaaaaa%s, %d yd %s|r"):format(q.giver or "?", q.distance or 0, q.direction or ""))
            end
        end
        quests:SetLines(lines, #(sheet.quests or {}))

        -- what her class trainer can teach her now (and soon), above what she knows
        lines = {}
        local function spellName(s) return (s.name or "?") .. ((s.rank or "") ~= "" and (" |cff888888(" .. s.rank .. ")|r") or "") end
        if sheet.learnable and #sheet.learnable > 0 then
            local cost = tonumber(sheet.learnableCost) or 0
            local short = sheet.money and cost > (tonumber(sheet.money) or 0)
            table.insert(lines, ("|cff60ff60Can learn now|r |cffaaaaaa(%s at her class trainer%s)|r"):format(money(cost),
                short and ("; |cffff8040she has only|r " .. money(sheet.money)) or ""))
            for _, s in ipairs(sheet.learnable) do table.insert(lines, "  " .. spellName(s)) end
        end
        if sheet.learnSoon and #sheet.learnSoon > 0 then
            table.insert(lines, "|cffffd100Soon|r")
            for _, s in ipairs(sheet.learnSoon) do table.insert(lines, ("  %s |cff888888level %d|r"):format(spellName(s), s.level or 0)) end
        end
        if #lines > 0 then table.insert(lines, "|cffffd100Known|r") end
        for _, s in ipairs(sheet.spells or {}) do table.insert(lines, s.name or "?") end
        spells:SetLines(lines, #(sheet.spells or {}))
        spells.head:SetText(("Spells & abilities (%d)%s"):format(#(sheet.spells or {}),
            sheet.learnable and #sheet.learnable > 0 and (" |cff60ff60+%d to learn|r"):format(#sheet.learnable) or ""))

        lines = {}
        for _, it in ipairs(sheet.gear or {}) do
            local color = QUALITY_COLORS[tonumber(it.quality) or 1] or "ffffff"
            table.insert(lines, ("|cff%s%s|r"):format(color, it.name or "?"))
        end
        gear:SetLines(lines, #(sheet.gear or {}))
    end

    function f:Request()
        local g = TC.state.selected
        if not g then
            f:Render()
            return
        end
        status:SetText("Updating...")
        TC:Request("get_character_sheet", { guid = g }, function(msg)
            if msg.op == "ack" and not msg.ok then
                status:SetText("|cffff6060" .. TC:AckText(msg) .. "|r")
            else
                status:SetText(("Updated %s"):format(date("%H:%M:%S")))
            end
        end)
    end

    refresh:SetScript("OnClick", function() f:Request() end)
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= REFRESH_SECONDS then
            elapsed = 0
            f:Request()
        end
    end)
    TC:On("SHEET_CHANGED", function(g) if f:IsShown() and g == TC.state.selected then f:Render() end end)
    TC:On("SELECTION_CHANGED", function() if f:IsShown() then f:Render() f:Request() end end)
    f.OnShowTab = function()
        elapsed = 0
        f:Render()
        f:Request()
    end
end

UI:RegisterTab("character", "Character", build, { group = "companion" })
