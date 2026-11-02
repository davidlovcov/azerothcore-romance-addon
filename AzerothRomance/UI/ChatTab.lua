--[[
  AzerothRomance - Chat tab: conversation history and input.
  The companion also answers in normal whispers; this panel mirrors the conversation.
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local function build(f)
    local panel = W.Panel(f, nil, nil, 0.75)
    panel:SetPoint("TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", 0, 64)

    local header = W.Heading(panel, "")
    header:SetPoint("TOPLEFT", 12, -10)

    local log = CreateFrame("ScrollingMessageFrame", nil, panel)
    log:SetPoint("TOPLEFT", 12, -32)
    log:SetPoint("BOTTOMRIGHT", -12, 26)
    log:SetFontObject(ChatFontNormal)
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(250)
    log:SetSpacing(3)
    if log.SetIndentedWordWrap then log:SetIndentedWordWrap(true) end
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() self:ScrollUp() end
        else
            if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() self:ScrollDown() end
        end
    end)
    if log.SetHyperlinksEnabled then log:SetHyperlinksEnabled(false) end

    local typing = W.Label(panel, "", 11, W.ROSE)
    typing:SetPoint("BOTTOMLEFT", 14, 8)

    -- input
    local input = W.StyleInput(CreateFrame("EditBox", "AzerothRomanceChatInput", f))
    input:SetHeight(26)
    input:SetPoint("BOTTOMLEFT", 0, 30)
    input:SetPoint("BOTTOMRIGHT", -100, 30)
    input:SetMaxLetters(450)
    local send = W.Button(f, "Send", 86, 24)
    send:SetPoint("LEFT", input, "RIGHT", 8, 0)
    local hint = W.Label(f, "Roleplay is sent to your companion. Start a line with ! to give a plain Playerbots command (e.g. !follow).", 10, W.MUTED)
    hint:SetPoint("BOTTOMLEFT", 8, 8)

    local function playerName()
        local p = AR.state.profile
        return (p and p.preferredName and p.preferredName ~= "" and p.preferredName) or UnitName("player")
    end

    local function lineFor(entry, compName)
        local ts = ""
        if AR.db.timestamps and entry.ts then
            ts = "|cff777777" .. date("%H:%M", entry.ts) .. "|r "
        end
        local text = (entry.text or ""):gsub("|", "||")
        if entry.from == "player" then
            return ts .. "|cffffd76b" .. playerName() .. ":|r |cffe8e0d0" .. text .. "|r"
        elseif entry.from == "command" then
            return ts .. "|cff8899aa[command] " .. text .. "|r"
        elseif entry.from == "system" then
            return ts .. "|cff808080[Playerbots] " .. text .. "|r"
        else
            return ts .. "|cffff9ccf" .. (compName or "Companion") .. ":|r |cfffff0f6" .. text .. "|r"
        end
    end

    function f:Render()
        local g, comp, char = AR:Selected()
        log:Clear()
        if not g then
            header:SetText("No companion selected")
            log:AddMessage("|cff999999Select a companion on the Companion tab first.|r")
            return
        end
        local cname = char and char.name or (comp and comp.name) or "Companion"
        header:SetText("Conversation with " .. cname)
        local entries = AR:ChatLog(g)
        local start = math.max(1, #entries - 150)
        for i = start, #entries do
            log:AddMessage(lineFor(entries[i], cname))
        end
        log:ScrollToBottom()
        f:RenderTyping()
    end

    local dots = 0
    local acc = 0
    function f:RenderTyping()
        local g, _, char = AR:Selected()
        if g and AR.state.typing[g] then
            typing:SetText((char and char.name or "Companion") .. " is thinking" .. string.rep(".", dots + 1))
        else
            typing:SetText("")
        end
    end
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc > 0.4 then
            acc = 0
            dots = (dots + 1) % 3
            f:RenderTyping()
        end
    end)

    local function doSend()
        local text = (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local g = AR.state.selected
        if text == "" or not g then return end
        input:SetText("")
        if text:sub(1, 1) == "!" then
            AR:AddChatLine(g, "command", text:sub(2), time())
        end
        AR.state.typing[g] = text:sub(1, 1) ~= "!" or nil
        f:RenderTyping()
        AR:Request("chat", { guid = g, text = text })
    end
    send:SetScript("OnClick", doSend)
    input:SetScript("OnEnterPressed", function(self) doSend() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    AR:On("CHAT_CHANGED", function(g) if g == AR.state.selected and f:IsShown() then f:Render() end end)
    AR:On("TYPING_CHANGED", function() f:RenderTyping() end)
    AR:On("SELECTION_CHANGED", function() if f:IsShown() then f:Render() end end)
    AR:On("PROFILE_CHANGED", function() if f:IsShown() then f:Render() end end)

    f.OnShowTab = function()
        if not AR.state.profile then AR:Request("get_profile") end
        f:Render()
        input:SetFocus()
    end
end

UI:RegisterTab("chat", "Chat", build)
