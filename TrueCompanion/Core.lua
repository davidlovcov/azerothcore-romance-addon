--[[
  TrueCompanion - core: saved variables, server communication, state, events.
  Licensed under the GNU GPL v2 or later.

  Everything authoritative (characters, ownership, relationship values, memories,
  Ollama) lives on the server. This addon only displays server data and sends
  requests; the server validates every request against the logged-in character.
]]

local TC = _G.TrueCompanion
local Protocol = TC.Protocol

TC.version = "2.0.0"
TC.state = {
    connected = false,
    hello = nil,
    status = nil,
    chars = {},
    companions = {},     -- guid -> companion payload
    sheets = {},         -- guid -> character sheet (bags, quests, spells, ...)
    relationship = {},   -- guid -> relationship payload
    typing = {},         -- guid -> true (see TC:SetTyping)
    typingSince = {},    -- guid -> GetTime() when the indicator was switched on
    selected = nil,      -- selected companion guid
    profile = nil,
    profileIsDefault = true,
    models = nil,
    errors = {},         -- recent errors for the debug tab
}

-- '|' opens a UI escape sequence (colour, texture, link): server and player text is shown literally.
function TC:Escape(s) return (tostring(s or "")):gsub("|", "||") end

-- ---------------------------------------------------------------- events

local listeners = {}

function TC:On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function TC:Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then self:LogError("ui:" .. event, err) end
    end
end

function TC:LogError(where, err)
    local e = self.state.errors
    table.insert(e, 1, { t = time(), where = tostring(where), msg = tostring(err) })
    while #e > 30 do table.remove(e) end
    self:Fire("ERRORS_CHANGED")
end

function TC:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cfff2e6c8[True Companion]|r " .. tostring(msg))
end

-- ---------------------------------------------------------------- saved variables

local defaults = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 220, hide = false },
    chat = {},          -- [realm-char][guid] = { {from,text,ts}, ... }
    lastTab = "companion",
    timestamps = true,
    hideBotFeedback = true,   -- hide Playerbots' command feedback from companions in the chat window
}

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function TC:CharKey()
    return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

function TC:ChatLog(guid)
    local key = self:CharKey()
    local db = TrueCompanionDB.chat
    db[key] = db[key] or {}
    local k = tostring(guid)
    db[key][k] = db[key][k] or {}
    return db[key][k]
end

function TC:AddChatLine(guid, from, text, ts)
    if not guid or not text then return end
    local log = self:ChatLog(guid)
    local last = log[#log]
    -- the server echoes player lines; avoid duplicates from history refreshes
    if last and last.text == text and last.from == from and math.abs((last.ts or 0) - (ts or 0)) < 3 then return end
    table.insert(log, { from = from, text = text, ts = ts or time() })
    while #log > 200 do table.remove(log, 1) end
    self:Fire("CHAT_CHANGED", guid)
end

-- ---------------------------------------------------------------- communication

local reassembler = Protocol.NewReassembler()
local pending = {}       -- req -> { op, cb, t }
local reqCounter = 0

local function rawSend(chunk)
    SendAddonMessage(Protocol.PREFIX, chunk, "WHISPER", UnitName("player"))
end

TC.sender = Protocol.NewSender(rawSend)

function TC:Request(op, payload, cb)
    payload = payload or {}
    payload.op = op
    reqCounter = reqCounter + 1
    payload.req = reqCounter
    if cb then pending[reqCounter] = { op = op, cb = cb, t = GetTime() } end
    local ok, err = pcall(self.sender.Queue, self.sender, payload)
    if not ok then self:LogError("send:" .. op, err) end
    return reqCounter
end

local function companionGuid(msg)
    return msg.guid and tonumber(msg.guid)
end

local handlers = {}

handlers.hello = function(msg)
    TC.state.connected = true
    TC.state.hello = msg
    TC.state.presets = msg.presets or {}
    TC.state.status = msg.status
    TC:Fire("HELLO", msg)
    TC:Fire("STATUS_CHANGED")
end

handlers.chars = function(msg)
    TC.state.chars = msg.chars or {}
    TC.state.maxActive = msg.maxActive
    TC:Fire("CHARS_CHANGED")
    TC:Fire("STATUS_CHANGED")
end

handlers.chars_changed = function()
    TC:Request("list_chars")
    if TC.state.selected then TC:Request("get_companion", { guid = TC.state.selected }) end
end

handlers.companion = function(msg)
    local g = companionGuid(msg)
    if not g then return end
    TC.state.companions[g] = msg
    if msg.relationship then TC.state.relationship[g] = msg.relationship end
    TC:Fire("COMPANION_CHANGED", g)
end

handlers.companion_active = function(msg)
    TC:Request("list_chars")
    TC:Fire("STATUS_CHANGED")
end

handlers.relationship = function(msg)
    local g = companionGuid(msg)
    if not g then return end
    TC.state.relationship[g] = msg
    TC:Fire("RELATIONSHIP_CHANGED", g)
end

handlers.milestone = function(msg)
    TC:Print(("|cffffd100%s|r"):format(TC:Escape(msg.label or "A new chapter begins.")))
    PlaySound("LEVELUPSOUND")
    TC:Fire("RELATIONSHIP_CHANGED", companionGuid(msg))
end

-- Longer than the server's request timeout plus one retry; a lost "typing off" (server restart,
-- reload, a line the server answered without AI) must not leave "is thinking..." up forever.
TC.TYPING_TIMEOUT = 100

