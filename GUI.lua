--[[
  Sightline - window, minimap button and game-settings entry.

  Layout rule: every piece of text that can change gets an explicit width, and
  either wraps into a height that fits it or is short enough for one line.
]]

local ADDON_NAME, ns = ...

ns.ICON = "Interface\\AddOns\\Sightline\\Media\\Icon"
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local W, H = 780, 600
local CW = W - 36          -- content width
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
-- Helpers
---------------------------------------------------------------------------

local function Pct(x) return ("%d%%"):format(math.floor((x or 0) * 100 + 0.5)) end

local function FormatValue(v)
    if not v then return "-" end
    if v == math.floor(v) then return tostring(v) end
    return ("%.2f"):format(v)
end

local function Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end
local function BandColorCode(band) return Hex(ns.BAND_INFO[band].color) end

local function Ago(t)
    if not t then return "-" end
    local d = time() - t
    if d < 60 then return "just now" end
    if d < 3600 then return ("%dm ago"):format(math.floor(d / 60)) end
    if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
    return ("%dd ago"):format(math.floor(d / 86400))
end

-- Text with an explicit width. lines > 1 lets it wrap into that many lines.
local function Text(parent, font, text, width, lines)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    if lines and lines > 1 then
        fs:SetWordWrap(true)
        fs:SetJustifyV("TOP")
        local _, size = fs:GetFont()
        fs:SetHeight(math.ceil((size or 12) * 1.25 * lines))
    else
        fs:SetWordWrap(false)
    end
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
        f.title = Text(f, "GameFontNormal", title, 300)
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

local function Checkbox(parent, label, tip, get, set, labelWidth)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = Text(cb, "GameFontHighlight", label, labelWidth or 190)
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

    f.value = Text(f, "GameFontHighlightSmall", nil, 52)
    if label then
        f.label = Text(f, "GameFontNormalSmall", label, width - 56)
        f.label:SetPoint("TOPLEFT", 2, 0)
        f.value:SetPoint("TOPRIGHT", -2, 0)
        f.value:SetJustifyH("RIGHT")
    end

    local s = CreateFrame("Slider", nil, f, TEMPLATE)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(17)
    if label then
        s:SetPoint("TOPLEFT", 0, -14); s:SetPoint("TOPRIGHT", 0, -14)
    else
        s:SetPoint("LEFT", 0, 0); s:SetPoint("RIGHT", -52, 0)
        f.value:SetPoint("LEFT", s, "RIGHT", 6, 0)
    end
    s:SetBackdrop(SLIDER_BACKDROP)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local lo, hi = self:GetMinMaxValues()
        self:SetValue(math.min(hi or maxV, math.max(lo or minV, self:GetValue() + delta * step)))
    end)
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        f.value:SetText(fmt(v))
        if not f.updating then set(v) end
    end)
    f.slider = s

    f.SetRange = function(lo, hi) s:SetMinMaxValues(lo, hi) end
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

-- Whole-number input box with a label and range hint.
local function NumberBox(parent, label, minV, maxV, unit, width, get, set, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 38)
    f.label = Text(f, "GameFontNormalSmall", label, width - 4)
    f.label:SetPoint("TOPLEFT", 2, 0)

    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(56, 20)
    box:SetPoint("TOPLEFT", 8, -15)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    box:SetJustifyH("CENTER")
    f.box = box

    local hint = Text(f, "GameFontDisableSmall", ("%s   (%d - %d)"):format(unit, minV, maxV), width - 80)
    hint:SetPoint("LEFT", box, "RIGHT", 8, 0)

    f.Refresh = function(force)
        if force or not box:HasFocus() then box:SetText(tostring(get())) end
    end
    local function Commit()
        local v = tonumber(box:GetText())
        if v then
            v = math.max(minV, math.min(maxV, math.floor(v)))
            if v ~= get() then set(v) end
        end
        f.Refresh(true)
    end
    box:SetScript("OnEnterPressed", function(self) Commit(); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(self) f.Refresh(true); self:ClearFocus() end)
    if tip then Tooltip(box, label, tip .. "\nType a number and press Enter.") end
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

    f.text = Text(sb, "GameFontHighlightSmall", nil, width - 8)
    f.text:SetJustifyH("CENTER")
    f.text:SetPoint("CENTER")

    f.Set = function(_, value, target, label)
        sb:SetValue(math.min(1, value))
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", f, "LEFT", width * math.min(1, target or value), 0)
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

local function RowButton(parent, width, height, index)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(width, height)
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(1, 1, 1, (index % 2 == 0) and 0.03 or 0)
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(1, 0.82, 0, 0.15)
    r.sel:Hide()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    return r
end

local CAL_STATUS_COLOR = {
    ["Calibrated"]    = "|cff60ff60",
    ["Recalibrating"] = "|cffffd100",
    ["No gain"]       = "|cffaaaaaa",
    ["At lowest"]     = "|cffff7050",
    ["Manual"]        = "|cffc89bff",
}
local function CalStatusText(c)
    if not c then return "-" end
    local s = (CAL_STATUS_COLOR[c.status] or "|cffffffff") .. (c.status or "?") .. "|r"
    if c.locked then s = s .. " |cffc89bff(locked)|r" end
    return s
end

local function FactorText(f)
    if not f then return "-" end
    local color = f < 0.999 and "|cffffb050" or (f > 1.001 and "|cff70c8ff" or "|cffffffff")
    return color .. Pct(f) .. "|r"
end

local function GoalText()
    local goal, low, high, mode = ns.FpsGoal()
    if mode == "target" then
        return ("around %d fps"):format(goal)
    end
    return ("at least %d fps"):format(goal)
end

---------------------------------------------------------------------------
-- Window and tabs
---------------------------------------------------------------------------

local window
local tabs = {}
local TAB_NAMES = { "Overview", "Distances", "Environments", "Zones", "Calibrations", "Performance", "Settings" }

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
    local tabWidth = (W - 40) / #TAB_NAMES

    local b = CreateFrame("Button", nil, window)
    b:SetSize(tabWidth - 4, 26)
    b:SetPoint("TOPLEFT", 20 + (index - 1) * tabWidth, -48)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetColorTexture(1, 0.82, 0, 1)
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    b.label = Text(b, "GameFontDisable", label, tabWidth - 8)
    b.label:SetJustifyH("CENTER")
    b.label:SetPoint("CENTER", 0, 1)
    b:SetScript("OnClick", function() SelectTab(index) end)

    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", 18, -82)
    content:SetPoint("BOTTOMRIGHT", -18, 18)
    content:Hide()

    local tab = { button = b, content = content }
    tabs[index] = tab
    build(tab, content)
