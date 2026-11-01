--[[
  Headless test of the AzerothRomance addon (Lua 5.1 + wow_stub.lua).
  Loads every file in .toc order, then drives the UI with simulated server
  traffic through the real wire protocol and checks the requests it sends.

    lua5.1 tests/test_addon.lua AzerothRomance
]]

local addonDir = arg[1] or "AzerothRomance"
local here = arg[0]:match("^(.*)/[^/]+$") or "."
local stub = dofile(here .. "/wow_stub.lua")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end
end

-- load files in .toc order
local files = {}
for line in io.lines(addonDir .. "/AzerothRomance.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^##") then files[#files + 1] = line:gsub("\\", "/") end
end
for _, f in ipairs(files) do
    local chunk, err = loadfile(addonDir .. "/" .. f)
    assert(chunk, err)
    chunk("AzerothRomance", {})
end
check(#files == 15, "toc lists 15 files")
local AR = AzerothRomance
local Protocol = AR.Protocol

-- server side helpers ------------------------------------------------------------
local serverId = 1
local function serverSend(msg)
    serverId = serverId + 1
    for _, chunk in ipairs(Protocol.Encode(msg, serverId)) do
        stub.FireEvent("CHAT_MSG_ADDON", "ARMN", chunk, "WHISPER", "Arthas")
    end
end

local inbound = Protocol.NewReassembler()
local function drainRequests()
    local out = {}
    for _ = 1, 400 do
        stub.Advance(0.05)
        stub.Update(0.05)
        if AR.sender:Pending() == 0 then break end
    end
    for _, s in ipairs(stub.sent) do
        check(s.prefix == "ARMN" and s.channel == "WHISPER" and s.target == "Arthas", "addon message addressed to self via WHISPER")
        local msg, err = inbound:Feed(s.text, 0)
        if msg then out[#out + 1] = msg elseif msg == false then check(false, "client sent malformed chunk: " .. tostring(err)) end
    end
    stub.sent = {}
    return out
end

local function findOp(list, op)
    for _, m in ipairs(list) do if m.op == op then return m end end
end

-- 1. load & login -----------------------------------------------------------------
stub.FireEvent("ADDON_LOADED", "AzerothRomance")
check(type(AzerothRomanceDB) == "table", "saved variables initialized")
check(_G.AzerothRomanceMinimapButton ~= nil, "minimap button created")
stub.FireEvent("PLAYER_LOGIN")
stub.Update(2.5)
local reqs = drainRequests()
local hello = findOp(reqs, "hello")
check(hello ~= nil and hello.protocol == 1, "hello sent after login")

-- 2. server hello + character list -------------------------------------------------
local presetProfile = { name = "", traits = { outgoing = 45, sarcasm = 5 }, styles = AR.Json.Array({ "anime", "sweet" }),
    length = "varied", language = "auto", romanceEnabled = true, stageLabels = AR.Json.Array({ "", "", "", "", "", "", "", "" }) }
serverSend({ op = "hello", req = hello and hello.req, protocol = 1, enabled = true,
    features = { ollama = true, proactive = true, naturalCommands = true, initialStage = true, maxInitialStage = 7,
        modelChoice = true, export = true, reset = true, debug = true, playerbots = true, memory = true },
    presets = { { id = "anime_girlfriend", label = "Anime Girlfriend", description = "Sweet", stage = "dating", profile = presetProfile } },
    stages = { { id = "strangers", label = "Strangers" }, { id = "acquaintances", label = "Acquaintances" }, { id = "friends", label = "Friends" },
        { id = "close_friends", label = "Close Friends" }, { id = "romantic_interest", label = "Romantic Interest" },
        { id = "dating", label = "Dating / Couple" }, { id = "engaged", label = "Engaged" }, { id = "married", label = "Married" } },
    styles = { "anime", "sweet" },
    status = { enabled = true, model = "qwen3.5:4b", ollama = { online = true, checked = true, version = "0.12", models = { "qwen3.5:4b" } } } })
check(AR.state.connected, "connected after hello")
check(AR:OllamaOnline(), "ollama status parsed")

SlashCmdList["AZEROTHROMANCE"]("")
check(AzerothRomanceMainFrame:IsShown(), "/romance opens the window")
reqs = drainRequests()
check(findOp(reqs, "list_chars") ~= nil, "window requests character list")

serverSend({ op = "chars", maxActive = 1, chars = {
    { guid = 2, name = "Elara", race = 1, raceName = "Human", class = 8, className = "Mage", level = 80, status = "available", reason = "Offline", configured = true, stageLabel = "Dating / Couple" },
    { guid = 3, name = "Lyra", race = 4, raceName = "Night Elf", class = 5, className = "Priest", level = 70, status = "online_player", reason = "Logged in by a player." },
} })
check(#AR.state.chars == 2, "character list stored")
check(#AR:ActiveNames() == 0, "no active companion yet")
-- selecting a companion that failed to join must not change the header
AR.state.selected = 3
AR.UI:RefreshStatus()
check((AR.UI.subtitle:GetText() or "") == "", "header empty while nobody is active")
check(AR:AckText({ code = "limit_reached", message = "You already have the maximum number of AI companions (3)." }):find("maximum") ~= nil,
    "readable ack message preferred over code")
check(AR:AckText({ code = "x" }) == "x", "ack code fallback")
AR.state.selected = nil

-- 3. select Elara, receive companion --------------------------------------------------
AR:Select(2)
reqs = drainRequests()
check(findOp(reqs, "get_companion") and findOp(reqs, "get_companion").guid == 2, "get_companion for selection")
check(findOp(reqs, "get_history") ~= nil, "history requested")
local personality = { name = "Elara", nickname = "Ela", age = 24, traits = { outgoing = 25, sarcasm = 5, playfulness = 60 },
    styles = AR.Json.Array({ "anime", "sweet" }), length = "varied", language = "auto", romanceEnabled = true,
    customInstructions = "She is extremely sweet | and loves exploring.", stageLabels = AR.Json.Array({ "", "", "", "", "", "", "", "" }) }
local relationship = { op = "relationship", guid = 2, stage = "dating", stageIndex = 5, stageLabel = "Dating / Couple", romantic = true,
    values = { friendship = 80, affection = 80, attraction = 74, trust = 78, familiarity = 72, comfort = 80, satisfaction = 76 },
    mood = "enjoying_company", labels = { "Strangers", "Acquaintances", "Friends", "Close Friends", "Romantic Interest", "Dating / Couple", "Engaged", "Married" } }
serverSend({ op = "companion", guid = 2, name = "Elara", configured = true, personality = personality,
    settings = { aiEnabled = true, proactiveEnabled = true, proactiveFrequency = 50, naturalCommands = true }, relationship = relationship,
    status = "available", reason = "Offline" })
serverSend({ op = "history", guid = 2, items = { { from = "player", text = "Hi Elara", ts = 1800000000 }, { from = "companion", text = "Hello you~", ts = 1800000005 } } })
check(AR.state.companions[2] ~= nil, "companion stored")
check(AR.state.relationship[2].stageLabel == "Dating / Couple", "relationship stored")

-- 4. every tab builds and shows without errors --------------------------------------
for _, id in ipairs(AR.UI.order) do
    AR.UI:ShowTab(id)
    check(AR.UI.current == id, "tab " .. id .. " shown")
end
drainRequests()

-- 5. personality save round trip ---------------------------------------------------
AR.UI:ShowTab("personality")
local ptab = AR.UI.tabs.personality.frame
local collected = ptab:Collect()
check(collected.name == "Elara" and collected.age == 24, "personality form loaded name/age")
check(collected.traits.outgoing == 25, "trait slider loaded")
local hasAnime = false
for _, s in ipairs(collected.styles) do if s == "anime" then hasAnime = true end end
check(hasAnime, "style checkbox loaded")
-- find the Save button and click it
for _, f in ipairs(WOWSTUB.frames) do
    if f._kind == "Button" and f._text == "Save personality" then f:Click() end
end
reqs = drainRequests()
local sp = findOp(reqs, "save_personality")
check(sp ~= nil, "save_personality sent")
check(sp and sp.personality.age == 24 and sp.personality.customInstructions:find("|", 1, true) ~= nil, "pipe survives the wire (escaped)")
check(sp and sp.guid == 2, "save targets selected companion")

-- 5b. presets: reset, custom presets, randomizers ------------------------------------
local function click(text)
    for _, f in ipairs(WOWSTUB.frames) do
        if f._kind == "Button" and f._text == text then f:Click() return true end
    end
end
personality.preset = "anime_girlfriend"
serverSend({ op = "companion", guid = 2, name = "Elara", configured = true, personality = personality })
drainRequests()
check(click("Reset to preset"), "reset button exists")
reqs = drainRequests()
local ap = findOp(reqs, "apply_preset")
check(ap and ap.preset == "anime_girlfriend" and ap.guid == 2, "reset re-applies the current preset")
check(ptab:Collect().preset == "anime_girlfriend", "saved personality keeps its preset id")

check(click("Save as preset"), "save-as-preset button exists")
check(findOp(drainRequests(), "save_preset") == nil, "no preset without a name")

serverSend({ op = "presets", ok = true, ["for"] = "save_preset", savedId = "custom:1", presets = {
    { id = "anime_girlfriend", label = "Anime Girlfriend", gender = "female", profile = presetProfile },
    { id = "gentle_knight", label = "Gentle Knight", gender = "male", profile = presetProfile },
    { id = "custom:1", label = "Herbalist", custom = true, profile = presetProfile } } })
check(#AR:Presets() == 3 and AR:Presets()[3].custom, "custom presets stored")

check(click("Randomize"), "randomize story button exists")
local story = ptab:Collect()
check(story.background ~= "" and story.likes ~= "" and story.lore ~= "", "random story fills the story fields")
check(story.name == "Elara", "randomize keeps the name")
local female = AR.Random.CompanionStory("female")
local male = AR.Random.CompanionStory("male")
for _, k in ipairs({ "background", "history", "interests", "likes", "dislikes", "goals", "fears", "relationshipPreferences", "lore" }) do
    check(type(female[k]) == "string" and female[k] ~= "", "random companion field " .. k)
end
check(not (female.fears .. female.goals .. female.history):find("%f[%a]they%f[%A]"), "female story uses her pronouns")
check(not (male.fears .. male.goals .. male.history):find("%f[%a]their%f[%A]"), "male story uses his pronouns")
local ps = AR.Random.PlayerStory("Elara")
check(ps.sharedHistory:find("Elara") ~= nil and ps.rpIdentity ~= "", "random player story mentions the companion")
check(click("Undo changes"), "undo button exists")
check(ptab:Collect().background == (personality.background or ""), "undo discards unsaved edits")

-- 5c. character tab --------------------------------------------------------------------
AR.UI:ShowTab("character")
reqs = drainRequests()
local gs = findOp(reqs, "get_character_sheet")
check(gs and gs.guid == 2, "character tab requests the sheet")
serverSend({ op = "character_sheet", req = gs and gs.req, guid = 2, name = "Elara", level = 23, xp = 500, xpNext = 1000, money = 123456,
    health = 90, freeSlots = 3, totalSlots = 64, follow = "lead", leadQuest = "Kobold Camp Cleanup",
    items = { { name = "Linen Cloth", count = 12, quality = 1 }, { name = "Broken Tooth", count = 3, quality = 0 } },
    gear = { { slot = 4, name = "Robe of Power", quality = 3 } },
    spells = { { id = 133, name = "Fireball" } },
    quests = { { title = "Kobold Camp Cleanup", level = 7, progress = "Kobold Vermin 4/10", shared = true } } })
check(AR.state.sheets[2] and AR.state.sheets[2].level == 23, "sheet stored")
stub.Update(11)
check(findOp(drainRequests(), "get_character_sheet") ~= nil, "sheet refreshes while the tab is open")

-- 5d. estrangement status -----------------------------------------------------------
local away = AR:CharStatus({ status = "available", estrangedUntil = time() + 5 * 3600 })
check(away.label:find("Left you") and not away.enabled, "estranged companion cannot be called")
check(AR:CharStatus({ status = "in_party", estranged = true }).label:find("estranged") ~= nil, "cold companion is marked")
check(AR:CharStatus({ status = "in_party" }).label == "In your party", "normal status unchanged")

-- 6. chat: send + typing + reply -----------------------------------------------------
AR.UI:ShowTab("chat")
AzerothRomanceChatInput:SetText("Hey Elara, ready for an adventure?")
AzerothRomanceChatInput:GetScript("OnEnterPressed")(AzerothRomanceChatInput)
reqs = drainRequests()
local chatReq = findOp(reqs, "chat")
check(chatReq and chatReq.text == "Hey Elara, ready for an adventure?", "chat request sent")
check(AR.state.typing[2] == true, "typing indicator on after send")
serverSend({ op = "chat_msg", guid = 2, from = "player", text = "Hey Elara, ready for an adventure?", ts = 1800000100 })
serverSend({ op = "chat_msg", guid = 2, from = "companion", text = "Always! Lead the way~", ts = 1800000102, mood = "excited" })
check(AR.state.typing[2] == nil, "typing cleared by reply")
local log = AR:ChatLog(2)
check(log[#log].text == "Always! Lead the way~", "reply stored in chat log")
AzerothRomanceChatInput:SetText("!follow")
AzerothRomanceChatInput:GetScript("OnEnterPressed")(AzerothRomanceChatInput)
reqs = drainRequests()
check(findOp(reqs, "chat").text == "!follow", "command sent verbatim with ! prefix")
check(AR:ChatLog(2)[#AR:ChatLog(2)].from == "command", "command shown as command, not roleplay")

-- 7. memory viewer ---------------------------------------------------------------
AR.MemoryViewer:Open(2)
reqs = drainRequests()
local gm = findOp(reqs, "get_memories")
check(gm and gm.limit == 10, "memory viewer requests a page")
serverSend({ op = "memories", req = gm and gm.req, guid = 2, total = 2, offset = 0, items = {
    { id = 7, kind = "gift", source = "observed", importance = 80, text = "Arthas gave Elara a Silver Ring of Devotion in Stormwind.", createdAt = 1800000000, pinned = false },
    { id = 3, kind = "preference", source = "player_stated", importance = 50, text = "Arthas likes exploring old ruins.", createdAt = 1799990000, pinned = true },
} })
check(AR.MemoryViewer.rows[1].mem and AR.MemoryViewer.rows[1].mem.id == 7, "memory row rendered")
AR.MemoryViewer.rows[1].del:Click()
reqs = drainRequests()
local del = findOp(reqs, "delete_memory")
check(del and del.id == 7 and del.guid == 2, "delete_memory sent for the right id")

-- 8. relationship stage change asks for confirmation --------------------------------
AR.UI:ShowTab("relationship")
drainRequests()
for _, f in ipairs(WOWSTUB.frames) do
    if f._kind == "Button" and f._text == "Set relationship" then f:Click() end
end
local popup = WOWSTUB.popups[#WOWSTUB.popups]
check(popup and popup.which == "AZEROTHROMANCE_SET_STAGE", "confirmation popup for stage change")
StaticPopupDialogs.AZEROTHROMANCE_SET_STAGE.OnAccept(popup, popup.data)
reqs = drainRequests()
local sr = findOp(reqs, "set_relationship")
check(sr and sr.stage == "dating", "set_relationship sent after confirmation")

-- 9. pacing: a large message stays under the flood limits ----------------------------
local big = {}
for i = 1, 300 do big[#big + 1] = "Elara loves the old ruins of Azeroth. " end
AR:Request("save_personality", { guid = 2, personality = { name = "Elara", background = table.concat(big) } })
local chunks = AR.sender:Pending()
check(chunks > 40, "large message is chunked (" .. chunks .. " chunks)")
local sentPerWindow, maxInOneSecond = {}, 0
local t = 0
while AR.sender:Pending() > 0 and t < 30 do
    local before = #stub.sent
    AR.sender:Update(0.05)
    t = t + 0.05
    local sec = math.floor(t)
    sentPerWindow[sec] = (sentPerWindow[sec] or 0) + (#stub.sent - before)
end
for _, n in pairs(sentPerWindow) do if n > maxInOneSecond then maxInOneSecond = n end end
check(maxInOneSecond <= 40, "never more than 40 chunks per second (" .. maxInOneSecond .. ")")
local msgs = drainRequests()
check(findOp(msgs, "save_personality") ~= nil and #findOp(msgs, "save_personality").personality.background > 10000, "large message reassembles")

-- 10. hostile / malformed server data does not break the addon -----------------------
stub.FireEvent("CHAT_MSG_ADDON", "ARMN", "garbage", "WHISPER", "Arthas")
stub.FireEvent("CHAT_MSG_ADDON", "ARMN", "a:1/1:{\"op\":", "WHISPER", "Arthas")
stub.FireEvent("CHAT_MSG_ADDON", "ARMN", Protocol.Encode({ op = "chat_msg", guid = 2, from = "companion", text = "hi" }, 99)[1], "WHISPER", "Mallory")
check(AR:ChatLog(2)[#AR:ChatLog(2)].text ~= "hi", "messages from other senders are ignored")
serverSend({ op = "error", code = "not_owner", message = "That character does not belong to you.", ["for"] = "get_companion" })
check(#AR.state.errors >= 2, "protocol errors are logged, not thrown")

-- 11. no unexpected UI errors -------------------------------------------------------
local unexpected = {}
for _, e in ipairs(AR.state.errors) do
    if not (e.where == "protocol" or e.where == "get_companion") then unexpected[#unexpected + 1] = e.where .. ": " .. e.msg end
end
check(#unexpected == 0, "no UI errors: " .. table.concat(unexpected, " | "))

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
