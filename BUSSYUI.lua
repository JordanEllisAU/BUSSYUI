-- BUSSYUI.lua
-- Minimal "busy" status indicator for World of Warcraft: Midnight (12.0.x).
--
-- Shows a small draggable frame that reports one of four states:
--   * CASTING  — the player is casting or channeling a spell.
--   * COMBAT   — the player is in combat (regen disabled).
--   * GCD      — the player is off-global-cooldown-locked.
--   * READY    — none of the above.
--
-- State precedence (highest first): CASTING > COMBAT > GCD > READY.
-- All API calls are confirmed against warcraft.wiki.gg for patch 12.0.5.

local ADDON, NS = "BUSSYUI", {}
NS.version = "1.0.0"

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

local DEFAULTS = {
    point = "CENTER",
    relTo = "UIParent",
    relPoint = "CENTER",
    x = 0,
    y = -120,
    scale = 1.0,
    locked = true,
    showGcd = true,
    width = 160,
    height = 36,
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

NS.db = nil          -- saved variables, merged with DEFAULTS
NS.frame = nil       -- root draggable frame (created in BuildUI)
NS.label = nil       -- status label fontstring
NS.isCasting = false
NS.isCombat = false
NS.gcdEnd = 0        -- GetTime() at which the current GCD finishes; 0 = none
NS.gcdProbeID = nil  -- cached spellID used to sample the GCD (resolved once at Init)

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

-- Merge user DB onto DEFAULTS so missing keys never index nil.
-- Pure: returns a new table; does not mutate either input.
function NS.MergeDefaults(user, defaults)
    local out = {}
    for k, v in pairs(defaults) do
        out[k] = v
    end
    if type(user) == "table" then
        for k, v in pairs(user) do
            out[k] = v
        end
    end
    return out
end

-- Persist current frame layout into NS.db. Called on drag end and on lock.
function NS.SaveLayout()
    if not (NS.db and NS.frame) then return end
    local point, _, relPoint, x, y = NS.frame:GetPoint(1)
    NS.db.point = point or DEFAULTS.point
    NS.db.relPoint = relPoint or DEFAULTS.relPoint
    NS.db.x = x or 0
    NS.db.y = y or 0
    NS.db.scale = NS.frame:GetScale() or DEFAULTS.scale
end

-- ---------------------------------------------------------------------------
-- State classification
-- ---------------------------------------------------------------------------

-- Pure: given the current state flags + time, return the active status key.
-- Returns one of: "CASTING", "COMBAT", "GCD", "READY".
function NS.ClassifyState(now, isCasting, isCombat, gcdEnd, showGcd)
    if isCasting then return "CASTING" end
    if isCombat then return "COMBAT" end
    if showGcd and gcdEnd and gcdEnd > now then return "GCD" end
    return "READY"
end

-- Display configuration per state. Colors are RGB 0..1.
local STATE_CONFIG = {
    CASTING = { text = "BUSY · CASTING", r = 0.20, g = 0.55, b = 1.00 },
    COMBAT  = { text = "BUSY · COMBAT",  r = 1.00, g = 0.30, b = 0.20 },
    GCD     = { text = "BUSY · GCD",     r = 1.00, g = 0.80, b = 0.20 },
    READY   = { text = "READY",          r = 0.30, g = 0.85, b = 0.40 },
}

-- Apply the current state to the frame label. Idempotent.
function NS.Render()
    if not (NS.label and NS.frame) then return end
    local now = GetTime()
    local key = NS.ClassifyState(now, NS.isCasting, NS.isCombat, NS.gcdEnd, NS.db.showGcd)
    local cfg = STATE_CONFIG[key]
    NS.label:SetText(cfg.text)
    NS.label:SetTextColor(cfg.r, cfg.g, cfg.b)
end

-- ---------------------------------------------------------------------------
-- GCD tracking
-- ---------------------------------------------------------------------------

-- Sample the GCD using the cached probe spellID.
-- Uses C_Spell.GetSpellCooldown (modern 12.x API). Returns gcdEnd (GetTime) or 0.
-- SpellCooldownInfo fields (warcraft.wiki.gg, 12.0.5): startTime, duration,
-- isEnabled (boolean), isActive (boolean). NOT start/enable.
function NS.SampleGcd()
    if not NS.gcdProbeID then return 0 end
    local cd = C_Spell.GetSpellCooldown(NS.gcdProbeID)
    if not cd then return 0 end
    -- GCD is <= 1.5s; real cooldowns are longer. isEnabled filters "on hold" CDs.
    if cd.duration and cd.duration > 0 and cd.duration <= 1.5 and cd.isEnabled then
        return (cd.startTime or 0) + cd.duration
    end
    return 0
end

-- Resolve a spellID to use as the GCD probe by scanning the player spellbook.
-- Enumerates skill lines, then slots within each line via GetSpellBookItemInfo.
-- Returns a spellID (number) or nil if no suitable spell is found.
-- Called once at Init; result cached in NS.gcdProbeID.
function NS.ResolveGcdProbeSpellID()
    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    if not numLines then return nil end
    local bank = Enum.SpellBookSpellBank.Player -- 0
    for lineIdx = 1, numLines do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
        if line and line.numSpellBookItems and line.numSpellBookItems > 0 then
            local first = (line.itemIndexOffset or 0) + 1
            local last = first + line.numSpellBookItems - 1
            for slot = first, last do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if info and info.spellID and C_SpellBook.IsSpellKnown(info.spellID) then
                    return info.spellID
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------------

NS.eventFrame = CreateFrame("Frame")

function NS.OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        NS.Init()
        return
    end
    if not NS.db then return end -- ignore events before Init

    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        local unit = ...
        if unit == "player" then
            NS.isCasting = true
            NS.Render()
        end
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED" then
        local unit = ...
        if unit == "player" then
            NS.isCasting = false
            NS.gcdEnd = NS.SampleGcd()
            NS.Render()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        NS.isCombat = true
        NS.Render()
    elseif event == "PLAYER_REGEN_ENABLED" then
        NS.isCombat = false
        NS.Render()
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- Cheap GCD refresh on every spell sent; SampleGcd no-ops if not on GCD.
        NS.gcdEnd = NS.SampleGcd()
        NS.Render()
    elseif event == "PLAYER_LOGOUT" then
        NS.SaveLayout()
    end
end

NS.eventFrame:SetScript("OnEvent", NS.OnEvent)

NS.eventFrame:RegisterEvent("PLAYER_LOGIN")
-- The rest are registered in Init() once db is loaded.

-- ---------------------------------------------------------------------------
-- UI construction
-- ---------------------------------------------------------------------------

function NS.BuildUI()
    local f = CreateFrame("Frame", "BUSSYUIFrame", UIParent, "BackdropTemplate")
    f:SetSize(NS.db.width, NS.db.height)
    f:SetScale(NS.db.scale)
    f:SetPoint(NS.db.point, _G[NS.db.relTo] or UIParent, NS.db.relPoint, NS.db.x, NS.db.y)
    f:SetMovable(true)
    f:SetResizable(false)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, 0.55)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    label:SetPoint("CENTER", f, "CENTER", 0, 0)
    label:SetText("READY")
    label:SetTextColor(0.3, 0.85, 0.4)
    NS.label = label

    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not NS.db.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(self)
        if self:IsMoving() then
            self:StopMovingOrSizing()
            NS.SaveLayout()
        end
    end)

    NS.frame = f
    NS.ApplyLockState()
