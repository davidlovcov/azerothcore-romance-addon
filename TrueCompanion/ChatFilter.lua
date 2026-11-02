--[[
  TrueCompanion - hides Playerbots' command feedback from your AI companions in the chat window.

  Playerbots answers commands with short lines ("Following", "attack rti target: useless", quest
  notices). Next to the companion's own reply they clutter the chat. The server sends every AI reply
  to the addon before the visible chat line, so a line from an active companion is:
    * the companion's own words      -> shown as usual
    * an answer you asked Playerbots
      for (a plain command)          -> shown (the server announces those with bot_feedback)
    * anything else                  -> hidden from the chat window, kept as a gray line in the Chat tab
  Only works with a server that announces the "botFeedback" feature; other servers see no change.
  Licensed under the GNU GPL v2 or later.
]]

local TC = _G.TrueCompanion

local F = {
    expected = {},   -- lower-case name -> { { text = normalized reply, t = GetTime() }, ... }
    allow = {},      -- lower-case name -> GetTime() until which Playerbots' answers are shown
    seen = {},       -- line id -> true (every chat frame runs the filter for the same line)
    seenCount = 0,
}
TC.ChatFilter = F

F.EXPECT_SECONDS = 30
F.ALLOW_SECONDS = 6

F.EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_SAY" }

local function normalize(s)
    s = tostring(s or ""):lower()
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
    s = s:gsub("^ ", ""):gsub(" $", "")
    return s
end
F.Normalize = normalize

local function baseName(author)
    return (tostring(author or ""):gsub("%-.*$", "")):lower()
end

function F:Enabled()
    local feat = TC.state.hello and TC.state.hello.features
    return feat and feat.botFeedback and TC.db and TC.db.hideBotFeedback ~= false
end

-- Active companion with that chat name, or nil.
function F:Companion(author)
    local n = baseName(author)
    if n == "" then return nil end
    for _, c in ipairs(TC.state.chars or {}) do
        if c.active and c.name and c.name:lower() == n then return c end
    end
end

function F:NameOf(guid)
    local c = TC:FindChar(guid)
    return c and c.name and c.name:lower()
end

-- The server says: this reply is coming as a chat line.
function F:Expect(guid, text)
    local n = self:NameOf(guid)
    if not n then return end
    local list = self.expected[n] or {}
    local now = GetTime()
    for i = #list, 1, -1 do
        if now - list[i].t > self.EXPECT_SECONDS then table.remove(list, i) end
    end
    table.insert(list, { text = normalize(text), t = now })
    while #list > 10 do table.remove(list, 1) end
    self.expected[n] = list
end

-- The server says: this line went to Playerbots without an AI reply, so its answer is wanted.
function F:Allow(name)
    if name and name ~= "" then self.allow[baseName(name)] = GetTime() + self.ALLOW_SECONDS end
end

function F:IsExpected(name, msg)
    local list = self.expected[name]
    if not list then return false end
    local text = normalize(msg)
    if text == "" then return false end
    local now = GetTime()
    for _, e in ipairs(list) do
        -- long replies arrive in several chat lines: each line is a piece of the reply
        if now - e.t <= self.EXPECT_SECONDS and e.text:find(text, 1, true) then return true end
    end
    return false
end

-- true = hide the line from the chat window.
function F:ShouldHide(msg, author)
    if not self:Enabled() then return false end
    local c = self:Companion(author)
    if not c then return false end
    local n = c.name:lower()
    if self:IsExpected(n, msg) then return false end
    if (self.allow[n] or 0) > GetTime() then return false end
    return true, c
end

function F:Filter(event, msg, author, ...)
    local hide, c = self:ShouldHide(msg, author)
    if not hide then return false end
    local lineId = select(9, ...)
    local key = lineId and ("id:" .. tostring(lineId)) or ("t:" .. tostring(author) .. ":" .. tostring(msg) .. ":" .. math.floor(GetTime()))
    if not self.seen[key] then
        self.seen[key] = true
        self.seenCount = self.seenCount + 1
        if self.seenCount > 200 then self.seen, self.seenCount = { [key] = true }, 1 end
        TC:AddChatLine(tonumber(c.guid), "system", msg, time())
    end
    return true
end

if ChatFrame_AddMessageEventFilter then
    for _, ev in ipairs(F.EVENTS) do
        ChatFrame_AddMessageEventFilter(ev, function(_, event, ...) return F:Filter(event, ...) end)
    end
end
