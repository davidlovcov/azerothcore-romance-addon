--[[
  AzerothRomance - paged export / import of a companion.

  One export can be much larger than one addon message, so it travels in pages:
    export:  "export" {part = 0, 1, ...}  ->  "export_data" {part, parts, data = page JSON}
    import:  "import_begin" {parts}  ->  "import_part" {index, data} x parts  ->  "import_end"
  Every step waits for the server's answer (which also paces the traffic). The server applies
  an import only when every part arrived; a missing answer aborts with an error after TIMEOUT.
]]

local AR = _G.AzerothRomance
local Json = AR.Json

local T = {}
AR.Transfer = T

T.FORMAT = "mod-romance-export"
T.REQUEST_BUDGET = 14000     -- bytes per import request; the server accepts 16 KiB per message
T.TIMEOUT = 30               -- seconds without an answer before a transfer is abandoned

local active               -- { deadline, fail }
local timers = {}          -- { at, fn }: delayed retries

local watchdog = CreateFrame("Frame")
watchdog:SetScript("OnUpdate", function()
    if #timers > 0 then
        local now = GetTime()
        for i = #timers, 1, -1 do
            if timers[i].at <= now then
                local fn = timers[i].fn
                table.remove(timers, i)
                fn()
            end
        end
    end
    if active and GetTime() > active.deadline then
        local fail = active.fail
        active = nil
        fail("the server did not answer in time")
    end
end)
watchdog:Show()

local function step(fail)
    active = { deadline = GetTime() + T.TIMEOUT, fail = fail }
end

local function finish()
    active = nil
end

function T:Busy() return active ~= nil end

-- Sends a transfer request; when the server answers "Too many requests" the same request is sent again
-- after a short pause (a transfer shares the server's rate limit with everything else the addon does).
local function request(op, payload, cb)
    local tries = 0
    local function send()
        AR:Request(op, payload, function(msg)
            if msg.op == "error" and msg.code == "rate_limited" and active and tries < 8 then
                tries = tries + 1
                active.deadline = GetTime() + T.TIMEOUT
                timers[#timers + 1] = { at = GetTime() + 1.5, fn = send }
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
        if not ok or type(page) ~= "table" or page.format ~= T.FORMAT then return nil, "invalid page " .. i end
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

-- onDone(text, memoryCount) or onDone(nil, error)
function T:Export(guid, onProgress, onDone)
    if active then onDone(nil, "another transfer is still running") return end
    local pages = {}
    local function fail(err)
        finish()
        onDone(nil, err)
    end
    local function ask(part)
        step(fail)
        request("export", { guid = guid, part = part }, function(msg)
            if not active then return end
            if msg.op ~= "export_data" then return fail(AR:AckText(msg)) end
            if msg.parts == nil then          -- server without paging: one complete export
                finish()
                local ok, full = pcall(Json.Decode, msg.data or "")
                return onDone(msg.data, ok and type(full) == "table" and #(full.memories or {}) or 0)
            end
            pages[part + 1] = msg.data or ""
            local parts = tonumber(msg.parts) or 1
            if onProgress then onProgress(part + 1, parts) end
            if part + 1 < parts then return ask(part + 1) end
            finish()
            local full, err = T.JoinPages(pages)
            if not full then return onDone(nil, err) end
            onDone(Json.Encode(full), #full.memories)
        end)
    end
    ask(0)
end

-- ------------------------------------------------------------------ import

-- onDone(true, notes) or onDone(false, error)
function T:Import(guid, text, onProgress, onDone)
    if active then onDone(false, "another transfer is still running") return end
    local ok, full = pcall(Json.Decode, text or "")
    if not ok or type(full) ~= "table" or full.format ~= T.FORMAT then
        onDone(false, "that is not a complete mod-romance export (if you pasted it, the text may have been cut off)")
        return
    end
    local pages, err = T.SplitForImport(full, guid)
    if not pages then onDone(false, err) return end
    local function fail(e)
        finish()
        onDone(false, e)
    end
    local function expectOk(msg)
        if not active then return false end
        if msg.op ~= "ack" or not msg.ok then
            fail(AR:AckText(msg))
            return false
        end
        return true
    end
    local function sendPart(i)
        if i > #pages then
            step(fail)
            request("import_end", { guid = guid }, function(msg)
                if not expectOk(msg) then return end
                finish()
                onDone(true, msg.notes or {})
            end)
            return
        end
        step(fail)
        request("import_part", { guid = guid, index = i - 1, data = pages[i] }, function(msg)
            if not expectOk(msg) then return end
            if onProgress then onProgress(i, #pages) end
            sendPart(i + 1)
        end)
    end
    step(fail)
    request("import_begin", { guid = guid, parts = #pages }, function(msg)
        if not expectOk(msg) then return end
        sendPart(1)
    end)
end
