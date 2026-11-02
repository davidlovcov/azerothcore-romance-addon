--[[
  TrueCompanion - addon <-> server protocol (see ADDON_PROTOCOL.md)
  Licensed under the GNU GPL v2 or later.

  Wire chunk:   <id>:<seq>/<total>:<data>   sent with prefix "TCMP" as a WHISPER to yourself.
  The server answers with whispers in LANG_ADDON that arrive as CHAT_MSG_ADDON.
]]

local TC = _G.TrueCompanion
local Json = TC.Json

local Protocol = {}
TC.Protocol = Protocol

Protocol.PREFIX = "TCMP"
Protocol.VERSION = 1
Protocol.CHUNK = 200
Protocol.MAX_INBOUND = 64 * 1024     -- server messages (memory pages, exports)
Protocol.PARTIAL_TIMEOUT = 20

local strsub, strbyte, strfind, floor = string.sub, string.byte, string.find, math.floor

local function base36(n)
    local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    local s = ""
    repeat
        local d = n % 36
        s = strsub(digits, d + 1, d + 1) .. s
        n = floor(n / 36)
    until n == 0 or #s >= 6
    return s
end

-- Splits an encoded JSON message into wire chunks, never inside a UTF-8 sequence.
function Protocol.Encode(msg, id)
    local data = Json.Encode(msg)
    local pieces = {}
    local pos, len = 1, #data
    while pos <= len do
        local n = math.min(Protocol.CHUNK, len - pos + 1)
        while n > 1 and pos + n <= len do
            local b = strbyte(data, pos + n)
            if b >= 0x80 and b < 0xC0 then n = n - 1 else break end
        end
        pieces[#pieces + 1] = strsub(data, pos, pos + n - 1)
        pos = pos + n
    end
    if #pieces == 0 then pieces[1] = "{}" end
    local sid = base36(id)
    local out = {}
    for i, p in ipairs(pieces) do
        out[i] = sid .. ":" .. i .. "/" .. #pieces .. ":" .. p
    end
    return out
end

-- Reassembler for inbound (server -> client) chunks.
local Reassembler = {}
Reassembler.__index = Reassembler

function Protocol.NewReassembler()
    return setmetatable({ partials = {} }, Reassembler)
end

-- Returns message table when complete, nil while incomplete, or false, err on error.
function Reassembler:Feed(chunk, now)
    now = now or 0
    for id, p in pairs(self.partials) do
        if now - p.first > Protocol.PARTIAL_TIMEOUT then self.partials[id] = nil end
    end
    local id, seq, total, data = chunk:match("^(%w+):(%d+)/(%d+):(.*)$")
    seq, total = tonumber(seq), tonumber(total)
    if not id or not seq or not total or seq < 1 or seq > total or total > 400 then
        return false, "bad chunk"
    end
    local p = self.partials[id]
    if not p then
        p = { total = total, parts = {}, received = 0, bytes = 0, first = now }
        self.partials[id] = p
    end
    if p.total ~= total then
        self.partials[id] = nil
        return false, "inconsistent chunk count"
    end
    if not p.parts[seq] then
        p.received = p.received + 1
        p.bytes = p.bytes + #data
    else
        p.bytes = p.bytes - #p.parts[seq] + #data   -- duplicate chunk: last one wins, and its size counts
    end
    p.parts[seq] = data
    if p.bytes > Protocol.MAX_INBOUND then
        self.partials[id] = nil
        return false, "message too large"
    end
    if p.received < p.total then return nil end
    self.partials[id] = nil
    local full = table.concat(p.parts, "", 1, p.total)
    local msg, err = Json.Decode(full)
    if type(msg) ~= "table" or type(msg.op) ~= "string" then
        return false, err or "missing op"
    end
    return msg
end

-- Outbound queue with pacing that stays below AzerothCore's addon flood protection
-- (ChatFlood.AddonMessageCount / AddonMessageDelay) and the module's own rate limit.
local Sender = {}
Sender.__index = Sender

function Protocol.NewSender(sendFunc)
    return setmetatable({ queue = {}, send = sendFunc, nextId = 1, acc = Sender.BURST }, Sender)
end

function Sender:Queue(msg)
    local id = self.nextId
    self.nextId = self.nextId + 1
    if self.nextId > 2000000 then self.nextId = 1 end
    for _, c in ipairs(Protocol.Encode(msg, id)) do
        self.queue[#self.queue + 1] = c
    end
    return id
end

-- Token bucket that stays well below the server's limit (mod-true-companion: 20 chunks/s, burst 80, plus 2 per
-- complete request), so long transfers (imports of many memories) never run into "Too many requests".
Sender.RATE = 10          -- chunks per second, sustained
Sender.BURST = 30         -- chunks that may go out at once after a quiet moment

function Sender:Update(elapsed)
    self.acc = math.min(Sender.BURST, self.acc + elapsed * Sender.RATE)
    while self.acc >= 1 and #self.queue > 0 do
        self.acc = self.acc - 1
        self.send(table.remove(self.queue, 1))
    end
end

function Sender:Pending()
    return #self.queue
end