function TC:SetTyping(guid, on)
    if not guid then return end
    if on then
        self.state.typing[guid] = true
        self.state.typingSince[guid] = GetTime()
    else
        self.state.typing[guid] = nil
        self.state.typingSince[guid] = nil
    end
    self:Fire("TYPING_CHANGED", guid)
end

function TC:ExpireTyping(now)
    for g, since in pairs(self.state.typingSince) do
        if now - since > self.TYPING_TIMEOUT then self:SetTyping(g, false) end
    end
end

handlers.chat_msg = function(msg)
    local g = companionGuid(msg)
    TC:AddChatLine(g, msg.from, msg.text, msg.ts)
    if msg.from == "companion" then
        if TC.ChatFilter then TC.ChatFilter:Expect(g, msg.text) end
        TC:SetTyping(g, false)
    end
end

handlers.bot_feedback = function(msg)
    if TC.ChatFilter then TC.ChatFilter:Allow(msg.name) end
end

handlers.typing = function(msg)
    TC:SetTyping(companionGuid(msg), msg.on and true or false)
end

handlers.status = function(msg)
    TC.state.status = msg
    TC:Fire("STATUS_CHANGED")
end

handlers.profile = function(msg)
    TC.state.profile = msg.profile or {}
    TC.state.profileIsDefault = msg.accountDefault and true or false
    TC:Fire("PROFILE_CHANGED")
end

handlers.character_sheet = function(msg)
    local g = companionGuid(msg)
    if not g then return end
    TC.state.sheets[g] = msg
    TC:Fire("SHEET_CHANGED", g)
end

handlers.presets = function(msg)
    TC.state.presets = msg.presets or TC.state.presets
    TC:Fire("PRESETS_CHANGED")
end

handlers.models = function(msg)
    TC.state.models = msg
    TC:Fire("MODELS_CHANGED")
end

-- memory_changed arrives once per changed memory (many at once after an import or a tidy-up): every tab that
-- shows memories reloads at most once per second per companion, and not while an import / export is running.
local memoryDirty = {}   -- guid (0 = unknown) -> GetTime() when MEMORY_CHANGED fires
local memoryTimer = CreateFrame("Frame")
memoryTimer:SetScript("OnUpdate", function()
    if not next(memoryDirty) then return end
    if TC.Transfer and TC.Transfer:Busy() then return end
    local now = GetTime()
    for g, at in pairs(memoryDirty) do
        if now >= at then
            memoryDirty[g] = nil
            TC:Fire("MEMORY_CHANGED", g ~= 0 and g or nil)
        end
    end
end)
memoryTimer:Show()

handlers.memory_changed = function(msg)
    local g = companionGuid(msg) or 0
    if not memoryDirty[g] then memoryDirty[g] = GetTime() + 1 end
end

handlers.error = function(msg)
    -- a running import / export resends a rate-limited step by itself: nothing to report
    if msg.code == "rate_limited" and TC.Transfer and TC.Transfer:Busy() then return end
    local text = (msg.message and msg.message ~= "") and msg.message or msg.code or "unknown error"
    TC:LogError(msg["for"] or "server", (msg.code or "") .. ": " .. text)
    -- "Too many requests" once in a while, not once per rejected request
    local quiet = msg.code == "rate_limited" and TC.lastRateLimitNote and GetTime() - TC.lastRateLimitNote < 10
    if msg.code == "rate_limited" and not quiet then TC.lastRateLimitNote = GetTime() end
    if msg.code ~= "protocol" and not quiet then
        TC:Print("|cffff6060" .. TC:Escape(text) .. "|r")
    end
    -- no answer is coming for these: clear "is thinking..."
    local noReply = { busy = true, not_active = true, ai_disabled = true, timeout = true, offline = true,
        model_missing = true, http_error = true, bad_response = true }
    if noReply[msg.code] or (msg.code == "rate_limited" and msg["for"] == "chat") then
        TC:SetTyping(companionGuid(msg) or TC.state.selected, false)
    end
end

