--[[
  TrueCompanion - Quests tab: the quests of the whole group (you and your companions) and the quests
  available around, in one place.

  The everyday view shows Lead / Share / Take; "Edit list" shows the order buttons, Ignore and Abandon.
  - Order: the order the leading companion does them on "lead the way". Move with Up / Down, then
    "Apply order" (she switches right away if she is leading). "Reset order" lets her choose again.
  - Lead: the selected companion leads there now (a finished quest: to turn it in).
  - Ignore: never picked up and never led to. Kept per character in the addon and sent to the server.
  - Share: every companion who lacks the quest (and can take it) gets it; you get it shared by one who has it.
  - Abandon: drops the quest for every companion (not for you). Click twice to confirm.
  - Available around here: who could take each quest; "Take" makes them take it (walking there with the
    leading or selected companion if the quest giver is not close).
]]

local TC = _G.TrueCompanion
local W = TC.W
local UI = TC.UI

local QUEST_ROWS, AVAIL_ROWS = 8, 4
local REFRESH_SECONDS = 10

local Q = { quests = {}, available = {}, changed = false, page = 1, availPage = 1, levelCap = 0, companions = 0 }
TC.GroupQuests = Q

-- ---------------------------------------------------------------- ignored quests (per character)

function Q:Ignored()
    TrueCompanionDB.ignoredQuests = TrueCompanionDB.ignoredQuests or {}
    local key = TC:CharKey()
    TrueCompanionDB.ignoredQuests[key] = TrueCompanionDB.ignoredQuests[key] or {}
    return TrueCompanionDB.ignoredQuests[key]   -- [questId] = title
end

