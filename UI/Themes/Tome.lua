-- UI/Themes/Tome.lua
-- Leather journal: quest-log fonts, roomy rows, thick gilt edge.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["tome"] = {
    name = "Tome",
    key  = "tome",

    bg        = { 0.102, 0.063, 0.047, 0.98 },  -- #1A100C
    panelBg   = { 0.125, 0.078, 0.055, 0.98 },
    headerBg  = { 0.165, 0.102, 0.071, 1.0  },
    headerBg2 = { 0.196, 0.122, 0.086, 1.0  },
    headerBg3 = { 0.196, 0.137, 0.047, 1.0  },  -- gilt wash — Collections
    headerBgHere = { 0.340, 0.250, 0.100, 1.0 },  -- current zone
    rowEven   = { 0.145, 0.090, 0.063, 1.0  },
    rowOdd    = { 0.114, 0.071, 0.051, 1.0  },
    rowHover  = { 0.220, 0.141, 0.094, 1.0  },
    inputBg   = { 0.078, 0.047, 0.031, 1.0  },

    border      = { 0.620, 0.455, 0.220, 1.0 },
    borderLight = { 0.745, 0.565, 0.310, 1.0 },

    accent    = { 0.769, 0.639, 0.353, 1.0 },  -- #C4A35A
    accentDim = { 0.545, 0.420, 0.180, 1.0 },
    accentBg  = { 0.769, 0.639, 0.353, 0.38 },

    textPrimary   = { 0.941, 0.894, 0.816, 1.0 },
    textSecondary = { 0.700, 0.600, 0.470, 1.0 },
    textDim       = { 0.450, 0.360, 0.260, 1.0 },
    textAccent    = { 0.850, 0.710, 0.400, 1.0 },
    textWarm      = { 0.941, 0.894, 0.816, 1.0 },
    textHeader    = { 0.850, 0.710, 0.400, 1.0 },
    textTask      = { 0.920, 0.860, 0.760, 1.0 },
    textRegistry  = { 0.941, 0.894, 0.816, 1.0 },

    complete = { 0.380, 0.680, 0.360, 1.0 },
    override = { 0.900, 0.700, 0.280, 1.0 },
    danger   = { 0.780, 0.220, 0.180, 1.0 },
    warning  = { 0.860, 0.520, 0.180, 1.0 },

    taskBarAutomated = { 0.769, 0.639, 0.353, 0.92 },
    taskBarManual    = { 0.900, 0.700, 0.280, 0.92 },

    insertLine  = { 0.769, 0.639, 0.353, 0.5 },
    insertHover = { 0.769, 0.639, 0.353, 1.0 },
    insertLinePickUp  = { 0.90, 0.70, 0.28, 0.75 },
    insertHoverPickUp = { 0.97, 0.82, 0.45, 1.0 },
    insertSplitGroupLine    = { 0.28, 0.58, 0.32, 0.60 },
    insertSplitGroupHover   = { 0.36, 0.70, 0.40, 0.95 },
    insertSplitTaskLine     = { 0.42, 0.38, 0.68, 0.55 },
    insertSplitTaskHover    = { 0.54, 0.48, 0.80, 0.95 },
    insertSplitTaskDisabled = { 0.36, 0.28, 0.22, 0.40 },
}
