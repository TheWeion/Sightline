--[[
  Sightline - window, minimap button and game-settings entry.
]]

local ADDON_NAME, ns = ...

ns.ICON = "Interface\\AddOns\\Sightline\\Media\\Icon"
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local W, H = 660, 540
local atan2 = math.atan2 or math.atan

local BACKDROP_MAIN = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32, insets = { left = 10, right = 10, top = 10, bottom = 10 },
}
local BACKDROP_PANEL = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local SLIDER_BACKDROP = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Pct(x) return ("%d%%"):format(math.floor((x or 0) * 100 + 0.5)) end

local function FormatValue(v)
    if not v then return "-" end
    if v == math.floor(v) then return tostring(v) end
    return ("%.2f"):format(v)
end

local function BandColorCode(band)
    local c = ns.BAND_INFO[band].color
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function Text(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if text then fs:SetText(text) end
    return fs
end

local function Tooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Panel(parent, title)
    local f = CreateFrame("Frame", nil, parent, TEMPLATE)
    f:SetBackdrop(BACKDROP_PANEL)
    f:SetBackdropColor(0, 0, 0, 0.45)
    f:SetBackdropBorderColor(0.65, 0.52, 0.22, 0.9)
    if title then
        f.title = Text(f, "GameFontNormal", title)
        f.title:SetPoint("TOPLEFT", 10, -8)
    end
    return f
end

local function Divider(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 0.82, 0, 0.25)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 8, y)
    t:SetPoint("TOPRIGHT", -8, y)
    return t
end

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 120, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function Checkbox(parent, label, tip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = Text(cb, "GameFontHighlight", label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Refresh = function() cb:SetChecked(get()) end
    if tip then Tooltip(cb, label, tip) end
    return cb
end

-- Slider built from base textures so it works on every client version.
local function Slider(parent, label, minV, maxV, step, width, fmt, get, set, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, label and 38 or 22)

    if label then
        f.label = Text(f, "GameFontNormalSmall", label)
        f.label:SetPoint("TOPLEFT", 2, 0)
    end
    f.value = Text(f, "GameFontHighlightSmall")
    if label then f.value:SetPoint("TOPRIGHT", -2, 0) end

    local s = CreateFrame("Slider", nil, f, TEMPLATE)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(17)
    if label then
        s:SetPoint("TOPLEFT", 0, -14); s:SetPoint("TOPRIGHT", 0, -14)
    else
        s:SetPoint("LEFT", 0, 0); s:SetPoint("RIGHT", -40, 0)
        f.value:SetPoint("LEFT", s, "RIGHT", 6, 0)
    end
    s:SetBackdrop(SLIDER_BACKDROP)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.min(maxV, math.max(minV, self:GetValue() + delta * step)))
    end)
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        f.value:SetText(fmt(v))
        if not f.updating then set(v) end
    end)
    f.slider = s

    f.Refresh = function()
        f.updating = true
        local v = get()
        s:SetValue(v)
        f.value:SetText(fmt(v))
        f.updating = false
    end
    if tip and label then Tooltip(s, label, tip) end
    return f
end

-- Horizontal bar with a marker for the target value.
local function Bar(parent, width, height, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.1, 0.9)

    local sb = CreateFrame("StatusBar", nil, f)
    sb:SetAllPoints()
    sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sb:SetStatusBarColor(color[1], color[2], color[3], 0.9)
    sb:SetMinMaxValues(0, 1)

    local marker = sb:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(1, 1, 1, 0.9)
    marker:SetSize(2, height + 4)

    f.text = Text(sb, "GameFontHighlightSmall")
    f.text:SetPoint("CENTER")

    f.Set = function(_, value, target, label)
        sb:SetValue(value)
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", f, "LEFT", width * (target or value), 0)
        f.text:SetText(label or Pct(value))
    end
    return f
end

