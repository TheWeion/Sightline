-- Runs Sightline against a stand-in for the game's API. From the repo root: lua5.1 tests/sim.lua

local clock, timers, writes = 0, {}, {}
local cvars = {
    farclip = "1000", horizonStart = "800", wmoLodDist = "600", groundEffectDist = "160",
    graphicsViewDistance = "5", graphicsGroundClutter = "5",
    maxFPS = "200", useMaxFPS = "1", maxFPSBk = "30", useMaxFPSBk = "1",
}
local world = { zone = "Elwynn Forest", subzone = "", fps = function() return 100 end }

local function Widget()
    local state = { scripts = {}, shown = true, value = 0, lo = 0, hi = 1 }
    local methods = {
        SetScript = function(_, k, fn) state.scripts[k] = fn end,
        HookScript = function(_, k, fn) state.scripts[k] = fn end,
        GetScript = function(_, k) return state.scripts[k] end,
        CreateTexture = Widget, CreateFontString = Widget,
        Show = function() state.shown = true end,
        Hide = function() state.shown = false end,
        SetShown = function(_, v) state.shown = v and true or false end,
        IsShown = function() return state.shown end,
        SetChecked = function(_, v) state.checked = v end,
        GetChecked = function() return state.checked end,
        SetMinMaxValues = function(_, lo, hi) state.lo, state.hi = lo, hi end,
        GetMinMaxValues = function() return state.lo, state.hi end,
        SetValue = function(self, v)
            state.value = v
            if state.scripts.OnValueChanged then state.scripts.OnValueChanged(self, v) end
        end,
        GetValue = function() return state.value end,
        SetText = function(_, text) state.text = text end,
        GetText = function() return state.text end,
        GetCenter = function() return 0, 0 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetEffectiveScale = function() return 1 end,
    }
    return setmetatable({ scripts = state.scripts }, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return methods[k] or function() end end
    end })
end

local frames = {}
function CreateFrame(_, name)
    local frame = Widget()
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value)
        cvars[name], writes[name] = tostring(value), (writes[name] or 0) + 1
        if name == "graphicsViewDistance" then
            cvars.farclip = value == "10" and "2600" or "1000"
            cvars.horizonStart = value == "10" and "2000" or "800"
        elseif name == "graphicsGroundClutter" then
            cvars.groundEffectDist = value == "10" and "320" or "160"
        end
    end,
}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent, Minimap, GameTooltip, SettingsPanel = Widget(), Widget(), Widget(), Widget()
Settings = { RegisterCanvasLayoutCategory = function() end, RegisterAddOnCategory = function() end }
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
YES, NO, tinsert, time, date = "Yes", "No", table.insert, os.time, os.date
function StaticPopup_Show(name) StaticPopupDialogs[name].OnAccept() end
function HideUIPanel() end
function GetCursorPosition() return 0, 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local copy = {} for k, v in pairs(t) do copy[k] = v end return copy end
function GetTime() return clock end
function GetFramerate() return world.fps() end
function GetRealZoneText() return world.zone end
function GetSubZoneText() return world.subzone end
function IsIndoors() return world.indoors end
function IsResting() return world.resting end
function IsInInstance() return false end
function UnitAffectingCombat() return world.combat end

local ns = {}
assert(loadfile("Core.lua"))("Sightline", ns)
assert(loadfile("GUI.lua"))("Sightline", ns)
local core = frames[1]

local function fire(event, ...) core.scripts.OnEvent(core, event, ...) end
local function run(seconds)
    for _ = 1, seconds * 2 do
        clock = clock + 0.5
        for i = #timers, 1, -1 do
            if timers[i].at <= clock then table.remove(timers, i).fn() end
        end
        core.scripts.OnUpdate(core, 0.5)
    end
end
local checks = 0
local function check(ok, what)
    if not ok then error("FAILED: " .. what, 2) end
    checks = checks + 1
end
local function cvar(name) return tonumber(cvars[name]) end
local function go(subzone) world.subzone = subzone; fire("ZONE_CHANGED") end
local function gpuBound(load) return function() return 90000 / (cvar("farclip") * load + 500) end end
local function logged(text)
    for _, line in ipairs(ns.state.fps.history) do
        if line:find(text, 1, true) then return true end
    end
end

fire("ADDON_LOADED", "Sightline")
fire("PLAYER_LOGIN")
local db, fs = ns.db, ns.state.fps
db.setupDone = true

-- Surroundings scale each band by its own amount.
db.fps.autoCalibrate = false
world.zone, world.resting = "Stormwind City", true
run(10)
check(cvar("farclip") == 550 and cvar("wmoLodDist") == 465 and cvar("groundEffectDist") == 149, "city scales far, mid and near differently")
world.indoors = true
run(10)
check(cvar("farclip") == 300 and cvar("groundEffectDist") == 152, "indoors cuts far settings hardest")

-- A value the player changes while scaled becomes their 100%.
C_CVar.SetCVar("farclip", "2000")
run(5)
check(db.baselines.farclip == 2000 and cvar("farclip") == 600, "a changed setting becomes the new baseline")
C_CVar.SetCVar("farclip", "1000")
world.zone, world.resting, world.indoors = "Elwynn Forest", false, false
run(10)
check(cvar("farclip") == 1000 and cvar("horizonStart") == 800, "open world uses the player's own values")

