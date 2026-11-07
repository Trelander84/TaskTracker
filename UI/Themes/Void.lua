-- UI/Themes/Void.lua
-- Deep void-purple overlay. Friends-list fonts, wide accent rail, tinted zebra.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["void"] = {
    name = "Void",
    key  = "void",

    bg        = { 0.071, 0.031, 0.094, 0.98 },  -- #120818
    panelBg   = { 0.094, 0.043, 0.125, 0.98 },
    headerBg  = { 0.133, 0.055, 0.180, 1.0  },
    headerBg2 = { 0.165, 0.071, 0.220, 1.0  },
    headerBg3 = { 0.145, 0.047, 0.220, 1.0  },  -- deeper void — Collections
    headerBgHere = { 0.280, 0.100, 0.380, 1.0 },  -- current zone
    rowEven   = { 0.110, 0.047, 0.149, 1.0  },
    rowOdd    = { 0.082, 0.035, 0.114, 1.0  },
    rowHover  = { 0.200, 0.078, 0.275, 1.0  },
    inputBg   = { 0.047, 0.020, 0.067, 1.0  },

    border      = { 0.420, 0.220, 0.560, 1.0 },
    borderLight = { 0.540, 0.320, 0.700, 1.0 },

    accent    = { 0.765, 0.333, 1.000, 1.0 },  -- #C355FF
    accentDim = { 0.510, 0.180, 0.720, 1.0 },
    accentBg  = { 0.765, 0.333, 1.000, 0.40 },

    textPrimary   = { 0.930, 0.880, 0.980, 1.0 },
    textSecondary = { 0.680, 0.560, 0.800, 1.0 },
    textDim       = { 0.420, 0.320, 0.500, 1.0 },
    textAccent    = { 0.820, 0.520, 1.000, 1.0 },
    textWarm      = { 0.930, 0.880, 0.980, 1.0 },
    textHeader    = { 0.820, 0.520, 1.000, 1.0 },
    textTask      = { 0.900, 0.850, 0.960, 1.0 },
    textRegistry  = { 0.930, 0.880, 0.980, 1.0 },

    complete = { 0.420, 0.860, 0.720, 1.0 },
    override = { 1.000, 0.780, 0.360, 1.0 },
    danger   = { 0.960, 0.280, 0.420, 1.0 },
    warning  = { 1.000, 0.560, 0.280, 1.0 },

    taskBarAutomated = { 0.765, 0.333, 1.000, 0.92 },
    taskBarManual    = { 1.000, 0.780, 0.360, 0.92 },

    insertLine  = { 0.765, 0.333, 1.000, 0.5 },
    insertHover = { 0.765, 0.333, 1.000, 1.0 },
    insertLinePickUp  = { 1.00, 0.78, 0.36, 0.75 },
    insertHoverPickUp = { 1.00, 0.88, 0.52, 1.0 },
    insertSplitGroupLine    = { 0.30, 0.78, 0.62, 0.55 },
    insertSplitGroupHover   = { 0.40, 0.90, 0.72, 0.95 },
    insertSplitTaskLine     = { 0.90, 0.40, 0.70, 0.55 },
    insertSplitTaskHover    = { 1.00, 0.52, 0.80, 0.95 },
    insertSplitTaskDisabled = { 0.32, 0.22, 0.38, 0.35 },
}
