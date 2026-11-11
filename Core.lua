--[[
  Sightline - adaptive view distance
  ----------------------------------
  The addon API cannot ray-trace the world, so how much the player can see is
  estimated from what the client exposes (indoors, cities, instances, flying,
  underwater, resting) plus per-zone values the player teaches it.

  Each view-distance setting belongs to a visibility BAND:
    far  - terrain and horizon. Walls and buildings block these first.
    mid  - building and object detail. Partly visible between buildings.
    near - ground clutter and characters. Still visible right next to you.
  Every environment gives each band its own scale, so in a city the horizon is
  cut hard while ground clutter and nearby characters barely change.

  The player's own values (graphics menu or /console) are always the 100%
  baseline. Sightline only scales down from them and restores them on
  logout/reload so Config.wtf always keeps the player's values.
]]

local ADDON_NAME, ns = ...
ns.title = "Sightline"
ns.version = "1.0.0"

---------------------------------------------------------------------------
-- Static data
---------------------------------------------------------------------------

ns.BANDS = { "far", "mid", "near" }
ns.BAND_INFO = {
    far  = { label = "Far",  color = { 1.00, 0.82, 0.00 }, desc = "Terrain and horizon. Walls block these first." },
    mid  = { label = "Mid",  color = { 0.40, 0.75, 1.00 }, desc = "Buildings and object detail nearby." },
    near = { label = "Near", color = { 0.45, 0.90, 0.45 }, desc = "Ground clutter and characters around you." },
}

-- Known view-distance CVars. Any not present in this client are skipped.
--   menu  : true if a graphics-menu control normally drives it; false = console only.
--   floor : absolute lowest value Sightline will write.
ns.CVAR_DEFS = {
    { name = "farclip",          label = "View distance",           band = "far",  floor = 185, int = true,  menu = true  },
    { name = "horizonStart",     label = "Horizon start",           band = "far",  floor = 100, int = true,  menu = false },
    { name = "horizonClip",      label = "Horizon clip",            band = "far",  floor = 200, int = true,  menu = false },
    { name = "terrainLodDist",   label = "Terrain detail distance", band = "mid",  floor = 100, int = true,  menu = false },
    { name = "wmoLodDist",       label = "Building detail distance",band = "mid",  floor = 100, int = true,  menu = false },
    { name = "entityLodDist",    label = "Character detail",        band = "near", floor = 10,  int = false, menu = false },
    { name = "groundEffectDist", label = "Ground clutter distance", band = "near", floor = 40,  int = true,  menu = true  },
}

ns.ENVIRONMENTS = {
    { key = "open",         label = "Open world" },
    { key = "flying",       label = "Flying" },
    { key = "battleground", label = "Battlegrounds" },
    { key = "resting",      label = "Towns & inns" },
    { key = "instance",     label = "Dungeons & raids" },
    { key = "indoors",      label = "Indoors & caves" },
    { key = "underwater",   label = "Underwater" },
}

-- Capital cities: one openness value each, turned into per-band scales.
local CITY_BY_MAPID = {
    [1453] = 0.55, -- Stormwind City
    [1454] = 0.60, -- Orgrimmar
    [1455] = 0.35, -- Ironforge
    [1456] = 0.90, -- Thunder Bluff
    [1457] = 0.65, -- Darnassus
    [1458] = 0.35, -- Undercity
}
local CITY_BY_NAME = {
    ["Stormwind City"] = 0.55, ["Orgrimmar"] = 0.60, ["Ironforge"] = 0.35,
    ["Thunder Bluff"]  = 0.90, ["Darnassus"] = 0.65, ["Undercity"] = 0.35,
}

-- How much each band drops when openness falls. Far drops fully, near barely.
local BAND_SENSITIVITY = { far = 1.00, mid = 0.50, near = 0.15 }

function ns.BandsFromOpenness(o)
    local t = {}
    for band, k in pairs(BAND_SENSITIVITY) do t[band] = 1 - (1 - o) * k end
    return t
end

