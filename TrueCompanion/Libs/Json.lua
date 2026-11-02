--[[
  TrueCompanion - JSON encode/decode for WoW 3.3.5a (Lua 5.1)
  Licensed under the GNU GPL v2 or later.

  * Objects are Lua tables with string keys, arrays are tables with 1..n keys.
  * Empty tables encode as {} unless marked with TC.Json.Array({}).
  * '|' is always written as |: the WoW client treats '|' as an escape
    sequence in chat/addon text.
]]

local TC = _G.TrueCompanion or {}
_G.TrueCompanion = TC

local Json = {}
TC.Json = Json

local strbyte, strchar, strsub, strfind, strformat = string.byte, string.char, string.sub, string.find, string.format
local tconcat, tinsert = table.concat, table.insert
local floor = math.floor

local ARRAY_MARK = {}

function Json.Array(t)
    t = t or {}
    return setmetatable(t, ARRAY_MARK)
end

local function isArray(t)
    if getmetatable(t) == ARRAY_MARK then return true end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    if n == 0 then return false end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local escapes = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["|"] = "\\u007c",
}

local function escapeString(s)
    return '"' .. s:gsub('[%c"\\|]', function(c)
        return escapes[c] or strformat("\\u%04x", strbyte(c))
    end) .. '"'
end

local encodeValue

local function encodeTable(t, out, depth)
    if depth > 20 then error("json: nesting too deep") end
    if isArray(t) then
        tinsert(out, "[")
        for i = 1, #t do
            if i > 1 then tinsert(out, ",") end
            encodeValue(t[i], out, depth + 1)
        end
        tinsert(out, "]")
    else
        tinsert(out, "{")
        local first = true
        local keys = {}
        for k in pairs(t) do
            if type(k) == "string" then tinsert(keys, k) end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            if not first then tinsert(out, ",") end
            first = false
            tinsert(out, escapeString(k))
            tinsert(out, ":")
            encodeValue(t[k], out, depth + 1)
        end
        tinsert(out, "}")
    end
end

encodeValue = function(v, out, depth)
    local tv = type(v)
    if tv == "nil" then
        tinsert(out, "null")
    elseif tv == "boolean" then
        tinsert(out, v and "true" or "false")
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            tinsert(out, "0")
        elseif v == floor(v) and v > -1e15 and v < 1e15 then
            -- "%d" goes through a C long, which is 32 bits in the Windows client: values above
            -- 2^31 would wrap. "%.0f" is exact for every integer below 2^53.
            tinsert(out, strformat("%.0f", v))
        else
            -- shortest form that reads back as the same number ("%.6g" lost precision)
            local s = strformat("%.14g", v)
            if tonumber(s) ~= v then s = strformat("%.17g", v) end
            tinsert(out, s)
        end
    elseif tv == "string" then
        tinsert(out, escapeString(v))
    elseif tv == "table" then
        encodeTable(v, out, depth)
    else
        error("json: cannot encode " .. tv)
    end
end

function Json.Encode(v)
    local out = {}
    encodeValue(v, out, 0)
    return tconcat(out)
end

-- ------------------------------------------------------------------ decode

local function utf8char(cp)
    if cp < 0x80 then return strchar(cp) end
    if cp < 0x800 then return strchar(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return strchar(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return strchar(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
        0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local decodeValue

local function skipWs(s, i)
    local _, e = strfind(s, "^[ \t\r\n]*", i)
    return e + 1
end

local function decodeString(s, i)
    -- s:sub(i,i) == '"'
    local out = {}
    local j = i + 1
    while true do
        local c = strsub(s, j, j)
        if c == "" then error("json: unterminated string") end
        if c == '"' then return tconcat(out), j + 1 end
        if c == "\\" then
            local e = strsub(s, j + 1, j + 1)
            if e == "u" then
                local hex = strsub(s, j + 2, j + 5)
                local cp = tonumber(hex, 16)
                if not cp or #hex < 4 then error("json: bad unicode escape") end
                j = j + 6
                if cp >= 0xD800 and cp <= 0xDBFF and strsub(s, j, j + 1) == "\\u" then
                    local lo = tonumber(strsub(s, j + 2, j + 5), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        j = j + 6
                    end
                end
                tinsert(out, utf8char(cp))
            else
                local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                local r = map[e]
                if not r then error("json: bad escape") end
                tinsert(out, r)
                j = j + 2
            end
        else
            local k = strfind(s, '["\\]', j)
            if not k then error("json: unterminated string") end
            tinsert(out, strsub(s, j, k - 1))
            j = k
        end
    end
end

local function decodeNumber(s, i)
    local _, e = strfind(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not e then error("json: bad number") end
    local n = tonumber(strsub(s, i, e))
    if not n then error("json: bad number") end
    return n, e + 1
end

decodeValue = function(s, i, depth)
    if depth > 32 then error("json: nesting too deep") end
    i = skipWs(s, i)
    local c = strsub(s, i, i)
    if c == "{" then
        local obj = {}
        i = skipWs(s, i + 1)
        if strsub(s, i, i) == "}" then return obj, i + 1 end
        while true do
            i = skipWs(s, i)
            if strsub(s, i, i) ~= '"' then error("json: expected key") end
            local key
            key, i = decodeString(s, i)
            i = skipWs(s, i)
            if strsub(s, i, i) ~= ":" then error("json: expected ':'") end
            local val
            val, i = decodeValue(s, i + 1, depth + 1)
            obj[key] = val
            i = skipWs(s, i)
            local d = strsub(s, i, i)
            if d == "}" then return obj, i + 1 end
            if d ~= "," then error("json: expected ',' or '}'") end
            i = i + 1
        end
    elseif c == "[" then
        local arr = Json.Array({})
        i = skipWs(s, i + 1)
        if strsub(s, i, i) == "]" then return arr, i + 1 end
        local n = 0
        while true do
            local val
            val, i = decodeValue(s, i, depth + 1)
            n = n + 1
            arr[n] = val
            i = skipWs(s, i)
            local d = strsub(s, i, i)
            if d == "]" then return arr, i + 1 end
            if d ~= "," then error("json: expected ',' or ']'") end
            i = i + 1
        end
    elseif c == '"' then
        return decodeString(s, i)
    elseif c == "-" or strfind(c, "%d") then
        return decodeNumber(s, i)
    elseif strsub(s, i, i + 3) == "true" then
        return true, i + 4
    elseif strsub(s, i, i + 4) == "false" then
        return false, i + 5
    elseif strsub(s, i, i + 3) == "null" then
        return nil, i + 4
    end
    error("json: unexpected character at " .. i)
end

-- Returns value or nil, error
function Json.Decode(s)
    if type(s) ~= "string" then return nil, "not a string" end
    local ok, v, i = pcall(decodeValue, s, 1, 0)
    if not ok then return nil, v end
    i = skipWs(s, i)
    if i <= #s then return nil, "json: trailing characters" end
    return v
end
