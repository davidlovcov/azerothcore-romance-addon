--[[
  Minimal WoW 3.3.5a API stub for running TrueCompanion outside the game (Lua 5.1).
  Frames are permissive objects that remember text/values/scripts; reading an
  undefined *global* raises an error so typos and Retail-only APIs are caught.
]]

local stub = { sent = {}, printed = {}, frames = {}, popups = {} }
_G.WOWSTUB = stub

local frameMT = {}
local function newFrame(kind, name, parent)
    local f = { _kind = kind or "Frame", _name = name, _parent = parent, _shown = true, _scripts = {}, _text = "",
        _value = 0, _checked = nil, _w = 100, _h = 20, _points = {}, _children = {}, _events = {} }
    setmetatable(f, frameMT)
    table.insert(stub.frames, f)
    if name then _G[name] = f end
    return f
end
stub.newFrame = newFrame

local methods = {}
function methods:Show() self._shown = true if self._scripts.OnShow then self._scripts.OnShow(self) end end
function methods:Hide() local was = self._shown self._shown = false if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown end
function methods:SetScript(ev, fn) self._scripts[ev] = fn end
function methods:GetScript(ev) return self._scripts[ev] end
function methods:HookScript(ev, fn) self._scripts[ev] = fn end
function methods:SetText(t) self._text = t == nil and "" or tostring(t) end
function methods:GetText() return self._text end
function methods:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
function methods:GetStringWidth() return #(self._text or "") * 6 end
function methods:SetValue(v) self._value = v if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end end
function methods:GetValue() return self._value end
function methods:SetChecked(v) self._checked = v and 1 or nil end
function methods:GetChecked() return self._checked end
function methods:SetWidth(w) self._w = w end
function methods:SetHeight(h) self._h = h end
function methods:GetWidth() return self._w end
function methods:GetHeight() return self._h end
function methods:SetSize(w, h) error("SetSize is not available on 3.3.5a regions (use SetWidth/SetHeight)") end
function methods:SetShown() error("SetShown is not available on 3.3.5a") end
function methods:SetPoint(...) table.insert(self._points, { ... }) end
function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods:GetName() return self._name end
function methods:GetParent() return self._parent end
function methods:CreateFontString(name) return newFrame("FontString", name, self) end
function methods:CreateTexture(name) return newFrame("Texture", name, self) end
function methods:RegisterEvent(e) self._events[e] = true end
function methods:UnregisterEvent(e) self._events[e] = nil end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12 end
function methods:GetVerticalScroll() return 0 end
function methods:GetCenter() return 0, 0 end
function methods:GetEffectiveScale() return 1 end
function methods:GetCursorPosition() return 0 end
function methods:IsEnabled() return self._enabled ~= false end
function methods:Enable() self._enabled = true end
function methods:Disable() self._enabled = false end
function methods:Click() if self._scripts.OnClick then self._scripts.OnClick(self, "LeftButton") end end
function methods:SetMultiLine() end
function methods:AddMessage(msg) self._messages = self._messages or {} table.insert(self._messages, msg) end
function methods:Clear() self._messages = {} end
function methods:GetNumMessages() return #(self._messages or {}) end
function methods:GetMinMaxValues() return 0, 100 end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end

frameMT.__index = function(t, k)
    local m = methods[k]
    if m then return m end
    -- any other widget *method* (CamelCase) is accepted as a no-op; plain fields are nil like in WoW
    if type(k) == "string" and k:match("^%u") then return function() return nil end end
    return nil
end

-- ---------------------------------------------------------------- globals

function CreateFrame(kind, name, parent, template)
    local f = newFrame(kind, name, parent)
    if template == "OptionsSliderTemplate" then
        newFrame("FontString", name .. "Low", f)
        newFrame("FontString", name .. "High", f)
        newFrame("FontString", name .. "Text", f)
    elseif template == "UICheckButtonTemplate" then
        newFrame("FontString", name .. "Text", f)
    end
    if kind == "EditBox" then f._text = "" end
    return f
end

UIParent = newFrame("Frame", "UIParent")
Minimap = newFrame("Frame", "Minimap")
GameTooltip = newFrame("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = newFrame("ScrollingMessageFrame", "DEFAULT_CHAT_FRAME")
DEFAULT_CHAT_FRAME.AddMessage = function(self, msg) table.insert(stub.printed, msg) end
ChatFontNormal, GameFontHighlightSmall, GameFontNormal = {}, {}, {}
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
YES, NO, SAVE, CANCEL, OKAY = "Yes", "No", "Save", "Cancel", "Okay"
RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, PRIEST = { r = 1, g = 1, b = 1 } }
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49, 0, 0.25 }, PALADIN = { 0, 0.25, 0.5, 0.75 }, PRIEST = { 0.49, 0.74, 0.25, 0.5 } }

