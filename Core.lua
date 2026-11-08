--[[
  Occlusion View Distance
  -----------------------
  The addon API cannot ray-trace the world, so "what the player can see" is
  estimated from what the client exposes: indoors/outdoors, cities, instances,
  flying, underwater, resting, plus per-zone overrides the player can teach it.

  The player's own CVar values (set in the graphics menu or via /console) are
  treated as the 100% baseline. The addon only ever scales DOWN from them, and
  restores them on logout/reload so Config.wtf always keeps the player's values.
]]

local ADDON_NAME = ...
local OVD = CreateFrame("Frame", "OcclusionViewDistanceFrame")

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

-- CVars to manage. Any that don't exist in this client are skipped at runtime.
--   weight : how strongly this CVar follows the openness scale (1 = fully,
--            0.5 = only drops half as much). Lower for detail/LOD settings so
--            nearby things don't visibly pop.
--   floor  : absolute lowest value the addon will ever set.
--   int    : write as an integer.
local CVAR_SPECS = {
    { name = "farclip",          weight = 1.00, floor = 185, int = true  },
    { name = "horizonStart",     weight = 1.00, floor = 100, int = true  },
    { name = "horizonClip",      weight = 1.00, floor = 200, int = true  },
    { name = "groundEffectDist", weight = 0.70, floor = 40,  int = true  },
    { name = "entityLodDist",    weight = 0.50, floor = 10,  int = false },
    { name = "terrainLodDist",   weight = 0.50, floor = 100, int = true  },
    { name = "wmoLodDist",       weight = 0.50, floor = 100, int = true  },
}

-- Openness (0..1) for known environments.
local OPENNESS = {
    flying     = 1.00,
    open       = 1.00,
    battleground = 0.90,
    instance   = 0.55, -- outdoor parts of dungeons/raids
    resting    = 0.70, -- towns/inns that aren't a known capital
    indoors    = 0.30, -- buildings, caves, tunnels (WMO interiors)
    underwater = 0.35, -- water fog limits sight anyway
}

-- Capital cities (Classic uiMapIDs). Values reflect how built-up they are.
local CITY_BY_MAPID = {
    [1453] = 0.55, -- Stormwind City
    [1454] = 0.60, -- Orgrimmar
    [1455] = 0.35, -- Ironforge
    [1456] = 0.90, -- Thunder Bluff (open mesas)
    [1457] = 0.65, -- Darnassus
    [1458] = 0.35, -- Undercity
}
-- Fallback by English zone name, in case Forever uses different map IDs.
local CITY_BY_NAME = {
    ["Stormwind City"] = 0.55, ["Orgrimmar"] = 0.60, ["Ironforge"] = 0.35,
    ["Thunder Bluff"]  = 0.90, ["Darnassus"] = 0.65, ["Undercity"] = 0.35,
}