end

local CH = H - 82 - 18 -- content height

---------------------------------------------------------------------------
-- Tab: Overview
---------------------------------------------------------------------------

local function BuildOverview(tab, c)
    local loc = Panel(c)
    loc:SetPoint("TOPLEFT"); loc:SetSize(CW, 100)
    local zone = Text(loc, "GameFontNormalLarge", nil, CW - 160)
    zone:SetPoint("TOPLEFT", 12, -10)
    local sub = Text(loc, "GameFontHighlight", nil, CW - 160)
    sub:SetPoint("TOPLEFT", 12, -32)
    local env = Text(loc, "GameFontHighlightSmall", nil, CW - 160)
    env:SetPoint("TOPLEFT", 12, -54)
    local cal = Text(loc, "GameFontHighlightSmall", nil, CW - 160)
    cal:SetPoint("TOPLEFT", 12, -72)

    local status = Text(loc, "GameFontNormalLarge", nil, 110)
    status:SetJustifyH("RIGHT")
    status:SetPoint("TOPRIGHT", -14, -12)
    local pause = Button(loc, "Pause", 100, function()
        ns.SetEnabled(not ns.db.enabled)
        tab.Update()
    end)
    pause:SetPoint("TOPRIGHT", -12, -42)

    local vis = Panel(c, "Visibility by band")
    vis:SetPoint("TOPLEFT", loc, "BOTTOMLEFT", 0, -8); vis:SetSize(CW, 122)
    local hint = Text(vis, "GameFontDisableSmall", "Bar = now, white marker = target", 220)
    hint:SetJustifyH("RIGHT")
    hint:SetPoint("TOPRIGHT", -12, -10)
    local bars = {}
    local barW = 330
    for i, band in ipairs(ns.BANDS) do
        local info = ns.BAND_INFO[band]
        local y = -36 - (i - 1) * 28
        local label = Text(vis, "GameFontNormal", BandColorCode(band) .. info.label .. "|r", 44)
        label:SetPoint("TOPLEFT", 14, y)
        local bar = Bar(vis, barW, 16, info.color)
        bar:SetPoint("TOPLEFT", 64, y + 1)
        local desc = Text(vis, "GameFontDisableSmall", info.desc, CW - 64 - barW - 26)
        desc:SetPoint("TOPLEFT", 64 + barW + 12, y - 2)
        bars[band] = bar
    end

    local live = Panel(c, "Live values")
    live:SetPoint("TOPLEFT", vis, "BOTTOMLEFT", 0, -8)
    live:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local cols = { { "Setting", 12, 270 }, { "Band", 300, 70 }, { "Your value", 380, 90 }, { "Now", 480, 90 }, { "Scale", 580, 80 } }
    for _, col in ipairs(cols) do
        Text(live, "GameFontNormalSmall", col[1], col[3]):SetPoint("TOPLEFT", col[2], -30)
    end
    Divider(live, -44)

    local rows = {}
    local MAX_ROWS = 10
    for i = 1, MAX_ROWS do
        local y = -50 - (i - 1) * 18
        local r = {}
        for j, key in ipairs({ "name", "band", "base", "now", "scale" }) do
            r[key] = Text(live, "GameFontHighlightSmall", nil, cols[j][3])
            r[key]:SetPoint("TOPLEFT", cols[j][2], y)
        end
        rows[i] = r
    end
    local more = Text(live, "GameFontDisableSmall", nil, CW - 24)
    more:SetPoint("BOTTOMLEFT", 12, 8)

    tab.Update = function()
        local st, db = ns.state, ns.db
        zone:SetText(st.zone ~= "" and st.zone or "Unknown zone")
        sub:SetText(st.subzone ~= "" and st.subzone or " ")
        env:SetText("Environment: |cffffd100" .. st.envLabel .. "|r")
        if ns.CalibrationActive() then
            local fs = st.fps
            cal:SetText(("Calibration: %s   |   %s   |   FPS %d, goal %s"):format(
                FactorText(ns.FpsFactor()), fs.status, math.floor(GetFramerate() + 0.5), GoalText()))
        else
            cal:SetText(("Calibration off   |   FPS %d"):format(math.floor(GetFramerate() + 0.5)))
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
            r.name:SetText(i == 1 and "|cff888888No view-distance settings found.|r" or "")
            r.band:SetText(""); r.base:SetText(""); r.now:SetText(""); r.scale:SetText("")
        end
        more:SetText(#ns.active > MAX_ROWS and ("+%d more on the Distances tab"):format(#ns.active - MAX_ROWS) or "")
    end
end

---------------------------------------------------------------------------
-- Tab: Distances (per-CVar control)
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
    local intro = Text(c, "GameFontHighlightSmall",
        "Each setting follows one band. Click a band to change it. |cff888888Console|r settings aren't in the graphics menu, but the game still uses them.",
        CW - 8, 2)
    intro:SetPoint("TOPLEFT", 4, -2)

    local list = Panel(c)
    list:SetPoint("TOPLEFT", 0, -36); list:SetSize(CW, 372)
    local cols = { { "On", 10, 30 }, { "Setting", 42, 250 }, { "Source", 310, 70 }, { "Band", 390, 80 }, { "Yours", 490, 80 }, { "Now", 580, 80 } }
    for _, col in ipairs(cols) do
        Text(list, "GameFontNormalSmall", col[1], col[3]):SetPoint("TOPLEFT", col[2], -8)
    end
    Divider(list, -22)

    local sf = ScrollArea(list, CW - 34, 340)
    sf:SetPoint("TOPLEFT", 4, -26)
    local child = sf.child
    local rows = {}

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, child)
        r:SetSize(CW - 40, 32)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)

        r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        r.check:SetSize(22, 22); r.check:SetPoint("LEFT", 4, 0)
        r.label = Text(r, "GameFontHighlight", nil, 250); r.label:SetPoint("TOPLEFT", 38, -3)
        r.cvar = Text(r, "GameFontDisableSmall", nil, 250); r.cvar:SetPoint("TOPLEFT", 38, -18)
        r.source = Text(r, "GameFontHighlightSmall", nil, 70); r.source:SetPoint("LEFT", 306, 0)

        r.band = CreateFrame("Button", nil, r, TEMPLATE)
        r.band:SetSize(72, 22); r.band:SetPoint("LEFT", 384, 0)
        r.band:SetBackdrop(BACKDROP_PANEL)
        r.band:SetBackdropColor(0, 0, 0, 0.6)
        r.band.text = Text(r.band, "GameFontHighlightSmall", nil, 64)
        r.band.text:SetJustifyH("CENTER")
        r.band.text:SetPoint("CENTER")
        local hl = r.band:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)

        r.base = Text(r, "GameFontHighlightSmall", nil, 80); r.base:SetPoint("LEFT", 486, 0)
        r.now = Text(r, "GameFontHighlightSmall", nil, 80); r.now:SetPoint("LEFT", 576, 0)

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
            r.cvar:SetText(spec.name .. (spec.exists and "" or "  (missing)"))
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
        child:SetHeight(math.max(340, #ns.specs * 32))
    end

    local addLabel = Text(c, "GameFontNormalSmall", "Add another setting by name:", 180)
    addLabel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -14)
    local box = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    box:SetSize(220, 20); box:SetAutoFocus(false)
    box:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
    local msg = Text(c, "GameFontDisableSmall", nil, CW - 140)
    msg:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -10)

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
    add:SetPoint("LEFT", box, "RIGHT", 8, 0)

    local reset = Button(c, "Reset bands", 120, function()
        for _, spec in ipairs(ns.specs) do
            local s = ns.db.cvarSettings[spec.name]
            if s then s.band = nil end
        end
        ns.RebuildCVars(); Rebuild()
    end)
    reset:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -10)

    tab.Refresh = Rebuild
    tab.Update = function()
        for _, r in ipairs(rows) do
            if r:IsShown() and r.spec then
                local active = false
                for _, a in ipairs(ns.active) do if a == r.spec then active = true break end end
                r.base:SetText(active and FormatValue(ns.db.baselines[r.spec.name]) or "-")
                r.now:SetText(r.spec.exists and FormatValue(ns.ReadCVar(r.spec.name)) or "-")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Tab: Environments (per-band profiles)