function StaticPopup_Show(which, a1)
    assert(StaticPopupDialogs[which], "unknown popup " .. tostring(which))
    local p = newFrame("Frame", nil, UIParent)
    p.editBox = newFrame("EditBox", nil, p)
    p.which = which
    p.arg1 = a1
    table.insert(stub.popups, p)
    return p
end

local dropdowns = {}
function UIDropDownMenu_Initialize(dd, fn) dd._init = fn end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) table.insert(dropdowns, info) end
function UIDropDownMenu_SetSelectedValue(dd, v) dd._selected = v end
function UIDropDownMenu_SetText(dd, t) dd._ddtext = t end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end

function SendAddonMessage(prefix, text, channel, target)
    assert(#prefix + #text + 1 <= 254, "addon message too long: " .. (#prefix + #text + 1))
    assert(not text:find("\0"), "NUL in addon message")
    table.insert(stub.sent, { prefix = prefix, text = text, channel = channel, target = target })
end
function UnitName(u) if u == "player" then return "Arthas" end return nil end
function GetRealmName() return "TestRealm" end
local clock = 1000
function GetTime() return clock end
function stub.Advance(sec) clock = clock + sec end
function PlaySound() end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function SetPortraitTexture() end

-- macros and chat (Commands tab)
stub.macros, stub.chatSent, stub.inCombat, stub.partyMembers = {}, {}, false, 0
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 36, 18
function InCombatLockdown() return stub.inCombat end
function GetNumMacros()
    local a, c = 0, 0
    for _, m in ipairs(stub.macros) do if m.perChar then c = c + 1 else a = a + 1 end end
    return a, c
end
function GetMacroIndexByName(name)
    for i, m in ipairs(stub.macros) do if m.name == name then return i end end
    return 0
end
function CreateMacro(name, icon, body, perChar)
    assert(#name <= 16, "macro names are limited to 16 characters: " .. name)
    table.insert(stub.macros, { name = name, icon = icon, body = body, perChar = perChar and true or false })
    return #stub.macros
end
function EditMacro(i, name, icon, body) local m = stub.macros[i] if m then m.name, m.icon, m.body = name, icon, body end return i end
function PickupMacro(i) stub.cursorMacro = i end
function SendChatMessage(text, chatType, lang, target) table.insert(stub.chatSent, { text = text, chatType = chatType, target = target }) end
function GetNumPartyMembers() return stub.partyMembers end
function GetNumRaidMembers() return 0 end
tinsert = table.insert
date = os.date
time = os.time

-- strict globals: reading an unknown global is an error (catches typos and Retail-only APIs)
local allowed = { TrueCompanionDB = true, TrueCompanion = true, TrueCompanionChatInput = true,
    TrueCompanionMainFrame = true, TrueCompanionMemoryFrame = true, TrueCompanionMinimapButton = true }
setmetatable(_G, {
    __index = function(_, k)
        if allowed[k] or (type(k) == "string" and (k:match("^TrueCompanion") or k == "AzerothRomanceDB" or k:match("^SLASH_"))) then return nil end
        error("read of undefined global '" .. tostring(k) .. "'", 2)
    end,
})

-- deliver a server->client chunk as the 3.3.5 client would (CHAT_MSG_ADDON)
function stub.FireEvent(event, ...)
    for _, f in ipairs(stub.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

-- chat message filters (ChatFrame_AddMessageEventFilter); ChatLine runs them like one chat frame would
stub.chatFilters = {}
function ChatFrame_AddMessageEventFilter(event, fn)
    stub.chatFilters[event] = stub.chatFilters[event] or {}
    table.insert(stub.chatFilters[event], fn)
end
function stub.ChatLine(event, msg, author, lineId)
    for _, fn in ipairs(stub.chatFilters[event] or {}) do
        if fn(DEFAULT_CHAT_FRAME, event, msg, author, "", "", "", "", 0, 0, "", 0, lineId) then return true end
    end
    return false
end

function stub.Update(elapsed)
    for _, f in ipairs(stub.frames) do
        if f._scripts.OnUpdate then f._scripts.OnUpdate(f, elapsed) end
    end
end

return stub
