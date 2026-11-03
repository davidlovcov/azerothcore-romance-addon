--[[
  TrueCompanion - paged export / import of a companion.

  One export can be much larger than one addon message, so it travels in pages:
    export:  "export" {part = 0, 1, ...}  ->  "export_data" {part, parts, data = page JSON}
    import:  "import_begin" {parts}  ->  "import_part" {index, data} x parts  ->  "import_end"
  Every step waits for the server's answer (which also paces the traffic). The server applies
  an import only when every part arrived; a missing answer aborts with an error after TIMEOUT.
]]

local TC = _G.TrueCompanion
local Json = TC.Json

local T = {}
TC.Transfer = T

T.FORMAT = "mod-true-companion-export"
-- exports made before the module was renamed (mod-romance) can still be imported
function T.IsFormat(f) return f == T.FORMAT or f == "mod-romance-export" end
T.REQUEST_BUDGET = 14000     -- bytes per import request; the server accepts 16 KiB per message
T.TIMEOUT = 30               -- seconds without an answer before a transfer is abandoned

-- The running transfer: { id, deadline, fail, done }. Every callback and retry checks that it still belongs to
-- the running transfer, so a late answer to an abandoned (timed-out) transfer can never touch a newer one.
local active
local nextId = 0
local timers = {}          -- { at, fn, t }: delayed retries of transfer t

local function isLive(t) return t ~= nil and active == t and not t.done end

-- ends transfer t exactly once; later calls (late answers, the watchdog) do nothing
local function complete(t, fn, ...)
    if not t or t.done then return end
    t.done = true
    if active == t then active = nil end
    for i = #timers, 1, -1 do
        if timers[i].t == t then table.remove(timers, i) end
    end
    fn(...)
end

local watchdog = CreateFrame("Frame")
watchdog:SetScript("OnUpdate", function()
    -- the timeout first: a transfer that ran out of time must not send its pending retry anymore
    if active and GetTime() > active.deadline then
        local t = active
        complete(t, t.fail, "the server did not answer in time", true)
    end
    if #timers > 0 then
        local now = GetTime()
        for i = #timers, 1, -1 do
            local tm = timers[i]
            if tm and tm.at <= now then
                table.remove(timers, i)
                if isLive(tm.t) then tm.fn() end
            end
        end
    end
end)
watchdog:Show()

local function begin(fail)
    nextId = nextId + 1
    active = { id = nextId, deadline = GetTime() + T.TIMEOUT, fail = fail, done = false }
    return active
end

local function step(t)
    if isLive(t) then t.deadline = GetTime() + T.TIMEOUT end
end

function T:Busy() return active ~= nil end