---------------------------------------------------------------------------

local function BuildEnvironments(tab, c)
    local intro = Text(c, "GameFontHighlightSmall",
        "How much of your view distance each band keeps in each environment. Far should drop the most when walls are close; Near should stay high.",
        CW - 8, 2)
    intro:SetPoint("TOPLEFT", 4, -2)

    local p = Panel(c)
    p:SetPoint("TOPLEFT", 0, -36); p:SetSize(CW, 330)
    local colX = { 200, 380, 560 }
    Text(p, "GameFontNormalSmall", "Environment", 170):SetPoint("TOPLEFT", 12, -10)
    for i, band in ipairs(ns.BANDS) do
        Text(p, "GameFontNormalSmall", BandColorCode(band) .. ns.BAND_INFO[band].label .. "|r", 160):SetPoint("TOPLEFT", colX[i], -10)
    end
    Divider(p, -26)

    local sliders, labels = {}, {}
    for r, envDef in ipairs(ns.ENVIRONMENTS) do
        local y = -38 - (r - 1) * 40
        local label = Text(p, "GameFontHighlight", envDef.label, 180)
        label:SetPoint("TOPLEFT", 12, y - 4)
        labels[envDef.key] = { fs = label, text = envDef.label }
        for i, band in ipairs(ns.BANDS) do
            local s = Slider(p, nil, 0.1, 1, 0.05, 168, Pct,
                function() return ns.db.profiles[envDef.key][band] end,
                function(v) ns.db.profiles[envDef.key][band] = v; ns.Refresh() end)
            s:SetPoint("TOPLEFT", colX[i] - 4, y)
            table.insert(sliders, s)
        end
    end

    local note = Text(c, "GameFontDisableSmall",
        "Capital cities and saved spots use one openness value, split across bands: Far drops fully, Mid half as much, Near only slightly.",
        CW - 150, 2)
    note:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 4, -12)

    local reset = Button(c, "Reset", 120, function()
        for key, bands in pairs(ns.DEFAULTS.profiles) do
            for band, v in pairs(bands) do ns.db.profiles[key][band] = v end
        end
        tab.Refresh(); ns.Refresh()
    end)
    reset:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, -10)

    tab.Refresh = function() for _, s in ipairs(sliders) do s.Refresh() end end
    tab.Update = function()
        for key, l in pairs(labels) do
            local here = key == ns.state.envKey
            l.fs:SetFontObject(here and GameFontNormal or GameFontHighlight)
            l.fs:SetText((here and "> " or "") .. l.text)
        end
    end
end

---------------------------------------------------------------------------
-- Tab: Zones (openness for spots)
---------------------------------------------------------------------------

local function PrettyKey(key)
    local zone, sub = key:match("^(.-)|(.*)$")
    if not zone then return key end
    if sub == "*" then return zone .. " |cff888888(whole zone)|r" end
    if sub == "" then return zone .. " |cff888888(no subzone)|r" end
    return zone .. " - " .. sub
end