local DEFAULTS = {
    enabled        = true,
    minScale       = 0.30,
    tickInterval   = 0.5,
    rampDown       = 0.60,
    rampUp         = 0.50,
    writeThreshold = 0.04,
    debug          = false,
    profiles = {
        open         = { far = 1.00, mid = 1.00, near = 1.00 },
        flying       = { far = 1.00, mid = 1.00, near = 0.70 }, -- grass is hard to see from the air
        battleground = { far = 0.90, mid = 1.00, near = 1.00 },
        resting      = { far = 0.70, mid = 0.85, near = 1.00 },
        instance     = { far = 0.55, mid = 0.80, near = 1.00 },
        indoors      = { far = 0.30, mid = 0.60, near = 0.95 },
        underwater   = { far = 0.35, mid = 0.50, near = 0.80 },
    },
    cvarSettings  = {},  -- [name] = { enabled = bool, band = "far"|"mid"|"near" }
    customCVars   = {},  -- list of extra CVar names
    engineMax     = {},  -- [cvar] = highest value the game's graphics menu uses
    engineMaxTime = nil,
    previousBaselines = nil, -- player's values before "engine maximum", for undo
    setupDone     = false,
    zoneOverrides = {},  -- ["Zone|Subzone"] or ["Zone|*"] = openness 0..1
    baselines     = {},
    lastApplied   = {},
    minimap       = { hide = false, angle = 215 },
    window        = {},
    fps = {
        enabled       = false,
        target        = 60,    -- frames per second to aim for
        tolerance     = 0.10,  -- within +/-10% of target counts as "close"
        gain          = 0.05,  -- a test must improve FPS by 5% (and at least 2 fps) to count
        sampleTime    = 4,     -- seconds of FPS averaged per measurement
        settleTime    = 2.5,   -- seconds to wait after a change before measuring (terrain loading)
        step          = 0.10,  -- size of each test adjustment
        minFactor     = 0.50,  -- lowest FPS adjustment (50% of the scaled values)
        allowAbove    = false, -- may raise values above the player's own settings
        maxFactor     = 1.30,  -- highest FPS adjustment when allowAbove is on
        pauseInCombat = true,
        failCooldown  = 90,    -- seconds before retrying a direction that gave no gain
        autoCalibrate = true,  -- calibrate every subzone even without a target FPS
        minFps        = 60,    -- goal when no target FPS is set
        verifyBackground = true, -- double-check low readings with the background FPS cap off
        bkWait        = 3,     -- seconds to let FPS recover after turning the background cap off
        bkSettle      = 3,     -- seconds to let FPS settle before checking it against the background cap
        bkProbe       = 2,     -- seconds of FPS compared with the background cap
    },
    calibrations = {},         -- ["zone|subzone|env"] = { factor, fps, status, locked, ... }
}

-- How strongly the FPS adjustment applies to each band. Far settings cost the
-- most to draw and are least noticed; near settings are what you look at.
ns.FPS_WEIGHT = { far = 1.00, mid = 0.80, near = 0.60 }
ns.DEFAULTS = DEFAULTS

---------------------------------------------------------------------------
-- State shared with the GUI
---------------------------------------------------------------------------

ns.specs  = {}   -- all known CVars (defaults + custom), with player settings applied
ns.active = {}   -- specs that are enabled and exist in this client
ns.state = {
    envKey = "open", envLabel = "Open world", reason = "",
    zone = "", subzone = "",
    target  = { far = 1, mid = 1, near = 1 },
    current = { far = 1, mid = 1, near = 1 },
    applied = { far = 1, mid = 1, near = 1 },
    envBands = { far = 1, mid = 1, near = 1 }, -- before the FPS adjustment
    pending = false,
    lastWrite = 0,
    fps = {
        status = "Off", factor = 1, calibrated = false,
        sum = 0, count = 0, confirm = 0, holdUntil = 0,
        cooldownDown = 0, cooldownUp = 0,
        history = {},
    },
}

local db
local writing = false
local elapsed = 0

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Sightline:|r " .. tostring(msg))
end

local function Debug(msg)
    if db and db.debug then ns.Print("|cff999999" .. msg .. "|r") end
end

function ns.ReadCVar(name)
    local v
    if C_CVar and C_CVar.GetCVar then v = C_CVar.GetCVar(name) else v = GetCVar(name) end
    return tonumber(v)
end
local ReadCVar = ns.ReadCVar

local function WriteCVar(name, value)
    writing = true
    local ok
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, name, tostring(value))
    else
        ok = pcall(SetCVar, name, tostring(value))
    end
    writing = false
    return ok
end

local function Clamp(x, lo, hi)
    if x < lo then return lo elseif x > hi then return hi end
    return x
end

