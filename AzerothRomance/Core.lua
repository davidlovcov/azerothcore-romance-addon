--[[
  AzerothRomance - core: saved variables, server communication, state, events.
  Licensed under the GNU GPL v2 or later.

  Everything authoritative (characters, ownership, relationship values, memories,
  Ollama) lives on the server. This addon only displays server data and sends
  requests; the server validates every request against the logged-in character.
]]

local AR = _G.AzerothRomance
local Protocol = AR.Protocol

AR.version = "1.0.0"
AR.state = {
    connected = false,
    hello = nil,
    status = nil,
    chars = {},
    companions = {},     -- guid -> companion payload
    relationship = {},   -- guid -> relationship payload
    typing = {},         -- guid -> true
    selected = nil,      -- selected companion guid
    profile = nil,
    profileIsDefault = true,
    models = nil,
    errors = {},         -- recent errors for the debug tab
}

-- ---------------------------------------------------------------- events

local listeners = {}

function AR:On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function AR:Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then self:LogError("ui:" .. event, err) end
    end
end

function AR:LogError(where, err)
    local e = self.state.errors
    table.insert(e, 1, { t = time(), where = tostring(where), msg = tostring(err) })
    while #e > 30 do table.remove(e) end
    self:Fire("ERRORS_CHANGED")
end

function AR:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff99cc[Romance]|r " .. tostring(msg))
end

-- ---------------------------------------------------------------- saved variables

local defaults = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 220, hide = false },
    chat = {},          -- [realm-char][guid] = { {from,text,ts}, ... }
    lastTab = "companion",
    timestamps = true,
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

function AR:CharKey()
    return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

function AR:ChatLog(guid)
    local key = self:CharKey()
    local db = AzerothRomanceDB.chat
    db[key] = db[key] or {}
    local k = tostring(guid)
    db[key][k] = db[key][k] or {}
    return db[key][k]
end

function AR:AddChatLine(guid, from, text, ts)
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

AR.sender = Protocol.NewSender(rawSend)

function AR:Request(op, payload, cb)
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
    AR.state.connected = true
    AR.state.hello = msg
    AR.state.presets = msg.presets or {}
    AR.state.status = msg.status
    AR:Fire("HELLO", msg)
    AR:Fire("STATUS_CHANGED")
end

handlers.chars = function(msg)
    AR.state.chars = msg.chars or {}
    AR.state.maxActive = msg.maxActive
    AR:Fire("CHARS_CHANGED")
    AR:Fire("STATUS_CHANGED")
end

handlers.chars_changed = function()
    AR:Request("list_chars")
    if AR.state.selected then AR:Request("get_companion", { guid = AR.state.selected }) end
end

handlers.companion = function(msg)
    local g = companionGuid(msg)
    if not g then return end
    AR.state.companions[g] = msg
    if msg.relationship then AR.state.relationship[g] = msg.relationship end
    AR:Fire("COMPANION_CHANGED", g)
end

handlers.companion_active = function(msg)
    AR:Request("list_chars")
    AR:Fire("STATUS_CHANGED")
end

handlers.relationship = function(msg)
    local g = companionGuid(msg)
    if not g then return end
    AR.state.relationship[g] = msg
    AR:Fire("RELATIONSHIP_CHANGED", g)
end

handlers.milestone = function(msg)
    AR:Print(("|cffffd100%s|r"):format(msg.label or "A new chapter begins."))
    PlaySound("LEVELUPSOUND")
    AR:Fire("RELATIONSHIP_CHANGED", companionGuid(msg))
end

handlers.chat_msg = function(msg)
    local g = companionGuid(msg)
    AR:AddChatLine(g, msg.from, msg.text, msg.ts)
    if msg.from == "companion" then
        AR.state.typing[g] = nil
        AR:Fire("TYPING_CHANGED", g)
    end
end

handlers.typing = function(msg)
    local g = companionGuid(msg)
    AR.state.typing[g] = msg.on and true or nil
    AR:Fire("TYPING_CHANGED", g)
end

handlers.status = function(msg)
    AR.state.status = msg
    AR:Fire("STATUS_CHANGED")
end

handlers.profile = function(msg)
    AR.state.profile = msg.profile or {}
    AR.state.profileIsDefault = msg.accountDefault and true or false
    AR:Fire("PROFILE_CHANGED")
end

handlers.presets = function(msg)
    AR.state.presets = msg.presets or AR.state.presets
    AR:Fire("PRESETS_CHANGED")
end

handlers.models = function(msg)
    AR.state.models = msg
    AR:Fire("MODELS_CHANGED")
end

handlers.memory_changed = function(msg)
    AR:Fire("MEMORY_CHANGED", companionGuid(msg))
end

handlers.error = function(msg)
    local text = (msg.message and msg.message ~= "") and msg.message or msg.code or "unknown error"
    AR:LogError(msg["for"] or "server", (msg.code or "") .. ": " .. text)
    if msg.code ~= "protocol" then
        AR:Print("|cffff6060" .. text .. "|r")
    end
    if msg.code == "busy" or msg.code == "not_active" then
        local g = companionGuid(msg) or AR.state.selected
        if g then
            AR.state.typing[g] = nil
            AR:Fire("TYPING_CHANGED", g)
        end
    end
end

local function dispatch(msg)
    local req = msg.req and tonumber(msg.req)
    if req and pending[req] then
        local p = pending[req]
        pending[req] = nil
        local ok, err = pcall(p.cb, msg)
        if not ok then AR:LogError("cb:" .. tostring(p.op), err) end
    end
    local h = handlers[msg.op]
    if h then
        local ok, err = pcall(h, msg)
        if not ok then AR:LogError("handler:" .. msg.op, err) end
    end
    AR:Fire("MESSAGE", msg)
