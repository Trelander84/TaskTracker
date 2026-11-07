-- UI/Themes/Nord.lua
-- Cool polar-night palette (Nord / Arctic Ice Studio). Frost accent, snow text.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["nord"] = {
    name = "Nord",
    key  = "nord",

    -- Polar Night surfaces, slightly darkened for an overlay panel.
    bg        = { 0.145, 0.165, 0.204, 0.98 },  -- #252A34
    panelBg   = { 0.180, 0.204, 0.251, 0.98 },  -- #2E3440
    headerBg  = { 0.231, 0.259, 0.322, 1.0  },  -- #3B4252
    headerBg2 = { 0.263, 0.298, 0.369, 1.0  },  -- #434C5E
    headerBg3 = { 0.220, 0.310, 0.400, 1.0  },  -- frost wash — Collections
    headerBgHere = { 0.300, 0.420, 0.480, 1.0 },  -- current zone
    rowEven   = { 0.196, 0.220, 0.271, 1.0  },
    rowOdd    = { 0.165, 0.188, 0.235, 1.0  },
    rowHover  = { 0.263, 0.298, 0.369, 1.0  },
    inputBg   = { 0.125, 0.145, 0.184, 1.0  },

    border      = { 0.298, 0.337, 0.416, 1.0 },  -- #4C566A
    borderLight = { 0.369, 0.416, 0.506, 1.0 },

    -- Frost
    accent    = { 0.533, 0.753, 0.816, 1.0 },  -- #88C0D0
    accentDim = { 0.369, 0.506, 0.675, 1.0 },  -- #5E81AC
    accentBg  = { 0.533, 0.753, 0.816, 0.42 },

    -- Snow Storm
    textPrimary   = { 0.898, 0.914, 0.941, 1.0 },  -- #E5E9F0
    textSecondary = { 0.506, 0.631, 0.757, 1.0 },  -- #81A1C1
    textDim       = { 0.420, 0.475, 0.545, 1.0 },
    textAccent    = { 0.533, 0.753, 0.816, 1.0 },
    textWarm      = { 0.847, 0.871, 0.914, 1.0 },  -- #D8DEE9
    textHeader    = { 0.533, 0.753, 0.816, 1.0 },
    textTask      = { 0.847, 0.871, 0.914, 1.0 },
    textRegistry  = { 0.898, 0.914, 0.941, 1.0 },

    -- Aurora
    complete = { 0.639, 0.745, 0.549, 1.0 },  -- #A3BE8C
    override = { 0.922, 0.796, 0.545, 1.0 },  -- #EBCB8B
    danger   = { 0.749, 0.380, 0.416, 1.0 },  -- #BF616A
    warning  = { 0.816, 0.529, 0.439, 1.0 },  -- #D08770

    taskBarAutomated = { 0.533, 0.753, 0.816, 0.92 },
    taskBarManual    = { 0.922, 0.796, 0.545, 0.92 },

    insertLine  = { 0.533, 0.753, 0.816, 0.5 },
    insertHover = { 0.533, 0.753, 0.816, 1.0 },
    insertLinePickUp  = { 0.922, 0.796, 0.545, 0.75 },
    insertHoverPickUp = { 0.957, 0.875, 0.655, 1.0 },
    insertSplitGroupLine    = { 0.639, 0.745, 0.549, 0.55 },
    insertSplitGroupHover   = { 0.720, 0.820, 0.630, 0.95 },
    insertSplitTaskLine     = { 0.706, 0.557, 0.678, 0.55 },  -- #B48EAD
    insertSplitTaskHover    = { 0.800, 0.655, 0.770, 0.95 },
    insertSplitTaskDisabled = { 0.35, 0.38, 0.45, 0.35 },
}
