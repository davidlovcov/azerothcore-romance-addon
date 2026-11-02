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
check(#files == 18, "toc lists 18 files")
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
    quests = { { title = "Kobold Camp Cleanup", level = 7, progress = "Kobold Vermin 4/10", shared = true } },
    available = { { title = "Arcane Instruction", level = 4, giver = "Khelden Bremen", distance = 120, direction = "north-east", classQuest = true } } })
check(AR.state.sheets[2] and AR.state.sheets[2].level == 23, "sheet stored")
stub.Update(11)
check(findOp(drainRequests(), "get_character_sheet") ~= nil, "sheet refreshes while the tab is open")

-- 5d. estrangement status -----------------------------------------------------------
local away = AR:CharStatus({ status = "available", estrangedUntil = time() + 5 * 3600 })
check(away.label:find("Left you") and not away.enabled, "estranged companion cannot be called")
check(AR:CharStatus({ status = "in_party", estranged = true }).label:find("estranged") ~= nil, "cold companion is marked")
check(AR:CharStatus({ status = "in_party" }).label == "In your party", "normal status unchanged")

-- 5e. paged export / import ----------------------------------------------------------
do
    local T = AR.Transfer
    local result
    T:Export(2, nil, function(text, count) result = { text = text, count = count } end)
    local r = findOp(drainRequests(), "export")
    check(r and r.part == 0, "export asks for part 0")
    local function page(i, n, mems) return AR.Json.Encode({ format = "mod-romance-export", page = i, pages = n, companion = "Elara",
        personality = i == 0 and { name = "Elara" } or nil, memories = AR.Json.Array(mems) }) end
    serverSend({ op = "export_data", req = r.req, guid = 2, part = 0, parts = 2, data = page(0, 2, { { text = "a" } }) })
    r = findOp(drainRequests(), "export")
    check(r and r.part == 1, "export asks for the next part")
    serverSend({ op = "export_data", req = r.req, guid = 2, part = 1, parts = 2, data = page(1, 2, { { text = "b" }, { text = "c" } }) })
    check(result and result.count == 3, "export pages joined")
    local full = result and AR.Json.Decode(result.text)
    check(full and full.personality.name == "Elara" and full.memories[3].text == "c" and full.page == nil, "joined export is one clean document")

    -- import: begin, every part acknowledged, end
    local done
    T:Import(2, result.text, nil, function(ok, notes) done = { ok = ok, notes = notes } end)
    local begin = findOp(drainRequests(), "import_begin")
    check(begin and begin.parts >= 1, "import begins with the part count")
    serverSend({ op = "ack", ["for"] = "import_begin", req = begin.req, ok = true })
    for i = 1, begin.parts do
        local part = findOp(drainRequests(), "import_part")
        check(part and part.index == i - 1, "import part " .. i .. " sent in order")
        serverSend({ op = "ack", ["for"] = "import_part", req = part.req, ok = true })
    end
    local fin = findOp(drainRequests(), "import_end")
    check(fin ~= nil, "import ends")
    serverSend({ op = "ack", ["for"] = "import_end", req = fin.req, ok = true, notes = { "3 of 3 memories imported" } })
    check(done and done.ok and done.notes[1]:find("3 of 3"), "import reports the server's result")

    -- "Too many requests" on a part: the same part is sent again after a pause and the import still finishes
    T:Import(2, result.text, nil, function(ok, notes) done = { ok = ok, notes = notes } end)
    begin = findOp(drainRequests(), "import_begin")
    serverSend({ op = "error", code = "rate_limited", ["for"] = "import_begin", req = begin.req, message = "Too many requests, slow down." })
    check(findOp(drainRequests(), "import_begin") == nil, "a rate-limited step waits before it is resent")
    stub.Advance(2)
    stub.Update(0.1)
    begin = findOp(drainRequests(), "import_begin")
    check(begin ~= nil, "a rate-limited step is sent again")
    serverSend({ op = "ack", ["for"] = "import_begin", req = begin.req, ok = true })
    for i = 1, begin.parts do
        local part = findOp(drainRequests(), "import_part")
        serverSend({ op = "ack", ["for"] = "import_part", req = part.req, ok = true })
    end
    fin = findOp(drainRequests(), "import_end")
    serverSend({ op = "ack", ["for"] = "import_end", req = fin.req, ok = true, notes = { "3 of 3 memories imported" } })
    check(done and done.ok, "import completes after a rate-limited step")

    -- a refused part aborts; a silent server times out
    T:Import(2, result.text, nil, function(ok, err) done = { ok = ok, err = err } end)
    begin = findOp(drainRequests(), "import_begin")
    serverSend({ op = "ack", ["for"] = "import_begin", req = begin.req, ok = false, code = "import_too_large", message = "That import is too large." })
    check(done and not done.ok and done.err:find("too large"), "refused import reports the reason")
    T:Export(2, nil, function(text, err) done = { text = text, err = err } end)
    drainRequests()
    stub.Advance(T.TIMEOUT + 1)
    stub.Update(0.1)
    check(done and done.text == nil and tostring(done.err):find("did not answer"), "silent server: export times out")
    check(not T:Busy(), "a failed transfer frees the slot")
    T:Import(2, "{\"format\":\"mod-romance-export\",\"memories\":[", nil, function(ok, err) done = { ok = ok, err = err } end)
    check(done and not done.ok and done.err:find("cut off"), "truncated paste is rejected before sending")

    -- the import dialog: a saved export is preselected and imported without pasting anything
    local MV = AR.MemoryViewer
    AzerothRomanceDB.exports = { Elara = { at = 1000, memories = 3, text = result.text } }
    AzerothRomanceDB.lastExport = "Elara"
    MV:Open(2)
    drainRequests()
    MV:ShowTransfer("import")
    check(AzerothRomanceTransferFrame and AzerothRomanceTransferFrame:IsShown(), "import dialog opens")
    check(MV.transfer.saved:GetValue() == "Elara", "the last saved export is preselected")
    check(#MV.transfer.saved.items == 2, "saved exports are listed")
    -- an export that is too large to show has no text box, only the explanation
    MV:ShowTransfer("export", "", "86 memories, 26.5 KB - too large to show here.")
    check(not MV.transfer.area:IsShown() and MV.transfer.note:IsShown(), "large export: no text box, only the note")
    MV:ShowTransfer("export", "{\"a\":1}", "1 memory")
    check(MV.transfer.area:IsShown() and not MV.transfer.note:IsShown(), "small export: text box shown")
    MV:ShowTransfer("import")
    check(MV.transfer.area:IsShown() and not MV.transfer.note:IsShown(), "import: text box shown again")
    MV:RunImport()
    check(findOp(drainRequests(), "import_begin") ~= nil, "importing a saved export needs no pasting")
    stub.Advance(T.TIMEOUT + 1)
    stub.Update(0.1)
    MV.transfer.saved:SetValue("")
    MV:RunImport()
    check(MV.transfer.status:GetText():find("Choose a saved export"), "nothing chosen: clear hint")
    MV.transfer:Hide()
end

-- 5f. sender pacing stays below the server's limit (20 chunks/s, burst 80) ----------------
do
    local sent = 0
    local s = Protocol.NewSender(function() sent = sent + 1 end)
    for _ = 1, 400 do s.queue[#s.queue + 1] = "x" end
    s:Update(0.01)
    check(sent <= 31, "first burst is limited")
    for _ = 1, 100 do s:Update(0.1) end   -- 10 seconds
    check(sent <= 30 + 10 * 10 + 1, "sustained rate is limited (" .. sent .. " chunks in 10 s)")
    check(sent >= 120, "but keeps sending")
end

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

-- 10b. Playerbots feedback filter ---------------------------------------------------
do
    local F = AR.ChatFilter
    check(F ~= nil and #stub.chatFilters["CHAT_MSG_WHISPER"] == 1, "chat filter registered")
    local feat = AR.state.hello.features
    local savedChars = AR.state.chars
    AR.state.chars = { { guid = 2, name = "Elara", active = true }, { guid = 5, name = "Bob", active = false } }
    feat.botFeedback = nil
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 1), "old server: nothing is hidden")
    feat.botFeedback = true
    serverSend({ op = "chat_msg", guid = 2, from = "companion", text = "Of course, I'm right behind you.  Lead on!", ts = 1 })
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Of course, I'm right behind you. Lead on!", "Elara", 2), "the companion's reply is shown")
    check(not stub.ChatLine("CHAT_MSG_PARTY", "Lead on!", "Elara", 3), "a piece of a long reply is shown")
    local before = #AR:ChatLog(2)
    check(stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 4), "Playerbots feedback is hidden")
    check(stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 4), "same line in a second chat frame is hidden too")
    local log = AR:ChatLog(2)
    check(#log == before + 1 and log[#log].from == "system" and log[#log].text == "Following", "hidden line kept once in the Chat tab")
    check(stub.ChatLine("CHAT_MSG_PARTY", "attack rti target: useless", "Elara-TestRealm", 5), "party feedback with realm name hidden")
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Bob", 6), "bots that aren't active companions are untouched")
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "lol", "Jaina", 7), "real players are untouched")
    serverSend({ op = "bot_feedback", guid = 2, name = "Elara" })
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Strategies: dps, follow", "Elara", 8), "answer to a plain command is shown")
    stub.Advance(F.ALLOW_SECONDS + 1)
    check(stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 9), "later feedback is hidden again")
    stub.Advance(F.EXPECT_SECONDS + 1)
    check(stub.ChatLine("CHAT_MSG_WHISPER", "Lead on!", "Elara", 10), "old replies are forgotten")
    AR.db.hideBotFeedback = false
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 11), "setting off: nothing is hidden")
    AR.db.hideBotFeedback = true
    feat.botFeedback = nil
    AR.state.chars = savedChars
