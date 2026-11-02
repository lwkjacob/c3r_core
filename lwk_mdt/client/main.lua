--[[ lwk_mdt — client: open / close, NUI <-> server requests, lwk_control bridge. ]]

local is_open = false
local status = nil       -- last 10-code said over lwk_control
local queued_view = nil  -- record a plate / name check produced while the MDT was closed

local function log(fmt, ...)
    if Config.Debug then print(('[lwk_mdt] ' .. fmt):format(...)) end
end

local function notify(text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

local function control_running() return GetResourceState('lwk_control') == 'started' end

-- The callsign signed on with in the CAD (the server sets it on the player's state bag).
local function callsign() return LocalPlayer.state.lwkMdtCallsign or '' end

-- ─── server requests ─────────────────────────────────────────────────────────

local pending, next_id = {}, 0

local function request(name, args, cb)
    next_id = next_id + 1
    pending[next_id] = cb
    TriggerServerEvent('lwk_mdt:req', next_id, name, args or {})
end

RegisterNetEvent('lwk_mdt:res', function(id, res)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(res) end
end)

-- ─── open / close ────────────────────────────────────────────────────────────

-- On an allowed c3r service (police for now).
local function on_duty()
    local ok, service = pcall(function() return exports.c3r:getService() end)
    if not ok then return false end
    for _, s in ipairs(Config.AllowedServices) do
        if service and tostring(service):lower() == s:lower() then return true end
    end
    return false
end

local function open_mdt(view)
    if is_open then
        if view then SendNUIMessage({ type = 'show', view = view }) end
        return
    end
    is_open = true
    SetNuiFocus(true, true)
    if not on_duty() then return SendNUIMessage({ type = 'open', civ = true }) end -- off shift: Citizen Portal
    TriggerServerEvent('lwk_mdt:callsign', callsign())
    SendNUIMessage({
        type = 'open', status = status, view = view or queued_view,
        quick = control_running() and Config.Quick or {},
    })
    queued_view = nil
end

local function close_mdt()
    is_open = false
    SetNuiFocus(false, false)
end

-- Open only, never toggle: another resource's key on the same press (lwk_cad's F7 runs /mdt) would
-- otherwise close it again and leave the page up without a cursor. Esc / the X close it.
local function open() open_mdt() end
RegisterCommand(Config.OpenCommand, open, false)
RegisterCommand('lwk_mdt_toggle', open, false) -- old name kept so players' rebinds survive
RegisterKeyMapping('lwk_mdt_toggle', 'Open the MDT (lwk_mdt)', 'keyboard', Config.OpenKey)

RegisterNUICallback('close', function(_, cb) close_mdt() cb({}) end)

-- "Strawberry Ave / Davis Ave, Davis" for a position.
local function street_at(p)
    local s1, s2 = GetStreetNameAtCoord(p.x, p.y, p.z)
    local street = GetStreetNameFromHashKey(s1)
    if s2 ~= 0 then street = street .. ' / ' .. GetStreetNameFromHashKey(s2) end
    local zone = GetLabelText(GetNameOfZone(p.x, p.y, p.z))
    return street .. (zone ~= 'NULL' and (', ' .. zone) or '')
end

RegisterNUICallback('req', function(data, cb)
    -- the pop-out link uses the address this game is connected to, when the server has no better one
    if data.name == 'popout' then data.args = { endpoint = GetCurrentServerEndpoint() } end
    if data.name == 'civ911' then -- the caller's position goes with the call
        local p = GetEntityCoords(PlayerPedId())
        data.args = { text = type(data.args) == 'table' and data.args.text or nil, x = p.x, y = p.y, z = p.z, location = street_at(p) }
    end
    request(data.name, data.args, function(res) cb(res or { error = 'No answer from the server.' }) end)
end)

RegisterNUICallback('run', function(data, cb)
    cb({})
    if not control_running() or type(data.intent) ~= 'string' then return end
    pcall(function() exports.lwk_control:run(data.intent) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and is_open then SetNuiFocus(false, false) end
end)

-- ─── server -> client ────────────────────────────────────────────────────────

-- Street and area at the start of an incident: "Strawberry Ave / Davis Ave, Davis".
RegisterNetEvent('lwk_mdt:where', function(id)
    TriggerServerEvent('lwk_mdt:location', id, street_at(GetEntityCoords(PlayerPedId())))
end)

RegisterNetEvent('lwk_mdt:notify', function(text) if type(text) == 'string' then notify(text) end end)

-- "Set Waypoint" on a 911 call (in game or from the browser pop-out).
RegisterNetEvent('lwk_mdt:waypoint', function(x, y)
    if tonumber(x) and tonumber(y) then SetNewWaypoint(x + 0.0, y + 0.0) end
end)

-- ─── citizen commands ────────────────────────────────────────────────────────

-- Nearest named colour to the paint, for /vehreg.
local COLORS = {
    { 'Black', 15, 15, 15 }, { 'Grey', 90, 90, 90 }, { 'Silver', 165, 165, 165 }, { 'White', 235, 235, 235 },
    { 'Red', 170, 20, 20 }, { 'Maroon', 100, 15, 20 }, { 'Orange', 220, 110, 20 }, { 'Yellow', 230, 200, 30 },
    { 'Gold', 180, 140, 60 }, { 'Green', 30, 120, 40 }, { 'Dark Green', 20, 60, 30 }, { 'Blue', 30, 60, 170 },
    { 'Dark Blue', 15, 25, 70 }, { 'Light Blue', 90, 150, 220 }, { 'Purple', 90, 40, 130 }, { 'Pink', 220, 100, 170 },
    { 'Brown', 100, 65, 35 }, { 'Beige', 200, 180, 140 },
}

local function color_name(veh)
    local r, g, b = GetVehicleColor(veh)
    local best, best_d
    for _, c in ipairs(COLORS) do
        local d = (r - c[2]) ^ 2 + (g - c[3]) ^ 2 + (b - c[4]) ^ 2
        if not best_d or d < best_d then best, best_d = c[1], d end
    end
    return best
end

local function label(text)
    local l = GetLabelText(text)
    return l ~= 'NULL' and l or nil
end

RegisterCommand('vehreg', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return notify('~r~/vehreg:~s~ sit in the driver seat first.') end
    local hash = GetEntityModel(veh)
    TriggerServerEvent('lwk_mdt:vehreg', {
        plate = GetVehicleNumberPlateText(veh), make = label(GetMakeNameFromVehicleModel(hash)),
        model = label(GetDisplayNameFromVehicleModel(hash)), color = color_name(veh),
    })
end, false)

RegisterCommand('showid', function()
    local me, my_pos = PlayerId(), GetEntityCoords(PlayerPedId())
    local best, best_d
    for _, pl in ipairs(GetActivePlayers()) do
        if pl ~= me then
            local d = #(GetEntityCoords(GetPlayerPed(pl)) - my_pos)
            if d < 3.0 and (not best_d or d < best_d) then best, best_d = pl, d end
        end
    end
    TriggerServerEvent('lwk_mdt:showid', best and GetPlayerServerId(best) or nil)
end, false)

RegisterNetEvent('lwk_mdt:idcard', function(c)
    if type(c) ~= 'table' then return end
    notify(('~b~ID CARD~s~~n~%s~n~DOB %s · %s~n~%s~n~Licence: %s'):format(tostring(c.name):upper(), tostring(c.dob),
        tostring(c.gender), tostring(c.address or ''), tostring(c.dl)))
end)

-- ─── 911 alerts (on-duty officers) ───────────────────────────────────────────

local alerts = {} -- [call id] = { area blip, centre blip }

local function clear_alert(id)
    for _, b in ipairs(alerts[id] or {}) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    alerts[id] = nil
end

RegisterNetEvent('lwk_mdt:911', function(a)
    if type(a) ~= 'table' or not tonumber(a.x) or not tonumber(a.y) then return end
    clear_alert(a.id)
    local area = AddBlipForRadius(a.x + 0.0, a.y + 0.0, 0.0, (tonumber(a.radius) or 180) + 0.0)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 90)
    local pin = AddBlipForCoord(a.x + 0.0, a.y + 0.0, 0.0)
    SetBlipColour(pin, 1)
    SetBlipFlashes(pin, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('911 Call #' .. tostring(a.id))
    EndTextCommandSetBlipName(pin)
    alerts[a.id] = { area, pin }
    SetTimeout((tonumber(a.ttl) or 900) * 1000, function() clear_alert(a.id) end)
    local text = ('~r~911 CALL #%s~s~ %s~n~%s~n~Respond in the MDT (/%s).'):format(tostring(a.id), tostring(a.location or ''),
        tostring(a.text or ''), Config.OpenCommand)
    if control_running() then -- dispatch reads it out like any other transmission
        local res = GetCurrentResourceName()
        local clip = LoadResourceFile(res, 'sounds/call911_1.ogg') and { ('https://cfx-nui-%s/sounds/call911_1.ogg'):format(res) } or nil
        pcall(function() exports.lwk_control:say(clip, text) end)
    else
        notify(text)
    end
end)

RegisterNetEvent('lwk_mdt:911done', clear_alert)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(alerts) do clear_alert(id) end
end)

RegisterNetEvent('lwk_mdt:drafted', function(id)
    notify(('~b~MDT~s~ Report #%d drafted, review it in /%s.'):format(id, Config.OpenCommand))
end)

-- A plate or name check over the radio: show the record now, or when the MDT next opens.
RegisterNetEvent('lwk_mdt:show', function(view)
    if is_open then SendNUIMessage({ type = 'show', view = view }) else queued_view = view end
end)

-- ─── lwk_control bridge ──────────────────────────────────────────────────────

-- A status-bar button pressed in the browser pop-out: the server checked it against Config.Quick.
RegisterNetEvent('lwk_mdt:run', function(intent)
    if control_running() and type(intent) == 'string' then pcall(function() exports.lwk_control:run(intent) end) end
end)

-- Unit board: report shift, callsign and 10-code whenever one changes (checked every 10 s).
local last_unit = nil

local function report_unit()
    local on = on_duty()
    local now = json.encode({ on, callsign(), status })
    if now == last_unit then return end
    last_unit = now
    TriggerServerEvent('lwk_mdt:unit', on, callsign(), status)
end

CreateThread(function()
    while true do
        report_unit()
        Wait(10000)
    end
end)

AddEventHandler('lwk_control:status', function(code)
    status = code
    report_unit()
    if is_open then SendNUIMessage({ type = 'status', status = status }) end
end)

AddEventHandler('lwk_control:ran', function(id, ctx)
    ctx = type(ctx) == 'table' and ctx or {}
    log('control ran %s', tostring(id))
    TriggerServerEvent('lwk_mdt:action', id, { plate = ctx.plate, code = ctx.code, verb = ctx.verb })
end)

local function register_intents()
    if not control_running() then return end
    exports.lwk_control:addIntent({
        id = 'mdt_open',
        say = { 'open the computer', 'open my computer', 'open the laptop', 'open my laptop' },
        run = function() open_mdt() end,
    })
    exports.lwk_control:addIntent({
        id = 'mdt_write_up',
        say = { 'write it up', 'start a report', 'start the paperwork', 'start a citation', 'write a citation',
                'write a ticket' },
        run = function(ctx)
            local text = type(ctx) == 'table' and ctx.text or ''
            local form = (text:find('citation') or text:find('ticket')) and 'citation' or nil
            request('writeUp', {}, function(res)
                if res and res.id then open_mdt({ type = 'report', id = res.id, form = form })
                else notify('~b~MDT~s~ Nothing to write up yet.') end
            end)
        end,
    })
end

CreateThread(register_intents)
AddEventHandler('onClientResourceStart', function(res)
    if res == 'lwk_control' then register_intents() end
end)

TriggerServerEvent('lwk_mdt:hello')