local function dispatch(msg)
    -- a malformed server field must not abort the whole message (this runs outside any pcall)
    local req = (type(msg.req) == "number" or type(msg.req) == "string") and tonumber(msg.req) or nil
    if req and pending[req] then
        local p = pending[req]
        pending[req] = nil
        local ok, err = pcall(p.cb, msg)
        if not ok then TC:LogError("cb:" .. tostring(p.op), err) end
    end
    local h = handlers[msg.op]
    if h then
        local ok, err = pcall(h, msg)
        if not ok then TC:LogError("handler:" .. msg.op, err) end
    end
    TC:Fire("MESSAGE", msg)
end

-- ---------------------------------------------------------------- event frame

local frame = CreateFrame("Frame", "TrueCompanionEventFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_LOGOUT")

local helloRetry = 0
local helloTimer = 0

frame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" and a1 == "TrueCompanion" then
        -- settings from before the rename (AzerothRomance): taken over once, if the old saved variables file was
        -- renamed to TrueCompanion.lua (see the README)
        if TrueCompanionDB == nil and type(AzerothRomanceDB) == "table" then TrueCompanionDB = AzerothRomanceDB end
        AzerothRomanceDB = nil
        TrueCompanionDB = TrueCompanionDB or {}
        copyDefaults(TrueCompanionDB, defaults)
        TC.db = TrueCompanionDB
        TC:Fire("DB_READY")
    elseif event == "PLAYER_LOGIN" then
        helloRetry = 3
        helloTimer = 2
        TC:Fire("LOGIN")
    elseif event == "CHAT_MSG_ADDON" then
        -- a1 prefix, a2 message, a3 distribution, a4 sender
        if a1 ~= Protocol.PREFIX or a3 ~= "WHISPER" or a4 ~= UnitName("player") then return end
        local msg, err = reassembler:Feed(a2, GetTime())
        if msg then
            dispatch(msg)
        elseif msg == false then
            TC:LogError("protocol", err)
        end
    end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    TC.sender:Update(elapsed)
    if helloRetry > 0 and not TC.state.connected then
        helloTimer = helloTimer - elapsed
        if helloTimer <= 0 then
            helloRetry = helloRetry - 1
            helloTimer = 5
            TC:Request("hello", { version = TC.version, protocol = Protocol.VERSION })
        end
    end
    -- drop stale callbacks and typing indicators
    local now = GetTime()
    TC:ExpireTyping(now)
    for req, p in pairs(pending) do
        if now - p.t > 60 then pending[req] = nil end
    end
end)

-- ---------------------------------------------------------------- helpers shared by the UI

