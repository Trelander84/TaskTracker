-- Core/DB.lua
-- Database initialization, UUID generation, and tree management
-- The tree is the single source of truth for all categories and tasks

TaskTracker = TaskTracker or {}

-- Max pinned command rows in the note window (Pin button). List uses a separate icon for command flyout vs notes.
TaskTracker.MAX_PINNED_COMMANDS = 3

-- ─────────────────────────────────────
-- UUID generation
-- Simple but collision-resistant for our use case
-- ─────────────────────────────────────
local uuidCounter = 0
function TaskTracker.GenerateUUID()
    uuidCounter = uuidCounter + 1
    return string.format("%08x-%04x-%04x-%04x",
        time() + uuidCounter,
        math.random(0, 65535),
        math.random(0, 65535),
        math.random(0, 65535)
    )
end

-- ─────────────────────────────────────
-- Node factories
-- Use these to create new nodes
-- ─────────────────────────────────────
function TaskTracker.NewGroupNode(name)
    return {
        id       = TaskTracker.GenerateUUID(),
        type     = "group",
        name     = name,
        expanded = true,
        children = {},
    }
end

local function NewModuleGroupNode(name, moduleGroupKey)
    local g = TaskTracker.NewGroupNode(name)
    g.moduleGroupKey = moduleGroupKey
    return g
end

--- Copy catalog/registry command specs onto a node, skipping commands already present.
function TaskTracker.AppendMissingCommandButtons(node, specList)
    if not node or type(specList) ~= "table" then return end
    if type(node.commandButtons) ~= "table" then node.commandButtons = {} end
    local have = {}
    local pinCount = 0
    for _, b in ipairs(node.commandButtons) do
        if type(b) == "table" then
            local cmd = tostring(b.command or "")
            if cmd ~= "" then have[cmd] = true end
            if b.pinned then pinCount = pinCount + 1 end
        end
    end
    local cap = TaskTracker.MAX_PINNED_COMMANDS or 3
    for _, b in ipairs(specList) do
        if type(b) == "table" then
            local cmd = b.command or ""
            if cmd ~= "" and not have[cmd] then
                local pin = b.pinned == true
                if pin then
                    pinCount = pinCount + 1
                    if pinCount > cap then pin = false end
                end
                table.insert(node.commandButtons, {
                    label   = b.label or "",
                    command = cmd,
                    icon    = TaskTracker.NormalizeCommandIcon and TaskTracker.NormalizeCommandIcon(b.icon, cmd) or (tonumber(b.icon) or 134400),
                    pinned  = pin,
                })
                have[cmd] = true
            end
        end
    end
end

function TaskTracker.NewTaskNode(name, reset, taskMax, advanced, excludeFromRollup, accountWide, showOnOtherCharacters)
    local m = tonumber(taskMax) or 1
    if m < 1 then m = 1 end
    if m > 99999999 then m = 99999999 end
    local node = {
        id              = TaskTracker.GenerateUUID(),
        type            = "task",
        name            = name,
        done            = false,
        reset           = reset or "none",
        taskMax         = m,
        taskCount       = 0,
        note            = "",
        commandButtons  = {},
        taskUserValue   = nil,
    }
    if excludeFromRollup then
        node.excludeFromRollup = true
    end
    if accountWide == true then
        node.accountWide = true
    else
        if showOnOtherCharacters == true then
            node.showOnOtherCharacters = true
        end
        if TaskTracker.GetCharProgressKey then
            local ok = TaskTracker.GetCharProgressKey()
            if ok then node.ownerCharKey = ok end
        end
    end
    if type(advanced) == "table" and advanced.type then
        node.advanced = advanced
    end
    return node
end

function TaskTracker.NewRegistryNode(registryEntryId)
    local n = {
        id                = TaskTracker.GenerateUUID(),
        type              = "registryEntry",
        registryEntryId   = registryEntryId,
        note              = "",
        commandButtons    = {},
    }
    local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[registryEntryId]
    if entry then
        TaskTracker.AppendMissingCommandButtons(n, entry.defaultCommandButtons)
    end
    return n
end

