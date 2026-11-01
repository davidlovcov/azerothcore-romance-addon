--[[
  AzerothRomance - Personality tab: identity, traits, response style, presets.
  The server sanitizes everything again (adult age, lengths, known styles).
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local TRAITS = {
    { key = "outgoing", label = "Shy  /  Outgoing", low = "shy", high = "outgoing" },
    { key = "sarcasm", label = "Kind  /  Sarcastic", low = "kind", high = "sarcastic" },
    { key = "playfulness", label = "Serious  /  Playful", low = "serious", high = "playful" },
    { key = "energy", label = "Calm  /  Energetic", low = "calm", high = "energetic" },
    { key = "confidence", label = "Nervous  /  Confident", low = "nervous", high = "confident" },
    { key = "romanticism", label = "Reserved  /  Romantic", low = "reserved", high = "romantic" },
    { key = "jealousy", label = "Jealousy", low = "none", high = "strong" },
    { key = "humor", label = "Humor", low = "little", high = "a lot" },
    { key = "expressiveness", label = "Emotional expressiveness", low = "low", high = "high" },
    { key = "affectionLevel", label = "Affection", low = "low", high = "high" },
    { key = "initiative", label = "Initiative in conversation", low = "low", high = "high" },
    { key = "loyalty", label = "Loyalty & trust", low = "low", high = "high" },
}

local STYLES = {
    { id = "anime", label = "Cute anime-style" },
    { id = "sweet", label = "Sweet & affectionate" },
    { id = "mature", label = "Mature & composed" },
    { id = "teasing", label = "Playful teasing" },
    { id = "tsundere", label = "Tsundere" },
    { id = "dandere", label = "Dandere" },
    { id = "fantasy_roleplay", label = "Fantasy roleplay" },
    { id = "casual", label = "Casual" },
    { id = "poetic", label = "Poetic" },
}

local TEXT_FIELDS = {
    { key = "background", label = "Background story" },
    { key = "history", label = "Personal history" },
    { key = "interests", label = "Interests & hobbies" },
    { key = "likes", label = "Likes" },
    { key = "dislikes", label = "Dislikes" },
    { key = "goals", label = "Goals" },
    { key = "fears", label = "Fears, flaws & insecurities" },
    { key = "relationshipPreferences", label = "Relationship preferences" },
    { key = "lore", label = "In-universe lore preferences" },
}

local function build(f)
    local scroll = CreateFrame("ScrollFrame", "AzerothRomancePersonalityScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 40)
    local c = CreateFrame("Frame", nil, scroll)
    c:SetWidth(730)
    c:SetHeight(1240)
    scroll:SetScrollChild(c)

    local fields = {}
    local y = -4

    -- ---------------------------------------------------------------- presets
    local h = W.Heading(c, "Preset")
    h:SetPoint("TOPLEFT", 4, y)
    local presetDesc = W.Label(c, "", 11, W.MUTED)
    local preset = W.Dropdown(c, "Preset (keeps your name and story fields)", 300, {}, function(id)
        for _, p in ipairs((AR.state.hello and AR.state.hello.presets) or {}) do
            if p.id == id then presetDesc:SetText(p.description or "") end
        end
    end)
    preset:SetPoint("TOPLEFT", 0, y - 18)
    local applyPreset = W.Button(c, "Apply preset", 110, 22, function()
        local g = AR.state.selected
        local id = preset:GetValue()
        if not g or not id then return end
        AR:Request("apply_preset", { guid = g, preset = id })
    end)
    applyPreset:SetPoint("TOPLEFT", 310, y - 32)
    presetDesc:SetPoint("TOPLEFT", 430, y - 34)
    presetDesc:SetWidth(290)
    y = y - 76

    -- ---------------------------------------------------------------- identity
    h = W.Heading(c, "Identity")
    h:SetPoint("TOPLEFT", 4, y)
    y = y - 18
    local idFields = {
        { key = "name", label = "Name", w = 170, max = 32 },
        { key = "nickname", label = "Nickname", w = 170, max = 32 },
        { key = "addressPlayerAs", label = "Calls you...", w = 170, max = 32 },
        { key = "age", label = "Age (18+)", w = 80, max = 4 },
        { key = "gender", label = "Gender", w = 120, max = 32 },
        { key = "pronouns", label = "Pronouns", w = 120, max = 32 },
    }
    local x = 0
    for i, fd in ipairs(idFields) do
        local e = W.Edit(c, fd.label, fd.w, fd.max)
        if i == 4 then
            x = 0
            y = y - 42
        end
        e:SetPoint("TOPLEFT", x, y)
        x = x + fd.w + 14
        fields[fd.key] = e
    end
    fields.age.edit:SetNumeric(true)
    y = y - 50

    -- ---------------------------------------------------------------- story fields
    h = W.Heading(c, "Story & taste")
    h:SetPoint("TOPLEFT", 4, y)
    y = y - 18
    for i, fd in ipairs(TEXT_FIELDS) do
        local col = (i - 1) % 2
        local area = W.TextArea(c, fd.label, 350, 54, 600)
        area:SetPoint("TOPLEFT", col * 364, y)
        fields[fd.key] = area
        if col == 1 or i == #TEXT_FIELDS then y = y - 78 end
    end

    -- ---------------------------------------------------------------- traits
    h = W.Heading(c, "Personality")
    h:SetPoint("TOPLEFT", 4, y)
    y = y - 30
    local sliders = {}
    for i, t in ipairs(TRAITS) do
        local col = (i - 1) % 3
        local s = W.Slider(c, t.label, 210, 0, 100, 5, t.low, t.high)
        s:SetPoint("TOPLEFT", 10 + col * 240, y)
        sliders[t.key] = s
        if col == 2 then y = y - 52 end
    end
    y = y - 8

    -- ---------------------------------------------------------------- response style
    h = W.Heading(c, "Response style")
    h:SetPoint("TOPLEFT", 4, y)
    y = y - 18
    local length = W.Dropdown(c, "Message length", 200, {
        { value = "short", text = "Short" }, { value = "medium", text = "Medium" },
        { value = "long", text = "Detailed" }, { value = "varied", text = "Natural (mostly short)" } })
    length:SetPoint("TOPLEFT", 0, y)
    local language = W.Dropdown(c, "Language", 200, {
        { value = "auto", text = "Match my language" }, { value = "en", text = "English" }, { value = "de", text = "Deutsch" } })
    language:SetPoint("TOPLEFT", 220, y)
    local formal = W.Check(c, "Formal language", "Polite and somewhat formal wording.")
    formal:SetPoint("TOPLEFT", 450, y - 14)
    y = y - 50
    local styleChecks = {}
    for i, st in ipairs(STYLES) do
        local col = (i - 1) % 3
        local cb = W.Check(c, st.label)
        cb:SetPoint("TOPLEFT", 4 + col * 240, y)
        styleChecks[st.id] = cb
        if col == 2 then y = y - 24 end
    end
    y = y - 10
    local romance = W.Check(c, "Romance possible", "Untick for a purely platonic companion (never progresses beyond close friends).")
    romance:SetPoint("TOPLEFT", 4, y)
    local autoAccept = W.Check(c, "Always says yes to proposals", "Skip the relationship requirements for proposals. Off = she decides based on your relationship.")
    autoAccept:SetPoint("TOPLEFT", 244, y)
    y = y - 34

    local custom = W.TextArea(c, "Custom instructions (e.g. \"She is initially shy and distant, but gradually becomes affectionate.\")", 714, 90, 1200)
    custom:SetPoint("TOPLEFT", 0, y)
    fields.customInstructions = custom
    y = y - 120
    c:SetHeight(-y + 20)

    -- ---------------------------------------------------------------- buttons
    local status = W.Label(f, "", 11, W.MUTED)
    status:SetPoint("BOTTOMLEFT", 4, 12)
    local save = W.Button(f, "Save personality", 140, 24)
    save:SetPoint("BOTTOMRIGHT", -4, 6)
    local revert = W.Button(f, "Revert", 80, 24)
    revert:SetPoint("RIGHT", save, "LEFT", -8, 0)

    local current = {}

    function f:Load()
        local g, comp = AR:Selected()
        local p = (comp and comp.personality) or {}
        current = p
        local presets = {}
        for _, pr in ipairs((AR.state.hello and AR.state.hello.presets) or {}) do
            presets[#presets + 1] = { value = pr.id, text = pr.label }
        end
        preset:SetItems(presets)
        preset:SetValue(p.preset ~= "" and p.preset or nil)
        for key, e in pairs(fields) do
            local v = p[key]
            if key == "age" then v = tostring(p.age or 21) end
            e:SetValue(v or "")
        end
        local traits = p.traits or {}
        for key, s in pairs(sliders) do s:SetValue(tonumber(traits[key]) or 50) end
        length:SetValue(p.length or "varied")
        language:SetValue(p.language or "auto")
        formal:SetChecked(p.formal and true or false)
        local set = {}
        for _, sname in ipairs(p.styles or {}) do set[sname] = true end
        for id, cb in pairs(styleChecks) do cb:SetChecked(set[id] and true or false) end
        romance:SetChecked(p.romanceEnabled ~= false)
        autoAccept:SetChecked(p.autoAcceptProposals and true or false)
        status:SetText(g and "" or "Select a companion on the Companion tab first.")
        if g then save:Enable() else save:Disable() end
    end

    function f:Collect()
        local p = {}
        for key, e in pairs(fields) do p[key] = e:GetValue() end
        p.age = tonumber(p.age) or 21
        p.traits = {}
        for key, s in pairs(sliders) do p.traits[key] = s:GetValueInt() end
        p.length = length:GetValue() or "varied"
        p.language = language:GetValue() or "auto"
        p.formal = formal:GetChecked() and true or false
        p.styles = AR.Json.Array({})
        for _, st in ipairs(STYLES) do
            if styleChecks[st.id]:GetChecked() then table.insert(p.styles, st.id) end
        end
        p.romanceEnabled = romance:GetChecked() and true or false
        p.autoAcceptProposals = autoAccept:GetChecked() and true or false
        p.preset = preset:GetValue() or current.preset or ""
        p.stageLabels = current.stageLabels or AR.Json.Array({})
        return p
    end

    save:SetScript("OnClick", function()
        local g = AR.state.selected
        if not g then return end
        local p = f:Collect()
        if p.age < 18 then
            status:SetText("|cffff6060Companions must be adults (18+).|r")
            return
        end
        status:SetText("Saving...")
        AR:Request("save_personality", { guid = g, personality = p }, function(msg)
            if msg.op == "ack" then
                local notes = msg.notes and #msg.notes > 0 and (" (" .. table.concat(msg.notes, ", ") .. ")") or ""
                status:SetText(msg.ok and ("|cff60ff60Saved.|r" .. notes) or ("|cffff6060" .. AR:AckText(msg) .. "|r"))
            end
        end)
    end)
    revert:SetScript("OnClick", function() f:Load() end)

    AR:On("COMPANION_CHANGED", function(g) if g == AR.state.selected and f:IsShown() then f:Load() end end)
    AR:On("SELECTION_CHANGED", function() if f:IsShown() then f:Load() end end)
    f.OnShowTab = function() f:Load() end
end

UI:RegisterTab("personality", "Personality", build)
