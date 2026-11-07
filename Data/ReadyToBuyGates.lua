-- Data/ReadyToBuyGates.lua
-- Ranks AllTheThings left off the item (no minReputation). Singularity is not
-- listed: its vendor already writes the rank. A row is stored only when a
-- published vendor list gives the rank. If the client cannot report that
-- faction's rank, Ready to Buy shows the restriction and does not offer the item.

TaskTracker = TaskTracker or {}

local PREY = 2808
local DELVES_S1 = 2742

local function prey(rank)
    return { factionId = PREY, min = rank, label = "Preyhunter's Journey" }
end

TaskTracker.READY_TO_BUY_GATES = {
    -- Construct V'anore (npc 252956), Prey season 2.
    [275312] = prey(2), -- Formula: Furious Tiki Mask
    [273061] = prey(2), -- Plans: Hunter's Ritual Stone
    [276229] = prey(4), -- Preyhunter's Trophy Stand
    [276258] = prey(4), -- Companion Command Crystal
    [258029] = prey(6), -- Vaunted helm
    [258027] = prey(6), -- Vaunted shoulders
    [258031] = prey(6), -- Vaunted knapsack
    [278101] = prey(7),
    [278103] = prey(7),
    [278104] = prey(7),
    [278105] = prey(7),
    [278261] = prey(7), -- Arsenal, same ATT price block as the rank 7 ensembles
    [275704] = prey(8), -- Preyhunter's Riftbreaker
    [275702] = prey(8), -- Preyhunter's Prismguard
    [279092] = prey(9), -- Anguish-Touched Pouch (itemized vendor list; one summary said rank 8)
    [275660] = prey(10), -- Preyhunter's Courser

    -- Construct Ali'a (npc 258181) decor, same journey.
    [278123] = prey(1),
    [278126] = prey(2),
    [278130] = prey(3),
    [278134] = prey(4),
    [250870] = prey(5),
    [253449] = prey(5),
    [278145] = prey(6),
    [278148] = prey(7),
    [278151] = prey(9),
    [250868] = prey(10),

    -- Telemancer Astrandis (npc 242399). ATT has a comment "Renown 5" and no
    -- minReputation. Faction 2742 is Delves: Season 1.
    [262500] = { factionId = DELVES_S1, min = 5, label = "Delver's Journey" },
}
