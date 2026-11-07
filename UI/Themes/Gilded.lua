-- UI/Themes/Gilded.lua
-- Tight dark overlay with an amber accent. Was Compact.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["gilded"] = {
    name = "Gilded",
    key  = "gilded",

    bg        = { 0.039, 0.039, 0.039, 0.96 },  -- #0A0A0A
    panelBg   = { 0.055, 0.055, 0.055, 0.96 },
    headerBg  = { 0.078, 0.078, 0.078, 1.0  },
    headerBg2 = { 0.094, 0.094, 0.094, 1.0  },
    headerBg3 = { 0.071, 0.118, 0.125, 1.0  },  -- teal wash — Collections
    headerBgHere = { 0.280, 0.180, 0.050, 1.0 },  -- current zone
    rowEven   = { 0.051, 0.051, 0.051, 1.0  },
    rowOdd    = { 0.047, 0.047, 0.047, 1.0  },
    rowHover  = { 0.110, 0.090, 0.055, 1.0  },
    inputBg   = { 0.027, 0.027, 0.027, 1.0  },

    border      = { 0.220, 0.220, 0.220, 1.0 },
    borderLight = { 0.310, 0.310, 0.310, 1.0 },

    accent    = { 1.000, 0.690, 0.125, 1.0 },  -- #FFB020
    accentDim = { 0.720, 0.480, 0.060, 1.0 },
    accentBg  = { 1.000, 0.690, 0.125, 0.38 },

    textPrimary   = { 0.910, 0.910, 0.910, 1.0 },
    textSecondary = { 0.560, 0.560, 0.560, 1.0 },
    textDim       = { 0.320, 0.320, 0.320, 1.0 },
    textAccent    = { 1.000, 0.690, 0.125, 1.0 },
    textWarm      = { 0.910, 0.910, 0.910, 1.0 },
    textHeader    = { 1.000, 0.690, 0.125, 1.0 },
    textTask      = { 0.880, 0.880, 0.880, 1.0 },
    textRegistry  = { 0.910, 0.910, 0.910, 1.0 },

    complete = { 0.400, 0.850, 0.450, 1.0 },
    override = { 1.000, 0.820, 0.280, 1.0 },
    danger   = { 0.950, 0.280, 0.220, 1.0 },
    warning  = { 1.000, 0.620, 0.150, 1.0 },

    taskBarAutomated = { 1.000, 0.690, 0.125, 0.92 },
    taskBarManual    = { 0.950, 0.550, 0.150, 0.92 },

    insertLine  = { 1.000, 0.690, 0.125, 0.5 },
    insertHover = { 1.000, 0.690, 0.125, 1.0 },
    insertLinePickUp  = { 0.95, 0.78, 0.35, 0.75 },
    insertHoverPickUp = { 1.00, 0.88, 0.50, 1.0 },
    insertSplitGroupLine    = { 0.30, 0.78, 0.42, 0.50 },
    insertSplitGroupHover   = { 0.40, 0.88, 0.52, 0.95 },
    insertSplitTaskLine     = { 0.45, 0.55, 0.90, 0.50 },
    insertSplitTaskHover    = { 0.55, 0.65, 1.00, 0.95 },
    insertSplitTaskDisabled = { 0.30, 0.30, 0.32, 0.35 },
}
