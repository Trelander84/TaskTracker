-- Data/ProfessionsCatalog.lua
-- Midnight profession weeklies (quest/currency ids from community macros; verify in-game with /dump C_QuestLog.IsQuestFlaggedCompleted(id))

TaskTracker = TaskTracker or {}

TaskTracker.ProfessionCatalogOrder = {
    "alchemy", "blacksmithing", "enchanting", "engineering", "herbalism",
    "inscription", "jewelcrafting", "leatherworking", "mining", "skinning", "tailoring",
}

--- @type table<string, table>
TaskTracker.ProfessionCatalog = {
    alchemy = {
        label = "Alchemy",
        catchupCurrencyId = 3189,
        weeklyQuestLabel = "Crafting Orders",
        weeklyQuestIds = { 93690 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93529, 93528 },
        treatiseQuestId = 95127,
    },
    blacksmithing = {
        label = "Blacksmithing",
        catchupCurrencyId = 3199,
        weeklyQuestLabel = "Crafting Orders",
        weeklyQuestIds = { 93691 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93530, 93531 },
        treatiseQuestId = 95128,
    },
    enchanting = {
        label = "Enchanting",
        catchupCurrencyId = 3198,
        weeklyQuestLabel = "Enchanting Supplies Quest",
        weeklyQuestIds = { 93698, 93697, 93699 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93533, 93532 },
        weeklyDisenchantRows = {
            {
                label    = "Swirling Arcane Essence",
                questIds = { 95048, 95049, 95050, 95051, 95052 },
                max      = 5,
            },
            {
                label    = "Brimming Mana Shard",
                questIds = { 95053 },
                max      = 1,
            },
        },
        treatiseQuestId = 95129,
    },
    engineering = {
        label = "Engineering",
        catchupCurrencyId = 3197,
        weeklyQuestLabel = "Crafting Orders",
        weeklyQuestIds = { 93692 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93535, 93534 },
        treatiseQuestId = 95138,
    },
    herbalism = {
        label = "Herbalism",
        catchupCurrencyId = 3196,
        weeklyQuestLabel = "Weekly Gathering",
        weeklyQuestIds = { 93700, 93702, 93703, 93704 },
        weeklyDropsLabel = "Weekly Samples",
        weeklyDropIds = { 81430 },
        treatiseQuestId = 95130,
        weeklyDropsQuestComplete = true,
    },
    inscription = {
        label = "Inscription",
        catchupCurrencyId = 3195,
        weeklyQuestLabel = "Crafting Orders",
        weeklyQuestIds = { 93693 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93536, 93537 },
        treatiseQuestId = 95131,
    },
    jewelcrafting = {
        label = "Jewelcrafting",
        catchupCurrencyId = 3194,
        weeklyQuestLabel = "Crafting Orders",
        weeklyQuestIds = { 93694 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93538, 93539 },
        treatiseQuestId = 95133,
    },
    leatherworking = {
        label = "Leatherworking",
        catchupCurrencyId = 3193,
        weeklyQuestLabel = "Crafting Orders",
        weeklyQuestIds = { 93695 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93541, 93540 },
        treatiseQuestId = 95134,
    },
    mining = {
        label = "Mining",
        catchupCurrencyId = 3192,
        weeklyQuestLabel = "Weekly Gathering",
        weeklyQuestIds = { 93705, 93706, 93707, 93708, 93709 },
        weeklyDropsLabel = "Weekly Samples",
        weeklyDropIds = { 88678 },
        treatiseQuestId = 95135,
        weeklyDropsQuestComplete = true,
    },
    skinning = {
        label = "Skinning",
        catchupCurrencyId = 3191,
        weeklyQuestLabel = "Weekly Gathering",
        weeklyQuestIds = { 93710 },
        weeklyDropsLabel = "Weekly Samples",
        weeklyDropIds = { 88529 },
        treatiseQuestId = 95136,
        weeklyDropsQuestComplete = true,
    },
    tailoring = {
        label = "Tailoring",
        catchupCurrencyId = 3190,
        weeklyQuestLabel = "Crafting Orders",
        weeklyQuestIds = { 93696 },
        weeklyDropsLabel = "Weekly Treasures",
        weeklyDropIds = { 93542, 93543 },
        treatiseQuestId = 95137,
    },
}