local function BuildZones(tab, c)
    local pending = 0.6
    local btnW = 160

    local here = Panel(c, "Where you are")
    here:SetPoint("TOPLEFT"); here:SetSize(CW, 184)
    local where = Text(here, "GameFontHighlight", nil, CW - btnW - 40)
    where:SetPoint("TOPLEFT", 12, -30)
    local current = Text(here, "GameFontHighlightSmall", nil, CW - btnW - 40)
    current:SetPoint("TOPLEFT", 12, -50)

    local preview = Text(here, "GameFontHighlightSmall", nil, 330)
    local slider = Slider(here, "How open is this spot?", 0, 1, 0.05, 330, Pct,
        function() return pending end,
        function(v)
            pending = v
            local b = ns.BandsFromOpenness(v)
            preview:SetText(("Far %s     Mid %s     Near %s"):format(
                BandColorCode("far") .. Pct(b.far) .. "|r", BandColorCode("mid") .. Pct(b.mid) .. "|r",
                BandColorCode("near") .. Pct(b.near) .. "|r"))
        end,
        "0% = walls right in front of you. 100% = you can see to the horizon.")
    slider:SetPoint("TOPLEFT", 12, -78)
    preview:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, -6)

    local function SaveFor(scope)
        local key = ns.SetOverride(scope, pending)
        ns.Print(PrettyKey(key) .. " set to " .. Pct(pending) .. " openness")
        tab.Refresh()
    end
    local b1 = Button(here, "Save for subzone", btnW, function() SaveFor("sub") end)
    b1:SetPoint("TOPRIGHT", -12, -30)
    local b2 = Button(here, "Save for zone", btnW, function() SaveFor("zone") end)
    b2:SetPoint("TOPRIGHT", b1, "BOTTOMRIGHT", 0, -6)
    local b3 = Button(here, "Clear subzone", btnW, function() ns.SetOverride("sub", nil); tab.Refresh() end)
    b3:SetPoint("TOPRIGHT", b2, "BOTTOMRIGHT", 0, -14)
    local b4 = Button(here, "Clear zone", btnW, function() ns.SetOverride("zone", nil); tab.Refresh() end)
    b4:SetPoint("TOPRIGHT", b3, "BOTTOMRIGHT", 0, -6)
    Tooltip(b1, "Save for subzone", "Use this value only in the current subzone, e.g. one district of a city.")
    Tooltip(b2, "Save for zone", "Use this value anywhere in the current zone that has no subzone value.")

    local saved = Panel(c, "Saved spots")
    saved:SetPoint("TOPLEFT", here, "BOTTOMLEFT", 0, -8)
    saved:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local listH = CH - 184 - 8 - 40
    local sf = ScrollArea(saved, CW - 40, listH)
    sf:SetPoint("TOPLEFT", 8, -30)
    local empty = Text(saved, "GameFontDisableSmall", "None yet. Stand somewhere, set how open it is above, and save it.", CW - 30)
    empty:SetPoint("TOPLEFT", 12, -34)
    local rows = {}

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, sf.child)
        r:SetSize(CW - 46, 24)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
        r.name = Text(r, "GameFontHighlightSmall", nil, CW - 150); r.name:SetPoint("LEFT", 4, 0)
        r.value = Text(r, "GameFontNormalSmall", nil, 50); r.value:SetJustifyH("RIGHT"); r.value:SetPoint("RIGHT", -36, 0)
        r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
        r.del:SetSize(22, 22); r.del:SetPoint("RIGHT", -6, 0)
        rows[i] = r
        return r
    end

    tab.Refresh = function()
        local subKey, zoneKey = ns.ZoneKeys()
        pending = ns.db.zoneOverrides[subKey] or ns.db.zoneOverrides[zoneKey] or ns.state.envBands.far
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
        sf.child:SetHeight(math.max(listH, #keys * 24))
    end

    tab.Update = function()
        local st = ns.state
        where:SetText((st.zone ~= "" and st.zone or "Unknown") .. (st.subzone ~= "" and (" - " .. st.subzone) or ""))
        current:SetText("Currently: |cffffd100" .. st.envLabel .. "|r")
    end
end

---------------------------------------------------------------------------
-- Tab: Calibrations (per-subzone FPS calibrations)
---------------------------------------------------------------------------

local function EnvLabelFor(c)
    if c.envLabel then return c.envLabel end
    for _, e in ipairs(ns.ENVIRONMENTS) do if e.key == c.env then return e.label end end
    return c.env or ""
end

local function BuildCalibrations(tab, c)
    local selected
    local onlyHere = false

    local intro = Text(c, "GameFontHighlightSmall", nil, CW - 170, 2)
    intro:SetPoint("TOPLEFT", 4, -2)

    local list = Panel(c)
    list:SetPoint("TOPLEFT", 0, -36); list:SetSize(CW, 282)
    local cols = { { "Place", 12, 300 }, { "Adjustment", 330, 80 }, { "FPS", 420, 60 }, { "Status", 490, 150 }, { "Updated", 650, 80 } }
    for _, col in ipairs(cols) do
        Text(list, "GameFontNormalSmall", col[1], col[3]):SetPoint("TOPLEFT", col[2], -8)
    end
    Divider(list, -22)

    local listH = 282 - 32
    local sf = ScrollArea(list, CW - 34, listH)
    sf:SetPoint("TOPLEFT", 4, -26)
    local empty = Text(list, "GameFontDisableSmall",
        "No calibrations yet. They appear here as you travel.", CW - 30)
    empty:SetPoint("TOPLEFT", 12, -32)
    local rows = {}

    -- Editor
    local ed = Panel(c, "Selected calibration")
    ed:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
    ed:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local edName = Text(ed, "GameFontHighlight", nil, 420)
    edName:SetPoint("TOPLEFT", 12, -30)
    local edInfo = Text(ed, "GameFontHighlightSmall", nil, 420, 2)
    edInfo:SetPoint("TOPLEFT", 12, -50)

    local editing
    local slider = Slider(ed, "Adjustment (moving it locks this place)", 0.3, 1.5, 0.05, 340, Pct,
        function() local cc = editing and ns.db.calibrations[editing]; return cc and cc.factor or 1 end,
        function(v) if editing then ns.SetCalibration(editing, v, true); tab.Refresh() end end,
        "100% = the normal scaled values. Lower = shorter view distances, higher frame rate.")
    slider:SetPoint("TOPLEFT", 12, -86)

    local lock = Checkbox(ed, "Locked", "Locked places keep their adjustment and are never recalibrated automatically.",
        function() local cc = editing and ns.db.calibrations[editing]; return cc and cc.locked or false end,
        function(v) if editing then ns.SetCalibration(editing, nil, v); tab.Refresh() end end, 80)
    lock:SetPoint("TOPLEFT", 370, -96)

    local bW = 150
    local recal = Button(ed, "Recalibrate", bW, function()
        if editing then ns.Recalibrate(editing); tab.Refresh() end
    end)
    recal:SetPoint("TOPRIGHT", -12, -30)
    Tooltip(recal, "Recalibrate", "Unlock and test again, starting from the stored value. Happens next time you're there.")
    local del = Button(ed, "Delete", bW, function()
        if editing then ns.DeleteCalibration(editing); editing = nil; selected = nil; tab.Refresh() end
    end)
    del:SetPoint("TOPRIGHT", recal, "BOTTOMRIGHT", 0, -6)

    StaticPopupDialogs["SIGHTLINE_CLEAR_CALS"] = {
        text = "Delete every Sightline calibration?\nPlaces will be calibrated again as you visit them.",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() ns.ClearCalibrations(); editing = nil; selected = nil; tab.Refresh() end,
    }
    local all = Button(ed, "Recalibrate all", bW, function() ns.RecalibrateAll(); tab.Refresh() end)
    all:SetPoint("TOPRIGHT", del, "BOTTOMRIGHT", 0, -14)
    local clear = Button(ed, "Delete all", bW, function() StaticPopup_Show("SIGHTLINE_CLEAR_CALS") end)
    clear:SetPoint("TOPRIGHT", all, "BOTTOMRIGHT", 0, -6)

    local filter = Checkbox(c, "Only this zone", nil,
        function() return onlyHere end, function(v) onlyHere = v; tab.Refresh() end, 120)
    filter:SetPoint("TOPRIGHT", -136, 0)

    local function ShowEditor(key)
        editing = key
        local cc = key and ns.db.calibrations[key]
        local enabled = cc ~= nil
        for _, w in ipairs({ slider.slider, lock, recal, del }) do
            if w.SetEnabled then w:SetEnabled(enabled) elseif enabled then w:Enable() else w:Disable() end
        end
        if not cc then
            edName:SetText("|cff888888Click a place in the list to change it.|r")
            edInfo:SetText("")
            return
        end
        edName:SetText(ns.PlaceName(cc) .. "  |cff888888(" .. EnvLabelFor(cc) .. ")|r")
        edInfo:SetText(("%s   |   last %s fps (goal %s)   |   %d tests   |   %s"):format(
            CalStatusText(cc), cc.fps and ("%.0f"):format(cc.fps) or "-", cc.goal or "-",
            cc.tests or 0, Ago(cc.updated)))
        slider.SetRange(ns.db.fps.minFactor, math.max(1, ns.MaxFpsFactor()))
        slider.Refresh()
        lock.Refresh()
    end

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = RowButton(sf.child, CW - 40, 32, i)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
        r.place = Text(r, "GameFontHighlight", nil, 300); r.place:SetPoint("TOPLEFT", 8, -3)
        r.env = Text(r, "GameFontDisableSmall", nil, 300); r.env:SetPoint("TOPLEFT", 8, -18)
        r.factor = Text(r, "GameFontHighlight", nil, 80); r.factor:SetPoint("LEFT", 326, 0)
        r.fps = Text(r, "GameFontHighlightSmall", nil, 60); r.fps:SetPoint("LEFT", 416, 0)
        r.status = Text(r, "GameFontHighlightSmall", nil, 150); r.status:SetPoint("LEFT", 486, 0)
        r.updated = Text(r, "GameFontDisableSmall", nil, 80); r.updated:SetPoint("LEFT", 646, 0)
        rows[i] = r
        return r
    end

    tab.Refresh = function()
        local goal, _, _, mode = ns.FpsGoal()
        if ns.CalibrationActive() then
            intro:SetText(("Sightline calibrates each place you visit to keep you %s. If FPS later drops, it recalibrates from the stored value and keeps a change only if it helps. Click a place to change it."):format(GoalText()))
        else
            intro:SetText("|cffff7050Calibration is off.|r Turn on 'Calibrate every subzone' or a target FPS on the Performance tab.")
        end

        local here = ns.state.zone
        local keys = {}
        for k, cc in pairs(ns.db.calibrations) do
            if not onlyHere or cc.zone == here then table.insert(keys, k) end
        end
        table.sort(keys, function(a, b)
            local ca, cb = ns.db.calibrations[a], ns.db.calibrations[b]
            if ca.zone ~= cb.zone then return (ca.zone or "") < (cb.zone or "") end
            if ca.subzone ~= cb.subzone then return (ca.subzone or "") < (cb.subzone or "") end
            return (ca.env or "") < (cb.env or "")
        end)

        for _, r in ipairs(rows) do r:Hide() end
        local currentKey = ns.CurrentCalKey()
        for i, k in ipairs(keys) do
            local cc = ns.db.calibrations[k]
            local r = GetRow(i)
            r:Show()
            r.key = k
            local isHere = k == currentKey
            r.place:SetText((isHere and "|cffffd100> " or "") .. ns.PlaceName(cc) .. (isHere and "|r" or ""))
            r.env:SetText(EnvLabelFor(cc))
            r.factor:SetText(FactorText(cc.factor))
            r.fps:SetText(cc.fps and ("%.0f"):format(cc.fps) or "-")
            r.status:SetText(CalStatusText(cc))
            r.updated:SetText(Ago(cc.updated))
            r.sel:SetShown(k == selected)
            r:SetScript("OnClick", function()
                selected = k
                tab.Refresh()
            end)
        end
        empty:SetShown(#keys == 0)
        sf.child:SetHeight(math.max(listH, #keys * 32))
        if selected and not ns.db.calibrations[selected] then selected = nil end
        ShowEditor(selected)
    end

    -- Live: refresh the list every couple of seconds while open.
    local t = 0
    tab.Update = function()
        t = t + 1
        if t >= 8 then t = 0; tab.Refresh() end
    end
end

---------------------------------------------------------------------------
-- Tab: Performance (goals and live FPS)
---------------------------------------------------------------------------

local function BuildPerformance(tab, c)
    local widgets = {}
    local function f() return ns.db.fps end
    local function changed() ns.Refresh() end

    local cfg = Panel(c, "Frame rate goal")
    cfg:SetPoint("TOPLEFT"); cfg:SetSize(CW, 232)

    local checks = {
        { "Calibrate every subzone", "Keep at least the minimum FPS everywhere, even without a target. Each place is calibrated once and rechecked if FPS drops.", "autoCalibrate", 10, -26 },
        { "Use a target FPS", "Aim for a specific frame rate instead of just a minimum. Distances can be raised as well as lowered.", "enabled", 260, -26 },
        { "Pause tests in combat", "Spell effects make FPS jump around in combat, which would spoil the measurements.", "pauseInCombat", 510, -26 },
        { "Allow above my settings", "With a target FPS, distances may go past your own values when there's spare FPS, up to the highest adjustment.", "allowAbove", 260, -50 },
        { "Double-check drops", "Addons can't tell when the game is in the background. Before acting on a low reading, Sightline briefly turns off the background FPS cap (useMaxFPSBk), waits a few seconds and measures again. The cap is always turned back on afterwards.", "verifyBackground", 510, -50 },
    }
    for _, d in ipairs(checks) do
        local key = d[3]
        local cb = Checkbox(cfg, d[1], d[2], function() return f()[key] end, function(v) f()[key] = v; changed() end, 200)
        cb:SetPoint("TOPLEFT", d[4], d[5])
        widgets[#widgets + 1] = cb
    end

    local sw = math.floor((CW - 28 - 40) / 3)
    local defs = {
        { "Minimum FPS (no target)", 20, 360, "fps", nil, "minFps",
          "Used when no target FPS is set: each place is calibrated to stay at or above this.", number = true },
        { "Target FPS", 15, 360, "fps", nil, "target",
          "The frame rate to aim for when 'Use a target FPS' is on.", number = true },
        { "Close enough (+/-)", 0.05, 0.25, 0.01, Pct, "tolerance",
          "No tests run while FPS is within this range of the target." },
        { "Noticeable improvement", 0.02, 0.20, 0.01, Pct, "gain",
          "A change is only kept if FPS rises by at least this much (and at least 2 fps). Otherwise it's reverted." },
        { "Measure for", 2, 10, 1, function(v) return ("%ds"):format(v) end, "sampleTime",
          "Seconds of FPS averaged for each measurement. Longer is more reliable but slower." },
        { "Lowest adjustment", 0.3, 0.9, 0.05, Pct, "minFactor",
          "The furthest calibration can lower the scaled values." },
        { "Highest adjustment", 1.0, 1.5, 0.05, Pct, "maxFactor",
          "With 'Allow above my settings' on, the furthest values can be raised. The game may cap some settings lower." },
    }
    for i, d in ipairs(defs) do
        local key = d[6]
        local s
        if d.number then
            s = NumberBox(cfg, d[1], d[2], d[3], d[4], sw,
                function() return f()[key] end, function(v) f()[key] = v; changed() end, d[7])
        else
            s = Slider(cfg, d[1], d[2], d[3], d[4], sw, d[5],
                function() return f()[key] end, function(v) f()[key] = v; changed() end, d[7])
        end
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        s:SetPoint("TOPLEFT", 14 + col * (sw + 20), -84 - row * 48)
        widgets[#widgets + 1] = s
    end

    local live = Panel(c, "Live")
    live:SetPoint("TOPLEFT", cfg, "BOTTOMLEFT", 0, -8); live:SetSize(CW, 128)

    local fpsNow = Text(live, "GameFontNormalHuge", nil, 90)
    fpsNow:SetPoint("TOPLEFT", 14, -32)
    Text(live, "GameFontDisableSmall", "current FPS", 90):SetPoint("TOPLEFT", 14, -62)

    local labels = { "Goal", "Here", "Last measurement", "Status" }
    local values = {}
    for i, label in ipairs(labels) do
        Text(live, "GameFontNormalSmall", label, 110):SetPoint("TOPLEFT", 120, -30 - (i - 1) * 18)
        values[i] = Text(live, "GameFontHighlightSmall", nil, 300)
        values[i]:SetPoint("TOPLEFT", 236, -30 - (i - 1) * 18)
    end

    Text(live, "GameFontNormalSmall", "Adjustment here", 180):SetPoint("TOPLEFT", 560, -30)
    local adjBar = Bar(live, 160, 14, { 0.85, 0.55, 1.0 })
    adjBar:SetPoint("TOPLEFT", 560, -48)
    Text(live, "GameFontDisableSmall", "100% = normal scaled values", 170):SetPoint("TOPLEFT", 560, -68)

    local warn = Text(live, "GameFontHighlightSmall", nil, CW - 30)
    warn:SetPoint("BOTTOMLEFT", 14, 8)

    local hist = Panel(c, "Recent tests")
    hist:SetPoint("TOPLEFT", live, "BOTTOMLEFT", 0, -8)
    hist:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local histLines = {}
    local nLines = math.floor((CH - 232 - 8 - 128 - 8 - 34) / 15)
    for i = 1, nLines do
        local h = Text(hist, "GameFontHighlightSmall", nil, CW - 30)
        h:SetPoint("TOPLEFT", 12, -28 - (i - 1) * 15)
        histLines[i] = h
    end

    tab.Refresh = function() for _, w in ipairs(widgets) do w.Refresh() end end
    tab.Update = function()
        local cfgv, fs = f(), ns.state.fps
        local fps = GetFramerate()
        local goal, low, high, mode = ns.FpsGoal()
        local active = ns.CalibrationActive()
        local color = "|cffffffff"
        if active then
            if fps < low then color = "|cffff6060"
            elseif fps > high and mode == "target" then color = "|cff60c0ff"
            else color = "|cff60ff60" end
        end
        fpsNow:SetText(color .. math.floor(fps + 0.5) .. "|r")

        values[1]:SetText(active and GoalText() or "|cff888888calibration off|r")
        values[2]:SetText(ns.PlaceName({ zone = ns.state.zone, subzone = ns.state.subzone }))
        values[3]:SetText(fs.avg and ("%.1f fps"):format(fs.avg) or "-")
        values[4]:SetText("|cffffd100" .. fs.status .. "|r")

        local factor = ns.FpsFactor()
        local hi = math.max(1, ns.MaxFpsFactor())
        adjBar:Set(factor / hi, 1 / hi, Pct(factor))

        local cap = ns.FpsCaps()
        if active and cap and cap < low then
            warn:SetText(("|cffff6060Your FPS cap (%d) is below the goal. Raise it in the graphics settings or lower the goal.|r"):format(cap))
        else
            warn:SetText("")
        end

        for i = 1, nLines do
            histLines[i]:SetText(fs.history[i] or (i == 1 and "|cff888888No tests yet.|r" or ""))
        end
    end
end

---------------------------------------------------------------------------
-- Tab: Settings
---------------------------------------------------------------------------

local function BuildSettings(tab, c)
    local widgets = {}
    local db = function() return ns.db end

    -- General
    local gen = Panel(c, "General")
    gen:SetPoint("TOPLEFT"); gen:SetSize(CW, 84)
    local en = Checkbox(gen, "Enable Sightline", "When off, your own settings are restored and nothing is scaled.",
        function() return db().enabled end, function(v) ns.SetEnabled(v) end, 200)
    en:SetPoint("TOPLEFT", 10, -26)
    local mm = Checkbox(gen, "Show minimap button", nil,
        function() return not db().minimap.hide end,
        function(v) db().minimap.hide = not v; if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end, 200)
    mm:SetPoint("TOPLEFT", 10, -50)
    local dbg = Checkbox(gen, "Debug messages in chat", "Print a line each time the values change.",
        function() return db().debug end, function(v) db().debug = v end, 200)
    dbg:SetPoint("TOPLEFT", 260, -26)
    widgets[#widgets + 1] = en; widgets[#widgets + 1] = mm; widgets[#widgets + 1] = dbg

    local restore = Button(gen, "Restore my values", 170, function()
        ns.SetEnabled(false)
        ns.Print("paused - your settings are restored")
        tab.Refresh()
    end)
    restore:SetPoint("TOPRIGHT", -12, -24)
    Tooltip(restore, "Restore my values", "Pause Sightline and put every setting back to your own value.")
    StaticPopupDialogs["SIGHTLINE_RESET"] = {
        text = "Reset Sightline settings, bands and saved spots to defaults?\nYour view-distance values and calibrations are kept.",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() ns.ResetSettings(); tab.Refresh(); ns.Print("settings reset") end,
    }
    local reset = Button(gen, "Reset to defaults", 170, function() StaticPopup_Show("SIGHTLINE_RESET") end)
    reset:SetPoint("TOPRIGHT", restore, "BOTTOMRIGHT", 0, -4)

    -- Scaling behaviour
    local beh = Panel(c, "Scaling behaviour")
    beh:SetPoint("TOPLEFT", gen, "BOTTOMLEFT", 0, -8); beh:SetSize(CW, 128)
    local sw = math.floor((CW - 28 - 40) / 3)
    local defs = {
        { "Lowest scale", 0.1, 1, 0.05, Pct, "minScale",
          "Surroundings never scale a setting below this share of your own value." },
        { "Shrink speed", 0.1, 1, 0.05, Pct, "rampDown",
          "How fast distances drop when you walk into a building or city. Share of the gap closed per check." },
        { "Grow speed", 0.1, 1, 0.05, Pct, "rampUp",
          "How fast distances return when you step outside. Faster means less fog but more loading stutter." },
        { "Check interval", 0.2, 2, 0.1, function(v) return ("%.1fs"):format(v) end, "tickInterval",
          "How often your surroundings are checked." },
        { "Minimum change to apply", 0.01, 0.15, 0.01, Pct, "writeThreshold",
          "Small changes are skipped. Every change makes the game reload terrain, so higher means fewer hitches." },
    }
    for i, d in ipairs(defs) do
        local key = d[6]
        local sl = Slider(beh, d[1], d[2], d[3], d[4], sw, d[5],
            function() return db()[key] end, function(v) db()[key] = v; ns.Refresh() end, d[7])
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        sl:SetPoint("TOPLEFT", 14 + col * (sw + 20), -32 - row * 46)
        widgets[#widgets + 1] = sl
    end

    -- Global values against the engine maximum
    local glob = Panel(c, "Your global view distances")
    glob:SetPoint("TOPLEFT", beh, "BOTTOMLEFT", 0, -8)
    glob:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    local info = Text(glob, "GameFontHighlightSmall",
        "These are your own values: the 100% that Sightline scales from in each place. Engine maximum is the highest the game's graphics menu goes (or your value, if you've set it higher).",
        CW - 24, 2)
    info:SetPoint("TOPLEFT", 12, -28)

    local cols = { { "Setting", 12, 220 }, { "Your value", 240, 90 }, { "Engine max", 340, 90 }, { "Of maximum", 440, 200 } }
    for _, col in ipairs(cols) do
        Text(glob, "GameFontNormalSmall", col[1], col[3]):SetPoint("TOPLEFT", col[2], -62)
    end
    Divider(glob, -76)

    local rows = {}
    local MAX_ROWS = 7
    for i = 1, MAX_ROWS do
        local y = -82 - (i - 1) * 19
        local r = {}
        r.name = Text(glob, "GameFontHighlightSmall", nil, 220); r.name:SetPoint("TOPLEFT", 12, y)
        r.base = Text(glob, "GameFontHighlightSmall", nil, 90); r.base:SetPoint("TOPLEFT", 240, y)
        r.max = Text(glob, "GameFontHighlightSmall", nil, 90); r.max:SetPoint("TOPLEFT", 340, y)
        r.bar = Bar(glob, 200, 13, { 1.0, 0.82, 0.0 })
        r.bar:SetPoint("TOPLEFT", 440, y + 1)
        rows[i] = r
    end

    local status = Text(glob, "GameFontDisableSmall", nil, CW - 24)
    status:SetPoint("BOTTOMLEFT", 12, 38)

    local bW = 200
    local useMax = Button(glob, "Set all to engine maximum", bW, function()
        if next(db().engineMax) == nil then
            status:SetText("|cffffd100Detecting the engine maximum...|r")
            ns.UseEngineMax(function() ns.Print("view distances set to the engine maximum"); tab.Refresh() end)
        elseif ns.ApplyEngineMax() then
            ns.Print("view distances set to the engine maximum"); tab.Refresh()
        end
    end)
    useMax:SetPoint("BOTTOMLEFT", 12, 10)
    Tooltip(useMax, "Set all to engine maximum",
        "Make the engine maximum your 100%. Sightline still scales it down wherever you can't see far, and calibration keeps your FPS up. Every place is recalibrated.")
    local detect = Button(glob, "Detect maximum again", bW, function()
        status:SetText("|cffffd100Detecting the engine maximum...|r")
        ns.DetectEngineMax(function() tab.Refresh() end)
    end)
    detect:SetPoint("LEFT", useMax, "RIGHT", 10, 0)
    Tooltip(detect, "Detect maximum again", "Takes about two seconds. Your settings are put back afterwards.")
    local undo = Button(glob, "Undo", 120, function()
        if ns.UndoEngineMax() then ns.Print("previous view distances restored"); tab.Refresh() end
    end)
    undo:SetPoint("LEFT", detect, "RIGHT", 10, 0)
    Tooltip(undo, "Undo", "Go back to the values you had before setting the engine maximum.")

    local function UpdateGlobal()
        local d = db()
        local shown = 0
        for _, spec in ipairs(ns.active) do
            if shown >= MAX_ROWS then break end
            shown = shown + 1
            local r = rows[shown]
            local base, max = d.baselines[spec.name], d.engineMax[spec.name]
            r.name:SetText(spec.label)
            r.base:SetText(FormatValue(base))
            r.max:SetText(max and FormatValue(max) or "|cff888888?|r")
            if base and max and max > 0 then
                local share = base / max
                r.bar:Set(math.min(1, share), math.min(1, share), Pct(share))
            else
                r.bar:Set(0, 0, "not detected")
            end
            r.name:Show(); r.base:Show(); r.max:Show(); r.bar:Show()
        end
        for i = shown + 1, MAX_ROWS do
            local r = rows[i]
            r.name:Hide(); r.base:Hide(); r.max:Hide(); r.bar:Hide()
        end
        if ns.busy then
            status:SetText("|cffffd100Detecting the engine maximum...|r")
        elseif d.engineMaxTime then
            status:SetText("Engine maximum detected " .. Ago(d.engineMaxTime) .. "." ..
                (d.previousBaselines and "   Undo returns to your earlier values." or ""))
        else
            status:SetText("Engine maximum not detected yet. 'Set all to engine maximum' detects it first.")
        end
        if undo.SetEnabled then undo:SetEnabled(d.previousBaselines ~= nil) end
        if detect.SetEnabled then detect:SetEnabled(not ns.busy) end
        if useMax.SetEnabled then useMax:SetEnabled(not ns.busy) end
    end

    tab.Refresh = function()
        for _, w in ipairs(widgets) do w.Refresh() end
        UpdateGlobal()
    end
    tab.Update = UpdateGlobal
end

---------------------------------------------------------------------------
-- First-run choice
---------------------------------------------------------------------------

local firstRun

local function ShowFirstRun()
    if ns.db.setupDone then return end
    if firstRun then firstRun:Show() return end

    local f = CreateFrame("Frame", "SightlineFirstRun", UIParent, TEMPLATE)
    firstRun = f
    f:SetSize(520, 300)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(BACKDROP_MAIN)
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(300, 64)
    header:SetPoint("TOP", 0, 12)
    local title = Text(f, "GameFontNormal", "Welcome to Sightline", 220)
    title:SetJustifyH("CENTER")
    title:SetPoint("TOP", header, "TOP", 0, -14)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.ICON)
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", 26, -40)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)

    local body = Text(f, "GameFontHighlight",
        "Sightline shortens view distance where buildings and walls block it, and keeps it long in the open. It also calibrates each place to keep your frame rate up.\n\nWhich view distances should it start from?",
        390, 7)
    body:SetPoint("TOPLEFT", 104, -42)

    local note = Text(f, "GameFontDisableSmall", "You can change this any time under Settings.", 470)
    note:SetJustifyH("CENTER")
    note:SetPoint("BOTTOM", 0, 64)

    local function Done() ns.db.setupDone = true; f:Hide() end

    local maxBtn
    maxBtn = Button(f, "Use engine maximum", 210, function()
        maxBtn:SetText("Detecting...")
        if maxBtn.SetEnabled then maxBtn:SetEnabled(false) end
        ns.UseEngineMax(function()
            ns.Print("view distances set to the engine maximum. Sightline will scale them to what you can see.")
            Done()
        end)
    end)
    maxBtn:SetPoint("BOTTOMLEFT", 36, 26)
    Tooltip(maxBtn, "Use engine maximum",
        "Raise every view-distance setting to the highest the game allows. Sightline scales it down wherever you can't see far, and calibration keeps your FPS up.")
    local keepBtn = Button(f, "Keep my current settings", 210, function()
        ns.Print("using your current view distances. You can switch to the engine maximum under Settings.")
        Done()
    end)
    keepBtn:SetPoint("BOTTOMRIGHT", -36, 26)
    Tooltip(keepBtn, "Keep my current settings", "Use the view distances you have now as Sightline's 100%.")

    f:Show()
end
ns.ShowFirstRun = ShowFirstRun

---------------------------------------------------------------------------
-- Create window
---------------------------------------------------------------------------

local BUILDERS = { BuildOverview, BuildCVars, BuildEnvironments, BuildZones, BuildCalibrations, BuildPerformance, BuildSettings }

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

    local glow = window:CreateTexture(nil, "BORDER")
    glow:SetColorTexture(1, 0.82, 0, 0.06)
    glow:SetPoint("TOPLEFT", 12, -12); glow:SetPoint("TOPRIGHT", -12, -12)
    glow:SetHeight(62)

    local header = window:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(300, 64)
    header:SetPoint("TOP", 0, 12)
    local title = Text(window, "GameFontNormal", "Sightline", 160)
    title:SetJustifyH("CENTER")
    title:SetPoint("TOP", header, "TOP", 0, -14)

    local subtitle = Text(window, "GameFontDisableSmall", "Adaptive view distance  -  v" .. ns.version, 240)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetPoint("TOP", 0, -28)

    local icon = window:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.ICON)
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", 18, -14)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    for i, name in ipairs(TAB_NAMES) do AddTab(name, BUILDERS[i]) end

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
    icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 6, -5)
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
            local col = ns.BAND_INFO[band].color
            GameTooltip:AddDoubleLine(ns.BAND_INFO[band].label, Pct(ns.db.enabled and st.current[band] or 1), col[1], col[2], col[3], 1, 1, 1)
        end
        if ns.CalibrationActive() then
            GameTooltip:AddLine(("FPS %d, goal %s"):format(math.floor(GetFramerate() + 0.5), GoalText()), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(("Calibration %s - %s"):format(Pct(ns.FpsFactor()), st.fps.status), 0.8, 0.8, 0.8)
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
    local t = Text(panel, "GameFontNormalLarge", "Sightline", 300)
    t:SetPoint("TOPLEFT", 16, -16)
    local d = Text(panel, "GameFontHighlight", "Adaptive view distance. All settings and live stats are in the Sightline window.", 560, 2)
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
    if not ns.db.setupDone then
        if C_Timer and C_Timer.After then C_Timer.After(4, ShowFirstRun) else ShowFirstRun() end
    end
end