end

function NS.ApplyLockState()
    if not NS.frame then return end
    if NS.db.locked then
        NS.frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    else
        NS.frame:SetBackdropBorderColor(1.0, 0.8, 0.2, 1.0)
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF66CCFF[BUSSYUI]|r " .. tostring(msg))
end

NS.SlashCommands = {}

function NS.SlashCommands.lock(args)
    NS.db.locked = true
    NS.ApplyLockState()
    Print("Locked.")
end

function NS.SlashCommands.unlock(args)
    NS.db.locked = false
    NS.ApplyLockState()
    Print("Unlocked — drag the frame to move it.")
end

function NS.SlashCommands.reset(args)
    for k, v in pairs(DEFAULTS) do NS.db[k] = v end
    NS.frame:ClearAllPoints()
    NS.frame:SetPoint(NS.db.point, UIParent, NS.db.relPoint, NS.db.x, NS.db.y)
    NS.frame:SetScale(NS.db.scale)
    NS.ApplyLockState()
    Print("Layout reset to defaults.")
end

function NS.SlashCommands.scale(args)
    local n = tonumber(args[1])
    if not n or n <= 0 then
        Print("Usage: /bussyui scale <0.5 - 3.0>")
        return
    end
    n = math.max(0.5, math.min(3.0, n))
    NS.db.scale = n
    NS.frame:SetScale(n)
    NS.SaveLayout()
    Print(string.format("Scale set to %.2f.", n))
end

function NS.SlashCommands.gcd(args)
    NS.db.showGcd = not NS.db.showGcd
    Print("GCD indicator " .. (NS.db.showGcd and "enabled" or "disabled") .. ".")
    NS.Render()
end

function NS.SlashCommands.help(args)
    Print("Commands: lock | unlock | reset | scale <n> | gcd | help")
end

local function SlashHandler(msg)
    local parts = {}
    for word in string.gmatch(msg or "", "%S+") do
        parts[#parts + 1] = word
    end
    if #parts == 0 then
        NS.SlashCommands.help({})
        return
    end
    local cmd = string.lower(parts[1])
    local argList = {}
    for i = 2, #parts do argList[#argList + 1] = parts[i] end

    local fn = NS.SlashCommands[cmd]
    if fn then
        fn(argList)
    else
        Print("Unknown command: " .. tostring(cmd))
        NS.SlashCommands.help({})
    end
end

SLASH_BUSSYUI1 = "/bussyui"
SLASH_BUSSYUI2 = "/busyui"
SlashCmdList["BUSSYUI"] = SlashHandler

-- ---------------------------------------------------------------------------
-- Init / lifecycle
-- ---------------------------------------------------------------------------

function NS.Init()
    NS.db = NS.MergeDefaults(BUSSYUI_DB, DEFAULTS)
    BUSSYUI_DB = NS.db -- promote merged table so SavedVariables persists it

    NS.BuildUI()

    -- Resolve and cache the GCD probe spellID once (O(n) spellbook scan).
    NS.gcdProbeID = NS.ResolveGcdProbeSpellID()

    -- Register runtime events now that db exists.
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    NS.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    NS.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    NS.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    NS.eventFrame:RegisterEvent("PLAYER_LOGOUT")

    -- Seed combat state (we may have logged in mid-combat).
    NS.isCombat = UnitAffectingCombat("player")
    NS.gcdEnd = NS.SampleGcd()
    NS.Render() -- single render after all state is seeded

    Print("v" .. NS.version .. " loaded. /bussyui for commands.")
end

-- Note: Init() is invoked from the PLAYER_LOGIN event handler above.
