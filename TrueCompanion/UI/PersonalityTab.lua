--[[
  TrueCompanion - Personality tab: presets, identity, story, traits, response style.
  The server sanitizes everything again (adult age, lengths, known styles).

  Presets are complete personalities. Applying one replaces every field except
  name and nickname (language, stage labels and the proposal setting stay too).
  "Reset to preset" applies the companion's current preset again; "Undo changes"
  throws away unsaved edits.
]]

local TC = _G.TrueCompanion
local W = TC.W
local UI = TC.UI

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

local function presetById(id)
    for _, p in ipairs(TC:Presets()) do
        if p.id == id then return p end
    end
end

local function build(f)
    local scroll = CreateFrame("ScrollFrame", "TrueCompanionPersonalityScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 40)
    local c = CreateFrame("Frame", nil, scroll)
    c:SetWidth(730)
    c:SetHeight(1300)
    scroll:SetScrollChild(c)

    local fields = {}
    local current = {}
    local y = -4

    -- bottom row first: other widgets report into `status`
    local status = W.Label(f, "", 11, W.MUTED)
    status:SetPoint("BOTTOMLEFT", 4, 12)
    status:SetWidth(330)
    local save = W.Button(f, "Save personality", 140, 24)
    save:SetPoint("BOTTOMRIGHT", -4, 6)
    local revert = W.Button(f, "Undo changes", 110, 24)
    revert:SetPoint("RIGHT", save, "LEFT", -8, 0)
    W.Tooltip(revert, "Undo changes", "Discards unsaved edits and shows the saved personality again.")
    local resetPreset = W.Button(f, "Reset to preset", 120, 24)
    resetPreset:SetPoint("RIGHT", revert, "LEFT", -8, 0)
    W.Tooltip(resetPreset, "Reset to preset defaults",
        "Applies the companion's current preset again: every field goes back to the preset's values (name and nickname stay).")

    local function ackText(okText)
        return function(msg)
            if msg.op == "ack" or msg.op == "presets" then
                status:SetText(msg.ok and ("|cff60ff60" .. okText .. "|r") or ("|cffff6060" .. TC:AckText(msg) .. "|r"))
            end
        end
    end

    -- ---------------------------------------------------------------- presets
    local h = W.Heading(c, "Preset")
    h:SetPoint("TOPLEFT", 4, y)
    local presetDesc = W.Label(c, "", 11, W.MUTED)
    local preset, showAll, deletePreset
    preset = W.Dropdown(c, "Preset (replaces everything except name & nickname)", 300, {}, function(id)
        local p = presetById(id)
        presetDesc:SetText(p and (p.description or "") or "")
        if p and p.custom then deletePreset:Enable() else deletePreset:Disable() end
    end)
    preset:SetPoint("TOPLEFT", 0, y - 18)
    local applyPreset = W.Button(c, "Apply preset", 110, 22, function()
        local g = TC.state.selected
        local id = preset:GetValue()
        if not g or not id then return end
        status:SetText("Applying preset...")
        TC:Request("apply_preset", { guid = g, preset = id }, ackText("Preset applied."))
    end)
    applyPreset:SetPoint("TOPLEFT", 310, y - 32)
    showAll = W.Check(c, "All genders", "Also list presets written for the other gender.")
    showAll:SetPoint("TOPLEFT", 430, y - 30)
    presetDesc:SetPoint("TOPLEFT", 4, y - 62)
    presetDesc:SetWidth(714)
    y = y - 84

    local presetName = W.Edit(c, "Save this personality as your own preset", 300, 40)
    presetName:SetPoint("TOPLEFT", 0, y)
    local savePreset = W.Button(c, "Save as preset", 120, 22)
    savePreset:SetPoint("TOPLEFT", 310, y - 14)
    deletePreset = W.Button(c, "Delete preset", 110, 22)
    deletePreset:SetPoint("TOPLEFT", 438, y - 14)
    deletePreset:Disable()
    y = y - 56

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
    local randomStory = W.Button(c, "Randomize", 90, 18)
    randomStory:SetPoint("TOPLEFT", 140, y + 2)
    W.Tooltip(randomStory, "Randomize story & taste", "Fills the fields below with a random story. Nothing is saved until you press Save.")
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
    local romance = W.Check(c, "Romantic relationship possible", "Untick for a purely platonic companion (never progresses beyond close friends).")
    romance:SetPoint("TOPLEFT", 4, y)
    local autoAccept = W.Check(c, "Always says yes to proposals", "Skip the relationship requirements for proposals. Off = the companion decides based on your relationship.")
    autoAccept:SetPoint("TOPLEFT", 244, y)
    y = y - 34

    local custom = W.TextArea(c, "Custom instructions (e.g. \"Initially shy and distant, but gradually becomes affectionate.\")", 714, 90, 1200)
    custom:SetPoint("TOPLEFT", 0, y)
    fields.customInstructions = custom
    y = y - 120
    c:SetHeight(-y + 20)

    -- ---------------------------------------------------------------- logic

    -- Gender of the selected companion: the personality's own setting, else the character's model.
    local function companionGender()
        local _, comp, char = TC:Selected()
        local pg = (comp and comp.personality and comp.personality.gender or ""):lower()
        if pg == "female" or pg == "male" then return pg end
        if char and char.gender ~= nil then return tonumber(char.gender) == 1 and "female" or "male" end
    end

    function f:FillPresets()
        local gender = companionGender()
        local items = {}
        for _, pr in ipairs(TC:Presets()) do
            local fits = showAll:GetChecked() or pr.custom or not gender or (pr.gender or "") == "" or pr.gender == gender
            if fits or pr.id == current.preset then
                items[#items + 1] = { value = pr.id, text = (pr.custom and "|cffffd100*|r " or "") .. pr.label }
            end
        end
        preset:SetItems(items)
        local sel = preset:GetValue()
        if sel and not presetById(sel) then sel = nil end
        preset:SetValue(sel)
        local p = sel and presetById(sel)
        presetDesc:SetText(p and (p.description or "") or "")
        if p and p.custom then deletePreset:Enable() else deletePreset:Disable() end
        if TC.state.selected and current.preset and current.preset ~= "" and presetById(current.preset) then
            resetPreset:Enable()
        else
            resetPreset:Disable()
        end
    end
    showAll:HookScript("OnClick", function() f:FillPresets() end)

    function f:Load()
        local g, comp = TC:Selected()
        local p = (comp and comp.personality) or {}
        current = p
        preset:SetValue(p.preset ~= "" and p.preset or nil)
        f:FillPresets()
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
        p.styles = TC.Json.Array({})
        for _, st in ipairs(STYLES) do
            if styleChecks[st.id]:GetChecked() then table.insert(p.styles, st.id) end
        end
        p.romanceEnabled = romance:GetChecked() and true or false
        p.autoAcceptProposals = autoAccept:GetChecked() and true or false
        -- the preset a personality came from; the dropdown is only a picker for "Apply"
        p.preset = current.preset or ""
        p.stageLabels = current.stageLabels or TC.Json.Array({})
        return p
    end

    save:SetScript("OnClick", function()
        local g = TC.state.selected
        if not g then return end
        local p = f:Collect()
        if p.age < 18 then
            status:SetText("|cffff6060Companions must be adults (18+).|r")
            return
        end
        status:SetText("Saving...")
        TC:Request("save_personality", { guid = g, personality = p }, function(msg)
            if msg.op == "ack" then
                local notes = msg.notes and #msg.notes > 0 and (" (" .. table.concat(msg.notes, ", ") .. ")") or ""
                status:SetText(msg.ok and ("|cff60ff60Saved.|r" .. notes) or ("|cffff6060" .. TC:AckText(msg) .. "|r"))
            end
        end)
    end)

    revert:SetScript("OnClick", function()
        f:Load()
        status:SetText("Unsaved changes discarded.")
    end)

    resetPreset:SetScript("OnClick", function()
        local g = TC.state.selected
        if not g or not current.preset or current.preset == "" then return end
        status:SetText("Resetting to preset...")
        TC:Request("apply_preset", { guid = g, preset = current.preset }, ackText("Back to the preset's defaults."))
    end)

    randomStory:SetScript("OnClick", function()
        for key, v in pairs(TC.Random.CompanionStory(companionGender())) do
            if fields[key] then fields[key]:SetValue(v) end
        end
        status:SetText("Random story filled in - press Save to keep it.")
    end)

    savePreset:SetScript("OnClick", function()
        local label = presetName:GetValue() or ""
        if label:gsub("%s", "") == "" then
            status:SetText("|cffff6060Give the preset a name first.|r")
            return
        end
        local sel = preset:GetValue()
        local existing = sel and presetById(sel)
        -- saving under the name of the selected custom preset overwrites it
        local replace = (existing and existing.custom and existing.label == label) and existing.id or nil
        local who = (current.name and current.name ~= "") and current.name or "a companion"
        TC:Request("save_preset", { label = label, description = "Saved from " .. who .. ".", personality = f:Collect(), replace = replace },
            function(msg)
                if msg.op ~= "presets" then return end
                status:SetText(msg.ok and ("|cff60ff60Preset \"" .. label .. "\" saved.|r") or ("|cffff6060" .. TC:AckText(msg) .. "|r"))
                if msg.ok and msg.savedId and msg.savedId ~= "" then preset:SetValue(msg.savedId) end
                f:FillPresets()
            end)
    end)

    deletePreset:SetScript("OnClick", function()
        local sel = preset:GetValue()
        local p = sel and presetById(sel)
        if not p or not p.custom then return end
        TC:Request("delete_preset", { preset = sel }, function(msg)
            if msg.op ~= "presets" then return end
            status:SetText(msg.ok and ("Preset \"" .. p.label .. "\" deleted.") or ("|cffff6060" .. TC:AckText(msg) .. "|r"))
            preset:SetValue(nil)
            f:FillPresets()
        end)
    end)

    TC:On("PRESETS_CHANGED", function() if f:IsShown() then f:FillPresets() end end)
    TC:On("COMPANION_CHANGED", function(g) if g == TC.state.selected and f:IsShown() then f:Load() end end)
    TC:On("SELECTION_CHANGED", function() if f:IsShown() then f:Load() end end)
    f.OnShowTab = function() f:Load() end
end

UI:RegisterTab("personality", "Personality", build, { group = "companion" })