end

-- ---------------------------------------------------------------- event frame

local frame = CreateFrame("Frame", "AzerothRomanceEventFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_LOGOUT")

local helloRetry = 0
local helloTimer = 0

frame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" and a1 == "AzerothRomance" then
        AzerothRomanceDB = AzerothRomanceDB or {}
        copyDefaults(AzerothRomanceDB, defaults)
        AR.db = AzerothRomanceDB
        AR:Fire("DB_READY")
    elseif event == "PLAYER_LOGIN" then
        helloRetry = 3
        helloTimer = 2
        AR:Fire("LOGIN")
    elseif event == "CHAT_MSG_ADDON" then
        -- a1 prefix, a2 message, a3 distribution, a4 sender
        if a1 ~= Protocol.PREFIX or a3 ~= "WHISPER" or a4 ~= UnitName("player") then return end
        local msg, err = reassembler:Feed(a2, GetTime())
        if msg then
            dispatch(msg)
        elseif msg == false then
            AR:LogError("protocol", err)
        end
    end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    AR.sender:Update(elapsed)
    if helloRetry > 0 and not AR.state.connected then
        helloTimer = helloTimer - elapsed
        if helloTimer <= 0 then
            helloRetry = helloRetry - 1
            helloTimer = 5
            AR:Request("hello", { version = AR.version, protocol = Protocol.VERSION })
        end
    end
    -- drop stale callbacks
    local now = GetTime()
    for req, p in pairs(pending) do
        if now - p.t > 60 then pending[req] = nil end
    end
end)

-- ---------------------------------------------------------------- helpers shared by the UI

AR.CLASS_TOKENS = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
    [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID" }

AR.STATUS_INFO = {
    available            = { label = "Available",             color = { 0.45, 0.85, 0.45 }, enabled = true },
    in_party             = { label = "In your party",         color = { 1.00, 0.82, 0.30 }, enabled = true },
    summoned             = { label = "Already summoned",      color = { 0.95, 0.75, 0.35 }, enabled = true },
    online_player        = { label = "Online as a player",    color = { 0.55, 0.55, 0.55 }, enabled = false },
    controlled_elsewhere = { label = "Controlled elsewhere",  color = { 0.55, 0.55, 0.55 }, enabled = false },
    unavailable          = { label = "Unavailable",           color = { 0.55, 0.55, 0.55 }, enabled = false },
    offline              = { label = "Offline",               color = { 0.55, 0.55, 0.55 }, enabled = false },
    ai_disabled          = { label = "AI companion disabled", color = { 0.70, 0.60, 0.80 }, enabled = true },
}

function AR:ClassColor(classId)
    local token = self.CLASS_TOKENS[tonumber(classId) or 0]
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

-- Built-in presets plus the account's custom ones (custom = true).
function AR:Presets()
    return self.state.presets or (self.state.hello and self.state.hello.presets) or {}
end

-- Names of the companions whose AI is active right now, in list order.
function AR:ActiveNames()
    local names = {}
    for _, c in ipairs(self.state.chars or {}) do
        if c.active then table.insert(names, c.name) end
    end
    return names
end

-- Readable text for a failed ack: the server sends `message`; older servers only `code`.
function AR:AckText(msg)
    if msg.message and msg.message ~= "" then return msg.message end
    return tostring(msg.code or "unknown error")
end

function AR:FindChar(guid)
    for _, c in ipairs(self.state.chars) do
        if tonumber(c.guid) == tonumber(guid) then return c end
    end
end

function AR:Selected()
    local g = self.state.selected
    return g, g and self.state.companions[g], g and self:FindChar(g)
end

function AR:Select(guid)
    guid = tonumber(guid)
    self.state.selected = guid
    if guid then
        self:Request("get_companion", { guid = guid })
        self:Request("get_history", { guid = guid, limit = 30 }, function(msg)
            if msg.op ~= "history" then return end
            local log = self:ChatLog(guid)
            if #log == 0 then
                for _, it in ipairs(msg.items or {}) do
                    if it.from ~= "event" then table.insert(log, { from = it.from, text = it.text, ts = it.ts }) end
                end
                self:Fire("CHAT_CHANGED", guid)
            end
        end)
    end
    self:Fire("SELECTION_CHANGED", guid)
end

function AR:OllamaOnline()
    local s = self.state.status
    return s and s.ollama and s.ollama.online
end

-- ---------------------------------------------------------------- slash command

SLASH_AZEROTHROMANCE1 = "/romance"
SLASH_AZEROTHROMANCE2 = "/ar"
SlashCmdList["AZEROTHROMANCE"] = function(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if input == "status" then
        AR:Request("get_status", {}, function(msg)
            local o = msg.ollama or {}
            AR:Print(("Module %s, Ollama %s%s, model %s"):format(msg.enabled and "on" or "off",
                o.online and "|cff60ff60online|r" or "|cffff6060offline|r", o.version ~= "" and (" " .. (o.version or "")) or "",
                tostring(msg.model)))
        end)
    elseif input == "reset window" then
        AR.db.window = { point = "CENTER", x = 0, y = 0 }
        if AR.UI and AR.UI.main then
            AR.UI.main:ClearAllPoints()
            AR.UI.main:SetPoint("CENTER")
        end
    elseif input == "minimap" then
        AR.db.minimap.hide = not AR.db.minimap.hide
        AR:Fire("MINIMAP_TOGGLE")
    else
        if AR.UI then AR.UI:Toggle() end
    end
end