TC.CLASS_TOKENS = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
    [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID" }

TC.STATUS_INFO = {
    available            = { label = "Available",             color = { 0.45, 0.85, 0.45 }, enabled = true },
    in_party             = { label = "In your party",         color = { 1.00, 0.82, 0.30 }, enabled = true },
    summoned             = { label = "Already summoned",      color = { 0.95, 0.75, 0.35 }, enabled = true },
    online_player        = { label = "Online as a player",    color = { 0.55, 0.55, 0.55 }, enabled = false },
    controlled_elsewhere = { label = "Controlled elsewhere",  color = { 0.55, 0.55, 0.55 }, enabled = false },
    unavailable          = { label = "Unavailable",           color = { 0.55, 0.55, 0.55 }, enabled = false },
    offline              = { label = "Offline",               color = { 0.55, 0.55, 0.55 }, enabled = false },
    ai_disabled          = { label = "AI off (commands)", color = { 0.70, 0.60, 0.80 }, enabled = true },
}

-- Status of a character entry, including estrangement (she left you / came back cold).
function TC:CharStatus(c)
    if not c then return self.STATUS_INFO.unavailable end
    local backAt = tonumber(c.estrangedUntil)
    if backAt and backAt > 0 then
        local hours = math.max(1, math.ceil((backAt - time()) / 3600))
        return { label = ("Left you (back in ~%dh)"):format(hours), color = { 0.9, 0.3, 0.3 }, enabled = false }
    end
    local st = self.STATUS_INFO[c.status] or self.STATUS_INFO.unavailable
    if c.estranged then
        return { label = st.label .. " - estranged", color = { 0.75, 0.45, 0.75 }, enabled = st.enabled }
    end
    return st
end

function TC:ClassColor(classId)
    local token = self.CLASS_TOKENS[tonumber(classId) or 0]
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

-- Built-in presets plus the account's custom ones (custom = true).
function TC:Presets()
    return self.state.presets or (self.state.hello and self.state.hello.presets) or {}
end

-- Names of the companions whose AI is active right now, in list order.
-- ---------------------------------------------------------------- who leads

-- Asks the server who leads and where to (TC.state.lead). Skipped without companions; an older server that doesn't
-- know the request is not asked again.
function TC:RequestLead()
    if not self.state.connected or self.state.leadUnsupported or #self:ActiveNames() == 0 then
        if self.state.lead and #self:ActiveNames() == 0 then
            self.state.lead = nil
            self:Fire("LEAD_CHANGED")
        end
        return
    end
    self:Request("get_lead", {}, function(msg)
        if msg.op == "lead_state" then
            self.state.lead = msg
        elseif msg.op == "error" and msg.code == "unknown_op" then
            -- an older server: don't ask again (a busy server, "rate_limited", is simply asked next time)
            self.state.leadUnsupported = true
            self.state.lead = nil
        end
        self:Fire("LEAD_CHANGED")
    end)
end

local LEAD_KIND = {
    turn_in = "to turn in quests", pick_up = "for new quests", take = "to take a quest", merchant = "to sell junk",
    trainer = "to learn spells",
}

-- "Rindronor leads to "Solanian's Belongings" (260 yd south)", "You lead", or "" when unknown.
function TC:LeadText(lead)
    lead = lead or self.state.lead
    if not lead then return "" end
    local text
    if lead.leader then
        if lead.kind == "grind" then
            text = ("%s leads: fighting around here"):format(lead.leader)
        else
            local target = lead.kind == "quest" and ("\"" .. (lead.target or "?") .. "\"") or (lead.target or "?")
            text = ("%s leads to %s"):format(lead.leader, target)
            if LEAD_KIND[lead.kind] then text = text .. " " .. LEAD_KIND[lead.kind] end
            local d = tonumber(lead.distance) or -1
            if d >= 0 then text = text .. (" (%d yd %s)"):format(d, lead.direction or "") end
        end
        if lead.paused then text = text .. " - waiting" end
    elseif lead.you then
        text = lead.fighting and "You lead - fighting here" or "You lead"
    else
        return ""
    end
    for _, e in ipairs(lead.errands or {}) do
        text = text .. ("; %s is off to %s"):format(e.name or "?", e.target or "?")
    end
    return text
end

function TC:ActiveNames()
    local names = {}
    for _, c in ipairs(self.state.chars or {}) do
        if c.active then table.insert(names, c.name) end
    end
    return names
end

-- Readable text for a failed ack: the server sends `message`; older servers only `code`.
function TC:AckText(msg)
    if msg.message and msg.message ~= "" then return msg.message end
    return tostring(msg.code or "unknown error")
end

function TC:FindChar(guid)
    for _, c in ipairs(self.state.chars) do
        if tonumber(c.guid) == tonumber(guid) then return c end
    end
end

function TC:Selected()
    local g = self.state.selected
    return g, g and self.state.companions[g], g and self:FindChar(g)
end

function TC:Select(guid)
    guid = tonumber(guid)
    self.state.selected = guid
    if guid then
        self:Request("get_companion", { guid = guid })
        self:Request("get_history", { guid = guid, limit = 30 }, function(msg)
            if msg.op ~= "history" then return end
            local log = self:ChatLog(guid)
            if #log == 0 then
                for _, it in ipairs(msg.items or {}) do
                    -- these entries are stored in SavedVariables and rendered later: keep only what renders
                    if type(it) == "table" and it.from ~= "event" and type(it.text) == "string" then
                        table.insert(log, { from = type(it.from) == "string" and it.from or "companion",
                                            text = it.text, ts = tonumber(it.ts) })
                    end
                end
                self:Fire("CHAT_CHANGED", guid)
            end
        end)
    end
    self:Fire("SELECTION_CHANGED", guid)
end

function TC:OllamaOnline()
    local s = self.state.status
    return s and s.ollama and s.ollama.online
end

-- ---------------------------------------------------------------- slash command

SLASH_TRUECOMPANION1 = "/tc"
SLASH_TRUECOMPANION2 = "/companion"
SlashCmdList["TRUECOMPANION"] = function(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if input == "status" then
        TC:Request("get_status", {}, function(msg)
            local o = msg.ollama or {}
            TC:Print(("Module %s, Ollama %s%s, model %s"):format(msg.enabled and "on" or "off",
                o.online and "|cff60ff60online|r" or "|cffff6060offline|r", (o.version and o.version ~= "") and (" " .. o.version) or "",
                tostring(msg.model)))
        end)
    elseif input == "reset window" then
        TC.db.window = { point = "CENTER", x = 0, y = 0 }
        if TC.UI and TC.UI.main then
            TC.UI.main:ClearAllPoints()
            TC.UI.main:SetPoint("CENTER")
        end
    elseif input == "minimap" then
        TC.db.minimap.hide = not TC.db.minimap.hide
        TC:Fire("MINIMAP_TOGGLE")
    else
        if TC.UI then TC.UI:Toggle() end
    end
end