local function ScrollArea(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(width, height)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(width, height)
    sf:SetScrollChild(child)
    sf.child = child
    return sf
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local window
local tabs = {}

local function SelectTab(index)
    for i, tab in ipairs(tabs) do
        local selected = i == index
        tab.content:SetShown(selected)
        tab.button.bg:SetColorTexture(selected and 0.32 or 0.10, selected and 0.24 or 0.08, selected and 0.04 or 0.05, 0.95)
        tab.button.line:SetShown(selected)
        tab.button.label:SetFontObject(selected and GameFontNormal or GameFontDisable)
        if selected then
            if tab.Refresh then tab.Refresh() end
            if tab.Update then tab.Update() end
        end
    end
    window.selected = index
end

local function AddTab(label, build)
    local index = #tabs + 1
    local tabWidth = (W - 40) / 6

    local b = CreateFrame("Button", nil, window)
    b:SetSize(tabWidth - 4, 24)
    b:SetPoint("TOPLEFT", 20 + (index - 1) * tabWidth, -46)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetColorTexture(1, 0.82, 0, 1)
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    b.label = Text(b, "GameFontDisable", label)
    b.label:SetPoint("CENTER", 0, 1)
    b:SetScript("OnClick", function() SelectTab(index) end)

    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", 18, -78)
    content:SetPoint("BOTTOMRIGHT", -18, 18)
    content:Hide()

    local tab = { button = b, content = content }
    tabs[index] = tab
    build(tab, content)
end

---------------------------------------------------------------------------
-- Tab: Overview
---------------------------------------------------------------------------

local function BuildOverview(tab, c)
    local cw = W - 36

    -- Location
    local loc = Panel(c)
    loc:SetPoint("TOPLEFT"); loc:SetSize(cw, 90)
    local zone = Text(loc, "GameFontNormalLarge")
    zone:SetPoint("TOPLEFT", 12, -10)
    local sub = Text(loc, "GameFontHighlight")
    sub:SetPoint("TOPLEFT", zone, "BOTTOMLEFT", 0, -4)
    local env = Text(loc, "GameFontHighlightSmall")
    env:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -6)

    local fpsLine = Text(loc, "GameFontHighlightSmall")
    fpsLine:SetPoint("TOPLEFT", env, "BOTTOMLEFT", 0, -4)

    local status = Text(loc, "GameFontNormalLarge")
    status:SetPoint("TOPRIGHT", -14, -12)
    local pause = Button(loc, "Pause", 90, function()
        ns.SetEnabled(not ns.db.enabled)
        if tab.Update then tab.Update() end
    end)
    pause:SetPoint("TOPRIGHT", -12, -40)

    -- Visibility bands
    local vis = Panel(c, "Visibility by band")
    vis:SetPoint("TOPLEFT", loc, "BOTTOMLEFT", 0, -8); vis:SetSize(cw, 112)
    local hint = Text(vis, "GameFontDisableSmall", "Bar = now   |   white marker = target")
    hint:SetPoint("TOPRIGHT", -12, -9)
    local bars = {}
    for i, band in ipairs(ns.BANDS) do
        local info = ns.BAND_INFO[band]
        local label = Text(vis, "GameFontNormal", BandColorCode(band) .. info.label .. "|r")
        label:SetPoint("TOPLEFT", 14, -32 - (i - 1) * 26)
        local bar = Bar(vis, cw - 220, 16, info.color)
        bar:SetPoint("LEFT", label, "LEFT", 54, 0)
        local desc = Text(vis, "GameFontDisableSmall", info.desc)
        desc:SetPoint("LEFT", bar, "RIGHT", 10, 0)
        desc:SetWidth(140); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetHeight(24)
        bars[band] = bar
    end

    -- Live values
    local live = Panel(c, "Live values")
    live:SetPoint("TOPLEFT", vis, "BOTTOMLEFT", 0, -8)
    live:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local cols = { { "Setting", 12 }, { "Band", 230 }, { "Your value", 300 }, { "Now", 390 }, { "Scale", 470 } }
    for _, col in ipairs(cols) do
        local h = Text(live, "GameFontNormalSmall", col[1])
        h:SetPoint("TOPLEFT", col[2], -30)
    end
    Divider(live, -44)

    local rows = {}
    local MAX_ROWS = 9
    for i = 1, MAX_ROWS do
        local y = -50 - (i - 1) * 18
        local r = {}
        r.name  = Text(live, "GameFontHighlightSmall"); r.name:SetPoint("TOPLEFT", 12, y)
        r.band  = Text(live, "GameFontHighlightSmall"); r.band:SetPoint("TOPLEFT", 230, y)
        r.base  = Text(live, "GameFontHighlightSmall"); r.base:SetPoint("TOPLEFT", 300, y)
        r.now   = Text(live, "GameFontHighlightSmall"); r.now:SetPoint("TOPLEFT", 390, y)
        r.scale = Text(live, "GameFontHighlightSmall"); r.scale:SetPoint("TOPLEFT", 470, y)
        rows[i] = r
    end
    local more = Text(live, "GameFontDisableSmall")
    more:SetPoint("BOTTOMLEFT", 12, 8)

    tab.Update = function()
        local st, db = ns.state, ns.db
        zone:SetText(st.zone ~= "" and st.zone or "Unknown zone")
        sub:SetText(st.subzone ~= "" and st.subzone or " ")
        env:SetText("Environment: |cffffd100" .. st.envLabel .. "|r")
        if db.fps.enabled then
            fpsLine:SetText(("FPS %d / target %d   |   adjustment %s   |   %s"):format(
                math.floor(GetFramerate() + 0.5), db.fps.target, Pct(ns.FpsFactor()), st.fps.status))
        else
            fpsLine:SetText(("FPS %d   |   target FPS off"):format(math.floor(GetFramerate() + 0.5)))
        end
        if db.enabled then
            status:SetText("|cff40ff40ACTIVE|r"); pause:SetText("Pause")
        else
            status:SetText("|cffff5050PAUSED|r"); pause:SetText("Resume")
        end

        for _, band in ipairs(ns.BANDS) do
            local now = db.enabled and st.current[band] or 1
            bars[band]:Set(now, st.target[band], Pct(now) .. "  ->  " .. Pct(st.target[band]))
        end

        local shown = 0
        for i, spec in ipairs(ns.active) do
            if i > MAX_ROWS then break end
            local r = rows[i]
            local base = db.baselines[spec.name]
            local now = ns.ReadCVar(spec.name)
            r.name:SetText(spec.label)
            r.band:SetText(BandColorCode(spec.band) .. ns.BAND_INFO[spec.band].label .. "|r")
            r.base:SetText(FormatValue(base))
            r.now:SetText(FormatValue(now))
            r.scale:SetText((base and base > 0 and now) and Pct(now / base) or "-")
            shown = i
        end
        for i = shown + 1, MAX_ROWS do
            local r = rows[i]
            r.name:SetText(i == 1 and "|cff888888No view-distance settings found in this client.|r" or "")
            r.band:SetText(""); r.base:SetText(""); r.now:SetText(""); r.scale:SetText("")
        end
        more:SetText(#ns.active > MAX_ROWS and ("+%d more on the View Distances tab"):format(#ns.active - MAX_ROWS) or "")
    end
end

---------------------------------------------------------------------------
-- Tab: View Distances (per-CVar control)
---------------------------------------------------------------------------

local function NextBand(band)
    for i, b in ipairs(ns.BANDS) do
        if b == band then return ns.BANDS[i % #ns.BANDS + 1] end
    end
    return "far"
end

local function CVarSetting(name)
    local s = ns.db.cvarSettings[name]
    if not s then s = {}; ns.db.cvarSettings[name] = s end
    return s
end

local function BuildCVars(tab, c)
    local cw = W - 36
    local intro = Text(c, "GameFontHighlightSmall",
        "Each setting follows one band. Click a band to change it. Settings marked |cff888888Console|r aren't in the graphics menu, but the game still uses them.")
    intro:SetPoint("TOPLEFT", 4, -2); intro:SetWidth(cw - 8); intro:SetJustifyH("LEFT")

    local list = Panel(c)
    list:SetPoint("TOPLEFT", 0, -36); list:SetSize(cw, 330)
    local cols = { { "On", 10 }, { "Setting", 40 }, { "Source", 250 }, { "Band", 320 }, { "Yours", 400 }, { "Now", 470 } }
    for _, col in ipairs(cols) do
        Text(list, "GameFontNormalSmall", col[1]):SetPoint("TOPLEFT", col[2], -8)
    end
    Divider(list, -22)

    local sf = ScrollArea(list, cw - 34, 300)
    sf:SetPoint("TOPLEFT", 4, -26)
    local child = sf.child
    local rows = {}

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, child)
        r:SetSize(cw - 40, 30)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)

        r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        r.check:SetSize(22, 22); r.check:SetPoint("LEFT", 4, 0)
        r.label = Text(r, "GameFontHighlight"); r.label:SetPoint("TOPLEFT", 36, -3)
        r.cvar = Text(r, "GameFontDisableSmall"); r.cvar:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -1)
        r.source = Text(r, "GameFontHighlightSmall"); r.source:SetPoint("LEFT", 246, 0)

        r.band = CreateFrame("Button", nil, r, TEMPLATE)
        r.band:SetSize(64, 20); r.band:SetPoint("LEFT", 314, 0)
        r.band:SetBackdrop(BACKDROP_PANEL)
        r.band:SetBackdropColor(0, 0, 0, 0.6)
        r.band.text = Text(r.band, "GameFontHighlightSmall"); r.band.text:SetPoint("CENTER")
        local hl = r.band:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)

        r.base = Text(r, "GameFontHighlightSmall"); r.base:SetPoint("LEFT", 396, 0)
        r.now = Text(r, "GameFontHighlightSmall"); r.now:SetPoint("LEFT", 466, 0)

        r.remove = CreateFrame("Button", nil, r, "UIPanelCloseButton")
        r.remove:SetSize(22, 22); r.remove:SetPoint("RIGHT", -2, 0)
        Tooltip(r.remove, "Remove", "Stop managing this custom setting and restore your value.")
        rows[i] = r
        return r
    end

    local function Rebuild()
        for _, r in ipairs(rows) do r:Hide() end
        for i, spec in ipairs(ns.specs) do
            local r = GetRow(i)
            r:Show()
            r.label:SetText(spec.exists and spec.label or ("|cff777777" .. spec.label .. "|r"))
            r.cvar:SetText(spec.name .. (spec.exists and "" or "  (not in this client)"))
            r.source:SetText(spec.custom and "|cffb48cffCustom|r" or (spec.menu and "|cffffd100Menu|r" or "|cff888888Console|r"))
            r.check:SetChecked(spec.enabled)
            r.check:SetEnabled(spec.exists)
            r.check:SetScript("OnClick", function(self)
                CVarSetting(spec.name).enabled = self:GetChecked() and true or false
                ns.RebuildCVars(); Rebuild()
            end)
            r.band.text:SetText(BandColorCode(spec.band) .. ns.BAND_INFO[spec.band].label .. "|r")
            r.band:SetScript("OnClick", function()
                CVarSetting(spec.name).band = NextBand(spec.band)
                ns.RebuildCVars(); Rebuild()
            end)
            r.band:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Band: " .. ns.BAND_INFO[spec.band].label, 1, 0.82, 0)
                GameTooltip:AddLine(ns.BAND_INFO[spec.band].desc, 1, 1, 1, true)
                GameTooltip:AddLine("Click to cycle Far / Mid / Near.", 0.6, 0.6, 0.6, true)
                if spec.band ~= spec.defaultBand then
                    GameTooltip:AddLine("Default: " .. ns.BAND_INFO[spec.defaultBand].label, 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            r.band:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.remove:SetShown(spec.custom and true or false)
            r.remove:SetScript("OnClick", function()
                for j, n in ipairs(ns.db.customCVars) do
                    if n == spec.name then table.remove(ns.db.customCVars, j) break end
                end
                ns.db.cvarSettings[spec.name] = nil
                ns.RebuildCVars()
                ns.db.baselines[spec.name] = nil
                Rebuild()
            end)
            r.spec = spec
        end
        child:SetHeight(math.max(300, #ns.specs * 30))
    end

    -- Add a custom CVar
    local addLabel = Text(c, "GameFontNormalSmall", "Add another setting by name:")
    addLabel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -12)
    local box = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    box:SetSize(200, 20); box:SetAutoFocus(false)
    box:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
    local msg = Text(c, "GameFontDisableSmall")
    msg:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -8)

    local function Add()
        local name = (box:GetText() or ""):gsub("%s", "")
        if name == "" then return end
        for _, spec in ipairs(ns.specs) do
            if spec.name:lower() == name:lower() then msg:SetText("|cffff6060Already in the list.|r") return end
        end
        if ns.ReadCVar(name) == nil then
            msg:SetText("|cffff6060This client has no numeric setting called " .. name .. ".|r")
            return
        end
        table.insert(ns.db.customCVars, name)
        box:SetText(""); box:ClearFocus()
        msg:SetText("|cff60ff60Added " .. name .. " to the Mid band. Click its band to change it.|r")
        ns.RebuildCVars(); Rebuild()
    end
    box:SetScript("OnEnterPressed", Add)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    local add = Button(c, "Add", 70, Add)
    add:SetPoint("LEFT", box, "RIGHT", 6, 0)

    local reset = Button(c, "Reset bands", 110, function()
        for _, spec in ipairs(ns.specs) do
            local s = ns.db.cvarSettings[spec.name]
            if s then s.band = nil end
        end
        ns.RebuildCVars(); Rebuild()
    end)
    reset:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -8)

    tab.Refresh = Rebuild
    tab.Update = function()
        for _, r in ipairs(rows) do
            if r:IsShown() and r.spec then
                local base = ns.db.baselines[r.spec.name]
                local active = false
                for _, a in ipairs(ns.active) do if a == r.spec then active = true break end end
                r.base:SetText(active and FormatValue(base) or "-")
                r.now:SetText(r.spec.exists and FormatValue(ns.ReadCVar(r.spec.name)) or "-")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Tab: Environments (per-band profiles)