-- A place below the goal is lowered until it reaches it, and the result is saved.
db.fps.autoCalibrate = true
world.fps = gpuBound(1.4)
go("Goldshire")
run(90)
local goldshire = db.calibrations["Elwynn Forest|Goldshire|open"]
check(fs.factor == 0.7 and cvar("farclip") == 700 and fs.status == "On goal", "calibrates down to the goal")
check(goldshire and goldshire.factor == 0.7 and goldshire.status == "Calibrated", "saves the calibration")
check(cvars.useMaxFPSBk == "1", "the background cap is back on after calibrating")

-- Where lowering changes nothing it is reverted, and the place is not re-checked on every reading.
world.fps = function() return 45 end
go("Market")
writes.useMaxFPSBk = 0
run(300)
check(fs.factor == 1 and cvar("farclip") == 1000, "reverts when lowering does not help")
check(fs.status == "Below goal, lowering didn't help", "says that lowering did not help")
check(writes.useMaxFPSBk <= 8, "leaves the background cap alone in a place that stays low, wrote it " .. writes.useMaxFPSBk .. " times")

-- Back in a calibrated place its saved value applies at once.
world.fps = gpuBound(1.4)
go("Goldshire")
run(12)
check(fs.factor == 0.7 and fs.status == "On goal", "re-entering uses the saved calibration")

-- Alt-tabbed: FPS holds at the background cap, so nothing changes and the cap is never touched.
writes.useMaxFPSBk = 0
world.fps = function() return 30 end
run(600)
check(fs.factor == 0.7 and fs.status == "Paused: game in background", "holding at the background cap means the game is in the background")
check(writes.useMaxFPSBk == 0 and logged("in the background"), "the background cap is not touched while alt-tabbed")
world.fps = gpuBound(1.4)
run(20)
check(fs.factor == 0.7 and fs.status == "On goal", "carries on unchanged after alt-tabbing back")

-- A drop that does not last changes nothing; one that does is recalibrated from the saved value.
local dropEnds = clock + 6
world.fps = function() return clock < dropEnds and 45 or gpuBound(1.4)() end
run(40)
check(fs.factor == 0.7 and logged("drop didn't last"), "a short drop changes nothing")
world.fps = gpuBound(2.0)
run(90)
check(fs.factor == 0.5 and goldshire.factor == 0.5 and fs.status == "On goal", "a lasting drop recalibrates from the saved value")
check(cvars.useMaxFPSBk == "1", "the background cap is back on after recalibrating")

-- Combat stops a test in flight.
world.fps = gpuBound(3.0)
run(14)
world.combat = true
run(2)
check(fs.trial == nil and fs.status == "Paused in combat" and cvars.useMaxFPSBk == "1", "combat stops tests and restores the background cap")
world.combat, world.fps = false, gpuBound(2.0)
run(20)

-- A locked place keeps its value, also when everything else is recalibrated.
ns.SetCalibration(fs.key, 0.9, true)
ns.RecalibrateAll()
run(30)
check(fs.factor == 0.9 and goldshire.locked and fs.status == "Locked", "a locked calibration is left alone")
check(db.calibrations["Elwynn Forest|Market|open"].pending, "unlocked calibrations are marked for recalibration")

-- An adjustment above 100% is dropped when going above the player's settings is no longer allowed.
ns.SetCalibration(fs.key, nil, false)
db.fps.enabled, db.fps.allowAbove, db.fps.target = true, true, 30
world.fps = function() return 100 end
run(120)
check(fs.factor > 1, "a target FPS with headroom may raise distances above the player's settings")
db.fps.enabled = false
run(2)
check(fs.factor == 1, "the adjustment returns to 100% when that is switched off")

-- Engine maximum: detected through the graphics menu, applied as the player's values, and undoable.
world.fps = function() return 100 end
ns.UseEngineMax()
run(5)
check(db.engineMax.farclip == 2600 and db.baselines.farclip == 2600 and db.baselines.groundEffectDist == 320, "engine maximum becomes the baseline")
check(cvars.graphicsViewDistance == "5" and cvars.graphicsGroundClutter == "5", "the graphics menu is put back")
check(db.calibrations["Elwynn Forest|Market|open"].pending and not goldshire.locked, "calibrations are redone against the new values")
ns.UseEngineMax()
run(5)
ns.UndoEngineMax()
run(5)
check(db.baselines.farclip == 1000 and db.baselines.groundEffectDist == 160, "undo returns to the values from before the first change")

-- The window builds, and every control can be used without an error.
SlashCmdList.SIGHTLINE("")
for round = 1, 2 do
    for _, frame in ipairs(frames) do
        local click, slide = frame.scripts.OnClick, frame.scripts.OnValueChanged
        if click and frame:IsShown() and frame ~= SightlineMinimapButton then click(frame, "LeftButton") end
        if slide then frame:SetValue(0.5) end
        if frame.scripts.OnEnter then frame.scripts.OnEnter(frame) end
        SightlineWindow.scripts.OnUpdate(SightlineWindow, 1)
    end
    run(3)
end
check(SightlineWindow ~= nil and SightlineFirstRun == nil, "the window opens and the first-run dialog stays away once answered")

-- Logging out puts everything back.
db.enabled = true
world.indoors = true
run(10)
check(cvar("farclip") < db.baselines.farclip, "scaled again before logging out")
fire("PLAYER_LOGOUT")
check(cvar("farclip") == db.baselines.farclip and cvars.useMaxFPSBk == "1", "logout restores the player's values")

print(checks .. " checks passed")
