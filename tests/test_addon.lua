--[[
  Headless test of the TrueCompanion addon (Lua 5.1 + wow_stub.lua).
  Loads every file in .toc order, then drives the UI with simulated server
  traffic through the real wire protocol and checks the requests it sends.

    lua5.1 tests/test_addon.lua TrueCompanion
]]

local addonDir = arg[1] or "TrueCompanion"
local here = arg[0]:match("^(.*)/[^/]+$") or "."
local stub = dofile(here .. "/wow_stub.lua")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end
end

-- load files in .toc order
local files = {}
for line in io.lines(addonDir .. "/TrueCompanion.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^##") then files[#files + 1] = line:gsub("\\", "/") end
end
for _, f in ipairs(files) do
    local chunk, err = loadfile(addonDir .. "/" .. f)
    assert(chunk, err)
    chunk("TrueCompanion", {})
end
check(#files == 19, "toc lists 19 files")
local TC = TrueCompanion
local Protocol = TC.Protocol

-- server side helpers ------------------------------------------------------------
local serverId = 1
local function serverSend(msg)
    serverId = serverId + 1
    for _, chunk in ipairs(Protocol.Encode(msg, serverId)) do
        stub.FireEvent("CHAT_MSG_ADDON", "TCMP", chunk, "WHISPER", "Arthas")
    end
end

local inbound = Protocol.NewReassembler()
local function drainRequests()
    local out = {}
    for _ = 1, 400 do
        stub.Advance(0.05)
        stub.Update(0.05)
        if TC.sender:Pending() == 0 then break end
    end
    for _, s in ipairs(stub.sent) do
        check(s.prefix == "TCMP" and s.channel == "WHISPER" and s.target == "Arthas", "addon message addressed to self via WHISPER")
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
-- settings saved by AzerothRomance (before the rename) are taken over
AzerothRomanceDB = { commands = { { label = "Old", text = "an old command" } } }
stub.FireEvent("ADDON_LOADED", "TrueCompanion")
check(TrueCompanionDB.commands and TrueCompanionDB.commands[1].text == "an old command" and AzerothRomanceDB == nil,
    "settings from AzerothRomance are taken over once")
TrueCompanionDB.commands = nil
check(type(TrueCompanionDB) == "table", "saved variables initialized")
check(_G.TrueCompanionMinimapButton ~= nil, "minimap button created")
stub.FireEvent("PLAYER_LOGIN")
stub.Update(2.5)
local reqs = drainRequests()
local hello = findOp(reqs, "hello")
check(hello ~= nil and hello.protocol == 1, "hello sent after login")

-- 2. server hello + character list -------------------------------------------------
local presetProfile = { name = "", traits = { outgoing = 45, sarcasm = 5 }, styles = TC.Json.Array({ "anime", "sweet" }),
    length = "varied", language = "auto", romanceEnabled = true, stageLabels = TC.Json.Array({ "", "", "", "", "", "", "", "" }) }
serverSend({ op = "hello", req = hello and hello.req, protocol = 1, enabled = true,
    features = { ollama = true, proactive = true, naturalCommands = true, initialStage = true, maxInitialStage = 7,
        modelChoice = true, export = true, reset = true, debug = true, playerbots = true, memory = true },
    presets = { { id = "anime_girlfriend", label = "Anime Girlfriend", description = "Sweet", stage = "dating", profile = presetProfile } },
    stages = { { id = "strangers", label = "Strangers" }, { id = "acquaintances", label = "Acquaintances" }, { id = "friends", label = "Friends" },
        { id = "close_friends", label = "Close Friends" }, { id = "romantic_interest", label = "Romantic Interest" },
        { id = "dating", label = "Dating / Couple" }, { id = "engaged", label = "Engaged" }, { id = "married", label = "Married" } },
    styles = { "anime", "sweet" },
    status = { enabled = true, model = "qwen3.5:4b", ollama = { online = true, checked = true, version = "0.12", models = { "qwen3.5:4b" } } } })
check(TC.state.connected, "connected after hello")
check(TC:OllamaOnline(), "ollama status parsed")

SlashCmdList["TRUECOMPANION"]("")
check(TrueCompanionMainFrame:IsShown(), "/tc opens the window")
reqs = drainRequests()
check(findOp(reqs, "list_chars") ~= nil, "window requests character list")

serverSend({ op = "chars", maxActive = 1, chars = {
    { guid = 2, name = "Elara", race = 1, raceName = "Human", class = 8, className = "Mage", level = 80, status = "available", reason = "Offline", configured = true, stageLabel = "Dating / Couple" },
    { guid = 3, name = "Lyra", race = 4, raceName = "Night Elf", class = 5, className = "Priest", level = 70, status = "online_player", reason = "Logged in by a player." },
} })
check(#TC.state.chars == 2, "character list stored")
check(#TC:ActiveNames() == 0, "no active companion yet")
-- selecting a companion that failed to join must not change the header
TC.state.selected = 3
TC.UI:RefreshStatus()
check((TC.UI.subtitle:GetText() or "") == "", "header empty while nobody is active")
check(TC:AckText({ code = "limit_reached", message = "You already have the maximum number of AI companions (3)." }):find("maximum") ~= nil,
    "readable ack message preferred over code")
check(TC:AckText({ code = "x" }) == "x", "ack code fallback")
TC.state.selected = nil

-- 3. select Elara, receive companion --------------------------------------------------
TC:Select(2)
reqs = drainRequests()
check(findOp(reqs, "get_companion") and findOp(reqs, "get_companion").guid == 2, "get_companion for selection")
check(findOp(reqs, "get_history") ~= nil, "history requested")
local personality = { name = "Elara", nickname = "Ela", age = 24, traits = { outgoing = 25, sarcasm = 5, playfulness = 60 },
    styles = TC.Json.Array({ "anime", "sweet" }), length = "varied", language = "auto", romanceEnabled = true,
    customInstructions = "She is extremely sweet | and loves exploring.", stageLabels = TC.Json.Array({ "", "", "", "", "", "", "", "" }) }
local relationship = { op = "relationship", guid = 2, stage = "dating", stageIndex = 5, stageLabel = "Dating / Couple", romantic = true,
    values = { friendship = 80, affection = 80, attraction = 74, trust = 78, familiarity = 72, comfort = 80, satisfaction = 76 },
    mood = "enjoying_company", labels = { "Strangers", "Acquaintances", "Friends", "Close Friends", "Romantic Interest", "Dating / Couple", "Engaged", "Married" } }
serverSend({ op = "companion", guid = 2, name = "Elara", configured = true, personality = personality,
    settings = { aiEnabled = true, proactiveEnabled = true, proactiveFrequency = 50, naturalCommands = true }, relationship = relationship,
    status = "available", reason = "Offline" })
serverSend({ op = "history", guid = 2, items = { { from = "player", text = "Hi Elara", ts = 1800000000 }, { from = "companion", text = "Hello you~", ts = 1800000005 } } })
check(TC.state.companions[2] ~= nil, "companion stored")
check(TC.state.relationship[2].stageLabel == "Dating / Couple", "relationship stored")

-- 4. every tab builds and shows without errors --------------------------------------
for _, id in ipairs(TC.UI.order) do
    TC.UI:ShowTab(id)
    check(TC.UI.current == id, "tab " .. id .. " shown")
end
drainRequests()

-- 5. personality save round trip ---------------------------------------------------
TC.UI:ShowTab("personality")
local ptab = TC.UI.tabs.personality.frame
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
check(#TC:Presets() == 3 and TC:Presets()[3].custom, "custom presets stored")

check(click("Randomize"), "randomize story button exists")
local story = ptab:Collect()
check(story.background ~= "" and story.likes ~= "" and story.lore ~= "", "random story fills the story fields")
check(story.name == "Elara", "randomize keeps the name")
local female = TC.Random.CompanionStory("female")
local male = TC.Random.CompanionStory("male")
for _, k in ipairs({ "background", "history", "interests", "likes", "dislikes", "goals", "fears", "relationshipPreferences", "lore" }) do
    check(type(female[k]) == "string" and female[k] ~= "", "random companion field " .. k)
end
check(not (female.fears .. female.goals .. female.history):find("%f[%a]they%f[%A]"), "female story uses her pronouns")
check(not (male.fears .. male.goals .. male.history):find("%f[%a]their%f[%A]"), "male story uses his pronouns")
local ps = TC.Random.PlayerStory("Elara")
check(ps.sharedHistory:find("Elara") ~= nil and ps.rpIdentity ~= "", "random player story mentions the companion")
check(click("Undo changes"), "undo button exists")
check(ptab:Collect().background == (personality.background or ""), "undo discards unsaved edits")

-- 5c. character tab --------------------------------------------------------------------
TC.UI:ShowTab("character")
reqs = drainRequests()
local gs = findOp(reqs, "get_character_sheet")
check(gs and gs.guid == 2, "character tab requests the sheet")
serverSend({ op = "character_sheet", req = gs and gs.req, guid = 2, name = "Elara", level = 23, xp = 500, xpNext = 1000, money = 123456,
    health = 90, freeSlots = 3, totalSlots = 64, follow = "lead", leadQuest = "Kobold Camp Cleanup",
    items = { { name = "Linen Cloth", count = 12, quality = 1 }, { name = "Broken Tooth", count = 3, quality = 0 } },
    gear = { { slot = 4, name = "Robe of Power", quality = 3 } },
    spells = { { id = 133, name = "Fireball" } },
    learnable = { { id = 116, name = "Frostbolt", rank = "Rank 3", cost = 1800, level = 22 } }, learnableCost = 1800,
    learnSoon = { { id = 2136, name = "Fire Blast", rank = "Rank 3", cost = 2000, level = 24 } },
    quests = { { title = "Kobold Camp Cleanup", level = 7, progress = "Kobold Vermin 4/10", shared = true } },
    available = { { title = "Arcane Instruction", level = 4, giver = "Khelden Bremen", distance = 120, direction = "north-east", classQuest = true } } })
check(TC.state.sheets[2] and TC.state.sheets[2].level == 23, "sheet stored")
do
    local box = TC.UI.tabs.character.frame.spellsBox
    local t = box.text:GetText()
    check(t:find("Can learn now") and t:find("Frostbolt") and t:find("18s") and t:find("Soon") and t:find("level 24") and t:find("Fireball"),
        "spells to learn now (with cost) and soon are listed above the known ones")
    check(box.head:GetText():find("%+1 to learn"), "the spell list heading counts what she can learn")
end
stub.Update(11)
check(findOp(drainRequests(), "get_character_sheet") ~= nil, "sheet refreshes while the tab is open")

-- 5d. estrangement status -----------------------------------------------------------
local away = TC:CharStatus({ status = "available", estrangedUntil = time() + 5 * 3600 })
check(away.label:find("Left you") and not away.enabled, "estranged companion cannot be called")
check(TC:CharStatus({ status = "in_party", estranged = true }).label:find("estranged") ~= nil, "cold companion is marked")
check(TC:CharStatus({ status = "in_party" }).label == "In your party", "normal status unchanged")

-- 5e. paged export / import ----------------------------------------------------------
do
    local T = TC.Transfer
    local result
    T:Export(2, nil, function(text, count) result = { text = text, count = count } end)
    local r = findOp(drainRequests(), "export")
    check(r and r.part == 0, "export asks for part 0")
    local function page(i, n, mems) return TC.Json.Encode({ format = "mod-true-companion-export", page = i, pages = n, companion = "Elara",
        personality = i == 0 and { name = "Elara" } or nil, memories = TC.Json.Array(mems) }) end
    serverSend({ op = "export_data", req = r.req, guid = 2, part = 0, parts = 2, data = page(0, 2, { { text = "a" } }) })
    r = findOp(drainRequests(), "export")
    check(r and r.part == 1, "export asks for the next part")
    serverSend({ op = "export_data", req = r.req, guid = 2, part = 1, parts = 2, data = page(1, 2, { { text = "b" }, { text = "c" } }) })
    check(result and result.count == 3, "export pages joined")
    local full = result and TC.Json.Decode(result.text)
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
    T:Import(2, "{\"format\":\"mod-true-companion-export\",\"memories\":[", nil, function(ok, err) done = { ok = ok, err = err } end)
    check(done and not done.ok and done.err:find("cut off"), "truncated paste is rejected before sending")

    -- the import dialog: a saved export is preselected and imported without pasting anything
    local MV = TC.MemoryViewer
    TrueCompanionDB.exports = { Elara = { at = 1000, memories = 3, text = result.text } }
    TrueCompanionDB.lastExport = "Elara"
    MV:Open(2)
    drainRequests()
    MV:ShowTransfer("import")
    check(TrueCompanionTransferFrame and TrueCompanionTransferFrame:IsShown(), "import dialog opens")
    check(MV.transfer.saved:GetValue() == "Elara", "the last saved export is preselected")
    check(#MV.transfer.saved.items == 2, "saved exports are listed")
    -- new exports: per realm and companion, several backups, older saved exports kept
    local realExport = TC.Transfer.Export
    TC.Transfer.Export = function(_, guid, onProgress, onDone) onDone("{\"format\":\"mod-true-companion-export\"}", 3) end
    for i = 1, 4 do
        stub.Advance(10)
        MV:Export()
    end
    local mine, old = 0, TrueCompanionDB.exports.Elara ~= nil
    for k, e in pairs(TrueCompanionDB.exports) do
        if e.realm == "TestRealm" and tostring(e.guid) == "2" then mine = mine + 1 end
    end
    check(mine == 3, "the newest three exports of a companion are kept")
    check(old, "an export saved by an older version is kept")
    check(TrueCompanionDB.lastExport:find("^TestRealm#2#"), "the last export is keyed by realm and companion")
    TrueCompanionDB.exports["OtherRealm#2#5"] = { name = "Elara", realm = "OtherRealm", guid = 2, at = 5, memories = 1, text = "{}" }
    MV:ShowTransfer("import")
    local otherShown = false
    for _, it in ipairs(MV.transfer.saved.items) do
        if it.value == "OtherRealm#2#5" then otherShown = it.text:find("Elara %(OtherRealm%)") ~= nil end
    end
    check(otherShown, "the same name on another realm is its own entry, marked with the realm")
    TC.Transfer.Export = realExport
    TrueCompanionDB.exports = { Elara = { at = 1000, memories = 3, text = result.text } }
    TrueCompanionDB.lastExport = "Elara"
    MV:ShowTransfer("import")
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
TC.UI:ShowTab("chat")
TrueCompanionChatInput:SetText("Hey Elara, ready for an adventure?")
TrueCompanionChatInput:GetScript("OnEnterPressed")(TrueCompanionChatInput)
reqs = drainRequests()
local chatReq = findOp(reqs, "chat")
check(chatReq and chatReq.text == "Hey Elara, ready for an adventure?", "chat request sent")
check(TC.state.typing[2] == true, "typing indicator on after send")
serverSend({ op = "chat_msg", guid = 2, from = "player", text = "Hey Elara, ready for an adventure?", ts = 1800000100 })
serverSend({ op = "chat_msg", guid = 2, from = "companion", text = "Always! Lead the way~", ts = 1800000102, mood = "excited" })
check(TC.state.typing[2] == nil, "typing cleared by reply")
local log = TC:ChatLog(2)
check(log[#log].text == "Always! Lead the way~", "reply stored in chat log")
TrueCompanionChatInput:SetText("!follow")
TrueCompanionChatInput:GetScript("OnEnterPressed")(TrueCompanionChatInput)
reqs = drainRequests()
check(findOp(reqs, "chat").text == "!follow", "command sent verbatim with ! prefix")
check(TC:ChatLog(2)[#TC:ChatLog(2)].from == "command", "command shown as command, not roleplay")

-- 7. memory viewer ---------------------------------------------------------------
TC.MemoryViewer:Open(2)
reqs = drainRequests()
local gm = findOp(reqs, "get_memories")
check(gm and gm.limit == 10, "memory viewer requests a page")
serverSend({ op = "memories", req = gm and gm.req, guid = 2, total = 2, offset = 0, items = {
    { id = 7, kind = "gift", source = "observed", importance = 80, text = "Arthas gave Elara a Silver Ring of Devotion in Stormwind.", createdAt = 1800000000, pinned = false },
    { id = 3, kind = "preference", source = "player_stated", importance = 50, text = "Arthas likes exploring old ruins.", createdAt = 1799990000, pinned = true },
} })
check(TC.MemoryViewer.rows[1].mem and TC.MemoryViewer.rows[1].mem.id == 7, "memory row rendered")
TC.MemoryViewer.rows[1].del:Click()
reqs = drainRequests()
local del = findOp(reqs, "delete_memory")
check(del and del.id == 7 and del.guid == 2, "delete_memory sent for the right id")

-- 8. relationship stage change asks for confirmation --------------------------------
TC.UI:ShowTab("relationship")
drainRequests()
for _, f in ipairs(WOWSTUB.frames) do
    if f._kind == "Button" and f._text == "Set relationship" then f:Click() end
end
local popup = WOWSTUB.popups[#WOWSTUB.popups]
check(popup and popup.which == "TRUECOMPANION_SET_STAGE", "confirmation popup for stage change")
StaticPopupDialogs.TRUECOMPANION_SET_STAGE.OnAccept(popup, popup.data)
reqs = drainRequests()
local sr = findOp(reqs, "set_relationship")
check(sr and sr.stage == "dating", "set_relationship sent after confirmation")

-- 9. pacing: a large message stays under the flood limits ----------------------------
local big = {}
for i = 1, 300 do big[#big + 1] = "Elara loves the old ruins of Azeroth. " end
TC:Request("save_personality", { guid = 2, personality = { name = "Elara", background = table.concat(big) } })
local chunks = TC.sender:Pending()
check(chunks > 40, "large message is chunked (" .. chunks .. " chunks)")
local sentPerWindow, maxInOneSecond = {}, 0
local t = 0
while TC.sender:Pending() > 0 and t < 30 do
    local before = #stub.sent
    TC.sender:Update(0.05)
    t = t + 0.05
    local sec = math.floor(t)
    sentPerWindow[sec] = (sentPerWindow[sec] or 0) + (#stub.sent - before)
end
for _, n in pairs(sentPerWindow) do if n > maxInOneSecond then maxInOneSecond = n end end
check(maxInOneSecond <= 40, "never more than 40 chunks per second (" .. maxInOneSecond .. ")")
local msgs = drainRequests()
check(findOp(msgs, "save_personality") ~= nil and #findOp(msgs, "save_personality").personality.background > 10000, "large message reassembles")

-- 10. hostile / malformed server data does not break the addon -----------------------
stub.FireEvent("CHAT_MSG_ADDON", "TCMP", "garbage", "WHISPER", "Arthas")
stub.FireEvent("CHAT_MSG_ADDON", "TCMP", "a:1/1:{\"op\":", "WHISPER", "Arthas")
stub.FireEvent("CHAT_MSG_ADDON", "TCMP", Protocol.Encode({ op = "chat_msg", guid = 2, from = "companion", text = "hi" }, 99)[1], "WHISPER", "Mallory")
check(TC:ChatLog(2)[#TC:ChatLog(2)].text ~= "hi", "messages from other senders are ignored")
serverSend({ op = "error", code = "not_owner", message = "That character does not belong to you.", ["for"] = "get_companion" })
check(#TC.state.errors >= 2, "protocol errors are logged, not thrown")

-- 10b. Playerbots feedback filter ---------------------------------------------------
do
    local F = TC.ChatFilter
    check(F ~= nil and #stub.chatFilters["CHAT_MSG_WHISPER"] == 1, "chat filter registered")
    local feat = TC.state.hello.features
    local savedChars = TC.state.chars
    TC.state.chars = { { guid = 2, name = "Elara", active = true }, { guid = 5, name = "Bob", active = false } }
    feat.botFeedback = nil
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 1), "old server: nothing is hidden")
    feat.botFeedback = true
    serverSend({ op = "chat_msg", guid = 2, from = "companion", text = "Of course, I'm right behind you.  Lead on!", ts = 1 })
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Of course, I'm right behind you. Lead on!", "Elara", 2), "the companion's reply is shown")
    check(not stub.ChatLine("CHAT_MSG_PARTY", "Lead on!", "Elara", 3), "a piece of a long reply is shown")
    local before = #TC:ChatLog(2)
    check(stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 4), "Playerbots feedback is hidden")
    check(stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 4), "same line in a second chat frame is hidden too")
    local log = TC:ChatLog(2)
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
    TC.db.hideBotFeedback = false
    check(not stub.ChatLine("CHAT_MSG_WHISPER", "Following", "Elara", 11), "setting off: nothing is hidden")
    TC.db.hideBotFeedback = true
    feat.botFeedback = nil
    TC.state.chars = savedChars
end

-- 10b. a burst of memory_changed (an import, a tidy-up) reloads the open memory list once ---------
do
    local MV = TC.MemoryViewer
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
    TC.state.selected = 2
    TrueCompanionDB.commandTarget = nil
    TC.UI:ShowTab("commands")
    local f = TC.UI.tabs.commands.frame
    check(f and f.builtinButtons and #f.builtinButtons == #TC.BUILTIN_COMMANDS, "commands tab shows all common commands")
    check(TC.UI.tabBarWidth and TC.UI.tabBarWidth <= 780 - 24, "the tabs fit in the window (" .. tostring(TC.UI.tabBarWidth) .. ")")
    drainRequests()
    local lead
    for i, c in ipairs(TC.BUILTIN_COMMANDS) do if c[1] == "Lead the way" then lead = f.builtinButtons[i] end end
    lead:Click()
    local r = findOp(drainRequests(), "chat")
    check(r and r.guid == 2 and r.text == "lead the way", "a command button talks to the selected companion")

    -- party: party chat, and a clear message when not in a party
    TrueCompanionDB.commandTarget = "party"
    stub.partyMembers = 0
    lead:Click()
    check(#stub.chatSent == 0, "no party chat outside a party")
    stub.partyMembers = 2
    lead:Click()
    check(stub.chatSent[1] and stub.chatSent[1].chatType == "PARTY" and stub.chatSent[1].text == "lead the way", "party target uses party chat")

    -- macros: one on the cursor, names <= 16 characters, updated instead of duplicated
    TrueCompanionDB.commandTarget = "selected"
    local idx, name = TC:MakeMacro("Lead the way", "lead the way")
    check(idx and stub.macros[idx].body == "/w Elara lead the way" and #name <= 16, "macro whispers the selected companion")
    local again = TC:MakeMacro("Lead the way", "lead the way")
    check(again == idx and #stub.macros == 1, "making it twice updates the same macro")
    TrueCompanionDB.commandTarget = "party"
    local pidx = TC:MakeMacro("Attack all here", "attack all here")
    check(pidx and stub.macros[pidx].body == "/p attack all here", "party macro uses /p")
    stub.inCombat = true
    check(TC:MakeMacro("Wait here", "wait") == nil, "no macros in combat")
    stub.inCombat = false
    TrueCompanionDB.commandTarget = "selected"

    -- own commands: add, use, delete
    f:Render()
    f.labelEdit:SetValue("Mine")
    f.textEdit:SetValue("lead me to the mine")
    f.addButton:Click()
    check(TrueCompanionDB.commands[1] and TrueCompanionDB.commands[1].text == "lead me to the mine", "own command saved")
    check(f.rows[1].send:IsShown() and f.rows[1].send:GetText() == "Mine" and not f.rows[2].send:IsShown(), "own command listed")
    drainRequests()
    f.rows[1].send:Click()
    r = findOp(drainRequests(), "chat")
    check(r and r.text == "lead me to the mine", "own command is sent")
    f.rows[1].macro:Click()
    check(stub.cursorMacro and stub.macros[stub.cursorMacro].body == "/w Elara lead me to the mine", "own command macro is on the cursor")
    f.rows[1].del:Click()
    check(#TrueCompanionDB.commands == 0 and not f.rows[1].send:IsShown(), "own command deleted")

    -- "Send to": every companion who is with you, not only the selected one
    local savedChars = TC.state.chars
    TC.state.chars = { { guid = 2, name = "Elara", active = true }, { guid = 3, name = "Lyra", active = true },
                       { guid = 5, name = "Bob", active = false } }
    f:Render()
    local values = {}
    for _, it in ipairs(f.toDropdown.items) do values[it.value] = it.text end
    check(values["2"] == "Elara" and values["3"] == "Lyra" and values["party"] and not values["5"],
        "Send to lists every called companion and party chat, not the others")
    check(f.toDropdown:GetValue() == "2", "Send to starts with the selected companion")
    TrueCompanionDB.commandTarget = "3"
    drainRequests()
    lead:Click()
    r = findOp(drainRequests(), "chat")
    check(r and r.guid == 3 and r.text == "lead the way", "a command goes to the companion chosen under Send to")
    local li = TC:MakeMacro("Wait here", "wait")
    check(li and stub.macros[li].body == "/w Lyra wait", "macros whisper the chosen companion")
    TC.state.chars[2].active = false   -- Lyra dismissed: back to the selected companion
    drainRequests()
    lead:Click()
    r = findOp(drainRequests(), "chat")
    check(r and r.guid == 2, "a dismissed companion is no longer the target (the selected one is)")
    TC.state.selected = 5
    f:Render()
    values = {}
    for _, it in ipairs(f.toDropdown.items) do values[it.value] = it.text end
    check(values["5"] == "Bob (not called)", "a selected companion who isn't called is still shown as the target")
    TC.state.selected = nil
    TrueCompanionDB.commandTarget = nil
    drainRequests()
    lead:Click()
    check(findOp(drainRequests(), "chat") == nil and f.status:GetText():find("Send to"), "no target: nothing sent, and why")
    TC.state.chars = savedChars
    TC.state.selected = nil
end

-- 10c2. two tab rows: general tabs, then the ones about the selected companion ------------------
do
    local UI = TC.UI
    for _, id in ipairs({ "chat", "character", "personality", "relationship", "settings" }) do
        check(UI.tabs[id].opts.group == "companion", id .. " is a companion tab")
    end
    for _, id in ipairs({ "companion", "commands", "quests", "profile" }) do
        check(UI.tabs[id].opts.group == nil, id .. " is a general tab")
    end
    check(UI.tabs.chat.button:GetParent() ~= UI.tabs.commands.button:GetParent(), "companion tabs are on their own row")
    check(UI.companionBarWidth and UI.companionBarWidth <= 780 - 24, "the companion tabs fit in the window (" .. tostring(UI.companionBarWidth) .. ")")
    TC.state.selected = 2
    TC:Fire("SELECTION_CHANGED", 2)
    check(UI.companionLabel:GetText():find("Elara"), "the companion row names the selected companion")
    TC.state.selected = nil
    TC:Fire("SELECTION_CHANGED", nil)
    check(UI.companionLabel:GetText():find("No companion"), "... or says none is selected")
    UI:ShowTab("settings")
    check(UI.tabs.settings.frame:IsShown(), "a companion tab still opens without a selection")
end

-- 10d. Quests tab: group quests, order + apply, ignore, abandon, lead -----------------------
do
    local stub = _G.WOWSTUB
    TC.state.selected = 2
    TrueCompanionDB.ignoredQuests = nil
    TC.UI:ShowTab("quests")
    local f = TC.UI.tabs.quests.frame
    local r = findOp(drainRequests(), "get_group_quests")
    check(r ~= nil, "Quests tab asks for the group's quests")
    serverSend({ op = "group_quests", req = r.req, levelCap = 4, companions = 2,
        quests = {
            { id = 101, title = "Reclaiming Sunstrider Isle", level = 1, who = { { name = "Arthas", player = true, done = true }, { name = "Elara", done = true } } },
            { id = 102, title = "Unfortunate Measures", level = 3, who = { { name = "Elara", done = false } } },
            { id = 103, title = "Windows to the Source", level = 2, who = { { name = "Arthas", player = true, done = false } } } },
        available = { { id = 201, title = "Thirst Unending", level = 3, giver = "Arcanist Helion", distance = 40, direction = "north" } } })
    check(f.rows[1].text:GetText():find("Reclaiming") and f.rows[2].text:IsShown() and not f.rows[4].text:IsShown(), "group quests listed")
    check(f.rows[1].text:GetText():find("you %(done%)") ~= nil, "who has it and who is done is shown")
    check(not f.apply:IsEnabled(), "Apply is off until the order changes")
    f.rows[1].down:Click()
    check(f.apply:IsEnabled() and f.rows[1].text:GetText():find("Unfortunate"), "Down changes the order locally")
    check(findOp(drainRequests(), "set_group_quest_order") == nil, "nothing is sent before Apply")
    f.apply:Click()
    r = findOp(drainRequests(), "set_group_quest_order")
    check(r and r.apply == true and r.quests[1] == 102 and r.quests[2] == 101 and r.quests[3] == 103, "Apply sends the new order")

    -- ignore: kept per character, sent to the server
    f.arows[1].ignore:Click()
    r = findOp(drainRequests(), "set_ignored_quests")
    check(r and r.quests[1] == 201, "ignoring an available quest is sent")
    check(f.arows[1].ignore:GetText() == "Unignore", "ignored quest can be unignored")
    check(TrueCompanionDB.ignoredQuests[TC:CharKey()][201] ~= nil, "ignored quests are saved")
    f.arows[1].ignore:Click()
    r = findOp(drainRequests(), "set_ignored_quests")
    check(r and #r.quests == 0, "unignore is sent")

    -- abandon: two clicks; only for quests a companion has
    local abandonRow
    for i = 1, 3 do if f.rows[i].text:GetText():find("Windows") then abandonRow = f.rows[i] end end
    check(not abandonRow.abandon:IsEnabled(), "no Abandon for a quest only you have")
    f.rows[1].abandon:Click()
    check(findOp(drainRequests(), "abandon_quest") == nil and f.rows[1].abandon:GetText() == "Sure?", "first Abandon click only asks")
    f.rows[1].abandon:Click()
    r = findOp(drainRequests(), "abandon_quest")
    check(r and r.quest == 102, "second click abandons it for the companions")

    -- lead: the selected companion leads there now
    f.rows[2].lead:Click()
    local chat = findOp(drainRequests(), "chat")
    check(chat and chat.guid == 2 and chat.text == "lead me to Reclaiming Sunstrider Isle", "Lead asks the selected companion")

    -- layout: the panels, rows, paging and the Refresh button don't overlap
    local function top(w) return w._points[1][#w._points[1]] end   -- y offset of the TOPLEFT point
    local topEnd = top(f.topPanel) - f.topPanel:GetHeight()
    check(top(f.bottomPanel) <= topEnd, "the available panel starts below the group panel")
    local contentHeight = 562 - 106 - 12
    check(top(f.bottomPanel) - f.bottomPanel:GetHeight() <= 0 and
          -(top(f.bottomPanel) - f.bottomPanel:GetHeight()) <= contentHeight - 6 - f.refresh:GetHeight(),
          "the available panel ends above the Refresh button")
    local lastAvail = f.arows[#f.arows].take
    check(-(top(lastAvail)) + lastAvail:GetHeight() <= f.bottomPanel:GetHeight() - 4 - 18, "the last available row ends above the paging")
    local lastRow = f.rows[#f.rows].abandon
    check(-(top(lastRow)) + lastRow:GetHeight() <= f.topPanel:GetHeight() - 4 - 18, "the last quest row ends above the paging")
    check(f.rows[1].abandon._points[1][2] + f.rows[1].abandon:GetWidth() <= 756, "the row buttons fit in the panel")

    -- share: only when it can be shared and someone lacks it
    TC.state.selected = 2
    local Q = TC.GroupQuests
    Q:Load({ levelCap = 4, companions = 2,
        quests = {
            { id = 101, title = "Reclaiming Sunstrider Isle", level = 1, sharable = true, missing = {},
              who = { { name = "Arthas", player = true, done = true }, { name = "Elara", done = true } } },
            { id = 102, title = "Unfortunate Measures", level = 3, sharable = true, missing = { "you", "Lyra" }, who = { { name = "Elara" } } },
            { id = 104, title = "Class Call", level = 3, sharable = false, missing = { "Lyra" }, who = { { name = "Elara" } } } },
        available = {
            { id = 201, title = "Thirst Unending", level = 3, giver = "Arcanist Helion", distance = 40, direction = "north",
              takers = { "Elara", "Lyra" }, you = true },
            { id = 202, title = "Aggression", level = 9, giver = "Lanthan Perilon", distance = 12, direction = "east",
              takers = {}, you = true, tooHigh = true },
            { id = 203, title = "Nobody's", level = 2, giver = "Someone", distance = 5, direction = "west", takers = {}, you = false } } })
    Q.page, Q.availPage = 1, 1
    f:Render()
    local function row(title)
        for i = 1, #f.rows do if (f.rows[i].text:GetText() or ""):find(title) then return f.rows[i] end end
    end
    local function arow(title)
        for i = 1, #f.arows do if (f.arows[i].text:GetText() or ""):find(title) then return f.arows[i] end end
    end
    check(row("Unfortunate") and row("Unfortunate").share:IsEnabled(), "Share is on when someone lacks a sharable quest")
    check(row("Reclaiming") and not row("Reclaiming").share:IsEnabled(), "Share is off when everyone has it")
    check(row("Class Call") and not row("Class Call").share:IsEnabled(), "Share is off for a quest that can't be shared")
    drainRequests()
    row("Unfortunate").share:Click()
    r = findOp(drainRequests(), "share_quest")
    check(r and r.quest == 102, "Share sends the quest")
    serverSend({ op = "ack", req = r.req, result = "Lyra took it; you got it shared." })
    check(f.status:GetText():find("Lyra took it"), "the result of Share is shown")

    -- take: who can take it, and the companions take it
    check(arow("Thirst") and arow("Thirst").text:GetText():find("Elara, Lyra, you"), "who can take an available quest is shown")
    check(arow("Nobody") and arow("Nobody").text:GetText():find("nobody can take it"), "... or that nobody can")
    check(arow("Thirst").take:IsEnabled() and not arow("Aggression").take:IsEnabled() and not arow("Nobody").take:IsEnabled(),
        "Take is only on when a companion can take it")
    Q:ToggleIgnore(201, "Thirst Unending")
    drainRequests()
    f:Render()
    arow("Thirst").take:Click()
    local reqs = drainRequests()
    local ig, tk = findOp(reqs, "set_ignored_quests"), findOp(reqs, "take_quest")
    check(tk and tk.quest == 201 and tk.guid == 2, "Take sends the quest and the selected companion")
    check(ig and #ig.quests == 0 and Q:Ignored()[201] == nil, "taking an ignored quest unignores it")
    serverSend({ op = "ack", req = tk.req, result = "Elara leads you to Arcanist Helion to take \"Thirst Unending\"." })
    check(f.status:GetText():find("leads you to Arcanist Helion"), "the result of Take is shown")
    -- an older server sends no takers / sharable: say so instead of "nobody can take it"
    Q:Load({ levelCap = 4, companions = 1, quests = { { id = 102, title = "Unfortunate Measures", level = 3, who = { { name = "Elara" } } } },
        available = { { id = 201, title = "Thirst Unending", level = 3, giver = "Arcanist Helion", distance = 40, direction = "north" } } })
    f:Render()
    check(arow("Thirst").text:GetText():find("server too old") and not arow("Thirst").take:IsEnabled(), "old server: Take explains why it is off")

    -- an edit made while a refresh is on its way is not undone by its answer
    local function ids() local out = {} for _, q in ipairs(Q.quests) do out[#out + 1] = q.id end return table.concat(out, ",") end
    local function questsMsg(list, extra)
        local m = { op = "group_quests", levelCap = 4, companions = 1, quests = {} }
        for _, q in ipairs(list) do m.quests[#m.quests + 1] = { id = q[1], title = q[2], level = 3, who = {}, status = q[3] } end
        for k, v in pairs(extra or {}) do m[k] = v end
        return m
    end
    Q.changed = false
    drainRequests()
    Q:Request()
    local pending = findOp(drainRequests(), "get_group_quests")
    Q:Load(questsMsg({ { 1, "First" }, { 2, "Second" } }))
    Q:Move(2, -1)                                  -- Second above First, not applied yet
    check(ids() == "2,1" and Q.changed, "moved quest 2 above quest 1")
    serverSend(questsMsg({ { 1, "First" }, { 2, "Second", "ready" }, { 3, "Third" } }, { req = pending.req }))
    check(ids() == "2,1,3", "an older refresh keeps the unsaved order (new quests go to the end)")
    check(Q.changed, "the edit is still marked as not applied")
    check(Q.quests[1].status == "ready", "... and its quest status is updated")
    -- a quest that disappears while editing just leaves the list
    Q:Load(questsMsg({ { 2, "Second" }, { 3, "Third" } }))
    check(ids() == "2,3" and Q.changed, "a quest gone while editing leaves the list, the order stays")
    -- Apply while a refresh is on its way: that old answer doesn't bring back the old order
    Q:Request()
    pending = findOp(drainRequests(), "get_group_quests")
    Q:Move(2, -1)                                  -- 3,2
    Q:Apply()
    local reqs2 = drainRequests()
    local applied = findOp(reqs2, "set_group_quest_order")
    check(applied and applied.quests[1] == 3 and applied.quests[2] == 2, "Apply sends the new order")
    serverSend(questsMsg({ { 2, "Second" }, { 3, "Third" } }, { req = pending.req }))
    check(ids() == "3,2", "an answer older than Apply doesn't restore the old order")
    serverSend({ op = "ack", ["for"] = "set_group_quest_order", req = applied.req, ok = true })
    local after = findOp(drainRequests(), "get_group_quests")
    serverSend(questsMsg({ { 3, "Third" }, { 2, "Second" } }, { req = after.req }))
    check(ids() == "3,2" and not Q.changed, "after Apply the server's order is taken again")
    TC.state.selected = nil
end

-- 10e. simple by default: the extras are one click away and the choice is remembered -----------
do
    -- Settings: basics visible, advanced folded
    TC.db.showAdvancedSettings = nil
    TC.UI:ShowTab("settings")
    local st = TC.UI.tabs.settings.frame
    check(not st.advanced[1]:IsShown() and st.advToggle:GetText() == "Show advanced settings", "Settings: advanced settings folded by default")
    st.advToggle:Click()
    check(st.advanced[1]:IsShown() and st.advanced[#st.advanced]:IsShown() and TC.db.showAdvancedSettings, "Settings: advanced settings open, remembered")
    st.advToggle:Click()

    -- Commands: the everyday commands, the rest under "More commands"
    TC.db.showMoreCommands = nil
    TC.UI:ShowTab("commands")
    local cf = TC.UI.tabs.commands.frame
    local shown, hidden = 0, 0
    for i, c in ipairs(TC.BUILTIN_COMMANDS) do
        if cf.builtinButtons[i]:IsShown() then shown = shown + 1 elseif c[3] then hidden = hidden + 1 end
    end
    check(shown == 8 and hidden == #TC.BUILTIN_COMMANDS - 8, "Commands: 8 everyday commands, the rest folded (" .. shown .. ")")
    cf.moreButton:Click()
    local all = true
    for i = 1, #TC.BUILTIN_COMMANDS do all = all and cf.builtinButtons[i]:IsShown() end
    check(all and cf.moreButton:GetText() == "Fewer commands", "Commands: More commands shows all")
    cf.moreButton:Click()

    -- Quests: Lead / Share / Take by default; Edit list for order, Ignore, Abandon
    local Q = TC.GroupQuests
    Q.editing = false
    Q:Load({ levelCap = 4, companions = 1,
        quests = { { id = 102, title = "Unfortunate Measures", level = 3, sharable = true, missing = { "you" }, who = { { name = "Elara" } } },
                   { id = 103, title = "Windows", level = 2, sharable = true, missing = {}, who = { { name = "Elara" } } } },
        available = { { id = 201, title = "Thirst Unending", level = 3, giver = "Helion", distance = 40, direction = "north", takers = { "Elara" } } } })
    TC.UI:ShowTab("quests")
    local qf = TC.UI.tabs.quests.frame
    qf:Render()
    local r1 = qf.rows[1]
    check(r1.lead:IsShown() and r1.share:IsShown() and not r1.up:IsShown() and not r1.ignore:IsShown() and not r1.abandon:IsShown()
        and not qf.apply:IsShown() and not qf.arows[1].ignore:IsShown() and qf.arows[1].take:IsShown(), "Quests: only Lead / Share / Take by default")
    qf.edit:Click()
    check(Q.editing and r1.up:IsShown() and r1.ignore:IsShown() and r1.abandon:IsShown() and not r1.lead:IsShown()
        and qf.apply:IsShown() and qf.arows[1].ignore:IsShown() and qf.edit:GetText() == "Done", "Quests: Edit list shows order, Ignore, Abandon")
    r1.down:Click()
    qf.edit:Click()
    check(Q.editing and qf.status:GetText():find("isn't applied"), "Quests: Done with an unapplied order asks to apply first")
    qf.reset:Click()
    qf.edit:Click()
    check(not Q.editing, "Quests: Done after reset goes back to the simple view")

    -- a rejected "Apply order" must keep the local order instead of claiming it was saved
    Q.changed = false
    Q.editing = true
    qf:Render()
    qf.rows[1].down:Click()
    check(Q.changed, "Quests: moving a quest marks the order unsaved")
    qf.apply:Click()
    local applied = findOp(drainRequests(), "set_group_quest_order")
    check(applied ~= nil, "Quests: Apply sends the order")
    serverSend({ op = "ack", ["for"] = "set_group_quest_order", req = applied.req, ok = false, code = "rate_limited" })
    check(Q.changed, "Quests: a rejected Apply does not claim the order was saved")
    check(qf.status:GetText() ~= "", "Quests: the rejection is shown")
    Q.editing = false

    -- Personality: presets and identity; the rest behind Customize
    TC.db.showPersonalityDetails = nil
    TC.UI:ShowTab("personality")
    local pf = TC.UI.tabs.personality.frame
    check(not pf.details:IsShown() and pf.detailsButton:GetText():find("Customize"), "Personality: story, traits and style folded by default")
    pf.detailsButton:Click()
    check(pf.details:IsShown() and TC.db.showPersonalityDetails, "Personality: Customize opens them, remembered")
    pf.detailsButton:Click()

    -- Companion tab: three steps until a companion is called
    local saved = TC.state.chars
    TC.state.chars = { { guid = 2, name = "Elara" } }
    TC.UI:ShowTab("companion")
    local cpf = TC.UI.tabs.companion.frame
    cpf:RefreshCard()
    check(cpf.help:GetText():find("Getting started"), "Companion tab: getting started while no companion is called")
    TC.state.chars = { { guid = 2, name = "Elara", active = true } }
    cpf:RefreshCard()
    check(not cpf.help:GetText():find("Getting started"), "Companion tab: the normal help once one is called")
    TC.state.chars = saved
end

-- 10f. who leads, spells to learn, Ollama off ---------------------------------------------
do
    check(TC:LeadText({ leader = "Rindronor", kind = "quest", target = "Solanian's Belongings", distance = 260, direction = "south" }) ==
        "Rindronor leads to \"Solanian's Belongings\" (260 yd south)", "lead text: a quest")
    check(TC:LeadText({ leader = "Myron", kind = "turn_in", target = "Lanthan Perilon", distance = 40, direction = "east", paused = true }) ==
        "Myron leads to Lanthan Perilon to turn in quests (40 yd east) - waiting", "lead text: a turn-in, paused")
    check(TC:LeadText({ you = true, errands = { { name = "Myron", kind = "merchant", target = "Jainthess Thelryn" } } }) ==
        "You lead; Myron is off to Jainthess Thelryn", "lead text: you lead, an errand")
    check(TC:LeadText({}) == "", "lead text: unknown")
    check(TC:LeadText({ you = true, fighting = true }) == "You lead - fighting here", "lead text: clearing the area with you")
    check(TC:LeadText({ leader = "Myron", kind = "trainer", target = "Pathstalker Kariel", distance = 80, direction = "west" }) ==
        "Myron leads to Pathstalker Kariel to learn spells (80 yd west)", "lead text: off to the trainer (with the group)")

    -- the header shows it with the companions
    local saved = TC.state.chars
    TC.state.chars = { { guid = 2, name = "Elara", active = true } }
    TC.UI:Open("companion")
    drainRequests()
    TC:RequestLead()
    local r = findOp(drainRequests(), "get_lead")
    check(r ~= nil, "the window asks who leads")
    serverSend({ op = "lead_state", req = r.req, leader = "Elara", kind = "quest", target = "Thirst Unending", distance = 30, direction = "north" })
    check(TC.UI.subtitle:GetText():find("Elara leads to \"Thirst Unending\""), "the header shows who leads and where to")
    -- no companion: not asked
    TC.state.chars = {}
    drainRequests()
    TC:RequestLead()
    check(findOp(drainRequests(), "get_lead") == nil and TC.state.lead == nil, "without companions nobody is asked")
    TC.state.chars = saved

    -- Ollama switched off on the server: the header says so instead of "Checking Ollama..."
    local feat = TC.state.hello.features
    feat.ollama = false
    TC.UI:RefreshStatus()
    check(TC.UI.lightText:GetText() == "AI off (commands only)", "Ollama off: the header says AI off")
    feat.ollama = true
    TC.UI:RefreshStatus()
end

-- 10g. protocol: duplicates, replacements, the byte limit -------------------------------
do
    local P = TC.Protocol
    local re = P.NewReassembler()
    check(re:Feed("a1:1/3:", 0) == nil and re:Feed("a1:1/3:", 0) == nil and re:Feed("a1:2/3:{\"op\":", 0) == nil,
        "protocol: an empty duplicate counts once")
    local msg = re:Feed("a1:3/3:\"x\"}", 0)
    check(type(msg) == "table" and msg.op == "x", "protocol: complete only after the last part")
    local half = string.rep("a", P.MAX_INBOUND / 2)
    re = P.NewReassembler()
    re:Feed("b1:1/3:" .. half, 0)
    re:Feed("b1:2/3:x", 0)
    local ok, err = re:Feed("b1:2/3:" .. half .. "c", 0)
    check(ok == false and tostring(err):find("large"), "protocol: a longer replacement counts against the limit")
    re = P.NewReassembler()
    re:Feed("c1:1/3:" .. half, 0)
    re:Feed("c1:2/3:" .. half, 0)
    re:Feed("c1:2/3:x", 0)
    ok, err = re:Feed("c1:3/3:" .. string.rep("z", 100), 0)
    check(ok ~= false or not tostring(err):find("large"), "protocol: a shorter replacement frees its bytes")
end

-- 10h. Memory Viewer: an operation stays with the companion it was opened for; late answers are dropped -----
do
    local stub = _G.WOWSTUB
    local MV = TC.MemoryViewer
    local savedChars = TC.state.chars
    TC.state.chars = { { guid = 2, name = "Elara", active = true }, { guid = 3, name = "Lyra", active = true } }
    local function lastPopup() return stub.popups[#stub.popups] end

    -- reset opened for Elara, viewer switched to Lyra, then confirmed: Elara is reset, Lyra untouched
    MV:Open(2)
    drainRequests()
    MV.resetButton:Click()
    local popup = lastPopup()
    check(popup.which == "TRUECOMPANION_RESET" and popup.arg1 == "Elara", "reset confirmation names the companion")
    MV:Open(3)
    drainRequests()
    popup.data()
    local r = findOp(drainRequests(), "reset_companion")
    check(r and r.guid == 2, "reset goes to the companion it was opened for, not the one shown now")

    -- clear and add the same way
    MV:Open(2)
    MV.clearButton:Click()
    popup = lastPopup()
    check(tostring(popup.arg1):find("Elara"), "clear confirmation names the companion")
    MV:Open(3)
    drainRequests()
    popup.data()
    r = findOp(drainRequests(), "clear_memories")
    check(r and r.guid == 2, "clear goes to the companion it was opened for")
    MV:Open(2)
    MV.addButton:Click()
    popup = lastPopup()
    MV:Open(3)
    drainRequests()
    popup.data.onAccept("remembered for Elara")
    r = findOp(drainRequests(), "add_memory")
    check(r and r.guid == 2, "add goes to the companion it was opened for")

    -- import window opened for Elara, viewer switched to Lyra: the import still goes to Elara
    MV:Open(2)
    MV:ShowTransfer("import")
    MV:Open(3)
    drainRequests()
    MV.transfer.area:SetValue(TC.Json.Encode({ format = "mod-true-companion-export", memories = TC.Json.Array({ { text = "x" } }) }))
    MV:RunImport()
    r = findOp(drainRequests(), "import_begin")
    check(r and r.guid == 2, "import goes to the companion the window was opened for")
    check(MV.transfer.title:GetText():find("Elara"), "import window keeps naming that companion")
    serverSend({ op = "ack", ["for"] = "import_begin", req = r.req, ok = false, code = "cancelled" })   -- end it
    MV.transfer:Hide()

    -- a late answer for Elara arrives after switching to Lyra: not shown under Lyra
    MV:Open(2)
    local forElara = findOp(drainRequests(), "get_memories")
    MV:Open(3)
    local forLyra = findOp(drainRequests(), "get_memories")
    check(MV.rows[1].mem == nil, "switching companions clears the old rows")
    serverSend({ op = "memories", req = forElara.req, total = 1, items = { { id = 99, text = "Elara's memory", kind = "fact" } } })
    check(MV.rows[1].mem == nil, "a late answer for the previous companion is dropped")
    serverSend({ op = "memories", req = forLyra.req, total = 1, items = { { id = 5, text = "Lyra's memory", kind = "fact" } } })
    check(MV.rows[1].mem and MV.rows[1].mem.id == 5, "the current companion's answer is shown")
    -- row actions use the companion of the answer they came from
    drainRequests()
    MV.rows[1].del:Click()
    r = findOp(drainRequests(), "delete_memory")
    check(r and r.guid == 3 and r.id == 5, "row action uses the shown answer's companion and memory")
    -- two loads for the same companion answered out of order: the older one is dropped
    MV.offset = 0
    MV:Load()
    local older = findOp(drainRequests(), "get_memories")
    MV.offset = 25
    MV:Load()
    local newer = findOp(drainRequests(), "get_memories")
    serverSend({ op = "memories", req = newer.req, total = 30, items = { { id = 30, text = "page 2", kind = "fact" } } })
    serverSend({ op = "memories", req = older.req, total = 30, items = { { id = 1, text = "page 1", kind = "fact" } } })
    check(MV.rows[1].mem and MV.rows[1].mem.id == 30, "an older answer arriving last doesn't replace the newer page")
    MV.frame:Hide()
    TC.state.chars = savedChars
end

-- 10i. transfers: a timed-out transfer can't disturb the next one; each ends exactly once ---------------
do
    local stub = _G.WOWSTUB
    local T = TC.Transfer
    local doneA, doneB = 0, 0
    local resA, resB
    T:Export(2, nil, function(text, err) doneA = doneA + 1 resA = { text = text, err = err } end)
    local a0 = findOp(drainRequests(), "export")
    stub.Advance(T.TIMEOUT + 1) stub.Update(0.1)
    check(doneA == 1 and resA.text == nil and not T:Busy(), "export A times out once")
    T:Export(3, nil, function(text, count) doneB = doneB + 1 resB = { text = text, count = count } end)
    local b0 = findOp(drainRequests(), "export")
    check(T:Busy() and b0 and b0.guid == 3, "export B runs")
    local function page(i, n, mems) return TC.Json.Encode({ format = "mod-true-companion-export", page = i, pages = n, memories = TC.Json.Array(mems) }) end
    -- A's late answer: ignored, B keeps running, A isn't completed again
    serverSend({ op = "export_data", req = a0.req, guid = 2, part = 0, parts = 1, snapshot = "s1", data = page(0, 1, { { text = "late" } }) })
    check(doneA == 1 and doneB == 0 and T:Busy(), "a late answer for A neither ends A again nor touches B")
    -- B: pages from one snapshot only
    serverSend({ op = "export_data", req = b0.req, guid = 3, part = 0, parts = 2, snapshot = "s7", data = page(0, 2, { { text = "b1" } }) })
    local b1 = findOp(drainRequests(), "export")
    check(b1 and b1.part == 1 and b1.snapshot == "s7", "the next page asks for the same snapshot")
    serverSend({ op = "export_data", req = b1.req, guid = 3, part = 1, parts = 2, snapshot = "s8", data = page(1, 2, { { text = "b2" } }) })
    check(doneB == 1 and resB.text == nil and tostring(resB.count):find("changed"), "pages from another snapshot are refused")
    serverSend({ op = "export_data", req = b1.req, guid = 3, part = 1, parts = 2, snapshot = "s7", data = page(1, 2, {}) })
    check(doneB == 1, "export B ends exactly once")

    -- a retry left over from a timed-out import never sends for the next one
    local resI, doneI = nil, 0
    T:Import(2, page(0, 1, { { text = "x" } }), nil, function(ok, e, unknown) doneI = doneI + 1 resI = { ok = ok, e = e, unknown = unknown } end)
    local ib = findOp(drainRequests(), "import_begin")
    serverSend({ op = "error", code = "rate_limited", req = ib.req })   -- schedules a retry in 1.5 s
    stub.Advance(T.TIMEOUT + 1) stub.Update(0.1)
    check(doneI == 1 and resI.ok == false and not resI.unknown, "import times out before import_end: nothing was applied")
    local doneJ, unknownJ = 0, nil
    T:Import(3, page(0, 1, { { text = "y" } }), nil, function(ok, e, unknown) doneJ = doneJ + 1 unknownJ = unknown end)
    local reqs = drainRequests()
    local begins = 0
    for _, m in ipairs(reqs) do if m.op == "import_begin" then begins = begins + 1 check(m.guid == 3, "only the new import sends") end end
    stub.Advance(2) stub.Update(0.1)
    for _, m in ipairs(drainRequests()) do if m.op == "import_begin" and m.guid == 2 then begins = 99 end end
    check(begins == 1, "the old import's retry is cancelled")
    -- the answer to import_end gets lost: the outcome is unknown, not "nothing changed"
    local jb = findOp(reqs, "import_begin")
    serverSend({ op = "ack", ["for"] = "import_begin", req = jb.req, ok = true })
    local jp = findOp(drainRequests(), "import_part")
    serverSend({ op = "ack", ["for"] = "import_part", req = jp.req, ok = true })
    local je = findOp(drainRequests(), "import_end")
    check(je ~= nil, "import_end sent")
    stub.Advance(T.TIMEOUT + 1) stub.Update(0.1)
    check(doneJ == 1 and not T:Busy() and unknownJ == true, "lost import_end answer: reported as unknown, not as unchanged")
    serverSend({ op = "ack", ["for"] = "import_end", req = je.req, ok = true })
    check(doneJ == 1, "a late import_end answer doesn't complete it again")
end

-- 10j. numbers and the typing indicator ---------------------------------------------
-- integers above 2^31 (C long in the 32-bit client) and fractions encode exactly
check(TC.Json.Encode({ a = 3000000000 }) == '{"a":3000000000}', "large integers are encoded exactly")
check(TC.Json.Encode({ a = -2147483649 }) == '{"a":-2147483649}', "large negative integers are encoded exactly")
for _, v in ipairs({ 0.1, 0.75, 1234567.5, 3.141592653589793, -0.000123456789 }) do
    local back = TC.Json.Decode(TC.Json.Encode({ v = v }))
    check(back and back.v == v, "number round-trips: " .. tostring(v))
end
check(TC.Json.Encode({ t = 0.75 }) == '{"t":0.75}', "short fractions stay short")

TC.state.selected = 2
TC.UI:ShowTab("chat")
TrueCompanionChatInput:SetText("follow")
TrueCompanionChatInput:GetScript("OnEnterPressed")(TrueCompanionChatInput)
drainRequests()
check(TC.state.typing[2] == true, "typing on after sending a line")
serverSend({ op = "typing", guid = 2, on = false })
check(TC.state.typing[2] == nil, "server clears typing when no reply comes")
-- a lost "typing off" expires on its own
TC:SetTyping(2, true)
stub.Advance(TC.TYPING_TIMEOUT / 2)
stub.Update(0.1)
check(TC.state.typing[2] == true, "typing still on while a reply may come")
stub.Advance(TC.TYPING_TIMEOUT)
stub.Update(0.1)
check(TC.state.typing[2] == nil, "stale typing indicator expires")
-- a typing push without guid is ignored instead of raising an error
local errorsBefore = #TC.state.errors
serverSend({ op = "typing", on = true })
check(#TC.state.errors == errorsBefore, "typing without guid is ignored")
-- a rate-limited chat line gets no answer; a rate-limited other request keeps the indicator
TC:SetTyping(2, true)
serverSend({ op = "error", code = "rate_limited", ["for"] = "get_memories" })
check(TC.state.typing[2] == true, "a rate-limited non-chat request keeps typing")
serverSend({ op = "error", code = "rate_limited", ["for"] = "chat" })
check(TC.state.typing[2] == nil, "a rate-limited chat line clears typing")
for _ = 1, 2 do table.remove(TC.state.errors, 1) end   -- expected server errors, not UI errors

-- 10k. broken or hostile server fields -------------------------------------------------
check(TC:Escape("a|b") == "a||b", "pipe is escaped before it reaches chat or a label")
check(TC:Escape(nil) == "", "escape tolerates nil")
-- dispatch runs outside any pcall: a non-scalar req must not abort the whole message
serverSend({ op = "typing", guid = 2, on = true, req = {} })
check(TC.state.typing[2] == true, "a table in req does not swallow the message")
serverSend({ op = "typing", guid = 2, on = false })
check(TC.state.typing[2] == nil, "typing still works afterwards")

-- 10l. a companion that disappears from the list is deselected ---------------------
TC.state.selected = 3
TC.state.companions[3] = { guid = 3, name = "Lyra" }
TC.state.sheets[3] = { level = 70 }
TC.state.relationship[3] = { stage = 1 }
TC.state.typing[3] = true
serverSend({ op = "chars", maxActive = 1, chars = {
    { guid = 2, name = "Elara", race = 1, raceName = "Human", class = 8, className = "Mage", level = 80, status = "available" } } })
check(TC.state.selected == nil, "a companion that left the list is deselected")
check(TC.state.companions[3] == nil and TC.state.sheets[3] == nil and TC.state.relationship[3] == nil
    and TC.state.typing[3] == nil, "its cached data is dropped with it")
check(findOp(drainRequests(), "get_companion") == nil, "nothing is requested for it any more")

-- 11. no unexpected UI errors -------------------------------------------------------
local unexpected = {}
for _, e in ipairs(TC.state.errors) do
    if not (e.where == "protocol" or e.where == "get_companion") then unexpected[#unexpected + 1] = e.where .. ": " .. e.msg end
end
check(#unexpected == 0, "no UI errors: " .. table.concat(unexpected, " | "))

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
