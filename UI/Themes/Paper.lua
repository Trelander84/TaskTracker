-- UI/Themes/Paper.lua
-- High-contrast light: larger highlight fonts, extra padding, strong zebra.

TaskTracker        = TaskTracker or {}
TaskTracker.Themes = TaskTracker.Themes or {}

TaskTracker.Themes["paper"] = {
    name = "Paper",
    key  = "paper",

    bg        = { 0.980, 0.980, 0.976, 1.0 },  -- #FAFAF9
    panelBg   = { 1.000, 1.000, 1.000, 1.0 },
    headerBg  = { 0.910, 0.922, 0.941, 1.0 },
    headerBg2 = { 0.875, 0.894, 0.922, 1.0 },
    headerBg3 = { 0.820, 0.855, 0.925, 1.0 },  -- indigo wash — Collections
    headerBgHere = { 0.700, 0.800, 0.920, 1.0 },  -- current zone
    rowEven   = { 0.941, 0.945, 0.953, 1.0 },
    rowOdd    = { 1.000, 1.000, 1.000, 1.0 },
    rowHover  = { 0.850, 0.900, 0.980, 1.0 },
    inputBg   = { 1.000, 1.000, 1.000, 1.0 },

    border      = { 0.220, 0.240, 0.280, 1.0 },
    borderLight = { 0.420, 0.450, 0.500, 1.0 },

    accent    = { 0.082, 0.396, 0.753, 1.0 },  -- #1565C0
    accentDim = { 0.051, 0.278, 0.561, 1.0 },
    accentBg  = { 0.082, 0.396, 0.753, 0.28 },

    textPrimary   = { 0.067, 0.067, 0.078, 1.0 },
    textSecondary = { 0.330, 0.345, 0.380, 1.0 },
    textDim       = { 0.520, 0.535, 0.560, 1.0 },
    textAccent    = { 0.051, 0.278, 0.561, 1.0 },
    textWarm      = { 0.067, 0.067, 0.078, 1.0 },
    textHeader    = { 0.051, 0.278, 0.561, 1.0 },
    textTask      = { 0.040, 0.040, 0.050, 1.0 },
    textRegistry  = { 0.040, 0.040, 0.050, 1.0 },

    complete = { 0.090, 0.490, 0.275, 1.0 },
    override = { 0.700, 0.430, 0.020, 1.0 },
    danger   = { 0.720, 0.110, 0.110, 1.0 },
    warning  = { 0.780, 0.400, 0.040, 1.0 },

    taskBarAutomated = { 0.082, 0.396, 0.753, 0.92 },
    taskBarManual    = { 0.820, 0.480, 0.060, 0.92 },

    insertLine  = { 0.082, 0.396, 0.753, 0.45 },
    insertHover = { 0.082, 0.396, 0.753, 1.0 },
    insertLinePickUp  = { 0.78, 0.48, 0.08, 0.70 },
    insertHoverPickUp = { 0.62, 0.36, 0.04, 1.0 },
    insertSplitGroupLine    = { 0.10, 0.50, 0.28, 0.60 },
    insertSplitGroupHover   = { 0.14, 0.60, 0.34, 0.95 },
    insertSplitTaskLine     = { 0.20, 0.35, 0.70, 0.55 },
    insertSplitTaskHover    = { 0.28, 0.45, 0.82, 0.95 },
    insertSplitTaskDisabled = { 0.62, 0.64, 0.68, 0.40 },
}