local function trimBuiltInNote(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function compactHowToForTooltip(h)
    h = trimBuiltInNote(h)
    if h == "" then return nil end
    h = h:gsub("%*%*", "")
    local para = h:match("^(.-)\n\n") or h
    para = trimBuiltInNote(para:gsub("%s+", " "))
    if para == "" then return nil end
    if #para > 280 then
        para = para:sub(1, 277) .. "..."
    end
    return para
end

local function addBuiltInNoteCandidate(out, seen, s)
    s = trimBuiltInNote(s)
    if s == "" or seen[s] then return end
    seen[s] = true
    out[#out + 1] = s
end

local function collectBuiltInNoteCandidates(entry, node)
    local out, seen = {}, {}
    if entry then
        addBuiltInNoteCandidate(out, seen, entry.defaultNote)
    end
    if node then
        if node.registryEntryId and TaskTracker.RegistryByID then
            local e = TaskTracker.RegistryByID[node.registryEntryId]
            if e then addBuiltInNoteCandidate(out, seen, e.defaultNote) end
        end
        if node.collectionFarmId and TaskTracker.RegistryByID then
            local e = TaskTracker.RegistryByID[node.collectionFarmId]
            if e then addBuiltInNoteCandidate(out, seen, e.defaultNote) end
        end
        -- Seeded collection achievement rows may use a shorter note than registry defaultNote.
        if node.collectionFarmId == "col_mount_emerald_skyfang" then
            addBuiltInNoteCandidate(out, seen,
                "Pro Poison Patroller: complete 250 Temple Patrols in the Vaults of Atal'Utek. Uses the in-game achievement bar.")
            addBuiltInNoteCandidate(out, seen,
                "Pro Poison Patroller: complete 250 Temple Patrols in the Vaults of Atal'Utek. Uses the in-game achievement bar (criteria 1). Completes when the achievement or the mount is done.")
        elseif node.collectionFarmId == "col_mount_venomous_coiler" then
            addBuiltInNoteCandidate(out, seen,
                "Assault the Vault: complete the 10 Vaults of Atal'Utek achievements. Uses the in-game criteria bar.")
        elseif node.collectionFarmId == "col_mount_auriferous_venomfang" then
            addBuiltInNoteCandidate(out, seen,
                "Treasures of Atal'Utek: loot the 22 treasures in the Vaults of Atal'Utek. Uses the in-game achievement bar.")
        elseif node.collectionFarmId == "col_toy_cursed_badge" then
            addBuiltInNoteCandidate(out, seen,
                "Student of Hissstory: find the 10 lore objects in the Vaults of Atal'Utek. Uses the in-game achievement bar.")
        elseif node.collectionFarmId == "col_pet_wild_caught" then
            addBuiltInNoteCandidate(out, seen,
                "The Coiled Isle Safari: catch all 8 wild pets. Uses the in-game achievement bar.")
        elseif node.collectionFarmId == "col_pet_three_eyed_fish" then
            addBuiltInNoteCandidate(out, seen,
                "Reward from Tipping the Scaled after Venom Trawler with Captain Tokka. Completes when the quest is done or you have the companion pet.")
            addBuiltInNoteCandidate(out, seen,
                "Reward from Tipping the Scaled (quest 97565) after Venom Trawler with Captain Tokka. Completes when you have the companion pet (item 279483).")
        elseif node.collectionFarmId == "col_pet_kiclak" then
            addBuiltInNoteCandidate(out, seen,
                "A Stack of Snacks: complete Olawu's world quest 5 times. Uses the in-game achievement bar.")
            addBuiltInNoteCandidate(out, seen,
                "A Stack of Snacks: finish Don't Be Afrayed, then complete Olawu's world quest 5 times. Uses the in-game achievement bar. Completes when the achievement or the pet is done.")
        elseif node.collectionFarmId == "col_pet_lil_mon" then
            addBuiltInNoteCandidate(out, seen,
                "Kill Big Mon on the Coiled Isle. Weekly account-wide, 5 kills.")
            addBuiltInNoteCandidate(out, seen,
                "Kill Big Mon on the Coiled Isle. Daily account-wide, 5 kills. The second line is your lifetime kills and the Rarity drop rate.")
            addBuiltInNoteCandidate(out, seen,
                "Kill Big Mon on the Coiled Isle. Daily account-wide, one kill. The second line shows your total kills and the Rarity drop rate.")
        elseif node.collectionFarmId == "col_rep_zuljarras_forces" then
            addBuiltInNoteCandidate(out, seen,
                "Coiled Isle Renown with Zul'jarra's Forces (Warband). Do isle rares, surges, and vaults to rank up. Complete at Renown 20.")
        elseif node.collectionFarmId == "col_currency_corrosive_coins" then
            addBuiltInNoteCandidate(out, seen,
                "Currency from the Altar of Corrosion in the Vaults of Atal'Utek.")
            addBuiltInNoteCandidate(out, seen,
                "Corrosive Coins from the Vaults of Atal'Utek (Altar of Corrosion). The bar is how many you have now. Completes at your goal (default 10000, enough for Caustic Venomfang).")
            addBuiltInNoteCandidate(out, seen,
                "Corrosive Coins from the Vaults of Atal'Utek. The bar is how many you have now.")
            addBuiltInNoteCandidate(out, seen,
                "Corrosive Coins from the Vaults of Atal'Utek (Altar of Corrosion, currency 3448). The bar is how many you have now. Completes at your goal (default 10000).")
        elseif node.collectionFarmId == "col_currency_voidlight_marl" then
            addBuiltInNoteCandidate(out, seen,
                "Midnight vendor currency from all zones. Weekly account-wide earned target (default 10000).")
        elseif node.collectionFarmId == "col_currency_remnant_of_anguish" then
            addBuiltInNoteCandidate(out, seen,
                "Prey currency from hunts. Spend it at Construct V'anore in Astalor's Sanctum. Weekly account-wide earned target (default 1000).")
            addBuiltInNoteCandidate(out, seen,
                "Prey currency from hunts. Spend it at Construct V'anore in Astalor's Sanctum. Weekly account-wide earned target (default 5000).")
        end
        if node.type == "task" and node.advanced and node.advanced.type == "collectable"
            and TaskTracker.GetCollectableEntry then
            local ent = TaskTracker.GetCollectableEntry(
                node.advanced.collectableExpansion,
                node.advanced.collectableCategory,
                node.advanced.collectableEntryId)
            if ent then
                addBuiltInNoteCandidate(out, seen, ent.defaultNote)
                addBuiltInNoteCandidate(out, seen, compactHowToForTooltip(ent.howTo))
                addBuiltInNoteCandidate(out, seen, ent.howTo)
            end
        end
    end
    return out
end

--- Built-in help for module / catalog rows. Shown on hover, not in the Notes field.
function TaskTracker.GetBuiltInRowTooltipText(entry, node)
    if node and type(node.generatedHelp) == "string" and node.generatedHelp ~= "" then
        return node.generatedHelp
    end
    local c = collectBuiltInNoteCandidates(entry, node)
    return c[1]
end

function TaskTracker.NoteMatchesBuiltInDefaults(note, entry, node)
    local n = trimBuiltInNote(note)
    if n == "" then return false end
    for _, cand in ipairs(collectBuiltInNoteCandidates(entry, node)) do
        if n == cand then return true end
    end
    return false
end

local function ClearMatchingBuiltInNotes(node)
    if type(node) ~= "table" then return end
    local entry
    if node.type == "registryEntry" and TaskTracker.RegistryByID then
        entry = TaskTracker.RegistryByID[node.registryEntryId]
    end
    if type(node.note) == "string" and node.note ~= "" then
        if TaskTracker.NoteMatchesBuiltInDefaults(node.note, entry, node) then
            node.note = ""
        end
    end
    if type(node.children) == "table" then
        for i = 1, #node.children do
            ClearMatchingBuiltInNotes(node.children[i])
        end
    end
end

-- Reset time calculation: Core/ResetSchedule.lua (TaskTracker.GetResetTimes)

-- Registry entry ids for default Midnight patch groups (must match Data\Registry.lua tree order)
local MIDNIGHT_PATCH_12_0_0_ORDER = {
    "prey_normal",
    "prey_hard",
    "prey_nightmare",
    "prey_nightmarish",
    "s1_halduron_weekly",
    "s1_lost_legends",
    "s1_fortify_runestones",
    "s1_stormarion_assault_wq",
    "s1_special_assignments",
}
local MIDNIGHT_PATCH_12_0_5_ORDER = {
    "s1_void_assaults",
}
local MIDNIGHT_PATCH_12_1_0_COILED_ORDER = {
    "s1_cursed_surges",
    "s1_open_sea_fishing",
    "s1_brinedrinker_gills",
    "s1_second_mate_sluggs",
    "s1_ethrandil",
}
local MIDNIGHT_PATCH_12_1_0_VAULTS_ORDER = {
    "s1_purging_the_vaults",
    "s1_hawkeye_soho",
    "s1_from_whence_it_came",
    "s1_dugal",
}
local MIDNIGHT_PATCH_12_1_5_AQIR_ORDER = {
    "p1215_aqir_satchel",
}
local MIDNIGHT_PATCH_12_1_5_REPUTATIONS_IDS = {
    "p1215_labyrinth_renown",
    "p1215_aqir_enclave",
}
local MIDNIGHT_PATCH_12_1_0_ORDER = {}
do
    for i = 1, #MIDNIGHT_PATCH_12_1_0_COILED_ORDER do
        MIDNIGHT_PATCH_12_1_0_ORDER[#MIDNIGHT_PATCH_12_1_0_ORDER + 1] = MIDNIGHT_PATCH_12_1_0_COILED_ORDER[i]
    end
    for i = 1, #MIDNIGHT_PATCH_12_1_0_VAULTS_ORDER do
        MIDNIGHT_PATCH_12_1_0_ORDER[#MIDNIGHT_PATCH_12_1_0_ORDER + 1] = MIDNIGHT_PATCH_12_1_0_VAULTS_ORDER[i]
    end
end

local MIDNIGHT_COLLECTIONS_TOYS_IDS = {
    "col_toy_ancient_amani_mask",
    "col_toy_idol_ulatek",
}
local MIDNIGHT_COLLECTIONS_MOUNTS_IDS = {
    "col_mount_sea_dwelling_isle_serpent",
    "col_mount_caustic_venomfang",
    "col_mount_indigo_coiled_horror",
    "col_mount_violet_backed_skyfang",
    "col_mount_spirit_tokjara",
}
-- Catalog-backed farm collectables seeded as advanced tasks (not registry rows).
local MIDNIGHT_COLLECTIONS_MOUNT_FARMS = {
    { expansion = "midnight", category = "mount", entryId = "ruby_writhe" },
    { expansion = "midnight", category = "mount", entryId = "topaz_skyfang" },
    { expansion = "midnight", category = "mount", entryId = "hexflame_reaver" },
}
local MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS = {
    { expansion = "midnight", category = "mount", entryId = "rootstalker_grimlynx" },
    { expansion = "midnight", category = "mount", entryId = "vibrant_petalwing" },
    { expansion = "midnight", category = "mount", entryId = "cerulean_hawkstrider" },
    { expansion = "midnight", category = "mount", entryId = "cobalt_dragonhawk" },
    { expansion = "midnight", category = "mount", entryId = "escaped_witherbark_pango" },
    { expansion = "midnight", category = "mount", entryId = "amani_sharptalon" },
    { expansion = "midnight", category = "mount", entryId = "sanguine_harrower" },
    { expansion = "midnight", category = "mount", entryId = "augmented_stormray" },
    { expansion = "midnight", category = "mount", entryId = "hexed_vilefeather_eagle" },
}
local MIDNIGHT_COLLECTIONS_PET_FARMS = {
    { expansion = "midnight", category = "pet", entryId = "poison_dart_frog" },
    { expansion = "midnight", category = "pet", entryId = "pale_hexscale" },
}
local MIDNIGHT_COLLECTIONS_TOY_FARMS = {
    { expansion = "midnight", category = "toy", entryId = "preyhunters_masquerade" },
}
local MIDNIGHT_COLLECTIONS_MOUNT_ACHIEVEMENTS = {
    {
        registryId = "col_mount_emerald_skyfang",
        name = "Emerald Skyfang",
        achievementId = 63653,
        achievementCriteriaIndex = 1,
        achievementMirrorGameTotals = false,
        reset = "weekly",
        taskMax = 10,
        secondLineGameBar = true,
        note = "Pro Poison Patroller: Temple Patrols in the Vaults of Atal'Utek. Weekly account-wide goal (default 10). The second line is the in-game bar, out of 250.",
    },
    {
        registryId = "col_mount_venomous_coiler",
        name = "Venomous Coiler",
        achievementId = 63630,
        achievementCriteriaIndex = 0,
        achievementMirrorGameTotals = true,
        reset = "none",
        taskMax = 10,
        note = "Assault the Vault: complete the 10 Vaults of Atal'Utek achievements. Uses the in-game criteria bar.",
    },
    {
        registryId = "col_mount_auriferous_venomfang",
        name = "Auriferous Venomfang",
        achievementId = 63359,
        achievementCriteriaIndex = 0,
        achievementMirrorGameTotals = true,
        reset = "none",
        taskMax = 22,
        note = "Treasures of Atal'Utek: loot the 22 treasures in the Vaults of Atal'Utek. Uses the in-game achievement bar.",
    },
}
local MIDNIGHT_COLLECTIONS_TOY_ACHIEVEMENTS = {
    {
        registryId = "col_toy_cursed_badge",
        name = "Cursed Badge of the Soulcoilers",
        achievementId = 63662,
        achievementCriteriaIndex = 0,
        achievementMirrorGameTotals = true,
        reset = "none",
        taskMax = 10,
        note = "Student of Hissstory: find the 10 lore objects in the Vaults of Atal'Utek. Uses the in-game achievement bar.",
    },
}
local MIDNIGHT_COLLECTIONS_PET_ACHIEVEMENTS = {
    {
        registryId = "col_pet_wild_caught",
        name = "The Coiled Isle Safari",
        achievementId = 62492,
        achievementCriteriaIndex = 0,
        achievementMirrorGameTotals = true,
        reset = "none",
        taskMax = 8,
        note = "The Coiled Isle Safari: catch all 8 wild pets. Uses the in-game achievement bar.",
    },
    {
        registryId = "col_pet_kiclak",
        name = "Ki'clak",
        achievementId = 63633,
        achievementCriteriaIndex = 1,
        achievementMirrorGameTotals = false,
        reset = "weekly",
        taskMax = 2,
        secondLineGameBar = true,
        note = "A Stack of Snacks: complete Olawu's world quest. Weekly account-wide goal (default 2). The second line is the in-game bar, out of 5.",
    },
}
local MIDNIGHT_COLLECTIONS_PET_KILLS = {
    {
        registryId = "col_pet_lil_mon",
        name = "Lil' Mon",
        npcIds = { 256631 },
        reset = "daily",
        taskMax = 1,
        accountWide = true,
        dropItemId = 280540,
        note = "Kill Big Mon on the Coiled Isle. Daily account-wide, one kill. The second line uses the Rarity drop rate when Rarity has that pet. Otherwise it shows your total kills.",
    },
}
local MIDNIGHT_COLLECTIONS_CURRENCY_ITEMS = {
    {
        registryId = "col_currency_corrosive_coins",
        name = "Corrosive Coins",
        currencyId = 3448,
        reset = "weekly",
        taskMax = 20000,
        itemTrackMode = "earned",
        accountWide = true,
        attSecondLine = true,
        note = "Currency from the Altar of Corrosion in the Vaults of Atal'Utek. Weekly account-wide earned target (default 20000).",
    },
}
local MIDNIGHT_1200_COLLECTIONS_CURRENCY_ITEMS = {
    {
        registryId = "col_currency_voidlight_marl",
        name = "Voidlight Marl",
        currencyId = 3316,
        reset = "weekly",
        taskMax = 10000,
        itemTrackMode = "earned",
        accountWide = true,
        attSecondLine = true,
        note = "Midnight vendor currency from all zones. Weekly account-wide earned target (default 10000).",
    },
    {
        registryId = "col_currency_remnant_of_anguish",
        name = "Remnant of Anguish",
        currencyId = 3392,
        reset = "weekly",
        taskMax = 1000,
        itemTrackMode = "earned",
        accountWide = true,
        attSecondLine = true,
        note = "Prey currency from hunts. Spend it at Construct V'anore in Astalor's Sanctum. Weekly account-wide earned target (default 1000).",
    },
}
local FARM_REGISTRY_TO_CATALOG = {
    col_mount_ruby_writhe = MIDNIGHT_COLLECTIONS_MOUNT_FARMS[1],
    col_mount_topaz_skyfang = MIDNIGHT_COLLECTIONS_MOUNT_FARMS[2],
    col_mount_hexflame_reaver = MIDNIGHT_COLLECTIONS_MOUNT_FARMS[3],
    col_mount_rootstalker_grimlynx = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[1],
    col_mount_vibrant_petalwing = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[2],
    col_mount_cerulean_hawkstrider = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[3],
    col_mount_cobalt_dragonhawk = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[4],
    col_mount_escaped_witherbark_pango = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[5],
    col_mount_amani_sharptalon = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[6],
    col_mount_sanguine_harrower = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[7],
    col_mount_augmented_stormray = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[8],
    col_mount_hexed_vilefeather_eagle = MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS[9],
    col_pet_poison_dart_frog = MIDNIGHT_COLLECTIONS_PET_FARMS[1],
    col_pet_pale_hexscale = MIDNIGHT_COLLECTIONS_PET_FARMS[2],
    col_toy_preyhunters_masquerade = MIDNIGHT_COLLECTIONS_TOY_FARMS[1],
}
local CATALOG_TO_FARM_REGISTRY = {
    ruby_writhe = "col_mount_ruby_writhe",
    topaz_skyfang = "col_mount_topaz_skyfang",
    hexflame_reaver = "col_mount_hexflame_reaver",
    rootstalker_grimlynx = "col_mount_rootstalker_grimlynx",
    vibrant_petalwing = "col_mount_vibrant_petalwing",
    cerulean_hawkstrider = "col_mount_cerulean_hawkstrider",
    cobalt_dragonhawk = "col_mount_cobalt_dragonhawk",
    escaped_witherbark_pango = "col_mount_escaped_witherbark_pango",
    amani_sharptalon = "col_mount_amani_sharptalon",
    sanguine_harrower = "col_mount_sanguine_harrower",
    augmented_stormray = "col_mount_augmented_stormray",
    hexed_vilefeather_eagle = "col_mount_hexed_vilefeather_eagle",
    poison_dart_frog = "col_pet_poison_dart_frog",
    pale_hexscale = "col_pet_pale_hexscale",
    preyhunters_masquerade = "col_toy_preyhunters_masquerade",
}
local CATALOG_TO_ACH_REGISTRY = {
    emerald_skyfang = "col_mount_emerald_skyfang",
    venomous_coiler = "col_mount_venomous_coiler",
    auriferous_venomfang = "col_mount_auriferous_venomfang",
    cursed_badge = "col_toy_cursed_badge",
    wild_caught_pets = "col_pet_wild_caught",
    kiclak = "col_pet_kiclak",
}
local ACH_REGISTRY_TO_SPEC = {}
local function indexCollectionAchievementSpecs(list)
    for i = 1, #list do
        local spec = list[i]
        ACH_REGISTRY_TO_SPEC[spec.registryId] = spec
    end
end
indexCollectionAchievementSpecs(MIDNIGHT_COLLECTIONS_MOUNT_ACHIEVEMENTS)
indexCollectionAchievementSpecs(MIDNIGHT_COLLECTIONS_TOY_ACHIEVEMENTS)
indexCollectionAchievementSpecs(MIDNIGHT_COLLECTIONS_PET_ACHIEVEMENTS)
local KILL_REGISTRY_TO_SPEC = {}
local CURRENCY_REGISTRY_TO_SPEC = {}
local function indexCollectionSpecs(list, dest)
    for i = 1, #list do
        local spec = list[i]
        dest[spec.registryId] = spec
    end
end
indexCollectionSpecs(MIDNIGHT_COLLECTIONS_PET_KILLS, KILL_REGISTRY_TO_SPEC)
indexCollectionSpecs(MIDNIGHT_COLLECTIONS_CURRENCY_ITEMS, CURRENCY_REGISTRY_TO_SPEC)
indexCollectionSpecs(MIDNIGHT_1200_COLLECTIONS_CURRENCY_ITEMS, CURRENCY_REGISTRY_TO_SPEC)
local MIDNIGHT_COLLECTIONS_MOUNT_SEEDED_IDS = {
    "col_mount_ruby_writhe",
    "col_mount_topaz_skyfang",
    "col_mount_hexflame_reaver",
    "col_mount_emerald_skyfang",
    "col_mount_venomous_coiler",
    "col_mount_auriferous_venomfang",
}
local MIDNIGHT_1200_COLLECTIONS_MOUNT_SEEDED_IDS = {
    "col_mount_rootstalker_grimlynx",
    "col_mount_vibrant_petalwing",
    "col_mount_cerulean_hawkstrider",
    "col_mount_cobalt_dragonhawk",
    "col_mount_escaped_witherbark_pango",
    "col_mount_amani_sharptalon",
    "col_mount_hexed_vilefeather_eagle",
    "col_mount_sanguine_harrower",
    "col_mount_augmented_stormray",
}
local MIDNIGHT_COLLECTIONS_TOY_SEEDED_IDS = {
    "col_toy_preyhunters_masquerade",
    "col_toy_cursed_badge",
}
local MIDNIGHT_COLLECTIONS_PET_SEEDED_IDS = {
    "col_pet_poison_dart_frog",
    "col_pet_pale_hexscale",
    "col_pet_wild_caught",
    "col_pet_kiclak",
    "col_pet_lil_mon",
}
local MIDNIGHT_COLLECTIONS_CURRENCY_SEEDED_IDS = {
    "col_currency_corrosive_coins",
}
local MIDNIGHT_1200_COLLECTIONS_CURRENCY_SEEDED_IDS = {
    "col_currency_voidlight_marl",
    "col_currency_remnant_of_anguish",
}

local function collectableTaskEntryId(node)
    if not node or node.type ~= "task" then return nil end
    local a = node.advanced
    if type(a) ~= "table" or a.type ~= "collectable" then return nil end
    local id = tostring(a.collectableEntryId or ""):lower()
    if id == "" then return nil end
    return id
end

--- Rare-drop mounts: second line is Rarity's attempt count and 1-in-N odds.
local RARE_KILL_MOUNT_SUBTEXT = {
    rootstalker_grimlynx = true,
    vibrant_petalwing = true,
    cerulean_hawkstrider = true,
    cobalt_dragonhawk = true,
    escaped_witherbark_pango = true,
    amani_sharptalon = true,
    sanguine_harrower = true,
    augmented_stormray = true,
    ruby_writhe = true,
    topaz_skyfang = true,
}

local function DefaultCollectableSubtext(entryId)
    entryId = tostring(entryId or ""):lower()
    if entryId == "hexed_vilefeather_eagle" then
        return {
            type = "item",
            itemKind = "item",
            itemIds = { 259361 },
            itemGoal = 1000,
        }
    end
    if RARE_KILL_MOUNT_SUBTEXT[entryId] then
        return {
            type = "mob_kill",
            useTask = true,
            showLifetime = true,
            showDrop = true,
        }
    end
    return nil
end

local function NewCatalogCollectableTaskNode(expansionId, categoryId, entryId)
    local ent = TaskTracker.GetCollectableEntry and TaskTracker.GetCollectableEntry(expansionId, categoryId, entryId)
    local name = (ent and ent.label) or entryId
    local goal = 30
    if ent then
        local g = tonumber(ent.defaultGoal)
        if g and g >= 1 then
            goal = math.floor(g)
        elseif ent.farm ~= true then
            goal = 1
        end
    end
    local adv = {
        type = "collectable",
        collectableExpansion = expansionId,
        collectableCategory = categoryId,
        collectableEntryId = entryId,
        collectableQuestIds = {},
    }
    if ent and type(ent.questIds) == "table" then
        for _, q in ipairs(ent.questIds) do
            local n = tonumber(q)
            if n and n > 0 then
                adv.collectableQuestIds[#adv.collectableQuestIds + 1] = n
            end
        end
    end
    local farmItemId = TaskTracker.CollectableEntryFarmItemId and TaskTracker.CollectableEntryFarmItemId(ent)
    if farmItemId then
        adv.collectableFarmItemId = farmItemId
    end
    local reset = "weekly"
    if ent then
        local dr = ent.defaultReset
        if dr == "daily" or dr == "weekly" or dr == "none" then
            reset = dr
        end
    end
    local node = TaskTracker.NewTaskNode(name, reset, goal, adv, false, true, nil)
    local sub = DefaultCollectableSubtext(entryId)
    if sub then
        node.subtext = sub
        node.subtextBuiltinStamp = "builtin"
    end
    node.collectionFarmId = CATALOG_TO_FARM_REGISTRY[entryId]
    if node.collectionFarmId then
        node.collectionFarmResetMigrated = true
    end
    TaskTracker.AppendMissingCommandButtons(node, ent and ent.defaultCommandButtons)
    return node
end

local function NewCollectionAchievementTaskNode(spec)
    if not spec then return nil end
    local adv = {
        type = "achievement",
        achievementId = tonumber(spec.achievementId) or 0,
        achievementCriteriaIndex = tonumber(spec.achievementCriteriaIndex) or 1,
        achievementMirrorGameTotals = spec.achievementMirrorGameTotals ~= false,
    }
    local node = TaskTracker.NewTaskNode(
        spec.name or "Achievement",
        spec.reset or "none",
        tonumber(spec.taskMax) or 1,
        adv,
        false,
        true,
        nil)
    node.collectionFarmId = spec.registryId
    node.collectionFarmResetMigrated = true
    if spec.secondLineGameBar then
        node.subtext = { type = "achievement", useTask = true, achievementTrackMode = "game" }
        node.subtextBuiltinStamp = "builtin"
    end
    local entry = TaskTracker.RegistryByID and spec.registryId and TaskTracker.RegistryByID[spec.registryId]
    TaskTracker.AppendMissingCommandButtons(node, entry and entry.defaultCommandButtons)
    return node
end

local function NewCollectionKillTaskNode(spec)
    if not spec then return nil end
    local ids = {}
    for i = 1, #(spec.npcIds or {}) do
        local n = tonumber(spec.npcIds[i])
        if n and n > 0 then ids[#ids + 1] = math.floor(n) end
    end
    local adv = {
        type = "mob_kill",
        mobKillMode = spec.mobKillMode or "world",
        mobIds = ids,
        mobAutoCount = 0,
    }
    local node = TaskTracker.NewTaskNode(
        spec.name or "Kill",
        spec.reset or "weekly",
        tonumber(spec.taskMax) or 5,
        adv,
        false,
        spec.accountWide ~= false,
        nil)
    node.collectionFarmId = spec.registryId
    node.collectionFarmResetMigrated = true
    local dropId = tonumber(spec.dropItemId)
    if dropId and dropId > 0 then
        node.subtext = {
            type = "mob_kill",
            useTask = true,
            showLifetime = true,
            showDrop = true,
            dropItemId = math.floor(dropId),
        }
        node.subtextBuiltinStamp = "builtin"
    end
    local entry = TaskTracker.RegistryByID and spec.registryId and TaskTracker.RegistryByID[spec.registryId]
    TaskTracker.AppendMissingCommandButtons(node, entry and entry.defaultCommandButtons)
    return node
end

local function NewCollectionCurrencyTaskNode(spec)
    if not spec then return nil end
    local cid = tonumber(spec.currencyId)
    local adv = {
        type = "item",
        itemKind = "currency",
        itemIds = (cid and cid > 0) and { cid } or {},
        itemTrackMode = spec.itemTrackMode or "total",
        itemAutoCount = 0,
    }
    local node = TaskTracker.NewTaskNode(
        spec.name or "Currency",
        spec.reset or "none",
        tonumber(spec.taskMax) or 10000,
        adv,
        false,
        spec.accountWide ~= false,
        nil)
    node.collectionFarmId = spec.registryId
    node.collectionFarmResetMigrated = true
    if spec.attSecondLine then
        node.subtext = { type = "item", useTask = true, itemAttTotal = true }
        node.subtextBuiltinStamp = "builtin"
    end
    local entry = TaskTracker.RegistryByID and spec.registryId and TaskTracker.RegistryByID[spec.registryId]
    TaskTracker.AppendMissingCommandButtons(node, entry and entry.defaultCommandButtons)
    return node
end

local function NewCollectionReputationTaskNode(entry)
    if type(entry) ~= "table" then return nil end
    local kind = tostring(entry.repKind or "renown"):lower()
    local weekly = tonumber(entry.weeklyGain)
    local target = math.max(1, math.floor(tonumber(entry.max) or 1))
    local goalType = (kind == "friendship") and "friendship" or "standing"
    local reset = entry.reset or "none"
    if kind ~= "friendship" and weekly and weekly >= 1 then
        goalType = "weekly_gain"
        target = math.floor(weekly)
        reset = "weekly"
    end
    local adv = {
        type = "reputation",
        repFactionId = tonumber(entry.factionId) or 0,
        repFactionName = entry.label or "",
        repGoalType = goalType,
        repStandingTarget = (goalType == "weekly_gain") and nil or target,
        repClassic = (kind == "classic") or nil,
    }
    local node = TaskTracker.NewTaskNode(entry.label or "Reputation", reset, target, adv, false, true, nil)
    node.collectionFarmId = entry.id
    node.collectionFarmResetMigrated = true
    local subMode = entry.renownSubtext and "renown" or (entry.standingSubtext and "standing") or nil
    if subMode then
        node.subtext = {
            type = "reputation",
            useTask = true,
            repDisplay = subMode,
            repFactionId = tonumber(entry.factionId) or 0,
            repFactionName = entry.label or "",
        }
        node.subtextBuiltinStamp = "builtin"
    end
    TaskTracker.AppendMissingCommandButtons(node, entry.defaultCommandButtons)
    return node
end

local BUILTIN_PROGRESS_KEYS = {
    "goldAutoCopper",
    "itemAutoCount",
    "weekStartAchTotal",
    "weekStartRepValue",
    "questWeekStartComplete",
    "questPeriodCredited",
    "questPeriodOrphanCredits",
    "questPeriodBaseline",
    "questPeriodTurnIns",
    "questPeriodRepeatCounts",
    "questPeriodBaselineFrozen",
    "mobAutoCount",
    "collectableInit",
    "collectableAutoCount",
    "collectableFishAttempts",
    "collectableCredited",
}

local function ApplyBuiltinSeedOntoNode(node, seed)
    if type(node) ~= "table" or type(seed) ~= "table" then return end
    node.name = seed.name
    node.reset = seed.reset
    node.taskMax = seed.taskMax
    node.note = seed.note or ""
    node.commandButtons = TaskTracker.DeepCopy(seed.commandButtons) or {}
    node.subtext = TaskTracker.DeepCopy(seed.subtext)
    node.subtextBuiltinStamp = seed.subtext and "builtin" or nil
    node.excludeFromRollup = seed.excludeFromRollup
    if seed.accountWide then
        node.accountWide = true
        node.showOnOtherCharacters = nil
        node.ownerCharKey = nil
    elseif seed.showOnOtherCharacters then
        node.accountWide = nil
        node.showOnOtherCharacters = true
    end
    node.taskUserValue = nil
    node.doneOverride = nil
    local old = node.advanced
    local newAdv = TaskTracker.DeepCopy(seed.advanced)
    if type(old) == "table" and type(newAdv) == "table" and old.type == newAdv.type then
        for _, k in ipairs(BUILTIN_PROGRESS_KEYS) do
            if old[k] ~= nil then
                newAdv[k] = old[k]
            end
        end
    else
        node.taskCount = 0
        node.done = false
    end
    node.advanced = newAdv
    if TaskTracker.SyncAdvancedTask then
        TaskTracker.SyncAdvancedTask(node)
    end
end

local function copyQuestIdList(ids)
    local out = {}
    if type(ids) ~= "table" then return out end
    for i = 1, #ids do
        local n = tonumber(ids[i])
        if n and n > 0 then
            out[#out + 1] = math.floor(n)
        end
    end
    return out
end

local function questIdsFromRegistrySet(set)
    local ids = {}
    for qid in pairs(set or {}) do
        local n = tonumber(qid)
        if n and n > 0 then
            ids[#ids + 1] = math.floor(n)
        end
    end
    table.sort(ids)
    return ids
end

--- Catalog order, so the editor shows the same quest ids every time.
local function professionQuestIdsForEntry(entry)
    if not entry then return {} end
    if entry.id == "s1_weekly_abundance" then
        return { 89507 }
    end
    local key = entry.professionKey
    local def = key and TaskTracker.ProfessionCatalog and TaskTracker.ProfessionCatalog[key]
    if not def then
        return questIdsFromRegistrySet(entry.quests)
    end
    if entry.id == "prof_" .. key .. "_weekly" then
        return copyQuestIdList(def.weeklyQuestIds)
    end
    if entry.id == "prof_" .. key .. "_drops" then
        return copyQuestIdList(def.weeklyDropIds)
    end
    if entry.id == "prof_" .. key .. "_treatise" then
        local q = tonumber(def.treatiseQuestId)
        if q and q > 0 then return { math.floor(q) } end
        return {}
    end
    local di = type(entry.id) == "string" and entry.id:match("^prof_" .. key .. "_disenchant_(%d+)$")
    if di and type(def.weeklyDisenchantRows) == "table" then
        local row = def.weeklyDisenchantRows[tonumber(di)]
        if row then return copyQuestIdList(row.questIds) end
    end
    return questIdsFromRegistrySet(entry.quests)
end

local function NewProfessionTaskNode(entry)
    if type(entry) ~= "table" or entry.expansion ~= "professions" then return nil end
    local node
    if entry.type == "profession_catchup" then
        local cid = tonumber(entry.catchupCurrencyId)
        local adv = {
            type = "item",
            itemKind = "currency",
            itemIds = (cid and cid > 0) and { math.floor(cid) } or {},
            itemTrackMode = "remaining",
        }
        node = TaskTracker.NewTaskNode(entry.label or "Catch-up Knowledge", entry.reset or "weekly", 1, adv, false, false, true)
    elseif entry.type == "quest_complete" or entry.type == "quest_count" then
        local adv = {
            type = "quest",
            questIds = professionQuestIdsForEntry(entry),
        }
        local max = tonumber(entry.max) or 1
        if entry.type == "quest_complete" then max = 1 end
        node = TaskTracker.NewTaskNode(entry.label or "Profession", entry.reset or "weekly", max, adv, false, false, true)
    else
        return nil
    end
    if not node then return nil end
    node.collectionFarmId = entry.id
    node.collectionFarmResetMigrated = true
    TaskTracker.AppendMissingCommandButtons(node, entry.defaultCommandButtons)
    return node
end

function TaskTracker.BuildBuiltinTaskSeed(registryId)
    if type(registryId) ~= "string" or registryId == "" then return nil end
    local farm = FARM_REGISTRY_TO_CATALOG[registryId]
    if farm then
        return NewCatalogCollectableTaskNode(farm.expansion, farm.category, farm.entryId)
    end
    local ach = ACH_REGISTRY_TO_SPEC[registryId]
    if ach then return NewCollectionAchievementTaskNode(ach) end
    local kill = KILL_REGISTRY_TO_SPEC[registryId]
    if kill then return NewCollectionKillTaskNode(kill) end
    local cur = CURRENCY_REGISTRY_TO_SPEC[registryId]
    if cur then return NewCollectionCurrencyTaskNode(cur) end
    local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[registryId]
    if type(entry) ~= "table" then return nil end
    if entry.type == "collectable_owned" and TaskTracker.FindCollectableSpecByItemId then
        local spec = TaskTracker.FindCollectableSpecByItemId(entry.itemId)
        if spec then
            local node = NewCatalogCollectableTaskNode(spec.expansion, spec.category, spec.entryId)
            if node then
                node.collectionFarmId = registryId
                node.collectionFarmResetMigrated = true
                node.reset = entry.reset or "none"
            end
            return node
        end
    end
    if entry.type == "reputation_standing" then
        return NewCollectionReputationTaskNode(entry)
    end
    if entry.expansion == "professions" then
        return NewProfessionTaskNode(entry)
    end
    return nil
end

function TaskTracker.ResetBuiltinTaskToSeed(registryId)
    if not registryId or not TaskTracker.WalkTree then return end
    local seed = TaskTracker.BuildBuiltinTaskSeed(registryId)
    if not seed then return end
    TaskTracker.WalkTree(function(node)
        if node.type == "task" and node.collectionFarmId == registryId then
            ApplyBuiltinSeedOntoNode(node, seed)
        end
    end)
    if TaskTracker.InvalidateAdvancedTaskIndex then
        TaskTracker.InvalidateAdvancedTaskIndex()
    end
    if TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
end

local function copyUserNoteIfCustom(fromNode, toNode)
    if type(fromNode) ~= "table" or type(toNode) ~= "table" then return end
    local n = type(fromNode.note) == "string" and fromNode.note or ""
    if n == "" then return end
    local entry
    if fromNode.registryEntryId and TaskTracker.RegistryByID then
        entry = TaskTracker.RegistryByID[fromNode.registryEntryId]
    end
    if TaskTracker.NoteMatchesBuiltInDefaults and TaskTracker.NoteMatchesBuiltInDefaults(n, entry, fromNode) then
        return
    end
    toNode.note = n
end

local function ConvertFarmRegistryNode(regNode)
    local spec = regNode and FARM_REGISTRY_TO_CATALOG[regNode.registryEntryId]
    if not spec then return nil end
    local task = NewCatalogCollectableTaskNode(spec.expansion, spec.category, spec.entryId)
    copyUserNoteIfCustom(regNode, task)
    if type(regNode.commandButtons) == "table" and #regNode.commandButtons > 0 then
        task.commandButtons = regNode.commandButtons
    end
    return task
end

local function ConvertFarmRegistryNodesInTree(node)
    if not node or type(node.children) ~= "table" then return end
    for i, ch in ipairs(node.children) do
        if type(ch) == "table" then
            if ch.type == "registryEntry" and FARM_REGISTRY_TO_CATALOG[ch.registryEntryId] then
                node.children[i] = ConvertFarmRegistryNode(ch)
            elseif ch.type == "registryEntry" and ACH_REGISTRY_TO_SPEC[ch.registryEntryId] then
                local task = NewCollectionAchievementTaskNode(ACH_REGISTRY_TO_SPEC[ch.registryEntryId])
                if task then
                    copyUserNoteIfCustom(ch, task)
                    node.children[i] = task
                end
            elseif ch.type == "registryEntry" and KILL_REGISTRY_TO_SPEC[ch.registryEntryId] then
                local task = NewCollectionKillTaskNode(KILL_REGISTRY_TO_SPEC[ch.registryEntryId])
                if task then
                    copyUserNoteIfCustom(ch, task)
                    node.children[i] = task
                end
            elseif ch.type == "registryEntry" and CURRENCY_REGISTRY_TO_SPEC[ch.registryEntryId] then
                local task = NewCollectionCurrencyTaskNode(CURRENCY_REGISTRY_TO_SPEC[ch.registryEntryId])
                if task then
                    copyUserNoteIfCustom(ch, task)
                    node.children[i] = task
                end
            elseif ch.type == "group" or ch.type == "root" then
                ConvertFarmRegistryNodesInTree(ch)
            end
        end
    end
end

local function SeedMissingCollectionFarmTasks(group, farmSpecs)
    if not group then return end
    group.children = group.children or {}
    local have = {}
    for _, ch in ipairs(group.children) do
        local eid = collectableTaskEntryId(ch)
        if eid then
            have[eid] = true
            if not ch.collectionFarmId and CATALOG_TO_FARM_REGISTRY[eid] then
                ch.collectionFarmId = CATALOG_TO_FARM_REGISTRY[eid]
            end
        end
    end
    for i = #farmSpecs, 1, -1 do
        local spec = farmSpecs[i]
        local eid = spec and spec.entryId
        if eid and not have[eid] then
            table.insert(group.children, 1, NewCatalogCollectableTaskNode(spec.expansion, spec.category, eid))
            have[eid] = true
        end
    end
end

local function OrderCollectionFarmTasks(group, farmSpecs)
    if not group or type(group.children) ~= "table" then return end
    local byId, rest = {}, {}
    for _, ch in ipairs(group.children) do
        local eid = collectableTaskEntryId(ch)
        local placed = false
        if eid then
            for _, spec in ipairs(farmSpecs) do
                if spec.entryId == eid then
                    byId[eid] = ch
                    placed = true
                    break
                end
            end
        end
        if not placed then
            rest[#rest + 1] = ch
        end
    end
    local kids = {}
    for _, spec in ipairs(farmSpecs) do
        local n = spec and byId[spec.entryId]
        if n then kids[#kids + 1] = n end
    end
    for i = 1, #rest do
        kids[#kids + 1] = rest[i]
    end
    group.children = kids
end

local function isSeededCollectionRegistryId(rid)
    if not rid then return false end
    return FARM_REGISTRY_TO_CATALOG[rid]
        or ACH_REGISTRY_TO_SPEC[rid]
        or KILL_REGISTRY_TO_SPEC[rid]
        or CURRENCY_REGISTRY_TO_SPEC[rid]
        or false
end

local function ConvertOwnedAndReputationNodesInTree(node)
    if not node or type(node.children) ~= "table" then return end
    for i, ch in ipairs(node.children) do
        if type(ch) == "table" then
            if ch.type == "registryEntry" and ch.registryEntryId and not isSeededCollectionRegistryId(ch.registryEntryId) then
                local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[ch.registryEntryId]
                local kind = entry and entry.type
                if kind == "collectable_owned" or kind == "reputation_standing" then
                    local task = TaskTracker.BuildBuiltinTaskSeed(ch.registryEntryId)
                    if task and task.advanced and (task.advanced.type == "collectable" or task.advanced.type == "reputation") then
                        copyUserNoteIfCustom(ch, task)
                        if type(ch.commandButtons) == "table" and #ch.commandButtons > 0 then
                            task.commandButtons = ch.commandButtons
                        end
                        node.children[i] = task
                    end
                end
            elseif ch.type == "group" or ch.type == "root" then
                ConvertOwnedAndReputationNodesInTree(ch)
            end
        end
    end
end

local function SeedMissingCollectionAchievementTasks(group, specs)
    if not group then return end
    group.children = group.children or {}
    local have = {}
    local drop = {}
    for i, ch in ipairs(group.children) do
        if ch then
            local rid = ch.collectionFarmId
            if (not rid or rid == "") and ch.type == "task" then
                local eid = collectableTaskEntryId(ch)
                if eid and CATALOG_TO_ACH_REGISTRY[eid] then
                    rid = CATALOG_TO_ACH_REGISTRY[eid]
                end
            end
            if ch.type == "registryEntry" and ACH_REGISTRY_TO_SPEC[ch.registryEntryId] then
                rid = ch.registryEntryId
            end
            if rid and ACH_REGISTRY_TO_SPEC[rid] then
                if have[rid] then
                    drop[#drop + 1] = i
                else
                    if not (ch.advanced and ch.advanced.type == "achievement") then
                        local task = NewCollectionAchievementTaskNode(ACH_REGISTRY_TO_SPEC[rid])
                        if task then
                            copyUserNoteIfCustom(ch, task)
                            group.children[i] = task
                        end
                    elseif not ch.collectionFarmId then
                        ch.collectionFarmId = rid
                    end
                    have[rid] = true
                end
            end
        end
    end
    for i = #drop, 1, -1 do
        table.remove(group.children, drop[i])
    end
    for i = #specs, 1, -1 do
        local spec = specs[i]
        local rid = spec and spec.registryId
        if rid and not have[rid] then
            table.insert(group.children, 1, NewCollectionAchievementTaskNode(spec))
            have[rid] = true
        end
    end
end

local function SeedMissingCollectionSpecTasks(group, specs, specById, expectedType, factory)
    if not group then return end
    group.children = group.children or {}
    local have = {}
    local drop = {}
    for i, ch in ipairs(group.children) do
        if ch then
            local rid = ch.collectionFarmId
            if ch.type == "registryEntry" and specById[ch.registryEntryId] then
                rid = ch.registryEntryId
            end
            if rid and specById[rid] then
                if have[rid] then
                    drop[#drop + 1] = i
                else
                    if not (ch.advanced and ch.advanced.type == expectedType) then
                        local task = factory(specById[rid])
                        if task then
                            copyUserNoteIfCustom(ch, task)
                            group.children[i] = task
                        end
                    elseif not ch.collectionFarmId then
                        ch.collectionFarmId = rid
                    end
                    have[rid] = true
                end
            end
        end
    end
    for i = #drop, 1, -1 do
        table.remove(group.children, drop[i])
    end
    for i = #specs, 1, -1 do
        local spec = specs[i]
        local rid = spec and spec.registryId
        if rid and not have[rid] then
            table.insert(group.children, 1, factory(spec))
            have[rid] = true
        end
    end
end

local function OrderCollectionSeededTasks(group, orderedFarmIds)
    if not group or type(group.children) ~= "table" then return end
    local byId, rest = {}, {}
    local want = {}
    for _, rid in ipairs(orderedFarmIds or {}) do
        want[rid] = true
    end
    for _, ch in ipairs(group.children) do
        local rid = ch and ch.collectionFarmId
        if rid and want[rid] and not byId[rid] then
            byId[rid] = ch
        else
            rest[#rest + 1] = ch
        end
    end
    local kids = {}
    for _, rid in ipairs(orderedFarmIds or {}) do
        local n = byId[rid]
        if n then kids[#kids + 1] = n end
    end
    for i = 1, #rest do
        kids[#kids + 1] = rest[i]
    end
    group.children = kids
end

local MIDNIGHT_COLLECTIONS_PETS_IDS = {
    "col_pet_corrosive_writhling",
    "col_pet_volatile_venomfang",
    "col_pet_snekzali",
    "col_pet_venom_elemental",
    "col_pet_cauldron_concoction",
    "col_pet_zan",
    "col_pet_three_eyed_fish",
}
local MIDNIGHT_COLLECTIONS_CURRENCY_IDS = {
    "col_currency_corrosive_coins",
}
local MIDNIGHT_COLLECTIONS_REPUTATIONS_IDS = {
    "col_rep_zuljarras_forces",
    "col_rep_captain_tokka",
    "col_rep_delvers_journey",
}
local MIDNIGHT_1200_COLLECTIONS_MOUNT_OWNED_IDS = {
    "col_mount_duskbrute_harrower",
}
local MIDNIGHT_1200_COLLECTIONS_PETS_IDS = {
    "col_pet_nova",
}

local SEASONAL_GENERAL_IDS = {
    "s1_ritual_sites",
}

local SEASONAL_DELVES_IDS = {
    "seasonal_delves_gilded",
    "seasonal_delves_bounty",
    "seasonal_delves_nullaeus",
}

local SEASONAL_VAULT_IDS = {
    "seasonal_vault_raid",
    "seasonal_vault_dungeon",
    "seasonal_vault_world",
}

local SEASONAL_MPLUS_IDS = {
    "seasonal_dungeon_normal",
    "seasonal_dungeon_heroic",
    "seasonal_mplus_hint_end",
    "seasonal_mplus_hint_vault",
}

local SEASONAL_RAID_IDS = {
    "seasonal_raid_normal",
    "seasonal_raid_vault_normal",
    "seasonal_raid_heroic",
    "seasonal_raid_vault_heroic",
    "seasonal_raid_mythic",
    "seasonal_raid_vault_mythic",
}

-- Registry rows at Professions root (not under a learned-profession subgroup).
local PROFESSIONS_SHARED_REGISTRY_IDS = {
    "s1_weekly_abundance",
}

local function FindChildGroupByModuleKey(parent, key)
    if not parent then return nil end
    for _, ch in ipairs(parent.children or {}) do
        if ch and ch.type == "group" and ch.moduleGroupKey == key then
            return ch
        end
    end
end

local function EnsureChildModuleGroup(parent, name, key)
    local g = FindChildGroupByModuleKey(parent, key)
    if not g then
        g = NewModuleGroupNode(name, key)
        parent.children = parent.children or {}
        table.insert(parent.children, g)
    else
        g.moduleGroupKey = key
    end
    g.children = g.children or {}
    return g
end

local function AppendMissingRegistryIds(group, orderedIds)
    local have = {}
    for _, ch in ipairs(group.children or {}) do
        if ch and ch.type == "registryEntry" and ch.registryEntryId then
            have[ch.registryEntryId] = true
        elseif ch and ch.type == "task" and type(ch.collectionFarmId) == "string" and ch.collectionFarmId ~= "" then
            have[ch.collectionFarmId] = true
        end
    end
    group.children = group.children or {}
    for _, rid in ipairs(orderedIds) do
        if not have[rid] then
            table.insert(group.children, TaskTracker.NewRegistryNode(rid))
            have[rid] = true
        end
    end
end

local function BuildPatch1210CollectionsGroup()
    local coll = NewModuleGroupNode("Collections", "patch_12_1_0_collections")
    local toys = NewModuleGroupNode("Toys", "patch_12_1_0_collections_toys")
    local mounts = NewModuleGroupNode("Mounts", "patch_12_1_0_collections_mounts")
    local pets = NewModuleGroupNode("Pets", "patch_12_1_0_collections_pets")
    local currency = NewModuleGroupNode("Currency", "patch_12_1_0_collections_currency")
    local reps = NewModuleGroupNode("Reputations", "patch_12_1_0_collections_reputations")
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_TOY_FARMS) do
        table.insert(toys.children, NewCatalogCollectableTaskNode(spec.expansion, spec.category, spec.entryId))
    end
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_TOY_ACHIEVEMENTS) do
        table.insert(toys.children, NewCollectionAchievementTaskNode(spec))
    end
    for _, regId in ipairs(MIDNIGHT_COLLECTIONS_TOYS_IDS) do
        table.insert(toys.children, TaskTracker.NewRegistryNode(regId))
    end
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_MOUNT_FARMS) do
        table.insert(mounts.children, NewCatalogCollectableTaskNode(spec.expansion, spec.category, spec.entryId))
    end
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_MOUNT_ACHIEVEMENTS) do
        table.insert(mounts.children, NewCollectionAchievementTaskNode(spec))
    end
    for _, regId in ipairs(MIDNIGHT_COLLECTIONS_MOUNTS_IDS) do
        table.insert(mounts.children, TaskTracker.NewRegistryNode(regId))
    end
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_PET_FARMS) do
        table.insert(pets.children, NewCatalogCollectableTaskNode(spec.expansion, spec.category, spec.entryId))
    end
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_PET_ACHIEVEMENTS) do
        table.insert(pets.children, NewCollectionAchievementTaskNode(spec))
    end
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_PET_KILLS) do
        table.insert(pets.children, NewCollectionKillTaskNode(spec))
    end
    for _, regId in ipairs(MIDNIGHT_COLLECTIONS_PETS_IDS) do
        table.insert(pets.children, TaskTracker.NewRegistryNode(regId))
    end
    for _, spec in ipairs(MIDNIGHT_COLLECTIONS_CURRENCY_ITEMS) do
        table.insert(currency.children, NewCollectionCurrencyTaskNode(spec))
    end
    for _, regId in ipairs(MIDNIGHT_COLLECTIONS_REPUTATIONS_IDS) do
        table.insert(reps.children, TaskTracker.NewRegistryNode(regId))
    end
    table.insert(coll.children, toys)
    table.insert(coll.children, mounts)
    table.insert(coll.children, pets)
    table.insert(coll.children, currency)
    table.insert(coll.children, reps)
    return coll
end

local function BuildPatch1200CollectionsGroup()
    local coll = NewModuleGroupNode("Collections", "patch_12_0_0_collections")
    local mounts = NewModuleGroupNode("Mounts", "patch_12_0_0_collections_mounts")
    for _, spec in ipairs(MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS) do
        table.insert(mounts.children, NewCatalogCollectableTaskNode(spec.expansion, spec.category, spec.entryId))
    end
    for _, regId in ipairs(MIDNIGHT_1200_COLLECTIONS_MOUNT_OWNED_IDS) do
        table.insert(mounts.children, TaskTracker.NewRegistryNode(regId))
    end
    local pets = NewModuleGroupNode("Pets", "patch_12_0_0_collections_pets")
    for _, regId in ipairs(MIDNIGHT_1200_COLLECTIONS_PETS_IDS) do
        table.insert(pets.children, TaskTracker.NewRegistryNode(regId))
    end
    local currency = NewModuleGroupNode("Currency", "patch_12_0_0_collections_currency")
    for _, spec in ipairs(MIDNIGHT_1200_COLLECTIONS_CURRENCY_ITEMS) do
        table.insert(currency.children, NewCollectionCurrencyTaskNode(spec))
    end
    table.insert(coll.children, mounts)
    table.insert(coll.children, pets)
    table.insert(coll.children, currency)
    return coll
end

-- ─────────────────────────────────────
-- Build default tree
-- Called on first ever load
-- ─────────────────────────────────────
local function BuildPowerGroupTree()
    local g = NewModuleGroupNode("Power", "power")
    if TaskTracker.GetEntriesForPowerModule then
        for _, e in ipairs(TaskTracker.GetEntriesForPowerModule()) do
            table.insert(g.children, TaskTracker.NewRegistryNode(e.id))
        end
    end
    return g
end

local WELCOME_TASKS = {
    { name = "Create new tasks in Edit mode", icon = "edit" },
    { name = "The gear icon opens Options", icon = "gear" },
    { name = "Turn on more modules in Options" },
    { name = "Check these off when you're done." },
    { name = "They delete themselves." },
}

function TaskTracker.NewWelcomeTasksGroup()
    local g = TaskTracker.NewGroupNode("Welcome Tasks")
    g.id = "welcome_tasks"
    g.welcomeGroup = true
    g.expanded = true
    for i, spec in ipairs(WELCOME_TASKS) do
        local n = TaskTracker.NewTaskNode(spec.name, "temporary", 1, nil, nil, true)
        n.id = "welcome_task_" .. i
        n.welcomeTask = true
        if spec.icon then n.welcomeIcon = spec.icon end
        g.children[#g.children + 1] = n
    end
    return g
end

local function BuildDefaultTree()
    local root = {
        id       = "root",
        type     = "root",
        children = {},
    }

    table.insert(root.children, TaskTracker.NewWelcomeTasksGroup())
    table.insert(root.children, BuildPowerGroupTree())

    -- Seasonal Activities (General, Vault Status, Delves, Dungeons, Raids)
    local seasonalGroup = NewModuleGroupNode("Seasonal Activities", "seasonal_activities")
    local generalGroup = NewModuleGroupNode("General", "seasonal_general")
    for _, regId in ipairs(SEASONAL_GENERAL_IDS) do
        table.insert(generalGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local delvesGroup = NewModuleGroupNode("Delves", "seasonal_delves")
    for _, regId in ipairs(SEASONAL_DELVES_IDS) do
        table.insert(delvesGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local vaultGroup = NewModuleGroupNode("Vault Status", "seasonal_vault")
    for _, regId in ipairs(SEASONAL_VAULT_IDS) do
        table.insert(vaultGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local mplusGroup = NewModuleGroupNode(
        TaskTracker.MPLUS_SEASONAL_GROUP_NAME or "Mythic+",
        "seasonal_mplus"
    )
    for _, regId in ipairs(SEASONAL_MPLUS_IDS) do
        table.insert(mplusGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local raidGroup = NewModuleGroupNode("Raids", "seasonal_raid")
    for _, regId in ipairs(SEASONAL_RAID_IDS) do
        table.insert(raidGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    table.insert(seasonalGroup.children, generalGroup)
    table.insert(seasonalGroup.children, vaultGroup)
    table.insert(seasonalGroup.children, delvesGroup)
    table.insert(seasonalGroup.children, mplusGroup)
    table.insert(seasonalGroup.children, raidGroup)
    table.insert(root.children, seasonalGroup)

    local patch1215 = NewModuleGroupNode("Patch 12.1.5", "patch_12_1_5")
    local aqir = NewModuleGroupNode("Aqir Invasions", "patch_12_1_5_aqir")
    for _, regId in ipairs(MIDNIGHT_PATCH_12_1_5_AQIR_ORDER) do
        table.insert(aqir.children, TaskTracker.NewRegistryNode(regId))
    end
    local coll1215 = NewModuleGroupNode("Collections", "patch_12_1_5_collections")
    local reps1215 = NewModuleGroupNode("Reputations", "patch_12_1_5_collections_reputations")
    for _, regId in ipairs(MIDNIGHT_PATCH_12_1_5_REPUTATIONS_IDS) do
        table.insert(reps1215.children, TaskTracker.NewRegistryNode(regId))
    end
    table.insert(coll1215.children, reps1215)
    table.insert(patch1215.children, aqir)
    table.insert(patch1215.children, coll1215)
    table.insert(root.children, patch1215)

    local patch1210 = NewModuleGroupNode("Patch 12.1.0", "patch_12_1_0")
    local coiledIsle = NewModuleGroupNode("The Coiled Isle", "patch_12_1_0_coiled_isle")
    for _, regId in ipairs(MIDNIGHT_PATCH_12_1_0_COILED_ORDER) do
        table.insert(coiledIsle.children, TaskTracker.NewRegistryNode(regId))
    end
    local vaultsGroup = NewModuleGroupNode("Vaults of Atal'Utek", "patch_12_1_0_vaults")
    for _, regId in ipairs(MIDNIGHT_PATCH_12_1_0_VAULTS_ORDER) do
        table.insert(vaultsGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    table.insert(coiledIsle.children, vaultsGroup)
    table.insert(patch1210.children, coiledIsle)
    table.insert(patch1210.children, BuildPatch1210CollectionsGroup())
    table.insert(root.children, patch1210)

    local patch1205 = NewModuleGroupNode("Patch 12.0.5", "patch_12_0_5")
    for _, regId in ipairs(MIDNIGHT_PATCH_12_0_5_ORDER) do
        table.insert(patch1205.children, TaskTracker.NewRegistryNode(regId))
    end
    table.insert(root.children, patch1205)

    local patch1200 = NewModuleGroupNode("Patch 12.0.0", "patch_12_0_0")
    for _, regId in ipairs(MIDNIGHT_PATCH_12_0_0_ORDER) do
        table.insert(patch1200.children, TaskTracker.NewRegistryNode(regId))
    end
    table.insert(patch1200.children, BuildPatch1200CollectionsGroup())
    table.insert(root.children, patch1200)

    return root
end
TaskTracker.BuildDefaultTree = BuildDefaultTree

local function TreeHasRegistryEntry(rootNode, regId)
    local found = false
    TaskTracker.WalkTree(function(node)
        if node.type == "registryEntry" and node.registryEntryId == regId then
            found = true
        end
    end, rootNode)
    return found
end

local function FindRootGroupByName(rootNode, name)
    for _, ch in ipairs(rootNode.children or {}) do
        if ch and ch.type == "group" and ch.name == name then
            return ch
        end
    end
end

local function FindRootGroupByModuleKey(rootNode, moduleGroupKey)
    for _, ch in ipairs(rootNode.children or {}) do
        if ch and ch.type == "group" and ch.moduleGroupKey == moduleGroupKey then
            return ch
        end
    end
end

local function RegistryIdSet(orderedIds)
    local s = {}
    for _, id in ipairs(orderedIds or {}) do
        s[id] = true
    end
    return s
end

local PROFESSIONS_SHARED_REGISTRY_SET = nil
local function ProfessionsSharedRegistrySet()
    if not PROFESSIONS_SHARED_REGISTRY_SET then
        PROFESSIONS_SHARED_REGISTRY_SET = RegistryIdSet(PROFESSIONS_SHARED_REGISTRY_IDS)
    end
    return PROFESSIONS_SHARED_REGISTRY_SET
end

local function GroupHasAnyRegistryId(group, idSet)
    if not group or not idSet then return false end
    for _, ch in ipairs(group.children or {}) do
        if ch.type == "registryEntry" and ch.registryEntryId and idSet[ch.registryEntryId] then
            return true
        end
    end
    return false
end

--- Unmigrated module group: matching registry content and no moduleGroupKey yet.
--- Does not match a custom group that only shares the display name.
local function FindRootGroupByModuleKeyOrContent(rootNode, moduleGroupKey, idSet)
    local g = FindRootGroupByModuleKey(rootNode, moduleGroupKey)
    if g then return g end
    if not idSet then return nil end
    for _, ch in ipairs(rootNode.children or {}) do
        if ch and ch.type == "group" and not ch.moduleGroupKey and GroupHasAnyRegistryId(ch, idSet) then
            return ch
        end
    end
end

local function GroupHasRegistryIdPrefix(group, prefix)
    if not group or not prefix then return false end
    for _, ch in ipairs(group.children or {}) do
        if ch.type == "registryEntry" and ch.registryEntryId and ch.registryEntryId:match("^" .. prefix) then
            return true
        end
    end
    return false
end

local function BuildPowerRegistryIdSet()
    local s = {}
    if TaskTracker.GetEntriesForPowerModule then
        for _, e in ipairs(TaskTracker.GetEntriesForPowerModule()) do
            s[e.id] = true
        end
    end
    return s
end

local function GroupHasSeasonalModuleRegistry(group)
    if not group or group.type ~= "group" then return false end
    for _, ch in ipairs(group.children or {}) do
        if ch.type == "registryEntry" and ch.registryEntryId then
            local rid = ch.registryEntryId
            if rid:match("^seasonal_") or rid == "s1_ritual_sites" then
                return true
            end
        elseif ch.type == "group" and GroupHasSeasonalModuleRegistry(ch) then
            return true
        end
    end
    return false
end

local function ProfessionCatalogKeyForGroupName(name)
    if not name or not TaskTracker.ProfessionCatalog then return nil end
    for key, def in pairs(TaskTracker.ProfessionCatalog) do
        if def.label == name then
            return key
        end
    end
end

--- Nil when this name can be saved. A second root "Professions", or a profession name under that group, is removed on the next sync.
function TaskTracker.GroupNameReservedReason(name, parent, existingNode)
    if type(name) ~= "string" or name == "" or not parent then return nil end
    if parent.type == "root" and name == "Professions" then
        for _, ch in ipairs(parent.children or {}) do
            if ch and ch.type == "group" and ch.name == "Professions" and ch ~= existingNode then
                return "Professions is already a module group. Pick another name."
            end
        end
    end
    local underProfessions = parent.type == "group"
        and (parent.moduleGroupKey == "professions" or (not parent.moduleGroupKey and parent.name == "Professions"))
    if underProfessions and ProfessionCatalogKeyForGroupName(name) then
        if not (existingNode and existingNode.name == name) then
            return name .. " is already a profession group. Pick another name."
        end
    end
    return nil
end

local function HasMidnightPatchModuleGroups(rootNode)
    local g1200 = FindRootGroupByModuleKey(rootNode, "patch_12_0_0")
        or FindRootGroupByName(rootNode, "Patch 12.0.0")
    local g1205 = FindRootGroupByModuleKey(rootNode, "patch_12_0_5")
        or FindRootGroupByName(rootNode, "Patch 12.0.5")
    return g1200 ~= nil and g1205 ~= nil
end

local function CollectRegistryNodesFromGroup(group, intoMap)
    if not group or not group.children then return end
    for _, ch in ipairs(group.children) do
        if ch.type == "registryEntry" and ch.registryEntryId then
            intoMap[ch.registryEntryId] = ch
        end
    end
end

-- Merge legacy "Prey" + "Season 1 Weeklies" root groups into Patch 12.0.0 / 12.0.5.
local function MigrateMidnightPatchGroupsInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    if HasMidnightPatchModuleGroups(rootNode) then
        return
    end

    local map = {}
    CollectRegistryNodesFromGroup(FindRootGroupByName(rootNode, "Prey"), map)
    CollectRegistryNodesFromGroup(FindRootGroupByName(rootNode, "Season 1 Weeklies"), map)

    local kids = rootNode.children
    local insertIdx
    for i, ch in ipairs(kids or {}) do
        if ch and ch.type == "group" and (ch.name == "Prey" or ch.name == "Season 1 Weeklies") then
            insertIdx = insertIdx and math.min(insertIdx, i) or i
        end
    end

    for i = #kids, 1, -1 do
        local ch = kids[i]
        if ch and ch.type == "group" and (ch.name == "Prey" or ch.name == "Season 1 Weeklies") then
            table.remove(kids, i)
        end
    end
    if not insertIdx then
        insertIdx = #kids + 1
    end

    local g1200 = NewModuleGroupNode("Patch 12.0.0", "patch_12_0_0")
    for _, rid in ipairs(MIDNIGHT_PATCH_12_0_0_ORDER) do
        table.insert(g1200.children, map[rid] or TaskTracker.NewRegistryNode(rid))
    end

    local g1205 = NewModuleGroupNode("Patch 12.0.5", "patch_12_0_5")
    for _, rid in ipairs(MIDNIGHT_PATCH_12_0_5_ORDER) do
        table.insert(g1205.children, map[rid] or TaskTracker.NewRegistryNode(rid))
    end

    table.insert(kids, insertIdx, g1200)
    table.insert(kids, insertIdx + 1, g1205)
end

-- Append any new registry nodes for the Midnight patch groups (preserves user row order).
local function SyncMidnightPatchRegistryNodes(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    ConvertFarmRegistryNodesInTree(rootNode)
    local ids1200 = RegistryIdSet(MIDNIGHT_PATCH_12_0_0_ORDER)
    local ids1205 = RegistryIdSet(MIDNIGHT_PATCH_12_0_5_ORDER)
    local ids1210 = RegistryIdSet(MIDNIGHT_PATCH_12_1_0_ORDER)
    local g1200 = FindRootGroupByModuleKeyOrContent(rootNode, "patch_12_0_0", ids1200)
    local g1205 = FindRootGroupByModuleKeyOrContent(rootNode, "patch_12_0_5", ids1205)
    if g1200 then g1200.moduleGroupKey = "patch_12_0_0" end
    if g1205 then g1205.moduleGroupKey = "patch_12_0_5" end

    local g1210 = FindRootGroupByModuleKeyOrContent(rootNode, "patch_12_1_0", ids1210)
    if not g1210 then
        g1210 = NewModuleGroupNode("Patch 12.1.0", "patch_12_1_0")
        local kids = rootNode.children or {}
        local insertAt = #kids + 1
        for i, ch in ipairs(kids) do
            if ch and (ch.moduleGroupKey == "patch_12_0_5" or ch.moduleGroupKey == "patch_12_0_0") then
                insertAt = i
                break
            end
        end
        table.insert(kids, insertAt, g1210)
        rootNode.children = kids
    end
    g1210.moduleGroupKey = "patch_12_1_0"

    local function extractMatchingRegistryChildren(parent, idSet)
        local out = {}
        if not parent or type(parent.children) ~= "table" or not idSet then return out end
        for i = #parent.children, 1, -1 do
            local ch = parent.children[i]
            if ch and ch.type == "registryEntry" and ch.registryEntryId and idSet[ch.registryEntryId] then
                table.insert(out, 1, table.remove(parent.children, i))
            end
        end
        return out
    end

    local coiledSet = RegistryIdSet(MIDNIGHT_PATCH_12_1_0_COILED_ORDER)
    local vaultsSet = RegistryIdSet(MIDNIGHT_PATCH_12_1_0_VAULTS_ORDER)
    local coiledExtracted = extractMatchingRegistryChildren(g1210, coiledSet)
    local vaultsExtracted = extractMatchingRegistryChildren(g1210, vaultsSet)

    -- Pull every matching group out of the tree (handles duplicates from an earlier sync).
    local function gatherGroups(node, key, into)
        if not node or type(node.children) ~= "table" then return end
        for i = #node.children, 1, -1 do
            local ch = node.children[i]
            if type(ch) == "table" and ch.type == "group" then
                gatherGroups(ch, key, into)
                if ch.moduleGroupKey == key then
                    table.remove(node.children, i)
                    into[#into + 1] = ch
                end
            end
        end
    end

    local function mergeRegistryChildren(dest, src)
        if not src then return end
        dest.children = dest.children or {}
        local have = {}
        for _, ch in ipairs(dest.children) do
            if ch and ch.type == "registryEntry" and ch.registryEntryId then
                have[ch.registryEntryId] = true
            end
        end
        for _, ch in ipairs(src.children or {}) do
            if ch and ch.type == "registryEntry" and ch.registryEntryId and not have[ch.registryEntryId] then
                dest.children[#dest.children + 1] = ch
                have[ch.registryEntryId] = true
            end
        end
    end

    local function mergeCollectionChildren(dest, src)
        mergeRegistryChildren(dest, src)
        if not src then return end
        dest.children = dest.children or {}
        local haveTask, haveId = {}, {}
        for _, ch in ipairs(dest.children) do
            if ch then
                if ch.id then haveId[ch.id] = true end
                local eid = collectableTaskEntryId(ch)
                if eid then haveTask[eid] = true end
            end
        end
        for _, ch in ipairs(src.children or {}) do
            if ch and ch.type == "task" then
                local eid = collectableTaskEntryId(ch)
                if eid then
                    if not haveTask[eid] then
                        dest.children[#dest.children + 1] = ch
                        haveTask[eid] = true
                        if ch.id then haveId[ch.id] = true end
                    end
                elseif ch.id and not haveId[ch.id] then
                    dest.children[#dest.children + 1] = ch
                    haveId[ch.id] = true
                end
            end
        end
    end

    local function mergeExtractedRegistryNodes(dest, nodes)
        dest.children = dest.children or {}
        local have = {}
        for _, ch in ipairs(dest.children) do
            if ch and ch.type == "registryEntry" and ch.registryEntryId then
                have[ch.registryEntryId] = true
            end
        end
        for _, n in ipairs(nodes or {}) do
            if n and n.registryEntryId and not have[n.registryEntryId] then
                dest.children[#dest.children + 1] = n
                have[n.registryEntryId] = true
            end
        end
    end

    local coiledGroups, vaultsGroups = {}, {}
    -- Nested Vaults must be gathered before Coiled Isle is detached, or a new
    -- empty Vaults group is created and appended every sync.
    gatherGroups(rootNode, "patch_12_1_0_vaults", vaultsGroups)
    gatherGroups(rootNode, "patch_12_1_0_coiled_isle", coiledGroups)
    for i = 1, #coiledGroups do
        gatherGroups(coiledGroups[i], "patch_12_1_0_vaults", vaultsGroups)
    end

    local coiled = coiledGroups[1] or NewModuleGroupNode("The Coiled Isle", "patch_12_1_0_coiled_isle")
    coiled.moduleGroupKey = "patch_12_1_0_coiled_isle"
    coiled.name = "The Coiled Isle"
    for i = 2, #coiledGroups do
        mergeRegistryChildren(coiled, coiledGroups[i])
    end
    mergeExtractedRegistryNodes(coiled, coiledExtracted)
    AppendMissingRegistryIds(coiled, MIDNIGHT_PATCH_12_1_0_COILED_ORDER)

    local vaults = vaultsGroups[1] or NewModuleGroupNode("Vaults of Atal'Utek", "patch_12_1_0_vaults")
    vaults.moduleGroupKey = "patch_12_1_0_vaults"
    vaults.name = "Vaults of Atal'Utek"
    for i = 2, #vaultsGroups do
        mergeRegistryChildren(vaults, vaultsGroups[i])
    end
    mergeExtractedRegistryNodes(vaults, vaultsExtracted)
    AppendMissingRegistryIds(vaults, MIDNIGHT_PATCH_12_1_0_VAULTS_ORDER)

    local colls = {}
    gatherGroups(rootNode, "patch_12_1_0_collections", colls)
    local coll = colls[1] or NewModuleGroupNode("Collections", "patch_12_1_0_collections")
    coll.moduleGroupKey = "patch_12_1_0_collections"
    for i = 2, #colls do
        mergeRegistryChildren(coll, colls[i])
        for _, ch in ipairs(colls[i].children or {}) do
            if ch and ch.type == "group" then
                coll.children = coll.children or {}
                coll.children[#coll.children + 1] = ch
            end
        end
    end

    local cats = {
        { "Toys", "patch_12_1_0_collections_toys", MIDNIGHT_COLLECTIONS_TOYS_IDS },
        { "Mounts", "patch_12_1_0_collections_mounts", MIDNIGHT_COLLECTIONS_MOUNTS_IDS },
        { "Pets", "patch_12_1_0_collections_pets", MIDNIGHT_COLLECTIONS_PETS_IDS },
        { "Currency", "patch_12_1_0_collections_currency", MIDNIGHT_COLLECTIONS_CURRENCY_IDS },
        { "Reputations", "patch_12_1_0_collections_reputations", MIDNIGHT_COLLECTIONS_REPUTATIONS_IDS },
    }
    local catKeepers = {}
    for i = 1, #cats do
        local cat = cats[i]
        local found = {}
        gatherGroups(rootNode, cat[2], found)
        gatherGroups(coll, cat[2], found)
        local g = found[1] or NewModuleGroupNode(cat[1], cat[2])
        g.moduleGroupKey = cat[2]
        g.name = cat[1]
        g.children = g.children or {}
        for j = 2, #found do
            mergeCollectionChildren(g, found[j])
        end
        AppendMissingRegistryIds(g, cat[3])
        if cat[2] == "patch_12_1_0_collections_mounts" then
            for i = #(g.children or {}), 1, -1 do
                local ch = g.children[i]
                if ch and ch.type == "registryEntry" and isSeededCollectionRegistryId(ch.registryEntryId) then
                    table.remove(g.children, i)
                end
            end
            SeedMissingCollectionFarmTasks(g, MIDNIGHT_COLLECTIONS_MOUNT_FARMS)
            SeedMissingCollectionAchievementTasks(g, MIDNIGHT_COLLECTIONS_MOUNT_ACHIEVEMENTS)
            OrderCollectionSeededTasks(g, MIDNIGHT_COLLECTIONS_MOUNT_SEEDED_IDS)
        elseif cat[2] == "patch_12_1_0_collections_pets" then
            for i = #(g.children or {}), 1, -1 do
                local ch = g.children[i]
                if ch and ch.type == "registryEntry" and isSeededCollectionRegistryId(ch.registryEntryId) then
                    table.remove(g.children, i)
                end
            end
            SeedMissingCollectionFarmTasks(g, MIDNIGHT_COLLECTIONS_PET_FARMS)
            SeedMissingCollectionAchievementTasks(g, MIDNIGHT_COLLECTIONS_PET_ACHIEVEMENTS)
            SeedMissingCollectionSpecTasks(g, MIDNIGHT_COLLECTIONS_PET_KILLS, KILL_REGISTRY_TO_SPEC, "mob_kill", NewCollectionKillTaskNode)
            OrderCollectionSeededTasks(g, MIDNIGHT_COLLECTIONS_PET_SEEDED_IDS)
        elseif cat[2] == "patch_12_1_0_collections_currency" then
            for i = #(g.children or {}), 1, -1 do
                local ch = g.children[i]
                if ch and ch.type == "registryEntry" and isSeededCollectionRegistryId(ch.registryEntryId) then
                    table.remove(g.children, i)
                end
            end
            SeedMissingCollectionSpecTasks(g, MIDNIGHT_COLLECTIONS_CURRENCY_ITEMS, CURRENCY_REGISTRY_TO_SPEC, "item", NewCollectionCurrencyTaskNode)
            OrderCollectionSeededTasks(g, MIDNIGHT_COLLECTIONS_CURRENCY_SEEDED_IDS)
        elseif cat[2] == "patch_12_1_0_collections_toys" then
            for i = #(g.children or {}), 1, -1 do
                local ch = g.children[i]
                if ch and ch.type == "registryEntry" and isSeededCollectionRegistryId(ch.registryEntryId) then
                    table.remove(g.children, i)
                end
            end
            SeedMissingCollectionFarmTasks(g, MIDNIGHT_COLLECTIONS_TOY_FARMS)
            SeedMissingCollectionAchievementTasks(g, MIDNIGHT_COLLECTIONS_TOY_ACHIEVEMENTS)
            OrderCollectionSeededTasks(g, MIDNIGHT_COLLECTIONS_TOY_SEEDED_IDS)
        end
        catKeepers[i] = g
    end
    coll.children = catKeepers

    local coiledKids = {}
    for _, ch in ipairs(coiled.children or {}) do
        if ch and ch.moduleGroupKey ~= "patch_12_1_0_vaults" and ch ~= vaults then
            coiledKids[#coiledKids + 1] = ch
        end
    end
    coiledKids[#coiledKids + 1] = vaults
    coiled.children = coiledKids

    local leftovers = {}
    for _, ch in ipairs(g1210.children or {}) do
        if ch and ch ~= coiled and ch ~= vaults and ch ~= coll then
            leftovers[#leftovers + 1] = ch
        end
    end
    g1210.children = { coiled }
    for i = 1, #leftovers do
        g1210.children[#g1210.children + 1] = leftovers[i]
    end
    g1210.children[#g1210.children + 1] = coll

    if g1200 then
        AppendMissingRegistryIds(g1200, MIDNIGHT_PATCH_12_0_0_ORDER)
        local colls1200 = {}
        gatherGroups(rootNode, "patch_12_0_0_collections", colls1200)
        local coll1200 = colls1200[1] or NewModuleGroupNode("Collections", "patch_12_0_0_collections")
        coll1200.moduleGroupKey = "patch_12_0_0_collections"
        coll1200.name = "Collections"
        for i = 2, #colls1200 do
            mergeCollectionChildren(coll1200, colls1200[i])
            for _, ch in ipairs(colls1200[i].children or {}) do
                if ch and ch.type == "group" then
                    coll1200.children = coll1200.children or {}
                    coll1200.children[#coll1200.children + 1] = ch
                end
            end
        end
        local mountsFound = {}
        gatherGroups(rootNode, "patch_12_0_0_collections_mounts", mountsFound)
        gatherGroups(coll1200, "patch_12_0_0_collections_mounts", mountsFound)
        local mounts1200 = mountsFound[1] or NewModuleGroupNode("Mounts", "patch_12_0_0_collections_mounts")
        mounts1200.moduleGroupKey = "patch_12_0_0_collections_mounts"
        mounts1200.name = "Mounts"
        mounts1200.children = mounts1200.children or {}
        for j = 2, #mountsFound do
            mergeCollectionChildren(mounts1200, mountsFound[j])
        end
        for i = #(mounts1200.children or {}), 1, -1 do
            local ch = mounts1200.children[i]
            if ch and ch.type == "registryEntry" and isSeededCollectionRegistryId(ch.registryEntryId) then
                table.remove(mounts1200.children, i)
            end
        end
        SeedMissingCollectionFarmTasks(mounts1200, MIDNIGHT_1200_COLLECTIONS_MOUNT_FARMS)
        OrderCollectionSeededTasks(mounts1200, MIDNIGHT_1200_COLLECTIONS_MOUNT_SEEDED_IDS)
        AppendMissingRegistryIds(mounts1200, MIDNIGHT_1200_COLLECTIONS_MOUNT_OWNED_IDS)
        local petsFound = {}
        gatherGroups(rootNode, "patch_12_0_0_collections_pets", petsFound)
        gatherGroups(coll1200, "patch_12_0_0_collections_pets", petsFound)
        local pets1200 = petsFound[1] or NewModuleGroupNode("Pets", "patch_12_0_0_collections_pets")
        pets1200.moduleGroupKey = "patch_12_0_0_collections_pets"
        pets1200.name = "Pets"
        pets1200.children = pets1200.children or {}
        for j = 2, #petsFound do
            mergeCollectionChildren(pets1200, petsFound[j])
        end
        AppendMissingRegistryIds(pets1200, MIDNIGHT_1200_COLLECTIONS_PETS_IDS)
        local currencyFound = {}
        gatherGroups(rootNode, "patch_12_0_0_collections_currency", currencyFound)
        gatherGroups(coll1200, "patch_12_0_0_collections_currency", currencyFound)
        local currency1200 = currencyFound[1] or NewModuleGroupNode("Currency", "patch_12_0_0_collections_currency")
        currency1200.moduleGroupKey = "patch_12_0_0_collections_currency"
        currency1200.name = "Currency"
        currency1200.children = currency1200.children or {}
        for j = 2, #currencyFound do
            mergeCollectionChildren(currency1200, currencyFound[j])
        end
        for i = #(currency1200.children or {}), 1, -1 do
            local ch = currency1200.children[i]
            if ch and ch.type == "registryEntry" and isSeededCollectionRegistryId(ch.registryEntryId) then
                table.remove(currency1200.children, i)
            end
        end
        SeedMissingCollectionSpecTasks(currency1200, MIDNIGHT_1200_COLLECTIONS_CURRENCY_ITEMS, CURRENCY_REGISTRY_TO_SPEC, "item", NewCollectionCurrencyTaskNode)
        OrderCollectionSeededTasks(currency1200, MIDNIGHT_1200_COLLECTIONS_CURRENCY_SEEDED_IDS)
        coll1200.children = { mounts1200, pets1200, currency1200 }
        g1200.children = g1200.children or {}
        g1200.children[#g1200.children + 1] = coll1200
    end
    if g1205 then AppendMissingRegistryIds(g1205, MIDNIGHT_PATCH_12_0_5_ORDER) end

    local g1215 = FindRootGroupByModuleKey(rootNode, "patch_12_1_5")
    if not g1215 then
        g1215 = NewModuleGroupNode("Patch 12.1.5", "patch_12_1_5")
        local kids1215 = rootNode.children or {}
        local insertAt = #kids1215 + 1
        for i, ch in ipairs(kids1215) do
            if ch and (ch.moduleGroupKey == "patch_12_1_0"
                or ch.moduleGroupKey == "patch_12_0_5"
                or ch.moduleGroupKey == "patch_12_0_0") then
                insertAt = i
                break
            end
        end
        table.insert(kids1215, insertAt, g1215)
        rootNode.children = kids1215
    end
    g1215.moduleGroupKey = "patch_12_1_5"
    g1215.name = "Patch 12.1.5"
    local function ensure1215Child(parent, key, label)
        for _, ch in ipairs(parent.children or {}) do
            if ch and ch.type == "group" and ch.moduleGroupKey == key then
                ch.name = label
                return ch
            end
        end
        local n = NewModuleGroupNode(label, key)
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = n
        return n
    end
    local repWant = RegistryIdSet(MIDNIGHT_PATCH_12_1_5_REPUTATIONS_IDS)
    local function repNodeId(ch)
        if ch and ch.type == "registryEntry" then return ch.registryEntryId end
        if ch and ch.type == "task" then return ch.collectionFarmId end
    end
    local pulledReps = {}
    local function pullReps(node)
        if not node or type(node.children) ~= "table" then return end
        for i = #node.children, 1, -1 do
            local ch = node.children[i]
            if ch and ch.type == "group" then
                pullReps(ch)
            end
            local rid = repNodeId(ch)
            if rid and repWant[rid] then
                table.remove(node.children, i)
                pulledReps[#pulledReps + 1] = ch
            end
        end
    end
    pullReps(g1215)
    for i = #(g1215.children or {}), 1, -1 do
        local ch = g1215.children[i]
        if ch and ch.moduleGroupKey == "patch_12_1_5_labyrinth" and #(ch.children or {}) == 0 then
            table.remove(g1215.children, i)
        end
    end
    local aqir = ensure1215Child(g1215, "patch_12_1_5_aqir", "Aqir Invasions")
    AppendMissingRegistryIds(aqir, MIDNIGHT_PATCH_12_1_5_AQIR_ORDER)
    local coll1215 = ensure1215Child(g1215, "patch_12_1_5_collections", "Collections")
    local reps1215 = ensure1215Child(coll1215, "patch_12_1_5_collections_reputations", "Reputations")
    local haveRep = {}
    for _, n in ipairs(pulledReps) do
        local rid = repNodeId(n)
        if rid and not haveRep[rid] then
            reps1215.children[#reps1215.children + 1] = n
            haveRep[rid] = true
        elseif rid and n.type == "task" and haveRep[rid] then
            for i, existing in ipairs(reps1215.children) do
                if repNodeId(existing) == rid and existing.type ~= "task" then
                    reps1215.children[i] = n
                    break
                end
            end
        end
    end
    AppendMissingRegistryIds(reps1215, MIDNIGHT_PATCH_12_1_5_REPUTATIONS_IDS)
    for i = #(g1215.children or {}), 1, -1 do
        if g1215.children[i] == coll1215 then
            table.remove(g1215.children, i)
        end
    end
    g1215.children[#g1215.children + 1] = coll1215

    local PATCH_NEWEST_FIRST = { "patch_12_1_5", "patch_12_1_0", "patch_12_0_5", "patch_12_0_0" }
    local kids = rootNode.children or {}
    local byKey, minI = {}, nil
    for i, ch in ipairs(kids) do
        local k = ch and ch.moduleGroupKey
        if k == "patch_12_1_5" or k == "patch_12_1_0" or k == "patch_12_0_5" or k == "patch_12_0_0" then
            byKey[k] = ch
            if not minI or i < minI then minI = i end
        end
    end
    if minI then
        for i = #kids, 1, -1 do
            local ch = kids[i]
            if ch and byKey[ch.moduleGroupKey] == ch then
                table.remove(kids, i)
            end
        end
        for i = #PATCH_NEWEST_FIRST, 1, -1 do
            local g = byKey[PATCH_NEWEST_FIRST[i]]
            if g then
                table.insert(kids, minI, g)
            end
        end
    end
    ConvertOwnedAndReputationNodesInTree(rootNode)
end

-- Patrolling the Temple, Relentless Strikes, and Decisive Incursions are one rotating daily.
local HAWKEYE_SOHO_ID = "s1_hawkeye_soho"
local HAWKEYE_SOHO_OLD_IDS = {
    s1_patrolling_the_temple = true,
    s1_relentless_strikes = true,
    s1_decisive_incursions = true,
}
local HAWKEYE_SOHO_OLD_NOTES = {
    ["Daily in the Vaults of Atal'Utek: complete Temple Patrols. Same pickup as the other vault dailies (Warleader Abdumati). Way pins the Eastern Fang entrance (not Abdumati)."] = true,
    ["Daily in the Vaults of Atal'Utek: complete Temple Strikes. Pick up from Warleader Abdumati. Way pins the Eastern Fang entrance (not Abdumati)."] = true,
    ["Daily in the Vaults of Atal'Utek: complete Temple Incursions. Pick up from Warleader Abdumati. Way pins the Eastern Fang entrance (not Abdumati)."] = true,
}

local function collectHawkeyeSohoNodes(node, found)
    local kids = node and node.children
    if type(kids) ~= "table" then return end
    for i = 1, #kids do
        local ch = kids[i]
        if type(ch) == "table" then
            if ch.type == "registryEntry" and ch.registryEntryId == HAWKEYE_SOHO_ID then
                found.have = true
            elseif ch.type == "registryEntry" and HAWKEYE_SOHO_OLD_IDS[ch.registryEntryId] then
                found.olds[#found.olds + 1] = ch
            else
                collectHawkeyeSohoNodes(ch, found)
            end
        end
    end
end

local function removeHawkeyeSohoOldNodes(node)
    local kids = node and node.children
    if type(kids) ~= "table" then return end
    for i = #kids, 1, -1 do
        local ch = kids[i]
        if type(ch) == "table" then
            if ch.type == "registryEntry" and HAWKEYE_SOHO_OLD_IDS[ch.registryEntryId] then
                table.remove(kids, i)
            else
                removeHawkeyeSohoOldNodes(ch)
            end
        end
    end
end

local function MigrateHawkeyeSohoInTree(rootNode)
    if not rootNode or type(rootNode) ~= "table" then return end
    local found = { have = false, olds = {} }
    collectHawkeyeSohoNodes(rootNode, found)
    if not found.have and #found.olds > 0 then
        local keep = found.olds[1]
        for i = 1, #found.olds do
            if found.olds[i].registryEntryId == "s1_patrolling_the_temple" then
                keep = found.olds[i]
                break
            end
        end
        keep.registryEntryId = HAWKEYE_SOHO_ID
        if type(keep.note) == "string" and HAWKEYE_SOHO_OLD_NOTES[keep.note] then
            keep.note = ""
        end
    end
    removeHawkeyeSohoOldNodes(rootNode)
end

local function MigrateHawkeyeSohoState(state)
    if type(state) ~= "table" then return end
    local oldIds = { "s1_patrolling_the_temple", "s1_relentless_strikes", "s1_decisive_incursions" }
    local any, enabled, powerOn, done = false, false, false, false
    local sawOff, sawPowerOff = false, false
    for i = 1, #oldIds do
        local st = state[oldIds[i]]
        if type(st) == "table" then
            any = true
            if st.enabled == false then
                sawOff = true
            else
                enabled = true
            end
            if st.powerListEnabled == false then
                sawPowerOff = true
            else
                powerOn = true
            end
            if (tonumber(st.value) or 0) >= 1 then
                done = true
            end
        end
    end
    if not any or state[HAWKEYE_SOHO_ID] then return end
    local neu = {
        enabled = enabled or not sawOff,
        powerListEnabled = powerOn or not sawPowerOff,
        value = done and 1 or 0,
        override = nil,
        userValue = nil,
    }
    state[HAWKEYE_SOHO_ID] = neu
end

-- Migration: old Power-only M+ registry ids → Seasonal Mythic+; drop removed pack row.
local function MigrateMPlusRegistryNodesInTree(rootNode)
    if not rootNode or type(rootNode) ~= "table" then return end
    local kids = rootNode.children
    if type(kids) == "table" then
        for i = #kids, 1, -1 do
            local ch = kids[i]
            if type(ch) == "table" and ch.type == "registryEntry" and ch.registryEntryId then
                local rid = ch.registryEntryId
                if rid == "seasonal_mplus_dungeon_guides" then
                    table.remove(kids, i)
                elseif rid == "power_mplus_line_end" then
                    ch.registryEntryId = "seasonal_mplus_hint_end"
                elseif rid == "power_mplus_line_vault" then
                    ch.registryEntryId = "seasonal_mplus_hint_vault"
                end
            end
        end
        for _, ch in ipairs(kids) do
            MigrateMPlusRegistryNodesInTree(ch)
        end
    end
end

local function MigrateMPlusRegistryState(state)
    if type(state) ~= "table" then return end
    local pack = state["seasonal_mplus_dungeon_guides"]
    local endOld = state["power_mplus_line_end"]
    local vaultOld = state["power_mplus_line_vault"]

    local function mergeInto(newId, oldTbl)
        if type(oldTbl) ~= "table" then return end
        local n = state[newId]
        if type(n) ~= "table" then
            state[newId] = {}
            n = state[newId]
        end
        for k, v in pairs(oldTbl) do
            if n[k] == nil then
                n[k] = v
            end
        end
    end

    mergeInto("seasonal_mplus_hint_end", endOld)
    mergeInto("seasonal_mplus_hint_vault", vaultOld)

    if type(pack) == "table" then
        local packOn = pack.enabled ~= false and pack.powerListEnabled ~= false
        if packOn then
            for _, nid in ipairs(SEASONAL_MPLUS_IDS) do
                if type(state[nid]) ~= "table" then
                    state[nid] = {}
                end
                state[nid].enabled = true
                state[nid].powerListEnabled = true
            end
        end
    end

    state["seasonal_mplus_dungeon_guides"] = nil
    state["power_mplus_line_end"] = nil
    state["power_mplus_line_vault"] = nil
end

-- Move Spark Quest (s1_ritual_sites) from legacy Patch 12.0.5 / elsewhere into Seasonal Activities → General.
local function MigrateSparkQuestRegistryToSeasonalGeneral(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    local SPARK_ID = "s1_ritual_sites"
    local sparkNode
    local function stripSpark(parent)
        if not parent or type(parent.children) ~= "table" then return end
        for i = #parent.children, 1, -1 do
            local ch = parent.children[i]
            if ch.type == "registryEntry" and ch.registryEntryId == SPARK_ID then
                if sparkNode then
                    table.remove(parent.children, i)
                else
                    sparkNode = table.remove(parent.children, i)
                end
            elseif ch.type == "group" then
                stripSpark(ch)
            end
        end
    end
    stripSpark(rootNode)

    local seasonal = FindRootGroupByName(rootNode, "Seasonal Activities")
    if not seasonal then return end
    seasonal.children = seasonal.children or {}
    local generalGroup
    for _, ch in ipairs(seasonal.children) do
        if ch.type == "group" and ch.name == "General" then
            generalGroup = ch
            break
        end
    end
    if not generalGroup then
        generalGroup = NewModuleGroupNode("General", "seasonal_general")
        table.insert(seasonal.children, 1, generalGroup)
    end
    generalGroup.moduleGroupKey = "seasonal_general"
    generalGroup.children = generalGroup.children or {}
    local haveSpark = false
    for _, ch in ipairs(generalGroup.children) do
        if ch.type == "registryEntry" and ch.registryEntryId == SPARK_ID then
            haveSpark = true
            break
        end
    end
    if not haveSpark then
        table.insert(generalGroup.children, sparkNode or TaskTracker.NewRegistryNode(SPARK_ID))
    end
end

local function findChildGroupByKeyOrName(parent, key, name)
    local byName
    for _, ch in ipairs(parent.children or {}) do
        if ch and ch.type == "group" then
            if ch.moduleGroupKey == key then return ch end
            if name and ch.name == name and not byName then byName = ch end
        end
    end
    return byName
end

local function childIndexByKey(parent, key, name)
    local nameIndex
    for i, ch in ipairs(parent.children or {}) do
        if ch and ch.type == "group" then
            if ch.moduleGroupKey == key then return i end
            if name and ch.name == name and not nameIndex then nameIndex = i end
        end
    end
    return nameIndex
end

--- Insert a missing id beside the neighbors in orderedIds. Existing rows stay put.
local function placeMissingRegistryIds(group, orderedIds)
    group.children = group.children or {}
    local function indexOfId(rid)
        for i, ch in ipairs(group.children) do
            if ch and ch.type == "registryEntry" and ch.registryEntryId == rid then
                return i
            end
        end
    end
    for n, rid in ipairs(orderedIds or {}) do
        if not indexOfId(rid) then
            local insertAt
            for prev = n - 1, 1, -1 do
                local pi = indexOfId(orderedIds[prev])
                if pi then
                    insertAt = pi + 1
                    break
                end
            end
            if not insertAt then
                for nxt = n + 1, #orderedIds do
                    local ni = indexOfId(orderedIds[nxt])
                    if ni then
                        insertAt = ni
                        break
                    end
                end
            end
            table.insert(group.children, insertAt or (#group.children + 1), TaskTracker.NewRegistryNode(rid))
        end
    end
end

--- Insert any missing registry rows at the front, in order. Existing rows stay where the player left them.
local function prependMissingRegistryIds(group, orderedIds)
    local have = {}
    for _, ch in ipairs(group.children or {}) do
        if ch and ch.type == "registryEntry" and ch.registryEntryId then
            have[ch.registryEntryId] = true
        end
    end
    group.children = group.children or {}
    local insertAt = 1
    for _, rid in ipairs(orderedIds or {}) do
        if not have[rid] then
            table.insert(group.children, insertAt, TaskTracker.NewRegistryNode(rid))
            have[rid] = true
            insertAt = insertAt + 1
        end
    end
end

-- New Power rows are appended. Pull each raid vault up under its difficulty.
local RAID_DIFFICULTY_PAIRS = {
    { "seasonal_raid_normal", "seasonal_raid_vault_normal" },
    { "seasonal_raid_heroic", "seasonal_raid_vault_heroic" },
    { "seasonal_raid_mythic", "seasonal_raid_vault_mythic" },
}

local function indexOfRegistryChild(children, rid)
    for i, ch in ipairs(children or {}) do
        if ch and ch.type == "registryEntry" and ch.registryEntryId == rid then
            return i
        end
    end
end

local function keepRaidDifficultyPairsTogether(children)
    if not children then return end
    for _, pair in ipairs(RAID_DIFFICULTY_PAIRS) do
        local dropI = indexOfRegistryChild(children, pair[1])
        local vaultI = indexOfRegistryChild(children, pair[2])
        if dropI and vaultI and vaultI ~= dropI + 1 then
            local vault = table.remove(children, vaultI)
            dropI = indexOfRegistryChild(children, pair[1])
            table.insert(children, dropI + 1, vault)
        end
    end
end

-- Dungeons (was Mythic+), Raids, and Vault Status above Delves.
local function EnsureSeasonalMplusGroupInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    local seasonalGroup = findChildGroupByKeyOrName(rootNode, "seasonal_activities", "Seasonal Activities")
    if not seasonalGroup then return end
    if GroupHasSeasonalModuleRegistry(seasonalGroup) then
        seasonalGroup.moduleGroupKey = "seasonal_activities"
    end
    seasonalGroup.children = seasonalGroup.children or {}

    local gname = TaskTracker.MPLUS_SEASONAL_GROUP_NAME or "Dungeons"
    local mplusGroup = findChildGroupByKeyOrName(seasonalGroup, "seasonal_mplus", "Mythic+")
        or findChildGroupByKeyOrName(seasonalGroup, "seasonal_mplus", gname)
    if not mplusGroup then
        mplusGroup = NewModuleGroupNode(gname, "seasonal_mplus")
        table.insert(seasonalGroup.children, mplusGroup)
    end
    mplusGroup.name = gname
    mplusGroup.moduleGroupKey = "seasonal_mplus"
    prependMissingRegistryIds(mplusGroup, SEASONAL_MPLUS_IDS)

    local raidGroup = findChildGroupByKeyOrName(seasonalGroup, "seasonal_raid", "Raids")
    if not raidGroup then
        raidGroup = NewModuleGroupNode("Raids", "seasonal_raid")
        local after = childIndexByKey(seasonalGroup, "seasonal_mplus")
        table.insert(seasonalGroup.children, (after or #seasonalGroup.children) + 1, raidGroup)
    end
    raidGroup.name = "Raids"
    raidGroup.moduleGroupKey = "seasonal_raid"
    placeMissingRegistryIds(raidGroup, SEASONAL_RAID_IDS)
    keepRaidDifficultyPairsTogether(raidGroup.children)

    local vaultI = childIndexByKey(seasonalGroup, "seasonal_vault", "Vault Status")
    local delvesI = childIndexByKey(seasonalGroup, "seasonal_delves", "Delves")
    if vaultI and delvesI and vaultI > delvesI then
        local vault = table.remove(seasonalGroup.children, vaultI)
        table.insert(seasonalGroup.children, delvesI, vault)
    end
end

local function subtreeHasTaskOrRegistryNode(node)
    if not node then return false end
    if node.type == "task" or node.type == "registryEntry" then return true end
    local kids = node.children
    if type(kids) ~= "table" then return false end
    for i = 1, #kids do
        if subtreeHasTaskOrRegistryNode(kids[i]) then return true end
    end
    return false
end

--- Empty extra Seasonal Activities roots are protected, so they cannot be deleted.
--- Keep the one that has rows. Drop the shells.
local function PruneEmptyDuplicateSeasonalRoots(rootNode)
    if not rootNode or rootNode.type ~= "root" or type(rootNode.children) ~= "table" then return end
    local keep
    for _, ch in ipairs(rootNode.children) do
        if ch and ch.type == "group" and ch.moduleGroupKey == "seasonal_activities"
            and subtreeHasTaskOrRegistryNode(ch) then
            keep = ch
            break
        end
    end
    if not keep then return end
    for i = #rootNode.children, 1, -1 do
        local ch = rootNode.children[i]
        if ch and ch ~= keep and ch.type == "group" and ch.moduleGroupKey == "seasonal_activities"
            and not subtreeHasTaskOrRegistryNode(ch) then
            table.remove(rootNode.children, i)
        end
    end
end

-- One-time migration: Seasonal Activities at top of tree (with Delves / Vault Status)
local function EnsureSeasonalActivitiesInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    if TreeHasRegistryEntry(rootNode, "seasonal_delves_gilded") then return end

    local seasonalGroup = NewModuleGroupNode("Seasonal Activities", "seasonal_activities")
    local generalGroup = NewModuleGroupNode("General", "seasonal_general")
    for _, regId in ipairs(SEASONAL_GENERAL_IDS) do
        table.insert(generalGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local delvesGroup = NewModuleGroupNode("Delves", "seasonal_delves")
    for _, regId in ipairs(SEASONAL_DELVES_IDS) do
        table.insert(delvesGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local vaultGroup = NewModuleGroupNode("Vault Status", "seasonal_vault")
    for _, regId in ipairs(SEASONAL_VAULT_IDS) do
        table.insert(vaultGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local mplusGroup = NewModuleGroupNode(
        TaskTracker.MPLUS_SEASONAL_GROUP_NAME or "Mythic+",
        "seasonal_mplus"
    )
    for _, regId in ipairs(SEASONAL_MPLUS_IDS) do
        table.insert(mplusGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    local raidGroup = NewModuleGroupNode("Raids", "seasonal_raid")
    for _, regId in ipairs(SEASONAL_RAID_IDS) do
        table.insert(raidGroup.children, TaskTracker.NewRegistryNode(regId))
    end
    table.insert(seasonalGroup.children, generalGroup)
    table.insert(seasonalGroup.children, vaultGroup)
    table.insert(seasonalGroup.children, delvesGroup)
    table.insert(seasonalGroup.children, mplusGroup)
    table.insert(seasonalGroup.children, raidGroup)
    seasonalGroup.moduleGroupKey = "seasonal_activities"
    table.insert(rootNode.children, 1, seasonalGroup)
end

-- One-time migration: add Prey: Nightmarish row if missing
local function EnsurePreyNightmarishInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    if TreeHasRegistryEntry(rootNode, "prey_nightmarish") then return end
    local patchGroup = FindRootGroupByModuleKey(rootNode, "patch_12_0_0")
        or FindRootGroupByName(rootNode, "Patch 12.0.0")
    if not patchGroup then return end
    local insertAt = #patchGroup.children + 1
    for i, ch in ipairs(patchGroup.children or {}) do
        if ch and ch.type == "registryEntry" and ch.registryEntryId == "prey_nightmare" then
            insertAt = i + 1
            break
        end
    end
    table.insert(patchGroup.children, insertAt, TaskTracker.NewRegistryNode("prey_nightmarish"))
end

local function childrenLayoutChanged(before, after)
    if before == after then return false end
    if not before or not after then return true end
    if #before ~= #after then return true end
    for i = 1, #before do
        if before[i] ~= after[i] then return true end
    end
    return false
end

--- Keep user rows (tasks, groups, etc.) in place; dedupe module registry leaves; append missing ids.
local function SyncOrderedRegistryChildrenPreservingLayout(children, orderedRegIds)
    children = children or {}
    local idSet = {}
    for _, id in ipairs(orderedRegIds or {}) do
        idSet[id] = true
    end

    local pool = {}
    for _, ch in ipairs(children) do
        if ch and ch.type == "registryEntry" and ch.registryEntryId and idSet[ch.registryEntryId] then
            if not pool[ch.registryEntryId] then
                pool[ch.registryEntryId] = ch
            end
        end
    end

    local seenReg = {}
    local out = {}
    for _, ch in ipairs(children) do
        if ch and ch.type == "registryEntry" and ch.registryEntryId and idSet[ch.registryEntryId] then
            local rid = ch.registryEntryId
            if not seenReg[rid] then
                seenReg[rid] = true
                out[#out + 1] = pool[rid] or ch
            end
        elseif ch then
            out[#out + 1] = ch
        end
    end

    for _, rid in ipairs(orderedRegIds or {}) do
        if not seenReg[rid] then
            seenReg[rid] = true
            out[#out + 1] = pool[rid] or TaskTracker.NewRegistryNode(rid)
        end
    end

    return out
end

-- Power group: mirrors registry rows with reward hints; kept in sync with GetEntriesForPowerModule().
local function EnsurePowerGroupInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    if not TaskTracker.GetEntriesForPowerModule then return end

    local powerIds = BuildPowerRegistryIdSet()
    local powerGroup = FindRootGroupByModuleKeyOrContent(rootNode, "power", powerIds)
    if not powerGroup then
        powerGroup = NewModuleGroupNode("Power", "power")
        table.insert(rootNode.children, 1, powerGroup)
    end
    powerGroup.moduleGroupKey = "power"

    local powerOrder = {}
    for _, e in ipairs(TaskTracker.GetEntriesForPowerModule()) do
        powerOrder[#powerOrder + 1] = e.id
    end
    local synced = SyncOrderedRegistryChildrenPreservingLayout(powerGroup.children, powerOrder)
    keepRaidDifficultyPairsTogether(synced)
    if childrenLayoutChanged(powerGroup.children, synced) then
        powerGroup.children = synced
    end

    for i = #rootNode.children, 1, -1 do
        if rootNode.children[i] == powerGroup and i ~= 1 then
            table.remove(rootNode.children, i)
            table.insert(rootNode.children, 1, powerGroup)
            break
        end
    end
end

local function ProfessionRegistryIdsForKey(key)
    local ids = {
        "prof_" .. key .. "_weekly",
    }
    local def = TaskTracker.ProfessionCatalog and TaskTracker.ProfessionCatalog[key]
    if def and def.weeklyDisenchantRows then
        for i in ipairs(def.weeklyDisenchantRows) do
            ids[#ids + 1] = "prof_" .. key .. "_disenchant_" .. i
        end
    end
    ids[#ids + 1] = "prof_" .. key .. "_drops"
    ids[#ids + 1] = "prof_" .. key .. "_treatise"
    ids[#ids + 1] = "prof_" .. key .. "_catchup"
    return ids
end

local function IsProfessionCatalogSubgroup(node)
    if not node or node.type ~= "group" or not node.name or not TaskTracker.ProfessionCatalog then
        return false
    end
    for _, def in pairs(TaskTracker.ProfessionCatalog) do
        if def.label == node.name then
            return true
        end
    end
    return false
end

local professionTaskIdsPresent

local function professionTaskIsShared(node)
    if not node then return false end
    if node.liveShareRole == "owner" then return true end
    if type(node.liveShareByChar) == "table" and next(node.liveShareByChar) then return true end
    if type(node.liveShareId) == "string" and node.liveShareId ~= ""
        and type(node.liveShareTo) == "string" and node.liveShareTo ~= "" then
        return true
    end
    return false
end

local function professionTaskScore(node)
    local score = 0
    if professionTaskIsShared(node) then score = score + 4 end
    if node.professionProgressSeeded then score = score + 1 end
    if node.type == "task" then score = score + 1 end
    return score
end

local function professionShareIdentity(node)
    if type(node.liveShareId) == "string" and node.liveShareId ~= "" then
        return node.liveShareId
    end
    return nil
end

--- Relog used to add a second copy of a shared profession quest. Drop the extra.
local function DedupeDuplicateProfessionTasks(root)
    if not root then return false end
    local groups = {}
    local function visit(node)
        if node.type == "task" and node.liveShareRole ~= "receiver" then
            local rid = node.collectionFarmId
            if type(rid) == "string" and rid ~= "" then
                local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[rid]
                if entry and entry.expansion == "professions" then
                    local list = groups[rid]
                    if not list then
                        list = {}
                        groups[rid] = list
                    end
                    list[#list + 1] = node
                end
            end
        end
        local kids = node.children
        if type(kids) == "table" then
            for i = 1, #kids do
                local ch = kids[i]
                if type(ch) == "table" then visit(ch) end
            end
        end
    end
    visit(root)
    local drop = {}
    local any = false
    for _, list in pairs(groups) do
        if #list > 1 then
            local keep = list[1]
            local anyShare = false
            for i = 1, #list do
                if professionTaskIsShared(list[i]) then anyShare = true end
                if professionTaskScore(list[i]) > professionTaskScore(keep) then
                    keep = list[i]
                end
            end
            local keepId = professionShareIdentity(keep)
            for i = 1, #list do
                local node = list[i]
                if node ~= keep then
                    local nodeId = professionShareIdentity(node)
                    local secondShare = anyShare and professionTaskIsShared(node) and nodeId and nodeId ~= keepId
                    if not secondShare then
                        drop[node] = true
                        any = true
                    end
                end
            end
        end
    end
    if not any then return false end
    local function prune(node)
        local kids = node.children
        if type(kids) ~= "table" then return end
        for i = #kids, 1, -1 do
            local ch = kids[i]
            if ch and drop[ch] then
                table.remove(kids, i)
            elseif type(ch) == "table" then
                prune(ch)
            end
        end
    end
    prune(root)
    return true
end

local function collectProfessionTaskIds(root)
    local have = {}
    local function visit(node)
        if node.type == "task" and node.liveShareRole ~= "receiver" then
            local rid = node.collectionFarmId
            if type(rid) == "string" and rid ~= "" then
                have[rid] = true
            end
        end
        local kids = node.children
        if type(kids) == "table" then
            for i = 1, #kids do
                local ch = kids[i]
                if type(ch) == "table" then visit(ch) end
            end
        end
    end
    if root then visit(root) end
    return have
end

--- The sender's row is still the module row. Only a received copy is someone else's task.
local function professionLeafRegistryId(node)
    if not node then return nil end
    if node.liveShareRole == "receiver" then return nil end
    if node.type == "task" and type(node.collectionFarmId) == "string" and node.collectionFarmId ~= "" then
        return node.collectionFarmId
    end
    if node.type == "registryEntry" and type(node.registryEntryId) == "string" and node.registryEntryId ~= "" then
        return node.registryEntryId
    end
end

--- Keep user order. Turn a profession registry row into an editable task, and add any that are missing.
local function SyncProfessionLeavesPreservingLayout(children, orderedIds)
    children = children or {}
    local idSet = {}
    for _, id in ipairs(orderedIds or {}) do
        idSet[id] = true
    end

    local pool = {}
    for _, ch in ipairs(children) do
        local rid = professionLeafRegistryId(ch)
        if rid and idSet[rid] then
            local prev = pool[rid]
            if not prev or professionTaskScore(ch) > professionTaskScore(prev) then
                pool[rid] = ch
            end
        end
    end

    local function adoptProfessionTask(task, rid)
        if not task or task.type ~= "task" or task.professionProgressSeeded then return end
        local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[rid]
        if entry and TaskTracker.SeedProfessionTaskFromRegistry then
            TaskTracker.SeedProfessionTaskFromRegistry(task, entry)
        else
            task.professionProgressSeeded = true
        end
    end

    for rid, ch in pairs(pool) do
        if ch.type == "registryEntry" then
            local task = TaskTracker.BuildBuiltinTaskSeed(rid)
            if task then
                copyUserNoteIfCustom(ch, task)
                if type(ch.commandButtons) == "table" and #ch.commandButtons > 0 then
                    task.commandButtons = ch.commandButtons
                end
                adoptProfessionTask(task, rid)
                pool[rid] = task
            end
        elseif ch.type == "task" then
            adoptProfessionTask(ch, rid)
        end
    end

    local seen = {}
    local out = {}
    for _, ch in ipairs(children) do
        local rid = professionLeafRegistryId(ch)
        if rid and idSet[rid] then
            if not seen[rid] then
                seen[rid] = true
                out[#out + 1] = pool[rid] or ch
            end
        elseif ch then
            out[#out + 1] = ch
        end
    end

    for _, rid in ipairs(orderedIds or {}) do
        if not seen[rid] then
            local task = pool[rid]
            if not task and professionTaskIdsPresent and professionTaskIdsPresent[rid] then
                -- This quest already exists somewhere else in the list. Do not add a second copy.
            elseif not task and TaskTracker.RegistryByID and TaskTracker.RegistryByID[rid] then
                task = TaskTracker.BuildBuiltinTaskSeed(rid)
                if task then
                    adoptProfessionTask(task, rid)
                end
            end
            if task then
                seen[rid] = true
                out[#out + 1] = task
            end
        end
    end
    return out
end

local function SyncProfessionsRootChildrenPreservingLayout(profRoot, sharedOrderedIds, sharedSet, moduleGroupsByKey, learnedSet)
    local seenShared = {}
    local seenModule = {}
    local out = {}
    local sharedLeaves = SyncProfessionLeavesPreservingLayout(profRoot.children, sharedOrderedIds)

    for _, ch in ipairs(sharedLeaves) do
        local rid = professionLeafRegistryId(ch)
        if rid and sharedSet[rid] then
            if not seenShared[rid] then
                seenShared[rid] = true
                out[#out + 1] = ch
            end
        elseif ch.type == "group" then
            local pkey = (ch.moduleGroupKey and ch.moduleGroupKey:match("^profession_(.+)$"))
                or ProfessionCatalogKeyForGroupName(ch.name)
            if pkey then
                -- Keep a profession the player already has, even on an alt who has not learned it.
                -- The list hides that group. Dropping it would throw away edits.
                if moduleGroupsByKey[pkey] then
                    local mk = "profession_" .. pkey
                    if not seenModule[mk] then
                        seenModule[mk] = true
                        out[#out + 1] = moduleGroupsByKey[pkey]
                    end
                end
            else
                -- Custom groups under Professions (not catalog subsections).
                out[#out + 1] = ch
            end
        else
            out[#out + 1] = ch
        end
    end

    for _, key in ipairs(TaskTracker.ProfessionCatalogOrder or {}) do
        if learnedSet[key] then
            local mk = "profession_" .. key
            if not seenModule[mk] and moduleGroupsByKey[key] then
                seenModule[mk] = true
                out[#out + 1] = moduleGroupsByKey[key]
            end
        end
    end

    return out
end

local function ProfessionsRootHasModuleRegistry(node)
    if not node or node.type ~= "group" then return false end
    for _, ch in ipairs(node.children or {}) do
        if ch.type == "registryEntry" and ch.registryEntryId and ch.registryEntryId:match("^prof_") then
            return true
        end
        if ch.type == "group" and IsProfessionCatalogSubgroup(ch) then
            return true
        end
    end
    return false
end

--- Tag built-in module groups by registry content (not display name) so custom same-name groups stay deletable.
local function MigrateModuleGroupKeysInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end

    local powerIds = BuildPowerRegistryIdSet()
    local patch1200Ids = RegistryIdSet(MIDNIGHT_PATCH_12_0_0_ORDER)
    local patch1205Ids = RegistryIdSet(MIDNIGHT_PATCH_12_0_5_ORDER)
    local patch1210Ids = RegistryIdSet(MIDNIGHT_PATCH_12_1_0_ORDER)
    local seasonalGeneralIds = RegistryIdSet(SEASONAL_GENERAL_IDS)
    local seasonalDelvesIds = RegistryIdSet(SEASONAL_DELVES_IDS)
    local seasonalVaultIds = RegistryIdSet(SEASONAL_VAULT_IDS)
    local seasonalMplusIds = RegistryIdSet(SEASONAL_MPLUS_IDS)

    for _, ch in ipairs(rootNode.children or {}) do
        if ch.type ~= "group" or ch.moduleGroupKey then
            -- skip
        elseif GroupHasAnyRegistryId(ch, powerIds) then
            ch.moduleGroupKey = "power"
        elseif GroupHasAnyRegistryId(ch, patch1200Ids) then
            ch.moduleGroupKey = "patch_12_0_0"
        elseif GroupHasAnyRegistryId(ch, patch1205Ids) then
            ch.moduleGroupKey = "patch_12_0_5"
        elseif GroupHasAnyRegistryId(ch, patch1210Ids) then
            ch.moduleGroupKey = "patch_12_1_0"
        elseif GroupHasSeasonalModuleRegistry(ch) then
            ch.moduleGroupKey = "seasonal_activities"
        elseif ch.name == "Professions" and ProfessionsRootHasModuleRegistry(ch) then
            ch.moduleGroupKey = "professions"
        end
    end

    local seasonalGroup = FindRootGroupByModuleKey(rootNode, "seasonal_activities")
    if seasonalGroup then
        for _, sub in ipairs(seasonalGroup.children or {}) do
            if sub.type == "group" and not sub.moduleGroupKey then
                if GroupHasAnyRegistryId(sub, seasonalGeneralIds) then
                    sub.moduleGroupKey = "seasonal_general"
                elseif GroupHasAnyRegistryId(sub, seasonalDelvesIds) then
                    sub.moduleGroupKey = "seasonal_delves"
                elseif GroupHasAnyRegistryId(sub, seasonalVaultIds) then
                    sub.moduleGroupKey = "seasonal_vault"
                elseif GroupHasAnyRegistryId(sub, seasonalMplusIds) then
                    sub.moduleGroupKey = "seasonal_mplus"
                end
            end
        end
    end

    local profRoot = FindRootGroupByModuleKey(rootNode, "professions")
    if profRoot then
        for _, sub in ipairs(profRoot.children or {}) do
            if sub.type == "group" and not sub.moduleGroupKey then
                local profKey = ProfessionCatalogKeyForGroupName(sub.name)
                if profKey and GroupHasRegistryIdPrefix(sub, "prof_") then
                    sub.moduleGroupKey = "profession_" .. profKey
                end
            end
        end
    end

    TaskTracker.WalkTree(function(node)
        if node.type == "group" and not node.moduleGroupKey
            and node.name == TaskTracker.MPLUS_GUIDE_GROUP_NAME
            and #(node.children or {}) == 0 then
            node.moduleGroupKey = "mplus_hints"
        end
    end, rootNode)
end

--- User-created "Professions" groups share the module name; keep one module root and allow deleting extras.
local function MigrateDuplicateProfessionsRootGroups(rootNode)
    if not rootNode or rootNode.type ~= "root" or type(rootNode.children) ~= "table" then return false end
    local hits = {}
    for i, ch in ipairs(rootNode.children) do
        if ch and ch.type == "group" and ch.name == "Professions" then
            hits[#hits + 1] = { index = i, node = ch }
        end
    end
    if #hits == 0 then return false end

    local layoutChanged = false
    local canonical = nil
    for _, h in ipairs(hits) do
        if h.node.moduleGroupKey == "professions" then
            canonical = h.node
            break
        end
    end
    if not canonical then
        for _, h in ipairs(hits) do
            if ProfessionsRootHasModuleRegistry(h.node) then
                canonical = h.node
                break
            end
        end
    end
    canonical = canonical or hits[1].node
    canonical.moduleGroupKey = "professions"

    local function appendUniqueChild(into, ch)
        if not ch or not ch.id then return end
        for _, existing in ipairs(into.children or {}) do
            if existing.id == ch.id then return end
        end
        into.children = into.children or {}
        table.insert(into.children, ch)
        layoutChanged = true
    end

    if #hits > 1 then
        canonical.children = canonical.children or {}
        for _, h in ipairs(hits) do
            if h.node ~= canonical then
                for _, ch in ipairs(h.node.children or {}) do
                    if ch.type == "task" or (ch.type == "group" and not IsProfessionCatalogSubgroup(ch)) then
                        appendUniqueChild(canonical, ch)
                    end
                end
            end
        end
        for i = #rootNode.children, 1, -1 do
            local ch = rootNode.children[i]
            if ch and ch.type == "group" and ch.name == "Professions" and ch ~= canonical then
                table.remove(rootNode.children, i)
                layoutChanged = true
            end
        end
    end

    return layoutChanged
end

--- Move Abundance (and other shared profession registry rows) out of Patch 12.0.0 into Professions.
local function MigrateSharedProfessionsRegistryInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    local sharedSet = ProfessionsSharedRegistrySet()
    local extracted = {}
    local function stripShared(parent)
        if not parent or type(parent.children) ~= "table" then return end
        for i = #parent.children, 1, -1 do
            local ch = parent.children[i]
            if ch.type == "registryEntry" and ch.registryEntryId and sharedSet[ch.registryEntryId] then
                if not extracted[ch.registryEntryId] then
                    extracted[ch.registryEntryId] = table.remove(parent.children, i)
                else
                    table.remove(parent.children, i)
                end
            elseif ch.type == "group" then
                stripShared(ch)
            end
        end
    end
    stripShared(rootNode)

    local profRoot = FindRootGroupByModuleKey(rootNode, "professions")
        or FindRootGroupByName(rootNode, "Professions")
    if not profRoot then return end

    profRoot.children = profRoot.children or {}
    local have = {}
    for _, ch in ipairs(profRoot.children) do
        if ch.type == "registryEntry" and ch.registryEntryId and sharedSet[ch.registryEntryId] then
            have[ch.registryEntryId] = ch
        end
    end
    for _, rid in ipairs(PROFESSIONS_SHARED_REGISTRY_IDS) do
        if not have[rid] then
            local node = extracted[rid] or TaskTracker.NewRegistryNode(rid)
            table.insert(profRoot.children, 1, node)
        end
    end
end

--- New Professions roots sit after Midnight. An existing root is left where the player put it.
local function insertIndexAfterMidnight(kids)
    local lastMidnight
    for i, ch in ipairs(kids) do
        local key = ch and ch.moduleGroupKey
        if ch and ch.type == "group" and type(key) == "string" and key:match("^patch_12_") then
            lastMidnight = i
        end
    end
    if lastMidnight then return lastMidnight + 1 end
    for i, ch in ipairs(kids) do
        if ch and ch.type == "group" and (ch.moduleGroupKey == "seasonal_activities" or ch.name == "Seasonal Activities") then
            return i + 1
        end
    end
    return #kids + 1
end

local function EnsureProfessionsGroupInTree(rootNode)
    if not rootNode or rootNode.type ~= "root" then return end
    if not TaskTracker.ProfessionCatalogOrder or not TaskTracker.ProfessionCatalog then return end

    local layoutChanged = MigrateDuplicateProfessionsRootGroups(rootNode)
    if DedupeDuplicateProfessionTasks(rootNode) then
        layoutChanged = true
    end
    professionTaskIdsPresent = collectProfessionTaskIds(rootNode)

    local profRoot = FindRootGroupByModuleKey(rootNode, "professions")
        or FindRootGroupByName(rootNode, "Professions")
    if profRoot and ProfessionsRootHasModuleRegistry(profRoot) then
        profRoot.moduleGroupKey = "professions"
    end

    if not profRoot then
        profRoot = NewModuleGroupNode("Professions", "professions")
        local kids = rootNode.children or {}
        rootNode.children = kids
        table.insert(kids, insertIndexAfterMidnight(kids), profRoot)
        profRoot.professionsStartCollapsed = true
        layoutChanged = true
    end

    MigrateSharedProfessionsRegistryInTree(rootNode)

    local sharedSet = ProfessionsSharedRegistrySet()
    local learned = (TaskTracker.GetLearnedProfessionKeys and TaskTracker.GetLearnedProfessionKeys()) or {}
    local existingByName = {}
    for _, ch in ipairs(profRoot.children or {}) do
        if ch and ch.type == "group" and ch.name then
            existingByName[ch.name] = ch
        end
    end

    local function syncProfessionCatalogGroup(grp, key)
        if not grp or not key then return end
        grp.moduleGroupKey = "profession_" .. key
        local leafOrder = ProfessionRegistryIdsForKey(key)
        local syncedLeaves = SyncProfessionLeavesPreservingLayout(grp.children, leafOrder)
        if childrenLayoutChanged(grp.children, syncedLeaves) then
            grp.children = syncedLeaves
            layoutChanged = true
        end
    end

    local moduleGroupsByKey = {}
    -- Sync every existing profession subgroup first (preserves user tasks even before learned list loads).
    for _, ch in ipairs(profRoot.children or {}) do
        if ch and ch.type == "group" then
            local pkey = (ch.moduleGroupKey and ch.moduleGroupKey:match("^profession_(.+)$"))
                or ProfessionCatalogKeyForGroupName(ch.name)
            if pkey and not moduleGroupsByKey[pkey] then
                syncProfessionCatalogGroup(ch, pkey)
                moduleGroupsByKey[pkey] = ch
            end
        end
    end

    -- Add subgroups for newly learned professions that are not in the tree yet.
    for _, key in ipairs(TaskTracker.ProfessionCatalogOrder) do
        if learned[key] and not moduleGroupsByKey[key] then
            local def = TaskTracker.ProfessionCatalog[key]
            local gname = (def and def.label) or key
            local grp = existingByName[gname] or NewModuleGroupNode(gname, "profession_" .. key)
            if not existingByName[gname] then
                if profRoot.professionsStartCollapsed then
                    grp.expanded = false
                end
                layoutChanged = true
            end
            syncProfessionCatalogGroup(grp, key)
            moduleGroupsByKey[key] = grp
        end
    end

    local syncedRoot = SyncProfessionsRootChildrenPreservingLayout(
        profRoot,
        PROFESSIONS_SHARED_REGISTRY_IDS,
        sharedSet,
        moduleGroupsByKey,
        learned
    )
    if childrenLayoutChanged(profRoot.children, syncedRoot) then
        profRoot.children = syncedRoot
        layoutChanged = true
    end
    profRoot.moduleGroupKey = "professions"

    if layoutChanged and TaskTracker.MarkListLayoutDirty then
        TaskTracker.MarkListLayoutDirty()
    end
    professionTaskIdsPresent = nil
end
TaskTracker.EnsureProfessionsGroupInTree = EnsureProfessionsGroupInTree

-- ─────────────────────────────────────
-- Build default registry state
-- ─────────────────────────────────────
local function BuildDefaultRegistryState(useStarter)
    local state = {}
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then
        return state
    end
    for _, entry in ipairs(TaskTracker.Registry) do
        local enabled, powerOn = true, true
        if useStarter and TaskTracker.IsStarterRegistryEntry then
            enabled = TaskTracker.IsStarterRegistryEntry(entry) and true or false
            powerOn = false
        end
        state[entry.id] = {
            enabled   = enabled,
            powerListEnabled = powerOn,
            value     = 0,
            override  = nil,
            userValue = nil,
        }
    end
    return state
end

-- ─────────────────────────────────────
-- Patch registry state
-- Ensures new registry entries get state
-- ─────────────────────────────────────
local function PatchRegistryState(state)
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then
        return
    end
    for _, entry in ipairs(TaskTracker.Registry) do
        if not state[entry.id] then
            state[entry.id] = {
                enabled   = true,
                powerListEnabled = true,
                value     = 0,
                override  = nil,
                userValue = nil,
            }
        end
        if state[entry.id].powerListEnabled == nil then state[entry.id].powerListEnabled = true end
        if state[entry.id].enabled  == nil then state[entry.id].enabled  = true end
        if state[entry.id].value    == nil then state[entry.id].value    = 0 end
        if state[entry.id].override == nil then state[entry.id].override = nil end
        if state[entry.id].userValue == nil then state[entry.id].userValue = nil end
    end
end

-- ─────────────────────────────────────
-- SavedVariables cleanup helpers
-- When registry entries are removed from Data\Registry.lua, old tree nodes can remain.
-- This prunes those stale nodes so users don't see "Unknown" rows.
-- ─────────────────────────────────────
local function PruneMissingRegistryEntriesInTree(node)
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then
        return
    end
    if not node or type(node) ~= "table" then return end
    local kids = node.children
    if type(kids) ~= "table" then return end

    for i = #kids, 1, -1 do
        local ch = kids[i]
        if type(ch) == "table" then
            if ch.type == "registryEntry" then
                local rid = ch.registryEntryId
                if not rid or not (TaskTracker.RegistryByID and TaskTracker.RegistryByID[rid]) then
                    table.remove(kids, i)
                end
            else
                PruneMissingRegistryEntriesInTree(ch)
            end
        end
    end
end

local function PruneMissingRegistryState(state)
    if type(state) ~= "table" then return end
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then
        return
    end
    for rid in pairs(state) do
        if not TaskTracker.RegistryByID[rid] then
            state[rid] = nil
        end
    end
end

local function PatchCommandButton(btn)
    if type(btn) ~= "table" then return end
    if btn.label == nil then btn.label = "" end
    if btn.command == nil then btn.command = "" end
    local ic = btn.icon
    if TaskTracker.NormalizeCommandIcon then
        btn.icon = TaskTracker.NormalizeCommandIcon(ic, btn.command)
    elseif ic == nil then
        btn.icon = 134400
    else
        btn.icon = tonumber(ic) or 134400
    end
    -- SavedVariables may use 1 or "true" instead of boolean; normalize so list pins still match.
    local p = btn.pinned
    btn.pinned = (p == true) or (p == 1) or (type(p) == "string" and p:lower() == "true")
    if btn.runMode ~= "line" then btn.runMode = nil end
end

local function PatchTaskNodes(node, catalogReady)
    node = node or TaskTrackerDB.tree
    if not node then return end
    if catalogReady == nil then
        catalogReady = TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()
    end
    -- Runtime leaf/holdout cache used to be stamped onto SavedVariables nodes.
    node._ttLeafGen = nil
    node._ttLeafDone = nil
    node._ttLeafTotal = nil
    node._ttHideHoldout = nil
    node._ttHideHoldoutGen = nil
    local kids = node.children
    if type(kids) == "table" and catalogReady then
        for i = #kids, 1, -1 do
            local ch = kids[i]
            if type(ch) == "table" and ch.type == "registryEntry" then
                local rid = ch.registryEntryId
                if not rid or not TaskTracker.RegistryByID[rid] then
                    table.remove(kids, i)
                end
            end
        end
    end
    if node.type == "task" then
        if node.taskMax == nil then node.taskMax = 1 end
        if node.taskCount == nil then node.taskCount = node.done and 1 or 0 end
        if node.accountWide ~= true then
            node.accountWide = nil
        else
            node.ownerCharKey = nil
            node.showOnOtherCharacters = nil
        end
        if node.accountWide ~= true and type(node.ownerCharKey) ~= "string" then
            node.ownerCharKey = nil
        end
        if node.accountWide ~= true and node.showOnOtherCharacters ~= true then
            node.showOnOtherCharacters = nil
        end
        node.suspended = nil -- removed feature; strip legacy SavedVariables
        if node.note == nil then node.note = "" end
        if type(node.commandButtons) ~= "table" then node.commandButtons = {} end
        if node.collectionFarmId then
            local farmEntry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[node.collectionFarmId]
            if farmEntry then
                TaskTracker.AppendMissingCommandButtons(node, farmEntry.defaultCommandButtons)
            end
            local spec = ACH_REGISTRY_TO_SPEC[node.collectionFarmId]
            if spec and spec.name and (node.name == "Wild-Caught Pets" or node.name == nil or node.name == "") then
                node.name = spec.name
            end
        end
        if type(node.advanced) ~= "table" or not node.advanced.type then
            node.advanced = nil
        end
        if type(node.taskUserValue) == "number" and not node.advanced then
            node.taskUserValue = nil
        end
        if node.advanced then
            if node.advanced.type == "gold" then
                if not node.advanced.goldMode then node.advanced.goldMode = "net" end
                if node.advanced.goldAutoCopper ~= nil then
                    node.advanced.goldAutoCopper = math.max(0, math.floor(tonumber(node.advanced.goldAutoCopper) or 0))
                end
                if not node.advanced.goldResetSource then node.advanced.goldResetSource = "inherit" end
                if node.advanced.goldResetSource == "override" and not node.advanced.resetOverride then
                    node.advanced.resetOverride = "none"
                end
            elseif node.advanced.type == "achievement" then
                node.advanced.achievementId = tonumber(node.advanced.achievementId) or 0
                if node.advanced.achievementCriteriaIndex == nil then
                    node.advanced.achievementCriteriaIndex = 0
                end
                if (tonumber(node.advanced.achievementCriteriaIndex) or 0) == 0 then
                    node.advanced.achievementMirrorGameTotals = nil
                elseif node.advanced.achievementMirrorGameTotals == nil then
                    node.advanced.achievementMirrorGameTotals = false
                end
                -- Emerald Skyfang used to mirror the 250 in-game bar. Weekly goal 10, second line keeps the total.
                -- One shot, and only when the row still has those defaults, so an edited goal stays.
                if node.collectionFarmId == "col_mount_emerald_skyfang" and node.emeraldSkyfangWeeklyMigrated ~= true then
                    local stillDefault = (tonumber(node.taskMax) or 0) == 250
                        and (node.reset == nil or node.reset == "none")
                        and node.advanced.achievementMirrorGameTotals == true
                    if stillDefault then
                        node.taskMax = 10
                        node.reset = "weekly"
                        node.advanced.achievementMirrorGameTotals = false
                        node.advanced.weekStartAchTotal = nil
                        if node.taskUserValue == nil then
                            node.taskCount = 0
                            node.done = false
                        end
                    end
                    node.emeraldSkyfangWeeklyMigrated = true
                end
                if node.collectionFarmId == "col_mount_emerald_skyfang" and node.subtextBuiltinStamp ~= "user" then
                    local sub = node.subtext
                    local empty = type(sub) ~= "table" or sub.type == nil or sub.type == "" or sub.type == "none"
                    if empty then
                        node.subtext = { type = "achievement", useTask = true, achievementTrackMode = "game" }
                        node.subtextBuiltinStamp = "builtin"
                    end
                end
                -- Ki'clak used to mirror the 5 in-game snacks. Weekly goal 2, second line keeps the total.
                -- One shot, and only when the row still has those defaults, so an edited goal stays.
                if node.collectionFarmId == "col_pet_kiclak" and node.kiclakWeeklyMigrated ~= true then
                    local stillDefault = (tonumber(node.taskMax) or 0) == 5
                        and (node.reset == nil or node.reset == "none")
                        and node.advanced.achievementMirrorGameTotals == true
                    if stillDefault then
                        node.taskMax = 2
                        node.reset = "weekly"
                        node.advanced.achievementMirrorGameTotals = false
                        node.advanced.weekStartAchTotal = nil
                        if node.taskUserValue == nil then
                            node.taskCount = 0
                            node.done = false
                        end
                    end
                    node.kiclakWeeklyMigrated = true
                end
                if node.collectionFarmId == "col_pet_kiclak" and node.subtextBuiltinStamp ~= "user" then
                    local sub = node.subtext
                    local empty = type(sub) ~= "table" or sub.type == nil or sub.type == "" or sub.type == "none"
                    if empty then
                        node.subtext = { type = "achievement", useTask = true, achievementTrackMode = "game" }
                        node.subtextBuiltinStamp = "builtin"
                    end
                end
            elseif node.advanced.type == "item" then
                if type(node.advanced.itemIds) ~= "table" then node.advanced.itemIds = {} end
                if not node.advanced.itemTrackMode then node.advanced.itemTrackMode = "earned" end
                -- Corrosive Coins used to track the wallet total at 10000. Match Voidlight: weekly earned, goal 20000.
                -- One shot, and only when the row still has those defaults, so an edited goal stays.
                if node.collectionFarmId == "col_currency_corrosive_coins" and node.corrosiveEarnedMigrated ~= true then
                    local stillDefault = (tonumber(node.taskMax) or 0) == 10000
                        and (node.reset == nil or node.reset == "none")
                        and (node.advanced.itemTrackMode or "total") == "total"
                    if stillDefault then
                        node.taskMax = 20000
                        node.reset = "weekly"
                        node.advanced.itemTrackMode = "earned"
                        node.advanced.itemAutoCount = 0
                        node.accountWide = true
                        if node.taskUserValue == nil then
                            node.taskCount = 0
                            node.done = false
                        end
                    end
                    node.corrosiveEarnedMigrated = true
                end
                -- The one-shot above skips a row whose goal or reset was already edited, and still
                -- marks it done. Those rows stayed on Current total, so a currency gain copied the
                -- wallet into the weekly count (the same number as the holdings second line).
                if node.collectionFarmId == "col_currency_corrosive_coins" and node.corrosiveEarnedModeRepaired ~= true then
                    if node.advanced.itemTrackMode == "total" then
                        node.advanced.itemTrackMode = "earned"
                        if node.taskUserValue == nil then
                            node.advanced.itemAutoCount = 0
                            node.taskCount = 0
                            node.done = false
                        end
                    end
                    node.corrosiveEarnedModeRepaired = true
                end
                -- Unreleased seed used 5000. Only rewrite a row that still has that goal.
                if node.collectionFarmId == "col_currency_remnant_of_anguish" and node.anguishGoalMigrated ~= true then
                    if (tonumber(node.taskMax) or 0) == 5000 then
                        node.taskMax = 1000
                        if node.taskUserValue == nil then
                            node.done = (tonumber(node.taskCount) or 0) >= 1000
                        end
                    end
                    local oldNote = "Prey currency from hunts. Spend it at Construct V'anore in Astalor's Sanctum. Weekly account-wide earned target (default 5000)."
                    if node.note == oldNote then
                        node.note = "Prey currency from hunts. Spend it at Construct V'anore in Astalor's Sanctum. Weekly account-wide earned target (default 1000)."
                    end
                    node.anguishGoalMigrated = true
                end
                if (node.collectionFarmId == "col_currency_corrosive_coins"
                    or node.collectionFarmId == "col_currency_voidlight_marl"
                    or node.collectionFarmId == "col_currency_remnant_of_anguish")
                    and node.subtextBuiltinStamp ~= "user" then
                    local sub = node.subtext
                    local empty = type(sub) ~= "table" or sub.type == nil or sub.type == "" or sub.type == "none"
                    if empty or sub.itemAttTotal == true then
                        node.subtext = { type = "item", useTask = true, itemAttTotal = true }
                        node.subtextBuiltinStamp = "builtin"
                    end
                end
                if node.advanced.itemAutoCount ~= nil then
                    node.advanced.itemAutoCount = math.max(0, math.floor(tonumber(node.advanced.itemAutoCount) or 0))
                end
            elseif node.advanced.type == "quest" then
                if type(node.advanced.questIds) ~= "table" then node.advanced.questIds = {} end
                if type(node.advanced.questNames) ~= "table" then node.advanced.questNames = {} end
            elseif node.advanced.type == "mob_kill" then
                -- Lil' Mon was a weekly kill of 5. Big Mon is once a day, so the row is 0/1.
                -- Also catches the unreleased daily goal of 5. An edited goal or reset stays.
                if node.collectionFarmId == "col_pet_lil_mon" and node.lilMonGoalOneMigrated ~= true then
                    local maxN = tonumber(node.taskMax) or 0
                    local oldWeekly = maxN == 5 and (node.reset == nil or node.reset == "weekly")
                    local oldDailyFive = maxN == 5 and node.reset == "daily"
                    if oldWeekly or oldDailyFive then
                        node.reset = "daily"
                        node.taskMax = 1
                        if node.taskUserValue == nil then
                            node.advanced.mobAutoCount = 0
                            node.taskCount = 0
                            node.done = false
                        end
                    end
                    node.lilMonGoalOneMigrated = true
                end
                if node.collectionFarmId == "col_pet_lil_mon" and node.subtextBuiltinStamp ~= "user" then
                    local sub = node.subtext
                    local empty = type(sub) ~= "table" or sub.type == nil or sub.type == "" or sub.type == "none"
                    if empty then
                        node.subtext = {
                            type = "mob_kill",
                            useTask = true,
                            showLifetime = true,
                            showDrop = true,
                            dropItemId = 280540,
                        }
                        node.subtextBuiltinStamp = "builtin"
                    end
                end
            elseif node.advanced.type == "kill" then
                -- Kill-based advanced tasks were removed; convert to a normal manual task.
                node.advanced = nil
                node.taskUserValue = nil
                node.doneOverride = nil
            elseif node.advanced.type == "reputation" then
                if not node.advanced.repGoalType then node.advanced.repGoalType = "weekly_gain" end
                node.advanced.repFactionId = tonumber(node.advanced.repFactionId) or 0
                if node.advanced.repFactionName == nil then node.advanced.repFactionName = "" end
                -- Zul'jarra's Forces used to be Renown 20. Weekly gain 2000.
                -- One shot, and only when the row still has those defaults, so an edited goal stays.
                if node.collectionFarmId == "col_rep_zuljarras_forces" and node.zuljarraWeeklyMigrated ~= true then
                    local stillDefault = node.advanced.repGoalType == "standing"
                        and (tonumber(node.taskMax) or 0) == 20
                        and (node.reset == nil or node.reset == "none")
                    if stillDefault then
                        node.advanced.repGoalType = "weekly_gain"
                        node.advanced.repStandingTarget = nil
                        node.taskMax = 2000
                        node.reset = "weekly"
                        node.advanced.weekStartRepValue = nil
                        if node.taskUserValue == nil then
                            node.taskCount = 0
                            node.done = false
                        end
                    end
                    node.zuljarraWeeklyMigrated = true
                end
                -- Aqir Research Enclave is a classic Neutral–Exalted bar (faction 2838), not a Renown.
                if node.collectionFarmId == "p1215_aqir_enclave" and node.aqirEnclaveClassicMigrated ~= true then
                    node.advanced.repClassic = true
                    node.advanced.repGoalType = "weekly_gain"
                    node.advanced.repStandingTarget = nil
                    if (tonumber(node.advanced.weekStartRepValue) or 0) >= 1000000 then
                        node.advanced.weekStartRepValue = nil
                    end
                    if (tonumber(node.taskMax) or 0) == 5 then
                        node.taskMax = 500
                        node.reset = "weekly"
                    end
                    if node.subtextBuiltinStamp ~= "user" then
                        local sub = node.subtext
                        local replace = type(sub) ~= "table" or sub.repDisplay == "renown"
                            or sub.type == nil or sub.type == "" or sub.type == "none"
                        if replace then
                            node.subtext = {
                                type = "reputation",
                                useTask = true,
                                repDisplay = "standing",
                                repFactionId = tonumber(node.advanced.repFactionId) or 2838,
                                repFactionName = node.advanced.repFactionName or "Aqir Research Enclave",
                            }
                            node.subtextBuiltinStamp = "builtin"
                        end
                    end
                    local oldNote = "Weekly reputation with the Aqir Research Enclave. The goal starts at 500. The second line shows your Renown."
                    if node.note == nil or node.note == "" or node.note == oldNote then
                        node.note = "Weekly reputation with the Aqir Research Enclave. Neutral through Exalted, 5000 total. The goal starts at 500. The second line shows your standing."
                    end
                    node.aqirEnclaveClassicMigrated = true
                end
                -- Friendship points are the bar (Neutral 0, Friendly 500, Honored 1500, Revered 3000, Exalted 5000).
                -- The old baseline was faction standing, which does not move. Start from 0 once so the row shows that total.
                if node.collectionFarmId == "p1215_aqir_enclave" and node.aqirEnclaveFriendshipMigrated ~= true then
                    node.advanced.repClassic = true
                    node.advanced.repGoalType = "weekly_gain"
                    node.advanced.weekStartRepValue = 0
                    node.aqirEnclaveFriendshipMigrated = true
                end
                -- Raising the weekly goal after the row finished left taskUserValue
                -- on the old count. The list shows that number and ignores new rep.
                -- Clear it once. Do not touch weekStartRepValue.
                if node.collectionFarmId == "p1215_aqir_enclave" and node.aqirEnclaveGoalUnlock ~= true then
                    node.advanced.repClassic = true
                    node.advanced.repGoalType = "weekly_gain"
                    if type(node.taskUserValue) == "number" then
                        node.taskUserValue = nil
                        node.doneOverride = nil
                    end
                    node.aqirEnclaveGoalUnlock = true
                end
                -- The full bar (standing / 42000) is not this friendship. Rank 5 finishes at 5000.
                -- Do not write weekStartRepValue.
                if node.collectionFarmId == "p1215_aqir_enclave" and node.aqirEnclaveFriendshipBar ~= true then
                    node.advanced.repClassic = nil
                    node.advanced.repGoalType = "friendship"
                    node.advanced.repStandingTarget = 5000
                    node.taskMax = 5000
                    node.reset = "none"
                    node.taskUserValue = nil
                    node.doneOverride = nil
                    if node.subtextBuiltinStamp ~= "user" then
                        local sub = node.subtext
                        if type(sub) ~= "table" or sub.repDisplay ~= "standing" or sub.type ~= "reputation" then
                            node.subtext = {
                                type = "reputation",
                                useTask = true,
                                repDisplay = "standing",
                                repFactionId = tonumber(node.advanced.repFactionId) or 2838,
                                repFactionName = node.advanced.repFactionName or "Aqir Research Enclave",
                            }
                            node.subtextBuiltinStamp = "builtin"
                        end
                    end
                    local note = node.note
                    local oldWeekly = "Weekly reputation with the Aqir Research Enclave. The goal starts at 500. The second line shows your Renown."
                    local oldStanding = "Weekly reputation with the Aqir Research Enclave. Neutral through Exalted, 5000 total. The goal starts at 500. The second line shows your standing."
                    if note == nil or note == "" or note == oldWeekly or note == oldStanding then
                        node.note = "Friendship with the Aqir Research Enclave. Neutral through Exalted. The row finishes at 5000. The second line shows your rank."
                    end
                    node.aqirEnclaveFriendshipBar = true
                end
            elseif node.advanced.type == "collectable" then
                if type(node.advanced.collectableQuestIds) ~= "table" then node.advanced.collectableQuestIds = {} end
                if node.advanced.collectableExpansion == nil then node.advanced.collectableExpansion = "midnight" end
                if node.advanced.collectableCategory == nil then node.advanced.collectableCategory = "mount" end
                if node.advanced.collectableEntryId == nil then node.advanced.collectableEntryId = "" end
                if type(node.advanced.collectableCredited) ~= "table" then node.advanced.collectableCredited = {} end
                if not node.advanced.collectableFarmItemId and TaskTracker.GetCollectableEntry
                    and TaskTracker.CollectableEntryFarmItemId then
                    local ent = TaskTracker.GetCollectableEntry(
                        node.advanced.collectableExpansion,
                        node.advanced.collectableCategory,
                        node.advanced.collectableEntryId)
                    local farmItemId = TaskTracker.CollectableEntryFarmItemId(ent)
                    if farmItemId then
                        node.advanced.collectableFarmItemId = farmItemId
                    end
                end
                if node.collectionFarmId == nil then
                    local eid = tostring(node.advanced.collectableEntryId or ""):lower()
                    local rid = CATALOG_TO_FARM_REGISTRY[eid]
                    if rid then
                        node.collectionFarmId = rid
                    end
                end
                -- One-shot: seeded farms used reset "none" before weekly was the default. Leave daily alone.
                -- After this stamp, player-chosen "none" is kept. Catalog defaultReset "none" (lifetime farms) is not coerced.
                if node.collectionFarmId and node.collectionFarmResetMigrated ~= true then
                    local keepNone = false
                    if TaskTracker.GetCollectableEntry then
                        local ent = TaskTracker.GetCollectableEntry(
                            node.advanced.collectableExpansion,
                            node.advanced.collectableCategory,
                            node.advanced.collectableEntryId)
                        keepNone = ent and ent.defaultReset == "none"
                    end
                    if not keepNone and (node.reset == nil or node.reset == "none") then
                        node.reset = "weekly"
                    end
                    node.collectionFarmResetMigrated = true
                end
                if node.subtextBuiltinStamp ~= "user" and node.subtextBuiltinStamp ~= "builtin" then
                    local def = DefaultCollectableSubtext(node.advanced.collectableEntryId)
                    if def then
                        node.subtext = def
                        node.subtextBuiltinStamp = "builtin"
                    end
                end
                if node.advanced.collectableAutoCount ~= nil then
                    node.advanced.collectableAutoCount = math.max(0, math.floor(tonumber(node.advanced.collectableAutoCount) or 0))
                end
                if node.advanced.collectableFishAttempts ~= nil then
                    node.advanced.collectableFishAttempts = math.max(0, math.floor(tonumber(node.advanced.collectableFishAttempts) or 0))
                end
                -- One-version sanitizer: unused ritual-kill stub → quest auto count, then drop the field.
                if TaskTracker.SanitizeCollectableRitualKills then
                    TaskTracker.SanitizeCollectableRitualKills(node.advanced)
                elseif node.advanced.collectableRitualKills ~= nil then
                    node.advanced.collectableRitualKills = nil
                end
            end
        end
        local pinCount = 0
        local cap = TaskTracker.MAX_PINNED_COMMANDS or 3
        for _, btn in ipairs(node.commandButtons) do
            PatchCommandButton(btn)
            if btn.pinned then
                pinCount = pinCount + 1
                if pinCount > cap then btn.pinned = false end
            end
        end
    elseif node.type == "registryEntry" then
        if node.note == nil then node.note = "" end
        if type(node.commandButtons) ~= "table" then node.commandButtons = {} end
        local entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[node.registryEntryId]
        if entry then
            TaskTracker.AppendMissingCommandButtons(node, entry.defaultCommandButtons)
        end
        local pinCountR = 0
        local capR = TaskTracker.MAX_PINNED_COMMANDS or 3
        for _, btn in ipairs(node.commandButtons) do
            PatchCommandButton(btn)
            if btn.pinned then
                pinCountR = pinCountR + 1
                if pinCountR > capR then btn.pinned = false end
            end
        end
    end
    if node.children then
        for _, ch in ipairs(node.children) do
            PatchTaskNodes(ch, catalogReady)
        end
    end
end

-- ─────────────────────────────────────
-- DB initialization
-- Safe to call on every load
-- ─────────────────────────────────────
function TaskTracker.InitDB()
    if not TaskTrackerDB then TaskTrackerDB = {} end
    local db = TaskTrackerDB
    -- Both missing means a first install. An existing save that has a tree keeps today's defaults.
    local freshInstall = db.tree == nil and db.registryState == nil
    db._dbg62be4f = nil
    db._ttAgentLog = nil
    db._ttDbg84 = nil
    db._ttDbg6b17b9 = nil
    db._ttDbg6898e9 = nil

    -- Apply theme first so UI helpers work during init
    if type(db.customThemes) ~= "table" then db.customThemes = {} end
    if type(db.customThemeSeq) ~= "number" then db.customThemeSeq = 0 end
    if TaskTracker.MigrateColorThemeKeys then
        TaskTracker.MigrateColorThemeKeys()
    end
    if TaskTracker.LoadCustomThemes then
        TaskTracker.LoadCustomThemes()
    end
    if db.theme == nil then db.theme = "gilded" end
    if not TaskTracker.Themes[db.theme] then db.theme = "dark" end
    TaskTracker.ApplyTheme()

    -- Global settings
    if db.hideCompleted  == nil then db.hideCompleted  = false end
    if db.showEmptyGroups ~= "off" and db.showEmptyGroups ~= "completed" and db.showEmptyGroups ~= "always" then
        db.showEmptyGroups = "off"
    end
    if db.showRowTooltips == nil then db.showRowTooltips = true end
    if db.showHelpTooltips == nil then db.showHelpTooltips = true end
    if db.showShortcutHints == nil then db.showShortcutHints = true end
    if db.patchListGroupMode == nil then db.patchListGroupMode = "patch" end
    if db.patchListGroupMode ~= "patch" and db.patchListGroupMode ~= "patch_zone"
        and db.patchListGroupMode ~= "zone" then
        db.patchListGroupMode = "patch"
    end
    if type(db.patchListViewExpanded) ~= "table" then db.patchListViewExpanded = {} end
    if db.zoneListFilter ~= "focus" and db.zoneListFilter ~= "zone" and db.zoneListFilter ~= "zone_plus" then
        db.zoneListFilter = "focus"
    end
    if db.zoneListFilterOn == nil then db.zoneListFilterOn = false end
    if db.zoneFilterIncludeParent == nil then db.zoneFilterIncludeParent = false end
    if db.zoneFilterIncludeChild == nil then db.zoneFilterIncludeChild = false end
    if db.listHideCollections == nil then db.listHideCollections = false end
    if db.listHideCustom == nil then db.listHideCustom = false end
    if db.listHideModules == nil then db.listHideModules = false end
    if db.enableNewModules == nil then db.enableNewModules = false end
    if db.zoneHereColor == nil then db.zoneHereColor = true end
    if db.zoneHereUnderline == nil then db.zoneHereUnderline = false end
    if db.attDataEnabled == nil then db.attDataEnabled = true end
    if type(db.readyToBuyExpansions) ~= "table" then
        db.readyToBuyExpansions = {}
        local cur = db.readyToBuyExpansion
        if type(cur) ~= "string" or cur == "" then cur = "midnight" end
        db.readyToBuyExpansions[cur] = true
    end
    if type(db.readyToBuyPicks) ~= "table" then db.readyToBuyPicks = {} end
    if type(db.readyToBuyCount) ~= "number" then db.readyToBuyCount = 5 end
    if db.readyToBuyCount < 1 then db.readyToBuyCount = 1 end
    if db.readyToBuyCount > 20 then db.readyToBuyCount = 20 end
    if type(db.readyToBuyIgnoredCurrencies) ~= "table" then db.readyToBuyIgnoredCurrencies = {} end
    if db.readyToBuyEnabled == nil then db.readyToBuyEnabled = not freshInstall end
    if db.readyToBuyZoneOnly == nil then db.readyToBuyZoneOnly = false end
    if db.readyToBuySpendOrder ~= "high" and db.readyToBuySpendOrder ~= "low" then
        db.readyToBuySpendOrder = "high"
    end
    if type(db.readyToBuyKinds) ~= "table" then db.readyToBuyKinds = {} end
    if db.worldQuestHuntEnabled == nil then db.worldQuestHuntEnabled = not freshInstall end
    if db.worldQuestHuntGold == nil then db.worldQuestHuntGold = true end
    if tonumber(db.worldQuestHuntMinGold) == nil then db.worldQuestHuntMinGold = 500 end
    if db.worldQuestHuntCollectables == nil then db.worldQuestHuntCollectables = true end
    if db.worldQuestHuntCurrency == nil then db.worldQuestHuntCurrency = false end
    if type(db.worldQuestHuntCurrencyText) ~= "string" then db.worldQuestHuntCurrencyText = "" end
    if db.worldQuestHuntReputation == nil then db.worldQuestHuntReputation = false end
    if type(db.worldQuestHuntReputationText) ~= "string" then db.worldQuestHuntReputationText = "" end
    if db.worldQuestHuntHideEmpty == nil then db.worldQuestHuntHideEmpty = true end
    if db.worldQuestHuntShowCompleted == nil then db.worldQuestHuntShowCompleted = false end
    if type(db.charWorldQuestDone) ~= "table" then db.charWorldQuestDone = {} end
    if type(db.worldQuestHuntExpansions) ~= "table" then
        db.worldQuestHuntExpansions = { midnight = true }
    end
    -- Minimap icon (LibDBIcon-1.0); LibDBIcon expects a table with `hide` boolean.
    if type(db.minimap) ~= "table" then db.minimap = {} end
    if db.minimap.hide == nil then db.minimap.hide = false end
    if db.minimized      == nil then db.minimized      = false end
    if db.wasShown       == nil then db.wasShown       = false end
    if db.lastDaily      == nil then db.lastDaily      = 0 end
    if db.lastWeekly     == nil then db.lastWeekly     = 0 end
    -- Daily / weekly reset schedule (see Core/ResetSchedule.lua, Options → General).
    if db.resetSchedulePreset == nil then db.resetSchedulePreset = "server" end
    if db.resetSchedulePreset ~= "server" and db.resetSchedulePreset ~= "us"
        and db.resetSchedulePreset ~= "eu" and db.resetSchedulePreset ~= "custom" then
        db.resetSchedulePreset = "server"
    end
    if db.resetCustomDailyHour == nil then db.resetCustomDailyHour = 8 end
    if db.resetCustomDailyMinute == nil then db.resetCustomDailyMinute = 0 end
    if db.resetCustomDailyTZ == nil or (db.resetCustomDailyTZ ~= "Pacific" and db.resetCustomDailyTZ ~= "Eastern"
        and db.resetCustomDailyTZ ~= "CET" and db.resetCustomDailyTZ ~= "UTC") then
        db.resetCustomDailyTZ = "Pacific"
    end
    if db.resetCustomWeeklyHour == nil then db.resetCustomWeeklyHour = 10 end
    if db.resetCustomWeeklyMinute == nil then db.resetCustomWeeklyMinute = 0 end
    if db.resetCustomWeeklyWday == nil then db.resetCustomWeeklyWday = 3 end -- Tuesday (Lua wday)
    if db.resetCustomWeeklyTZ == nil or (db.resetCustomWeeklyTZ ~= "Pacific" and db.resetCustomWeeklyTZ ~= "Eastern"
        and db.resetCustomWeeklyTZ ~= "CET" and db.resetCustomWeeklyTZ ~= "UTC") then
        db.resetCustomWeeklyTZ = "Eastern"
    end
    if db.indentSize     == nil then db.indentSize     = 12 end
    -- List layout (scroll gutter, padding, vertical gaps)
    if db.scrollGutter         == nil then db.scrollGutter         = 6 end
    if db.listPadLeft          == nil then db.listPadLeft          = 8 end
    if db.listPadRight         == nil then db.listPadRight         = 6 end
    if db.listPadTop           == nil then db.listPadTop           = 0 end
    if db.listPadBottom        == nil then db.listPadBottom        = 0 end
    if db.spacingGroupHeader   == nil then db.spacingGroupHeader   = 2 end
    if db.spacingGroupSection  == nil then db.spacingGroupSection  = 4 end
    if db.spacingBetweenTasks  == nil then db.spacingBetweenTasks  = 0 end
    if db.extraHeaderHeight    == nil then db.extraHeaderHeight    = 0 end
    if db.extraTaskHeight      == nil then db.extraTaskHeight      = 0 end
    if db.cmdIconPercent       == nil then db.cmdIconPercent       = 80 end
    if db.rowIconPercent       == nil then db.rowIconPercent       = 90 end
    if db.checkboxPercent      == nil then db.checkboxPercent      = 85 end
    if db.labelToIconGap       == nil then db.labelToIconGap       = 6 end
    if db.headerTitleGap       == nil then db.headerTitleGap       = 6 end
    if db.fontPercent    == nil then db.fontPercent    = 100 end
    -- Task list: narrow panel — ellipsis vs wrap (multi-line title; row grows).
    if db.taskLabelOverflow == nil then db.taskLabelOverflow = "ellipsis" end
    if db.taskLabelOverflow ~= "grow" and db.taskLabelOverflow ~= "ellipsis" then
        db.taskLabelOverflow = "ellipsis"
    end
    if db.uiScalePercent == nil then db.uiScalePercent = 100 end
    if db.panelWidth     == nil then db.panelWidth     = 280 end
    if db.panelHeight    == nil then db.panelHeight    = 400 end
    if db.theme          == nil then db.theme          = "gilded" end
    if db.iconSet ~= "classic" and db.iconSet ~= "tintable" then
        db.iconSet = "classic"
    end
    if db.optionsPanelWidth  == nil then db.optionsPanelWidth  = 1160 end
    if db.optionsPanelHeight == nil then db.optionsPanelHeight = 680 end
    if db.powerDetailsPanelWidth  == nil then db.powerDetailsPanelWidth  = 780 end
    if db.powerDetailsPanelHeight == nil then db.powerDetailsPanelHeight = 520 end
    if db.optionsNavKey == "notes" then
        db.optionsNavKey = "style"
    end
    if db.optionsNavKey ~= "general" and db.optionsNavKey ~= "characters"
        and db.optionsNavKey ~= "style"
        and db.optionsNavKey ~= "advanced" and db.optionsNavKey ~= "modules"
        and db.optionsNavKey ~= "generative" and db.optionsNavKey ~= "profiles" then
        db.optionsNavKey = "general"
    end
    if type(db.charMeta) ~= "table" then
        db.charMeta = {}
    end
    if db.charTooltipAlwaysCurrencyTotal == nil then
        db.charTooltipAlwaysCurrencyTotal = true
    end
    if db.charTooltipAlwaysHighestRep == nil then
        db.charTooltipAlwaysHighestRep = true
    end
    if db.notePanelSide == nil then db.notePanelSide = "right" end
    if db.alwaysShowNoteIcon == nil then db.alwaysShowNoteIcon = false end
    if db.notePeekBgOpacityPercent == nil and db.notePeekTextOpacityPercent == nil then
        if db.notePeekOpacityPercent ~= nil then
            db.notePeekBgOpacityPercent    = db.notePeekOpacityPercent
            db.notePeekTextOpacityPercent = 100
        else
            db.notePeekBgOpacityPercent    = 85
            db.notePeekTextOpacityPercent = 100
        end
    else
        if db.notePeekBgOpacityPercent == nil then
            db.notePeekBgOpacityPercent = 85
        end
        if db.notePeekTextOpacityPercent == nil then
            db.notePeekTextOpacityPercent = 100
        end
    end
    if db.notePeekCmdOpacityPercent == nil then
        db.notePeekCmdOpacityPercent = 100
    end
    -- Collectable task dialog: omit mounts/toys/pets already in collection when building picker list.
    if db.collectablesHideOwnedInPicker == nil then
        db.collectablesHideOwnedInPicker = true
    end

    -- Tree
    if not db.tree then
        db.tree = BuildDefaultTree()
    end
    TaskTracker.RepairLoadedTree()

    if TaskTracker.MigrateTaskScopeDefaults then
        TaskTracker.MigrateTaskScopeDefaults()
    end
    if TaskTracker.MigrateTaskOwnerCharKeys then
        TaskTracker.MigrateTaskOwnerCharKeys()
    end

    -- Registry state
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then
        print("|cffff6666TaskTracker|r quest catalog failed to load. Skipping registry cleanup so saved progress is not wiped. Fix the error and /reload.")
    end
    if not db.registryState then
        db.registryState = BuildDefaultRegistryState(freshInstall)
    else
        -- Migrate M+ ids before prune removes legacy registryState keys.
        MigrateMPlusRegistryState(db.registryState)
        MigrateHawkeyeSohoState(db.registryState)
        PruneMissingRegistryState(db.registryState)
        PatchRegistryState(db.registryState)
        -- Re-baseline weekly quest_count delta when the Special Assignment id pool changes (mid-week safe).
        local SPECIAL_ASSIGNMENT_POOL_STATE_VER = 3
        if (db.specialAssignmentPoolStateVer or 0) < SPECIAL_ASSIGNMENT_POOL_STATE_VER then
            local st = db.registryState["s1_special_assignments"]
            if st then
                st.questPeriodBaselineCount = nil
            end
            db.specialAssignmentPoolStateVer = SPECIAL_ASSIGNMENT_POOL_STATE_VER
        end
        -- Spark Quest: quest id pool changes; re-baseline weekly delta.
        local SPARK_QUEST_POOL_STATE_VER = 2
        if (db.sparkQuestPoolStateVer or 0) < SPARK_QUEST_POOL_STATE_VER then
            local st = db.registryState["s1_ritual_sites"]
            if st then
                st.questPeriodBaselineCount = nil
            end
            db.sparkQuestPoolStateVer = SPARK_QUEST_POOL_STATE_VER
        end
        -- Prey Nightmare: Coiled Isle ids 95021–95024; re-baseline weekly delta.
        local PREY_NIGHTMARE_POOL_STATE_VER = 1
        if (db.preyNightmarePoolStateVer or 0) < PREY_NIGHTMARE_POOL_STATE_VER then
            local st = db.registryState["prey_nightmare"]
            if st then
                st.questPeriodBaselineCount = nil
            end
            db.preyNightmarePoolStateVer = PREY_NIGHTMARE_POOL_STATE_VER
        end
        -- Nullaeus: drop the false weekly complete from quest 86371 (Delver's Bounty map loot).
        local NULLAEUS_KILL_TRACK_VER = 1
        if (db.nullaeusKillTrackVer or 0) < NULLAEUS_KILL_TRACK_VER then
            local st = db.registryState["seasonal_delves_nullaeus"]
            if st then
                st.value = 0
                st.weeklyQuestCompleteLatched = nil
                st.userValue = nil
                st.override = nil
                st.checkboxDoneOverride = nil
                st.powerShareClaimAt = nil
            end
            db.nullaeusKillTrackVer = NULLAEUS_KILL_TRACK_VER
        end
    end

    if TaskTracker.SyncMPlusDungeonGuidesPackTree then
        TaskTracker.SyncMPlusDungeonGuidesPackTree()
    end

    -- Options state (Modules tab); ensure new expansion keys exist after addon updates
    if not db.optionsExpanded then
        db.optionsExpanded = {}
        for _, exp in ipairs(TaskTracker.ExpansionOrder) do
            db.optionsExpanded[exp] = true
        end
        if TaskTracker.Registry then
            for _, entry in ipairs(TaskTracker.Registry) do
                if entry.subsection and entry.expansion then
                    local sk = entry.expansion .. "_" .. entry.subsection
                    db.optionsExpanded[sk] = true
                end
            end
        end
    else
        for _, exp in ipairs(TaskTracker.ExpansionOrder) do
            if db.optionsExpanded[exp] == nil then
                db.optionsExpanded[exp] = true
            end
        end
        -- Nested module groups (e.g. midnight_patch_12_0_0, midnight_patch_12_0_5)
        if TaskTracker.Registry then
            for _, entry in ipairs(TaskTracker.Registry) do
                if entry.subsection and entry.expansion then
                    local sk = entry.expansion .. "_" .. entry.subsection
                    if db.optionsExpanded[sk] == nil then
                        db.optionsExpanded[sk] = true
                    end
                end
            end
        end
    end

    if not db.optionsGroupExpanded then
        db.optionsGroupExpanded = {}
    end

    if TaskTracker.InvalidateResetTimesCache then
        TaskTracker.InvalidateResetTimesCache()
    end

    if TaskTracker.GetCharProgressKey and TaskTracker.GetCharProgressKey()
        and TaskTracker.RefreshLearnedProfessionsTree then
        TaskTracker.RefreshLearnedProfessionsTree()
    end

    if TaskTracker.MigrateProfiles then
        TaskTracker.MigrateProfiles()
    end
    if TaskTracker.ApplyNewModuleDefaults then
        TaskTracker.ApplyNewModuleDefaults()
    end

    if TaskTracker.MigrateLayoutPreset then
        TaskTracker.MigrateLayoutPreset()
    end
    if TaskTracker.ApplyStoredLayoutPreset then
        TaskTracker.ApplyStoredLayoutPreset()
    end
    if TaskTracker.MigrateOptionsPanelStyle then
        TaskTracker.MigrateOptionsPanelStyle()
    end

end

-- One-time layout migrations. Ongoing syncs (Power, patch rows, professions, sanitize) still run.
-- Profile loads call this again so an inactive profile catches up when it is opened.
TaskTracker.TREE_SCHEMA_VER = 1
TaskTracker.BUILT_IN_NOTES_TO_TOOLTIP_VER = 1

function TaskTracker.RepairLoadedTree()
    local db = TaskTrackerDB
    if not db or not db.tree then return end
    local TREE_SCHEMA_VER = TaskTracker.TREE_SCHEMA_VER
    if (db.treeSchemaVer or 0) < TREE_SCHEMA_VER then
        MigrateMPlusRegistryNodesInTree(db.tree)
        MigrateMidnightPatchGroupsInTree(db.tree)
        MigrateSparkQuestRegistryToSeasonalGeneral(db.tree)
        EnsurePreyNightmarishInTree(db.tree)
        MigrateModuleGroupKeysInTree(db.tree)
        db.treeSchemaVer = TREE_SCHEMA_VER
    end
    MigrateHawkeyeSohoInTree(db.tree)
    SyncMidnightPatchRegistryNodes(db.tree)
    EnsureSeasonalActivitiesInTree(db.tree)
    EnsureSeasonalMplusGroupInTree(db.tree)
    PruneEmptyDuplicateSeasonalRoots(db.tree)
    EnsurePowerGroupInTree(db.tree)
    EnsureProfessionsGroupInTree(db.tree)
    PatchTaskNodes(db.tree)
    local notesVer = TaskTracker.BUILT_IN_NOTES_TO_TOOLTIP_VER
    if (db.builtInNotesToTooltipVer or 0) < notesVer then
        ClearMatchingBuiltInNotes(db.tree)
        db.builtInNotesToTooltipVer = notesVer
    end
    if TaskTracker.InvalidateAdvancedTaskIndex then
        TaskTracker.InvalidateAdvancedTaskIndex()
    end
end

--- Peek opacity as 0–1. `hovered` reads the mouse-over slider, then the away slider.
local function notePeekOpacity(awayKey, hoverKey, fallback, hovered)
    local db = TaskTrackerDB
    local p
    if hovered and db and hoverKey then
        p = tonumber(db[hoverKey])
    end
    if p == nil and db then
        p = tonumber(db[awayKey])
    end
    if not p then p = fallback end
    p = math.max(0, math.min(100, math.floor(p + 0.5)))
    return p / 100
end

--- Peek window background opacity (0–1). Away slider, unless `hovered`.
function TaskTracker.GetNotePeekBgOpacity(hovered)
    return notePeekOpacity("notePeekBgOpacityPercent", "notePeekHoverBgOpacityPercent", 85, hovered)
end

--- Peek window text opacity (0–1). Away slider, unless `hovered`.
function TaskTracker.GetNotePeekTextOpacity(hovered)
    return notePeekOpacity("notePeekTextOpacityPercent", "notePeekHoverTextOpacityPercent", 100, hovered)
end

--- Peek × + inline command button opacity (0–1). UI floors × at 10%.
function TaskTracker.GetNotePeekCmdOpacity(hovered)
    return notePeekOpacity("notePeekCmdOpacityPercent", "notePeekHoverCmdOpacityPercent", 100, hovered)
end

-- ─────────────────────────────────────
-- List layout helpers (saved + theme fallbacks)
-- ─────────────────────────────────────
function TaskTracker.GetScrollGutter()
    local v = TaskTrackerDB and TaskTrackerDB.scrollGutter
    if v == nil then v = 3 end
    return math.max(0, math.min(12, math.floor(tonumber(v) or 3)))
end

function TaskTracker.GetListPadLeft()
    local v = TaskTrackerDB and TaskTrackerDB.listPadLeft
    if v == nil then v = 0 end
    return math.max(0, math.min(16, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetListPadRight()
    local v = TaskTrackerDB and TaskTrackerDB.listPadRight
    if v == nil then v = 8 end
    return math.max(0, math.min(12, math.floor(tonumber(v) or 8)))
end

function TaskTracker.GetListPadTop()
    local v = TaskTrackerDB and TaskTrackerDB.listPadTop
    if v == nil then v = 0 end
    return math.max(0, math.min(8, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetListPadBottom()
    local v = TaskTrackerDB and TaskTrackerDB.listPadBottom
    if v == nil then v = 0 end
    return math.max(0, math.min(8, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetSpacingGroupHeader()
    local v = TaskTrackerDB and TaskTrackerDB.spacingGroupHeader
    if v == nil then v = 0 end
    return math.max(0, math.min(4, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetSpacingGroupSection()
    local v = TaskTrackerDB and TaskTrackerDB.spacingGroupSection
    if v == nil then v = 0 end
    return math.max(0, math.min(8, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetSpacingBetweenTasks()
    local v = TaskTrackerDB and TaskTrackerDB.spacingBetweenTasks
    if v == nil then v = 0 end
    return math.max(0, math.min(8, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetExtraHeaderHeight()
    local v = TaskTrackerDB and TaskTrackerDB.extraHeaderHeight
    if v == nil then v = 0 end
    return math.max(-10, math.min(10, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetExtraTaskHeight()
    local v = TaskTrackerDB and TaskTrackerDB.extraTaskHeight
    if v == nil then v = 0 end
    return math.max(-10, math.min(10, math.floor(tonumber(v) or 0)))
end

function TaskTracker.GetListCommandIconPercent()
    return TaskTracker.GetListRowIconPercent()
end

function TaskTracker.GetListRowIconPercent()
    local v = TaskTrackerDB and TaskTrackerDB.rowIconPercent
    if v == nil then v = 60 end
    return math.max(60, math.min(100, math.floor(tonumber(v) or 60)))
end

function TaskTracker.GetListCheckboxPercent()
    local v = TaskTrackerDB and TaskTrackerDB.checkboxPercent
    if v == nil then v = 70 end
    return math.max(50, math.min(120, math.floor(tonumber(v) or 70)))
end

function TaskTracker.GetLabelToIconGap()
    local v = TaskTrackerDB and TaskTrackerDB.labelToIconGap
    if v == nil then v = 2 end
    return math.max(0, math.min(12, math.floor(tonumber(v) or 2)))
end

function TaskTracker.GetHeaderTitleGap()
    local v = TaskTrackerDB and TaskTrackerDB.headerTitleGap
    if v == nil then v = 4 end
    return math.max(0, math.min(12, math.floor(tonumber(v) or 4)))
end

function TaskTracker.GetCollectablesHideOwnedInPicker()
    return TaskTrackerDB and TaskTrackerDB.collectablesHideOwnedInPicker == true
end

--- "ellipsis" = one line + "…"; "grow" = wrap title (and subtitle) and increase row height.
function TaskTracker.GetTaskLabelOverflowMode()
    local m = TaskTrackerDB and TaskTrackerDB.taskLabelOverflow
    if m == "grow" then return "grow" end
    return "ellipsis"
end

-- ─────────────────────────────────────
-- Reset logic
-- ─────────────────────────────────────
function TaskTracker.CheckResets()
    local db = TaskTrackerDB
    if not (TaskTracker.IsRegistryCatalogReady and TaskTracker.IsRegistryCatalogReady()) then
        return
    end
    -- The hidden new-install profile is not this character's list. A reset here
    -- would bump the stamps and then skip that list.
    if TaskTracker.HiddenProfileIsLoaded and TaskTracker.HiddenProfileIsLoaded() then
        return
    end
    if not TaskTracker._ttCharProgressLoaded then
        return
    end
    local dailyReset, weeklyReset = TaskTracker.GetResetTimes()
    local needWeekly = db.lastWeekly < weeklyReset
    local needDaily  = db.lastDaily < dailyReset

    -- Registry resets
    if needWeekly then
        for _, entry in ipairs(TaskTracker.Registry) do
            if entry.reset == "weekly" then
                local state = db.registryState[entry.id]
                if state then
                    state.value     = 0
                    state.override  = nil
                    state.userValue = nil
                    state.checkboxDoneOverride = nil
                    state.trackItemHadThisPeriod = nil
                    state.trackItemHadByChar = nil
                    state.weeklyQuestCompleteLatched = nil
                    state.powerShareClaimAt = nil
                    state.powerShareClaimTimes = nil
                    state.questPeriodBaselineCount = nil
                end
            end
        end
        if TaskTracker.ClearCharRegistryOverridesForReset then
            TaskTracker.ClearCharRegistryOverridesForReset("weekly")
        end
        db.lastWeekly = weeklyReset
        if TaskTracker.InvalidatePowerShareWinnersCache then
            TaskTracker.InvalidatePowerShareWinnersCache()
        end
    end

    if needDaily then
        for _, entry in ipairs(TaskTracker.Registry) do
            if entry.reset == "daily" then
                local state = db.registryState[entry.id]
                if state then
                    state.value     = 0
                    state.override  = nil
                    state.userValue = nil
                    state.checkboxDoneOverride = nil
                    state.trackItemHadThisPeriod = nil
                    state.trackItemHadByChar = nil
                end
            end
        end
        if TaskTracker.ClearCharRegistryOverridesForReset then
            TaskTracker.ClearCharRegistryOverridesForReset("daily")
        end
        db.lastDaily = dailyReset
    end

    -- Task node resets (recursive; use flags — lastDaily/lastWeekly already bumped above)
    TaskTracker.WalkTree(function(node)
        if node.type == "task" then
            if TaskTracker.RestoreHeldShareCount then
                TaskTracker.RestoreHeldShareCount(node)
            end
            local holdWeekly = false
            if node.reset == "weekly" and node.liveShareRole == "receiver" and TaskTracker.LiveShareHoldsWeeklyReset then
                local sameWeek = TaskTracker.LiveShareHoldsWeeklyReset(node, weeklyReset)
                if sameWeek and needWeekly then
                    holdWeekly = true
                end
            end
            if TaskTracker.AdvancedOnPeriodReset then
                TaskTracker.AdvancedOnPeriodReset(node, needDaily, needWeekly and not holdWeekly)
            end
            if node.reset == "daily" and needDaily then
                node.done = false
                node.taskCount = 0
                node.taskUserValue = nil
                node.doneOverride = nil
            end
            if node.reset == "weekly" and needWeekly and not holdWeekly then
                node.done = false
                node.taskCount = 0
                node.taskUserValue = nil
                node.doneOverride = nil
                if node.liveShareRole == "receiver" then
                    node.liveSharePeriod = weeklyReset
                    node.liveShareSentCount = 0
                end
            end
        end
    end)

    if needWeekly and TaskTracker.ResetStoredCharTaskPeriod then
        TaskTracker.ResetStoredCharTaskPeriod("weekly", weeklyReset, "check")
    end
    if needDaily and TaskTracker.ResetStoredCharTaskPeriod then
        TaskTracker.ResetStoredCharTaskPeriod("daily", dailyReset, "check")
    end

    if TaskTracker.PersistActiveCharTaskProgress then
        TaskTracker.PersistActiveCharTaskProgress()
    end
end

-- ─────────────────────────────────────
-- Tree walker
-- Calls fn(node, parent, index) for every node
-- ─────────────────────────────────────
function TaskTracker.WalkTree(fn, node, parent, index)
    node = node or TaskTrackerDB.tree
    if not node then return false end
    if fn(node, parent, index) then return true end
    if node.children then
        for i, child in ipairs(node.children) do
            if TaskTracker.WalkTree(fn, child, node, i) then return true end
        end
    end
    return false
end

local function afterTreeStructureChange()
    if TaskTracker.InvalidateAdvancedTaskIndex then
        TaskTracker.InvalidateAdvancedTaskIndex()
    end
    if TaskTracker.RefreshCombatLogKillRegistration then
        TaskTracker.RefreshCombatLogKillRegistration()
    end
end

-- ─────────────────────────────────────
-- Find a node by ID
-- Returns node, parent, index
-- ─────────────────────────────────────
function TaskTracker.FindNode(targetID, node, parent, index)
    node = node or TaskTrackerDB.tree
    if not node then return nil end
    if node.id == targetID then
        return node, parent, index
    end
    if node.children then
        for i, child in ipairs(node.children) do
            local found, foundParent, foundIndex = TaskTracker.FindNode(targetID, child, node, i)
            if found then return found, foundParent, foundIndex end
        end
    end
    return nil
end

-- ─────────────────────────────────────
-- Move a node up within its parent
-- ─────────────────────────────────────
function TaskTracker.MoveNodeUp(nodeID)
    local node, parent, index = TaskTracker.FindNode(nodeID)
    if not node or not parent or index <= 1 then return end
    parent.children[index], parent.children[index - 1] =
        parent.children[index - 1], parent.children[index]
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

-- ─────────────────────────────────────
-- Move a node down within its parent
-- ─────────────────────────────────────
function TaskTracker.MoveNodeDown(nodeID)
    local node, parent, index = TaskTracker.FindNode(nodeID)
    if not node or not parent or index >= #parent.children then return end
    parent.children[index], parent.children[index + 1] =
        parent.children[index + 1], parent.children[index]
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

function TaskTracker.NodeIsUnderAncestor(nodeId, ancestorId)
    if not nodeId or not ancestorId then return false end
    local _, par = TaskTracker.FindNode(nodeId)
    while par do
        if par.id == ancestorId then return true end
        _, par = TaskTracker.FindNode(par.id)
    end
    return false
end

function TaskTracker.MoveNodeBefore(nodeID, beforeNodeID)
    if not nodeID or not beforeNodeID or nodeID == beforeNodeID then return end
    local node, pSrc, iSrc = TaskTracker.FindNode(nodeID)
    local _, pTgt, iTgt = TaskTracker.FindNode(beforeNodeID)
    if not node or not pTgt or not iTgt then return end
    if TaskTracker.NodeIsUnderAncestor(beforeNodeID, nodeID) then return end
    table.remove(pSrc.children, iSrc)
    if pSrc == pTgt and iSrc < iTgt then
        iTgt = iTgt - 1
    end
    table.insert(pTgt.children, iTgt, node)
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

function TaskTracker.MoveNodeAfter(nodeID, afterSiblingId)
    if not nodeID or not afterSiblingId or nodeID == afterSiblingId then return end
    local aft, pTgt, iAft = TaskTracker.FindNode(afterSiblingId)
    local node, pSrc, iSrc = TaskTracker.FindNode(nodeID)
    if not aft or not pTgt or not iAft or not node then return end
    if TaskTracker.TaskMoveIntoSectionBlocked and TaskTracker.TaskMoveIntoSectionBlocked(node, pTgt) then
        return
    end
    if TaskTracker.NodeIsUnderAncestor(afterSiblingId, nodeID) then return end
    table.remove(pSrc.children, iSrc)
    if pSrc == pTgt and iSrc < iAft then
        iAft = iAft - 1
    end
    table.insert(pTgt.children, iAft + 1, node)
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

function TaskTracker.MoveNodeToGroupStart(nodeID, parentID)
    local parent = TaskTracker.FindNode(parentID)
    if not parent then return end
    local moving = TaskTracker.FindNode(nodeID)
    if moving and TaskTracker.TaskMoveIntoSectionBlocked and TaskTracker.TaskMoveIntoSectionBlocked(moving, parent) then
        return
    end
    if parent.type ~= "group" and parent.type ~= "root" then return end
    if TaskTracker.NodeIsUnderAncestor(parentID, nodeID) then return end
    if not parent.children then parent.children = {} end
    local node, pSrc, iSrc = TaskTracker.FindNode(nodeID)
    if not node then return end
    if #parent.children == 0 then
        table.remove(pSrc.children, iSrc)
        table.insert(parent.children, 1, node)
        if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
        if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    else
        TaskTracker.MoveNodeBefore(nodeID, parent.children[1].id)
    end
end

-- ─────────────────────────────────────
-- Remove a node from the tree
-- ─────────────────────────────────────
function TaskTracker.RemoveNode(nodeID, opts)
    local node, parent, index = TaskTracker.FindNode(nodeID)
    if not node or not parent then return end
    if node.type == "registryEntry" and TaskTracker.RegistryByID[node.registryEntryId] then
        return
    end
    if node.type == "group" and TaskTracker.IsProtectedModuleGroup(node) then
        return
    end
    if TaskTracker.NotifyLiveShareRemoved then
        TaskTracker.NotifyLiveShareRemoved(node)
    end
    table.remove(parent.children, index)
    if TaskTracker.PruneCharProgressForRemovedNode then
        TaskTracker.PruneCharProgressForRemovedNode(node)
    end
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if not (opts and opts.skipRefresh) and TaskTracker.RefreshList then
        TaskTracker.RefreshList()
    end
end

--- Custom tasks with reset "temporary" remove themselves when complete.
--- Built-in collection farm rows (`collectionFarmId`) are left alone.
function TaskTracker.IsCustomTemporaryTask(node)
    return node and node.type == "task" and node.reset == "temporary" and not node.collectionFarmId
end

--- Remove completed custom Temporary tasks. Returns true if anything was deleted.
function TaskTracker.SweepCompletedTemporaryTasks()
    local db = TaskTrackerDB
    if not db or not db.tree then return false end
    local skipId
    local dlg = TaskTracker.taskDialog
    if dlg and dlg.IsShown and dlg:IsShown() then
        skipId = dlg._editNodeId
    end
    local ids = {}
    TaskTracker.WalkTree(function(node)
        if not TaskTracker.IsCustomTemporaryTask(node) then return end
        if skipId and node.id == skipId then return end
        if node.advanced and node.advanced.type == "mplus_hint" then return end
        if TaskTracker.IsTaskEffectivelyDone and TaskTracker.IsTaskEffectivelyDone(node) then
            ids[#ids + 1] = node.id
        end
    end)
    if #ids == 0 then return false end
    for i = 1, #ids do
        TaskTracker.RemoveNode(ids[i], { skipRefresh = true })
    end
    local welcome
    TaskTracker.WalkTree(function(node)
        if node.welcomeGroup then welcome = node end
    end)
    if welcome and #(welcome.children or {}) == 0 then
        TaskTracker.RemoveNode(welcome.id, { skipRefresh = true })
    end
    return true
end

-- ─────────────────────────────────────
-- Add a child node to a parent
-- ─────────────────────────────────────
function TaskTracker.AddChild(parentID, childNode, afterIndex)
    local parent = TaskTracker.FindNode(parentID)
    if not parent then return end
    if afterIndex then
        table.insert(parent.children, afterIndex + 1, childNode)
    else
        table.insert(parent.children, childNode)
    end
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

-- ─────────────────────────────────────
-- Insert a new group after a given node
-- ─────────────────────────────────────
function TaskTracker.InsertGroupAfter(siblingID, name)
    local _, parent, index = TaskTracker.FindNode(siblingID)
    if not parent then return end
    local newGroup = TaskTracker.NewGroupNode(name)
    table.insert(parent.children, index + 1, newGroup)
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

-- ─────────────────────────────────────
-- Insert a new group before a given node
-- ─────────────────────────────────────
function TaskTracker.InsertGroupBefore(siblingID, name)
    local _, parent, index = TaskTracker.FindNode(siblingID)
    if not parent then return end
    local newGroup = TaskTracker.NewGroupNode(name)
    table.insert(parent.children, index, newGroup)
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end

-- ─────────────────────────────────────
-- Add a task to a group
-- ─────────────────────────────────────
function TaskTracker.AddTaskToGroup(groupID, name, reset, taskMax, advanced, excludeFromRollup, accountWide, showOnOtherCharacters)
    local group = TaskTracker.FindNode(groupID)
    if not group or group.type ~= "group" then return end
    if TaskTracker.ModuleSectionBlocksNewTask and TaskTracker.ModuleSectionBlocksNewTask(group) then
        return
    end
    local newNode = TaskTracker.NewTaskNode(name, reset, taskMax, advanced, excludeFromRollup, accountWide, showOnOtherCharacters)
    if advanced and advanced.type == "collectable" then
        local ent = TaskTracker.GetCollectableEntry
            and TaskTracker.GetCollectableEntry(advanced.collectableExpansion, advanced.collectableCategory, advanced.collectableEntryId)
        if ent then
            TaskTracker.AppendMissingCommandButtons(newNode, ent.defaultCommandButtons)
        end
    end
    table.insert(group.children, newNode)
    if advanced and advanced.type == "collectable" and TaskTracker.UpdateCollectableFromQuestFlags then
        TaskTracker.UpdateCollectableFromQuestFlags(newNode)
    end
    if TaskTracker.SyncAdvancedTask then
        TaskTracker.SyncAdvancedTask(newNode)
    end
    if TaskTracker.EnsureNewTaskCharOwnership then
        TaskTracker.EnsureNewTaskCharOwnership(newNode)
    end
    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
    return newNode
end

-- ─────────────────────────────────────
-- Reparent a node (move to different group)
-- ─────────────────────────────────────
function TaskTracker.ReparentNode(nodeID, newParentID, afterIndex)
    local node, oldParent, oldIndex = TaskTracker.FindNode(nodeID)
    if not node or not oldParent then return end

    -- Remove from old parent
    table.remove(oldParent.children, oldIndex)

    -- Add to new parent
    local newParent = TaskTracker.FindNode(newParentID)
    if not newParent then return end

    if afterIndex then
        table.insert(newParent.children, afterIndex + 1, node)
    else
        table.insert(newParent.children, node)
    end

    afterTreeStructureChange()
    if TaskTracker.MarkListLayoutDirty then TaskTracker.MarkListLayoutDirty() end
    if TaskTracker.RefreshList then TaskTracker.RefreshList() end
end