local function NearlyEqual(a, b)
    if not a or not b then return false end
    return math.abs(a - b) <= math.max(0.5, math.abs(b) * 0.005)
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns.ZoneKeys()
    local zone = GetRealZoneText() or ""
    local sub = GetSubZoneText() or ""
    return zone .. "|" .. sub, zone .. "|*", zone, sub
end

---------------------------------------------------------------------------
-- CVar discovery and baselines
---------------------------------------------------------------------------

local function BuildSpecs()
    wipe(ns.specs)
    for _, def in ipairs(ns.CVAR_DEFS) do
        local spec = {}
        for k, v in pairs(def) do spec[k] = v end
        spec.defaultBand = def.band
        table.insert(ns.specs, spec)
    end
    for _, name in ipairs(db.customCVars) do
        table.insert(ns.specs, { name = name, label = name, band = "mid", defaultBand = "mid",
                                 floor = 0, int = false, menu = false, custom = true })
    end
    for _, spec in ipairs(ns.specs) do
        local s = db.cvarSettings[spec.name]
        spec.enabled = not (s and s.enabled == false)
        if s and ns.BAND_INFO[s.band or ""] then spec.band = s.band end
        spec.exists = ReadCVar(spec.name) ~= nil
    end
end

local function DiscoverCVars()
    BuildSpecs()
    wipe(ns.active)
    for _, spec in ipairs(ns.specs) do
        if spec.enabled and spec.exists then
            table.insert(ns.active, spec)
            local current = ReadCVar(spec.name)
            local base, last = db.baselines[spec.name], db.lastApplied[spec.name]
            -- Still holding a value we wrote (e.g. after a crash)? Keep the saved
            -- baseline. Otherwise the current value is the player's own.
            if not (base and last and NearlyEqual(current, last)) then
                db.baselines[spec.name] = current
            end
            db.lastApplied[spec.name] = nil
        end
    end
    for _, b in ipairs(ns.BANDS) do ns.state.applied[b] = 1 end
end

local function CheckForUserChanges()
    for _, spec in ipairs(ns.active) do
        local current = ReadCVar(spec.name)
        local expected = db.lastApplied[spec.name] or db.baselines[spec.name]
        if current and expected and not NearlyEqual(current, expected) then
            db.baselines[spec.name] = current
            db.lastApplied[spec.name] = nil
            for _, b in ipairs(ns.BANDS) do ns.state.applied[b] = -1 end -- force rewrite
            Debug(("%s: you changed it to %s, now your 100%%"):format(spec.name, current))
        end
    end
end

function ns.RestoreBaselines()
    for _, spec in ipairs(ns.active) do
        local base = db.baselines[spec.name]
        if base then WriteCVar(spec.name, base) end
        db.lastApplied[spec.name] = nil
    end
    for _, b in ipairs(ns.BANDS) do
        ns.state.applied[b] = 1
        ns.state.current[b] = 1
    end
end

-- Call after changing which CVars are managed, their bands, or custom CVars.
function ns.RebuildCVars()
    ns.RestoreBaselines()
    DiscoverCVars()
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Engine maximum
--
-- The addon API has no way to ask for a setting's maximum, so Sightline asks
-- the game's own graphics menu: it briefly sets the menu's view distance,
-- environment detail and ground clutter to their top level, reads the values
-- the game picks for each distance setting, then puts the menu back. Where the
-- player's own value is already higher (set via the console), theirs counts
-- as the maximum.
---------------------------------------------------------------------------

local PRESETS = { "graphicsViewDistance", "graphicsEnvironmentDetail", "graphicsGroundClutter" }
local PRESET_TOP = 10

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

local function ForceRewrite()
    for _, b in ipairs(ns.BANDS) do ns.state.applied[b] = -1 end
    ns.Refresh()
end

function ns.DetectEngineMax(callback)
    if ns.busy then return end
    ns.busy = true
    ns.RestoreBaselines()

    local saved = {}
    for _, p in ipairs(PRESETS) do
        local v = ReadCVar(p)
        if v then saved[p] = v; WriteCVar(p, PRESET_TOP) end
    end

    After(1.0, function()
        local found = {}
        for _, spec in ipairs(ns.active) do
            local atTop = ReadCVar(spec.name) or 0
            found[spec.name] = math.max(atTop, db.baselines[spec.name] or 0)
        end
        for p, v in pairs(saved) do WriteCVar(p, v) end

        -- Restoring the menu can reset the distance settings to its own
        -- values, so put the player's values back afterwards.
        After(1.0, function()
            for _, spec in ipairs(ns.active) do
                local base = db.baselines[spec.name]
                if base then WriteCVar(spec.name, base) end
                db.lastApplied[spec.name] = nil
            end
            for name, v in pairs(found) do db.engineMax[name] = v end
            db.engineMaxTime = time()
            ns.busy = false
            ForceRewrite()
            if callback then callback(found) end
        end)
    end)