local function questSet(ids)
    local t = {}
    for _, qid in ipairs(ids) do
        t[qid] = true
    end
    return t
end

function TaskTracker.BuildProfessionRegistryEntries()
    local out = {}
    for _, key in ipairs(TaskTracker.ProfessionCatalogOrder) do
        local def = TaskTracker.ProfessionCatalog[key]
        if def then
            local profLabel = def.label or key
            local weeklyLabel = def.weeklyQuestLabel or "Weekly Quest"
            if weeklyLabel == "Crafting Orders" then
                weeklyLabel = "Crafting Orders: " .. profLabel
            end

            local dropIds = def.weeklyDropIds or {}
            local dropMax = #dropIds
            if dropMax < 1 then dropMax = 1 end

            out[#out + 1] = {
                id             = "prof_" .. key .. "_weekly",
                label          = weeklyLabel,
                expansion      = "professions",
                subsection     = key,
                professionKey  = key,
                type           = "quest_complete",
                max            = 1,
                reset          = "weekly",
                quests         = questSet(def.weeklyQuestIds or {}),
                defaultNote    = "Complete this week's " .. weeklyLabel .. " for " .. profLabel .. ".",
            }

            for i, deRow in ipairs(def.weeklyDisenchantRows or {}) do
                local deMax = tonumber(deRow.max) or #deRow.questIds
                if deMax < 1 then deMax = 1 end
                out[#out + 1] = {
                    id             = "prof_" .. key .. "_disenchant_" .. i,
                    label          = deRow.label or "Weekly Disenchant Knowledge",
                    expansion      = "professions",
                    subsection     = key,
                    professionKey  = key,
                    type           = "quest_count",
                    max            = deMax,
                    reset          = "weekly",
                    quests         = questSet(deRow.questIds or {}),
                    defaultNote    = "Disenchant items for " .. (deRow.label or "knowledge") .. " this week (" .. profLabel .. ").",
                }
            end

            if def.weeklyDropsQuestComplete then
                out[#out + 1] = {
                    id             = "prof_" .. key .. "_drops",
                    label          = def.weeklyDropsLabel or "Weekly Drops",
                    expansion      = "professions",
                    subsection     = key,
                    professionKey  = key,
                    type           = "quest_complete",
                    max            = 1,
                    reset          = "weekly",
                    quests         = questSet(dropIds),
                    defaultNote    = "Loot this week's " .. (def.weeklyDropsLabel or "profession treasures") .. " for " .. profLabel .. ".",
                }
            else
                out[#out + 1] = {
                    id             = "prof_" .. key .. "_drops",
                    label          = def.weeklyDropsLabel or "Weekly Drops",
                    expansion      = "professions",
                    subsection     = key,
                    professionKey  = key,
                    type           = "quest_count",
                    max            = dropMax,
                    reset          = "weekly",
                    quests         = questSet(dropIds),
                    defaultNote    = "Loot this week's " .. (def.weeklyDropsLabel or "profession treasures") .. " for " .. profLabel .. ".",
                }
            end

            out[#out + 1] = {
                id             = "prof_" .. key .. "_treatise",
                label          = "Treatise",
                expansion      = "professions",
                subsection     = key,
                professionKey  = key,
                type           = "quest_complete",
                max            = 1,
                reset          = "weekly",
                quests         = questSet({ def.treatiseQuestId }),
                defaultNote    = "Use this week's " .. profLabel .. " treatise for knowledge.",
            }

            out[#out + 1] = {
                id                  = "prof_" .. key .. "_catchup",
                label               = "Catch-up Knowledge",
                expansion           = "professions",
                subsection          = key,
                professionKey       = key,
                type                = "profession_catchup",
                catchupCurrencyId   = def.catchupCurrencyId,
                max                 = 1,
                reset               = "weekly",
                quests              = {},
                defaultNote         = "Spend leftover catch-up knowledge for " .. profLabel .. ". The row shows remaining currency.",
            }
        end
    end
    return out
end
