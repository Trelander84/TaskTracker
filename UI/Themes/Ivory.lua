-- UI/Themes/Ivory.lua
-- Cool light surfaces with indigo accent (Linear / Notion-style). Complements warm Parchment.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["ivory"] = {
    name = "Ivory",
    key  = "ivory",

    bg        = { 0.953, 0.945, 0.925, 1.0 },  -- #F3F1EC
    panelBg   = { 0.969, 0.961, 0.945, 1.0 },
    headerBg  = { 0.910, 0.898, 0.870, 1.0 },
    headerBg2 = { 0.886, 0.875, 0.847, 1.0 },
    headerBg3 = { 0.850, 0.840, 0.890, 1.0 },  -- indigo wash — Collections
    headerBgHere = { 0.720, 0.720, 0.900, 1.0 },  -- current zone
    rowEven   = { 0.941, 0.933, 0.914, 1.0 },
    rowOdd    = { 0.969, 0.961, 0.945, 1.0 },
    rowHover  = { 0.875, 0.870, 0.910, 1.0 },  -- slight indigo wash
    inputBg   = { 0.988, 0.984, 0.973, 1.0 },

    border      = { 0.690, 0.655, 0.580, 1.0 },
    borderLight = { 0.780, 0.745, 0.675, 1.0 },

    accent    = { 0.357, 0.357, 0.839, 1.0 },  -- #5B5BD6
    accentDim = { 0.275, 0.275, 0.651, 1.0 },
    accentBg  = { 0.357, 0.357, 0.839, 0.32 },

    textPrimary   = { 0.133, 0.122, 0.110, 1.0 },  -- #221F1C
    textSecondary = { 0.420, 0.400, 0.365, 1.0 },
    textDim       = { 0.560, 0.535, 0.490, 1.0 },
    textAccent    = { 0.275, 0.275, 0.651, 1.0 },  -- darker indigo on light
    textWarm      = { 0.133, 0.122, 0.110, 1.0 },
    textHeader    = { 0.275, 0.275, 0.651, 1.0 },
    textTask      = { 0.110, 0.098, 0.086, 1.0 },
    textRegistry  = { 0.110, 0.098, 0.086, 1.0 },

    complete = { 0.133, 0.525, 0.310, 1.0 },
    override = { 0.720, 0.470, 0.040, 1.0 },
    danger   = { 0.720, 0.180, 0.180, 1.0 },
    warning  = { 0.780, 0.450, 0.080, 1.0 },

    taskBarAutomated = { 0.357, 0.357, 0.839, 0.92 },
    taskBarManual    = { 0.820, 0.520, 0.080, 0.92 },

    insertLine  = { 0.357, 0.357, 0.839, 0.45 },
    insertHover = { 0.357, 0.357, 0.839, 1.0 },
    insertLinePickUp  = { 0.78, 0.52, 0.10, 0.70 },
    insertHoverPickUp = { 0.62, 0.38, 0.06, 1.0 },
    insertSplitGroupLine    = { 0.12, 0.48, 0.28, 0.60 },
    insertSplitGroupHover   = { 0.16, 0.58, 0.34, 0.95 },
    insertSplitTaskLine     = { 0.40, 0.32, 0.70, 0.55 },
    insertSplitTaskHover    = { 0.48, 0.40, 0.80, 0.95 },
    insertSplitTaskDisabled = { 0.62, 0.58, 0.52, 0.40 },
}
