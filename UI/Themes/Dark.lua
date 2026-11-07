-- UI/Themes/Dark.lua
-- Dark teal theme for TaskTracker

TaskTracker         = TaskTracker or {}
TaskTracker.Themes  = TaskTracker.Themes or {}

TaskTracker.Themes["dark"] = {
    name        = "Dark",
    key         = "dark",

    -- ─────────────────────────────────
    -- Backgrounds
    -- ─────────────────────────────────
    bg          = { 0.051, 0.051, 0.051, 0.98 },  -- #0D0D0D
    panelBg     = { 0.078, 0.078, 0.078, 0.98 },  -- #141414
    headerBg    = { 0.102, 0.102, 0.102, 1.0  },  -- #1A1A1A
    headerBg2   = { 0.118, 0.118, 0.118, 1.0  },  -- #1E1E1E sub headers
    headerBg3   = { 0.055, 0.145, 0.165, 1.0  },  -- teal wash — Collections
    headerBgHere = { 0.070, 0.310, 0.350, 1.0  },  -- current zone
    rowEven     = { 0.086, 0.086, 0.086, 1.0  },  -- #161616
    rowOdd      = { 0.071, 0.071, 0.071, 1.0  },  -- #121212
    rowHover    = { 0.118, 0.118, 0.118, 1.0  },  -- #1E1E1E
    inputBg     = { 0.059, 0.059, 0.059, 1.0  },  -- #0F0F0F

    -- ─────────────────────────────────
    -- Borders
    -- ─────────────────────────────────
    border      = { 0.165, 0.165, 0.165, 1.0  },  -- #2A2A2A
    borderLight = { 0.220, 0.220, 0.220, 1.0  },  -- #383838

    -- ─────────────────────────────────
    -- Accent
    -- ─────────────────────────────────
    accent      = { 0.000, 0.737, 0.831, 1.0  },  -- #00BCD4
    accentDim   = { 0.000, 0.478, 0.537, 1.0  },  -- #007A89
    -- Same RGB as title / textAccent so active & hover reads clearly (was very faint alpha).
    accentBg    = { 0.000, 0.737, 0.831, 0.42 },

    -- ─────────────────────────────────
    -- Text
    -- ─────────────────────────────────
    textPrimary   = { 0.878, 0.878, 0.878, 1.0 },  -- #E0E0E0
    textSecondary = { 0.533, 0.533, 0.533, 1.0 },  -- #888888
    textDim       = { 0.267, 0.267, 0.267, 1.0 },  -- #444444
    textAccent    = { 0.000, 0.737, 0.831, 1.0 },  -- teal
    textWarm      = { 0.831, 0.788, 0.690, 1.0 },  -- #D4C9B0
    textHeader    = { 0.000, 0.737, 0.831, 1.0 },  -- teal headers
    textTask      = { 0.831, 0.788, 0.690, 1.0 },  -- warm for tasks
    textRegistry  = { 0.878, 0.878, 0.878, 1.0 },  -- light for registry

    -- ─────────────────────────────────
    -- Status
    -- ─────────────────────────────────
    complete    = { 0.290, 0.871, 0.502, 1.0 },  -- vivid green (#4ADE80) — reads clearly on dark/cyan UI
    override    = { 1.000, 0.757, 0.027, 1.0 },  -- #FFC107
    danger      = { 0.957, 0.263, 0.212, 1.0 },  -- #F44336
    warning     = { 1.000, 0.596, 0.000, 1.0 },  -- #FF9800

    -- Task list: automation indicator (left of checkbox)
    taskBarAutomated = { 0.000, 0.737, 0.831, 0.92 },  -- cyan / teal
    taskBarManual    = { 1.000, 0.757, 0.027, 0.92 },  -- amber yellow

    -- ─────────────────────────────────
    -- Insert zone
    -- ─────────────────────────────────
    insertLine  = { 0.000, 0.737, 0.831, 0.5 },
    insertHover = { 0.000, 0.737, 0.831, 1.0 },
    -- Pick-up reorder mode (insert lines use these instead of cyan)
    insertLinePickUp  = { 0.95, 0.82, 0.38, 0.75 },
    insertHoverPickUp = { 1.00, 0.92, 0.55, 1.0 },
    -- Split insert / add strip (not gold — reserved for reorder drop targets)
    insertSplitGroupLine    = { 0.35, 0.82, 0.50, 0.55 },
    insertSplitGroupHover   = { 0.45, 0.92, 0.58, 0.95 },
    insertSplitTaskLine     = { 0.62, 0.48, 0.95, 0.55 },
    insertSplitTaskHover    = { 0.72, 0.58, 1.00, 0.95 },
    insertSplitTaskDisabled = { 0.35, 0.35, 0.40, 0.35 },
}