end

-- Make the given values the player's 100% (their "global" values).
local function SetBaselines(values)
    for _, spec in ipairs(ns.active) do
        local v = values[spec.name]
        if v then
            WriteCVar(spec.name, v)
            db.baselines[spec.name] = ReadCVar(spec.name) or v
            db.lastApplied[spec.name] = nil
        end
    end
    -- Calibrations were made against the old values.
    if ns.RecalibrateAll then ns.RecalibrateAll() end
    ForceRewrite()
end

function ns.ApplyEngineMax()
    local any = false
    for _, spec in ipairs(ns.active) do if db.engineMax[spec.name] then any = true end end
    if not any then return false end
    local prev = {}
    for _, spec in ipairs(ns.active) do prev[spec.name] = db.baselines[spec.name] end
    db.previousBaselines = prev
    SetBaselines(db.engineMax)
    return true
end

function ns.UndoEngineMax()
    if not db.previousBaselines then return false end
    SetBaselines(db.previousBaselines)
    db.previousBaselines = nil
    return true
end

-- Detect (if needed) and apply in one go, e.g. from the first-run dialog.
function ns.UseEngineMax(callback)
    ns.DetectEngineMax(function()
        ns.ApplyEngineMax()
        if callback then callback() end
    end)
end

---------------------------------------------------------------------------
-- Environment detection
---------------------------------------------------------------------------

local function EnvLabel(key)
    for _, e in ipairs(ns.ENVIRONMENTS) do if e.key == key then return e.label end end
    return key
end

local function ComputeEnvironment()
    local subKey, zoneKey, zone = ns.ZoneKeys()

    local o = db.zoneOverrides[subKey]
    if o then return "override", "Your setting (subzone)", ns.BandsFromOpenness(o) end
    o = db.zoneOverrides[zoneKey]
    if o then return "override", "Your setting (zone)", ns.BandsFromOpenness(o) end

    if IsFlying and IsFlying() then return "flying", EnvLabel("flying"), db.profiles.flying end
    if IsSubmerged and IsSubmerged() then return "underwater", EnvLabel("underwater"), db.profiles.underwater end
    if IsIndoors() then return "indoors", EnvLabel("indoors"), db.profiles.indoors end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local city = (mapID and CITY_BY_MAPID[mapID]) or CITY_BY_NAME[zone]
    if city then return "city", "Capital city", ns.BandsFromOpenness(city) end

    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "pvp" then return "battleground", EnvLabel("battleground"), db.profiles.battleground end
        return "instance", EnvLabel("instance"), db.profiles.instance
    end

    if IsResting() then return "resting", EnvLabel("resting"), db.profiles.resting end
    return "open", EnvLabel("open"), db.profiles.open
end

---------------------------------------------------------------------------
-- Scaling
---------------------------------------------------------------------------

-- Value a CVar gets for the given band scales.
function ns.ValueFor(spec, bands)
    local base = db.baselines[spec.name]
    if not base then return nil end
    local s = bands[spec.band] or 1
    local value = math.max(base * s, math.min(spec.floor or 0, base))
    if spec.int then return math.floor(value + 0.5) end
    return math.floor(value * 100 + 0.5) / 100
end

local function ApplyBands(bands)
    local values = {}
    for _, spec in ipairs(ns.active) do values[spec.name] = ns.ValueFor(spec, bands) end
    -- Keep the horizon inside the draw distance.
    if values.horizonStart and values.farclip and values.horizonStart > values.farclip then
        values.horizonStart = values.farclip
    end

    local allOk = true
    for _, spec in ipairs(ns.active) do
        local v = values[spec.name]
        if v then
            if WriteCVar(spec.name, v) then
                db.lastApplied[spec.name] = ReadCVar(spec.name) or v
            else
                allOk = false
            end
        end
    end

    ns.state.pending = not allOk
    ns.state.lastWrite = GetTime()
    if allOk then
        for _, b in ipairs(ns.BANDS) do ns.state.applied[b] = bands[b] end
        Debug(("far %.0f%%  mid %.0f%%  near %.0f%%  (%s)"):format(
            bands.far * 100, bands.mid * 100, bands.near * 100, ns.state.envLabel))
    end
