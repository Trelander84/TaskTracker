-- Data/PowerSeason.lua
-- This expansion's Power loot table. Registry rows say what to track; this file says what they drop.
--
-- Mid-expansion (new source): add the registry row + quest ids, add its id to the tree order in
-- Core/DB.lua, add a sources[] entry here (pick a pattern, attach a pool if it shares a cap).
-- Expansion change: delete last expansion's registry rows, this file's contents, and those DB.lua
-- order lists. Drop leftover SavedVariables for the old ids. Write the new season + first sources.

TaskTracker = TaskTracker or {}

-- Patterns the apply step understands:
--   pinnacle_then_surplus  first slot is the shared pinnacle chest; optional surplus after the cap
--   first_hunt_then_crest  Prey-style: chest until firstHunt.untilCount hunts this week, then crests
--   standalone             one slot (rep leftover, Mythic+ hints, anything that is not pooled)
--   gear_then_crest        gear slot, then a crest that keeps its own ilvl (it does not copy the gear gate)
-- minLevel on a source applies to every slot. Under that level the row leaves the Power list.

TaskTracker.PowerSeason = {
    id = "midnight_s2",

    pools = {
        -- Any cache tagged "Pinnacle Cache - Midnight Season 2" shares this cap.
        -- First two each week contain Veteran gear (ilvl 279); later ones are surplus.
        pinnacle_gear = { weeklyCap = 2 },
    },

    sources = {
        prey_normal = {
            sortOrder = 10,
            minLevel = 90,
            pattern = "first_hunt_then_crest",
            firstHunt = { itemId = 275918, expectedIlvl = 266, untilCount = 2, label = "Preyhunter's Adventurer Chest" },
            crest = { expectedIlvl = 282, currencyId = 3437, label = "Adventurer Mistcrest" },
        },
        prey_hard = {
            sortOrder = 11,
            minLevel = 90,
            pattern = "first_hunt_then_crest",
            firstHunt = { itemId = 275822, expectedIlvl = 279, untilCount = 2, label = "Preyhunter's Veteran Chest" },
            crest = { expectedIlvl = 295, currencyId = 3443, label = "Veteran Mistcrest" },
        },
        prey_nightmare = {
            sortOrder = 12,
            minLevel = 90,
            pattern = "first_hunt_then_crest",
            firstHunt = { itemId = 275726, expectedIlvl = 292, untilCount = 2, label = "Preyhunter's Champion Chest" },
            -- Also 5 Hero Mistcrest (3445); icon uses Champion as the main follow-up.
            crest = { expectedIlvl = 308, currencyId = 3444, label = "Champion + Hero Mistcrest" },
        },

        -- After the two Veteran caches, the bag still holds Veteran Mistcrest (3443).
        -- A capped crest drops a tier in game; the row shows Veteran.
        s1_fortify_runestones = {
            sortOrder = 20,
            minLevel = 90,
            pattern = "pinnacle_then_surplus",
            pool = "pinnacle_gear",
            priority = 10,
            pinnacle = {
                itemId = 279522, expectedIlvl = 279,
                label = "Surplus Bag of Party Favors",
            },
            surplus = {
                currencyId = 3443,
                label = "Veteran Mistcrest",
            },
        },
        s1_special_assignments = {
            sortOrder = 21,
            minLevel = 90,
            pattern = "pinnacle_then_surplus",
            pool = "pinnacle_gear",
            priority = 22,
            -- quest_count max 2: each completion consumes one pool slot (two of this cache / week).
            -- Coiled Isle drops 282183 instead; same Veteran pool, ilvl not confirmed (using 279).
            pinnacle = {
                itemId = 279520, expectedIlvl = 279,
                label = "Fabled Veteran's Cache",
                otherReward = "Coiled Isle cache 282183 (ilvl unconfirmed).",
            },
            surplus = {
                currencyId = 3443,
                label = "Veteran Mistcrest",
            },
        },
        s1_weekly_abundance = {
            sortOrder = 22,
            minLevel = 90,
            pattern = "pinnacle_then_surplus",
            pool = "pinnacle_gear",
            priority = 30,
            pinnacle = {
                itemId = 279523, expectedIlvl = 279,
                label = "Overflowing Abundant Satchel",
            },
            surplus = {
                currencyId = 3443,
                label = "Veteran Mistcrest",
            },
        },
        s1_lost_legends = {
            sortOrder = 23,
            minLevel = 90,
            pattern = "pinnacle_then_surplus",
            pool = "pinnacle_gear",
            priority = 40,
            pinnacle = {
                itemId = 279525, expectedIlvl = 279,
                label = "Avid Learner's Supply Pack",
            },
            surplus = {
                currencyId = 3443,
                label = "Veteran Mistcrest",
            },
        },
        s1_stormarion_assault_wq = {
            sortOrder = 24,
            minLevel = 90,
            pattern = "pinnacle_then_surplus",
            pool = "pinnacle_gear",
            priority = 50,
            -- One Stormarion cache per week; still counts as one seat in the shared 2-pinnacle pool.
            pinnacle = {
                itemId = 279526, expectedIlvl = 279,
                label = "Victorious Stormarion Pinnacle Cache",
            },
            surplus = {
                currencyId = 3443,
                label = "Veteran Mistcrest",
            },
        },
        s1_cursed_surges = {
            sortOrder = 25,
            minLevel = 90,
            pattern = "pinnacle_then_surplus",
            pool = "pinnacle_gear",
            priority = 60,
            pinnacle = {
                itemId = 275911, expectedIlvl = 279,
                label = "Venom-Covered Chest",
            },
            surplus = {
                currencyId = 3443,
                label = "Veteran Mistcrest",
            },
        },

        -- Crest caps are the top of that crest's upgrade track, not the drop.
        -- Adventurer 282 matches the Prey crest. Champion 309 / Hero 322 are the raid 6/6 rare column.
        -- Myth 334 is Wowhead's Myth Mistcrest cap (currency 3446) and the standard Mythic vault choice.
        -- Difficulty icons are the Group Manager hover marks on UIGroupManager2x.
        -- Aqir Research Satchel (item 277283). Gear gate is Champion 2/6 (295).
        -- Champion Mistcrest keeps its own cap, same as the other Champion rows.
        p1215_aqir_satchel = {
            sortOrder = 26,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                itemId = 277283,
                expectedIlvl = 295,
                label = "Aqir Research Satchel",
            },
            crest = { expectedIlvl = 309, currencyId = 3444, label = "Champion Mistcrest" },
        },

        seasonal_dungeon_normal = {
            sortOrder = 64,
            minLevel = 80,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvl = 253,
                label = "Normal dungeon",
                iconAtlas = "GM-icon-difficulty-normal-hover",
            },
            crest = { expectedIlvl = 282, currencyId = 3437, label = "Adventurer Mistcrest" },
        },
        seasonal_dungeon_heroic = {
            sortOrder = 65,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvl = 276,
                label = "Heroic dungeon",
                iconAtlas = "GM-icon-difficulty-heroic-hover",
            },
            crest = { expectedIlvl = 282, currencyId = 3437, label = "Adventurer Mistcrest" },
        },
        -- Venomous Abyss boss band: early through final. expectedIlvl is the high end (the Power gate).
        -- Mythic final bosses (The Coiled Altar, Ula'tek) are 344; earlier mythic bosses start at 318.
        seasonal_raid_normal = {
            sortOrder = 66,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvlLow = 292,
                expectedIlvl = 302,
                label = "Normal raid",
                iconAtlas = "GM-icon-difficulty-normal-hover",
            },
            crest = { expectedIlvl = 309, currencyId = 3444, label = "Champion Mistcrest" },
        },
        seasonal_raid_vault_normal = {
            sortOrder = 67,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvl = 305,
                label = "Normal vault",
                iconAtlas = "GM-icon-difficulty-normal-hover",
            },
            crest = { expectedIlvl = 309, currencyId = 3444, label = "Champion Mistcrest" },
        },
        seasonal_raid_heroic = {
            sortOrder = 68,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvlLow = 305,
                expectedIlvl = 315,
                label = "Heroic raid",
                iconAtlas = "GM-icon-difficulty-heroic-hover",
            },
            crest = { expectedIlvl = 322, currencyId = 3445, label = "Hero Mistcrest" },
        },
        seasonal_raid_vault_heroic = {
            sortOrder = 69,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvl = 318,
                label = "Heroic vault",
                iconAtlas = "GM-icon-difficulty-heroic-hover",
            },
            crest = { expectedIlvl = 322, currencyId = 3445, label = "Hero Mistcrest" },
        },
        seasonal_raid_mythic = {
            sortOrder = 70,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvlLow = 318,
                expectedIlvl = 344,
                label = "Mythic raid",
                iconAtlas = "GM-icon-difficulty-mythic-hover",
            },
            -- Myth crests stop at 334. The gear gate is 344, so this slot stays on the details page.
            crest = { expectedIlvl = 334, currencyId = 3446, label = "Myth Mistcrest" },
        },
        seasonal_raid_vault_mythic = {
            sortOrder = 71,
            minLevel = 90,
            pattern = "gear_then_crest",
            slot = {
                expectedIlvlLow = 334,
                expectedIlvl = 344,
                label = "Mythic vault",
                iconAtlas = "GM-icon-difficulty-mythic-hover",
            },
            crest = { expectedIlvl = 334, currencyId = 3446, label = "Myth Mistcrest" },
        },

        seasonal_mplus_hint_end = {
            sortOrder = 80,
            minLevel = 90,
            pattern = "standalone",
            slot = {
                label = "End chest target",
                otherReward = "Lowest +key whose end chest beats your comparison ilvl.",
            },
        },
        seasonal_mplus_hint_vault = {
            sortOrder = 81,
            minLevel = 90,
            pattern = "standalone",
            slot = {
                label = "Vault slots",
                otherReward = "Lowest +key whose dungeon vault reward beats your comparison ilvl.",
            },
        },
    },
}
