--[[
  AzerothRomance - Debug tab (deliberately small): diagnostics, memory inspector, errors.
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local function build(f)
    local left = W.Panel(f, 370, 440)
    left:SetPoint("TOPLEFT", 0, 0)
    local h = W.Heading(left, "Diagnostics")
    h:SetPoint("TOPLEFT", 12, -10)
    local refresh = W.Button(left, "Refresh", 70, 20)
    refresh:SetPoint("TOPRIGHT", -10, -6)
    local text = W.Label(left, "", 11, W.TEXT)
    text:SetPoint("TOPLEFT", 12, -34)
    text:SetWidth(346)
    local mem = W.Button(left, "Advanced Memory...", 150, 22, function() AR.MemoryViewer:Open() end)
    mem:SetPoint("BOTTOMLEFT", 12, 10)
    local clearChat = W.Button(left, "Clear server chat history", 180, 22, function()
        local g = AR.state.selected
        if not g then return end
        local popup = StaticPopup_Show("AZEROTHROMANCE_CONFIRM", "Delete the stored conversation history (memories are kept)?")
        if popup then popup.data = function() AR:Request("clear_history", { guid = g }) end end
    end)
    clearChat:SetPoint("LEFT", mem, "RIGHT", 8, 0)

    local right = W.Panel(f, 370, 440)
    right:SetPoint("TOPRIGHT", 0, 0)
    local h2 = W.Heading(right, "Last model output / errors")
    h2:SetPoint("TOPLEFT", 12, -10)
    local log = CreateFrame("ScrollingMessageFrame", nil, right)
    log:SetPoint("TOPLEFT", 12, -32)
    log:SetPoint("BOTTOMRIGHT", -12, 12)
    log:SetFontObject(GameFontHighlightSmall)
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(200)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, d) if d > 0 then self:ScrollUp() else self:ScrollDown() end end)

    local function esc(s) return (tostring(s or "")):gsub("|", "||") end

    function f:Load()
        local g = AR.state.selected
        AR:Request(g and "get_debug" or "get_status", { guid = g }, function(msg)
            local o = msg.ollama or {}
            local q = msg.queue or {}
            local d = msg.debug or {}
            local lines = {
                ("Ollama: %s  %s  (%d ms)"):format(o.online and "|cff60ff60online|r" or "|cffff6060offline|r", esc(o.version), tonumber(o.latencyMs) or 0),
                ("Model: %s   installed: %d"):format(esc(msg.model), #(o.models or {})),
                ("Queue: %d queued, %d running, capacity %d"):format(tonumber(q.queued) or 0, tonumber(q.busy) or 0, tonumber(q.capacity) or 0),
                ("Active AI companions on server: %d"):format(tonumber(msg.activeCompanions) or 0),
            }
            if o.lastError and o.lastError ~= "" then lines[#lines + 1] = "|cffff6060" .. esc(o.lastError) .. "|r" end
            if msg.op == "debug" then
                lines[#lines + 1] = " "
                lines[#lines + 1] = ("Companion: pending %d, language %s, memories %d"):format(tonumber(msg.pending) or 0, esc(msg.language), tonumber(msg.memories) or 0)
                lines[#lines + 1] = ("Requests %d, failures %d"):format(tonumber(d.requests) or 0, tonumber(d.failures) or 0)
                lines[#lines + 1] = ("Last: %s, %d ms, prompt %d chars"):format(esc(d.status), tonumber(d.latencyMs) or 0, tonumber(d.promptChars) or 0)
                if d.error and d.error ~= "" then lines[#lines + 1] = "|cffff6060" .. esc(d.error) .. "|r" end
                if d.warnings and #d.warnings > 0 then lines[#lines + 1] = "Warnings: " .. esc(table.concat(d.warnings, "; ")) end
            elseif msg.op == "error" then
                lines[#lines + 1] = "|cffaaaaaaDebug details are disabled on this server.|r"
            end
            text:SetText(table.concat(lines, "\n"))
            f.raw = d.raw
            f:RenderLog()
        end)
    end
    -- local only: never sends a request (errors from requests must not trigger new requests)
    function f:RenderLog()
        log:Clear()
        if f.raw and f.raw ~= "" then
            log:AddMessage("|cffffd100Raw model output:|r")
            log:AddMessage(esc(f.raw))
            log:AddMessage(" ")
        end
        log:AddMessage("|cffffd100Client errors:|r")
        for _, e in ipairs(AR.state.errors) do
            log:AddMessage(("|cff888888%s|r %s: %s"):format(date("%H:%M:%S", e.t), esc(e.where), esc(e.msg)))
        end
    end
    refresh:SetScript("OnClick", function() f:Load() end)
    AR:On("ERRORS_CHANGED", function() if f:IsShown() then f:RenderLog() end end)
    f.OnShowTab = function() f:Load() end
end

UI:RegisterTab("debug", "Debug", build, { small = true })