end

local function NeedsWrite()
    local st = ns.state
    if st.pending then return true end
    for _, b in ipairs(ns.BANDS) do
        local diff = math.abs(st.current[b] - st.applied[b])
        if diff >= db.writeThreshold then return true end
        -- Always land exactly on the target once we've reached it.
        if diff > 0.0001 and st.current[b] == st.target[b] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- FPS calibration
--
-- Every spot (zone + subzone + environment) gets its own calibration: an
-- adjustment on top of the surroundings-based scaling, saved between sessions.
-- Goal: at least db.fps.minFps (default 60), or around db.fps.target when a
-- target FPS is set.
--
-- Entering a spot with no calibration: measure FPS, then test one step at a
-- time until FPS meets the goal or a limit is reached.
--   * a lower step is kept only if FPS rose noticeably, otherwise reverted
--   * a higher step is kept only if FPS stays at the goal, otherwise reverted
-- Calibrated spots keep being watched. If FPS falls below the goal, the spot
-- is recalibrated starting from its stored value; if that gives no real gain,
-- the stored value stays. Locked calibrations are never changed automatically.
---------------------------------------------------------------------------

local EPS = 0.001
local TRIAL_STEP = 0.10
local SETTLE_SECONDS = 2.5 -- terrain streams in after a change, so FPS right after one is noise
local RETRY_SECONDS = 90
local RECHECK_SECONDS = 3
local IN_BACKGROUND = "Paused: game in background"
local CHECKING = "Checking a low reading"

function ns.PlaceName(place)
    local name = place.zone ~= "" and place.zone or "Unknown"
    if place.subzone ~= "" then name = name .. " - " .. place.subzone end
    return name
end

local function FpsLog(msg)
    local history = ns.state.fps.history
    table.insert(history, 1, date("%H:%M") .. "  " .. ns.PlaceName(ns.state) .. ": " .. msg)
    history[13] = nil
    Debug("FPS: " .. msg)
end

local function ResetSamples()
    local fs = ns.state.fps
    fs.sum, fs.count, fs.min, fs.max = 0, 0, nil, nil
end

function ns.CalibrationActive()
    return db.enabled and (db.fps.enabled or db.fps.autoCalibrate)
end

function ns.FpsGoal()
    local f = db.fps
    if f.enabled then
        return f.target, f.target * (1 - f.tolerance), f.target * (1 + f.tolerance), "target"
    end
    return f.minFps, f.minFps * 0.97, f.minFps * (1 + f.tolerance), "minimum"
end

function ns.MaxFpsFactor()
    return db.fps.enabled and db.fps.allowAbove and db.fps.maxFactor or 1
end

function ns.FpsFactor()
    local fs = ns.state.fps
    return ns.CalibrationActive() and (fs.trial or fs.factor) or 1
end

function ns.FpsCaps()
    local function cap(value, use)
        local v = ReadCVar(value)
        if v and v > 0 and ReadCVar(use) ~= 0 then return v end
    end
    return cap("maxFPS", "useMaxFPS"), cap("maxFPSBk", "useMaxFPSBk")
end

local function AtCap(fps, cap)
    return math.abs(fps - cap) <= math.max(1.5, cap * 0.03)
end

local function Pc(x) return math.floor(x * 100 + 0.5) end

function ns.RestoreBkCap()
    local fs = ns.state.fps
    if fs.capOff then
        WriteCVar("useMaxFPSBk", 1)
        fs.capOff = nil
    end
end

local function StopTests(status)
    local fs = ns.state.fps
    fs.status, fs.trial, fs.confirm = status, nil, 0
    ns.RestoreBkCap()
    ResetSamples()
end

local function SaveCal(calStatus)
    local fs, st = ns.state.fps, ns.state
    local c = db.calibrations[fs.key]
    if not c then
        c = { zone = st.zone, subzone = st.subzone, env = st.envKey, envLabel = st.envLabel, tests = 0 }
        db.calibrations[fs.key] = c
    end
    c.factor, c.fps, c.goal = fs.factor, fs.avg, ns.FpsGoal()
    c.status, c.updated, c.pending = calStatus, time(), nil
end

local function Settle(status, calStatus)
    local fs = ns.state.fps
    StopTests(status)
    if not fs.calibrated then
        FpsLog(("calibrated at %d%% (%.0f fps)"):format(Pc(fs.factor), fs.avg))
        fs.calibrated = true
    end
    SaveCal(calStatus)
