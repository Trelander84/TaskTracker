-- UI/Themes/Parchment.lua
-- Warm parchment theme for TaskTracker

TaskTracker         = TaskTracker or {}
TaskTracker.Themes  = TaskTracker.Themes or {}

TaskTracker.Themes["parchment"] = {
    name        = "Parchment",
    key         = "parchment",

    -- ─────────────────────────────────
    -- Backgrounds
    -- ─────────────────────────────────
    bg          = { 0.780, 0.733, 0.620, 1.0  },  -- warm tan
    panelBg     = { 0.800, 0.757, 0.643, 1.0  },
    headerBg    = { 0.718, 0.667, 0.545, 1.0  },  -- darker tan for headers
    headerBg2   = { 0.749, 0.702, 0.584, 1.0  },  -- mid tan sub headers
    headerBg3   = { 0.690, 0.612, 0.455, 1.0  },  -- darker ink wash — Collections
    headerBgHere = { 0.780, 0.620, 0.340, 1.0  },  -- current zone
    rowEven     = { 0.792, 0.749, 0.635, 1.0  },
    rowOdd      = { 0.812, 0.769, 0.655, 1.0  },
    rowHover    = { 0.690, 0.643, 0.525, 1.0  },
    inputBg     = { 0.859, 0.820, 0.714, 1.0  },

    -- ─────────────────────────────────
    -- Borders
    -- ─────────────────────────────────
    border      = { 0.459, 0.361, 0.200, 1.0  },  -- warm brown
    borderLight = { 0.557, 0.447, 0.271, 1.0  },

    -- ─────────────────────────────────
    -- Accent
    -- ─────────────────────────────────
    accent      = { 0.600, 0.420, 0.020, 1.0  },  -- rich gold
    accentDim   = { 0.459, 0.318, 0.012, 1.0  },
    -- Same RGB as title / textAccent so active & hover reads clearly.
    accentBg    = { 0.600, 0.420, 0.020, 0.42 },

    -- ─────────────────────────────────
    -- Text
    -- ─────────────────────────────────
    textPrimary   = { 0.180, 0.110, 0.040, 1.0 },  -- very dark brown
    textSecondary = { 0.380, 0.270, 0.120, 1.0 },  -- medium brown
    textDim       = { 0.520, 0.420, 0.260, 1.0 },  -- light brown
    textAccent    = { 0.600, 0.420, 0.020, 1.0 },  -- gold
    textWarm      = { 0.180, 0.110, 0.040, 1.0 },
    textHeader    = { 0.600, 0.420, 0.020, 1.0 },  -- gold headers
    textTask      = { 0.150, 0.090, 0.030, 1.0 },  -- darkest brown for tasks
    textRegistry  = { 0.150, 0.090, 0.030, 1.0 },

    -- ─────────────────────────────────
    -- Status
    -- ─────────────────────────────────
    complete    = { 0.180, 0.580, 0.260, 1.0 },  -- forest green (brighter than prior for done rows / counts)
    override    = { 0.700, 0.450, 0.000, 1.0 },  -- amber
    danger      = { 0.550, 0.100, 0.100, 1.0 },  -- dark red
    warning     = { 0.650, 0.380, 0.000, 1.0 },

    -- Task list: automation indicator (cool teal vs warm amber on parchment)
    taskBarAutomated = { 0.10, 0.42, 0.48, 1.0 },
    taskBarManual    = { 0.78, 0.48, 0.06, 1.0 },

    -- ─────────────────────────────────
    -- Insert zone
    -- ─────────────────────────────────
    insertLine  = { 0.600, 0.420, 0.020, 0.5 },
    insertHover = { 0.600, 0.420, 0.020, 1.0 },
    insertLinePickUp  = { 0.72, 0.48, 0.10, 0.75 },
    insertHoverPickUp = { 0.55, 0.35, 0.06, 1.0 },
    -- Split insert / add strip (avoid theme gold — that reads as reorder)
    insertSplitGroupLine    = { 0.12, 0.42, 0.22, 0.65 },
    insertSplitGroupHover   = { 0.18, 0.55, 0.30, 0.95 },
    insertSplitTaskLine     = { 0.22, 0.38, 0.62, 0.65 },
    insertSplitTaskHover    = { 0.30, 0.48, 0.75, 0.95 },
    insertSplitTaskDisabled = { 0.50, 0.45, 0.38, 0.40 },
}