---------------------------------------------------------------------------

local function BuildEnvironments(tab, c)
    local cw = W - 36
    local intro = Text(c, "GameFontHighlightSmall",
        "How much of your view distance each band keeps in each environment. Far should drop the most when walls are close; Near should stay high.")
    intro:SetPoint("TOPLEFT", 4, -2); intro:SetWidth(cw - 8); intro:SetJustifyH("LEFT")

    local p = Panel(c)
    p:SetPoint("TOPLEFT", 0, -36); p:SetSize(cw, 312)
    local colX = { 170, 300, 430 }
    Text(p, "GameFontNormalSmall", "Environment"):SetPoint("TOPLEFT", 12, -10)
    for i, band in ipairs(ns.BANDS) do
        Text(p, "GameFontNormalSmall", BandColorCode(band) .. ns.BAND_INFO[band].label .. "|r"):SetPoint("TOPLEFT", colX[i], -10)
    end
    Divider(p, -26)

    local sliders, labels = {}, {}
    for r, envDef in ipairs(ns.ENVIRONMENTS) do
        local y = -36 - (r - 1) * 38
        local label = Text(p, "GameFontHighlight", envDef.label)
        label:SetPoint("TOPLEFT", 12, y - 4)
        labels[envDef.key] = label
        for i, band in ipairs(ns.BANDS) do
            local s = Slider(p, nil, 0.1, 1, 0.05, 124, Pct,
                function() return ns.db.profiles[envDef.key][band] end,
                function(v) ns.db.profiles[envDef.key][band] = v; ns.Refresh() end)
            s:SetPoint("TOPLEFT", colX[i] - 4, y)
            table.insert(sliders, s)
        end
    end

    local note = Text(c, "GameFontDisableSmall",
        "Capital cities and your saved spots use one openness value, split across bands so Far drops fully, Mid half as much and Near only slightly.")
    note:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 4, -10); note:SetWidth(cw - 140); note:SetJustifyH("LEFT")

    local reset = Button(c, "Reset", 110, function()
        for key, bands in pairs(ns.DEFAULTS.profiles) do
            for band, v in pairs(bands) do ns.db.profiles[key][band] = v end
        end
        tab.Refresh(); ns.Refresh()
    end)
    reset:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, -8)

    tab.Refresh = function() for _, s in ipairs(sliders) do s.Refresh() end end
    tab.Update = function()
        for key, label in pairs(labels) do
            label:SetFontObject(key == ns.state.envKey and GameFontNormal or GameFontHighlight)
            label:SetText((key == ns.state.envKey and "> " or "") .. (function()
                for _, e in ipairs(ns.ENVIRONMENTS) do if e.key == key then return e.label end end
            end)())
        end
    end