end

local function StartTrial(dir)
    local fs = ns.state.fps
    local highest = dir == "restore" and 1 or ns.MaxFpsFactor()
    fs.trialDir = dir
    fs.trial = Clamp(Pc(fs.factor + (dir == "down" and -TRIAL_STEP or TRIAL_STEP)) / 100, db.fps.minFactor, highest)
    ResetSamples()
    local verb = dir == "restore" and "Restoring" or not fs.calibrated and "Calibrating"
        or dir == "down" and "Recalibrating" or "Fine-tuning"
    fs.status = ("%s: testing %d%%"):format(verb, Pc(fs.trial))
    local c = db.calibrations[fs.key]
    if c and fs.calibrated and dir == "down" then c.status = "Recalibrating" end
end

local function FinishTrial(avg, now)
    local f, fs = db.fps, ns.state.fps
    local goal, _, _, mode = ns.FpsGoal()
    local dir, before = fs.trialDir, fs.avg
    local noticeable = math.max(2, before * f.gain)
    local kept
    if dir == "down" then
        kept = avg - before >= noticeable
    elseif dir == "restore" then
        kept = avg >= before - noticeable
    else
        kept = avg >= (mode == "minimum" and goal or goal * (1 - f.tolerance / 2))
    end

    local verb = dir == "down" and "lowered" or dir == "restore" and "restored" or "raised"
    FpsLog(("%s to %d%%: %.0f -> %.0f fps, %s"):format(verb, Pc(fs.trial), before, avg,
        kept and "kept" or ("reverted to %d%%"):format(Pc(fs.factor))))
    if kept then
        fs.factor, fs.avg = fs.trial, avg
    elseif dir == "down" then
        fs.cooldownDown = now + RETRY_SECONDS
    else
        fs.cooldownUp = now + RETRY_SECONDS
    end
    fs.trial = nil

    local c = db.calibrations[fs.key]
    if c then
        c.tests = (c.tests or 0) + 1
        if fs.calibrated then SaveCal(c.status) end
    end
end

-- A drop is measured again before anything is lowered, and once more with the background FPS
-- cap off when that cap is on: an addon cannot tell whether the game is in the background.
local function Confirmed(now)
    local fs = ns.state.fps
    if fs.confirm == 0 then
        fs.confirm = 1
    elseif fs.confirm == 1 and db.fps.verifyBackground and ReadCVar("useMaxFPSBk") == 1 then
        fs.confirm = 2
        fs.capOff = WriteCVar("useMaxFPSBk", 0)
    else
        return true
    end
    fs.status, fs.holdUntil = CHECKING, now + RECHECK_SECONDS
end

local function Decide(avg, now)
    local f, fs = db.fps, ns.state.fps
    local _, low, high = ns.FpsGoal()
    fs.avg = avg
    if avg < low then
        local atLowest = fs.factor <= f.minFactor + EPS
        if not atLowest and now >= fs.cooldownDown then
            if Confirmed(now) then StartTrial("down") end
        elseif fs.factor < 1 - EPS and now >= fs.cooldownUp then
            StartTrial("restore")
        elseif atLowest then
            Settle("Below goal, at lowest allowed", "At lowest")
        else
            Settle("Below goal, lowering didn't help", "No gain")
        end
        return
    end
    if fs.status == CHECKING then FpsLog(("drop didn't last (back to %.0f fps), no change"):format(avg)) end
    if avg > high and fs.factor < ns.MaxFpsFactor() - EPS and now >= fs.cooldownUp then
        StartTrial("up")
    elseif avg > high then
        Settle(fs.factor >= 1 - EPS and "Above goal at full distance" or "Above goal, raising cost too much", "Calibrated")
    else
        Settle("On goal", "Calibrated")
    end
end

local function EnterSpot(key)
    local fs = ns.state.fps
    local c = db.calibrations[key]
    StopTests(not c and "Calibrating" or c.locked and "Locked" or c.pending and "Recalibrating" or "Checking")
    fs.key, fs.avg, fs.holdUntil, fs.cooldownDown, fs.cooldownUp = key, nil, 0, 0, 0
    fs.factor = c and c.factor or 1
    fs.calibrated = c ~= nil and not c.pending
end

