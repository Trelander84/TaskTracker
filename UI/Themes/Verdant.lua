-- UI/Themes/Verdant.lua
-- Pine canopy: objective-tracker fonts, 2px edge, green-tinted zebra.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["verdant"] = {
    name = "Verdant",
    key  = "verdant",

    bg        = { 0.047, 0.078, 0.055, 0.98 },  -- #0C1410
    panelBg   = { 0.063, 0.098, 0.071, 0.98 },
    headerBg  = { 0.086, 0.133, 0.094, 1.0  },
    headerBg2 = { 0.110, 0.165, 0.118, 1.0  },
    headerBg3 = { 0.071, 0.173, 0.114, 1.0  },  -- pine wash — Collections
    headerBgHere = { 0.140, 0.280, 0.150, 1.0 },  -- current zone
    rowEven   = { 0.078, 0.122, 0.086, 1.0  },
    rowOdd    = { 0.055, 0.090, 0.063, 1.0  },
    rowHover  = { 0.133, 0.196, 0.125, 1.0  },
    inputBg   = { 0.031, 0.055, 0.039, 1.0  },

    border      = { 0.280, 0.460, 0.300, 1.0 },
    borderLight = { 0.380, 0.560, 0.390, 1.0 },

    accent    = { 0.486, 0.702, 0.259, 1.0 },  -- #7CB342
    accentDim = { 0.330, 0.500, 0.170, 1.0 },
    accentBg  = { 0.486, 0.702, 0.259, 0.40 },

    textPrimary   = { 0.910, 0.941, 0.894, 1.0 },
    textSecondary = { 0.580, 0.680, 0.560, 1.0 },
    textDim       = { 0.360, 0.440, 0.350, 1.0 },
    textAccent    = { 0.620, 0.820, 0.380, 1.0 },
    textWarm      = { 0.910, 0.941, 0.894, 1.0 },
    textHeader    = { 0.620, 0.820, 0.380, 1.0 },
    textTask      = { 0.880, 0.920, 0.860, 1.0 },
    textRegistry  = { 0.910, 0.941, 0.894, 1.0 },

    complete = { 0.420, 0.820, 0.400, 1.0 },
    override = { 0.920, 0.760, 0.280, 1.0 },
    danger   = { 0.860, 0.280, 0.220, 1.0 },
    warning  = { 0.900, 0.620, 0.180, 1.0 },

    taskBarAutomated = { 0.486, 0.702, 0.259, 0.92 },
    taskBarManual    = { 0.920, 0.760, 0.280, 0.92 },

    insertLine  = { 0.486, 0.702, 0.259, 0.5 },
    insertHover = { 0.486, 0.702, 0.259, 1.0 },
    insertLinePickUp  = { 0.92, 0.76, 0.28, 0.75 },
    insertHoverPickUp = { 0.97, 0.86, 0.42, 1.0 },
    insertSplitGroupLine    = { 0.35, 0.78, 0.48, 0.55 },
    insertSplitGroupHover   = { 0.45, 0.88, 0.56, 0.95 },
    insertSplitTaskLine     = { 0.55, 0.70, 0.35, 0.55 },
    insertSplitTaskHover    = { 0.68, 0.82, 0.42, 0.95 },
    insertSplitTaskDisabled = { 0.28, 0.34, 0.28, 0.35 },
}
