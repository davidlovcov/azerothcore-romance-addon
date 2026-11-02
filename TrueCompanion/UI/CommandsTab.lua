--[[
  TrueCompanion - Commands tab: one-click buttons for the common companion commands, your own
  commands, and WoW macros made from any of them (to put on an action bar).

  A button sends its text exactly as if you had typed it: to the companion chosen under "Send to" (any
  companion who is with you; by default the one selected on the Companion tab) or in party chat to all. A macro does the same with /w <name> or /p, so it also
  works with this window closed.
]]

local TC = _G.TrueCompanion
local W = TC.W
local UI = TC.UI

local MAX_CUSTOM = 12
local MACRO_ICON = 1   -- the question mark; another icon can be picked in the macro window (/macro)

-- label, what is said, [true = only under "More commands"]; the first ones are the everyday commands
local BUILTIN = {
    { "Follow me", "follow me" },
    { "Wait here", "wait" },
    { "Lead the way", "lead the way" },
    { "Stop leading", "stop leading" },
    { "Attack all here", "attack all here" },
    { "Stop attacking", "stop attacking" },
    { "Pick up quests", "pick up all your quests" },
    { "Turn in quests", "turn in your quests" },
    { "Go on", "go on", true },
    { "Attack", "attack", true },
    { "Accept quest", "accept the quest", true },
    { "Share quests", "share your quests", true },
    { "Sell junk", "sell your junk", true },
    { "Bags?", "what's in your bags?", true },
    { "Learn spells", "learn your spells", true },
}
TC.BUILTIN_COMMANDS = BUILTIN

local function custom()
    TrueCompanionDB.commands = TrueCompanionDB.commands or {}
    return TrueCompanionDB.commands
end

-- "party", or the guid of the companion the commands go to (default: the one selected on the Companion tab)
local function target()
    local t = TrueCompanionDB.commandTarget
    if t == "party" then return "party" end
    local g = tonumber(t)
    if g then
        local c = TC:FindChar(g)
        if c and c.active then return g end
    end
    return TC.state.selected
end
TC.CommandTarget = target

