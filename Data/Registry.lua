-- Data/Registry.lua
-- Registry of all module-tracked activities (see Options → Modules)
-- Each entry is a trackable game activity
-- Entries are placed into the tree by DB init
-- To add a tracked activity: add an entry here, add its id to the matching order
-- list in Core/DB.lua, and if it drops seasonal gear, add a source in Data/PowerSeason.lua.

TaskTracker = TaskTracker or {}

-- ─────────────────────────────────────
-- Expansion display names
-- ─────────────────────────────────────
TaskTracker.ExpansionLabels = {
    power        = "Power",
    seasonal     = "Seasonal Activities",
    professions  = "Professions",
    midnight     = "Midnight",
    tww          = "The War Within",
    dragonflight = "Dragonflight",
}

TaskTracker.ExpansionOrder = {
    "power",
    "seasonal",
    "midnight",
    "professions",
    "tww",
    "dragonflight",
}

-- Live patch a brand-new install turns on.
-- Activities under this key start on. Collections and older patches stay off.
TaskTracker.STARTER_PATCH_KEY = "patch_12_1_0"

--- True for rows a brand-new install shows: Professions, Seasonal Activities
--- except Vault Status, Dungeons, and Raids, and the current patch's zone activities.
--- Collections stay off.
function TaskTracker.IsStarterRegistryEntry(entry)
    if type(entry) ~= "table" then return false end
    local exp = entry.expansion
    if exp == "seasonal" then
        local sub = entry.subsection
        if sub == "vault" or sub == "mplus" or sub == "raid" then return false end
        return true
    end
    if exp == "professions" then return true end
    if exp ~= "midnight" then return false end
    local sub = entry.subsection
    if type(sub) ~= "string" or sub == "" then return false end
    if sub:find("_collections", 1, true) then return false end
    local patch = TaskTracker.STARTER_PATCH_KEY
    if type(patch) ~= "string" or patch == "" then return false end
    if sub == patch then return true end
    return sub:sub(1, #patch + 1) == (patch .. "_")
end

-- List grouping (Options → General / Modules): A = patch modules, B = patch then zone, C = zones.
TaskTracker.ListZoneOrder = { "midnight", "instanced", "coiled_isle", "vaults", "harandar", "quelthalas", "zulaman", "voidstorm" }
-- mapIds are uiMap roots. Subzones match by walking C_Map parent links up to one of these.
-- Vaults (2509) is listed before the isle so a vaults map resolves before its parent 2512.
TaskTracker.ListZones = {
    midnight    = { label = "Expansion Activities" },
    instanced   = { label = "Instanced Activities" },
    coiled_isle = { label = "The Coiled Isle", mapIds = { 2512 } },
    vaults      = { label = "Vaults of Atal'Utek", parentZone = "coiled_isle", mapIds = { 2509 } },
    harandar    = { label = "Harandar", mapIds = { 2413 } },
    quelthalas  = { label = "Quel'Thalas", mapIds = { 2395, 2424 } },
    zulaman     = { label = "Zul'Aman", mapIds = { 2437 } },
    voidstorm   = { label = "Voidstorm", mapIds = { 2405 } },
}

function TaskTracker.GetListZoneParent(zoneKey)
    local z = TaskTracker.ListZones and TaskTracker.ListZones[zoneKey]
    return z and z.parentZone or nil
end

function TaskTracker.GetListZoneChildKeys(zoneKey)
    local out = {}
    if not zoneKey then return out end
    local order = TaskTracker.ListZoneOrder or {}
    local zones = TaskTracker.ListZones or {}
    for i = 1, #order do
        local k = order[i]
        local info = zones[k]
        if info and info.parentZone == zoneKey then
            out[#out + 1] = k
        end
    end
    return out
end

--- True when zoneKey is ancestorKey, or nested under it via parentZone.
function TaskTracker.IsListZoneUnder(zoneKey, ancestorKey)
    if not zoneKey or not ancestorKey then return false end
    if zoneKey == ancestorKey then return true end
    local zones = TaskTracker.ListZones or {}
    local guard = 0
    local z = zoneKey
    while z and zones[z] and zones[z].parentZone and guard < 8 do
        if zones[z].parentZone == ancestorKey then return true end
        z = zones[z].parentZone
        guard = guard + 1
    end
    return false
end
TaskTracker.CollectionCategoryOrder = { "toys", "mounts", "pets", "currency", "reputations" }
TaskTracker.CollectionCategoryLabels = {
    toys         = "Toys",
    mounts       = "Mounts",
    pets         = "Pets",
    currency     = "Currency",
    reputations  = "Reputations",
}
TaskTracker.MIDNIGHT_PATCH_ROOT_ORDER = { "patch_12_1_5", "patch_12_1_0", "patch_12_0_5", "patch_12_0_0" }
TaskTracker.MIDNIGHT_PATCH_ROOT_KEYS = {
    patch_12_1_5 = true,
    patch_12_1_0 = true,
    patch_12_0_5 = true,
    patch_12_0_0 = true,
}
TaskTracker.MIDNIGHT_COLLECTION_SUBSECTIONS = {
    toys         = "patch_12_1_0_collections_toys",
    mounts       = "patch_12_1_0_collections_mounts",
    pets         = "patch_12_1_0_collections_pets",
    currency     = "patch_12_1_0_collections_currency",
    reputations  = "patch_12_1_0_collections_reputations",
}

-- ─────────────────────────────────────
-- Registry entries
-- Fields:
--   id        (string)  unique identifier, never change once set
--   label     (string)  display name in UI
--   expansion (string)  top-level group in Options → Modules (e.g. midnight)
--   subsection (string, optional)  nested group under expansion (e.g. patch_12_0_0, patch_12_0_5, patch_12_1_0)
--   listZone  (string, optional)  zone key for Patch→zone / Zones list grouping (see ListZones)
--   type      (string)  "quest_count", "quest_complete", "vault_row" (display-only; vaultKind = raid|dungeon|world),
--                         "profession_catchup" (catchupCurrencyId; remaining knowledge on the row),
--                         "mplus_hint_row" (mplusHintKind = end_dungeon | vault; manual 0/1 + subtitle; mirrors to Power when enabled),
--                         "collectable_owned" (collectableKind = mount|pet|toy; itemId / mountId / petSpeciesId; 0/1 when journal owned;
--                           optional quests = also complete if any of those ids is flagged done;
--                         "reputation_standing" (factionId, repKind = renown|friendship, max = cap; current/max until maxed)
--   purchaseReqs (array, optional)  vendor costs on hover: renown / friendship / currency / gold / item;
--                           AllTheThings, if loaded, can fill the same hover from item cost data)
--   requireOwnedRegistryId (string, optional)  hide this row from the list and Modules until that collectable registry id is owned
--   professionKey (string, optional)  professions expansion only; row visible when the player has that primary profession
--   widgetId  (number, optional)  UI widget number for quest_count (e.g. Gilded Stash); see Core\Widgets.lua
--   trackItemId (number, optional)  for quest_count: read progress from GetItemCount (bags/bank)
--   trackItemLatch (bool, optional)  quest_count + trackItemId: once this character holds the item
--                         this reset, the row stays full after the item is opened or used.
--   itemAbsentMeansUsed (bool, optional)  if true: "used" when count hits 0 only after this
--     character held the item this reset (registryState.trackItemHadByChar[charKey])
--   latchWeeklyQuestComplete (bool, optional)  quest_complete + weekly: once any linked quest is flagged
--     complete this week (or a kill/cache latch), the row stays done until weekly reset
--   trackNpcIds (array, optional)  quest_complete: complete when one of these creature ids dies (nameplate, if dead)
--   trackEncounterName (string, optional)  quest_complete: complete on ENCOUNTER_END success when the name matches
--   trackLootObjectIds (array, optional)  quest_complete: complete when loot sources include this GameObject id
--     The in-delve nemesis cache is quest 92887, not an object loot latch.
--   max       (number)  for quest_count, the cap
--   reset     (string)  "daily", "weekly", or "none"
--   quests    (table)   set of questIDs { [id]=true }
--   defaultNote (string, optional)  Hover tooltip copy for this row (not written into the Notes field).
--   defaultCommandButtons (array, optional)  Each { label, command, icon?, pinned? } — copied into new nodes; up to MAX_PINNED_COMMANDS pinned=true are kept.
--   Power loot (ilvl, items, shared weekly pools) lives in Data/PowerSeason.lua, not here.
--
-- Note: placement in the main list tree is controlled
-- by the order lists in Core/DB.lua, not by fields here
-- ─────────────────────────────────────

-- TomTom `/way #uiMapID x y` is zone-controlled (works from any continent).
-- Coiled Isle outdoor map is 2512.
local WAY_TOKKA         = "/way #2512 57.20 48.60 Captain Tokka"
local WAY_EASTERN_FANG  = "/way #2512 45.90 64.93 Eastern Fang"
local WAY_JANSARI       = "/way #2512 58.80 46.00 Jan'sari the Watchful"
local WAY_SLUGGS        = "/way #2512 51.60 49.80 Second Mate Sluggs"
local WAY_GILLS         = "/way #2512 51.47 50.88 Brinedrinker Gills"
local WAY_ETHRANDIL     = "/way #2512 58.23 48.63 Sanctum Attendant Ethrandil"
local WAY_ASTALOR       = "/way #2512 58.21 48.72 Image of Astalor"
local WAY_ERINYE        = "/way #2509 51.20 62.40 Skull of Er'inye"
local WAY_DUGAL         = "/way #2509 50.48 63.86 Du'gal"
local WAY_BIG_MON       = "/way #2512 70.00 63.50 Big Mon"
local WAY_OLAWU         = "/way #2512 58.50 47.20 Olawu"
local WAY_RITUAL_SKULL  = "/way #2437 44.72 44.10 Abandoned Ritual Skull"
local WAY_THRAXADAR     = "/way #2444 39.32 80.96 Thraxadar"
local WAY_ICON          = TaskTracker.WAY_COMMAND_ATLAS or "TaxiNode_Neutral"

-- Vendor costs (hover). Faction 2772 Zul'jarra's Forces; 2773 Captain Tokka.
-- Currencies: 3316 Voidlight Marl, 3392 Remnant of Anguish, 3448 Corrosive Coin, 3546 Coiled Filament.
local FAC_ZULJARRA = 2772
local FAC_TOKKA    = 2773
local CUR_MARL     = 3316
local CUR_COIN     = 3448
local CUR_FILAMENT = 3546
local function reqRenown(minRank)
    return { type = "renown", factionId = FAC_ZULJARRA, min = minRank, label = "Zul'jarra's Forces" }
end
local function reqFriendship(minRank, rankName)
    return { type = "friendship", factionId = FAC_TOKKA, min = minRank, rankName = rankName, label = "Captain Tokka" }
end
local function reqCurrency(currencyId, amount)
    return { type = "currency", currencyId = currencyId, amount = amount }
end
local function reqGold(gold)
    return { type = "gold", amount = gold }
end

TaskTracker.Registry = {
    {
        id          = "prey_normal",
        label       = "Prey: Normal",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_count",
        max       = 4,
        reset     = "weekly",
        quests    = {
            [91095]=true,[91096]=true,[91097]=true,[91098]=true,[91099]=true,
            [91100]=true,[91101]=true,[91102]=true,[91103]=true,[91104]=true,
            [91105]=true,[91106]=true,[91107]=true,[91108]=true,[91109]=true,
            [91110]=true,[91111]=true,[91112]=true,[91113]=true,[91114]=true,
            [91115]=true,[91116]=true,[91117]=true,[91118]=true,[91119]=true,
            [91120]=true,[91121]=true,[91122]=true,[91123]=true,[91124]=true,
        },
        defaultNote = "Complete Prey hunts from the Prey board in Silvermoon. This row counts Normal hunts (up to 4 this week).",
    },
    {
        id          = "prey_hard",
        label       = "Prey: Hard",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_count",
        max       = 4,
        reset     = "weekly",
        quests    = {
            [91210]=true,[91212]=true,[91214]=true,[91216]=true,[91218]=true,
            [91220]=true,[91222]=true,[91224]=true,[91226]=true,[91228]=true,
            [91230]=true,[91232]=true,[91234]=true,[91236]=true,[91238]=true,
            [91240]=true,[91242]=true,[91243]=true,[91244]=true,[91245]=true,
            [91246]=true,[91247]=true,[91248]=true,[91249]=true,[91250]=true,
            [91251]=true,[91252]=true,[91253]=true,[91254]=true,[91255]=true,
        },
        defaultNote = "Complete Prey hunts from the Prey board in Silvermoon. This row counts Hard hunts (up to 4 this week).",
    },
    {
        id          = "prey_nightmare",
        label       = "Prey: Nightmare",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_count",
        max       = 4,
        reset     = "weekly",
        quests    = {
            [91211]=true,[91213]=true,[91215]=true,[91217]=true,[91219]=true,
            [91221]=true,[91223]=true,[91225]=true,[91227]=true,[91229]=true,
            [91231]=true,[91233]=true,[91235]=true,[91237]=true,[91239]=true,
            [91241]=true,[91256]=true,[91257]=true,[91258]=true,[91259]=true,
            [91260]=true,[91261]=true,[91262]=true,[91263]=true,[91264]=true,
            [91265]=true,[91266]=true,[91267]=true,[91268]=true,[91269]=true,
            -- Patch 12.1 Coiled Isle (Nightmare only on Wowhead)
            [95021]=true,[95022]=true,[95023]=true,[95024]=true,
            -- Preferential Killing: pick the target, zone, and difficulty. One quest id for every difficulty.
            [91277]=true,
        },
        defaultNote = "Complete Prey hunts from the Prey board in Silvermoon. This row counts Nightmare hunts, including Coiled Isle targets (up to 4 this week). Preferential Killing counts too: that is the hunt where you pick the target, zone, and difficulty. Sanctum Attendant Ethrandil at the Crypt of the Lost Warrior is the island Prey NPC.",
    },
    {
        id          = "prey_nightmarish",
        label       = "Prey: Nightmarish",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_complete",
        max       = 1,
        reset     = "weekly",
        quests    = { [94446] = true },
        defaultNote = "Complete the Nightmarish Prey weekly from the Prey board in Silvermoon. One hunt fills this row.",
    },

    -- ── Midnight patch weeklies (Modules → Patch 12.0.0 / 12.0.5 / 12.1.0) ──
    -- Quest IDs from Wowhead / in-game; verify with:
    --   /dump C_QuestLog.IsQuestFlaggedCompleted(<id>)
    -- If a row never updates, replace the id(s) in Data\Registry.lua.

    {
        id        = "s1_void_assaults",
        label     = "Void Assaults",
        expansion   = "midnight",
        subsection  = "patch_12_0_5",
        type      = "quest_complete",
        max       = 1,
        reset     = "weekly",
        -- Two zone-week ids; weekly delta ignores whichever id stayed flagged from a prior week.
        quests    = { [94385] = true, [94386] = true },
        defaultNote = "Complete this week's Void Assaults weekly (Patch 12.0.5). Look for the Void Assault world activity in Midnight zones.",
    },
    {
        id        = "s1_halduron_weekly",
        label     = "Halduron's Weekly",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_complete",
        max       = 1,
        reset     = "weekly",
        -- Any one of these weeklies counts as done for the row.
        quests    = {
            [93755] = true, [95468] = true, [93753] = true, [93754] = true, [93752] = true,
            [93758] = true, [93756] = true, [93757] = true, [93751] = true,
        },
        defaultNote = "Pick up Halduron Brightwing's dungeon weekly from the Farstriders in Quel'Thalas (any of his weeklies).",
    },
    {
        id        = "s1_weekly_abundance",
        label     = "Abundance",
        expansion   = "professions",
        subsection  = "_shared",
        type      = "quest_complete",
        max       = 1,
        reset     = "weekly",
        quests    = { [89507] = true },
        defaultCommandButtons = {
            {
                label = "Toy",
                command = "/use item:266370",
                icon = "achievement_dungeon_ulduar80_25man",
                pinned = true,
            },
        },
        defaultNote = "Complete the weekly Abundance profession quest at the Midnight profession hub. One turn-in fills this row. The second line is Shard of Dundun. It turns green at 6, since the quest adds 2 more toward 8. The Toy button uses Dundun's Abundant Travel Method if you have it. Midnight zones only, 30 minute cooldown.",
    },
    {
        id        = "s1_lost_legends",
        label     = "Lost Legends",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_complete",
        max       = 1,
        reset     = "weekly",
        quests    = {
            [88993] = true, [88994] = true, [88995] = true, [88996] = true, [88997] = true,
            [88998] = true, [88999] = true, [92716] = true, [92719] = true, [92720] = true,
            [92721] = true, [92722] = true, [92724] = true, [92725] = true,
        },
        defaultNote = "Find and complete a Lost Legend weekly in Harandar. Any one of the listed weeklies fills this row.",
    },
    {
        id        = "s1_fortify_runestones",
        label     = "Fortify the Runestones",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_count",
        max       = 1,
        reset     = "weekly",
        quests    = {
            [90573] = true, [90574] = true, [90575] = true, [90576] = true,
        },
        defaultNote = "Complete a Fortify the Runestones weekly in Eversong Woods. One of the listed weeklies fills this row.",
    },
    {
        id        = "s1_stormarion_assault_wq",
        label     = "Stormarion Assault (WQ)",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_complete",
        max       = 1,
        reset     = "weekly",
        -- 90962 Stormarion Assault; 93892 Midnight: Stormarion Assault (weekly flag / turn-in may use either).
        quests    = { [90962] = true, [93892] = true },
        defaultNote = "Complete the Stormarion Assault world quest when it is up in Voidstorm. Either listed weekly flag fills this row.",
    },
    {
        id        = "s1_special_assignments",
        label     = "Special Assignment",
        expansion   = "midnight",
        subsection  = "patch_12_0_0",
        type      = "quest_count",
        max       = 2,
        reset     = "weekly",
        -- Pool of possible Special Assignment quests; weekly delta: first 2 newly completed this week fill the bar.
        -- Some assignments flag either the objective quest or the map quest. Both ids are listed when both exist.
        quests    = {
            [91796] = true, -- Ours Once More!
            [91390] = true, -- What Remains of a Temple Broken
            [92063] = true, -- A Hunter's Regret
            [92145] = true, -- The Grand Magister's Drink
            [92139] = true, -- Shade and Claw
            [93013] = true, [94391] = true, -- Push Back the Light
            [93244] = true, [94795] = true, -- Agents of the Shield
            [93438] = true, [94743] = true, -- Precision Excision
            [95918] = true, [96307] = true, -- Wraith Wrath (Coiled Isle)
            [95921] = true, [96492] = true, -- Demand and Supply (Coiled Isle)
            [95922] = true, [96029] = true, -- Face the Swarm (Coiled Isle)
        },
        defaultNote = "Complete up to two Special Assignment world quests this week. They rotate across Midnight, including the Coiled Isle.",
    },
    {
        id        = "s1_cursed_surges",
        label     = "Cursed Surges",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_coiled_isle",
        type      = "quest_complete",
        max       = 1,
        reset     = "weekly",
        -- Weekly: Turn Back the Surge (complete 3 Cursed Surge events).
        quests    = { [96995] = true },
        defaultNote = "Weekly on the Coiled Isle: complete three Cursed Surge events (they show on the isle map when active), then turn in Turn Back the Surge. No pickup NPC. Shares this week's pinnacle cache cap with other pinnacle weeklies.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_TOKKA, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_purging_the_vaults",
        label       = "Purging the Vaults",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_vaults",
        type        = "quest_complete",
        max         = 1,
        reset       = "weekly",
        -- Weekly: patrol, strike, and incursion in the Vaults of Atal'Utek (not a pinnacle cache).
        quests      = { [95520] = true },
        defaultNote = "Weekly in the Vaults of Atal'Utek: pick up from Warleader Abdumati in the Amani Foothold, then complete patrol, strike, and incursion objectives. Way pins the Eastern Fang entrance (not Abdumati).",
        defaultCommandButtons = {
            { label = "Way", command = WAY_EASTERN_FANG, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_hawkeye_soho",
        label       = "Hawkeye Soho",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_vaults",
        type        = "quest_complete",
        max         = 1,
        reset       = "daily",
        -- Rotating vault dailies; only one can be picked up. Any one turn-in fills the row.
        quests      = {
            [96639] = true, -- Patrolling the Temple
            [96641] = true, -- Relentless Strikes
            [96642] = true, -- Decisive Incursions
        },
        defaultNote = "Daily in the Vaults of Atal'Utek from Hawkeye Soho. Patrolling the Temple, Relentless Strikes, and Decisive Incursions rotate, and only one can be picked up. Completes when you turn that one in. Way pins the Eastern Fang entrance.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_EASTERN_FANG, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_from_whence_it_came",
        label       = "Er'inye",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_vaults",
        type        = "quest_complete",
        max         = 1,
        reset       = "daily",
        -- Rotating vault dailies; only one can be picked up. Any one turn-in fills the row.
        quests      = {
            [96640] = true, -- Bounty of the Cursed
            [96644] = true, -- Essence of Malice
            [96643] = true, -- From Whence it Came
        },
        defaultNote = "Daily in the Vaults of Atal'Utek from Er'inye. Bounty of the Cursed, Essence of Malice, and From Whence it Came rotate, and only one can be picked up. Completes when you turn that one in. Way pins the Eastern Fang entrance.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_EASTERN_FANG, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_dugal",
        label       = "Du'gal",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_vaults",
        type        = "quest_complete",
        max         = 1,
        reset       = "daily",
        -- Rotating spirit dailies after the Tok'jara chain; any one turn-in fills the row.
        -- Daily copies only (story ids 96267/96276/96273/96275/96271 stay flagged forever).
        -- List row is hidden until Spirit of Tok'jara is learned (six-day chain).
        quests      = {
            [96349] = true, -- Ancestral Gems
            [96352] = true, -- Dark Charms
            [96354] = true, -- A Balance Paid in Blood
            [96360] = true, -- Wading In
            [96361] = true, -- Cursed Existence
        },
        requireOwnedRegistryId = "col_mount_spirit_tokjara",
        defaultNote = "Daily from Du'gal at the Amani Foothold after you learn Spirit of Tok'jara (his six-day chain; Renown 10 with Zul'jarra's Forces to start it).",
        defaultCommandButtons = {
            { label = "Way", command = WAY_DUGAL, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_open_sea_fishing",
        label       = "Open Sea Fishing",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_coiled_isle",
        type        = "quest_complete",
        max         = 1,
        reset       = "weekly",
        -- Coiled Isle world quest: board Tokka's Battered Vessel.
        quests      = { [95931] = true },
        defaultNote = "Weekly world quest on the Coiled Isle: talk to Captain Tokka and board Tokka's Battered Vessel. Requires rank 4 (Venom Trawler) with Captain Tokka.",
        purchaseReqs = { reqFriendship(4, "Venom Trawler") },
        defaultCommandButtons = {
            { label = "Way", command = WAY_TOKKA, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_brinedrinker_gills",
        label       = "Brinedrinker Gills",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_coiled_isle",
        type        = "quest_complete",
        max         = 1,
        reset       = "daily",
        -- Rotating fishing dailies at Tokka's Folly; any one turn-in fills the row.
        quests      = {
            [97562] = true, -- Culling the Killifish
            [97571] = true, -- Dogging the Darters
            [97557] = true, -- Tailing the Tlhapi
        },
        defaultNote = "Daily fishing at Tokka's Folly: turn in whichever catch Brinedrinker Gills asks for (Killifish, Darters, or Tlhapi).",
        defaultCommandButtons = {
            { label = "Way", command = WAY_GILLS, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_second_mate_sluggs",
        label       = "Second Mate Sluggs",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_coiled_isle",
        type        = "quest_complete",
        max         = 1,
        reset       = "daily",
        -- Rotating kill/collect dailies at Tokka's Folly; any one turn-in fills the row.
        quests      = {
            [94796] = true, -- Curing Curse Resistance
            [94798] = true, -- Ssak'mozek's Desire
            [94800] = true, -- Crushed Crabs
            [94802] = true, -- Death from the Dead
            [94803] = true, -- Going for the Crown
            [94804] = true, -- A Collection of Rot
            [94805] = true, -- The New Hoard, Poached
            [94806] = true, -- Wriggling and Wet
        },
        defaultNote = "Daily at Tokka's Folly: turn in whichever job Second Mate Sluggs offers (kills and pickups around the Serpent's Tail).",
        defaultCommandButtons = {
            { label = "Way", command = WAY_SLUGGS, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id          = "s1_ethrandil",
        label       = "Sanctum Attendant Ethrandil",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_coiled_isle",
        type        = "quest_complete",
        max         = 1,
        reset       = "daily",
        -- Prey daily at the Crypt of the Lost Warrior.
        quests      = {
            [96528] = true, -- Prey: Anguish from Beyond
        },
        defaultNote = "Daily Prey hunt at the Crypt of the Lost Warrior: complete Prey: Anguish from Beyond for 100 Ossified Relics.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_ETHRANDIL, icon = WAY_ICON, pinned = true },
        },
    },

    -- ── Patch 12.0.0 → Collections (rare-drop mount farms; list rows are seeded tasks) ───
    {
        id              = "col_mount_rootstalker_grimlynx",
        label           = "Rootstalker Grimlynx",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 246735,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Harandar rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_vibrant_petalwing",
        label           = "Vibrant Petalwing",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 252012,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Harandar rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_cerulean_hawkstrider",
        label           = "Cerulean Hawkstrider",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 257156,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Eversong Woods rares in Quel'Thalas. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_cobalt_dragonhawk",
        label           = "Cobalt Dragonhawk",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 257147,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Eversong Woods rares in Quel'Thalas. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_escaped_witherbark_pango",
        label           = "Escaped Witherbark Pango",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 257200,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Zul'Aman / Amani rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_amani_sharptalon",
        label           = "Amani Sharptalon",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 257152,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Zul'Aman / Amani rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_hexed_vilefeather_eagle",
        label           = "Hexed Vilefeather Eagle",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 257444,
        max             = 1,
        reset           = "none",
        defaultNote     = "Loot the Abandoned Ritual Skull in Zul'Aman (Maisara Deeps) for 1000 Vile Essence. Weekly farm of Essence; default goal 100. Completes at your goal or when you learn the mount.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_RITUAL_SKULL, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_currency_voidlight_marl",
        label           = "Voidlight Marl",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_currency",
        type            = "collectable_owned",
        collectableKind = "currency",
        currencyId      = 3316,
        max             = 1,
        reset           = "none",
        defaultNote     = "Midnight vendor currency from all zones. Weekly account-wide earned target (default 10000).",
    },
    {
        id              = "col_currency_remnant_of_anguish",
        label           = "Remnant of Anguish",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_currency",
        type            = "collectable_owned",
        collectableKind = "currency",
        currencyId      = 3392,
        max             = 1,
        reset           = "none",
        defaultNote     = "Prey currency from hunts. Spend it at Construct V'anore in Astalor's Sanctum. Weekly account-wide earned target (default 1000).",
    },
    {
        id              = "col_mount_sanguine_harrower",
        label           = "Sanguine Harrower",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 260635,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Voidstorm rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_augmented_stormray",
        label           = "Augmented Stormray",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 257085,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Voidstorm rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_duskbrute_harrower",
        label           = "Duskbrute Harrower",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 257176,
        max             = 1,
        reset           = "none",
        defaultNote     = "Chance from a Slayer's Duellum Trove, the paragon chest after Exalted. Completes when you learn the mount.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_THRAXADAR, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_pet_nova",
        label           = "Nova",
        expansion       = "midnight",
        subsection      = "patch_12_0_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 264892,
        max             = 1,
        reset           = "none",
        defaultNote     = "Chance from a Slayer's Duellum Trove, the paragon chest after Exalted. Completes when you have the pet.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_THRAXADAR, icon = WAY_ICON, pinned = true },
        },
    },

    -- ── Patch 12.1.0 → Collections (owned = complete; 12.0 catalog farms unchanged) ───
    {
        id              = "col_toy_ancient_amani_mask",
        label           = "Ancient Amani Mask",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_toys",
        type            = "collectable_owned",
        collectableKind = "toy",
        itemId          = 279052,
        max             = 1,
        reset           = "none",
        defaultNote     = "Toy from the Sunken Diver's Chest on the Coiled Isle (Diver's Key fragments from Glittering Grouper Brinetail).",
        defaultCommandButtons = {
            { label = "Way", command = "/way #2512 65.41 5.64 Ancient Amani Mask", icon = WAY_ICON, pinned = true },
        },
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Achievement task (see DB collectionFarmId).
    {
        id              = "col_toy_cursed_badge",
        label           = "Cursed Badge of the Soulcoilers",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_toys",
        type            = "collectable_owned",
        collectableKind = "toy",
        itemId          = 280419,
        achievementId   = 63662,
        max             = 1,
        reset           = "none",
        defaultNote     = "Student of Hissstory: find the 10 lore objects in the Vaults of Atal'Utek. Uses the in-game achievement bar. Completes when the achievement or the toy is done.",
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Collectable task (see DB collectionFarmId).
    {
        id              = "col_toy_preyhunters_masquerade",
        label           = "Preyhunter's Masquerade",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_toys",
        type            = "collectable_owned",
        collectableKind = "toy",
        itemId          = 276207,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Ral'kala. Offer Ossified Relics at a Haunted Brazier (100 to summon, at least 1 for loot). Each kill +1; no weekly lockout. Completes at your goal or when the toy is in your collection.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_ASTALOR, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_toy_idol_ulatek",
        label           = "Idol of Ula'tek",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_toys",
        type            = "collectable_owned",
        collectableKind = "toy",
        itemId          = 276925,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from Jan'sari the Watchful on the Coiled Isle for 4000 Voidlight Marl at Renown 13 with Zul'jarra's Forces.",
        purchaseReqs    = { reqRenown(13), reqCurrency(CUR_MARL, 4000) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
        },
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Collectable task (see DB collectionFarmId).
    {
        id              = "col_mount_ruby_writhe",
        label           = "Ruby Writhe",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 276803,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Coiled Isle rares and Cursed Surge bosses. Each qualifying kill +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    {
        id              = "col_mount_topaz_skyfang",
        label           = "Topaz Skyfang",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 276549,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Coiled Isle rares and Cursed Surge bosses. Each qualifying kill +1; weekly account-wide. Completes at your goal or when you learn the mount.",
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Collectable task (see DB collectionFarmId).
    {
        id              = "col_mount_hexflame_reaver",
        label           = "Hexflame Reaver",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 275659,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Ral'kala. Offer Ossified Relics at a Haunted Brazier (100 to summon, at least 1 for loot). Each kill +1; no weekly lockout. Completes at your goal or when you learn the mount.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_ASTALOR, icon = WAY_ICON, pinned = true },
        },
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Achievement task (see DB collectionFarmId).
    {
        id              = "col_mount_emerald_skyfang",
        label           = "Emerald Skyfang",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 276553,
        achievementId   = 63653,
        max             = 1,
        reset           = "none",
        defaultNote     = "Pro Poison Patroller: Temple Patrols in the Vaults of Atal'Utek. Weekly account-wide goal (default 10). The second line is the in-game bar, out of 250. Completes when the achievement or the mount is done.",
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Achievement task (see DB collectionFarmId).
    {
        id              = "col_mount_venomous_coiler",
        label           = "Venomous Coiler",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 276801,
        achievementId   = 63630,
        max             = 1,
        reset           = "none",
        defaultNote     = "Earn the Assault the Vault meta-achievement in the Vaults of Atal'Utek (10 criteria). Uses the in-game achievement bar. Completes when the achievement or the mount is done.",
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Achievement task (see DB collectionFarmId).
    {
        id              = "col_mount_auriferous_venomfang",
        label           = "Auriferous Venomfang",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 275656,
        achievementId   = 63359,
        max             = 1,
        reset           = "none",
        defaultNote     = "Treasures of Atal'Utek: loot the 22 treasures in the Vaults of Atal'Utek. Uses the in-game achievement bar. Completes when the achievement or the mount is done.",
    },
    {
        id              = "col_mount_sea_dwelling_isle_serpent",
        label           = "Sea-Dwelling Isle Serpent",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 275653,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from Second Mate Sluggs on the Coiled Isle for 2500 Coiled Filament at Captain Tokka Bloodsworn Crew.",
        purchaseReqs    = { reqFriendship(5, "Bloodsworn Crew"), reqCurrency(CUR_FILAMENT, 2500) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_SLUGGS, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_mount_caustic_venomfang",
        label           = "Caustic Venomfang",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 275654,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from the Skull of Er'inye in the Vaults of Atal'Utek for 10000 Corrosive Coins.",
        purchaseReqs    = { reqCurrency(CUR_COIN, 10000) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_ERINYE, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_mount_indigo_coiled_horror",
        label           = "Indigo Coiled Horror",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 276802,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from Jan'sari the Watchful on the Coiled Isle for 6000 Voidlight Marl at Renown 17 with Zul'jarra's Forces.",
        purchaseReqs    = { reqRenown(17), reqCurrency(CUR_MARL, 6000) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_mount_violet_backed_skyfang",
        label           = "Violet-Backed Skyfang",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 276551,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from Jan'sari the Watchful on the Coiled Isle for 8000 Voidlight Marl at Renown 19 with Zul'jarra's Forces.",
        purchaseReqs    = { reqRenown(19), reqCurrency(CUR_MARL, 8000) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_mount_spirit_tokjara",
        label           = "Spirit of Tok'jara",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_mounts",
        type            = "collectable_owned",
        collectableKind = "mount",
        itemId          = 273838,
        max             = 1,
        reset           = "none",
        -- Last one-time chain quest (The Innocent Essence) teaches the mount.
        quests          = { [96305] = true },
        purchaseReqs    = { reqRenown(10) },
        defaultNote     = "Du'gal at the Amani Foothold: Renown 10 with Zul'jarra's Forces starts his six-day Spirit of Tok'jara chain. The last quest, The Innocent Essence, teaches the mount. After you learn it, Du'gal offers rotating dailies.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_DUGAL, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_pet_corrosive_writhling",
        label           = "Corrosive Writhling",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 275631,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from the Skull of Er'inye in the Vaults of Atal'Utek for 5000 Corrosive Coins.",
        purchaseReqs    = { reqCurrency(CUR_COIN, 5000) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_ERINYE, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_pet_volatile_venomfang",
        label           = "Volatile Venomfang",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 275632,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from the Skull of Er'inye in the Vaults of Atal'Utek for 5000 Corrosive Coins.",
        purchaseReqs    = { reqCurrency(CUR_COIN, 5000) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_ERINYE, icon = WAY_ICON, pinned = true },
        },
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Achievement task (see DB collectionFarmId).
    {
        id              = "col_pet_wild_caught",
        label           = "The Coiled Isle Safari",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        achievementId   = 62492,
        max             = 1,
        reset           = "none",
        defaultNote     = "The Coiled Isle Safari: catch all 8 wild pets (Poisoned Parasite, Cursed Spawn, Steady Croakfrog, Sleek Snakebiter, Nightfur Kapara, Jaundiced Slitherer, Caustic Writhling, Autumn Snapling). Uses the in-game achievement bar. Awards Zesty.",
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Achievement task (see DB collectionFarmId).
    {
        id              = "col_pet_kiclak",
        label           = "Ki'clak",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 279921,
        achievementId   = 63633,
        max             = 1,
        reset           = "none",
        defaultNote     = "A Stack of Snacks: finish Don't Be Afrayed, then complete Olawu's world quest. Weekly account-wide goal (default 2). The second line is the in-game bar, out of 5. Completes when the achievement or the pet is done.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_OLAWU, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_pet_snekzali",
        label           = "Snek'zali",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 276248,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from Jan'sari the Watchful on the Coiled Isle for 2500 Voidlight Marl at Renown 12 with Zul'jarra's Forces.",
        purchaseReqs    = { reqRenown(12), reqCurrency(CUR_MARL, 2500) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_pet_venom_elemental",
        label           = "Venom Elemental",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 275020,
        max             = 1,
        reset           = "none",
        defaultNote     = "Buy from Second Mate Sluggs on the Coiled Isle at Venom Trawler with Captain Tokka (100 gold).",
        purchaseReqs    = { reqFriendship(4, "Venom Trawler"), reqGold(100) },
        defaultCommandButtons = {
            { label = "Way", command = WAY_SLUGGS, icon = WAY_ICON, pinned = true },
        },
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Kill task (see DB collectionFarmId).
    {
        id              = "col_pet_lil_mon",
        label           = "Lil' Mon",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        max             = 1,
        reset           = "none",
        defaultNote     = "Kill Big Mon on the Coiled Isle. Daily account-wide, one kill. The second line uses the Rarity drop rate when Rarity has that pet. Otherwise it shows your total kills.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_BIG_MON, icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_pet_cauldron_concoction",
        label           = "Cauldron Concoction",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 280189,
        max             = 1,
        reset           = "none",
        defaultNote     = "Chance from Ofi's Mixing Mysteries offerings after unlocking her cauldron (Renown 3 with Zul'jarra's Forces).",
    },
    {
        id              = "col_pet_zan",
        label           = "Zan",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 268644,
        max             = 1,
        reset           = "none",
        quests          = { [93393] = true },
        defaultNote     = "Reward from A Little Kindness (Strange Friends in Odd Places). Starts at Ofi the Sly with Dealing with Pests. Completes when the quest is done or you have the companion pet.",
        defaultCommandButtons = {
            { label = "Way", command = "/way #2512 61.00 33.00 Ofi the Sly", icon = WAY_ICON, pinned = true },
        },
    },
    {
        id              = "col_pet_three_eyed_fish",
        label           = "Three-Eyed Fish",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 279483,
        max             = 1,
        reset           = "none",
        quests          = { [97565] = true },
        defaultNote     = "Venom Trawler is rank 4 of 5 with Captain Tokka. After that, buy an Eerie Bauble for 250 Voidlight and use it on a fishing pool to fish up a Star Ooze. That starts a quest chain of 3 quests, ending with Tipping the Scaled.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_TOKKA, icon = WAY_ICON, pinned = true },
        },
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Collectable task (see DB collectionFarmId).
    {
        id              = "col_pet_poison_dart_frog",
        label           = "Poison Dart Frog",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 280178,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare from Unfortunate Scout's Satchels on the Coiled Isle (Renown 9 with Zul'jarra's Forces). Each satchel +1; weekly account-wide. Completes at your goal or when you have the pet.",
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced Collectable task (see DB collectionFarmId).
    {
        id              = "col_pet_pale_hexscale",
        label           = "Pale Hexscale",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_pets",
        type            = "collectable_owned",
        collectableKind = "pet",
        itemId          = 278572,
        max             = 1,
        reset           = "none",
        defaultNote     = "Rare drop from Ral'kala. Offer Ossified Relics at a Haunted Brazier (100 to summon, at least 1 for loot). Each kill +1; no weekly lockout. Completes at your goal or when you have the pet.",
        defaultCommandButtons = {
            { label = "Way", command = WAY_ASTALOR, icon = WAY_ICON, pinned = true },
        },
    },
    -- Options Modules labels + toggles; the list row is a seeded advanced currency task (see DB collectionFarmId).
    {
        id              = "col_currency_corrosive_coins",
        label           = "Corrosive Coins",
        expansion       = "midnight",
        subsection      = "patch_12_1_0_collections_currency",
        type            = "collectable_owned",
        collectableKind = "currency",
        currencyId      = 3448,
        max             = 1,
        reset           = "none",
        defaultNote     = "Currency from the Altar of Corrosion in the Vaults of Atal'Utek. Weekly account-wide earned target (default 20000).",
    },
    {
        id          = "col_rep_zuljarras_forces",
        label       = "Zul'jarra's Forces",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_collections_reputations",
        type        = "reputation_standing",
        factionId   = 2772,
        repKind     = "renown",
        warband     = true,
        max         = 20,
        weeklyGain  = 2000,
        reset       = "none",
        defaultNote = "Coiled Isle Renown with Zul'jarra's Forces (Warband). Weekly account-wide goal (default 2000). Do isle rares, surges, and vaults to rank up.",
    },
    {
        id          = "col_rep_captain_tokka",
        label       = "Captain Tokka",
        expansion   = "midnight",
        subsection  = "patch_12_1_0_collections_reputations",
        type        = "reputation_standing",
        factionId   = 2773,
        repKind     = "friendship",
        warband     = true,
        max         = 5,
        reset       = "none",
        defaultNote = "Coiled Isle fishing friendship with Captain Tokka. Fish and turn in Coiled Filament at Tokka's Landing. Complete at Bloodsworn Crew (rank 5).",
    },
    {
        id           = "col_rep_delvers_journey",
        label        = "Delver's Journey",
        expansion    = "midnight",
        subsection   = "patch_12_1_0_collections_reputations",
        listZone     = "midnight",
        type         = "reputation_standing",
        factionId    = 2796,
        repKind      = "renown",
        renownSubtext = true,
        warband      = true,
        max          = 10,
        weeklyGain   = 4200,
        reset        = "weekly",
        defaultNote  = "Weekly Delver's Journey, the one you check with Valeera. The goal starts at 4200, one rank. The second line shows your Renown.",
    },

    -- ── Patch 12.1.5 ───────────────────────────────────────────────
    {
        id           = "p1215_labyrinth_renown",
        label        = "The Labyrinth of Kindo'jan",
        expansion    = "midnight",
        subsection   = "patch_12_1_5_collections_reputations",
        listZone     = "midnight",
        type         = "reputation_standing",
        factionId    = 2836,
        repKind      = "renown",
        renownSubtext = true,
        warband      = true,
        max          = 9,
        weeklyGain   = 2100,
        reset        = "weekly",
        defaultNote  = "Weekly Renown for the Labyrinth of Kindo'jan. The goal starts at 2100. The second line shows your Renown.",
    },
    {
        id            = "p1215_aqir_satchel",
        label         = "Aqir Research Satchel",
        expansion     = "midnight",
        subsection    = "patch_12_1_5_aqir",
        listZone      = "midnight",
        type          = "quest_count",
        max           = 1,
        reset         = "weekly",
        quests        = {},
        trackItemId   = 277283,
        trackItemLatch = true,
        defaultNote   = "Loot the Aqir Research Satchel from the first Aqir Monstrosity you kill this week. Power treats it as Champion 2 gear, item level 295. After that, it keeps Champion Mistcrest until 309.",
    },
    {
        id           = "p1215_aqir_enclave",
        label        = "Aqir Research Enclave",
        expansion    = "midnight",
        subsection   = "patch_12_1_5_collections_reputations",
        listZone     = "midnight",
        type         = "reputation_standing",
        factionId    = 2838,
        repKind      = "friendship",
        standingSubtext = true,
        warband      = true,
        max          = 5000,
        reset        = "none",
        defaultNote  = "Friendship with the Aqir Research Enclave. Neutral through Exalted. The row finishes at 5000. The second line shows your rank.",
    },

    -- ── Seasonal Activities → Dungeons (manual 0/1; mirror under Power) ───
    {
        id                  = "seasonal_dungeon_normal",
        label               = "Normal dungeons",
        expansion           = "seasonal",
        subsection          = "mplus",
        type                = "mplus_hint_row",
        max                 = 1,
        manualOnly          = true,
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Season 2 normal dungeons drop item level 253. After that, Power keeps Adventurer Mistcrest until 282. Check it off yourself. It is not auto-completed. Power shows it from level 80.",
    },
    {
        id                  = "seasonal_dungeon_heroic",
        label               = "Heroic dungeons",
        expansion           = "seasonal",
        subsection          = "mplus",
        type                = "mplus_hint_row",
        max                 = 1,
        manualOnly          = true,
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Season 2 heroic dungeons drop item level 276. After that, Power keeps Adventurer Mistcrest until 282. Check it off yourself. It is not auto-completed. Power shows it from level 90.",
    },
    -- ── Seasonal Activities → Raids (Venomous Abyss; boss kills and vault slots; mirror under Power) ───
    -- raidDifficulty: 14 Normal, 15 Heroic, 16 Mythic. raidBossCount is the fallback until a lockout reports the real total.
    {
        id                  = "seasonal_raid_normal",
        label               = "Normal raid",
        expansion           = "seasonal",
        subsection          = "raid",
        type                = "quest_count",
        max                 = 8,
        raidTrack           = "bosses",
        raidDifficulty      = 14,
        raidBossCount       = 8,
        raidInstanceName    = "Venomous Abyss",
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Bosses killed on Normal this week. Finishes when the raid is clear. Drops item level 292 to 302. After that, Power keeps Champion Mistcrest until 309.",
    },
    {
        id                  = "seasonal_raid_heroic",
        label               = "Heroic raid",
        expansion           = "seasonal",
        subsection          = "raid",
        type                = "quest_count",
        max                 = 8,
        raidTrack           = "bosses",
        raidDifficulty      = 15,
        raidBossCount       = 8,
        raidInstanceName    = "Venomous Abyss",
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Bosses killed on Heroic this week. Finishes when the raid is clear. Drops item level 305 to 315. After that, Power keeps Hero Mistcrest until 322.",
    },
    {
        id                  = "seasonal_raid_mythic",
        label               = "Mythic raid",
        expansion           = "seasonal",
        subsection          = "raid",
        type                = "quest_count",
        max                 = 8,
        raidTrack           = "bosses",
        raidDifficulty      = 16,
        raidBossCount       = 8,
        raidInstanceName    = "Venomous Abyss",
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Bosses killed on Mythic this week. Finishes when the raid is clear. Drops item level 318 to 344. The last two bosses are 344. Myth Mistcrest stops at 334, so the gear line stays the one Power uses.",
    },
    {
        id                  = "seasonal_raid_vault_normal",
        label               = "Normal vault",
        expansion           = "seasonal",
        subsection          = "raid",
        type                = "quest_count",
        max                 = 3,
        raidTrack           = "vault",
        raidDifficulty      = 14,
        raidInstanceName    = "Venomous Abyss",
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Great Vault slots from Normal bosses. Finishes when the vault is full (6 bosses). The choice is item level 305. After that, Power keeps Champion Mistcrest until 309.",
    },
    {
        id                  = "seasonal_raid_vault_heroic",
        label               = "Heroic vault",
        expansion           = "seasonal",
        subsection          = "raid",
        type                = "quest_count",
        max                 = 3,
        raidTrack           = "vault",
        raidDifficulty      = 15,
        raidInstanceName    = "Venomous Abyss",
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Great Vault slots from Heroic bosses. Finishes when the vault is full (6 bosses). The choice is item level 318. After that, Power keeps Hero Mistcrest until 322.",
    },
    {
        id                  = "seasonal_raid_vault_mythic",
        label               = "Mythic vault",
        expansion           = "seasonal",
        subsection          = "raid",
        type                = "quest_count",
        max                 = 3,
        raidTrack           = "vault",
        raidDifficulty      = 16,
        raidInstanceName    = "Venomous Abyss",
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Great Vault slots from Mythic bosses. Finishes when the vault is full (6 bosses). Choices are item level 334 to 344. The 344 choice is the last two bosses. Myth Mistcrest stops at 334.",
    },
    {
        id                  = "seasonal_mplus_hint_end",
        label               = "Mythic + EOD",
        expansion           = "seasonal",
        subsection          = "mplus",
        type                = "mplus_hint_row",
        mplusHintKind       = "end_dungeon",
        max                 = 1,
        manualOnly          = true,
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Hint for this week's end-of-dungeon Mythic+ upgrade. Run the key level shown in the subtitle. Check it off yourself; it is not auto-completed.",
    },
    {
        id                  = "seasonal_mplus_hint_vault",
        label               = "Mythic+ Great Vault",
        expansion           = "seasonal",
        subsection          = "mplus",
        type                = "mplus_hint_row",
        mplusHintKind       = "vault",
        max                 = 1,
        manualOnly          = true,
        reset               = "weekly",
        quests              = {},
        defaultNote         = "Hint for this week's dungeon Great Vault upgrade versus your lowest equipped item (or the Details ilvl). Run the key level shown in the subtitle. Check it off yourself; it is not auto-completed.",
    },
    -- Spark Quest: any one of the listed weeklies completes the row (weekly quest-delta when >1 id).
    {
        id          = "s1_ritual_sites",
        label       = "Spark Quest",
        expansion   = "seasonal",
        subsection  = "general",
        type        = "quest_complete",
        max         = 1,
        reset       = "weekly",
        quests      = {
            [93890] = true, [93767] = true, [94457] = true, [93909] = true, [93911] = true, [93769] = true,
            [93910] = true, [93912] = true, [93889] = true, [93892] = true, [93913] = true, [93766] = true,
            [95843] = true,
        },
        defaultNote = "Complete any Midnight spark weekly (rotating ritual sites / world quests). Any one of the listed weeklies fills this row.",
    },

    -- ── Seasonal Activities (Delves + Great Vault) ─────────────────
    -- Gilded: widgetId 7591 — status bar or spell tooltip (e.g. "1/4" stash looted).
    {
        id          = "seasonal_delves_gilded",
        label       = "Gilded Stashes (4/week)",
        expansion   = "seasonal",
        subsection  = "delves",
        type        = "quest_count",
        max         = 4,
        reset       = "weekly",
        widgetId    = 7591,
        quests      = {},
        defaultNote = "Loot four Gilded Stashes in Delves each week. Progress comes from the Delves UI (the 4/week bar).",
    },
    {
        id          = "seasonal_delves_bounty",
        label       = "Trovehunter's Bounty",
        expansion   = "seasonal",
        subsection  = "delves",
        type        = "quest_count",
        max         = 1,
        reset       = "weekly",
        quests      = {},
        trackItemId = 274374,
        itemAbsentMeansUsed = true,
        defaultNote = "Use your Trovehunter's Bounty in a delve this week. Each character tracks their own map. Completes after you had the item and it is gone.",
    },
    -- Scalebound Herald's Flute summon inside a normal delve. AllTheThings: object 656489
    -- (Azta'rec Cache) costs item 275910 and isWeekly quest 92887. Wowhead names 275910
    -- Scalebound Herald's Flute (5000 Undercoin, spell 1298210).
    -- Last season's pair is object 618495 / Beacon of Hope item 253342, same quest, group u=2.
    -- Not Venomfall Deeps, and not Torment's Rise: n(252892) quest 96416 and n(252101) quest 96417.
    -- Not 93525 (one-time intro). Not 86371 (Trovehunter's Bounty map item 274374).
    {
        id          = "seasonal_delves_nullaeus",
        label       = "Azta'rec summoned (weekly)",
        expansion   = "seasonal",
        subsection  = "delves",
        type        = "quest_complete",
        max         = 1,
        reset       = "weekly",
        quests      = { [92887] = true },
        defaultNote = "Use a Scalebound Herald's Flute at the checkpoint in a delve, then loot the cache he leaves. Once a week. His own delve, Venomfall Deeps, does not check this off. Left/right-click to override.",
    },
    {
        id           = "seasonal_vault_raid",
        label        = "Raid",
        expansion    = "seasonal",
        subsection   = "vault",
        type         = "vault_row",
        vaultKind    = "raid",
        reset        = "weekly",
        quests       = {},
        defaultNote  = "Shows this week's Great Vault raid slot. Fill it by raiding; this row is status, not a separate checklist.",
    },
    {
        id           = "seasonal_vault_dungeon",
        label        = "Dungeon",
        expansion    = "seasonal",
        subsection   = "vault",
        type         = "vault_row",
        vaultKind    = "dungeon",
        reset        = "weekly",
        quests       = {},
        defaultNote  = "Shows this week's Great Vault dungeon slot. Fill it with Mythic+ (or Heroic/Mythic dungeons). This row is status, not a separate checklist.",
    },
    {
        id           = "seasonal_vault_world",
        label        = "World",
        expansion    = "seasonal",
        subsection   = "vault",
        type         = "vault_row",
        vaultKind    = "world",
        reset        = "weekly",
        quests       = {},
        defaultNote  = "Shows this week's Great Vault world slot. Fill it with world activities (delves, weeklies, and the like). This row is status, not a separate checklist.",
    },
}

if TaskTracker.BuildProfessionRegistryEntries then
    for _, profEntry in ipairs(TaskTracker.BuildProfessionRegistryEntries()) do
        TaskTracker.Registry[#TaskTracker.Registry + 1] = profEntry
    end
end

-- ─────────────────────────────────────
-- Quick lookup: questID -> { entries } (a quest id can appear on more than one row)
-- Built automatically, do not edit
-- ─────────────────────────────────────
TaskTracker.QuestToEntry = {}
for _, entry in ipairs(TaskTracker.Registry) do
    local n = 0
    local ids
    if entry.quests then
        ids = {}
        for qid in pairs(entry.quests) do
            n = n + 1
            ids[n] = qid
            local list = TaskTracker.QuestToEntry[qid]
            if not list then
                list = {}
                TaskTracker.QuestToEntry[qid] = list
            end
            list[#list + 1] = entry
        end
    end
    entry._ttQuestCount = n
    entry._ttQuestIds = ids
end

-- NPC / encounter / cache loot → registry rows (e.g. weekly Nullaeus)
TaskTracker.NpcToRegistry = {}
TaskTracker.EncounterNameToRegistry = {}
TaskTracker.LootObjectToRegistry = {}
for _, entry in ipairs(TaskTracker.Registry) do
    if entry.trackNpcIds then
        for i = 1, #entry.trackNpcIds do
            local nid = tonumber(entry.trackNpcIds[i])
            if nid then
                local list = TaskTracker.NpcToRegistry[nid]
                if not list then
                    list = {}
                    TaskTracker.NpcToRegistry[nid] = list
                end
                list[#list + 1] = entry
            end
        end
    end
    if type(entry.trackEncounterName) == "string" and entry.trackEncounterName ~= "" then
        local key = string.lower(entry.trackEncounterName)
        local list = TaskTracker.EncounterNameToRegistry[key]
        if not list then
            list = {}
            TaskTracker.EncounterNameToRegistry[key] = list
        end
        list[#list + 1] = entry
    end
    if entry.trackLootObjectIds then
        for i = 1, #entry.trackLootObjectIds do
            local oid = tonumber(entry.trackLootObjectIds[i])
            if oid then
                local list = TaskTracker.LootObjectToRegistry[oid]
                if not list then
                    list = {}
                    TaskTracker.LootObjectToRegistry[oid] = list
                end
                list[#list + 1] = entry
            end
        end
    end
end

-- ─────────────────────────────────────
-- Quick lookup: entryID -> entry
-- Built automatically, do not edit
-- ─────────────────────────────────────
TaskTracker.RegistryByID = {}

-- Applied onto Registry rows (listZone may also be set on the entry itself).
local REGISTRY_LIST_ZONE = {
    prey_normal                 = "midnight",
    prey_hard                   = "midnight",
    prey_nightmare              = "midnight",
    prey_nightmarish            = "midnight",
    s1_halduron_weekly          = "midnight",
    s1_fortify_runestones       = "quelthalas",
    s1_stormarion_assault_wq    = "voidstorm",
    s1_lost_legends             = "harandar",
    s1_special_assignments      = "midnight",
    s1_void_assaults            = "midnight",
    s1_cursed_surges            = "coiled_isle",
    s1_open_sea_fishing         = "coiled_isle",
    s1_brinedrinker_gills       = "coiled_isle",
    s1_second_mate_sluggs       = "coiled_isle",
    s1_ethrandil                = "coiled_isle",
    s1_purging_the_vaults       = "vaults",
    s1_hawkeye_soho             = "vaults",
    s1_from_whence_it_came      = "vaults",
    s1_dugal                    = "vaults",
    col_toy_ancient_amani_mask      = "coiled_isle",
    col_toy_preyhunters_masquerade  = "coiled_isle",
    col_toy_idol_ulatek             = "coiled_isle",
    col_toy_cursed_badge            = "vaults",
    col_mount_rootstalker_grimlynx  = "harandar",
    col_mount_vibrant_petalwing     = "harandar",
    col_mount_cerulean_hawkstrider  = "quelthalas",
    col_mount_cobalt_dragonhawk     = "quelthalas",
    col_mount_escaped_witherbark_pango = "zulaman",
    col_mount_amani_sharptalon      = "zulaman",
    col_mount_hexed_vilefeather_eagle = "zulaman",
    col_mount_sanguine_harrower     = "voidstorm",
    col_mount_augmented_stormray    = "voidstorm",
    col_mount_ruby_writhe           = "coiled_isle",
    col_mount_topaz_skyfang         = "coiled_isle",
    col_mount_hexflame_reaver       = "coiled_isle",
    col_mount_sea_dwelling_isle_serpent = "coiled_isle",
    col_mount_indigo_coiled_horror  = "coiled_isle",
    col_mount_violet_backed_skyfang = "coiled_isle",
    col_mount_emerald_skyfang       = "vaults",
    col_mount_venomous_coiler       = "vaults",
    col_mount_auriferous_venomfang  = "vaults",
    col_mount_caustic_venomfang     = "vaults",
    col_mount_spirit_tokjara        = "vaults",
    col_pet_wild_caught             = "coiled_isle",
    col_pet_kiclak                  = "coiled_isle",
    col_pet_snekzali                = "coiled_isle",
    col_pet_venom_elemental         = "coiled_isle",
    col_pet_lil_mon                 = "coiled_isle",
    col_pet_cauldron_concoction     = "coiled_isle",
    col_pet_zan                     = "coiled_isle",
    col_pet_three_eyed_fish         = "coiled_isle",
    col_pet_poison_dart_frog        = "coiled_isle",
    col_pet_pale_hexscale           = "coiled_isle",
    col_pet_corrosive_writhling     = "vaults",
    col_pet_volatile_venomfang      = "vaults",
    col_currency_voidlight_marl     = "midnight",
    col_currency_remnant_of_anguish = "midnight",
    col_currency_corrosive_coins    = "vaults",
    col_rep_zuljarras_forces        = "coiled_isle",
    col_rep_captain_tokka           = "coiled_isle",
    col_mount_duskbrute_harrower    = "voidstorm",
    col_pet_nova                    = "voidstorm",
}

for _, entry in ipairs(TaskTracker.Registry) do
    TaskTracker.RegistryByID[entry.id] = entry
    if not entry.listZone and REGISTRY_LIST_ZONE[entry.id] then
        entry.listZone = REGISTRY_LIST_ZONE[entry.id]
    end
end

function TaskTracker.GetCollectionCategoryKey(subsection)
    if type(subsection) ~= "string" then return nil end
    return subsection:match("_collections_(%w+)$")
end

function TaskTracker.GetMidnightPatchKeyFromSubsection(sub)
    if type(sub) ~= "string" then return nil end
    if sub:find("patch_12_1_5", 1, true) then return "patch_12_1_5" end
    if sub:find("patch_12_1_0", 1, true) then return "patch_12_1_0" end
    if sub:find("patch_12_0_5", 1, true) then return "patch_12_0_5" end
    if sub:find("patch_12_0_0", 1, true) then return "patch_12_0_0" end
    return nil
end

function TaskTracker.GetRegistryListZone(entryOrId)
    local entry = entryOrId
    if type(entryOrId) == "string" then
        entry = TaskTracker.RegistryByID and TaskTracker.RegistryByID[entryOrId]
    end
    return entry and entry.listZone or nil
end

-- ─────────────────────────────────────
-- Get all entries for a given expansion
-- Used by options panel
-- ─────────────────────────────────────
function TaskTracker.GetEntriesForExpansion(expansion)
    if expansion == "power" then
        return TaskTracker.GetEntriesForPowerModule()
    end
    local entries = {}
    for _, entry in ipairs(TaskTracker.Registry) do
        if entry.expansion == expansion then
            if TaskTracker.IsRegistryRequireOwnedLocked
                and TaskTracker.IsRegistryRequireOwnedLocked(entry) then
                -- Hidden until the named collectable is owned (e.g. Du'gal dailies).
            elseif expansion == "professions" and TaskTracker.ProfessionRegistryEntryVisible then
                if TaskTracker.ProfessionRegistryEntryVisible(entry) then
                    table.insert(entries, entry)
                end
            else
                table.insert(entries, entry)
            end
        end
    end
    return entries
end

-- Stable ids for built-in module groups (rename-safe; custom groups must not carry these keys).
TaskTracker.MODULE_GROUP_KEYS = {
    power                 = true,
    patch_12_0_0          = true,
    patch_12_0_5          = true,
    patch_12_1_5          = true,
    patch_12_1_5_aqir                 = true,
    patch_12_1_5_collections          = true,
    patch_12_1_5_collections_reputations = true,
    patch_12_1_0          = true,
    patch_12_0_0_collections              = true,
    patch_12_0_0_collections_mounts       = true,
    patch_12_0_0_collections_currency     = true,
    patch_12_0_0_collections_pets         = true,
    patch_12_1_0_coiled_isle              = true,
    patch_12_1_0_vaults                   = true,
    patch_12_1_0_collections              = true,
    patch_12_1_0_collections_toys         = true,
    patch_12_1_0_collections_mounts       = true,
    patch_12_1_0_collections_pets         = true,
    patch_12_1_0_collections_currency     = true,
    patch_12_1_0_collections_reputations  = true,
    seasonal_activities   = true,
    seasonal_general      = true,
    seasonal_delves       = true,
    seasonal_vault        = true,
    seasonal_mplus        = true,
    seasonal_raid         = true,
    professions           = true,
    mplus_hints           = true,
}

function TaskTracker.IsKnownModuleGroupKey(key)
    if not key or type(key) ~= "string" then return false end
    if TaskTracker.MODULE_GROUP_KEYS[key] then return true end
    return key:match("^profession_") ~= nil
end

-- Tree groups that cannot be deleted (use Modules to hide/disable)
function TaskTracker.IsProtectedModuleGroup(node)
    if not node or node.type ~= "group" then return false end
    if node.isPatchListView then return true end
    return TaskTracker.IsKnownModuleGroupKey(node.moduleGroupKey)
end

--- Official module sections (Midnight, Seasonal, Professions, and the groups under them)
--- do not take new tasks. A group the player made still does.
function TaskTracker.ModuleSectionBlocksNewTask(node)
    if not node or node.type ~= "group" then return false end
    if node.generatedSection then return true end
    return TaskTracker.IsProtectedModuleGroup(node) and true or false
end

--- True when this task cannot be dropped into dest. A shared task can sit
--- wherever the player puts it. A row already in that section can be reordered there.
function TaskTracker.TaskMoveIntoSectionBlocked(node, dest)
    if not node or node.type ~= "task" then return false end
    if not dest or not TaskTracker.ModuleSectionBlocksNewTask(dest) then return false end
    if node.liveShareRole == "receiver" or node.liveShareRole == "owner" then return false end
    if node.id and dest.id and TaskTracker.FindNode then
        local _, parent = TaskTracker.FindNode(node.id)
        if parent and parent.id == dest.id then return false end
    end
    return true
end

function TaskTracker.IsPowerModuleGroup(node)
    return node and node.type == "group" and node.moduleGroupKey == "power"
end