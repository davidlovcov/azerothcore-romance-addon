--[[
  C++ <-> Lua wire compatibility test.
    lua5.1 tests/test_interop.lua AzerothRomance /path/to/romance_wire   (romance_wire is built by mod-romance/scripts/run-tests.sh)
]]

local addonDir, tool = arg[1] or "AzerothRomance", arg[2] or "romance_wire"
local here = arg[0]:match("^(.*)/[^/]+$") or "."
_G.AzerothRomance = {}
dofile(addonDir .. "/Libs/Json.lua")
dofile(addonDir .. "/Libs/Protocol.lua")
local AR = _G.AzerothRomance
local passed, failed = 0, 0
local function check(c, m) if c then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. m) end end

local function write(path, s) local f = assert(io.open(path, "wb")) f:write(s) f:close() end
local function read(cmd) local p = assert(io.popen(cmd, "r")) local s = p:read("*a") p:close() return s end

local text = "Grüße aus Dalaran ♥ | \"quotes\" \\ back\nslash " .. string.rep("Elara mag Blumen. ", 60)
local msg = { op = "save_personality", guid = 2, personality = { name = "Elara", customInstructions = text, age = 24,
    styles = AR.Json.Array({ "anime", "sweet" }) } }

-- Lua -> C++
local chunks = AR.Protocol.Encode(msg, 77)
check(#chunks > 3, "lua produced multiple chunks")
for _, c in ipairs(chunks) do check(not c:find("|", 1, true), "no raw pipe in lua chunk") end
write("/tmp/romance_chunks.txt", table.concat(chunks, "\n") .. "\n")
local decoded = read(tool .. " decode < /tmp/romance_chunks.txt")
local back = AR.Json.Decode(decoded)
check(back and back.personality and back.personality.customInstructions == text, "C++ decoded Lua message intact (UTF-8, pipes, quotes)")
check(back and back.guid == 2 and back.personality.age == 24, "numbers survive")

-- C++ -> Lua
write("/tmp/romance_msg.json", AR.Json.Encode(msg))
local out = read(tool .. " encode < /tmp/romance_msg.json")
local re = AR.Protocol.NewReassembler()
local result
for line in out:gmatch("[^\n]+") do
    check(#line + 5 <= 255, "C++ chunk fits a 3.3.5 addon message")
    local r = re:Feed(line, 0)
    if r then result = r end
end
check(result and result.personality.customInstructions == text, "Lua decoded C++ message intact")
check(result and result.personality.styles[2] == "sweet", "arrays survive")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
