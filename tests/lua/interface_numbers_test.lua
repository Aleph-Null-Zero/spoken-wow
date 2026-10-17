-- Every `## Interface:` number the repo writes, and which client each one is. The numbers are
-- written by hand in the addons' .toc files, the packs' generated .toc (tts_cli/build.py, which
-- scripts/audio/acted.mjs copies for the language packs) and the meta addons' (package-meta.sh),
-- so this is what keeps them one list. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local Expect, Failures = H.Expecter(stub.print)
local ROOT = here .. "/../../"

local FOREVER = 16001
local CLIENTS = {
    [FOREVER] = "Forever 1.60.1",
    [11509] = "Classic Era 1.15.9",
    [20506] = "Anniversary 2.5.6",
    [30403] = "Wrath Classic 3.4.3",
    -- Retail 10.0.7, never offered; on the packs it leads the line for the 1.12, 2.4.3 and
    -- 3.3.5 clients, which read the first number alone and refuse one below 20000.
    [100007] = "the lead the legacy clients read",
    [11200] = "1.12", [20400] = "2.4.3", [30300] = "3.3.5",
}

local function Read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local function Numbers(line)
    local list = {}
    for number in line:gmatch("%d+") do list[#list + 1] = tonumber(number) end
    return list
end

local function Check(where, line)
    for _, number in ipairs(Numbers(line)) do
        Expect(where .. " names a known client (" .. number .. ")", CLIENTS[number] ~= nil, true)
    end
end

local FOLDERS = { "Spoken", "Spoken_Quests", "Spoken_Places", "Spoken_Readables", "Spoken_Developer",
    "SpokenContributions", "SpokenZonesAudio", "SpokenBooksAudio" }
local SUFFIXES = { "", "_Vanilla", "_TBC", "_1.12", "_2.4.3", "_3.3.5" }
for _, folder in ipairs(FOLDERS) do
    for _, suffix in ipairs(SUFFIXES) do
        local name = folder .. suffix .. ".toc"
        local text = Read(ROOT .. "addons/" .. folder .. "/" .. name)
        if text then
            local line = text:match("^## Interface:([^\r\n]*)")
            Expect(name .. " starts with its Interface line", line ~= nil, true)
            if line then
                Check(name, line)
                -- The unsuffixed .toc is the one Forever reads.
                if suffix == "" then
                    local listed = false
                    for _, number in ipairs(Numbers(line)) do listed = listed or number == FOREVER end
                    Expect(name .. " lists Forever, which rejects a .toc that does not", listed, true)
                end
            end
        elseif suffix == "" then
            Expect(folder .. " has its .toc", false, true)
        end
    end
end

-- The packs and the meta addons are filed against the same clients, with the same line.
local packLines = {}
for _, path in ipairs({ "pipelines/quests/tts_cli/build.py", "scripts/quests/package-meta.sh",
    "scripts/spoken/package-meta.sh" }) do
    local text = assert(Read(ROOT .. path), path)
    local line = text:match("## Interface:([^\r\n]*)")
    Expect(path .. " writes an Interface line", line ~= nil, true)
    if line then
        Check(path, line)
        packLines[#packLines + 1] = line
        Expect(path .. " leads with the number the legacy clients read", Numbers(line)[1], 100007)
    end
end
for i = 2, #packLines do
    Expect("the packs' and meta addons' Interface lines agree (" .. i .. ")", packLines[i], packLines[1])
end

os.exit(Failures() == 0 and 0 or 1)
