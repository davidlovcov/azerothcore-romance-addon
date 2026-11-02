--[[
  AzerothRomance - Quests tab: the quests of the whole group (you and your companions) and the quests
  available around, in one place.

  - Order: the order the leading companion does them on "lead the way". Move with Up / Down, then
    "Apply order" (she switches right away if she is leading). "Reset order" lets her choose again.
  - Lead: the selected companion leads there now (a finished quest: to turn it in).
  - Ignore: never picked up and never led to. Kept per character in the addon and sent to the server.
  - Abandon: drops the quest for every companion (not for you). Click twice to confirm.
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local QUEST_ROWS, AVAIL_ROWS = 11, 4
local REFRESH_SECONDS = 10

local Q = { quests = {}, available = {}, changed = false, page = 1, availPage = 1, levelCap = 0, companions = 0 }
AR.GroupQuests = Q

-- ---------------------------------------------------------------- ignored quests (per character)

function Q:Ignored()
    AzerothRomanceDB.ignoredQuests = AzerothRomanceDB.ignoredQuests or {}
    local key = AR:CharKey()
    AzerothRomanceDB.ignoredQuests[key] = AzerothRomanceDB.ignoredQuests[key] or {}
    return AzerothRomanceDB.ignoredQuests[key]   -- [questId] = title
end

function Q:SendIgnored()
    local ids = {}
    for id in pairs(self:Ignored()) do ids[#ids + 1] = tonumber(id) end
    table.sort(ids)
    AR:Request("set_ignored_quests", { quests = ids })
end

function Q:ToggleIgnore(id, title)
    local list = self:Ignored()
    if list[id] then list[id] = nil else list[id] = title or "?" end
    self:SendIgnored()
end

AR:On("HELLO", function() Q:SendIgnored() end)

-- ---------------------------------------------------------------- data

function Q:Load(data)
    self.quests = {}
    for _, q in ipairs(data.quests or {}) do self.quests[#self.quests + 1] = q end
    self.available = data.available or {}
    self.levelCap = tonumber(data.levelCap) or 0
    self.companions = tonumber(data.companions) or 0
    self.changed = false
end

function Q:Request()
    AR:Request("get_group_quests", {}, function(msg)
        if msg.op == "group_quests" then
            Q:Load(msg)
            if Q.frame and Q.frame:IsShown() then Q.frame:Render() end
        end
    end)
end

function Q:Move(i, delta)
    local j = i + delta
    if j < 1 or j > #self.quests then return end
    self.quests[i], self.quests[j] = self.quests[j], self.quests[i]
    self.changed = true
end

function Q:Apply()
    local ids = {}
    for _, q in ipairs(self.quests) do ids[#ids + 1] = q.id end
    self.changed = false
    AR:Request("set_group_quest_order", { quests = ids, apply = true }, function() Q:Request() end)
end

function Q:ResetOrder()
    self.changed = false
    AR:Request("set_group_quest_order", { quests = {}, apply = false }, function() Q:Request() end)
end

local function whoText(q)
    local parts = {}
    for _, w in ipairs(q.who or {}) do
        local color = w.done and "60ff60" or "aaaaaa"
        parts[#parts + 1] = ("|cff%s%s%s|r"):format(color, w.player and "you" or (w.name or "?"), w.done and " (done)" or "")
    end
    return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------- UI

local function build(f)
    Q.frame = f
    local status = W.Label(f, "", 11, W.MUTED)
    status:SetPoint("BOTTOMLEFT", 2, 10)
    status:SetWidth(430)
    local function say(text, bad) status:SetText(bad and ("|cffff6060" .. text .. "|r") or text) end
    f.say = say

    -- the group's quests
    local top = W.Panel(f, 756, 290, 0.35)
    top:SetPoint("TOPLEFT", 0, 0)
    local h1 = W.Heading(top, "Group quests")
    h1:SetPoint("TOPLEFT", 8, -6)
    local cap = W.Label(top, "", 10, W.MUTED)
    cap:SetPoint("TOPLEFT", 140, -9)
    cap:SetWidth(300)
    f.apply = W.Button(top, "Apply order", 100, 20, function()
        Q:Apply()
        say("Order applied: the leading companion does the first quest that is still needed.")
    end)
    f.apply:SetPoint("TOPRIGHT", -112, -4)
    W.Tooltip(f.apply, "Apply order", "Sends the new order. A companion who is leading right now switches to the new first quest.")
    f.reset = W.Button(top, "Reset order", 100, 20, function()
        Q:ResetOrder()
        say("Order reset: she follows her quest log again.")
    end)
    f.reset:SetPoint("TOPRIGHT", -6, -4)

    f.rows = {}
    for i = 1, QUEST_ROWS do
        local y = -30 - (i - 1) * 23
        local r = {}
        r.text = W.Label(top, "", 11, W.TEXT)
        r.text:SetPoint("TOPLEFT", 10, y - 2)
        r.text:SetWidth(470)
        r.up = W.Button(top, "Up", 30, 20)
        r.up:SetPoint("TOPLEFT", 486, y)
        r.down = W.Button(top, "Down", 42, 20)
        r.down:SetPoint("TOPLEFT", 518, y)
        r.lead = W.Button(top, "Lead", 42, 20)
        r.lead:SetPoint("TOPLEFT", 562, y)
        r.ignore = W.Button(top, "Ignore", 54, 20)
        r.ignore:SetPoint("TOPLEFT", 606, y)
        r.abandon = W.Button(top, "Abandon", 84, 20)
        r.abandon:SetPoint("TOPLEFT", 662, y)
        f.rows[i] = r
    end
    f.prev = W.Button(top, "<", 26, 18, function() Q.page = math.max(1, Q.page - 1) f:Render() end)
    f.prev:SetPoint("BOTTOMRIGHT", -70, 4)
    f.pageText = W.Label(top, "", 10, W.MUTED)
    f.pageText:SetPoint("BOTTOMRIGHT", -36, 8)
    f.next = W.Button(top, ">", 26, 18, function() Q.page = Q.page + 1 f:Render() end)
    f.next:SetPoint("BOTTOMRIGHT", -6, 4)

    -- available around
    local bottom = W.Panel(f, 756, 128, 0.35)
    bottom:SetPoint("TOPLEFT", 0, -296)
    local h2 = W.Heading(bottom, "Available around here")
    h2:SetPoint("TOPLEFT", 8, -6)
    f.arows = {}
    for i = 1, AVAIL_ROWS do
        local y = -28 - (i - 1) * 22
        local r = {}
        r.text = W.Label(bottom, "", 11, W.TEXT)
        r.text:SetPoint("TOPLEFT", 10, y - 2)
        r.text:SetWidth(600)
        r.ignore = W.Button(bottom, "Ignore", 84, 20)
        r.ignore:SetPoint("TOPLEFT", 662, y)
        f.arows[i] = r
    end
    f.aprev = W.Button(bottom, "<", 26, 18, function() Q.availPage = math.max(1, Q.availPage - 1) f:Render() end)
    f.aprev:SetPoint("BOTTOMRIGHT", -70, 4)
    f.apageText = W.Label(bottom, "", 10, W.MUTED)
    f.apageText:SetPoint("BOTTOMRIGHT", -36, 8)
    f.anext = W.Button(bottom, ">", 26, 18, function() Q.availPage = Q.availPage + 1 f:Render() end)
    f.anext:SetPoint("BOTTOMRIGHT", -6, 4)

    local refresh = W.Button(f, "Refresh", 90, 22, function() Q:Request() end)
    refresh:SetPoint("BOTTOMRIGHT", -4, 6)

    local armed = {}   -- quest id -> GetTime() of the first Abandon click

    function f:Render()
        local ignored = Q:Ignored()
        cap:SetText(Q.levelCap > 0 and ("Quests up to level %d are picked up automatically."):format(Q.levelCap) or
            (Q.companions == 0 and "Call a companion to see the group's quests." or ""))
        local pages = math.max(1, math.ceil(#Q.quests / QUEST_ROWS))
        Q.page = math.min(Q.page, pages)
        self.pageText:SetText(("%d/%d"):format(Q.page, pages))
        if Q.changed then self.apply:Enable() else self.apply:Disable() end
        for i, r in ipairs(self.rows) do
            local n = (Q.page - 1) * QUEST_ROWS + i
            local q = Q.quests[n]
            local widgets = { r.text, r.up, r.down, r.lead, r.ignore, r.abandon }
            if not q then
                for _, w in ipairs(widgets) do w:Hide() end
            else
                for _, w in ipairs(widgets) do w:Show() end
                local isIgnored = ignored[q.id] ~= nil
                r.text:SetText(("%d. |cffffd100[%d]|r %s%s  %s"):format(n, q.level or 0, isIgnored and "|cff888888" or "", (q.title or "?") ..
                    (isIgnored and " (ignored)|r" or ""), whoText(q)))
                r.up:SetScript("OnClick", function() Q:Move(n, -1) f:Render() end)
                r.down:SetScript("OnClick", function() Q:Move(n, 1) f:Render() end)
                if n == 1 then r.up:Disable() else r.up:Enable() end
                if n == #Q.quests then r.down:Disable() else r.down:Enable() end
                r.lead:SetScript("OnClick", function()
                    local g = AR.state.selected
                    if not g then return say("Select the companion who should lead on the Companion tab.", true) end
                    AR.state.typing[g] = true
                    AR:Request("chat", { guid = g, text = "lead me to " .. (q.title or "") })
                    say("Asked her to lead to \"" .. (q.title or "") .. "\".")
                end)
                r.ignore:SetText(isIgnored and "Unignore" or "Ignore")
                r.ignore:SetScript("OnClick", function()
                    Q:ToggleIgnore(q.id, q.title)
                    f:Render()
                end)
                local hasCompanion = false
                for _, w in ipairs(q.who or {}) do if not w.player then hasCompanion = true end end
                if hasCompanion then r.abandon:Enable() else r.abandon:Disable() end
                local sure = armed[q.id] and GetTime() - armed[q.id] < 4
                r.abandon:SetText(sure and "Sure?" or "Abandon")
                r.abandon:SetScript("OnClick", function()
                    if not (armed[q.id] and GetTime() - armed[q.id] < 4) then
                        armed[q.id] = GetTime()
                        say("Click Abandon again to drop \"" .. (q.title or "") .. "\" for all companions.")
                        return f:Render()
                    end
                    armed[q.id] = nil
                    AR:Request("abandon_quest", { quest = q.id }, function(msg)
                        say(("\"%s\" abandoned by %d companion(s)."):format(q.title or "", tonumber(msg.abandoned) or 0))
                        Q:Request()
                    end)
                end)
            end
        end

        local apages = math.max(1, math.ceil(#Q.available / AVAIL_ROWS))
        Q.availPage = math.min(Q.availPage, apages)
        self.apageText:SetText(("%d/%d"):format(Q.availPage, apages))
        for i, r in ipairs(self.arows) do
            local a = Q.available[(Q.availPage - 1) * AVAIL_ROWS + i]
            if not a then
                r.text:Hide()
                r.ignore:Hide()
            else
                r.text:Show()
                r.ignore:Show()
                local isIgnored = ignored[a.id] ~= nil
                r.text:SetText(("|cffffd100[%d]|r %s%s%s%s  |cffaaaaaa%s, %d yd %s|r"):format(a.level or 0, isIgnored and "|cff888888" or "",
                    a.title or "?", a.classQuest and " |cff9ad2ff(class)|r" or "", a.tooHigh and " |cffff8040(too high)|r" or "",
                    a.giver or "?", a.distance or 0, a.direction or ""))
                r.ignore:SetText(isIgnored and "Unignore" or "Ignore")
                r.ignore:SetScript("OnClick", function()
                    Q:ToggleIgnore(a.id, a.title)
                    f:Render()
                end)
            end
        end
    end

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= REFRESH_SECONDS and not Q.changed then   -- don't overwrite an order that isn't applied yet
            elapsed = 0
            Q:Request()
        end
    end)
    f.OnShowTab = function()
        elapsed = 0
        f:Render()
        Q:Request()
    end
end

UI:RegisterTab("quests", "Quests", build)