local DEFAULTS = {
    enabled        = true,
    minScale       = 0.30,  -- never go below 30% of the player's values
    tickInterval   = 0.5,   -- seconds between environment checks
    rampDown       = 0.60,  -- fraction of the gap closed per tick when shrinking
    rampUp         = 0.50,  -- fraction of the gap closed per tick when growing
    writeThreshold = 0.04,  -- min scale change before CVars are rewritten (limits hitching)
    debug          = false,
    zoneOverrides  = {},    -- ["Zone|Subzone"] = openness
    baselines      = {},    -- [cvar] = player's own value
    lastApplied    = {},    -- [cvar] = value we last wrote
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local db
local active = {}          -- specs whose CVar exists in this client
local currentScale = 1.0   -- smoothed scale actually in effect
local appliedScale = 1.0   -- scale last written to CVars
local targetScale, targetReason = 1.0, "open"
local writing = false      -- true while we call SetCVar ourselves
local pendingWrite = false -- a write was blocked (e.g. combat) and must be retried
local elapsed = 0

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffOVD:|r " .. tostring(msg))
end

local function Debug(msg)
    if db and db.debug then Print("|cff999999" .. msg .. "|r") end
end

local function ReadCVar(name)
    local v
    if C_CVar and C_CVar.GetCVar then v = C_CVar.GetCVar(name) else v = GetCVar(name) end
    return tonumber(v)
end

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
        if dst[k] == nil then
            if type(v) == "table" then dst[k] = CopyDefaults(v, {}) else dst[k] = v end
        end
    end
    return dst
end

local function ZoneKey()
    local zone = GetRealZoneText() or ""
    local sub = GetSubZoneText() or ""
    return zone .. "|" .. sub, zone
end

---------------------------------------------------------------------------
-- Baselines: the player's own values are always the 100% point
---------------------------------------------------------------------------

local function DiscoverCVars()
    wipe(active)
    for _, spec in ipairs(CVAR_SPECS) do
        local current = ReadCVar(spec.name)
        if current then
            table.insert(active, spec)
            local base = db.baselines[spec.name]
            local last = db.lastApplied[spec.name]
            -- If the CVar still holds a value we wrote (e.g. after a crash, before
            -- we could restore), keep the saved baseline. Otherwise the player's
            -- current value is the baseline.
            if not (base and last and NearlyEqual(current, last)) then
                db.baselines[spec.name] = current
            end
            db.lastApplied[spec.name] = nil
        end
    end
end

-- Detect changes the player made in the graphics menu or via /console.
local function CheckForUserChanges()
    for _, spec in ipairs(active) do
        local current = ReadCVar(spec.name)
        local last = db.lastApplied[spec.name]
        local expected = last or db.baselines[spec.name]
        if current and expected and not NearlyEqual(current, expected) then
            db.baselines[spec.name] = current
            db.lastApplied[spec.name] = nil
            appliedScale = 1.0 -- the CVar is now at baseline; force a rewrite
            Debug(("%s baseline changed by player -> %s"):format(spec.name, current))
        end
    end
end

local function RestoreBaselines()
    for _, spec in ipairs(active) do
        local base = db.baselines[spec.name]
        if base then WriteCVar(spec.name, base) end
        db.lastApplied[spec.name] = nil
    end
    appliedScale = 1.0
end

---------------------------------------------------------------------------
-- Openness estimate
---------------------------------------------------------------------------

local function ComputeOpenness()
    local key, zone = ZoneKey()

    -- 1. Player-taught overrides win (subzone first, then whole zone).
    local o = db.zoneOverrides[key] or db.zoneOverrides[zone .. "|*"]
    if o then return o, "override (" .. key .. ")" end

    -- 2. Flying: you can see a long way.
    if IsFlying and IsFlying() then return OPENNESS.flying, "flying" end

    -- 3. Underwater: fog limits sight anyway.
    if IsSubmerged and IsSubmerged() then return OPENNESS.underwater, "underwater" end

    -- 4. Inside a building, cave or tunnel.
    if IsIndoors() then return OPENNESS.indoors, "indoors" end

    -- 5. Capital cities.
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID and CITY_BY_MAPID[mapID] then return CITY_BY_MAPID[mapID], "city" end
    if CITY_BY_NAME[zone] then return CITY_BY_NAME[zone], "city" end

    -- 6. Instances.
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "pvp" then return OPENNESS.battleground, "battleground" end
        return OPENNESS.instance, "instance"
    end

    -- 7. Towns and inns.
    if IsResting() then return OPENNESS.resting, "resting" end

    -- 8. Open world: fields, mountains, roads.
    return OPENNESS.open, "open"
end

---------------------------------------------------------------------------
-- Applying the scale
---------------------------------------------------------------------------

local function ApplyScale(scale, force)
    if not force and math.abs(scale - appliedScale) < db.writeThreshold
        and not (scale == targetScale and scale ~= appliedScale) then
        return
    end

    local allOk = true
    for _, spec in ipairs(active) do
        local base = db.baselines[spec.name]
        if base then
            local effective = 1 - spec.weight * (1 - scale)
            local value = math.max(base * effective, math.min(spec.floor, base))
            if spec.int then value = math.floor(value + 0.5) else value = math.floor(value * 100 + 0.5) / 100 end
            if WriteCVar(spec.name, value) then
                -- Read back: the engine may clamp the value.
                db.lastApplied[spec.name] = ReadCVar(spec.name) or value
            else
                allOk = false
            end
        end
    end

    if allOk then
        appliedScale = scale
        pendingWrite = false
        Debug(("scale %.0f%% (%s)"):format(scale * 100, targetReason))
    else
        pendingWrite = true
        Debug("CVar write blocked; will retry")
    end
end

local function Tick()
    if not db.enabled then return end

    CheckForUserChanges()

    local openness, reason = ComputeOpenness()
    targetScale = Clamp(openness, db.minScale, 1.0)
    targetReason = reason

    local gap = targetScale - currentScale
    local rate = gap < 0 and db.rampDown or db.rampUp
    currentScale = currentScale + gap * rate
    if math.abs(targetScale - currentScale) < 0.02 then currentScale = targetScale end

    ApplyScale(currentScale, pendingWrite and not InCombatLockdown())
end

OVD:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if db and elapsed >= db.tickInterval then
        elapsed = 0
        Tick()
    end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

OVD:RegisterEvent("ADDON_LOADED")
OVD:RegisterEvent("PLAYER_LOGIN")
OVD:RegisterEvent("PLAYER_LOGOUT")
OVD:RegisterEvent("PLAYER_ENTERING_WORLD")
OVD:RegisterEvent("ZONE_CHANGED")
OVD:RegisterEvent("ZONE_CHANGED_INDOORS")
OVD:RegisterEvent("ZONE_CHANGED_NEW_AREA")
OVD:RegisterEvent("PLAYER_REGEN_ENABLED")
OVD:RegisterEvent("CVAR_UPDATE")

OVD:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        OcclusionViewDistanceDB = CopyDefaults(DEFAULTS, OcclusionViewDistanceDB or {})
        db = OcclusionViewDistanceDB

    elseif event == "PLAYER_LOGIN" then
        DiscoverCVars()
        currentScale, appliedScale = 1.0, 1.0

    elseif event == "PLAYER_LOGOUT" then
        -- Put the player's values back so Config.wtf saves them, not ours.
        RestoreBaselines()

    elseif event == "CVAR_UPDATE" then
        -- A settings-menu change. The next tick's check picks up the new baseline.
        if not writing then elapsed = db and db.tickInterval or 0 end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingWrite then ApplyScale(currentScale, true) end

    else
        -- Zone/indoor changes: react immediately instead of waiting for the tick.
        if db then elapsed = db.tickInterval end
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Status()
    Print(("%s | target %.0f%% (%s) | current %.0f%% | min %.0f%%"):format(
        db.enabled and "|cff00ff00on|r" or "|cffff0000off|r",
        targetScale * 100, targetReason, currentScale * 100, db.minScale * 100))
    for _, spec in ipairs(active) do
        Print(("  %s: baseline %s -> now %s"):format(spec.name,
            tostring(db.baselines[spec.name]), tostring(ReadCVar(spec.name))))
    end
    local missing = {}
    for _, spec in ipairs(CVAR_SPECS) do
        if ReadCVar(spec.name) == nil then table.insert(missing, spec.name) end
    end
    if #missing > 0 then Print("  not in this client (skipped): " .. table.concat(missing, ", ")) end
end

local function Help()
    Print("commands:")
    Print("  /ovd - status")
    Print("  /ovd on | off - enable, or disable and restore your settings")
    Print("  /ovd min <10-100> - lowest % of your settings to use")
    Print("  /ovd here <0-100> - set openness for this subzone")
    Print("  /ovd zone <0-100> - set openness for this whole zone")
    Print("  /ovd here clear | zone clear - remove an override")
    Print("  /ovd overrides - list overrides")
    Print("  /ovd debug - toggle debug messages")
end

SLASH_OCCLUSIONVIEWDISTANCE1 = "/ovd"
SlashCmdList["OCCLUSIONVIEWDISTANCE"] = function(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "" or cmd == "status" then
        Status()
    elseif cmd == "on" then
        db.enabled = true
        Print("enabled")
    elseif cmd == "off" then
        db.enabled = false
        RestoreBaselines()
        currentScale = 1.0
        Print("disabled - your settings are restored")
    elseif cmd == "min" then
        local n = tonumber(arg)
        if n and n >= 10 and n <= 100 then
            db.minScale = n / 100
            Print(("minimum set to %d%%"):format(n))
        else
            Print("usage: /ovd min <10-100>")
        end
    elseif cmd == "here" or cmd == "zone" then
        local key, zone = ZoneKey()
        if cmd == "zone" then key = zone .. "|*" end
        if arg == "clear" then
            db.zoneOverrides[key] = nil
            Print("override cleared for " .. key)
        else
            local n = tonumber(arg)
            if n and n >= 0 and n <= 100 then
                db.zoneOverrides[key] = n / 100
                Print(("%s set to %d%% openness"):format(key, n))
            else
                Print("usage: /ovd " .. cmd .. " <0-100> | clear")
            end
        end
        elapsed = db.tickInterval
    elseif cmd == "overrides" then
        local any = false
        for k, v in pairs(db.zoneOverrides) do
            Print(("  %s = %d%%"):format(k, v * 100))
            any = true
        end
        if not any then Print("no overrides set") end
    elseif cmd == "debug" then
        db.debug = not db.debug
        Print("debug " .. (db.debug and "on" or "off"))
    else
        Help()
    end
end
