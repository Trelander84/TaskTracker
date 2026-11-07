-- Data/WorldQuestMaps.lua
-- Zone uiMapIDs that have world quests, Legion through Midnight.
-- Zone list checked against World Quest Tracker's WorldQuestZones (Legion through
-- Midnight hubs) and Wowhead's uiMap list. Extra zones that had their own world
-- quests: Korthia, Uldum, Vale of Eternal Blossoms, Siren Isle, and The Coiled Isle.

TaskTracker = TaskTracker or {}

TaskTracker.WORLD_QUEST_MAPS = {
    midnight = {
        { id = 2395, name = "Eversong Woods" },
        { id = 2393, name = "Silvermoon City" },
        { id = 2437, name = "Zul'Aman" },
        { id = 2405, name = "Voidstorm" },
        { id = 2413, name = "Harandar" },
        { id = 2424, name = "Isle of Quel'Danas" },
        { id = 2512, name = "The Coiled Isle" },
    },
    tww = {
        { id = 2248, name = "Isle of Dorn" },
        { id = 2214, name = "The Ringing Deeps" },
        { id = 2215, name = "Hallowfall" },
        { id = 2255, name = "Azj-Kahet" },
        { id = 2256, name = "Azj-Kahet" },
        { id = 2213, name = "City of Threads" },
        { id = 2216, name = "City of Threads" },
        { id = 2346, name = "Undermine" },
        { id = 2371, name = "K'aresh" },
        { id = 2369, name = "Siren Isle" },
    },
    dragonflight = {
        { id = 2022, name = "The Waking Shores" },
        { id = 2023, name = "Ohn'ahran Plains" },
        { id = 2024, name = "The Azure Span" },
        { id = 2025, name = "Thaldraszus" },
        { id = 2112, name = "Valdrakken" },
        { id = 2151, name = "The Forbidden Reach" },
        { id = 2133, name = "Zaralek Cavern" },
        { id = 2200, name = "Emerald Dream" },
    },
    shadowlands = {
        { id = 1533, name = "Bastion" },
        { id = 1536, name = "Maldraxxus" },
        { id = 1565, name = "Ardenweald" },
        { id = 1525, name = "Revendreth" },
        { id = 1543, name = "The Maw" },
        { id = 1961, name = "Korthia" },
        { id = 1970, name = "Zereth Mortis" },
    },
    bfa = {
        { id = 862, name = "Zuldazar" },
        { id = 863, name = "Nazmir" },
        { id = 864, name = "Vol'dun" },
        { id = 1165, name = "Dazar'alor" },
        { id = 895, name = "Tiragarde Sound" },
        { id = 942, name = "Stormsong Valley" },
        { id = 896, name = "Drustvar" },
        { id = 1161, name = "Boralus" },
        { id = 1169, name = "Tol Dagor" },
        { id = 62, name = "Darkshore" },
        { id = 14, name = "Arathi Highlands" },
        { id = 1355, name = "Nazjatar" },
        { id = 1462, name = "Mechagon" },
        { id = 1527, name = "Uldum" },
        { id = 1530, name = "Vale of Eternal Blossoms" },
    },
    legion = {
        { id = 630, name = "Azsuna" },
        { id = 641, name = "Val'sharah" },
        { id = 650, name = "Highmountain" },
        { id = 634, name = "Stormheim" },
        { id = 680, name = "Suramar" },
        { id = 646, name = "Broken Shore" },
        { id = 790, name = "Eye of Azshara" },
        { id = 625, name = "Dalaran" },
        { id = 627, name = "Dalaran" },
        { id = 830, name = "Krokuun" },
        { id = 882, name = "Eredath" },
        { id = 885, name = "Antoran Wastes" },
    },
}
