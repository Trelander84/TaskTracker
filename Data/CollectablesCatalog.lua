-- Data/CollectablesCatalog.lua
-- Built-in collectable definitions (expansion + category + entry) for advanced Collectable tasks.
-- Optional fields: patch (e.g. "12.0.0"), farm (attempt counter), defaultGoal, defaultReset,
-- defaultNote, npcIds, lootObjectIds, farmItemId (bag-item earned count for the farm),
-- defaultCommandButtons ({ label, command, icon?, pinned? }).

TaskTracker = TaskTracker or {}

local AMANI_MASK_WAY = "/way #2512 65.41 5.64 Ancient Amani Mask"
local WAY_JANSARI = "/way #2512 58.80 46.00 Jan'sari the Watchful"
local WAY_SLUGGS = "/way #2512 51.60 49.80 Second Mate Sluggs"
local WAY_ERINYE = "/way #2509 51.20 62.40 Skull of Er'inye"
local WAY_DUGAL = "/way #2509 50.48 63.86 Du'gal"
local WAY_BIG_MON = "/way #2512 70.00 63.50 Big Mon"
local WAY_OLAWU = "/way #2512 58.50 47.20 Olawu"
local WAY_ASTALOR = "/way #2512 58.21 48.72 Image of Astalor"
local WAY_RITUAL_SKULL = "/way #2437 44.72 44.10 Abandoned Ritual Skull"
local WAY_ICON = TaskTracker.WAY_COMMAND_ATLAS or "TaxiNode_Neutral"

--- Ral'kala (Prey summon at Haunted Braziers). Hexflame Reaver / Pale Hexscale / Preyhunter's Masquerade.
local RALKALA_NPCS = { 258928 }

--- Coiled Isle rares (Coiled to Strike) + Cursed Surge bosses — both mounts drop from this set.
local MIDNIGHT_COILED_ISLE_RARE_NPCS = {
    264854, -- Farthik the Plunderer
    268090, -- Kari'zah the Forgotten
    265262, -- Hisstara
    258916, -- Garsecg
    257906, -- Coin-Eye Skully
    261109, -- Sss'alik
    268049, -- Siltmouth
    265237, -- Lockjaw
    263456, -- Szarith the Fanged
    258920, -- Nar'zira
    256631, -- Big Mon
    261142, -- Destra
    255088, -- Looming Mutagenitor (Cursed Surge)
    257863, -- Vassti, the Exalted Broodmother
    258254, -- Ss'akrithos
    255927, -- Venom Lancer Ori'kassi
    255087, -- Malformed Leviathan
}
local MIDNIGHT_RARE_LOOT_QUESTS = {
    91832, 92137, 92142, 92148, 92154, 92161, 92168, 92170, 92172, 92176, 92183, 92190, 92191, 92193, 92194,
}

--- Eversong Woods rare daily bonus (character) quest IDs — mounts item 257156 / 257147; not warband-wide quests.
local MIDNIGHT_EVERSONGRARE_LOOT_QUESTS = {
    92392, 91280, 91315, 92366, 92389, 92391, 92393, 92395, 92399, 92403, 92404, 92409, 93550, 93555, 93561,
}

--- Zul'Aman / Amani–Witherbark rare daily bonus (character) quest IDs — mounts item 257200 / 257152.
local MIDNIGHT_AMANI_WITHERBARK_LOOT_QUESTS = {
    89569, 89570, 89571, 89572, 89573, 89575, 89578, 89579, 89580, 89581, 89583, 91072, 91073, 91174, 91634,
}

--- Sanguine Harrower / Augmented Stormray rare daily bonus (character) quest IDs — mounts item 260635 / 257085.
local MIDNIGHT_SANGUINE_STORMRAY_LOOT_QUESTS = {
    91050, 91048, 90805, 91051, 91047, 94460, 94458, 94462, 94459, 94463, 93884, 93895, 93896, 93966, 93946, 93944,
    93947, 93934, 93953,
}