-- the companions that are with you right now (called, AI on)
local function activeCompanions()
    local out = {}
    for _, c in ipairs(TC.state.chars or {}) do
        if c.active then out[#out + 1] = c end
    end
    return out
end

local function inParty()
    return (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 or (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Sends `text` to the selected companion, or in party chat to all of them. Returns true when sent.
function TC:SendCommand(text)
    text = trim(text)
    if text == "" then return false, "Nothing to send." end
    if target() == "party" then
        if not inParty() then return false, "You are not in a party: invite your companions or send to the selected one." end
        SendChatMessage(text, "PARTY")
        return true
    end
    local g = target()
    if not g then return false, "Choose a companion under \"Send to\" (or call one on the Companion tab)." end
    TC.state.typing[g] = true
    TC:Fire("TYPING_CHANGED", g)
    TC:Request("chat", { guid = g, text = text })
    return true
end

-- Macro name (max. 16 characters in 3.3.5) and body for a command, for the current target.
local function macroFor(label, text)
    if target() == "party" then
        return ("Party " .. label):sub(1, 16), "/p " .. text
    end
    local g = target()
    local c = g and TC:FindChar(g)
    if not c or not c.name then return nil, "Choose a companion under \"Send to\" first." end
    return (c.name:sub(1, 6) .. " " .. label):sub(1, 16), "/w " .. c.name .. " " .. text
end

-- Creates the macro (or updates one with the same name). Returns its index, or nil and the reason.
function TC:MakeMacro(label, text)
    if InCombatLockdown() then return nil, "Macros can't be changed during combat." end
    local name, body = macroFor(label, trim(text))
    if not name then return nil, body end
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        EditMacro(idx, name, MACRO_ICON, body)
        return idx, name
    end
    local numAccount, numChar = GetNumMacros()
    if numChar < (MAX_CHARACTER_MACROS or 18) then
        return CreateMacro(name, MACRO_ICON, body, 1), name
    elseif numAccount < (MAX_ACCOUNT_MACROS or 36) then
        return CreateMacro(name, MACRO_ICON, body, nil), name
    end
    return nil, "All macro slots are full; delete some in the macro window (/macro)."
end

local function build(f)
    local status = W.Label(f, "", 11, W.MUTED)
    status:SetPoint("BOTTOMLEFT", 2, 10)
    status:SetWidth(520)
    local function say(text, bad) status:SetText(bad and ("|cffff6060" .. text .. "|r") or text) end

    local to = W.Dropdown(f, "Send to", 250, {}, function(v)
        TrueCompanionDB.commandTarget = v
        f:Render()
    end)
    to:SetPoint("TOPLEFT", 0, -2)
    f.toDropdown, f.status = to, status
    local macroMode = W.Check(f, "Macro mode",
        "On: clicking a command creates a WoW macro for it and puts it on your cursor, to drop on an action bar. " ..
        "Off: clicking sends the command.")
    macroMode:SetPoint("TOPLEFT", 270, -16)
    local help = W.Label(f, "Click to send. With macro mode on, a click makes a macro instead (also works with this window closed).",
        10, W.MUTED)
    help:SetPoint("TOPLEFT", 400, -14)
    help:SetWidth(350)

    -- one click: send, or make a macro and put it on the cursor
    local function activate(label, text)
        if macroMode:GetChecked() then
            local idx, info = TC:MakeMacro(label, text)
            if not idx then return say(info, true) end
            PickupMacro(idx)
            return say(("Macro \"%s\" is on your cursor: drop it on an action bar."):format(info))
        end
        local ok, err = TC:SendCommand(text)
        if ok then say("Sent: " .. text) else say(err, true) end
    end

    -- built-in commands: two columns
    local left = W.Panel(f, 370, 330, 0.35)
    left:SetPoint("TOPLEFT", 0, -50)
    local h1 = W.Heading(left, "Common commands")
    h1:SetPoint("TOPLEFT", 8, -6)
    f.builtinButtons = {}
    for i, cmd in ipairs(BUILTIN) do
        local b = W.Button(left, cmd[1], 172, 24, function() activate(cmd[1], cmd[2]) end)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", 8 + col * 180, -28 - row * 28)
        W.Tooltip(b, cmd[1], "Says: \"" .. cmd[2] .. "\"")
        f.builtinButtons[i] = b
    end
    local more = W.Button(left, "", 172, 20)
    more:SetPoint("BOTTOMLEFT", 8, 8)
    W.Tooltip(more, "More commands", "Go on, attack your target, accept a quest, share quests, sell junk, ask what's in her bags, learn new spells at her trainer.")
    local function showMore()
        local open = TC.db.showMoreCommands and true or false
        for i, cmd in ipairs(BUILTIN) do
            if cmd[3] then UI.SetShown(f.builtinButtons[i], open) end
        end
        more:SetText(open and "Fewer commands" or "More commands")
    end
    more:SetScript("OnClick", function()
        TC.db.showMoreCommands = not TC.db.showMoreCommands
        showMore()
    end)
    f.moreButton = more

    -- own commands
    local right = W.Panel(f, 380, 330, 0.35)
    right:SetPoint("TOPLEFT", 378, -50)
    local h2 = W.Heading(right, "Your commands")
    h2:SetPoint("TOPLEFT", 8, -6)
    local label = W.Edit(right, "Button label", 110, 24)
    label:SetPoint("TOPLEFT", 10, -26)
    local text = W.Edit(right, "What to say", 180, 200)
    text:SetPoint("TOPLEFT", 128, -26)
    f.labelEdit, f.textEdit = label, text
    local add = W.Button(right, "Add", 50, 22, function()
        local l, t = trim(label:GetValue()), trim(text:GetValue())
        if t == "" then return say("Type what she should be told, e.g. \"lead me to the mine\".", true) end
        if #custom() >= MAX_CUSTOM then return say(("You can keep up to %d commands; delete one first."):format(MAX_CUSTOM), true) end
        table.insert(custom(), { label = l ~= "" and l:sub(1, 24) or t:sub(1, 24), text = t })
        label:SetValue("")
        text:SetValue("")
        say("Added.")
        f:Render()
    end)
    add:SetPoint("TOPLEFT", 316, -41)
    f.addButton = add

    f.rows = {}
    for i = 1, MAX_CUSTOM do
        local y = -72 - (i - 1) * 21
        local send = W.Button(right, "", 230, 20)
        send:SetPoint("TOPLEFT", 10, y)
        local mac = W.Button(right, "Macro", 60, 20)
        mac:SetPoint("TOPLEFT", 244, y)
        W.Tooltip(mac, "Macro", "Creates a WoW macro for this command and puts it on your cursor.")
        local del = W.Button(right, "X", 26, 20)
        del:SetPoint("TOPLEFT", 308, y)
        W.Tooltip(del, "Delete", "Removes this command (a macro made from it stays).")
        f.rows[i] = { send = send, macro = mac, del = del }
    end

    local all = W.Button(f, "Make macros for all", 150, 22, function()
        if InCombatLockdown() then return say("Macros can't be changed during combat.", true) end
        local made, failed = 0, nil
        local list = {}
        for _, c in ipairs(BUILTIN) do list[#list + 1] = { c[1], c[2] } end
        for _, c in ipairs(custom()) do list[#list + 1] = { c.label, c.text } end
        for _, c in ipairs(list) do
            local idx, info = TC:MakeMacro(c[1], c[2])
            if idx then made = made + 1 else failed = info break end
        end
        if failed then
            say(("%d macros made, then: %s"):format(made, failed), true)
        else
            say(("%d macros made. Open the macro window (/macro) and drag them to your action bars."):format(made))
        end
    end)
    all:SetPoint("BOTTOMRIGHT", -4, 6)
    W.Tooltip(all, "Make macros for all", "One macro per command (common and yours), for the current \"Send to\". " ..
        "Existing ones with the same name are updated. Character macros first, then account macros.")

    function f:Render()
        showMore()
        local items = {}
        for _, c in ipairs(activeCompanions()) do
            items[#items + 1] = { value = tostring(c.guid), text = c.name }
        end
        local t = target()
        -- the selected companion is not with you (not called): still listed, so the choice is visible
        local c = t ~= "party" and t and TC:FindChar(t)
        if c and not c.active then items[#items + 1] = { value = tostring(c.guid), text = c.name .. " (not called)" } end
        items[#items + 1] = { value = "party", text = "All companions (party chat)" }
        to:SetItems(items)
        to:SetValue(t == "party" and "party" or tostring(t or ""))
        local list = custom()
        for i, row in ipairs(self.rows) do
            local cmd = list[i]
            if cmd then
                row.send:SetText(cmd.label)
                row.send:SetScript("OnClick", function() activate(cmd.label, cmd.text) end)
                W.Tooltip(row.send, cmd.label, "Says: \"" .. cmd.text .. "\"")
                row.macro:SetScript("OnClick", function()
                    local idx, info = TC:MakeMacro(cmd.label, cmd.text)
                    if not idx then return say(info, true) end
                    PickupMacro(idx)
                    say(("Macro \"%s\" is on your cursor: drop it on an action bar."):format(info))
                end)
                row.del:SetScript("OnClick", function()
                    table.remove(list, i)
                    say("Deleted.")
                    f:Render()
                end)
                row.send:Show()
                row.macro:Show()
                row.del:Show()
            else
                row.send:Hide()
                row.macro:Hide()
                row.del:Hide()
            end
        end
    end

    TC:On("SELECTION_CHANGED", function() if f:IsShown() then f:Render() end end)
    TC:On("CHARS_CHANGED", function() if f:IsShown() then f:Render() end end)
    f.OnShowTab = function() f:Render() end
end

UI:RegisterTab("commands", "Commands", build)
