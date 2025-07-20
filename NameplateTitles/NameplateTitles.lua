-- NameplateTitles.lua
-- Shows guilds (players) or titles (NPCs) on nameplates with configurable options in Interface menu
local addonName, _ = ...
local f = CreateFrame("Frame")
local db

-- Default settings
local defaults = {
    showPlayer = true,
    showNPC = true,
    player = {friendly = true, neutral = false, hostile = false},
    npc = {friendly = true, neutral = true, hostile = false}
}

-- Utility: classify unit if it is assistable or attackable
local function Classify(unit)
    -- Hostile if you can attack it
    if UnitCanAttack("player", unit) then return "hostile" end

    -- Friendly if you can assist or interact in a non-hostile way
    if UnitCanAssist("player", unit) or UnitIsFriend("player", unit) then
        return "friendly"
    end

    -- Catch-all: not attackable or assistable
    return "neutral"
end

-- Hidden tooltip scanner
local scanner = CreateFrame("GameTooltip", "HiddenTooltipScanner", nil,
                            "GameTooltipTemplate")
scanner:SetOwner(UIParent, "ANCHOR_NONE")

-- Extract NPC title (line 2 only)
local function GetNPCTitle(unit)
    scanner:ClearLines()
    scanner:SetUnit(unit)
    local line = _G[scanner:GetName() .. "TextLeft2"]
    if not line then return end
    local text = line:GetText()
    if text and not text:match("^Level") then return text end
end

-- Attach a FontString under the nameplate
local function AttachTitleText(plate, text)
    if not plate.TitleText then
        local fs = plate:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        fs:SetPoint("TOP", plate, "BOTTOM", 0, -2)
        fs:SetTextColor(0.3, 1.0, 0.3)
        plate.TitleText = fs
    end
    plate.TitleText:SetText(text or "")
    plate.TitleText:Show()
end

-- Polling state
local PollingPlates = {} -- [unit] = { t = 0, total = 0 }
local SeenPlates = {} -- [unit] = true

-- Try to find & display title. Return true if done polling.
local function PollTitle(unit)
    if SeenPlates[unit] then return true end

    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or not UnitExists(unit) then
        SeenPlates[unit] = true
        return true
    end

    local isPlayer = UnitIsPlayer(unit)
    local rep = Classify(unit)
    local title

    -- Master toggles + per‑rep filters
    if isPlayer then
        if not db.showPlayer or not db.player[rep] then
            SeenPlates[unit] = true
            return true
        end
        local guild = GetGuildInfo(unit)
        if guild then title = "<" .. guild .. ">" end

    else
        if not db.showNPC or not db.npc[rep] then
            SeenPlates[unit] = true
            return true
        end
        local raw = GetNPCTitle(unit)
        if raw then title = "<" .. raw .. ">" end
    end

    if title then
        AttachTitleText(plate, title)
        SeenPlates[unit] = true
        return true
    end

    return false
end

-- Polling driver
local pollFrame = CreateFrame("Frame")
local refreshTimer = 0

pollFrame:SetScript("OnUpdate", function(self, elapsed)
    refreshTimer = refreshTimer + elapsed

    -- Poll existing entries
    for unit, data in pairs(PollingPlates) do
        data.t = data.t + elapsed
        data.total = data.total + elapsed
        if data.t >= 0.1 then
            data.t = 0
            local done = PollTitle(unit)
            if done or data.total >= 5 then PollingPlates[unit] = nil end
        end
    end

    -- Every 5 seconds, sweep for new plates
    if refreshTimer >= 5 then
        refreshTimer = 0
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = plate.unitToken
            if unit and not PollingPlates[unit] and not SeenPlates[unit] then
                PollingPlates[unit] = {t = 0, total = 0}
            end
        end
    end

    if next(PollingPlates) == nil then self:Hide() end
end)

-- Start polling a new unit
local function StartPolling(unit)
    if not SeenPlates[unit] then
        PollingPlates[unit] = {t = 0, total = 0}
        pollFrame:Show()
    end
end

-- Stop polling and hide title
local function StopPolling(unit)
    PollingPlates[unit] = nil
    SeenPlates[unit] = nil
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.TitleText then plate.TitleText:Hide() end
end

-- Refresh all visible nameplates
local function RefreshAllPlates()
    -- Hide any existing title text
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if plate.TitleText then plate.TitleText:Hide() end
    end
    -- Clear caches
    wipe(PollingPlates)
    wipe(SeenPlates)
    -- Restart polling for all visible plates
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.unitToken
        if unit then StartPolling(unit) end
    end
    pollFrame:Show()
end

-- Options panel in Interface menu
local options = CreateFrame("Frame", "NameplateTitlesOptions", UIParent)
options.name = "NameplateTitles"
InterfaceOptions_AddCategory(options)

options:SetScript("OnShow", function(self)
    if self.initted then return end
    local y = -20

    -- Creates a checkbox bound to db[key], with optional indent
    local function CreateCheck(key, label, indent)
        local frameName = addonName .. "_Check_" .. key:gsub("%.", "_")
        local cb = CreateFrame("CheckButton", frameName, options,
                               "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", indent and (36) or (16), y)
        _G[frameName .. "Text"]:SetText(label)

        local function get()
            local p, c = key:match("^(%w+)%.(%w+)$")
            if p and c then
                return db[p][c]
            else
                return db[key]
            end
        end
        local function set(val)
            val = val and true or false
            local p, c = key:match("^(%w+)%.(%w+)$")
            if p and c then
                db[p][c] = val
            else
                db[key] = val
            end
        end

        cb:SetChecked(get())
        cb:SetScript("OnClick", function()
            set(cb:GetChecked())
            RefreshAllPlates()
        end)

        y = y - 24
    end

    -- Group: Player
    CreateCheck("showPlayer", "Show Player Guilds")
    CreateCheck("player.friendly", "Friendly Players", true)
    CreateCheck("player.hostile", "Enemy Players", true)
    CreateCheck("player.neutral", "Any Other Players", true)

    y = y - 12 -- extra spacing between groups

    -- Group: NPC
    CreateCheck("showNPC", "Show NPC Job Titles")
    CreateCheck("npc.friendly", "Friendly NPCs", true)
    CreateCheck("npc.hostile", "Hostile NPCs", true)
    CreateCheck("npc.neutral", "Any Other NPCs", true)

    self.initted = true
end)

-- Event handling
f:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        NameplateTitlesDB = NameplateTitlesDB or {}
        db = NameplateTitlesDB
        -- Merge defaults, enforce booleans
        for k, v in pairs(defaults) do
            if type(v) == "table" then
                db[k] = db[k] or {}
                for sk, sv in pairs(v) do
                    db[k][sk] = (db[k][sk] == nil) and sv or
                                    (db[k][sk] and true or false)
                end
            else
                db[k] = (db[k] == nil) and v or (db[k] and true or false)
            end
        end

        -- Register nameplate events
        f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        -- Cleanup
        f:UnregisterEvent("ADDON_LOADED")

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        StartPolling(arg)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        StopPolling(arg)
    end
end)

f:RegisterEvent("ADDON_LOADED")