end

---------------------------------------------------------------------------
-- Tab: Zones (player-taught spots)
---------------------------------------------------------------------------

local function PrettyKey(key)
    local zone, sub = key:match("^(.-)|(.*)$")
    if not zone then return key end
    if sub == "*" then return zone .. " |cff888888(whole zone)|r" end
    if sub == "" then return zone .. " |cff888888(no subzone)|r" end
    return zone .. " - " .. sub
end

local function BuildZones(tab, c)
    local cw = W - 36
    local pending = 0.6

    local here = Panel(c, "Where you are")
    here:SetPoint("TOPLEFT"); here:SetSize(cw, 170)
    local where = Text(here, "GameFontHighlight")
    where:SetPoint("TOPLEFT", 12, -28)
    local current = Text(here, "GameFontHighlightSmall")
    current:SetPoint("TOPLEFT", where, "BOTTOMLEFT", 0, -4)

    local preview = Text(here, "GameFontHighlightSmall")
    local slider = Slider(here, "How open is this spot?", 0, 1, 0.05, 260, Pct,
        function() return pending end,
        function(v)
            pending = v
            local b = ns.BandsFromOpenness(v)
            preview:SetText(("Far %s   Mid %s   Near %s"):format(
                BandColorCode("far") .. Pct(b.far) .. "|r", BandColorCode("mid") .. Pct(b.mid) .. "|r",
                BandColorCode("near") .. Pct(b.near) .. "|r"))
        end,
        "0% = walls right in front of you. 100% = you can see to the horizon.")
    slider:SetPoint("TOPLEFT", 12, -68)
    preview:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, -4)

    local function SaveFor(scope)
        local key = ns.SetOverride(scope, pending)
        ns.Print(PrettyKey(key) .. " set to " .. Pct(pending) .. " openness")
        if tab.Refresh then tab.Refresh() end
    end
    local b1 = Button(here, "Save for subzone", 140, function() SaveFor("sub") end)
    b1:SetPoint("TOPRIGHT", -12, -28)
    local b2 = Button(here, "Save for zone", 140, function() SaveFor("zone") end)
    b2:SetPoint("TOPRIGHT", b1, "BOTTOMRIGHT", 0, -4)
    local b3 = Button(here, "Clear subzone", 140, function() ns.SetOverride("sub", nil); tab.Refresh() end)
    b3:SetPoint("TOPRIGHT", b2, "BOTTOMRIGHT", 0, -10)
    local b4 = Button(here, "Clear zone", 140, function() ns.SetOverride("zone", nil); tab.Refresh() end)
    b4:SetPoint("TOPRIGHT", b3, "BOTTOMRIGHT", 0, -4)
    Tooltip(b1, "Save for subzone", "Use this value only in the current subzone, e.g. one district of a city.")
    Tooltip(b2, "Save for zone", "Use this value anywhere in the current zone that has no subzone value.")

    local saved = Panel(c, "Saved spots")
    saved:SetPoint("TOPLEFT", here, "BOTTOMLEFT", 0, -8)
    saved:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local sf = ScrollArea(saved, cw - 40, 180)
    sf:SetPoint("TOPLEFT", 8, -28)
    local empty = Text(saved, "GameFontDisableSmall", "None yet. Stand somewhere, set how open it is above, and save it.")
    empty:SetPoint("TOPLEFT", 12, -32)
    local rows = {}

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, sf.child)
        r:SetSize(cw - 46, 22)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        r.name = Text(r, "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 4, 0)
        r.value = Text(r, "GameFontNormalSmall"); r.value:SetPoint("RIGHT", -34, 0)
        r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
        r.del:SetSize(20, 20); r.del:SetPoint("RIGHT", -6, 0)
        rows[i] = r
        return r
    end

    tab.Refresh = function()
        local subKey, zoneKey = ns.ZoneKeys()
        pending = ns.db.zoneOverrides[subKey] or ns.db.zoneOverrides[zoneKey] or ns.state.target.far
        slider.Refresh()
        slider.slider:GetScript("OnValueChanged")(slider.slider, pending)

        local keys = {}
        for k in pairs(ns.db.zoneOverrides) do table.insert(keys, k) end
        table.sort(keys)
        for _, r in ipairs(rows) do r:Hide() end
        for i, k in ipairs(keys) do
            local r = GetRow(i)
            r:Show()
            r.name:SetText(PrettyKey(k))
            r.value:SetText(Pct(ns.db.zoneOverrides[k]))
            r.del:SetScript("OnClick", function()
                ns.db.zoneOverrides[k] = nil; ns.Refresh(); tab.Refresh()
            end)
        end
        empty:SetShown(#keys == 0)
        sf.child:SetHeight(math.max(180, #keys * 22))
    end

    tab.Update = function()
        local st = ns.state
        where:SetText((st.zone ~= "" and st.zone or "Unknown") .. (st.subzone ~= "" and (" - " .. st.subzone) or ""))
        current:SetText("Currently: |cffffd100" .. st.envLabel .. "|r")
    end
end

---------------------------------------------------------------------------
-- Tab: Settings
---------------------------------------------------------------------------

local function BuildPerformance(tab, c)
    local cw = W - 36
    local widgets = {}
    local function f() return ns.db.fps end
    local function changed() ns.Refresh() end

    local cfg = Panel(c, "Target FPS")
    cfg:SetPoint("TOPLEFT"); cfg:SetSize(cw, 214)

    local en = Checkbox(cfg, "Use a target FPS",
        "Sightline tests small changes to your view distances and keeps a change only if it moves you closer to the target.",
        function() return f().enabled end, function(v) f().enabled = v; changed() end)
    en:SetPoint("TOPLEFT", 10, -26)
    local above = Checkbox(cfg, "Allow above my settings",
        "When FPS is well above the target, view distances may go past your own values, up to the highest adjustment.",
        function() return f().allowAbove end, function(v) f().allowAbove = v; changed() end)
    above:SetPoint("TOPLEFT", 220, -26)
    local combat = Checkbox(cfg, "Pause tests in combat",
        "Spell effects make FPS jump around in combat, which would spoil the measurements.",
        function() return f().pauseInCombat end, function(v) f().pauseInCombat = v; changed() end)
    combat:SetPoint("TOPLEFT", 430, -26)
    widgets[#widgets + 1] = en; widgets[#widgets + 1] = above; widgets[#widgets + 1] = combat

    local sw = (cw - 60) / 2
    local defs = {
        { "Target FPS", 15, 240, 5, function(v) return ("%d fps"):format(v) end, "target",
          "The frame rate to aim for." },
        { "Close enough (+/-)", 0.05, 0.25, 0.01, Pct, "tolerance",
          "No tests run while FPS is within this range of the target." },
        { "Noticeable improvement", 0.02, 0.20, 0.01, Pct, "gain",
          "Lowering distances is only kept if FPS rises by at least this much (and at least 2 fps). Otherwise it's reverted." },
        { "Measure for", 2, 10, 1, function(v) return ("%ds"):format(v) end, "sampleTime",
          "Seconds of FPS averaged for each measurement. Longer is more reliable but slower to react." },
        { "Lowest adjustment", 0.3, 0.9, 0.05, Pct, "minFactor",
          "The furthest the FPS target can lower the scaled values." },
        { "Highest adjustment", 1.0, 1.5, 0.05, Pct, "maxFactor",
          "With 'Allow above my settings' on, the furthest values can be raised. The game may cap some settings lower." },
    }
    for i, d in ipairs(defs) do
        local key = d[6]
        local s = Slider(cfg, d[1], d[2], d[3], d[4], sw, d[5],
            function() return f()[key] end, function(v) f()[key] = v; changed() end, d[7])
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        s:SetPoint("TOPLEFT", 14 + col * (sw + 30), -58 - row * 48)
        widgets[#widgets + 1] = s
    end

    local live = Panel(c, "Live")
    live:SetPoint("TOPLEFT", cfg, "BOTTOMLEFT", 0, -8)
    live:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)

    local fpsNow = Text(live, "GameFontNormalHuge")
    fpsNow:SetPoint("TOPLEFT", 14, -30)
    local fpsLabel = Text(live, "GameFontDisableSmall", "current FPS")
    fpsLabel:SetPoint("TOPLEFT", fpsNow, "BOTTOMLEFT", 0, -2)

    local lines = {}
    for i, label in ipairs({ "Last measurement", "Target range", "Status" }) do
        local l = Text(live, "GameFontNormalSmall", label)
        l:SetPoint("TOPLEFT", 120, -30 - (i - 1) * 18)
        local v = Text(live, "GameFontHighlightSmall")
        v:SetPoint("TOPLEFT", 240, -30 - (i - 1) * 18)
        lines[i] = v
    end

    local adjLabel = Text(live, "GameFontNormalSmall", "Adjustment")
    adjLabel:SetPoint("TOPLEFT", 14, -98)
    local adjBar = Bar(live, 220, 14, { 0.85, 0.55, 1.0 })
    adjBar:SetPoint("LEFT", adjLabel, "LEFT", 90, 0)
    local adjHint = Text(live, "GameFontDisableSmall", "100% = the normal scaled values")
    adjHint:SetPoint("TOPLEFT", adjLabel, "BOTTOMLEFT", 0, -8)

    local warn = Text(live, "GameFontHighlightSmall")
    warn:SetPoint("BOTTOMLEFT", 14, 10)
    warn:SetWidth(cw / 2 - 20); warn:SetJustifyH("LEFT")

    local histTitle = Text(live, "GameFontNormalSmall", "Recent tests")
    histTitle:SetPoint("TOPLEFT", cw / 2 + 20, -30)
    local hist = {}
    for i = 1, 8 do
        local h = Text(live, "GameFontHighlightSmall")
        h:SetPoint("TOPLEFT", histTitle, "BOTTOMLEFT", 0, -4 - (i - 1) * 15)
        h:SetWidth(cw / 2 - 30); h:SetJustifyH("LEFT"); h:SetWordWrap(false)
        hist[i] = h
    end

    tab.Refresh = function() for _, w in ipairs(widgets) do w.Refresh() end end
    tab.Update = function()
        local cfgv, fs = f(), ns.state.fps
        local fps = GetFramerate()
        local tol = cfgv.target * cfgv.tolerance
        local color = "|cffffffff"
        if cfgv.enabled then
            if fps < cfgv.target - tol then color = "|cffff6060"
            elseif fps > cfgv.target + tol then color = "|cff60c0ff"
            else color = "|cff60ff60" end
        end
        fpsNow:SetText(color .. math.floor(fps + 0.5) .. "|r")

        lines[1]:SetText(fs.avg and ("%.1f fps"):format(fs.avg) or "-")
        lines[2]:SetText(("%d - %d fps"):format(math.floor(cfgv.target - tol + 0.5), math.floor(cfgv.target + tol + 0.5)))
        lines[3]:SetText("|cffffd100" .. fs.status .. "|r" .. (fs.trial and (" (" .. Pct(fs.trial) .. ")") or ""))

        local factor = ns.FpsFactor()
        local hi = math.max(1, ns.MaxFpsFactor())
        adjBar:Set(factor / hi, 1 / hi, Pct(factor))

        local cap = ns.ReadCVar("maxFPS")
        if cfgv.enabled and cap and cap > 0 and cap < cfgv.target then
            warn:SetText(("|cffff6060Your FPS cap (%d) is below the target. Raise it in the graphics settings or lower the target.|r"):format(cap))
        elseif not cfgv.enabled then
            warn:SetText("|cff888888Target FPS is off. View distances follow your surroundings only.|r")
        else
            warn:SetText("")
        end

        for i = 1, 8 do hist[i]:SetText(fs.history[i] or (i == 1 and "|cff888888No tests yet.|r" or "")) end
    end
end

local function BuildSettings(tab, c)
    local cw = W - 36
    local widgets = {}
    local db = function() return ns.db end

    local gen = Panel(c, "General")
    gen:SetPoint("TOPLEFT"); gen:SetSize(cw, 100)
    local en = Checkbox(gen, "Enable Sightline", "When off, your own settings are restored and nothing is scaled.",
        function() return db().enabled end, function(v) ns.SetEnabled(v) end)
    en:SetPoint("TOPLEFT", 10, -26)
    local mm = Checkbox(gen, "Show minimap button", nil,
        function() return not db().minimap.hide end,
        function(v) db().minimap.hide = not v; if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end)
    mm:SetPoint("TOPLEFT", en, "BOTTOMLEFT", 0, -2)
    local dbg = Checkbox(gen, "Debug messages in chat", "Print a line each time the values change.",
        function() return db().debug end, function(v) db().debug = v end)
    dbg:SetPoint("TOPLEFT", 300, -26)
    widgets[#widgets + 1] = en; widgets[#widgets + 1] = mm; widgets[#widgets + 1] = dbg

    local beh = Panel(c, "Scaling behaviour")
    beh:SetPoint("TOPLEFT", gen, "BOTTOMLEFT", 0, -8); beh:SetSize(cw, 170)
    local sw = (cw - 60) / 2
    local defs = {
        { "Lowest scale", 0.1, 1, 0.05, Pct, "minScale",
          "No setting is ever scaled below this share of your own value." },
        { "Check interval", 0.2, 2, 0.1, function(v) return ("%.1fs"):format(v) end, "tickInterval",
          "How often your surroundings are checked." },
        { "Shrink speed", 0.1, 1, 0.05, Pct, "rampDown",
          "How fast distances drop when you walk into a building or city. Share of the gap closed per check." },
        { "Grow speed", 0.1, 1, 0.05, Pct, "rampUp",
          "How fast distances return when you step outside. Faster means less fog, but more loading stutter." },
        { "Minimum change before applying", 0.01, 0.15, 0.01, Pct, "writeThreshold",
          "Small changes are skipped. Every change makes the game reload terrain, so higher means fewer hitches." },
    }
    for i, d in ipairs(defs) do
        local key = d[6]
        local s = Slider(beh, d[1], d[2], d[3], d[4], sw, d[5],
            function() return db()[key] end, function(v) db()[key] = v; ns.Refresh() end, d[7])
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        s:SetPoint("TOPLEFT", 14 + col * (sw + 30), -30 - row * 46)
        widgets[#widgets + 1] = s
    end

    local act = Panel(c, "Actions")
    act:SetPoint("TOPLEFT", beh, "BOTTOMLEFT", 0, -8)
    act:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local restore = Button(act, "Restore my values", 160, function()
        ns.SetEnabled(false)
        ns.Print("paused - your settings are restored")
        tab.Refresh()
    end)
    restore:SetPoint("TOPLEFT", 12, -30)
    Tooltip(restore, "Restore my values", "Pause Sightline and put every setting back to your own value.")

    StaticPopupDialogs["SIGHTLINE_RESET"] = {
        text = "Reset all Sightline settings, bands and saved spots to defaults?\nYour own view-distance values are kept.",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() ns.ResetSettings(); tab.Refresh(); ns.Print("settings reset") end,
    }
    local reset = Button(act, "Reset to defaults", 160, function() StaticPopup_Show("SIGHTLINE_RESET") end)
    reset:SetPoint("LEFT", restore, "RIGHT", 10, 0)

    local about = Text(act, "GameFontDisableSmall",
        ("Sightline %s   |   /sight opens this window   |   Your values are restored on logout and /reload."):format(ns.version))
    about:SetPoint("BOTTOMLEFT", 12, 10)

    tab.Refresh = function() for _, w in ipairs(widgets) do w.Refresh() end end
end

---------------------------------------------------------------------------
-- Create window
---------------------------------------------------------------------------

local function CreateWindow()
    window = CreateFrame("Frame", "SightlineWindow", UIParent, TEMPLATE)
    window:SetSize(W, H)
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.window = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    local pos = ns.db.window
    if pos and pos.point then
        window:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        window:SetPoint("CENTER")
    end
    window:SetBackdrop(BACKDROP_MAIN)
    window:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
    tinsert(UISpecialFrames, "SightlineWindow")

    -- Faint gold glow along the top
    local glow = window:CreateTexture(nil, "BORDER")
    glow:SetColorTexture(1, 0.82, 0, 0.06)
    glow:SetPoint("TOPLEFT", 12, -12); glow:SetPoint("TOPRIGHT", -12, -12)
    glow:SetHeight(60)

    local header = window:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(300, 64)
    header:SetPoint("TOP", 0, 12)
    local title = Text(window, "GameFontNormal", "Sightline")
    title:SetPoint("TOP", header, "TOP", 0, -14)

    local subtitle = Text(window, "GameFontDisableSmall", "Adaptive view distance")
    subtitle:SetPoint("TOP", 0, -26)

    local icon = window:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.ICON)
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", 20, -18)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    AddTab("Overview", BuildOverview)
    AddTab("View Distances", BuildCVars)
    AddTab("Environments", BuildEnvironments)
    AddTab("Zones", BuildZones)
    AddTab("Performance", BuildPerformance)
    AddTab("Settings", BuildSettings)

    local t = 0
    window:SetScript("OnUpdate", function(_, dt)
        t = t + dt
        if t < 0.25 then return end
        t = 0
        local tab = tabs[window.selected or 1]
        if tab and tab.Update then tab.Update() end
    end)
    window:SetScript("OnShow", function() SelectTab(window.selected or 1) end)

    SelectTab(1)
end

function ns.ToggleWindow()
    if not window then CreateWindow(); window:Show() return end
    window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local mini

local function PlaceMinimapButton()
    local a = math.rad(ns.db.minimap.angle or 215)
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function CreateMinimapButton()
    mini = CreateFrame("Button", "SightlineMinimapButton", Minimap)
    mini:SetSize(31, 31)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mini:RegisterForDrag("LeftButton")
    mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = mini:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
    local icon = mini:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.ICON)
    icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    local border = mini:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")

    mini:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.SetEnabled(not ns.db.enabled)
            ns.Print(ns.db.enabled and "enabled" or "paused - your settings are restored")
        else
            ns.ToggleWindow()
        end
    end)
    mini:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mini:SetScript("OnEnter", function(self)
        local st = ns.state
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Sightline", 1, 0.82, 0)
        GameTooltip:AddLine(st.envLabel .. (ns.db.enabled and "" or "  |cffff5050(paused)|r"), 1, 1, 1)
        for _, band in ipairs(ns.BANDS) do
            local c = ns.BAND_INFO[band].color
            GameTooltip:AddDoubleLine(ns.BAND_INFO[band].label, Pct(ns.db.enabled and st.current[band] or 1), c[1], c[2], c[3], 1, 1, 1)
        end
        if ns.db.fps.enabled then
            GameTooltip:AddLine(("FPS %d / %d  -  %s"):format(math.floor(GetFramerate() + 0.5), ns.db.fps.target, st.fps.status), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Left-click: open   Right-click: pause/resume   Drag: move", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceMinimapButton()
end

function ns.UpdateMinimapButton()
    if not mini then return end
    mini:SetShown(not ns.db.minimap.hide)
end

---------------------------------------------------------------------------
-- Entry in the game's AddOns settings
---------------------------------------------------------------------------

local function RegisterSettingsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Sightline"
    local t = Text(panel, "GameFontNormalLarge", "Sightline")
    t:SetPoint("TOPLEFT", 16, -16)
    local d = Text(panel, "GameFontHighlight", "Adaptive view distance. All settings and live stats are in the Sightline window.")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
    local b = Button(panel, "Open Sightline", 160, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        if not window or not window:IsShown() then ns.ToggleWindow() end
    end)
    b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -16)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Sightline")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

ns.OnLogin = function()
    CreateMinimapButton()
    ns.UpdateMinimapButton()
    pcall(RegisterSettingsPanel)
end
