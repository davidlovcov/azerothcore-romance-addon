--[[
  AzerothRomance - Relationship tab: stage, values, mood, milestones, starting relationship.
  All values are server-authoritative; this tab only displays them.
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local VALUES = {
    { key = "friendship", label = "Friendship", color = { 0.45, 0.8, 1.0 } },
    { key = "affection", label = "Affection", color = { 1.0, 0.55, 0.75 } },
    { key = "attraction", label = "Romantic attraction", color = { 1.0, 0.35, 0.5 } },
    { key = "trust", label = "Trust", color = { 0.5, 0.9, 0.55 } },
    { key = "familiarity", label = "Familiarity", color = { 0.85, 0.75, 0.45 } },
    { key = "comfort", label = "Comfort", color = { 0.7, 0.65, 1.0 } },
    { key = "satisfaction", label = "Relationship satisfaction", color = { 1.0, 0.8, 0.35 } },
}

StaticPopupDialogs["AZEROTHROMANCE_SET_STAGE"] = {
    text = "Set the starting relationship to |cffffd100%s|r?\nThis replaces the current relationship values. Memories are kept.",
    button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data) data() end,
}

local function build(f)
    -- ---------------------------------------------------------------- left: stage & values
    local left = W.Panel(f, 390, 440)
    left:SetPoint("TOPLEFT", 0, 0)
    local stage = W.Label(left, "", 18, W.ROSE, "GameFontNormalLarge")
    stage:SetPoint("TOPLEFT", 14, -12)
    local mood = W.Label(left, "", 11, W.TEXT)
    mood:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -6)
    local strained = W.Label(left, "", 11, { 1, 0.5, 0.4 })
    strained:SetPoint("TOPLEFT", mood, "BOTTOMLEFT", 0, -4)
    strained:SetWidth(362)
    strained:SetJustifyH("LEFT")

    -- stage track
    local pips = {}
    for i = 1, 8 do
        local p = left:CreateTexture(nil, "ARTWORK")
        p:SetWidth(36)
        p:SetHeight(6)
        p:SetPoint("TOPLEFT", 14 + (i - 1) * 45, -78)
        p:SetTexture("Interface\\Buttons\\WHITE8X8")
        pips[i] = p
    end
    local stageNames = W.Label(left, "", 9, W.MUTED)
    stageNames:SetPoint("TOPLEFT", 14, -88)
    stageNames:SetWidth(360)

    local bars = {}
    for i, v in ipairs(VALUES) do
        local b = W.Bar(left, v.label, 360, v.color)
        b:SetPoint("TOPLEFT", 14, -112 - (i - 1) * 36)
        bars[v.key] = b
    end
    local note = W.Label(left, "Values change through your conversations, kindness, gifts and shared adventures - " ..
        "gradually, and capped per day.", 10, W.MUTED)
    note:SetPoint("BOTTOMLEFT", 14, 12)
    note:SetWidth(360)

    -- ---------------------------------------------------------------- right: milestones & actions
    local right = W.Panel(f, 350, 250)
    right:SetPoint("TOPRIGHT", 0, 0)
    local mh = W.Heading(right, "Significant moments")
    mh:SetPoint("TOPLEFT", 12, -10)
    local memButton = W.Button(right, "Memories...", 100, 20, function() AR.MemoryViewer:Open() end)
    memButton:SetPoint("TOPRIGHT", -10, -6)
    local moments = {}
    for i = 1, 6 do
        local l = W.Label(right, "", 11, W.TEXT)
        l:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 34)
        l:SetWidth(320)
        moments[i] = l
    end

    local actions = W.Panel(f, 350, 182)
    actions:SetPoint("BOTTOMRIGHT", 0, 0)
    local ah = W.Heading(actions, "Starting relationship")
    ah:SetPoint("TOPLEFT", 12, -10)
    local stageDD = W.Dropdown(actions, "Stage", 190, {})
    stageDD:SetPoint("TOPLEFT", 4, -28)
    local romantic = W.Check(actions, "Romantic", "Off = platonic friendship.")
    romantic:SetPoint("TOPLEFT", 210, -44)
    romantic:SetChecked(true)
    local backstory = W.Edit(actions, "Backstory (optional)", 330, 300)
    backstory:SetPoint("TOPLEFT", 8, -74)
    local setStage = W.Button(actions, "Set relationship", 130, 22)
    setStage:SetPoint("TOPLEFT", 10, -118)
    local hint = W.Label(actions, "Proposals happen in chat, e.g. \"Would you like to be my girlfriend?\"", 10, W.MUTED)
    hint:SetPoint("TOPLEFT", 12, -148)
    hint:SetWidth(330)
    local ask = W.Button(actions, "Ask in chat", 100, 22, function()
        UI:ShowTab("chat")
        local r = AR.state.relationship[AR.state.selected or 0]
        local idx = r and r.stageIndex or 0
        local text = idx >= 6 and "Will you marry me?" or idx == 5 and "Will you marry me? Let's get engaged." or "Would you like to be my girlfriend?"
        if AzerothRomanceChatInput then
            AzerothRomanceChatInput:SetText(text)
            AzerothRomanceChatInput:SetFocus()
        end
    end)
    ask:SetPoint("LEFT", setStage, "RIGHT", 10, 0)

    setStage:SetScript("OnClick", function()
        local g = AR.state.selected
        local st = stageDD:GetValue()
        if not g or not st then return end
        local label = st
        for _, it in ipairs(stageDD.items) do if it.value == st then label = it.text end end
        local popup = StaticPopup_Show("AZEROTHROMANCE_SET_STAGE", label)
        if popup then
            popup.data = function()
                AR:Request("set_relationship", { guid = g, stage = st, romantic = romantic:GetChecked() and true or false,
                    backstory = backstory:GetValue() }, function(msg)
                    if msg.op == "ack" and not msg.ok then AR:Print("|cffff6060" .. AR:AckText(msg) .. "|r") end
                end)
            end
        end
    end)

    function f:Refresh()
        local g = AR.state.selected
        local r = g and AR.state.relationship[g]
        local hello = AR.state.hello
        local items = {}
        local maxStage = hello and hello.features and hello.features.maxInitialStage or 7
        for i, s in ipairs((hello and hello.stages) or {}) do
            if i - 1 <= maxStage then items[#items + 1] = { value = s.id, text = s.label } end
        end
        stageDD:SetItems(items)
        if hello and hello.features and hello.features.initialStage == false then setStage:Disable() else setStage:Enable() end
        if not r then
            stage:SetText(g and "Loading..." or "No companion selected")
            mood:SetText("")
            strained:SetText("")
            for _, b in pairs(bars) do b:Set(0) end
            for i = 1, 8 do pips[i]:SetVertexColor(0.25, 0.22, 0.25) end
            return
        end
        stage:SetText(r.stageLabel or "")
        mood:SetText(("Mood: %s"):format(((r.mood or "relaxed"):gsub("_", " "))))
        if r.estranged then
            strained:SetText(("Estranged: only apologies and kindness over several days win them back (%d/100)."):format(
                tonumber(r.reconciliation) or 0))
        elseif (tonumber(r.resentment) or 0) >= 50 then
            strained:SetText("Deeply hurt - one more insult and they may leave you.")
        else
            strained:SetText(r.strained and "Things feel tense between you right now." or "")
        end
        for key, b in pairs(bars) do b:Set(r.values and r.values[key] or 0) end
        UI.SetShown(bars.attraction, r.romantic ~= false)
        local idx = tonumber(r.stageIndex) or 0
        for i = 1, 8 do
            if i - 1 < idx then pips[i]:SetVertexColor(1, 0.55, 0.75)
            elseif i - 1 == idx then pips[i]:SetVertexColor(1, 0.82, 0.25)
            else pips[i]:SetVertexColor(0.25, 0.22, 0.25) end
        end
        local labels = r.labels or {}
        stageNames:SetText(("%s  >  %s"):format(labels[1] or "", labels[8] or ""))
        stageDD:SetValue(r.stage)
    end

    function f:LoadMoments()
        local g = AR.state.selected
        for i = 1, 6 do moments[i]:SetText("") end
        if not g then return end
        AR:Request("get_memories", { guid = g, kind = "relationship", limit = 4 }, function(msg)
            if msg.op ~= "memories" then return end
            local items = msg.items or {}
            AR:Request("get_memories", { guid = g, kind = "gift", limit = 2 }, function(m2)
                for _, it in ipairs(m2.items or {}) do table.insert(items, it) end
                for i = 1, 6 do
                    local it = items[i]
                    moments[i]:SetText(it and ("|cffffd100" .. date("%d.%m.", it.createdAt or 0) .. "|r " .. it.text) or "")
                end
            end)
        end)
    end

    AR:On("RELATIONSHIP_CHANGED", function() if f:IsShown() then f:Refresh() end end)
    AR:On("SELECTION_CHANGED", function() if f:IsShown() then f:Refresh() f:LoadMoments() end end)
    AR:On("MEMORY_CHANGED", function() if f:IsShown() then f:LoadMoments() end end)
    f.OnShowTab = function()
        f:Refresh()
        f:LoadMoments()
    end
end

UI:RegisterTab("relationship", "Relationship", build, { group = "companion" })
