-- UI/Themes/Bronzed.lua
-- Charcoal mahogany, metallic gold, cream text. Was Gilded.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["bronzed"] = {
    name = "Bronzed",
    key  = "bronzed",

    bg        = { 0.055, 0.043, 0.031, 0.98 },  -- #0E0B08
    panelBg   = { 0.078, 0.063, 0.047, 0.98 },  -- #14100C
    headerBg  = { 0.110, 0.086, 0.055, 1.0  },  -- #1C160E
    headerBg2 = { 0.137, 0.106, 0.071, 1.0  },  -- #231B12
    headerBg3 = { 0.180, 0.125, 0.043, 1.0  },  -- gold wash — Collections
    headerBgHere = { 0.320, 0.230, 0.080, 1.0 },  -- current zone
    rowEven   = { 0.094, 0.075, 0.055, 1.0  },
    rowOdd    = { 0.071, 0.055, 0.039, 1.0  },
    rowHover  = { 0.157, 0.122, 0.078, 1.0  },
    inputBg   = { 0.043, 0.031, 0.020, 1.0  },

    border      = { 0.545, 0.420, 0.180, 1.0 },  -- antique gold edge
    borderLight = { 0.655, 0.522, 0.267, 1.0 },

    accent    = { 0.851, 0.686, 0.275, 1.0 },  -- #D9AF46
    accentDim = { 0.620, 0.478, 0.157, 1.0 },
    accentBg  = { 0.851, 0.686, 0.275, 0.42 },

    textPrimary   = { 0.973, 0.910, 0.710, 1.0 },  -- #F8E8B5
    textSecondary = { 0.720, 0.620, 0.400, 1.0 },
    textDim       = { 0.420, 0.350, 0.220, 1.0 },
    textAccent    = { 0.851, 0.686, 0.275, 1.0 },
    textWarm      = { 0.973, 0.910, 0.710, 1.0 },
    textHeader    = { 0.851, 0.686, 0.275, 1.0 },
    textTask      = { 0.945, 0.875, 0.655, 1.0 },
    textRegistry  = { 0.973, 0.910, 0.710, 1.0 },

    complete = { 0.310, 0.760, 0.380, 1.0 },  -- quest-complete green
    override = { 1.000, 0.820, 0.280, 1.0 },
    danger   = { 0.820, 0.180, 0.140, 1.0 },  -- WoW hostile red
    warning  = { 0.910, 0.550, 0.120, 1.0 },

    taskBarAutomated = { 0.851, 0.686, 0.275, 0.92 },
    taskBarManual    = { 0.950, 0.550, 0.150, 0.92 },

    insertLine  = { 0.851, 0.686, 0.275, 0.5 },
    insertHover = { 0.851, 0.686, 0.275, 1.0 },
    insertLinePickUp  = { 1.00, 0.82, 0.38, 0.75 },
    insertHoverPickUp = { 1.00, 0.90, 0.55, 1.0 },
    insertSplitGroupLine    = { 0.28, 0.70, 0.38, 0.55 },
    insertSplitGroupHover   = { 0.38, 0.82, 0.48, 0.95 },
    insertSplitTaskLine     = { 0.42, 0.55, 0.82, 0.55 },
    insertSplitTaskHover    = { 0.52, 0.65, 0.92, 0.95 },
    insertSplitTaskDisabled = { 0.38, 0.32, 0.24, 0.35 },
}
