--[[
  TrueCompanion - Memory viewer: inspect, filter, edit, pin, delete, add, clear,
  export/import. Every change goes to the authoritative server storage.
]]

local TC = _G.TrueCompanion
local W = TC.W
local UI = TC.UI

local MV = {}
TC.MemoryViewer = MV

local function companionName(guid)
    local c = TC:FindChar(guid)
    return c and c.name or tostring(guid)
end

local PAGE = 10
local KINDS = {
    { value = "", text = "All memories" }, { value = "fact", text = "Facts" }, { value = "preference", text = "Preferences" },
    { value = "episode", text = "Shared moments" }, { value = "relationship", text = "Relationship" },
    { value = "promise", text = "Promises" }, { value = "gift", text = "Gifts" }, { value = "summary", text = "Conversation summaries" },
}
local SOURCE_LABEL = {
    observed = "|cff60ff60seen in game|r", player_stated = "|cffffd76byou said|r", model_summary = "|cffaaaaffsummary|r",
    interpretation = "|cffaaaaaaher impression|r", user_edited = "|cff60d0ffedited by you|r", profile = "|cffffaaddbackstory|r",
}

StaticPopupDialogs["TRUECOMPANION_EDIT_MEMORY"] = {
    text = "Edit memory:", button1 = SAVE, button2 = CANCEL, hasEditBox = 1, maxLetters = 300, hasWideEditBox = 1,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self, data)
        local eb = self.wideEditBox or self.editBox
        eb:SetText(data and data.text or "")
        eb:SetFocus()
    end,
    OnAccept = function(self, data)
        local eb = self.wideEditBox or self.editBox
        if data and data.onAccept then data.onAccept(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local data = parent.data
        if data and data.onAccept then data.onAccept(self:GetText()) end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["TRUECOMPANION_CONFIRM"] = {
    text = "%s", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data) if data then data() end end,
}

StaticPopupDialogs["TRUECOMPANION_RESET"] = {
    text = "This erases |cffff6060everything|r about %s: personality, relationship, memories and chat history.\n\nType RESET to confirm.",
    button1 = OKAY, button2 = CANCEL, hasEditBox = 1, maxLetters = 8, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data)
        local eb = self.editBox
        if eb:GetText() == "RESET" and data then data() end
    end,
}

