--[[
  AzerothRomance - Settings tab: per-companion preferences (within server limits) and addon options.
  Server-wide settings (Ollama URL, limits) are administrator-only and not editable here.
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local function build(f)
    local left = W.Panel(f, 440, 440)
    left:SetPoint("TOPLEFT", 0, 0)
    local h = W.Heading(left, "Companion behavior")
    h:SetPoint("TOPLEFT", 12, -10)
    local who = W.Label(left, "", 11, W.MUTED)
    who:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)

    local ai = W.Check(left, "AI conversation enabled", "Off = a regular Playerbot (no Ollama requests at all).")
    ai:SetPoint("TOPLEFT", 10, -48)
    local proactive = W.Check(left, "Starts conversations unprompted", "Spontaneous remarks while you travel. Never during combat.")
    proactive:SetPoint("TOPLEFT", 10, -74)
    local freq = W.Slider(left, "How often to speak up", 200, 0, 100, 5, "rarely", "often")
    freq:SetPoint("TOPLEFT", 40, -112)
    local commands = W.Check(left, "Understand spoken commands", "\"Elara, follow me\" -> follow. Only follow, stay, attack and flee.")
    commands:SetPoint("TOPLEFT", 10, -146)
    local party = W.Check(left, "Answer in party chat", "Reply in party chat instead of whispering you.")
    party:SetPoint("TOPLEFT", 10, -172)
    local listen = W.Check(left, "Listen in party chat when addressed by name")
    listen:SetPoint("TOPLEFT", 10, -198)
    local waitLoot = W.Check(left, "Wait for me to loot",
        "After a fight she also waits until you have looted (your round-robin turn, your quest items). Off: she loots her own and goes on.")
    waitLoot:SetPoint("TOPLEFT", 10, -224)

    local model = W.Dropdown(left, "Model (server default if empty)", 260, {})
    model:SetPoint("TOPLEFT", 4, -254)
    local temp = W.Slider(left, "Creativity (temperature x100, 0 = server default)", 220, 0, 120, 5, "default", "wild")
    temp:SetPoint("TOPLEFT", 40, -316)
    local maxChars = W.Slider(left, "Maximum reply length (characters, 0 = default)", 220, 0, 600, 25, "default", "600")
    maxChars:SetPoint("TOPLEFT", 40, -364)

    local status = W.Label(left, "", 11, W.MUTED)
    status:SetPoint("BOTTOMLEFT", 12, 14)
    local save = W.Button(left, "Save settings", 130, 24)
    save:SetPoint("BOTTOMRIGHT", -10, 8)

    -- addon options
    local right = W.Panel(f, 300, 226)
    right:SetPoint("TOPRIGHT", 0, 0)
    local h2 = W.Heading(right, "Addon")
    h2:SetPoint("TOPLEFT", 12, -10)
    local ts = W.Check(right, "Show timestamps in chat")
    ts:SetPoint("TOPLEFT", 10, -34)
    ts:SetScript("OnClick", function(self)
        AR.db.timestamps = self:GetChecked() and true or false
        AR:Fire("CHAT_CHANGED", AR.state.selected)
    end)
    local mm = W.Check(right, "Show minimap button")
    mm:SetPoint("TOPLEFT", 10, -60)
    mm:SetScript("OnClick", function(self)
        AR.db.minimap.hide = not self:GetChecked()
        AR:Fire("MINIMAP_TOGGLE")
    end)
    local quiet = W.Check(right, "Hide Playerbots feedback", "Lines like \"Following\" or \"attack rti target: useless\" from your companions only show in the Chat tab (gray), not in the chat window.")
    quiet:SetPoint("TOPLEFT", 10, -86)
    quiet:SetScript("OnClick", function(self)
        AR.db.hideBotFeedback = self:GetChecked() and true or false
    end)
    local clearLocal = W.Button(right, "Clear local chat log", 150, 22, function()
        if AR.state.selected then
            local log = AR:ChatLog(AR.state.selected)
            for i = #log, 1, -1 do log[i] = nil end
            AR:Fire("CHAT_CHANGED", AR.state.selected)
        end
    end)
    clearLocal:SetPoint("TOPLEFT", 14, -120)
    local slashHelp = W.Label(right, "/romance  - open or close\n/romance status  - server status\n/romance minimap  - toggle button\n/romance reset window", 10, W.MUTED)
    slashHelp:SetPoint("TOPLEFT", 14, -152)

    local info = W.Panel(f, 300, 210)
    info:SetPoint("BOTTOMRIGHT", 0, 0)
    local h3 = W.Heading(info, "Server")
    h3:SetPoint("TOPLEFT", 12, -10)
    local serverText = W.Label(info, "", 11, W.TEXT)
    serverText:SetPoint("TOPLEFT", 12, -32)
    serverText:SetWidth(276)

    function f:Load()
        local g, comp, char = AR:Selected()
        local s = (comp and comp.settings) or {}
        who:SetText(char and ("for " .. char.name) or "Select a companion first.")
        ai:SetChecked(s.aiEnabled ~= false)
        proactive:SetChecked(s.proactiveEnabled ~= false)
        freq:SetValue(tonumber(s.proactiveFrequency) or 50)
        commands:SetChecked(s.naturalCommands ~= false)
        party:SetChecked(s.partyChatMode and true or false)
        listen:SetChecked(s.listenInParty ~= false)
        waitLoot:SetChecked(s.waitForPlayerLoot and true or false)
        local items = { { value = "", text = "Server default" } }
        local m = AR.state.models
        if m and m.choice then
            for _, name in ipairs(m.models or {}) do items[#items + 1] = { value = name, text = name } end
        end
        model:SetItems(items)
        model:SetValue(s.model or "")
        local t = tonumber(s.temperature) or -1
        temp:SetValue(t >= 0 and math.floor(t * 100 + 0.5) or 0)
        maxChars:SetValue(tonumber(s.maxReplyChars) or 0)
        ts:SetChecked(AR.db.timestamps)
        mm:SetChecked(not AR.db.minimap.hide)
        quiet:SetChecked(AR.db.hideBotFeedback ~= false)
        if g then save:Enable() else save:Disable() end

        local st = AR.state.status or {}
        local o = st.ollama or {}
        local feat = (AR.state.hello and AR.state.hello.features) or {}
        local srv = AR.state.hello and AR.state.hello.module
        local ver = ("Addon: v%s\nServer module: %s"):format(AR.version, srv and ("v" .. srv) or "|cffaaaaaaunknown (older module)|r")
        if srv and srv ~= AR.version then ver = ver .. " |cffff6060(differs from the addon)|r" end
        serverText:SetText(ver .. ("\nModule: %s\nOllama: %s %s\nDefault model: %s\nInstalled models: %d\nProactive chat: %s\nSpoken commands: %s\nPlayerbots: %s"):format(
            st.enabled == false and "|cffff6060disabled|r" or "|cff60ff60enabled|r",
            o.online and "|cff60ff60online|r" or "|cffff6060offline|r", o.version or "",
            tostring(st.model or "?"), #(o.models or {}),
            feat.proactive == false and "disabled by server" or "allowed",
            feat.naturalCommands == false and "disabled by server" or "allowed",
            feat.playerbots and "found" or "|cffff6060not found|r"))
        if feat.proactive == false then proactive:Disable() else proactive:Enable() end
        if feat.naturalCommands == false then commands:Disable() else commands:Enable() end
        if feat.modelChoice == false then UIDropDownMenu_DisableDropDown(model.dd) else UIDropDownMenu_EnableDropDown(model.dd) end
    end

    save:SetScript("OnClick", function()
        local g = AR.state.selected
        if not g then return end
        local t = temp:GetValueInt()
        local s = {
            aiEnabled = ai:GetChecked() and true or false,
            proactiveEnabled = proactive:GetChecked() and true or false,
            proactiveFrequency = freq:GetValueInt(),
            naturalCommands = commands:GetChecked() and true or false,
            partyChatMode = party:GetChecked() and true or false,
            listenInParty = listen:GetChecked() and true or false,
            waitForPlayerLoot = waitLoot:GetChecked() and true or false,
            model = model:GetValue() or "",
            temperature = t > 0 and (t / 100) or -1,
            maxReplyChars = maxChars:GetValueInt(),
        }
        status:SetText("Saving...")
        AR:Request("save_settings", { guid = g, settings = s }, function(msg)
            if msg.op == "ack" then
                status:SetText(msg.ok and "|cff60ff60Saved.|r" or ("|cffff6060" .. AR:AckText(msg) .. "|r"))
            end
        end)
    end)

    AR:On("COMPANION_CHANGED", function() if f:IsShown() then f:Load() end end)
    AR:On("MODELS_CHANGED", function() if f:IsShown() then f:Load() end end)
    AR:On("STATUS_CHANGED", function() if f:IsShown() then f:Load() end end)
    AR:On("SELECTION_CHANGED", function() if f:IsShown() then f:Load() end end)
    f.OnShowTab = function()
        AR:Request("list_models")
        AR:Request("get_status")
        f:Load()
    end
end

UI:RegisterTab("settings", "Settings", build, { group = "companion" })