TaskTracker.CollectableCatalog = TaskTracker.CollectableCatalog or {
    tww = {
        mount = {},
        pet = {},
        toy = {},
        currency = {},
        other = {},
    },
    midnight = {
        mount = {
            {
                id = "rootstalker_grimlynx",
                label = "Rootstalker Grimlynx",
                patch = "12.0.0",
                itemId = 246735,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Harandar rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Harandar rares (Midnight). Kill eligible world rares each day; when the game marks the rare's daily bonus loot quest complete, this task gains +1 (up to your goal). Weekly account-wide. Completes when you learn the mount (item 246735).",
                questIds = MIDNIGHT_RARE_LOOT_QUESTS,
            },
            {
                id = "vibrant_petalwing",
                label = "Vibrant Petalwing",
                patch = "12.0.0",
                itemId = 252012,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Harandar rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Harandar rares (Midnight). Same daily rare bonus quests as Rootstalker Grimlynx — each rare's first completion of the day adds +1. Weekly account-wide. Completes when you learn the mount (item 252012).",
                questIds = MIDNIGHT_RARE_LOOT_QUESTS,
            },
            {
                id = "cerulean_hawkstrider",
                label = "Cerulean Hawkstrider",
                patch = "12.0.0",
                itemId = 257156,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Eversong Woods rares in Quel'Thalas. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Eversong Woods rares (Quel'Thalas). +1 per linked daily bonus quest when flagged complete on this character. Weekly account-wide. Completes when you learn the mount (item 257156).",
                questIds = MIDNIGHT_EVERSONGRARE_LOOT_QUESTS,
            },
            {
                id = "cobalt_dragonhawk",
                label = "Cobalt Dragonhawk",
                patch = "12.0.0",
                itemId = 257147,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Eversong Woods rares in Quel'Thalas. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Eversong Woods rares (Quel'Thalas). +1 per linked daily bonus quest when flagged complete on this character. Weekly account-wide. Completes when you learn the mount (item 257147).",
                questIds = MIDNIGHT_EVERSONGRARE_LOOT_QUESTS,
            },
            {
                id = "escaped_witherbark_pango",
                label = "Escaped Witherbark Pango",
                patch = "12.0.0",
                itemId = 257200,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Zul'Aman / Amani rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Zul'Aman / Amani–Witherbark route rares (Midnight). +1 per linked daily bonus quest when flagged complete on this character. Weekly account-wide. Completes when you learn the mount (item 257200).",
                questIds = MIDNIGHT_AMANI_WITHERBARK_LOOT_QUESTS,
            },
            {
                id = "amani_sharptalon",
                label = "Amani Sharptalon",
                patch = "12.0.0",
                itemId = 257152,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Zul'Aman / Amani rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Zul'Aman / Amani–Witherbark route rares (Midnight). +1 per linked daily bonus quest when flagged complete on this character. Weekly account-wide. Completes when you learn the mount (item 257152).",
                questIds = MIDNIGHT_AMANI_WITHERBARK_LOOT_QUESTS,
            },
            {
                id = "hexed_vilefeather_eagle",
                label = "Hexed Vilefeather Eagle",
                patch = "12.0.0",
                itemId = 257444,
                farm = true,
                farmItemId = 259361,
                defaultGoal = 100,
                defaultReset = "weekly",
                defaultNote = "Loot the Abandoned Ritual Skull in Zul'Aman (Maisara Deeps) for 1000 Vile Essence. Weekly farm of Essence; default goal 100. Completes at your goal or when you learn the mount.",
                howTo = "Farm Vile Essence (item 259361) from elites in Maisara Deeps, Zul'Aman. The Abandoned Ritual Skull at 44.7 44.1 costs 1000 Essence and teaches Hexed Vilefeather Eagle (item 257444). This row counts Essence gained this week (default goal 100). Completes when you learn the mount.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_RITUAL_SKULL, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "sanguine_harrower",
                label = "Sanguine Harrower",
                patch = "12.0.0",
                itemId = 260635,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Voidstorm rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Voidstorm rares (pair with Augmented Stormray). +1 per linked daily bonus quest when flagged complete on this character. Weekly account-wide. Completes when you learn the mount (item 260635).",
                questIds = MIDNIGHT_SANGUINE_STORMRAY_LOOT_QUESTS,
            },
            {
                id = "augmented_stormray",
                label = "Augmented Stormray",
                patch = "12.0.0",
                itemId = 257085,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Voidstorm rares. Each rare's daily bonus loot +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Voidstorm rares (pair with Sanguine Harrower). +1 per linked daily bonus quest when flagged complete on this character. Weekly account-wide. Completes when you learn the mount (item 257085).",
                questIds = MIDNIGHT_SANGUINE_STORMRAY_LOOT_QUESTS,
            },
            {
                id = "void_corrupted_lynx",
                label = "Void-Corrupted Lynx",
                patch = "12.0.0",
                itemId = 1287359,
                farm = true,
                manualOnly = true,
                defaultGoal = 30,
                howTo = "Farm any Ritual level or challenges (Midnight) for this mount (item 1287359). "
                    .. "**Manual tracking only:** the addon does not detect runs. Left-click the task row to increment, right-click to decrement (locks manual progress). "
                    .. "Ctrl–left-click clears the lock and resets the displayed count to the automated total (zero for this entry). Set goal to the number of attempts or clears you want to track.",
            },
            {
                id = "nether_swept_drake",
                label = "Nether Swept Drake",
                patch = "12.0.0",
                mountId = 260916,
                farm = true,
                defaultGoal = 30,
                howTo = "Midnight fishing mount. Progress **+1** per qualifying attempt (goal is your own target, e.g. attempts until drop).\n\n"
                    .. "**Open water:** Voidstorm **uiMapID 2405** and **all subzones** (the addon treats each id in `fishingOpenWaterMapIds` as a **parent**: your map must equal that id or appear **under** it in `C_Map.GetMapInfo` parent chains). Cast Fishing with **no** pool GameObject under the mouse when the cast starts.\n\n"
                    .. "**Pools:** same region tree — pool under the mouse + map under the **LCA** of the configured roots (with `fishingCountMidnightPools`).\n\n"
                    .. "Examples of Voidstorm submaps (in-game ids): **2444** Slayer's Rise, **2506** Shadowguard Point, **2507** Torment's Rise, **2528–2530**, **2556**, **2571–2574**, **2581–2582**; you only need **2405** in data if Blizzard links children to that parent.\n\n"
                    .. "If nothing increments, run **/tt fishdebug**; add missing spell ids to `Core/FishingAttempts.lua` or add a submap id next to **2405** if the client does not parent your current map to 2405.",
                fishingOpenWaterMapIds = { 2405 },
                fishingCountMidnightPools = true,
            },
            {
                id = "ruby_writhe",
                label = "Ruby Writhe",
                patch = "12.1.0",
                itemId = 276803,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Coiled Isle rares and Cursed Surge bosses. Each kill +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Coiled Isle rares and Cursed Surge bosses (Patch 12.1). "
                    .. "Each qualifying kill adds **+1** (goal 30 by default). Resets weekly; progress is account-wide unless you change it. "
                    .. "The row also completes when this mount is in your journal (item 276803).",
                npcIds = MIDNIGHT_COILED_ISLE_RARE_NPCS,
            },
            {
                id = "topaz_skyfang",
                label = "Topaz Skyfang",
                patch = "12.1.0",
                itemId = 276549,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare drop from Coiled Isle rares and Cursed Surge bosses. Each kill +1; weekly account-wide. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from Coiled Isle rares and Cursed Surge bosses (Patch 12.1). "
                    .. "Each qualifying kill adds **+1** (goal 30 by default). Resets weekly; progress is account-wide unless you change it. "
                    .. "The row also completes when this mount is in your journal (item 276549).",
                npcIds = MIDNIGHT_COILED_ISLE_RARE_NPCS,
            },
            {
                id = "hexflame_reaver",
                label = "Hexflame Reaver",
                patch = "12.1.0",
                itemId = 275659,
                farm = true,
                defaultGoal = 50,
                defaultReset = "none",
                defaultNote = "Rare drop from Ral'kala. Offer Ossified Relics at a Haunted Brazier (100 to summon, at least 1 for loot). Each kill +1; no weekly lockout. Completes at your goal or when you learn the mount.",
                howTo = "Rare drop from **Ral'kala** on the Coiled Isle (Patch 12.1 Prey). "
                    .. "Turn on **Curse of the Isle** at the Image of Astalor in Tokka's Landing (Way pins Astalor, not Ral'kala). "
                    .. "Haunted Braziers show on the zone map. Offering **Ossified Relics** fills the bar (**100** to spawn; contribute **at least 1** for loot). "
                    .. "Ethrandil's daily **Prey: Anguish from Beyond** awards 100 relics. "
                    .. "Each qualifying kill adds **+1** (goal 50 by default). No weekly lockout. "
                    .. "The row also completes when this mount is in your journal (item 275659).",
                npcIds = RALKALA_NPCS,
                defaultCommandButtons = {
                    { label = "Way", command = WAY_ASTALOR, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "emerald_skyfang",
                label = "Emerald Skyfang",
                patch = "12.1.0",
                itemId = 276553,
                defaultGoal = 10,
                defaultReset = "weekly",
                howTo = "Pro Poison Patroller: Temple Patrols in the Vaults of Atal'Utek. Weekly goal 10. "
                    .. "The second line is the in-game bar, out of 250. Completes when the achievement or the mount (item 276553) is done.",
            },
            {
                id = "venomous_coiler",
                label = "Venomous Coiler",
                patch = "12.1.0",
                itemId = 276801,
                defaultGoal = 1,
                howTo = "Assault the Vault meta-achievement (63630) in the Vaults of Atal'Utek: complete the 10 listed achievements. "
                    .. "The Collections row tracks those criteria as the in-game bar. Completes when the achievement (or the mount, item 276801) is done.",
            },
            {
                id = "sea_dwelling_isle_serpent",
                label = "Sea-Dwelling Isle Serpent",
                patch = "12.1.0",
                itemId = 275653,
                defaultGoal = 1,
                howTo = "Second Mate Sluggs, 2500 Coiled Filament, Captain Tokka Bloodsworn Crew (item 275653). Completes when you learn the mount.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_SLUGGS, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "auriferous_venomfang",
                label = "Auriferous Venomfang",
                patch = "12.1.0",
                itemId = 275656,
                defaultGoal = 1,
                howTo = "Treasures of Atal'Utek (achievement 63359): loot the 22 treasures in the Vaults of Atal'Utek. "
                    .. "The Collections row tracks those criteria as the in-game bar. Completes when the achievement (or the mount, item 275656) is done.",
            },
            {
                id = "caustic_venomfang",
                label = "Caustic Venomfang",
                patch = "12.1.0",
                itemId = 275654,
                defaultGoal = 1,
                howTo = "Skull of Er'inye in the Vaults of Atal'Utek, 10000 Corrosive Coins (item 275654). Completes when you learn the mount.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_ERINYE, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "indigo_coiled_horror",
                label = "Indigo Coiled Horror",
                patch = "12.1.0",
                itemId = 276802,
                defaultGoal = 1,
                howTo = "Jan'sari the Watchful, 6000 Voidlight Marl, Renown 17 with Zul'jarra's Forces (item 276802). Completes when you learn the mount.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "violet_backed_skyfang",
                label = "Violet-Backed Skyfang",
                patch = "12.1.0",
                itemId = 276551,
                defaultGoal = 1,
                howTo = "Jan'sari the Watchful, 8000 Voidlight Marl, Renown 19 with Zul'jarra's Forces (item 276551). Completes when you learn the mount.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "spirit_tokjara",
                label = "Spirit of Tok'jara",
                patch = "12.1.0",
                itemId = 273838,
                defaultGoal = 1,
                howTo = "Du'gal at the Amani Foothold. Renown 10 with Zul'jarra's Forces starts his six-day chain. "
                    .. "The last quest, The Innocent Essence, teaches the mount (item 273838). "
                    .. "After you learn it, Du'gal offers rotating dailies.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_DUGAL, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "duskbrute_harrower",
                label = "Duskbrute Harrower",
                patch = "12.0.0",
                itemId = 257176,
                defaultGoal = 1,
                howTo = "Chance from a Slayer's Duellum Trove, the paragon chest after Exalted with the Slayer's Duellum (item 257176). Completes when you learn the mount.",
                defaultCommandButtons = {
                    { label = "Way", command = "/way #2444 39.32 80.96 Thraxadar", icon = WAY_ICON, pinned = true },
                },
            },
        },
        pet = {
            {
                id = "nova",
                label = "Nova",
                patch = "12.0.0",
                itemId = 264892,
                defaultGoal = 1,
                howTo = "Chance from a Slayer's Duellum Trove, the paragon chest after Exalted with the Slayer's Duellum (item 264892). Completes when you have the companion pet.",
                defaultCommandButtons = {
                    { label = "Way", command = "/way #2444 39.32 80.96 Thraxadar", icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "poison_dart_frog",
                label = "Poison Dart Frog",
                patch = "12.1.0",
                itemId = 280178,
                farm = true,
                defaultGoal = 30,
                defaultReset = "weekly",
                defaultNote = "Rare from Unfortunate Scout's Satchels on the Coiled Isle (Renown 9 with Zul'jarra's Forces). Each satchel +1; weekly account-wide. Completes at your goal or when you have the pet.",
                howTo = "Rare drop from **Unfortunate Scout's Satchels** on the Coiled Isle (outside the vaults). "
                    .. "Requires Renown 9 with Zul'jarra's Forces to see the satchels. "
                    .. "Each satchel you loot adds **+1** (goal 30 by default). Resets weekly; progress is account-wide unless you change it. "
                    .. "The row also completes when this pet is in your journal (item 280178).",
                lootObjectIds = { 656046 }, -- Unfortunate Scout's Satchel
            },
            {
                id = "pale_hexscale",
                label = "Pale Hexscale",
                patch = "12.1.0",
                itemId = 278572,
                farm = true,
                defaultGoal = 50,
                defaultReset = "none",
                defaultNote = "Rare drop from Ral'kala. Offer Ossified Relics at a Haunted Brazier (100 to summon, at least 1 for loot). Each kill +1; no weekly lockout. Completes at your goal or when you have the pet.",
                howTo = "Rare drop from **Ral'kala** on the Coiled Isle (Patch 12.1 Prey). "
                    .. "Turn on **Curse of the Isle** at the Image of Astalor in Tokka's Landing (Way pins Astalor, not Ral'kala). "
                    .. "Haunted Braziers show on the zone map. Offering **Ossified Relics** fills the bar (**100** to spawn; contribute **at least 1** for loot). "
                    .. "Ethrandil's daily **Prey: Anguish from Beyond** awards 100 relics. "
                    .. "Each qualifying kill adds **+1** (goal 50 by default). No weekly lockout. "
                    .. "The row also completes when this pet is in your journal (item 278572).",
                npcIds = RALKALA_NPCS,
                defaultCommandButtons = {
                    { label = "Way", command = WAY_ASTALOR, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "corrosive_writhling",
                label = "Corrosive Writhling",
                patch = "12.1.0",
                itemId = 275631,
                defaultGoal = 1,
                howTo = "Skull of Er'inye in the Vaults of Atal'Utek, 5000 Corrosive Coins (item 275631). Completes when you have the companion pet.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_ERINYE, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "volatile_venomfang",
                label = "Volatile Venomfang",
                patch = "12.1.0",
                itemId = 275632,
                defaultGoal = 1,
                howTo = "Skull of Er'inye in the Vaults of Atal'Utek, 5000 Corrosive Coins (item 275632). Completes when you have the companion pet.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_ERINYE, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "wild_caught_pets",
                label = "The Coiled Isle Safari",
                patch = "12.1.0",
                defaultGoal = 1,
                howTo = "The Coiled Isle Safari (achievement 62492): catch all 8 wild pets. "
                    .. "The Collections row tracks those criteria as the in-game bar. Completes when the achievement is done (rewards Zesty).",
            },
            {
                id = "kiclak",
                label = "Ki'clak",
                patch = "12.1.0",
                itemId = 279921,
                defaultGoal = 1,
                howTo = "A Stack of Snacks (achievement 63633): finish Don't Be Afrayed, then complete Olawu's world quest. "
                    .. "Weekly goal 2. The second line is the in-game bar, out of 5. Completes when the achievement (or the pet, item 279921) is done.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_OLAWU, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "snekzali",
                label = "Snek'zali",
                patch = "12.1.0",
                itemId = 276248,
                defaultGoal = 1,
                howTo = "Jan'sari the Watchful, 2500 Voidlight Marl, Renown 12 with Zul'jarra's Forces (item 276248). Completes when you have the companion pet.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "venom_elemental",
                label = "Venom Elemental",
                patch = "12.1.0",
                itemId = 275020,
                defaultGoal = 1,
                howTo = "Second Mate Sluggs at Venom Trawler with Captain Tokka, 100 gold (item 275020). Completes when you have the companion pet.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_SLUGGS, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "lil_mon",
                label = "Lil' Mon",
                patch = "12.1.0",
                itemId = 280540,
                farm = true,
                defaultGoal = 1,
                defaultReset = "daily",
                npcIds = { 256631 },
                howTo = "Kill Big Mon on the Coiled Isle (item 280540). Daily account-wide, one kill. "
                    .. "The second line shows your total kills and the Rarity drop rate. Completes at your goal or when you have the companion pet.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_BIG_MON, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "cauldron_concoction",
                label = "Cauldron Concoction",
                patch = "12.1.0",
                itemId = 280189,
                defaultGoal = 1,
                howTo = "Chance from Ofi's Mixing Mysteries offerings after unlocking her cauldron (Renown 3 with Zul'jarra's Forces, item 280189). Completes when you have the companion pet.",
            },
            {
                id = "zan",
                label = "Zan",
                patch = "12.1.0",
                itemId = 268644,
                defaultGoal = 1,
                howTo = "Reward from A Little Kindness (quest 93393, Strange Friends in Odd Places). Starts at Ofi the Sly. Completes when you have the companion pet (item 268644).",
                defaultCommandButtons = {
                    { label = "Way", command = "/way #2512 61.00 33.00 Ofi the Sly", icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "three_eyed_fish",
                label = "Three-Eyed Fish",
                patch = "12.1.0",
                itemId = 279483,
                defaultGoal = 1,
                howTo = "Venom Trawler is rank 4 of 5 with Captain Tokka. After that, buy an Eerie Bauble for 250 Voidlight and use it on a fishing pool to fish up a Star Ooze. That starts a quest chain of 3 quests, ending with Tipping the Scaled (quest 97565).",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_TOKKA, icon = WAY_ICON, pinned = true },
                },
            },
        },
        toy = {
            {
                id = "ancient_amani_mask",
                label = "Ancient Amani Mask",
                patch = "12.1.0",
                itemId = 279052,
                defaultGoal = 1,
                defaultNote = "Toy from the Sunken Diver's Chest on the Coiled Isle (Diver's Key fragments from Glittering Grouper Brinetail).",
                howTo = "Toy from the Sunken Diver's Chest on the Coiled Isle (item 279052). "
                    .. "Completes when the toy is in your collection.",
                defaultCommandButtons = {
                    { label = "Way", command = AMANI_MASK_WAY, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "preyhunters_masquerade",
                label = "Preyhunter's Masquerade",
                patch = "12.1.0",
                itemId = 276207,
                farm = true,
                defaultGoal = 50,
                defaultReset = "none",
                defaultNote = "Rare drop from Ral'kala. Offer Ossified Relics at a Haunted Brazier (100 to summon, at least 1 for loot). Each kill +1; no weekly lockout. Completes at your goal or when the toy is in your collection.",
                howTo = "Rare drop from **Ral'kala** on the Coiled Isle (Patch 12.1 Prey). "
                    .. "Turn on **Curse of the Isle** at the Image of Astalor in Tokka's Landing (Way pins Astalor, not Ral'kala). "
                    .. "Haunted Braziers show on the zone map. Offering **Ossified Relics** fills the bar (**100** to spawn; contribute **at least 1** for loot). "
                    .. "Ethrandil's daily **Prey: Anguish from Beyond** awards 100 relics. "
                    .. "Each qualifying kill adds **+1** (goal 50 by default). No weekly lockout. "
                    .. "The row also completes when this toy is in your collection (item 276207).",
                npcIds = RALKALA_NPCS,
                defaultCommandButtons = {
                    { label = "Way", command = WAY_ASTALOR, icon = WAY_ICON, pinned = true },
                },
            },
            {
                id = "cursed_badge",
                label = "Cursed Badge of the Soulcoilers",
                patch = "12.1.0",
                itemId = 280419,
                defaultGoal = 1,
                howTo = "Student of Hissstory (achievement 63662): find the 10 lore objects in the Vaults of Atal'Utek. "
                    .. "The Collections row tracks those criteria as the in-game bar. Completes when the achievement (or the toy, item 280419) is done.",
            },
            {
                id = "idol_ulatek",
                label = "Idol of Ula'tek",
                patch = "12.1.0",
                itemId = 276925,
                defaultGoal = 1,
                howTo = "Jan'sari the Watchful, 4000 Voidlight Marl, Renown 13 with Zul'jarra's Forces (item 276925). Completes when the toy is in your collection.",
                defaultCommandButtons = {
                    { label = "Way", command = WAY_JANSARI, icon = WAY_ICON, pinned = true },
                },
            },
        },
        currency = {
            {
                id = "voidlight_marl",
                label = "Voidlight Marl",
                patch = "12.0.0",
                currencyId = 3316,
                defaultGoal = 10000,
                defaultReset = "weekly",
                howTo = "Midnight vendor currency from all zones (renown quartermasters and other vendors). Weekly earned target; default goal 10000.",
            },
            {
                id = "remnant_of_anguish",
                label = "Remnant of Anguish",
                patch = "12.0.0",
                currencyId = 3392,
                defaultGoal = 1000,
                defaultReset = "weekly",
                howTo = "Prey currency from hunts. Spend it at Construct V'anore in Astalor's Sanctum. Weekly earned target; default goal 1000.",
            },
            {
                id = "corrosive_coins",
                label = "Corrosive Coins",
                patch = "12.1.0",
                currencyId = 3448,
                defaultGoal = 20000,
                defaultReset = "weekly",
                howTo = "Currency from the Altar of Corrosion in the Vaults of Atal'Utek. Weekly earned target; default goal 20000.",
            },
        },
        other = {},
    },
}

function TaskTracker.GetCollectableExpansionList()
    return {
        { id = "midnight", label = "Midnight" },
        { id = "tww", label = "The War Within" },
    }
end

function TaskTracker.GetCollectableCategories()
    return {
        { id = "mount", label = "Mounts" },
        { id = "pet", label = "Pets" },
        { id = "toy", label = "Toys" },
        { id = "currency", label = "Currency" },
        { id = "other", label = "Other" },
    }
end

local function catalogRoot(expansionId)
    expansionId = tostring(expansionId or ""):lower()
    local root = TaskTracker.CollectableCatalog[expansionId]
    if type(root) ~= "table" then return nil end
    return root
end

--- @return table[] list of { id, label, howTo, questIds }
function TaskTracker.GetCollectableEntries(expansionId, categoryId)
    local root = catalogRoot(expansionId)
    if not root then return {} end
    categoryId = tostring(categoryId or ""):lower()
    local list = root[categoryId]
    if type(list) ~= "table" then return {} end
    return list
end

function TaskTracker.FindCollectableSpecByItemId(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return nil end
    local cat = TaskTracker.CollectableCatalog
    if type(cat) ~= "table" then return nil end
    for expId, root in pairs(cat) do
        if type(root) == "table" then
            for catId, list in pairs(root) do
                if type(list) == "table" then
                    for _, ent in ipairs(list) do
                        if type(ent) == "table" and tonumber(ent.itemId) == itemId and ent.id then
                            return { expansion = expId, category = catId, entryId = ent.id }
                        end
                    end
                end
            end
        end
    end
    return nil
end

function TaskTracker.GetCollectableEntry(expansionId, categoryId, entryId)
    entryId = tostring(entryId or ""):lower()
    for _, e in ipairs(TaskTracker.GetCollectableEntries(expansionId, categoryId)) do
        if e and tostring(e.id or ""):lower() == entryId then
            return e
        end
    end
    return nil
end

--- BattlePetSpeciesID taught by a companion item. GetPetInfoByItemID's first return is the name.
local function petSpeciesIdFromItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or not (C_PetJournal and C_PetJournal.GetPetInfoByItemID) then
        return nil
    end
    local packed = { pcall(C_PetJournal.GetPetInfoByItemID, itemId) }
    if packed[1] ~= true then return nil end
    -- pcall ok + 13 API returns: speciesID is packed[14]. Older clients returned speciesID first.
    local speciesID = tonumber(packed[14])
    if speciesID and speciesID > 0 then return speciesID end
    speciesID = tonumber(packed[2])
    if speciesID and speciesID > 0 then return speciesID end
    return nil
end

--- FindPetIDByName returns speciesId, petGUID. speciesId exists for unowned pets; only petGUID means collected.
local function petSpeciesAndGuidByName(name)
    if type(name) ~= "string" then return nil, nil end
    name = name:match("^%s*(.-)%s*$") or ""
    if name == "" or not (C_PetJournal and C_PetJournal.FindPetIDByName) then return nil, nil end
    local ok, speciesId, petGUID = pcall(C_PetJournal.FindPetIDByName, name)
    if not ok then return nil, nil end
    if type(petGUID) ~= "string" or petGUID == "" then petGUID = nil end
    speciesId = tonumber(speciesId)
    if not speciesId or speciesId <= 0 then speciesId = nil end
    return speciesId, petGUID
end

--- True if the catalog entry is already collected (mount journal, toy box, etc.). Unknown / no id → false.
function TaskTracker.IsCatalogCollectableOwned(entry, categoryId)
    if type(entry) ~= "table" then return false end
    categoryId = tostring(categoryId or ""):lower()
    if categoryId == "mount" then
        local mid = tonumber(entry.mountId)
        if mid and mid > 0 and C_MountJournal and C_MountJournal.GetMountInfoByID then
            local ok, isCollected = pcall(function()
                return select(11, C_MountJournal.GetMountInfoByID(mid))
            end)
            return ok and isCollected == true
        end
        local spellId = tonumber(entry.mountSpellId)
        if spellId and spellId > 0 and C_MountJournal and C_MountJournal.GetMountFromSpell then
            local ok, fromSpell = pcall(C_MountJournal.GetMountFromSpell, spellId)
            if ok and fromSpell and fromSpell > 0 and C_MountJournal.GetMountInfoByID then
                local ok2, isCollected = pcall(function()
                    return select(11, C_MountJournal.GetMountInfoByID(fromSpell))
                end)
                return ok2 and isCollected == true
            end
        end
        local itemId = tonumber(entry.itemId)
        if itemId and itemId > 0 and C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountInfoByID then
            local ok, journalMountId = pcall(C_MountJournal.GetMountFromItem, itemId)
            if ok and journalMountId and journalMountId > 0 then
                local ok2, isCollected = pcall(function()
                    return select(11, C_MountJournal.GetMountInfoByID(journalMountId))
                end)
                return ok2 and isCollected == true
            end
        end
        return false
    end
    if categoryId == "toy" then
        local itemId = tonumber(entry.itemId)
        if itemId and itemId > 0 and PlayerHasToy then
            local ok, has = pcall(PlayerHasToy, itemId)
            return ok and has == true
        end
        return false
    end
    if categoryId == "currency" then
        return false
    end
    if categoryId == "pet" then
        local speciesId = tonumber(entry.petSpeciesId)
        if not speciesId or speciesId <= 0 then
            speciesId = petSpeciesIdFromItem(entry.itemId)
        end
        if speciesId and speciesId > 0 and C_PetJournal and C_PetJournal.GetNumCollectedInfo then
            local ok, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, speciesId)
            if ok and type(numCollected) == "number" and numCollected > 0 then
                return true
            end
        end
        -- FindPetIDByName is speciesId, petGUID. speciesId exists for unowned pets; GUID means collected.
        local byName, guid = petSpeciesAndGuidByName(entry.label)
        if guid then return true end
        if (not speciesId or speciesId <= 0) and byName and C_PetJournal and C_PetJournal.GetNumCollectedInfo then
            local ok, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, byName)
            if ok and type(numCollected) == "number" and numCollected > 0 then
                return true
            end
        end
        return false
    end
    return false
end

function TaskTracker.CollectableEntryHasOwnershipId(ent)
    if type(ent) ~= "table" then return false end
    local itemId = tonumber(ent.itemId)
    if itemId and itemId > 0 then return true end
    local mountId = tonumber(ent.mountId)
    if mountId and mountId > 0 then return true end
    local spellId = tonumber(ent.mountSpellId)
    if spellId and spellId > 0 then return true end
    local speciesId = tonumber(ent.petSpeciesId)
    if speciesId and speciesId > 0 then return true end
    local currencyId = tonumber(ent.currencyId)
    if currencyId and currencyId > 0 then return true end
    return false
end

--- True when an advanced collectable task's catalog entry is already in the journal/toy box.
function TaskTracker.IsCollectableTaskJournalOwned(node)
    if not node or node.type ~= "task" then return false end
    local a = node.advanced
    if type(a) ~= "table" or a.type ~= "collectable" then return false end
    local ent = TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
    if not ent then return false end
    return TaskTracker.IsCatalogCollectableOwned(ent, a.collectableCategory) == true
end

--- Same as GetCollectableEntries but omits entries the player already owns when the option is enabled.
function TaskTracker.GetCollectableEntriesForPicker(expansionId, categoryId)
    local list = TaskTracker.GetCollectableEntries(expansionId, categoryId)
    if not TaskTracker.GetCollectablesHideOwnedInPicker or not TaskTracker.GetCollectablesHideOwnedInPicker() then
        return list
    end
    local out = {}
    for _, ent in ipairs(list) do
        if not TaskTracker.IsCatalogCollectableOwned(ent, categoryId) then
            out[#out + 1] = ent
        end
    end
    return out
end

--- Catalog entry opts in to fully manual progress (no quest or fishing automation).
function TaskTracker.CollectableEntryIsManualOnly(ent)
    return type(ent) == "table" and ent.manualOnly == true
end

--- Catalog entry opts in to fishing attempt automation (see Core/FishingAttempts.lua).
function TaskTracker.CollectableEntryHasFishingRules(ent)
    if type(ent) ~= "table" then return false end
    if ent.fishingCountMidnightPools == true then return true end
    local ow = ent.fishingOpenWaterMapIds
    if type(ow) == "table" then
        for _, id in ipairs(ow) do
            if tonumber(id) and tonumber(id) > 0 then
                return true
            end
        end
    end
    return false
end

function TaskTracker.CollectableEntryNpcIds(ent)
    if type(ent) ~= "table" or type(ent.npcIds) ~= "table" or #ent.npcIds == 0 then return nil end
    return ent.npcIds
end

function TaskTracker.CollectableEntryMatchesNpc(ent, npcId)
    npcId = tonumber(npcId)
    if not npcId or npcId <= 0 then return false end
    local ids = TaskTracker.CollectableEntryNpcIds(ent)
    if not ids then return false end
    for _, id in ipairs(ids) do
        if tonumber(id) == npcId then return true end
    end
    return false
end

function TaskTracker.CollectableEntryLootObjectIds(ent)
    if type(ent) ~= "table" or type(ent.lootObjectIds) ~= "table" or #ent.lootObjectIds == 0 then return nil end
    return ent.lootObjectIds
end

function TaskTracker.CollectableEntryFarmItemId(ent)
    if type(ent) ~= "table" then return nil end
    local id = tonumber(ent.farmItemId)
    if id and id > 0 then return math.floor(id) end
    return nil
end

function TaskTracker.CollectableEntryMatchesLootObject(ent, objectId)
    objectId = tonumber(objectId)
    if not objectId or objectId <= 0 then return false end
    local ids = TaskTracker.CollectableEntryLootObjectIds(ent)
    if not ids then return false end
    for _, id in ipairs(ids) do
        if tonumber(id) == objectId then return true end
    end
    return false
end

function TaskTracker.CollectableAdvHasProgressSource(adv)
    if type(adv) ~= "table" or adv.type ~= "collectable" then return false end
    if type(adv.collectableQuestIds) == "table" and #adv.collectableQuestIds > 0 then return true end
    local ent = TaskTracker.GetCollectableEntry(adv.collectableExpansion, adv.collectableCategory, adv.collectableEntryId)
    if TaskTracker.CollectableEntryIsManualOnly(ent) then return true end
    if TaskTracker.CollectableEntryHasFishingRules(ent) then return true end
    if TaskTracker.CollectableEntryNpcIds(ent) then return true end
    if TaskTracker.CollectableEntryLootObjectIds(ent) then return true end
    if TaskTracker.CollectableEntryFarmItemId and TaskTracker.CollectableEntryFarmItemId(ent) then return true end
    return TaskTracker.CollectableEntryHasOwnershipId(ent)
end

--- Resolve quest id list for a saved advanced.collectable node (prefers explicit list, else catalog).
function TaskTracker.GetCollectableQuestIdsForNodeAdvanced(a)
    if type(a) ~= "table" or a.type ~= "collectable" then return {} end
    if type(a.collectableQuestIds) == "table" and #a.collectableQuestIds > 0 then
        local out, seen = {}, {}
        for _, q in ipairs(a.collectableQuestIds) do
            local n = tonumber(q)
            if n and n > 0 and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
        return out
    end
    local ent = TaskTracker.GetCollectableEntry(a.collectableExpansion, a.collectableCategory, a.collectableEntryId)
    if ent and type(ent.questIds) == "table" then
        return ent.questIds
    end
    return {}
end
