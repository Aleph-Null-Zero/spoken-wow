setfenv(1, VoiceOver)
local function jaccardSimilarity(a, b)
    local tokens_a, tokens_b = {}, {}
    for token in string.gmatch(a, "%S+") do tokens_a[token] = true end
    for token in string.gmatch(b, "%S+") do tokens_b[token] = true end

    local intersection, union = 0, 0
    for token in pairs(tokens_a) do
        union = union + 1
        if tokens_b[token] then
            intersection = intersection + 1
        end
    end
    for token in pairs(tokens_b) do
        if not tokens_a[token] then
            union = union + 1
        end
    end

    return intersection / union
end

-- How alike a line must be to the text on screen to be read for it. Measured on the corpus: a
-- line and the client's rewording of the same moment score 0.8 or more once punctuation and the
-- player's tokens are set aside, while an NPC's other lines, read for a text the packs lack (a
-- trainer's greeting to a player of its profession, a barker's place for the other faction),
-- mostly score under 0.6.
GOSSIP_MATCH_FLOOR = 0.7

--- A line's words as they are compared: lower case, ASCII punctuation as spaces. Bytes past
--- ASCII are kept, so another alphabet's words compare whole.
local function Words(text)
    return (string.gsub(string.lower(text), "%p", " "))
end

--- The NPC's line for the gossip text on screen, or nil when none is like it.
---
--- The lines are keyed by their text as extracted, with the server's tokens ($N, $g...) still
--- in it, so each is filled in for this player before it is compared.
---@param shown string
---@param lines table<string, any> line text -> value
---@return { value: any, text: string, similarity: number }|nil
function FuzzySearchGossipLine(shown, lines)
    local best = FuzzySearchBestKeys(Words(shown), lines, function(text)
        return Words(Utils:FillPlayerTokens(text))
    end)
    return best and best.similarity >= GOSSIP_MATCH_FLOOR and best or nil
end

---@param query string
---@param tableVar table<string, any>
---@param keyText fun(key: string): string? what a key is compared as, the key itself by default
function FuzzySearchBestKeys(query, tableVar, keyText)
    local best_result = nil
    local max_similarity = -1

    for entry, value in pairs(tableVar) do
        local similarity = jaccardSimilarity(query, keyText and keyText(entry) or entry)
        if similarity > max_similarity then
            max_similarity = similarity
            best_result = {
                value = value,
                text = entry,
                similarity = similarity
            }
        end
    end

    return best_result
end