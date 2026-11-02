--[[
  AzerothRomance - main window, tabs, minimap button.
]]

local AR = _G.AzerothRomance
local W = AR.W

local UI = { tabs = {}, order = {} }
AR.UI = UI

local WIDTH, HEIGHT = 780, 540

-- 3.3.5 has no Region:SetShown()
local function setShown(region, shown) if shown then region:Show() else region:Hide() end end

function UI:RegisterTab(id, label, build, opts)
    self.tabs[id] = { id = id, label = label, build = build, opts = opts or {} }
    table.insert(self.order, id)
end

local function makeTabButton(parent, tab, x, small)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(small and 18 or 24)
    local fs = b:CreateFontString(nil, "OVERLAY", small and "GameFontNormalSmall" or "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(tab.label)
    b.text = fs
    b:SetWidth(math.max(70, (fs:GetStringWidth() or 60) + 24))
    local hl = b:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetTexture(1, 0.82, 0.25, 0.12)
    hl:Hide()
    b.selectedTex = hl
    local line = b:CreateTexture(nil, "ARTWORK")
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", 6, 0)
    line:SetPoint("BOTTOMRIGHT", -6, 0)
    line:SetTexture(1, 0.82, 0.25, 0.9)
    line:Hide()
    b.line = line
    b:SetScript("OnClick", function() UI:ShowTab(tab.id) end)
    b:SetScript("OnEnter", function(self) if UI.current ~= tab.id then self.text:SetTextColor(1, 1, 1) end end)
    b:SetScript("OnLeave", function(self) UI:StyleTab(tab.id) end)
    return b
end

function UI:StyleTab(id)
    local tab = self.tabs[id]
    if not tab or not tab.button then return end
    local sel = self.current == id
    setShown(tab.button.selectedTex, sel)
    setShown(tab.button.line, sel)
    if sel then
        tab.button.text:SetTextColor(1, 0.82, 0.25)
    elseif tab.opts.small then
        tab.button.text:SetTextColor(0.55, 0.55, 0.55)
    else
        tab.button.text:SetTextColor(0.85, 0.8, 0.72)
    end
end

function UI:ShowTab(id)
    if not self.tabs[id] then id = "companion" end
    for tid, tab in pairs(self.tabs) do
        if tab.frame then tab.frame:Hide() end
    end
    local tab = self.tabs[id]
    if not tab.frame then
        local f = CreateFrame("Frame", nil, self.content)
        f:SetAllPoints(self.content)
        local ok, err = pcall(tab.build, f)
        if not ok then AR:LogError("build:" .. id, err) end
        tab.frame = f
    end
    tab.frame:Show()
    self.current = id
    AR.db.lastTab = id
    for tid in pairs(self.tabs) do self:StyleTab(tid) end
    if tab.frame.OnShowTab then
        local ok, err = pcall(tab.frame.OnShowTab, tab.frame)
        if not ok then AR:LogError("show:" .. id, err) end
    end
end


function UI:Build()
    if self.main then return end
    local f = W.Panel(UIParent, WIDTH, HEIGHT, 0.95)
    _G.AzerothRomanceMainFrame = f
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        AR.db.window = { point = point, x = x, y = y }
    end)
    local w = AR.db.window
    f:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
    f:Hide()
    tinsert(UISpecialFrames, "AzerothRomanceMainFrame")   -- ESC closes the window
    self.main = f

    -- header
    local glow = f:CreateTexture(nil, "BORDER")
    glow:SetPoint("TOPLEFT", 4, -4)
    glow:SetPoint("TOPRIGHT", -4, -4)
    glow:SetHeight(46)
    glow:SetTexture(0.35, 0.12, 0.22, 0.45)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(26)
    icon:SetHeight(26)
    icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\AddOns\\AzerothRomance\\Media\\heart")
    local title = W.Label(f, "Azeroth Romance", 17, W.GOLD, "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    self.subtitle = W.Label(f, "", 11, W.MUTED)
    self.subtitle:SetPoint("LEFT", title, "RIGHT", 12, -1)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- connection light
    local light = f:CreateTexture(nil, "OVERLAY")
    light:SetWidth(10)
    light:SetHeight(10)
    light:SetPoint("TOPRIGHT", -40, -20)
    light:SetTexture("Interface\\Buttons\\WHITE8X8")
    self.light = light
    self.lightText = W.Label(f, "", 10, W.MUTED)
    self.lightText:SetPoint("RIGHT", light, "LEFT", -6, 0)

    -- tab bar
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 10, -52)
    bar:SetPoint("TOPRIGHT", -10, -52)
    bar:SetHeight(26)
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetTexture(1, 0.82, 0.25, 0.35)
    local normal, smallWidth = {}, 0
    for _, id in ipairs(self.order) do
        local tab = self.tabs[id]
        local b = makeTabButton(bar, tab, 0, tab.opts.small)
        if tab.opts.small then
            b:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 2)
            smallWidth = smallWidth + b:GetWidth() + 6
        else
            normal[#normal + 1] = b
        end
        tab.button = b
    end
    -- the tabs must not run into the small ones on the right: narrow them evenly if needed
    local total = 0
    for _, b in ipairs(normal) do total = total + b:GetWidth() + 2 end
    local room = WIDTH - 24 - smallWidth
    local shrink = total > room and math.ceil((total - room) / #normal) or 0
    local x = 0
    for _, b in ipairs(normal) do
        if shrink > 0 then b:SetWidth(math.max(50, b:GetWidth() - shrink)) end
        b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
        x = x + b:GetWidth() + 2
    end
    UI.tabBarWidth = x + smallWidth

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 12, -84)
    content:SetPoint("BOTTOMRIGHT", -12, 12)
    self.content = content

    f:SetScript("OnShow", function()
        UI:RefreshStatus()
        if not AR.state.connected then
            AR:Request("hello", { version = AR.version, protocol = AR.Protocol.VERSION })
        end
        AR:Request("list_chars")
        AR:Request("get_status")
    end)

    AR:On("STATUS_CHANGED", function() UI:RefreshStatus() end)
    AR:On("HELLO", function() UI:RefreshStatus() end)
end

function UI:RefreshStatus()
    if not self.light then return end
    local s = AR.state.status
    local online = AR:OllamaOnline()
    if not AR.state.connected then
        self.light:SetVertexColor(0.5, 0.5, 0.5)
        self.lightText:SetText("Connecting to server...")
    elseif s and s.enabled == false then
        self.light:SetVertexColor(0.8, 0.2, 0.2)
        self.lightText:SetText("Module disabled")
    elseif online then
        self.light:SetVertexColor(0.3, 0.9, 0.4)
        self.lightText:SetText("Ollama online")
    elseif s and s.ollama and s.ollama.checked then
        self.light:SetVertexColor(0.95, 0.35, 0.3)
        self.lightText:SetText("Ollama unavailable")
    else
        self.light:SetVertexColor(0.95, 0.75, 0.3)
        self.lightText:SetText("Checking Ollama...")
    end
    -- The header names the companions that are really with you, not just the selected one:
    -- a failed call must not look like a switch.
    local names = AR:ActiveNames()
    if #names > 0 then
        self.subtitle:SetText(("with %s"):format(table.concat(names, ", ")))
    else
        self.subtitle:SetText("")
    end
end

function UI:Toggle()
    self:Build()
    if self.main:IsShown() then
        self.main:Hide()
    else
        self.main:Show()
        self:ShowTab(self.current or AR.db.lastTab or "companion")
    end
end

function UI:Open(tab)
    self:Build()
    self.main:Show()
    self:ShowTab(tab)
end

-- shared region helper for tabs
UI.SetShown = setShown

-- ---------------------------------------------------------------- minimap button

local function updateMinimapPosition(btn)
    local angle = math.rad(AR.db.minimap.angle or 220)
    local r = 80
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function buildMinimapButton()
    local b = CreateFrame("Button", "AzerothRomanceMinimapButton", Minimap)
    b:SetWidth(31)
    b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\AddOns\\AzerothRomance\\Media\\heart")
    icon:SetPoint("CENTER", b, "TOPLEFT", 16.5, -16.5)   -- the middle of the border ring
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            UI:Open("chat")
        else
            UI:Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            AR.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            updateMinimapPosition(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Azeroth Romance", 1, 0.82, 0.25)
        GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
        GameTooltip:AddLine("Right-click: chat", 1, 1, 1)
        GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updateMinimapPosition(b)
    setShown(b, not AR.db.minimap.hide)
    UI.minimap = b
end

AR:On("DB_READY", function()
    buildMinimapButton()
end)

AR:On("MINIMAP_TOGGLE", function()
    if UI.minimap then setShown(UI.minimap, not AR.db.minimap.hide) end
end)
