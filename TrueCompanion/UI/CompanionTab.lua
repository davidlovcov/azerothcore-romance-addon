--[[
  TrueCompanion - Companion tab: account characters, status, summon/return.
]]

local TC = _G.TrueCompanion
local W = TC.W
local UI = TC.UI

local ROWS = 9
local ROW_H = 38

local function build(f)
    -- ---------------------------------------------------------------- character list
    local list = W.Panel(f, 330, 440)
    list:SetPoint("TOPLEFT", 0, 0)
    local head = W.Heading(list, "Your characters")
    head:SetPoint("TOPLEFT", 12, -10)
    local refresh = W.Button(list, "Refresh", 70, 20, function() TC:Request("list_chars") end)
    refresh:SetPoint("TOPRIGHT", -10, -6)

    local empty = W.Label(list, "", 11, W.MUTED)
    empty:SetPoint("TOP", 0, -60)
    empty:SetWidth(290)
    empty:SetJustifyH("CENTER")

    local rows = {}
    local offset = 0
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 8, -32 - (i - 1) * (ROW_H + 6))
        r:SetPoint("TOPRIGHT", -8, -32 - (i - 1) * (ROW_H + 6))
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(1, 1, 1, 0.04)
        r.bg = bg
        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(30)
        icon:SetHeight(30)
        icon:SetPoint("LEFT", 4, 0)
        r.icon = icon
        r.name = W.Label(r, "", 13, W.TEXT, "GameFontNormal")
        r.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
        r.info = W.Label(r, "", 10, W.MUTED)
        r.info:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
        r.status = W.Label(r, "", 10, W.MUTED)
        r.status:SetPoint("RIGHT", -6, 6)
        r.status:SetJustifyH("RIGHT")
        r.stage = W.Label(r, "", 10, W.ROSE)
        r.stage:SetPoint("RIGHT", -6, -8)
        r.stage:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self)
            if self.char then TC:Select(self.char.guid) end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.char then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.char.name, 1, 0.82, 0.25)
            local st = TC:CharStatus(self.char)
            GameTooltip:AddLine(st.label, st.color[1], st.color[2], st.color[3])
            if self.char.reason and self.char.reason ~= "" then GameTooltip:AddLine(self.char.reason, 1, 1, 1, true) end
            if self.char.linked then GameTooltip:AddLine("From a linked account", 0.7, 0.7, 0.7) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local n = #TC.state.chars
        offset = math.max(0, math.min(math.max(0, n - ROWS), offset - delta))
        f:RefreshList()
    end)

    function f:RefreshList()
        local chars = TC.state.chars
        UI.SetShown(empty, #chars == 0)
        if not TC.state.connected then
            empty:SetText("Waiting for the server...\nIs mod-true-companion installed on this realm?")
        else
            empty:SetText("No other characters on your account.\nCreate some characters to use them as companions.")
        end
        for i = 1, ROWS do
            local r = rows[i]
            local c = chars[i + offset]
            r.char = c
            if not c then
                r:Hide()
            else
                r:Show()
                local st = TC:CharStatus(c)
                W.SetClassIcon(r.icon, c.class)
                local cr, cg, cb = TC:ClassColor(c.class)
                if not st.enabled then cr, cg, cb = 0.5, 0.5, 0.5 end
                r.name:SetText(c.name)
                r.name:SetTextColor(cr, cg, cb)
                r.info:SetText(("Level %d %s %s"):format(c.level or 0, c.raceName or "", c.className or ""))
                r.status:SetText(st.label)
                r.status:SetTextColor(st.color[1], st.color[2], st.color[3])
                r.stage:SetText(c.configured and (c.stageLabel or "") or "")
                r.icon:SetDesaturated(not st.enabled)
                r:SetAlpha(st.enabled and 1 or 0.55)
                if tonumber(c.guid) == TC.state.selected then
                    r.bg:SetTexture(1, 0.82, 0.25, 0.16)
                else
                    r.bg:SetTexture(1, 1, 1, 0.04)
                end
            end
        end
    end

    -- ---------------------------------------------------------------- companion card
    local card = W.Panel(f, 420, 440)
    card:SetPoint("TOPRIGHT", 0, 0)

    local portraitFrame = W.Panel(card, 84, 84, 0.9)
    portraitFrame:SetPoint("TOPLEFT", 16, -16)
    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", 6, -6)
    portrait:SetPoint("BOTTOMRIGHT", -6, 6)

    local name = W.Label(card, "Choose a companion", 20, W.GOLD, "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", portraitFrame, "TOPRIGHT", 14, -4)
    local sub = W.Label(card, "Select one of your characters on the left.", 11, W.MUTED)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    local stage = W.Label(card, "", 13, W.ROSE, "GameFontNormal")
    stage:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
    local mood = W.Label(card, "", 11, W.TEXT)
    mood:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -4)

    local statusLine = W.Label(card, "", 11, W.MUTED)
    statusLine:SetPoint("TOPLEFT", 16, -116)
    statusLine:SetWidth(390)
    local aiLine = W.Label(card, "", 11, W.MUTED)
    aiLine:SetPoint("TOPLEFT", statusLine, "BOTTOMLEFT", 0, -6)
    aiLine:SetWidth(390)

    local call = W.Button(card, "Call companion", 130, 26, function()
        local g = TC.state.selected
        if not g then return end
        TC:Request("summon", { guid = g }, function(msg)
            if msg.op == "ack" and msg.ok then
                TC:Print("Calling your companion...")
            elseif msg.op == "ack" then
                TC:Print("|cffff6060Cannot call: " .. TC:AckText(msg) .. "|r")
            end
            TC:Request("list_chars")
        end)
    end)
    call:SetPoint("TOPLEFT", 16, -170)

    local dismiss = W.Button(card, "Send home", 110, 26, function()
        local g = TC.state.selected
        if not g then return end
        TC:Request("dismiss", { guid = g, logout = true }, function() TC:Request("list_chars") end)
    end)
    dismiss:SetPoint("LEFT", call, "RIGHT", 8, 0)

    local aiToggle = W.Button(card, "Disable AI", 110, 26)
    aiToggle:SetPoint("LEFT", dismiss, "RIGHT", 8, 0)
    aiToggle:SetScript("OnClick", function()
        local g, comp, char = TC:Selected()
        if not g or not comp then return end
        local s = comp.settings or {}
        local online = char and (char.status == "in_party" or char.status == "summoned")
        if s.aiEnabled ~= false and online and not char.active then
            s.aiEnabled = true      -- enabled but not running yet: (re)activate now
        else
            s.aiEnabled = not (s.aiEnabled ~= false)
        end
        TC:Request("save_settings", { guid = g, settings = s }, function() TC:Request("list_chars") end)
    end)

    local configure = W.Button(card, "Personality...", 130, 22, function() UI:ShowTab("personality") end)
    configure:SetPoint("TOPLEFT", call, "BOTTOMLEFT", 0, -10)
    local talk = W.Button(card, "Talk", 110, 22, function() UI:ShowTab("chat") end)
    talk:SetPoint("LEFT", configure, "RIGHT", 8, 0)
    local rel = W.Button(card, "Relationship", 110, 22, function() UI:ShowTab("relationship") end)
    rel:SetPoint("LEFT", talk, "RIGHT", 8, 0)

    local HELP = "Companions are your own characters, logged in as Playerbots. Combat, following and spells stay with " ..
        "Playerbots; only the companion you select here talks through the AI.\n\n" ..
        "Whisper them normally or use the Chat tab. Plain Playerbots commands (follow, stay, attack...) still work; " ..
        "prefix a line with ! to force a command."
    -- before the first companion is called: three steps instead of the explanation
    local GETTING_STARTED = "|cffffd100Getting started|r\n" ..
        "1. Pick one of your characters on the left.\n" ..
        "2. Click \"Call companion\": they log in and join your party.\n" ..
        "3. Talk to them (whisper, or the Chat tab), or use the Commands and Quests tabs.\n\n" ..
        "The tabs in the second row (Chat, Character, ...) are about the companion selected here."
    local help = W.Label(card, HELP, 11, W.MUTED)
    help:SetPoint("BOTTOMLEFT", 16, 16)
    help:SetWidth(390)
    f.help = help

    function f:RefreshCard()
        help:SetText(#TC:ActiveNames() == 0 and GETTING_STARTED or HELP)
        local g, comp, char = TC:Selected()
        local enabled = false
        if not char then
            name:SetText(g and "Loading..." or "Choose a companion")
            sub:SetText("Select one of your characters on the left.")
            stage:SetText("")
            mood:SetText("")
            statusLine:SetText("")
            aiLine:SetText("")
            portrait:SetTexture(nil)
        else
            local st = TC:CharStatus(char)
            enabled = st.enabled
            name:SetText(char.name)
            name:SetTextColor(TC:ClassColor(char.class))
            sub:SetText(("Level %d %s %s"):format(char.level or 0, char.raceName or "", char.className or ""))
            W.SetCompanionPortrait(portrait, char.name, char.class)
            local r = TC.state.relationship[g]
            if r then
                stage:SetText(r.stageLabel or "")
                mood:SetText("Mood: " .. ((r.mood or "relaxed"):gsub("_", " ")))
            else
                stage:SetText("")
                mood:SetText("")
            end
            statusLine:SetText(("Status: |cff%02x%02x%02x%s|r  %s"):format(st.color[1] * 255, st.color[2] * 255, st.color[3] * 255,
                st.label, char.reason or ""))
            local aiOn = not comp or not comp.settings or comp.settings.aiEnabled ~= false
            local online = TC:OllamaOnline()
            local present = char.status == "in_party" or char.status == "summoned"
            local aiText = not aiOn and "|cffaaaaaaoff - commands only|r" or (char.active and "|cff60ff60active|r")
                or (present and "|cffffd100not active yet|r") or "|cff60ff60on (starts when called)|r"
            local feat = TC.state.hello and TC.state.hello.features or {}
            local ollama = feat.ollama == false and "|cffaaaaaaoff on this server|r - commands work, no conversation"
                or online and "|cff60ff60online|r"
                or "|cffff6060offline|r - commands work, no conversation"
            aiLine:SetText(("AI conversation: %s   Ollama: %s"):format(aiText, ollama))
            if aiOn and present and not char.active then
                aiToggle:SetText("Activate AI")
            else
                aiToggle:SetText(aiOn and "Disable AI" or "Enable AI")
            end
        end
        local status = char and char.status
        if enabled and status == "available" then call:Enable() else call:Disable() end
        if char and (status == "in_party" or status == "summoned") then dismiss:Enable() else dismiss:Disable() end
        if char and enabled then aiToggle:Enable() configure:Enable() rel:Enable() talk:Enable()
        else aiToggle:Disable() configure:Disable() rel:Disable() talk:Disable() end
        if char and status == "available" and not TC.state.hello then call:Disable() end
    end

    TC:On("CHARS_CHANGED", function() f:RefreshList() f:RefreshCard() end)
    TC:On("SELECTION_CHANGED", function() f:RefreshList() f:RefreshCard() end)
    TC:On("COMPANION_CHANGED", function() f:RefreshCard() end)
    TC:On("RELATIONSHIP_CHANGED", function() f:RefreshCard() end)
    TC:On("STATUS_CHANGED", function() f:RefreshCard() end)

    f.OnShowTab = function()
        f:RefreshList()
        f:RefreshCard()
    end
end

UI:RegisterTab("companion", "Companion", build)
