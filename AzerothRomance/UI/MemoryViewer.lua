--[[
  AzerothRomance - Memory viewer: inspect, filter, edit, pin, delete, add, clear,
  export/import. Every change goes to the authoritative server storage.
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local MV = {}
AR.MemoryViewer = MV

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

StaticPopupDialogs["AZEROTHROMANCE_EDIT_MEMORY"] = {
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

StaticPopupDialogs["AZEROTHROMANCE_CONFIRM"] = {
    text = "%s", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data) if data then data() end end,
}

StaticPopupDialogs["AZEROTHROMANCE_RESET"] = {
    text = "This erases |cffff6060everything|r about this companion: personality, relationship, memories and chat history.\n\nType RESET to confirm.",
    button1 = OKAY, button2 = CANCEL, hasEditBox = 1, maxLetters = 8, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self, data)
        local eb = self.editBox
        if eb:GetText() == "RESET" and data then data() end
    end,
}

local function build()
    local f = W.Panel(UIParent, 640, 500, 0.97)
    _G.AzerothRomanceMemoryFrame = f
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER", 40, -20)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "AzerothRomanceMemoryFrame")
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

    local add = W.Button(f, "Add memory", 100, 22, function()
        local popup = StaticPopup_Show("AZEROTHROMANCE_EDIT_MEMORY")
        if popup then
            popup.data = { text = "", onAccept = function(text)
                AR:Request("add_memory", { guid = MV.guid, kind = (kind:GetValue() ~= "" and kind:GetValue() ~= "summary") and kind:GetValue() or "fact",
                    text = text, importance = 60 }, function() MV:Load() end)
            end }
        end
    end)
    add:SetPoint("LEFT", nextB, "RIGHT", 20, 0)
    local clear = W.Button(f, "Clear shown kind", 120, 22, function()
        local k = kind:GetValue()
        local label = k == "" and "ALL memories" or ("all memories of this kind (" .. k .. ")")
        local popup = StaticPopup_Show("AZEROTHROMANCE_CONFIRM", "Delete " .. label .. "?")
        if popup then
            popup.data = function()
                AR:Request("clear_memories", { guid = MV.guid, kind = k ~= "" and k or nil }, function() MV.offset = 0 MV:Load() end)
            end
        end
    end)
    clear:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local reset = W.Button(f, "Full reset...", 100, 22, function()
        local popup = StaticPopup_Show("AZEROTHROMANCE_RESET")
        if popup then
            popup.data = function()
                AR:Request("reset_companion", { guid = MV.guid, confirm = "RESET" }, function() MV.offset = 0 MV:Load() end)
            end
        end
    end)
    reset:SetPoint("LEFT", clear, "RIGHT", 6, 0)

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
    AR:On("MEMORY_CHANGED", function(g) if f:IsShown() and g == MV.guid then MV:Load() end end)
end

-- ---------------------------------------------------------------- export / import

local MAX_SHOWN = 16000   -- the text box holds this many characters; bigger exports are only kept saved

local function companionName(guid)
    local c = AR:FindChar(guid)
    return c and c.name or tostring(guid)
end

local function savedExports()
    AzerothRomanceDB.exports = AzerothRomanceDB.exports or {}
    return AzerothRomanceDB.exports
end

-- Dialog that shows an export or takes an import.
local function buildTransfer()
    local d = W.Panel(UIParent, 500, 360, 0.98)
    _G.AzerothRomanceTransferFrame = d
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetPoint("CENTER", 0, 20)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "AzerothRomanceTransferFrame")
    d.title = W.Label(d, "", 14, W.GOLD, "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", 14, -12)
    local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    d.help = W.Label(d, "", 11, W.TEXT)
    d.help:SetPoint("TOPLEFT", 14, -36)
    d.help:SetWidth(470)
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

function MV:ShowTransfer(mode, text, info)
    local d = self.transfer or buildTransfer()
    self.transfer = d
    d.mode = mode
    local name = companionName(self.guid)
    d.status:SetText("")
    if mode == "export" then
        d.title:SetText("Export of " .. name)
        d.help:SetText("The export is saved in the addon. To import it into a companion, open its Memories and press " ..
            "\"Import...\" - no copying needed.\nTo keep it somewhere else, press Ctrl+C now to copy the text below.")
        d.saved:Hide()
        d.area:ClearAllPoints()
        d.area:SetPoint("TOPLEFT", 14, -84)
        d.area.caption:SetText(info or "")
        d.area:SetValue(text or "")
        d.go:Hide()
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
    d.saved:SetItems(items)
    local last = AzerothRomanceDB.lastExport
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
    AR.Transfer:Export(guid, function(i, n) status:SetText(("Exporting part %d/%d..."):format(i, n)) end,
        function(text, count)
            if not text then
                status:SetText("|cffff6060Export failed: " .. tostring(count) .. "|r")
                return
            end
            local name = companionName(guid)
            savedExports()[name] = { at = time(), memories = count, text = text }
            AzerothRomanceDB.lastExport = name
            local size = ("%d memories, %.1f KB"):format(count or 0, #text / 1024)
            status:SetText("|cff60ff60Saved|r (" .. size .. ").")
            if #text <= MAX_SHOWN then
                self:ShowTransfer("export", text, size)
            else
                self:ShowTransfer("export", "", size .. " - too large to show here. It is saved in the addon " ..
                    "(and in WTF/Account/<account>/SavedVariables/AzerothRomance.lua after /reload).")
            end
        end)
end

function MV:RunImport()
    local d = self.transfer
    local guid = self.guid
    if not d or not guid then return end
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
    AR.Transfer:Import(guid, text, function(i, n) d.status:SetText(("Importing part %d/%d..."):format(i, n)) end,
        function(ok, result)
            d.go:Enable()
            if ok then
                d.status:SetText("|cff60ff60Done:|r " .. table.concat(result or {}, ", "))
                self.ioStatus:SetText("|cff60ff60Imported:|r " .. table.concat(result or {}, ", "))
                self.offset = 0
                self:Load()
            else
                d.status:SetText("|cffff6060Import failed, nothing was changed: " .. tostring(result) .. "|r")
            end
        end)
end

function MV:Open(guid)
    guid = guid or AR.state.selected
    if not guid then
        AR:Print("Select a companion first.")
        return
    end
    if not self.frame then build() end
    self.guid = guid
    self.offset = 0
    local c = AR:FindChar(guid)
    self.who:SetText(c and ("of " .. c.name) or "")
    self.frame:Show()
    self:Load()
end

function MV:Load()
    if not self.frame or not self.guid then return end
    local kind = self.kind:GetValue()
    AR:Request("get_memories", { guid = self.guid, kind = kind ~= "" and kind or nil, search = self.search:GetValue(),
        offset = self.offset or 0, limit = PAGE }, function(msg)
        if msg.op ~= "memories" then return end
        self:Render(msg)
    end)
end

function MV:Render(msg)
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
                local popup = StaticPopup_Show("AZEROTHROMANCE_EDIT_MEMORY")
                if popup then
                    popup.data = { text = m.text, onAccept = function(text)
                        AR:Request("edit_memory", { guid = self.guid, id = m.id, text = text }, function() self:Load() end)
                    end }
                    local eb = popup.wideEditBox or popup.editBox
                    eb:SetText(m.text)
                end
            end)
            r.pin:SetScript("OnClick", function()
                AR:Request("pin_memory", { guid = self.guid, id = m.id, pinned = not m.pinned }, function() self:Load() end)
            end)
            r.del:SetScript("OnClick", function()
                AR:Request("delete_memory", { guid = self.guid, id = m.id }, function() self:Load() end)
            end)
        end
    end
end
