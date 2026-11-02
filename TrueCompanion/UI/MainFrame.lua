--[[
  TrueCompanion - main window, tabs, minimap button.
]]

local TC = _G.TrueCompanion
local W = TC.W

local UI = { tabs = {}, order = {} }
TC.UI = UI

local WIDTH, HEIGHT = 780, 562
local CONTENT_TOP = -106   -- below the two tab rows

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
        if not ok then TC:LogError("build:" .. id, err) end
        tab.frame = f
    end
    tab.frame:Show()
    self.current = id
    TC.db.lastTab = id
    for tid in pairs(self.tabs) do self:StyleTab(tid) end
    if tab.frame.OnShowTab then
        local ok, err = pcall(tab.frame.OnShowTab, tab.frame)
        if not ok then TC:LogError("show:" .. id, err) end
    end
end


function UI:Build()
    if self.main then return end
    local f = W.Panel(UIParent, WIDTH, HEIGHT, 0.95)
    _G.TrueCompanionMainFrame = f
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
        TC.db.window = { point = point, x = x, y = y }
    end)
    local w = TC.db.window
    f:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
    f:Hide()
    tinsert(UISpecialFrames, "TrueCompanionMainFrame")   -- ESC closes the window
    self.main = f

    -- header
    local glow = f:CreateTexture(nil, "BORDER")
    glow:SetPoint("TOPLEFT", 4, -4)
    glow:SetPoint("TOPRIGHT", -4, -4)
    glow:SetHeight(46)
    glow:SetTexture(0.04, 0.09, 0.30, 0.55)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(26)
    icon:SetHeight(26)
    icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\AddOns\\TrueCompanion\\Media\\logo")
    local title = W.Label(f, "True Companion", 17, W.GOLD, "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    self.subtitle = W.Label(f, "", 11, W.MUTED)
    self.subtitle:SetPoint("LEFT", title, "RIGHT", 12, -1)
    self.subtitle:SetWidth(430)
    self.subtitle:SetHeight(14)   -- one line; a long one is cut

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

    -- tab bars: the general tabs on top, below them the tabs about the selected companion
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 10, -52)
    bar:SetPoint("TOPRIGHT", -10, -52)
    bar:SetHeight(26)
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetTexture(1, 0.82, 0.25, 0.35)
    local bar2 = CreateFrame("Frame", nil, f)
    bar2:SetPoint("TOPLEFT", 10, -80)
    bar2:SetPoint("TOPRIGHT", -10, -80)
    bar2:SetHeight(24)
    local sep2 = bar2:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("BOTTOMLEFT")
    sep2:SetPoint("BOTTOMRIGHT")
    sep2:SetTexture(1, 0.82, 0.25, 0.2)
    local who = W.Label(bar2, "", 11, W.MUTED)
    who:SetPoint("LEFT", bar2, "LEFT", 4, 0)
    who:SetWidth(150)
    who:SetJustifyH("LEFT")
    self.companionLabel = who
    local COMPANION_X = 158   -- where the companion tabs start (after the label)

    local normal, personal, smallWidth = {}, {}, 0
    for _, id in ipairs(self.order) do
        local tab = self.tabs[id]
        local isPersonal = tab.opts.group == "companion"
        local b = makeTabButton(isPersonal and bar2 or bar, tab, 0, tab.opts.small)
        if tab.opts.small then
            b:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 2)
            smallWidth = smallWidth + b:GetWidth() + 6
        elseif isPersonal then
            personal[#personal + 1] = b
        else
            normal[#normal + 1] = b
        end
        tab.button = b
    end
    -- the tabs must not run into the small ones (or out of the window): narrow them evenly if needed
    local function lay(buttons, row, x0, room)
        local total = 0
        for _, b in ipairs(buttons) do total = total + b:GetWidth() + 2 end
        local shrink = total > room and math.ceil((total - room) / #buttons) or 0
        local x = x0
        for _, b in ipairs(buttons) do
            if shrink > 0 then b:SetWidth(math.max(50, b:GetWidth() - shrink)) end
            b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
            x = x + b:GetWidth() + 2
        end
        return x
    end
    UI.tabBarWidth = lay(normal, bar, 0, WIDTH - 24 - smallWidth) + smallWidth
    UI.companionBarWidth = lay(personal, bar2, COMPANION_X, WIDTH - 24 - COMPANION_X)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 12, CONTENT_TOP)
    content:SetPoint("BOTTOMRIGHT", -12, 12)
    self.content = content

    f:SetScript("OnShow", function()
        UI:RefreshStatus()
        if not TC.state.connected then
            TC:Request("hello", { version = TC.version, protocol = TC.Protocol.VERSION })
        end
        TC:Request("list_chars")
        TC:Request("get_status")
    end)

    TC:On("STATUS_CHANGED", function() UI:RefreshStatus() end)
    TC:On("LEAD_CHANGED", function() UI:RefreshStatus() end)
    -- who leads and where to, while the window is open
    local leadTimer = 0
    f:SetScript("OnUpdate", function(_, dt)
        leadTimer = leadTimer - dt
        if leadTimer > 0 then return end
        leadTimer = 4
        TC:RequestLead()
    end)
    TC:On("HELLO", function() UI:RefreshStatus() end)
    TC:On("SELECTION_CHANGED", function() UI:RefreshCompanionLabel() end)
    TC:On("CHARS_CHANGED", function() UI:RefreshCompanionLabel() end)
    self:RefreshCompanionLabel()
end

-- the second tab row is about the companion selected on the Companion tab
function UI:RefreshCompanionLabel()
    if not self.companionLabel then return end
    local c = TC.state.selected and TC:FindChar(TC.state.selected)
    if c and c.name then
        self.companionLabel:SetText(("|cffffd100%s|r:"):format(c.name))
    else
        self.companionLabel:SetText("No companion selected:")
    end
end

function UI:RefreshStatus()
    if not self.light then return end
    local s = TC.state.status
    local online = TC:OllamaOnline()
    if not TC.state.connected then
        self.light:SetVertexColor(0.5, 0.5, 0.5)
        self.lightText:SetText("Connecting to server...")
    elseif s and s.enabled == false then
        self.light:SetVertexColor(0.8, 0.2, 0.2)
        self.lightText:SetText("Module disabled")
    elseif TC.state.hello and TC.state.hello.features and TC.state.hello.features.ollama == false then
        -- switched off on the server: not an error, and nothing is being checked
        self.light:SetVertexColor(0.5, 0.5, 0.55)
        self.lightText:SetText("AI off (commands only)")
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
    local names = TC:ActiveNames()
    if #names > 0 then
        local lead = TC:LeadText()
        self.subtitle:SetText(("with %s%s"):format(table.concat(names, ", "), lead ~= "" and ("  |cffffd100·|r  " .. lead) or ""))
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
        self:ShowTab(self.current or TC.db.lastTab or "companion")
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
    local angle = math.rad(TC.db.minimap.angle or 220)
    local r = 80
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function buildMinimapButton()
    local b = CreateFrame("Button", "TrueCompanionMinimapButton", Minimap)
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
    icon:SetTexture("Interface\\AddOns\\TrueCompanion\\Media\\logo")
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
            TC.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            updateMinimapPosition(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("True Companion", 1, 0.82, 0.25)
        GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
        GameTooltip:AddLine("Right-click: chat", 1, 1, 1)
        GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updateMinimapPosition(b)
    setShown(b, not TC.db.minimap.hide)
    UI.minimap = b
end

TC:On("DB_READY", function()
    buildMinimapButton()
end)

TC:On("MINIMAP_TOGGLE", function()
    if UI.minimap then setShown(UI.minimap, not TC.db.minimap.hide) end
end)
