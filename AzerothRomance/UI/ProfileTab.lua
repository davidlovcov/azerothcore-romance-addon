--[[
  AzerothRomance - Player Profile tab: who you are in the roleplay.
  Stored per character, with an optional account-wide default.
]]

local AR = _G.AzerothRomance
local W = AR.W
local UI = AR.UI

local FIELDS = {
    { key = "rpIdentity", label = "Roleplay identity (who you are in this world)" },
    { key = "background", label = "Character background" },
    { key = "interests", label = "Interests & hobbies" },
    { key = "preferences", label = "Personal preferences" },
    { key = "expectations", label = "What you hope for in the relationship" },
    { key = "sharedHistory", label = "Shared fictional history with your companion" },
}

local function build(f)
    local intro = W.Label(f, "Tell your companions who you are in the roleplay. They remember it, so they won't keep asking.", 11, W.MUTED)
    intro:SetPoint("TOPLEFT", 2, -2)
    intro:SetWidth(740)

    local fields = {}
    local name = W.Edit(f, "Preferred name", 170, 32)
    name:SetPoint("TOPLEFT", 0, -24)
    fields.preferredName = name
    local nick = W.Edit(f, "Nickname", 170, 32)
    nick:SetPoint("TOPLEFT", 184, -24)
    fields.nickname = nick
    local age = W.Edit(f, "Age (optional)", 90, 4)
    age:SetPoint("TOPLEFT", 368, -24)
    age.edit:SetNumeric(true)
    fields.age = age
    local pron = W.Edit(f, "Pronouns", 150, 24)
    pron:SetPoint("TOPLEFT", 472, -24)
    fields.pronouns = pron

    local y = -74
    for i, fd in ipairs(FIELDS) do
        local col = (i - 1) % 2
        local area = W.TextArea(f, fd.label, 365, 52, 600)
        area:SetPoint("TOPLEFT", col * 376, y)
        fields[fd.key] = area
        if col == 1 then y = y - 76 end
    end
    local facts = W.TextArea(f, "Custom instructions and personal facts", 741, 52, 600)
    facts:SetPoint("TOPLEFT", 0, y)
    fields.customFacts = facts

    local example = W.Label(f, "Example: \"My name is David. I'm a human adventurer who enjoys exploring Azeroth, collecting rare " ..
        "equipment, and learning magic. Elara and I have been friends since childhood.\"", 10, W.MUTED)
    example:SetPoint("TOPLEFT", 0, y - 74)
    example:SetWidth(740)

    local default = W.Check(f, "Save as account-wide default", "Used by all your characters that have no profile of their own.")
    default:SetPoint("BOTTOMLEFT", 0, 4)
    local status = W.Label(f, "", 11, W.MUTED)
    status:SetPoint("BOTTOMLEFT", 220, 12)
    local save = W.Button(f, "Save profile", 130, 24)
    save:SetPoint("BOTTOMRIGHT", -4, 6)
    local random = W.Button(f, "Randomize story", 130, 24, function()
        local _, comp, char = AR:Selected()
        local companion = (comp and comp.personality and comp.personality.name ~= "" and comp.personality.name) or (char and char.name)
        for key, v in pairs(AR.Random.PlayerStory(companion)) do
            if fields[key] then fields[key]:SetValue(v) end
        end
        status:SetText("Random story filled in - press Save to keep it.")
    end)
    random:SetPoint("RIGHT", save, "LEFT", -8, 0)
    W.Tooltip(random, "Randomize story", "Fills identity, background, interests and shared history with a random story. Name, age and pronouns stay.")

    function f:Load()
        local p = AR.state.profile or {}
        for key, e in pairs(fields) do
            local v = p[key]
            if key == "age" then v = (tonumber(p.age) or 0) > 0 and tostring(p.age) or "" end
            e:SetValue(v or "")
        end
        default:SetChecked(AR.state.profileIsDefault and true or false)
        status:SetText(AR.state.profileIsDefault and "Showing your account-wide profile." or "Showing this character's profile.")
    end

    save:SetScript("OnClick", function()
        local p = {}
        for key, e in pairs(fields) do p[key] = e:GetValue() end
        p.age = tonumber(p.age) or 0
        status:SetText("Saving...")
        AR:Request("save_profile", { profile = p, accountDefault = default:GetChecked() and true or false }, function(msg)
            status:SetText(msg.ok and "|cff60ff60Saved.|r" or "|cffff6060Could not save.|r")
            AR:Request("get_profile")
        end)
    end)

    AR:On("PROFILE_CHANGED", function() if f:IsShown() then f:Load() end end)
    f.OnShowTab = function()
        f:Load()
        AR:Request("get_profile")
    end
end

UI:RegisterTab("profile", "Player Profile", build)