local function build()
    local f = W.Panel(UIParent, 640, 500, 0.97)
    _G.TrueCompanionMemoryFrame = f
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER", 40, -20)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "TrueCompanionMemoryFrame")
    local title = W.Label(f, "Memories", 15, W.GOLD, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    local who = W.Label(f, "", 11, W.MUTED)
    who:SetPoint("LEFT", title, "RIGHT", 10, -1)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local kind = W.Dropdown(f, "Show", 200, KINDS, function() MV.offset = 0 MV:Load() end)
    kind:SetPoint("TOPLEFT", 4, -34)
    kind:SetValue("")
    local search = W.Edit(f, "Search", 180, 40)
    search:SetPoint("TOPLEFT", 216, -34)
    search.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() MV.offset = 0 MV:Load() end)
    local go = W.Button(f, "Filter", 60, 20, function() MV.offset = 0 MV:Load() end)
    go:SetPoint("TOPLEFT", 404, -48)
    local total = W.Label(f, "", 11, W.MUTED)
    total:SetPoint("TOPRIGHT", -16, -52)

    local rows = {}
    for i = 1, PAGE do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(32)
        r:SetPoint("TOPLEFT", 12, -84 - (i - 1) * 34)
        r:SetPoint("TOPRIGHT", -12, -84 - (i - 1) * 34)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.06)
        r.text = W.Label(r, "", 11, W.TEXT)
        r.text:SetPoint("TOPLEFT", 6, -3)
        r.text:SetWidth(440)
        r.text:SetHeight(14)
        r.meta = W.Label(r, "", 9, W.MUTED)
        r.meta:SetPoint("BOTTOMLEFT", 6, 3)
        r.edit = W.Button(r, "Edit", 44, 18)
        r.edit:SetPoint("RIGHT", -102, 0)
        r.pin = W.Button(r, "Pin", 44, 18)
        r.pin:SetPoint("RIGHT", -54, 0)
        r.del = W.Button(r, "Delete", 50, 18)
        r.del:SetPoint("RIGHT", -2, 0)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.mem then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.mem.text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end

    local prev = W.Button(f, "< Newer", 80, 22, function() MV.offset = math.max(0, MV.offset - PAGE) MV:Load() end)
    prev:SetPoint("BOTTOMLEFT", 12, 44)
    local nextB = W.Button(f, "Older >", 80, 22, function() MV.offset = MV.offset + PAGE MV:Load() end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 6, 0)

    -- Every operation is bound to the companion it was opened for: switching the viewer to another companion
    -- before confirming never redirects it.
    local add = W.Button(f, "Add memory", 100, 22, function()
        local guid = MV.guid
        if not guid then return end
        local k = kind:GetValue()
        local popup = StaticPopup_Show("TRUECOMPANION_EDIT_MEMORY")
        if popup then
            popup.data = { text = "", guid = guid, onAccept = function(text)
                TC:Request("add_memory", { guid = guid, kind = (k ~= "" and k ~= "summary") and k or "fact",
                    text = text, importance = 60 }, function() MV:Reload(guid) end)
            end }
        end
    end)
    add:SetPoint("LEFT", nextB, "RIGHT", 20, 0)
    local clear = W.Button(f, "Clear shown kind", 120, 22, function()
        local guid = MV.guid
        if not guid then return end
        local k = kind:GetValue()
        local label = k == "" and "ALL memories" or ("all memories of this kind (" .. k .. ")")
        local popup = StaticPopup_Show("TRUECOMPANION_CONFIRM", "Delete " .. label .. " of " .. companionName(guid) .. "?")
        if popup then
            popup.guid = guid
            popup.data = function()
                TC:Request("clear_memories", { guid = guid, kind = k ~= "" and k or nil }, function() MV:Reload(guid, true) end)
            end
        end
    end)
    clear:SetPoint("LEFT", add, "RIGHT", 6, 0)
    MV.addButton, MV.clearButton = add, clear
    local reset = W.Button(f, "Full reset...", 100, 22, function()
        local guid = MV.guid
        if not guid then return end
        local popup = StaticPopup_Show("TRUECOMPANION_RESET", companionName(guid))
        if popup then
            popup.guid = guid
            popup.data = function()
                TC:Request("reset_companion", { guid = guid, confirm = "RESET" }, function() MV:Reload(guid, true) end)
            end
        end
    end)
    reset:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    MV.resetButton = reset

    -- backup: export / import (the text itself lives in a separate dialog)
    local ioLabel = W.Label(f, "Backup", 11, W.GOLD_DIM)
    ioLabel:SetPoint("BOTTOMLEFT", 14, 15)
    local export = W.Button(f, "Export", 70, 20, function()
        if MV.guid then MV:Export() end
    end)
    export:SetPoint("LEFT", ioLabel, "RIGHT", 8, 0)
    W.Tooltip(export, "Export", "Saves all memories of this companion in the addon, and shows the text so you can copy it.")
    local import = W.Button(f, "Import...", 80, 20, function()
        if MV.guid then MV:ShowTransfer("import") end
    end)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    W.Tooltip(import, "Import", "Adds memories from a saved export or from pasted text to this companion.")
    local ioStatus = W.Label(f, "", 10, W.MUTED)
    ioStatus:SetPoint("LEFT", import, "RIGHT", 10, 0)
    ioStatus:SetWidth(330)
    MV.ioStatus = ioStatus

    MV.frame, MV.rows, MV.kind, MV.search, MV.total, MV.who, MV.prev, MV.next = f, rows, kind, search, total, who, prev, nextB
    -- reload the list at most every 2 seconds, and not in the middle of an import / export
    local reloadAt
    TC:On("MEMORY_CHANGED", function(g)
        if f:IsShown() and g == MV.guid and not reloadAt then reloadAt = GetTime() + 2 end
    end)
    f:HookScript("OnUpdate", function()
        if reloadAt and GetTime() >= reloadAt and not TC.Transfer:Busy() then
            reloadAt = nil
            if f:IsShown() then MV:Load() end
        end
    end)
end

-- ---------------------------------------------------------------- export / import

local MAX_SHOWN = 16000   -- the text box holds this many characters; bigger exports are only kept saved


local function savedExports()
    TrueCompanionDB.exports = TrueCompanionDB.exports or {}
    return TrueCompanionDB.exports
end

