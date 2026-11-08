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
    far  = { label = "Far",  color = { 1.00, 0.82, 0.00 }, desc = "Terrain and horizon. Walls and buildings block these first." },
    mid  = { label = "Mid",  color = { 0.40, 0.75, 1.00 }, desc = "Building and object detail. Partly visible between buildings." },
    near = { label = "Near", color = { 0.45, 0.90, 0.45 }, desc = "Ground clutter and characters. Still visible right beside you." },
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
    zoneOverrides = {},  -- ["Zone|Subzone"] or ["Zone|*"] = openness 0..1
    baselines     = {},
    lastApplied   = {},
    minimap       = { hide = false, angle = 215 },
    window        = {},
}
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
    pending = false,
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

local function Tick()
    local st = ns.state
    local subKey, zoneKey, zone, sub = ns.ZoneKeys()
    st.zone, st.subzone = zone, sub

    local envKey, label, bands = ComputeEnvironment()
    st.envKey, st.envLabel = envKey, label
    for _, b in ipairs(ns.BANDS) do st.target[b] = Clamp(bands[b] or 1, db.minScale, 1) end

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
    if not db.enabled then ns.RestoreBaselines() end
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
    ns.RestoreBaselines()
    local keep = { baselines = db.baselines, minimap = db.minimap, window = db.window }
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
        DiscoverCVars()
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)
        if loaded and loaded("OcclusionViewDistance") then
            ns.Print("|cffff4040The old OcclusionViewDistance addon is still enabled. Disable or delete it, or the two will fight over your settings.|r")
        end
        if ns.OnLogin then ns.OnLogin() end

    elseif event == "PLAYER_LOGOUT" then
        ns.RestoreBaselines()

    elseif event == "CVAR_UPDATE" then
        if not writing then ns.Refresh() end

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
    elseif cmd == "minimap" then
        db.minimap.hide = not db.minimap.hide
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    elseif cmd == "debug" then
        db.debug = not db.debug; ns.Print("debug " .. (db.debug and "on" or "off"))
    else
        ns.Print("/sight - open the window | on | off | here <0-100>|clear | zone <0-100>|clear | minimap | debug")
    end
end