end

-- 10b. a burst of memory_changed (an import, a tidy-up) reloads the open memory list once ---------
do
    local MV = AR.MemoryViewer
    MV:Open(2)
    drainRequests()
    for i = 1, 50 do serverSend({ op = "memory_changed", guid = 2, id = i }) end
    local n, rel = 0, 0
    for _ = 1, 40 do
        stub.Advance(0.1)
        stub.Update(0.1)
        for _, m in ipairs(drainRequests()) do
            if m.op == "get_memories" then
                if m.kind == "relationship" then rel = rel + 1 elseif m.kind == nil then n = n + 1 end
            end
        end
    end
    check(n == 1, "50 memory_changed pushes reload the memory list once (got " .. n .. ")")
    check(rel <= 1, "... and the relationship moments at most once (got " .. rel .. ")")
    MV.frame:Hide()
end

-- 10c. Commands tab: send, party, macros, own commands -------------------------------------
do
    local stub = _G.WOWSTUB
    AR.state.selected = 2
    AzerothRomanceDB.commandTarget = nil
    AR.UI:ShowTab("commands")
    local f = AR.UI.tabs.commands.frame
    check(f and f.builtinButtons and #f.builtinButtons == #AR.BUILTIN_COMMANDS, "commands tab shows all common commands")
    check(AR.UI.tabBarWidth and AR.UI.tabBarWidth <= 780 - 24, "the tabs fit in the window (" .. tostring(AR.UI.tabBarWidth) .. ")")
    drainRequests()
    local lead
    for i, c in ipairs(AR.BUILTIN_COMMANDS) do if c[1] == "Lead the way" then lead = f.builtinButtons[i] end end
    lead:Click()
    local r = findOp(drainRequests(), "chat")
    check(r and r.guid == 2 and r.text == "lead the way", "a command button talks to the selected companion")

    -- party: party chat, and a clear message when not in a party
    AzerothRomanceDB.commandTarget = "party"
    stub.partyMembers = 0
    lead:Click()
    check(#stub.chatSent == 0, "no party chat outside a party")
    stub.partyMembers = 2
    lead:Click()
    check(stub.chatSent[1] and stub.chatSent[1].chatType == "PARTY" and stub.chatSent[1].text == "lead the way", "party target uses party chat")

    -- macros: one on the cursor, names <= 16 characters, updated instead of duplicated
    AzerothRomanceDB.commandTarget = "selected"
    local idx, name = AR:MakeMacro("Lead the way", "lead the way")
    check(idx and stub.macros[idx].body == "/w Elara lead the way" and #name <= 16, "macro whispers the selected companion")
    local again = AR:MakeMacro("Lead the way", "lead the way")
    check(again == idx and #stub.macros == 1, "making it twice updates the same macro")
    AzerothRomanceDB.commandTarget = "party"
    local pidx = AR:MakeMacro("Attack all here", "attack all here")
    check(pidx and stub.macros[pidx].body == "/p attack all here", "party macro uses /p")
    stub.inCombat = true
    check(AR:MakeMacro("Wait here", "wait") == nil, "no macros in combat")
    stub.inCombat = false
    AzerothRomanceDB.commandTarget = "selected"

    -- own commands: add, use, delete
    f:Render()
    f.labelEdit:SetValue("Mine")
    f.textEdit:SetValue("lead me to the mine")
    f.addButton:Click()
    check(AzerothRomanceDB.commands[1] and AzerothRomanceDB.commands[1].text == "lead me to the mine", "own command saved")
    check(f.rows[1].send:IsShown() and f.rows[1].send:GetText() == "Mine" and not f.rows[2].send:IsShown(), "own command listed")
    drainRequests()
    f.rows[1].send:Click()
    r = findOp(drainRequests(), "chat")
    check(r and r.text == "lead me to the mine", "own command is sent")
    f.rows[1].macro:Click()
    check(stub.cursorMacro and stub.macros[stub.cursorMacro].body == "/w Elara lead me to the mine", "own command macro is on the cursor")
    f.rows[1].del:Click()
    check(#AzerothRomanceDB.commands == 0 and not f.rows[1].send:IsShown(), "own command deleted")
    AR.state.selected = nil
end

-- 11. no unexpected UI errors -------------------------------------------------------
local unexpected = {}
for _, e in ipairs(AR.state.errors) do
    if not (e.where == "protocol" or e.where == "get_companion") then unexpected[#unexpected + 1] = e.where .. ": " .. e.msg end
end
check(#unexpected == 0, "no UI errors: " .. table.concat(unexpected, " | "))

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