-- Dialog that shows an export or takes an import.
local function buildTransfer()
    local d = W.Panel(UIParent, 500, 360, 0.98)
    _G.TrueCompanionTransferFrame = d
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetPoint("CENTER", 0, 20)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "TrueCompanionTransferFrame")
    d.title = W.Label(d, "", 14, W.GOLD, "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", 14, -12)
    local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    d.help = W.Label(d, "", 11, W.TEXT)
    d.help:SetPoint("TOPLEFT", 14, -36)
    d.help:SetWidth(470)
    d.help:SetJustifyV("TOP")
    d.note = W.Label(d, "", 12, W.GOLD_DIM)   -- shown instead of the text box when an export is too large to display
    d.note:SetPoint("TOPLEFT", 14, -112)
    d.note:SetWidth(470)
    d.note:SetJustifyV("TOP")
    d.note:Hide()
    d.saved = W.Dropdown(d, "Saved export", 300, {}, function() d.area:SetValue("") end)
    d.saved:SetPoint("TOPLEFT", 10, -84)
    d.area = W.TextArea(d, "", 472, 170, MAX_SHOWN)
    d.area:SetPoint("TOPLEFT", 14, -132)
    d.status = W.Label(d, "", 11, W.MUTED)
    d.status:SetPoint("BOTTOMLEFT", 14, 16)
    d.status:SetWidth(300)
    d.go = W.Button(d, "Import", 110, 22, function() MV:RunImport() end)
    d.go:SetPoint("BOTTOMRIGHT", -12, 10)
    d.cancel = W.Button(d, "Close", 80, 22, function() d:Hide() end)
    d.cancel:SetPoint("RIGHT", d.go, "LEFT", -6, 0)
    return d
end

function MV:ShowTransfer(mode, text, info, guid)
    local d = self.transfer or buildTransfer()
    self.transfer = d
    d.mode = mode
    d.guid = guid or self.guid   -- the import goes to this companion, even if the viewer switches meanwhile
    local name = companionName(d.guid)
    d.status:SetText("")
    if mode == "export" then
        d.title:SetText("Export of " .. name)
        d.help:SetText("The export is saved in the addon. To import it into a companion, open its Memories and press " ..
            "\"Import...\" - no copying needed.")
        d.saved:Hide()
        d.go:Hide()
        if (text or "") == "" then
            -- too large to show: no text box (nothing to copy or type), just the explanation
            d.area:Hide()
            d.note:SetText(info or "")
            d.note:Show()
            d:Show()
            return
        end
        d.note:Hide()
        d.area:Show()
        d.area:ClearAllPoints()
        d.area:SetPoint("TOPLEFT", 14, -96)
        d.area.caption:SetText((info or "") .. " - press Ctrl+C to copy the text below to somewhere else.")
        d.area:SetValue(text)
        d:Show()
        d.area.edit:SetFocus()
        d.area.edit:HighlightText()
        return
    end
    d.title:SetText("Import into " .. name)
    d.help:SetText("Choose a saved export, or paste an export (Ctrl+V) into the box. Imported memories are added; " ..
        "existing ones stay. Nothing changes unless the whole import arrives.")
    local items = { { value = "", text = "None - use the pasted text" } }
    local names = {}
    for n in pairs(savedExports()) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local e = savedExports()[n]
        items[#items + 1] = { value = n, text = ("%s - %d memories - %s"):format(n, tonumber(e.memories) or 0,
            date("%d.%m. %H:%M", tonumber(e.at) or 0)) }
    end
    d.note:Hide()
    d.area:Show()
    d.saved:SetItems(items)
    local last = TrueCompanionDB.lastExport
    d.saved:SetValue(savedExports()[last or ""] and last or "")
    d.saved:Show()
    d.area:ClearAllPoints()
    d.area:SetPoint("TOPLEFT", 14, -132)
    d.area.caption:SetText("Or paste an export here")
    d.area:SetValue("")
    d.go:SetText("Import")
    d.go:Show()
    d.go:Enable()
    d:Show()
end