function Q:SendIgnored()
    local ids = {}
    for id in pairs(self:Ignored()) do ids[#ids + 1] = tonumber(id) end
    table.sort(ids)
    TC:Request("set_ignored_quests", { quests = ids })
end

function Q:ToggleIgnore(id, title)
    local list = self:Ignored()
    if list[id] then list[id] = nil else list[id] = title or "?" end
    self:SendIgnored()
end

TC:On("HELLO", function() Q:SendIgnored() end)

-- ---------------------------------------------------------------- data

-- Requests are numbered; `orderAt` is the number of the last request sent before the order changed here (a move,
-- Apply or Reset). An answer to an older request carries an out-of-date order: only its quest status is taken.
Q.seq, Q.orderAt = 0, 0

-- Takes the server's quest data but keeps the local order (unsaved edits, or an Apply still on its way):
-- quests keep their place with fresh status, new ones go to the end, finished or dropped ones disappear.
function Q:Merge(data)
    local fresh = {}
    for _, q in ipairs(data.quests or {}) do fresh[q.id] = q end
    local merged, seen = {}, {}
    for _, q in ipairs(self.quests) do
        if fresh[q.id] then
            merged[#merged + 1] = fresh[q.id]
            seen[q.id] = true
        end
    end
    for _, q in ipairs(data.quests or {}) do
        if not seen[q.id] then merged[#merged + 1] = q end
    end
    self.quests = merged
end

function Q:Load(data, seq)
    local stale = seq and seq <= self.orderAt
    if self.changed or stale then
        self:Merge(data)
    else
        self.quests = {}
        for _, q in ipairs(data.quests or {}) do self.quests[#self.quests + 1] = q end
    end
    self.available = data.available or {}
    self.levelCap = tonumber(data.levelCap) or 0
    self.companions = tonumber(data.companions) or 0
    if data.lead then
        TC.state.lead = data.lead
        TC:Fire("LEAD_CHANGED")
    end
end

function Q:Request()
    self.seq = self.seq + 1
    local mine = self.seq
    TC:Request("get_group_quests", {}, function(msg)
        if msg.op == "group_quests" then
            Q:Load(msg, mine)
            if Q.frame and Q.frame:IsShown() then Q.frame:Render() end
        end
    end)
end

function Q:Move(i, delta)
    local j = i + delta
    if j < 1 or j > #self.quests then return end
    self.quests[i], self.quests[j] = self.quests[j], self.quests[i]
    self.changed = true
    self.orderAt = self.seq   -- answers to requests already sent must not undo this
end

-- The local order only becomes "saved" when the server confirms it: a rejected or unanswered request keeps
-- `changed` set, so the next refresh merges instead of silently throwing the edits away. The message goes
-- to the tab's status line, which is built later, hence the frame lookup.
function Q:OrderAck(sentAt, okText)
    if self.seq == sentAt then self.changed = false end
    if self.frame and self.frame.say then self.frame.say(okText) end
    Q:Request()
end

function Q:OrderFailed(msg)
    if self.frame and self.frame.say then self.frame.say(TC:AckText(msg), true) end
end

function Q:Apply()
    local ids = {}
    for _, q in ipairs(self.quests) do ids[#ids + 1] = q.id end
    local sentAt = self.seq
    self.orderAt = self.seq   -- answers already on their way must not undo this
    TC:Request("set_group_quest_order", { quests = ids, apply = true }, function(msg)
        if msg.op == "ack" and msg.ok then
            Q:OrderAck(sentAt, "Order applied: the leading companion does the first quest that is still needed.")
        else
            Q:OrderFailed(msg)
        end
    end)
end

function Q:ResetOrder()
    -- nothing to lose here: "follow your quest log again" discards the local order either way
    self.changed = false
    self.orderAt = self.seq
    TC:Request("set_group_quest_order", { quests = {}, apply = false }, function(msg)
        if msg.op == "ack" and msg.ok then
            if self.frame and self.frame.say then self.frame.say("Order reset: she follows her quest log again.") end
            Q:Request()
        else
            Q:OrderFailed(msg)
        end
    end)
end

local function names(list)
    local out = {}
    for _, n in ipairs(list or {}) do out[#out + 1] = tostring(n) end
    return out
end
Q.Names = names

-- a server module older than this addon sends no share/take data: say so instead of "nobody can take it"
local OLD_SERVER = "Your server module is older than this addon: rebuild the server module from the same version."
function Q:ServerTooOld(row) return row.takers == nil and row.sharable == nil end

-- Share is useful when the quest can be shared and someone in the group still lacks it
function Q:CanShare(q)
    return q.sharable and #names(q.missing) > 0 or false
end

-- the companions who can take an available quest, plus "you" if you can too
function Q:Takers(a)
    local list = names(a.takers)
    if a.you then list[#list + 1] = "you" end
    return list
end

-- Take: the companions take it (an ignored quest is unignored: you chose it)
function Q:Take(a, done)
    if self:Ignored()[a.id] then self:ToggleIgnore(a.id, a.title) end
    TC:Request("take_quest", { quest = a.id, guid = TC.state.selected }, function(msg)
        if done then done(msg.result or "") end
        Q:Request()
    end)
end

function Q:Share(q, done)
    TC:Request("share_quest", { quest = q.id }, function(msg)
        if done then done(msg.result or "") end
        Q:Request()
    end)
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
    status:SetWidth(640)
    status:SetHeight(14)
    local function say(text, bad) status:SetText(bad and ("|cffff6060" .. text .. "|r") or text) end
    f.say, f.status = say, status

    -- the group's quests
    local top = W.Panel(f, 756, 250, 0.35)
    top:SetPoint("TOPLEFT", 0, 0)
    f.topPanel = top
    local h1 = W.Heading(top, "Group quests")
    h1:SetPoint("TOPLEFT", 8, -6)
    local cap = W.Label(top, "", 10, W.MUTED)
    cap:SetPoint("TOPLEFT", 140, -9)
    cap:SetWidth(280)
    f.apply = W.Button(top, "Apply order", 100, 20, function() Q:Apply() end)
    f.apply:SetPoint("TOPRIGHT", -218, -4)
    W.Tooltip(f.apply, "Apply order", "Sends the new order. A companion who is leading right now switches to the new first quest.")
    f.reset = W.Button(top, "Reset order", 100, 20, function() Q:ResetOrder() end)
    f.reset:SetPoint("TOPRIGHT", -112, -4)
    -- the everyday view shows Lead / Share / Take; "Edit list" adds the order, Ignore and Abandon
    f.edit = W.Button(top, "Edit list", 100, 20, function()
        if Q.editing and Q.changed then
            return say("Your new order isn't applied yet: click \"Apply order\" (or \"Reset order\").", true)
        end
        Q.editing = not Q.editing
        f:Render()
    end)
    f.edit:SetPoint("TOPRIGHT", -6, -4)
    W.Tooltip(f.edit, "Edit list", "Change the order she does the quests in, ignore quests or abandon them for every companion.")

    f.rows = {}
    for i = 1, QUEST_ROWS do
        local y = -30 - (i - 1) * 23
        local r = {}
        r.text = W.Label(top, "", 11, W.TEXT)
        r.text:SetPoint("TOPLEFT", 10, y - 3)
        r.text:SetWidth(400)
        r.text:SetHeight(14)   -- one line: a long one is cut, not wrapped into the next row
        r.up = W.Button(top, "Up", 30, 20)
        r.up:SetPoint("TOPLEFT", 500, y)
        r.down = W.Button(top, "Down", 46, 20)
        r.down:SetPoint("TOPLEFT", 534, y)
        r.ignore = W.Button(top, "Ignore", 58, 20)
        r.ignore:SetPoint("TOPLEFT", 586, y)
        r.abandon = W.Button(top, "Abandon", 64, 20)
        r.abandon:SetPoint("TOPLEFT", 646, y)
        -- everyday buttons share the right edge with the edit buttons; only one set is shown
        r.lead = W.Button(top, "Lead", 54, 20)
        r.lead:SetPoint("TOPLEFT", 586, y)
        r.share = W.Button(top, "Share", 64, 20)
        r.share:SetPoint("TOPLEFT", 646, y)
        f.rows[i] = r
    end
    f.prev = W.Button(top, "<", 26, 18, function() Q.page = math.max(1, Q.page - 1) f:Render() end)
    f.prev:SetPoint("BOTTOMRIGHT", -70, 4)
    f.pageText = W.Label(top, "", 10, W.MUTED)
    f.pageText:SetPoint("BOTTOMRIGHT", -36, 8)
    f.next = W.Button(top, ">", 26, 18, function() Q.page = Q.page + 1 f:Render() end)
    f.next:SetPoint("BOTTOMRIGHT", -6, 4)

    -- available around
    local bottom = W.Panel(f, 756, 152, 0.35)
    bottom:SetPoint("TOPLEFT", 0, -256)
    f.bottomPanel = bottom
    local h2 = W.Heading(bottom, "Available around here")
    h2:SetPoint("TOPLEFT", 8, -6)
    f.arows = {}
    for i = 1, AVAIL_ROWS do
        local y = -28 - (i - 1) * 24
        local r = {}
        r.text = W.Label(bottom, "", 11, W.TEXT)
        r.text:SetPoint("TOPLEFT", 10, y - 3)
        r.text:SetWidth(570)
        r.text:SetHeight(14)
        r.take = W.Button(bottom, "Take", 54, 20)
        r.take:SetPoint("TOPLEFT", 586, y)
        r.ignore = W.Button(bottom, "Ignore", 64, 20)
        r.ignore:SetPoint("TOPLEFT", 646, y)
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
    f.refresh = refresh

    local armed = {}   -- quest id -> GetTime() of the first Abandon click

    function f:Render()
        local ignored = Q:Ignored()
        cap:SetText(Q.levelCap > 0 and ("Quests up to level %d are picked up automatically."):format(Q.levelCap) or
            (Q.companions == 0 and "Call a companion to see the group's quests." or ""))
        local pages = math.max(1, math.ceil(#Q.quests / QUEST_ROWS))
        Q.page = math.min(Q.page, pages)
        self.pageText:SetText(("%d/%d"):format(Q.page, pages))
        if Q.changed then self.apply:Enable() else self.apply:Disable() end
        UI.SetShown(self.apply, Q.editing)
        UI.SetShown(self.reset, Q.editing)
        self.edit:SetText(Q.editing and "Done" or "Edit list")
        for i, r in ipairs(self.rows) do
            local n = (Q.page - 1) * QUEST_ROWS + i
            local q = Q.quests[n]
            local widgets = { r.text, r.up, r.down, r.lead, r.share, r.ignore, r.abandon }
            if not q then
                for _, w in ipairs(widgets) do w:Hide() end
            else
                r.text:Show()
                for _, w in ipairs({ r.up, r.down, r.ignore, r.abandon }) do UI.SetShown(w, Q.editing) end
                for _, w in ipairs({ r.lead, r.share }) do UI.SetShown(w, not Q.editing) end
                r.text:SetWidth(Q.editing and 484 or 570)
                local isIgnored = ignored[q.id] ~= nil
                r.text:SetText(("%d. |cffffd100[%d]|r %s%s  %s"):format(n, q.level or 0, isIgnored and "|cff888888" or "", (q.title or "?") ..
                    (isIgnored and " (ignored)|r" or ""), whoText(q)))
                r.up:SetScript("OnClick", function() Q:Move(n, -1) f:Render() end)
                r.down:SetScript("OnClick", function() Q:Move(n, 1) f:Render() end)
                if n == 1 then r.up:Disable() else r.up:Enable() end
                if n == #Q.quests then r.down:Disable() else r.down:Enable() end
                r.lead:SetScript("OnClick", function()
                    local g = TC.state.selected
                    if not g then return say("Select the companion who should lead on the Companion tab.", true) end
                    TC:SetTyping(g, true)
                    TC:Request("chat", { guid = g, text = "lead me to " .. (q.title or "") })
                    say("Asked her to lead to \"" .. (q.title or "") .. "\".")
                end)
                local missing = names(q.missing)
                if Q:CanShare(q) then r.share:Enable() else r.share:Disable() end
                W.Tooltip(r.share, "Share", Q:ServerTooOld(q) and OLD_SERVER or not q.sharable and "This quest can't be shared." or
                    (#missing == 0 and "Everyone in the group has it." or
                     ("Still without it: %s. Companions who can take it get it; you get it shared."):format(table.concat(missing, ", "))))
                r.share:SetScript("OnClick", function()
                    say("Sharing \"" .. (q.title or "") .. "\"...")
                    Q:Share(q, function(result) say(result ~= "" and result or "Shared.") end)
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
                    TC:Request("abandon_quest", { quest = q.id }, function(msg)
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
                r.take:Hide()
                r.ignore:Hide()
            else
                r.text:Show()
                r.take:Show()
                UI.SetShown(r.ignore, Q.editing)
                local isIgnored = ignored[a.id] ~= nil
                local takers = Q:Takers(a)
                r.text:SetText(("|cffffd100[%d]|r %s%s%s%s  |cffaaaaaa%s, %d yd %s|r  %s"):format(a.level or 0, isIgnored and "|cff888888" or "",
                    a.title or "?", a.classQuest and " |cff9ad2ff(class)|r" or "", a.tooHigh and " |cffff8040(too high)|r" or "",
                    a.giver or "?", a.distance or 0, a.direction or "",
                    Q:ServerTooOld(a) and "|cffff8040server too old for Take|r" or
                    #takers > 0 and ("|cff60ff60" .. table.concat(takers, ", ") .. "|r") or "|cff888888nobody can take it|r"))
                local companionsCan = #names(a.takers) > 0
                if companionsCan then r.take:Enable() else r.take:Disable() end
                W.Tooltip(r.take, "Take", Q:ServerTooOld(a) and OLD_SERVER or companionsCan
                    and ("%s take it%s. If the quest giver is not close, the leading (or selected) companion leads you all there.")
                        :format(table.concat(names(a.takers), ", "), a.you and "; you get it shared" or "")
                    or (a.you and "None of your companions can take it; you can take it yourself." or "None of your companions can take it."))
                r.take:SetScript("OnClick", function()
                    say("Taking \"" .. (a.title or "") .. "\"...")
                    Q:Take(a, function(result) say(result ~= "" and result or "Done.") end)
                end)
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
