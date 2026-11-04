--[[
    c3r — client: the player's Discord activity (config/presence.lua). FiveM takes one string and splits it at the first
    newline, the part after it going on top. The timer is FiveM's: time since joining the server.
]]

local P = Config.Presence or {}

local call = nil -- the call I'm on: { name, arrived }
local shift = {} -- [stat] = how many this shift (server/presence.lua)
local sent = {}  -- [native] = its last value: Discord only takes an update every 15 s, so nothing goes twice
local buttons_set, was_on = false, false

RegisterNetEvent('c3r:callout:joined', function(r) call = { name = r.name } end)
RegisterNetEvent('c3r:callout:card', function(card) if call then call.arrived = card.arrived end end)
RegisterNetEvent('c3r:callout:ended', function() call = nil end)
RegisterNetEvent('c3r:presence:stat', function(stat, n) shift[stat] = (shift[stat] or 0) + n end)

-- A callout outranks the stops inside it; a chase outranks the callout.
local function doing()
    if not LocalPlayer.state.c3rDuty then return 'off' end
    if LocalPlayer.state.c3rService == 'ambulance' then -- (client/ems.lua: a patient aboard)
        if EmsAboard and EmsAboard() then return 'transport' end
        if call then return call.arrived and 'scene' or 'callout' end
        return 'ems'
    end
    local s = Stop
    if s and s.pursuit then return 'pursuit' end
    for _, o in pairs(s and s.occ or {}) do
        if o.fleeing then return 'chase' end
    end
    if call then return call.arrived and 'scene' or 'callout' end
    if not s then return 'patrol' end
    if s.felony then return 'felony' end
    return (s.foot or s.parked or s.empty) and 'contact' or 'stop'
end

local function unit()
    local cs = GetResourceState('lwk_control') == 'started' and exports.lwk_control:getCallsign()
        or LocalPlayer.state.lwkMdtCallsign
    if LocalPlayer.state.c3rService == 'ambulance' then return cs and cs ~= '' and cs or P.noCallsignMedic or 'Paramedic' end
    return cs and cs ~= '' and cs or P.noCallsign
end

local function push(native, value)
    if sent[native] ~= value then
        sent[native] = value
        native(value)
    end
end

-- Join first; a button with no valid url gives its place up, and FiveM would drop it silently anyway.
local function set_buttons()
    local slot = 0
    for _, b in ipairs({ P.join or {}, P.website or {} }) do
        local url = b.url or ''
        if b.label and b.label ~= '' and (url:find('^https://') or url:find('^fivem://connect/')) then
            SetDiscordRichPresenceAction(slot, b.label:sub(1, 32), url)
            slot = slot + 1
        end
    end
end

local function update()
    if not tostring(P.appId or ''):match('^%d+$') then return end
    local on = LocalPlayer.state.c3rDuty == true
    if on and not was_on then shift = {} end
    was_on = on

    local state = P.states[doing()] or P.states.patrol or {} -- (a config from before a state was added)
    local online = GlobalState.c3rOnline or {}
    local values = { unit = unit(), call = call and call.name or '', players = online.players or 0,
                     max = online.max or 0, duty = online.duty or 0 }
    local function fill(text)
        text = text or ''
        return (text:gsub('{([%w_]+)}', function(k) return values[k] or shift[k] or 0 end))
    end

    push(SetDiscordAppId, tostring(P.appId))
    if not buttons_set then
        buttons_set = true
        set_buttons()
    end
    push(SetDiscordRichPresenceAsset, P.large or '')
    push(SetDiscordRichPresenceAssetText, P.largeText or '')
    push(SetDiscordRichPresenceAssetSmall, state.icon or '')
    push(SetDiscordRichPresenceAssetSmallText, fill(state.hover or P.hover or ''))
    push(SetRichPresence, fill(P.line or '') .. '\n' .. fill(state.text))
end

CreateThread(function()
    while true do
        update()
        Wait(5000)
    end
end)