function MV:Export()
    local guid = self.guid
    local status = self.ioStatus
    status:SetText("Exporting...")
    TC.Transfer:Export(guid, function(i, n) status:SetText(("Exporting part %d/%d..."):format(i, n)) end,
        function(text, count)
            if not text then
                status:SetText("|cffff6060Export failed: " .. tostring(count) .. "|r")
                return
            end
            local name = companionName(guid)
            savedExports()[name] = { at = time(), memories = count, text = text }
            TrueCompanionDB.lastExport = name
            local size = ("%d memories, %.1f KB"):format(count or 0, #text / 1024)
            status:SetText("|cff60ff60Saved|r (" .. size .. ").")
            if #text <= MAX_SHOWN then
                self:ShowTransfer("export", text, size, guid)
            else
                self:ShowTransfer("export", "", size .. " - too large to show here.\nIt is saved in the addon, and in " ..
                    "WTF/Account/<account>/SavedVariables/TrueCompanion.lua after /reload.", guid)
            end
        end)
end

function MV:RunImport()
    local d = self.transfer
    local guid = d and d.guid
    if not d or not guid or d.mode ~= "import" then return end
    local text, source = d.area:GetValue(), "the pasted text"
    if text == "" then
        local pick = d.saved:GetValue()
        local saved = pick and pick ~= "" and savedExports()[pick]
        if not saved then
            d.status:SetText("|cffff6060Choose a saved export or paste one first.|r")
            return
        end
        text, source = saved.text, "the saved export of " .. pick
    elseif #text >= MAX_SHOWN then
        d.status:SetText("|cffff6060The pasted text was cut off (too long). Use a saved export instead.|r")
        return
    end
    d.go:Disable()
    d.status:SetText("Importing from " .. source .. "...")
    TC.Transfer:Import(guid, text, function(i, n) d.status:SetText(("Importing part %d/%d..."):format(i, n)) end,
        function(ok, result, unknown)
            d.go:Enable()
            if ok then
                d.status:SetText("|cff60ff60Done:|r " .. table.concat(result or {}, ", "))
                self.ioStatus:SetText("|cff60ff60Imported:|r " .. table.concat(result or {}, ", "))
                self:Reload(guid, true)
            elseif unknown then
                -- the server may have applied it and only the answer got lost: look instead of claiming nothing changed
                d.status:SetText("|cffff6060No answer from the server.|r It may or may not have been applied; check the list " ..
                    "before importing again.")
                self:Reload(guid, true)
            else
                d.status:SetText("|cffff6060Import failed, nothing was changed: " .. tostring(result) .. "|r")
            end
        end)
end

function MV:Open(guid)
    guid = guid or TC.state.selected
    if not guid then
        TC:Print("Select a companion first.")
        return
    end
    if not self.frame then build() end
    if self.guid ~= guid then
        self.loadGen = (self.loadGen or 0) + 1   -- whatever is still on its way for the old companion is dropped
        self:Render({ items = {}, total = 0 }, guid)
    end
    self.guid = guid
    self.offset = 0
    local c = TC:FindChar(guid)
    self.who:SetText(c and ("of " .. c.name) or "")
    self.frame:Show()
    self:Load()
end

-- Reloads after an operation on `guid`, but only if the viewer still shows that companion.
function MV:Reload(guid, toFirstPage)
    if guid ~= self.guid then return end
    if toFirstPage then self.offset = 0 end
    self:Load()
end

-- Only the newest request is rendered: a late answer for another companion, filter, search or page is dropped.
function MV:Load()
    if not self.frame or not self.guid then return end
    self.loadGen = (self.loadGen or 0) + 1
    local gen, guid = self.loadGen, self.guid
    local kind = self.kind:GetValue()
    TC:Request("get_memories", { guid = guid, kind = kind ~= "" and kind or nil, search = self.search:GetValue(),
        offset = self.offset or 0, limit = PAGE }, function(msg)
        if msg.op ~= "memories" or gen ~= self.loadGen or guid ~= self.guid then return end
        self:Render(msg, guid)
    end)
end

function MV:Render(msg, guid)
    local items = msg.items or {}
    local n = tonumber(msg.total) or 0
    self.total:SetText(("%d memories"):format(n))
    if (self.offset or 0) > 0 then self.prev:Enable() else self.prev:Disable() end
    if (self.offset or 0) + PAGE < n then self.next:Enable() else self.next:Disable() end
    for i, r in ipairs(self.rows) do
        local m = items[i]
        r.mem = m
        if not m then
            r:Hide()
        else
            r:Show()
            r.text:SetText((m.pinned and "|cffffd100*|r " or "") .. m.text)
            r.meta:SetText(("%s  |  %s  |  importance %d  |  %s"):format(m.kind or "?", SOURCE_LABEL[m.source] or m.source or "?",
                tonumber(m.importance) or 0, date("%d.%m.%Y %H:%M", tonumber(m.createdAt) or 0)))
            r.pin:SetText(m.pinned and "Unpin" or "Pin")
            r.edit:SetScript("OnClick", function()
                local popup = StaticPopup_Show("TRUECOMPANION_EDIT_MEMORY")
                if popup then
                    popup.data = { text = m.text, guid = guid, onAccept = function(text)
                        TC:Request("edit_memory", { guid = guid, id = m.id, text = text }, function() self:Reload(guid) end)
                    end }
                    local eb = popup.wideEditBox or popup.editBox
                    eb:SetText(m.text)
                end
            end)
            r.pin:SetScript("OnClick", function()
                TC:Request("pin_memory", { guid = guid, id = m.id, pinned = not m.pinned }, function() self:Reload(guid) end)
            end)
            r.del:SetScript("OnClick", function()
                TC:Request("delete_memory", { guid = guid, id = m.id }, function() self:Reload(guid) end)
            end)
        end
    end
end
