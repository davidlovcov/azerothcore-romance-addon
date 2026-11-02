--[[
  TrueCompanion - widget helpers (WoW 3.3.5a API only)
  Dark panels with gold accents built from stock 3.3.5 textures.
]]

local TC = _G.TrueCompanion
local W = {}
TC.W = W

W.GOLD = { 1.0, 0.82, 0.25 }
W.GOLD_DIM = { 0.75, 0.6, 0.25 }
W.ROSE = { 1.0, 0.6, 0.8 }
W.TEXT = { 0.92, 0.88, 0.8 }
W.MUTED = { 0.6, 0.58, 0.55 }

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function W.Panel(parent, w, h, alpha)
    local f = CreateFrame("Frame", nil, parent)
    if w then f:SetWidth(w) end
    if h then f:SetHeight(h) end
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.06, 0.05, 0.07, alpha or 0.85)
    f:SetBackdropBorderColor(W.GOLD_DIM[1], W.GOLD_DIM[2], W.GOLD_DIM[3], 0.8)
    return f
end

function W.Label(parent, text, size, color, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if size then
        local path = fs:GetFont()
        fs:SetFont(path or "Fonts\\FRIZQT__.TTF", size)
    end
    local c = color or W.TEXT
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Heading(parent, text)
    local fs = W.Label(parent, text, 13, W.GOLD, "GameFontNormal")
    return fs
end

function W.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(w or 100)
    b:SetHeight(h or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local INPUT_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Styles a plain EditBox: dark field with a gold border that brightens while focused.
-- (The stock InputBoxTemplate draws its middle segment almost invisibly on dark panels.)
function W.StyleInput(e)
    e:SetBackdrop(INPUT_BACKDROP)
    e:SetBackdropColor(0, 0, 0, 0.65)
    e:SetBackdropBorderColor(W.GOLD_DIM[1], W.GOLD_DIM[2], W.GOLD_DIM[3], 0.7)
    e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(7, 7, 3, 3)
    e:SetAutoFocus(false)
    e:EnableMouse(true)
    e:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(W.GOLD_DIM[1], W.GOLD_DIM[2], W.GOLD_DIM[3], 0.7)
        self:HighlightText(0, 0)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

-- Single-line edit box with a caption above it.
function W.Edit(parent, caption, w, maxLetters)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(w)
    holder:SetHeight(40)
    holder.caption = W.Label(holder, caption, 11, W.GOLD_DIM)
    holder.caption:SetPoint("TOPLEFT", 2, 0)
    holder.caption:SetWidth(w)
    local e = W.StyleInput(CreateFrame("EditBox", nil, holder))
    e:SetWidth(w)
    e:SetHeight(24)
    e:SetPoint("TOPLEFT", 0, -15)
    e:SetMaxLetters(maxLetters or 64)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    holder.edit = e
    function holder:GetValue() return self.edit:GetText() or "" end
    function holder:SetValue(v) self.edit:SetText(v or "") self.edit:SetCursorPosition(0) end
    return holder
end

-- Multi-line text area inside a scroll frame.
local areaCount = 0
function W.TextArea(parent, caption, w, h, maxLetters)
    areaCount = areaCount + 1
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(w)
    holder:SetHeight(h + 16)
    holder.caption = W.Label(holder, caption, 11, W.GOLD_DIM)
    holder.caption:SetPoint("TOPLEFT", 2, 0)
    local bg = W.Panel(holder, w, h, 0.6)
    bg:SetPoint("TOPLEFT", 0, -14)
    local scroll = CreateFrame("ScrollFrame", "TrueCompanionTextArea" .. areaCount, bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local e = CreateFrame("EditBox", nil, scroll)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetWidth(w - 36)
    e:SetHeight(h)
    e:SetMaxLetters(maxLetters or 600)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnCursorChanged", function(self, x, y, cw, ch)
        local offset = scroll:GetVerticalScroll()
        local height = scroll:GetHeight()
        y = -y
        if y < offset then
            scroll:SetVerticalScroll(y)
        elseif y + ch > offset + height then
            scroll:SetVerticalScroll(y + ch - height)
        end
    end)
    scroll:SetScrollChild(e)
    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() e:SetFocus() end)
    holder.edit = e
    function holder:GetValue() return self.edit:GetText() or "" end
    function holder:SetValue(v) self.edit:SetText(v or "") end
    return holder
end

local sliderCount = 0
function W.Slider(parent, caption, w, minV, maxV, step, lowText, highText)
    sliderCount = sliderCount + 1
    local name = "TrueCompanionSlider" .. sliderCount
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(w)
    s:SetHeight(16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step or 1)
    _G[name .. "Low"]:SetText(lowText or tostring(minV))
    _G[name .. "High"]:SetText(highText or tostring(maxV))
    _G[name .. "Text"]:SetText(caption)
    _G[name .. "Text"]:SetTextColor(W.GOLD_DIM[1], W.GOLD_DIM[2], W.GOLD_DIM[3])
    local value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOP", s, "BOTTOM", 0, 2)
    s.valueText = value
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        self.valueText:SetText(v)
        if self.onChange then self.onChange(v) end
    end)
    function s:GetValueInt() return math.floor(self:GetValue() + 0.5) end
    return s
