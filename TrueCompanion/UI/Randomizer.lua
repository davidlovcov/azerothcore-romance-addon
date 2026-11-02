--[[
  TrueCompanion - random story & taste for companions and the player profile.
  Everything is local to the addon; nothing is saved until you press Save.
  Lines are combined from several pools, so results rarely repeat.
]]

local TC = _G.TrueCompanion
local R = {}
TC.Random = R

local function pick(list) return list[math.random(#list)] end

local function pickN(list, n)
    local copy, out = {}, {}
    for i, v in ipairs(list) do copy[i] = v end
    for _ = 1, math.min(n, #copy) do
        table.insert(out, table.remove(copy, math.random(#copy)))
    end
    return out
end

local function join(list) return table.concat(list, ", ") end

-- ---------------------------------------------------------------- shared pools

local ORIGINS = {
    "a farmstead in Elwynn Forest", "the canals of Stormwind's Mage Quarter", "a fishing village on the Westfall coast",
    "the snowy hills of Dun Morogh", "a quiet glade in Ashenvale", "the bustling docks of Booty Bay",
    "a manor in Lordaeron before the plague", "a dwarven mining camp in Loch Modan", "the cliffs of Teldrassil",
    "a caravan that crossed the Barrens every season", "a monastery in the Redridge Mountains", "the streets of Dalaran",
    "a hunting lodge in Grizzly Hills", "a lighthouse near Menethil Harbor", "the ruins of Gilneas' outskirts",
}

local REASONS = {
    "left home to see the world", "lost everything to the Scourge and started over", "ran away from an arranged future",
    "followed a prophecy that never quite made sense", "was sent away to train and never went back",
    "went looking for a missing sibling", "wanted adventure more than a quiet life", "fled debts and a bad reputation",
    "answered the call to fight in Northrend", "inherited an old map and could not resist",
}

local MEETINGS = {
    "after you helped fight off a pack of wolves on the road", "in a tavern brawl in Goldshire that you both lost",
    "when you were both hired for the same bounty", "during the defense of a village against the Scourge",
    "while lost in the same dungeon", "at the Darkmoon Faire, over a rigged game", "on a ship to Northrend during a storm",
    "when you rescued them from an ambush", "while competing for the same treasure", "through a mutual friend in Dalaran",
}

local INTERESTS = {
    "cooking", "fishing", "stargazing", "reading old tomes", "sketching landscapes", "collecting rare herbs",
    "brewing", "card games", "music", "dancing", "swordplay", "archery", "tinkering with gadgets", "horse riding",
    "exploring ruins", "writing poems", "collecting trinkets", "studying magic", "taming animals", "gardening",
}

local LIKES = {
    "warm inns on rainy nights", "sweet pastries", "flowers", "sunsets over the sea", "honest people", "good jokes",
    "quiet mornings", "shiny loot", "campfire stories", "spicy food", "snow", "long rides", "hot tea", "music in taverns",
    "being praised", "surprises", "a well-made weapon", "maps of unknown places", "hot springs", "festivals",
}

local DISLIKES = {
    "spiders", "being left behind", "liars", "cold rain", "rude people", "boredom", "the Scourge", "crowds",
    "early mornings", "bad food", "cowards", "waiting", "murlocs", "being underestimated", "arrogant nobles",
    "dark caves", "losing at cards", "goblin prices", "noise", "broken promises",
}

local GOALS = {
    "to see every corner of Azeroth", "to build a home somewhere peaceful", "to become a legendary fighter",
    "to master the arcane arts", "to protect the people they love", "to write a book about their travels",
    "to find a lost family heirloom", "to open a tavern one day", "to make their family proud", "to find where they belong",
}

local FEARS = {
    "is afraid of being abandoned", "doubts they are strong enough", "fears losing someone in battle again",
    "hides insecurity behind jokes", "struggles to trust people", "worries about being a burden",
    "is stubborn to a fault", "gets jealous more easily than anyone would guess", "can be reckless when angry",
    "is afraid of the dark", "overthinks everything", "has trouble asking for help",
}

local REL_PREFS = {
    "Needs time and trust before opening up.", "Loves openly and shows it with small gestures.",
    "Values loyalty above everything.", "Shows care through actions rather than words.",
    "Likes to be pursued, but stays true once committed.", "Wants a partner who is also a best friend.",
    "Prefers slow, honest romance over grand gestures.", "Playful and flirty; commitment has to sneak up on them.",
}

local LORE = {
    "Fascinated by the night elves and their ancient history.", "Loves the legends of the Silver Hand.",
    "Curious about the Titans and Ulduar.", "Admires the Kirin Tor and Dalaran's magic.",
    "Loves goblin gadgets and pirate legends.", "Interested in the dwarves' search for their origins.",
    "Follows the Light, but with doubts.", "Fond of druidic lore and the Emerald Dream.",
}

local HISTORIES = {
    "%s Since then you have shared many roads together.", "%s You have been inseparable ever since.",
    "%s It took a while, but now you trust each other completely.", "%s The two of you have been traveling together for months.",
}

-- Neutral pronouns in the pools are adjusted to the companion's gender.
local function gendered(text, gender)
    if gender == "female" then
        text = text:gsub("their", "her"):gsub("them", "her"):gsub("they are", "she is"):gsub("they", "she")
    elseif gender == "male" then
        text = text:gsub("their", "his"):gsub("them", "him"):gsub("they are", "he is"):gsub("they", "he")
    end
    return text
end

local function capital(s) return (s:gsub("^%l", string.upper)) end

-- Story & taste fields of the Personality tab.
function R.CompanionStory(gender)
    local g = function(s) return gendered(s, gender) end
    local meeting = pick(MEETINGS)
    return {
        background = g(("Grew up in %s and %s."):format(pick(ORIGINS), pick(REASONS))),
        history = g(pick(HISTORIES):format(("You met %s."):format(meeting))),
        interests = capital(join(pickN(INTERESTS, 3))),
        likes = join(pickN(LIKES, 4)),
        dislikes = join(pickN(DISLIKES, 3)),
        goals = g(capital(pick(GOALS)) .. "."),
        fears = g(capital(pick(FEARS)) .. "; " .. pick(FEARS) .. "."),
        relationshipPreferences = g(pick(REL_PREFS)),
        lore = g(pick(LORE)),
    }
end

-- ---------------------------------------------------------------- player profile

local PLAYER_IDENTITIES = {
    "A wandering adventurer who takes whatever work pays.", "A soldier of the Alliance on leave from the front.",
    "A treasure hunter with more maps than gold.", "A healer who travels where help is needed.",
    "A former noble who gave up the title for the open road.", "A scholar studying ancient ruins.",
    "A mercenary with a soft heart.", "A hunter who knows the wilds better than any city.",
}

local PLAYER_PREFS = {
    "prefers honesty over flattery", "likes quiet company after a long fight", "enjoys being teased a little",
    "appreciates small gestures", "likes making plans together", "needs some time alone now and then",
    "loves good food and good stories", "is not a morning person",
}

local PLAYER_MEETINGS = {
    "on the road near Goldshire, fighting off the same pack of wolves", "in a tavern brawl that neither of us won",
    "when we were hired for the same bounty", "while defending a village against the Scourge",
    "lost in the same dungeon", "at the Darkmoon Faire", "on a stormy crossing to Northrend",
    "competing for the same treasure", "through a friend in Dalaran",
}

local PLAYER_HOPES = {
    "A partner to share adventures and quiet evenings with.", "Someone to trust completely on and off the battlefield.",
    "A slow, honest romance that grows over time.", "A best friend first, everything else later.",
    "Someone who makes the long roads feel shorter.",
}

-- Fields of the Player Profile tab. `companion` is used for the shared history line.
function R.PlayerStory(companion)
    companion = (companion and companion ~= "") and companion or "your companion"
    return {
        rpIdentity = pick(PLAYER_IDENTITIES),
        background = ("Grew up in %s and %s."):format(pick(ORIGINS), pick(REASONS)),
        interests = capital(join(pickN(INTERESTS, 3))),
        preferences = capital(join(pickN(PLAYER_PREFS, 2))) .. ".",
        expectations = pick(PLAYER_HOPES),
        sharedHistory = ("%s and I met %s."):format(companion, pick(PLAYER_MEETINGS)),
    }
end
