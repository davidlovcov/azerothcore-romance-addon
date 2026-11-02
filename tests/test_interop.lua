--[[
  C++ <-> Lua wire compatibility test.
    lua5.1 tests/test_interop.lua TrueCompanion /path/to/true_companion_wire   (true_companion_wire is built by mod-true-companion/scripts/run-tests.sh)
]]

local addonDir, tool = arg[1] or "TrueCompanion", arg[2] or "true_companion_wire"
local here = arg[0]:match("^(.*)/[^/]+$") or "."
_G.TrueCompanion = {}
dofile(addonDir .. "/Libs/Json.lua")
dofile(addonDir .. "/Libs/Protocol.lua")
local TC = _G.TrueCompanion
local passed, failed = 0, 0
local function check(c, m) if c then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. m) end end

local function write(path, s) local f = assert(io.open(path, "wb")) f:write(s) f:close() end
local function read(cmd) local p = assert(io.popen(cmd, "r")) local s = p:read("*a") p:close() return s end

local text = "Grüße aus Dalaran ♥ | \"quotes\" \\ back\nslash " .. string.rep("Elara mag Blumen. ", 60)
local msg = { op = "save_personality", guid = 2, personality = { name = "Elara", customInstructions = text, age = 24,
    styles = TC.Json.Array({ "anime", "sweet" }) } }

-- Lua -> C++
local chunks = TC.Protocol.Encode(msg, 77)
check(#chunks > 3, "lua produced multiple chunks")
for _, c in ipairs(chunks) do check(not c:find("|", 1, true), "no raw pipe in lua chunk") end
write("/tmp/true_companion_chunks.txt", table.concat(chunks, "\n") .. "\n")
local decoded = read(tool .. " decode < /tmp/true_companion_chunks.txt")
local back = TC.Json.Decode(decoded)
check(back and back.personality and back.personality.customInstructions == text, "C++ decoded Lua message intact (UTF-8, pipes, quotes)")
check(back and back.guid == 2 and back.personality.age == 24, "numbers survive")

-- C++ -> Lua
write("/tmp/true_companion_msg.json", TC.Json.Encode(msg))
local out = read(tool .. " encode < /tmp/true_companion_msg.json")
local re = TC.Protocol.NewReassembler()
local result
for line in out:gmatch("[^\n]+") do
    check(#line + 5 <= 255, "C++ chunk fits a 3.3.5 addon message")
    local r = re:Feed(line, 0)
    if r then result = r end
end
check(result and result.personality.customInstructions == text, "Lua decoded C++ message intact")
check(result and result.personality.styles[2] == "sweet", "arrays survive")

-- Paged import of a full export (400 memories): every part must pass the C++ server reassembler (16 KiB, 96 chunks)
_G.CreateFrame = function() return { SetScript = function() end, Show = function() end } end
_G.GetTime = function() return 0 end
dofile(addonDir .. "/Transfer.lua")
local memories = {}
for i = 1, 400 do
    memories[i] = { id = i, kind = "fact", source = "user_edited", importance = 40, pinned = false,
        text = ("Madox kept a \"souvenir %d\" from Dalaran \195\164\195\182\195\188 \\ with a long note about the trip number %d"):format(i, i) }
end
local full = { format = "mod-true-companion-export", version = 1, companion = "Elara",
    personality = { name = "Elara", customInstructions = text, styles = TC.Json.Array({ "anime" }) },
    memories = TC.Json.Array(memories) }
local pages = TC.Transfer.SplitForImport(full, 2)
check(pages and #pages > 3, "large export split into several import parts")
local joinedBack = {}
for i, page in ipairs(pages or {}) do
    local req = { op = "import_part", guid = 2, index = i - 1, data = page, req = 999999 }
    write("/tmp/true_companion_part.txt", table.concat(TC.Protocol.Encode(req, 500 + i), "\n") .. "\n")
    local got = read(tool .. " decode < /tmp/true_companion_part.txt")
    local back = got ~= "" and TC.Json.Decode(got)
    check(back and back.data == page, "C++ server accepts import part " .. i .. " (" .. #page .. " bytes)")
    joinedBack[i] = back and back.data or ""
end
local joined = TC.Transfer.JoinPages(joinedBack)
check(joined and #joined.memories == 400, "all 400 memories survive the paged import")
check(joined and joined.memories[400].text == memories[400].text, "memory text intact (quotes, UTF-8, backslash)")

-- a server export page (8 KiB of JSON) reaches the addon intact
local page = TC.Json.Encode({ format = "mod-true-companion-export", page = 0, pages = 1, memories = TC.Json.Array({ memories[1], memories[2] }),
    personality = { customInstructions = string.rep("x", 7000) } })
write("/tmp/true_companion_msg.json", TC.Json.Encode({ op = "export_data", part = 0, parts = 1, data = page }))
out = read(tool .. " encode < /tmp/true_companion_msg.json")
re = TC.Protocol.NewReassembler()
result = nil
for line in out:gmatch("[^\n]+") do
    local r = re:Feed(line, 0)
    if r then result = r end
end
check(result and result.data == page, "C++ export page decoded by the addon")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