end

local checkCount = 0
function W.Check(parent, caption, tooltip)
    checkCount = checkCount + 1
    local c = CreateFrame("CheckButton", "TrueCompanionCheck" .. checkCount, parent, "UICheckButtonTemplate")
    c:SetWidth(24)
    c:SetHeight(24)
    local label = _G[c:GetName() .. "Text"]
    label:SetText(caption)
    label:SetTextColor(W.TEXT[1], W.TEXT[2], W.TEXT[3])
    if tooltip then
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(caption, 1, 0.82, 0.25)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return c
end

local ddCount = 0
-- items: { {value=..., text=...}, ... }
function W.Dropdown(parent, caption, w, items, onSelect)
    ddCount = ddCount + 1
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(w)
    holder:SetHeight(44)
    holder.caption = W.Label(holder, caption, 11, W.GOLD_DIM)
    holder.caption:SetPoint("TOPLEFT", 2, 0)
    local dd = CreateFrame("Frame", "TrueCompanionDropdown" .. ddCount, holder, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", -16, -12)
    UIDropDownMenu_SetWidth(dd, w - 40)
    holder.dd = dd
    holder.items = items or {}
    holder.value = nil
    UIDropDownMenu_Initialize(dd, function()
        for _, it in ipairs(holder.items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = it.text
            info.value = it.value
            info.checked = (holder.value == it.value)
            info.func = function()
                holder:SetValue(it.value)
                if onSelect then onSelect(it.value) end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    function holder:SetItems(list)
        self.items = list or {}
    end
    function holder:SetValue(v)
        self.value = v
        local text = ""
        for _, it in ipairs(self.items) do
            if it.value == v then text = it.text end
        end
        UIDropDownMenu_SetSelectedValue(self.dd, v)
        UIDropDownMenu_SetText(self.dd, text)
    end
    function holder:GetValue() return self.value end
    return holder
end

-- Horizontal value bar (relationship meters).
function W.Bar(parent, caption, w, color)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(w)
    holder:SetHeight(26)
    holder.caption = W.Label(holder, caption, 11, W.TEXT)
    holder.caption:SetPoint("TOPLEFT", 0, 0)
    holder.value = W.Label(holder, "", 11, W.MUTED)
    holder.value:SetPoint("TOPRIGHT", 0, 0)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetWidth(w)
    bar:SetHeight(10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local c = color or W.ROSE
    bar:SetStatusBarColor(c[1], c[2], c[3])
    bar:SetMinMaxValues(0, 100)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(0.15, 0.12, 0.15, 0.8)
    holder.bar = bar
    function holder:Set(v)
        v = tonumber(v) or 0
        self.bar:SetValue(v)
        self.value:SetText(("%d"):format(v))
    end
    return holder
end

function W.Tooltip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0.25)
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Class icon texture coordinates from the stock character-create sheet.
function W.SetClassIcon(tex, classId)
    local token = TC.CLASS_TOKENS[tonumber(classId) or 0]
    tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
    local c = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if c then
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- Shows a portrait if the companion is a party/raid member; otherwise the class icon.
function W.SetCompanionPortrait(tex, name, classId)
    if name then
        for i = 1, 4 do
            if UnitName("party" .. i) == name then
                SetPortraitTexture(tex, "party" .. i)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                return
            end
        end
    end
    W.SetClassIcon(tex, classId)
end