local function FpsController(now, landed)
    local f, fs, st = db.fps, ns.state.fps, ns.state
    if not ns.CalibrationActive() then
        StopTests(db.enabled and "Off" or "Paused")
        fs.key, fs.factor = nil, 1
        return
    end

    local key = st.zone .. "|" .. st.subzone .. "|" .. st.envKey
    if key ~= fs.key then EnterSpot(key) end
    local c = db.calibrations[key]
    if c and c.locked then fs.factor = c.factor end
    fs.factor = Clamp(fs.factor, f.minFactor, ns.MaxFpsFactor())

    if f.pauseInCombat and UnitAffectingCombat("player") then
        StopTests("Paused in combat")
        return
    end
    if not landed or now - st.lastWrite < SETTLE_SECONDS or now < fs.holdUntil then
        ResetSamples()
        return
    end

    local fps = GetFramerate()
    fs.sum, fs.count = fs.sum + fps, fs.count + 1
    fs.min, fs.max = math.min(fs.min or fps, fps), math.max(fs.max or fps, fps)
    if fs.count * db.tickInterval < f.sampleTime then return end

    local avg, spread = fs.sum / fs.count, fs.max - fs.min
    ResetSamples()
    local _, low = ns.FpsGoal()
    local fgCap, bgCap = ns.FpsCaps()

    if c and c.locked then
        fs.avg = avg
        StopTests("Locked")
    elseif fgCap and fgCap < low and AtCap(avg, fgCap) then
        fs.avg = avg
        StopTests("Limited by your FPS cap")
    elseif avg < low and bgCap and AtCap(avg, bgCap) and spread <= math.max(2, bgCap * 0.06) then
        if fs.status ~= IN_BACKGROUND then
            FpsLog(("holding at the background cap (%d fps): game is in the background"):format(bgCap))
        end
        StopTests(IN_BACKGROUND)
    elseif fs.trial then
        FinishTrial(avg, now)
    else
        Decide(avg, now)
    end
end

function ns.CurrentCalKey() return ns.state.fps.key end

function ns.SetCalibration(key, factor, locked)
    local c = db.calibrations[key]
    if factor then
        c.factor, c.status, c.updated = Clamp(factor, db.fps.minFactor, ns.MaxFpsFactor()), "Manual", time()
    end
    if locked ~= nil then
        c.locked = locked or nil
        if not locked and c.status == "Manual" then c.status = "Calibrated" end
    end
    if key == ns.state.fps.key then
        ns.state.fps.factor = c.factor
        StopTests(c.locked and "Locked" or "Checking")
    end
    ns.Refresh()
end

function ns.Recalibrate(key)
    local c = db.calibrations[key]
    c.pending, c.locked, c.status = true, nil, "Recalibrating"
    if key == ns.state.fps.key then ns.state.fps.key = nil end
    ns.Refresh()
end

function ns.RecalibrateAll()
    for key, c in pairs(db.calibrations) do
        if not c.locked then ns.Recalibrate(key) end
    end
end

function ns.DeleteCalibration(key)
    db.calibrations[key] = nil
    if key == ns.state.fps.key then ns.state.fps.key = nil end
    ns.Refresh()
end

function ns.ClearCalibrations()
    wipe(db.calibrations)
    ns.state.fps.key = nil
    ns.Refresh()
end

-- Band scales after the FPS adjustment.
local function ApplyFpsFactor(bands, factor)
    local out = {}
    local hi = math.max(1, ns.MaxFpsFactor())
    for _, b in ipairs(ns.BANDS) do
        local w = ns.FPS_WEIGHT[b]
        out[b] = Clamp(bands[b] * (1 - w * (1 - factor)), 0.1, hi)
    end
    return out
end

local function Tick()
    if ns.busy then return end
    local st = ns.state
    local subKey, zoneKey, zone, sub = ns.ZoneKeys()
    st.zone, st.subzone = zone, sub

    local envKey, label, bands = ComputeEnvironment()
    st.envKey, st.envLabel = envKey, label
    for _, b in ipairs(ns.BANDS) do st.envBands[b] = Clamp(bands[b] or 1, db.minScale, 1) end

    -- "Landed" = the values in use have reached their target, so FPS readings
    -- reflect the current setting rather than a transition.
    local landed = true
    for _, b in ipairs(ns.BANDS) do
        if st.current[b] ~= st.target[b] or st.applied[b] ~= st.target[b] then landed = false end
    end
    FpsController(GetTime(), landed)

    local adjusted = ApplyFpsFactor(st.envBands, ns.FpsFactor())
    for _, b in ipairs(ns.BANDS) do st.target[b] = adjusted[b] end

    if not db.enabled then return end
    CheckForUserChanges()

    for _, b in ipairs(ns.BANDS) do
        local gap = st.target[b] - st.current[b]
        local rate = gap < 0 and db.rampDown or db.rampUp
        st.current[b] = st.current[b] + gap * rate
        if math.abs(st.target[b] - st.current[b]) < 0.02 then st.current[b] = st.target[b] end
    end

    if NeedsWrite() then
        if st.pending and InCombatLockdown() then return end
        ApplyBands(st.current)
    end