-- Sends a transfer request for transfer t; when the server answers "Too many requests" the same request is sent
-- again after a short pause (a transfer shares the server's rate limit with everything else the addon does).
-- Answers that arrive after t ended are ignored.
local function request(t, op, payload, cb)
    local tries = 0
    local function send()
        if not isLive(t) then return end
        TC:Request(op, payload, function(msg)
            if not isLive(t) then return end
            if msg.op == "error" and msg.code == "rate_limited" and tries < 8 then
                tries = tries + 1
                step(t)
                timers[#timers + 1] = { at = GetTime() + 1.5, fn = send, t = t }
                return
            end
            cb(msg)
        end)
    end
    send()
end

-- ------------------------------------------------------------------ pages

-- Joins export pages (JSON strings, in order) into one export table.
function T.JoinPages(pages)
    local full, memories = nil, {}
    for i, text in ipairs(pages) do
        local ok, page = pcall(Json.Decode, text)
        if not ok or type(page) ~= "table" or not T.IsFormat(page.format) then return nil, "invalid page " .. i end
        if page.page ~= nil and (tonumber(page.page) ~= i - 1 or tonumber(page.pages) ~= #pages) then
            return nil, "pages out of order"
        end
        if i == 1 then
            full = {}
            for k, v in pairs(page) do
                if k ~= "page" and k ~= "pages" and k ~= "memories" then full[k] = v end
            end
        end
        for _, m in ipairs(page.memories or {}) do table.insert(memories, m) end
    end
    if not full then return nil, "empty export" end
    full.memories = Json.Array(memories)
    return full
end

local function newPage(full, index)
    local p = {}
    if index == 0 then
        for k, v in pairs(full) do
            if k ~= "memories" then p[k] = v end
        end
    end
    p.format = T.FORMAT
    p.page = index
    p.pages = 9999          -- placeholder with the most digits; set when the count is known
    p.memories = Json.Array({})
    return p
end

local function requestSize(guid, index, page)
    return #Json.Encode({ op = "import_part", guid = guid, index = index, data = Json.Encode(page), req = 999999 })
end

-- Splits an export table into page strings whose import requests stay within REQUEST_BUDGET.
function T.SplitForImport(full, guid)
    local pages = { newPage(full, 0) }
    for _, m in ipairs(full.memories or {}) do
        local page = pages[#pages]
        table.insert(page.memories, m)
        if requestSize(guid, #pages - 1, page) > T.REQUEST_BUDGET then
            table.remove(page.memories)
            if #page.memories == 0 then return nil, "a single memory is too large to send" end
            page = newPage(full, #pages)
            table.insert(pages, page)
            table.insert(page.memories, m)
            if requestSize(guid, #pages - 1, page) > T.REQUEST_BUDGET then return nil, "a single memory is too large to send" end
        end
    end
    local out = {}
    for _, p in ipairs(pages) do
        p.pages = #pages
        table.insert(out, Json.Encode(p))
    end
    return out
end

-- ------------------------------------------------------------------ export

-- onDone(text, memoryCount) or onDone(nil, error). Called exactly once.
function T:Export(guid, onProgress, onDone)
    if active then onDone(nil, "another transfer is still running") return end
    local pages, snapshot = {}, nil
    local t
    local function fail(err) complete(t, onDone, nil, err) end
    t = begin(function(err) onDone(nil, err) end)
    local function ask(part)
        step(t)
        request(t, "export", { guid = guid, part = part, snapshot = snapshot }, function(msg)
            if msg.op ~= "export_data" then return fail(TC:AckText(msg)) end
            if msg.parts == nil then          -- server without paging: one complete export
                local ok, full = pcall(Json.Decode, msg.data or "")
                if not ok or type(full) ~= "table" or not T.IsFormat(full.format) then
                    return fail("the server sent an invalid export")
                end
                return complete(t, onDone, msg.data, #(full.memories or {}))
            end
            -- every page must come from the same frozen export (the server's snapshot)
            if part == 0 then
                snapshot = msg.snapshot
            elseif msg.snapshot ~= snapshot then
                return fail("the export changed while it was being sent; please export again")
            end
            pages[part + 1] = msg.data or ""
            local parts = tonumber(msg.parts) or 1
            if onProgress then onProgress(part + 1, parts) end
            if part + 1 < parts then return ask(part + 1) end
            local full, err = T.JoinPages(pages)
            if not full then return fail(err) end
            complete(t, onDone, Json.Encode(full), #full.memories)
        end)
    end
    ask(0)
end

-- ------------------------------------------------------------------ import

-- onDone(true, notes) or onDone(false, error, unknown). Called exactly once. `unknown` is true when the answer to
-- "import_end" never came: the server may have applied the import, so "nothing changed" can't be claimed.
function T:Import(guid, text, onProgress, onDone)
    if active then onDone(false, "another transfer is still running") return end
    local ok, full = pcall(Json.Decode, text or "")
    if not ok or type(full) ~= "table" or not T.IsFormat(full.format) then
        onDone(false, "that is not a complete mod-true-companion export (if you pasted it, the text may have been cut off)")
        return
    end
    local pages, err = T.SplitForImport(full, guid)
    if not pages then onDone(false, err) return end
    local committing = false
    local t = begin(function(e, timedOut) onDone(false, e, timedOut and committing or false) end)
    local function fail(e) complete(t, onDone, false, e, false) end
    local function expectOk(msg)
        if msg.op ~= "ack" or not msg.ok then
            fail(TC:AckText(msg))
            return false
        end
        return true
    end
    local function sendPart(i)
        step(t)
        if i > #pages then
            committing = true
            request(t, "import_end", { guid = guid }, function(msg)
                if not expectOk(msg) then return end
                complete(t, onDone, true, msg.notes or {})
            end)
            return
        end
        request(t, "import_part", { guid = guid, index = i - 1, data = pages[i] }, function(msg)
            if not expectOk(msg) then return end
            if onProgress then onProgress(i, #pages) end
            sendPart(i + 1)
        end)
    end
    request(t, "import_begin", { guid = guid, parts = #pages }, function(msg)
        if not expectOk(msg) then return end
        sendPart(1)
    end)
end