end

-- Run a check now instead of waiting for the next tick.
function ns.Refresh()
    elapsed = db and db.tickInterval or 0
end

function ns.SetEnabled(on)
    db.enabled = on and true or false
    if not db.enabled then ns.RestoreBkCap(); ns.RestoreBaselines() end
    ns.Refresh()
end

function ns.SetOverride(scope, openness)
    local subKey, zoneKey = ns.ZoneKeys()
    local key = scope == "zone" and zoneKey or subKey
    db.zoneOverrides[key] = openness
    ns.Refresh()
    return key
end

function ns.ResetSettings()
    ns.RestoreBkCap()
    ns.RestoreBaselines()
    local keep = { baselines = db.baselines, minimap = db.minimap, window = db.window, calibrations = db.calibrations,
                   engineMax = db.engineMax, engineMaxTime = db.engineMaxTime,
                   previousBaselines = db.previousBaselines, setupDone = db.setupDone }
    wipe(db)
    CopyDefaults(DEFAULTS, db)
    for k, v in pairs(keep) do db[k] = v end
    DiscoverCVars()
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Frame, events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if db and elapsed >= db.tickInterval then
        elapsed = 0
        Tick()
    end
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
                     "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
                     "PLAYER_REGEN_ENABLED", "CVAR_UPDATE" }) do
    frame:RegisterEvent(e)
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        SightlineDB = CopyDefaults(DEFAULTS, SightlineDB or {})
        db = SightlineDB
        ns.db = db

    elseif event == "PLAYER_LOGIN" then
        if db.bkRestore then ns.RestoreBkCap() end -- left off by a crash mid-check
        DiscoverCVars()
        if ns.OnLogin then ns.OnLogin() end

    elseif event == "PLAYER_LOGOUT" then
        ns.RestoreBkCap()
        ns.RestoreBaselines()

    elseif event == "CVAR_UPDATE" then
        if not writing then ns.Refresh() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Loading screens tank FPS for a moment; don't measure through them.
        ns.state.lastWrite = GetTime()
        ns.Refresh()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.state.pending then ApplyBands(ns.state.current) end

    else
        ns.Refresh()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_SIGHTLINE1 = "/sightline"
SLASH_SIGHTLINE2 = "/sight"
SlashCmdList["SIGHTLINE"] = function(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        if ns.ToggleWindow then ns.ToggleWindow() end
    elseif cmd == "on" then
        ns.SetEnabled(true); ns.Print("enabled")
    elseif cmd == "off" then
        ns.SetEnabled(false); ns.Print("paused - your settings are restored")
    elseif cmd == "here" or cmd == "zone" then
        if arg == "clear" then
            ns.Print("override cleared for " .. ns.SetOverride(cmd, nil))
        else
            local n = tonumber(arg)
            if n and n >= 0 and n <= 100 then
                ns.Print(("%s set to %d%% openness"):format(ns.SetOverride(cmd, n / 100), n))
            else
                ns.Print("usage: /sight " .. cmd .. " <0-100> | clear")
            end
        end
    elseif cmd == "fps" then
        local n = tonumber(arg)
        if arg == "off" then
            db.fps.enabled = false; ns.Print("target FPS off")
        elseif n and n >= 15 and n <= 360 then
            db.fps.enabled = true; db.fps.target = n; ns.Print(("target FPS set to %d"):format(n))
        else
            ns.Print("usage: /sight fps <15-360> | off")
        end
        ns.Refresh()
    elseif cmd == "minimap" then
        db.minimap.hide = not db.minimap.hide
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    elseif cmd == "debug" then
        db.debug = not db.debug; ns.Print("debug " .. (db.debug and "on" or "off"))
    else
        ns.Print("/sight - open the window | on | off | fps <15-360>|off | here <0-100>|clear | zone <0-100>|clear | minimap | debug")
    end
end
