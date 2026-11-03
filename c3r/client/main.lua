--[[ c3r — client: duty, and the exports other resources read the officer's state from. ]]

-- GTA cuts a text component off at 99 bytes, and its 'STRING' label holds only one. Longer text goes in as several
-- pieces (never split inside a ~colour~ code or a multi-byte character), under a label with a slot for each:
-- BeginLongText(BeginTextCommandPrint, text), then end the command as usual.
local function pieces_of(text)
    local out, i = {}, 1
    while i <= #text do
        local j = math.min(i + 98, #text)
        if j < #text then
            local piece = text:sub(i, j)
            local _, tildes = piece:gsub('~', '')
            if tildes % 2 == 1 then j = i + piece:match('.*()~') - 2 end -- (a ~code~ would be cut: stop before it)
            while j > i and text:byte(j + 1) and text:byte(j + 1) >= 0x80 and text:byte(j + 1) < 0xC0 do j = j - 1 end
        end
        out[#out + 1] = text:sub(i, j)
        i = j + 1
    end
    return out
end

function BeginLongText(begin, text)
    local list = pieces_of(tostring(text))
    local label = 'C3R_TEXT_' .. #list
    AddTextEntry(label, string.rep('~a~', #list))
    begin(label)
    for _, p in ipairs(list) do AddTextComponentSubstringPlayerName(p) end
end

function Notify(msg)
    BeginLongText(BeginTextCommandThefeedPost, msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function on_duty() return LocalPlayer.state.c3rDuty == true end

exports('isOnDuty', on_duty)
exports('getService', function() return on_duty() and LocalPlayer.state.c3rService or nil end)
exports('setDuty', function(on, service)
    TriggerServerEvent('c3r:setDuty', on == true, service)
    return true
end)

-- On shift as police: pull-overs, staged violators and the PA are theirs alone.
function OnPatrol() return on_duty() and LocalPlayer.state.c3rService == 'police' end

-- /duty, or /duty ambulance
RegisterCommand(Config.DutyCommand, function(_, args) TriggerServerEvent('c3r:setDuty', not on_duty(), args[1]) end, false)

-- The service screen (F11): pick a service to go on duty, or end the shift.
local duty_open = false
local function close_duty()
    if not duty_open then return end
    duty_open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'duty', open = false })
    NoPause()
end

RegisterCommand('+c3r_duty', function()
    if duty_open then return close_duty() end
    if IsNuiFocused() then return end -- another menu is up
    duty_open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'duty', open = true, on = on_duty(), service = LocalPlayer.state.c3rService, key = KeyName('+c3r_duty', 'F11') })
end, false)
RegisterCommand('-c3r_duty', function() end, false)
RegisterKeyMapping('+c3r_duty', 'Service screen: go on / off duty (c3r)', 'keyboard', Config.DutyKey)

RegisterNUICallback('duty', function(d, cb)
    cb({})
    close_duty()
    if d.service then TriggerServerEvent('c3r:setDuty', not on_duty(), d.service) end
end)
RegisterNUICallback('dutyClose', function(_, cb)
    cb({})
    close_duty()
end)

-- /c3rconfig (server/config_edit.lua): the editor, for admins, and its changes, live for everyone.
local cfg_open = false
local function close_cfg()
    if not cfg_open then return end
    cfg_open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'config', open = false })
    NoPause()
end

RegisterNetEvent('c3r:config:open', function(tabs, msg)
    if IsNuiFocused() and not cfg_open then return end -- another menu is up
    cfg_open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'config', open = true, tabs = tabs, msg = msg })
end)
RegisterNUICallback('configSave', function(d, cb)
    cb({})
    if cfg_open and type(d.changes) == 'table' then TriggerServerEvent('c3r:config:save', d.changes) end
end)
RegisterNUICallback('configList', function(d, cb) -- a list's entry added or taken out
    cb({})
    if cfg_open then TriggerServerEvent('c3r:config:list', d.file, d.path, d.action, d.index) end
end)
RegisterNUICallback('configHere', function(_, cb) -- "Set here": where the admin is standing
    local p = GetEntityCoords(PlayerPedId())
    cb({ x = p.x, y = p.y, z = p.z })
end)
RegisterNUICallback('configClose', function(_, cb)
    cb({})
    close_cfg()
end)

RegisterNetEvent('c3r:config:set', function(list)
    for _, c in ipairs(list) do
        local t = Config
        for i = 1, #c.keys - 1 do t = type(t) == 'table' and t[c.keys[i]] or nil end
        if type(t) == 'table' then t[c.keys[#c.keys]] = c.value end
    end
end)
TriggerServerEvent('c3r:config:sync') -- (changed since c3r started: this game loaded the files as they were)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then close_duty() close_cfg() end
end)

-- Going on duty: a boom, a small shake, a white wall sweeping out from where you stand: 250 m in 2.8 s, floor to sky (the
-- marker starts 200 m underground so its bottom never shows), then gone; and the welcome screen over the game, blurred
-- for as long as it's up. Only on your own game.
local SHIFT_MS = 2600
local function duty_fx()
    local pos = GetEntityCoords(PlayerPedId())
    SendNUIMessage({ type = 'sfx', name = 'duty' })
    SendNUIMessage({ type = 'shift', ms = SHIFT_MS })
    ShakeGameplayCam('EXPLOSION_SHAKE', 0.15)
    TriggerScreenblurFadeIn(300.0)
    SetTimeout(SHIFT_MS, function() TriggerScreenblurFadeOut(350.0) end)
    CreateThread(function()
        local duration, radius = 2800, 250.0
        local started = GetGameTimer()
        while GetGameTimer() - started < duration do
            local t = (GetGameTimer() - started) / duration
            local size = radius * t * 2
            DrawMarker(1, pos.x, pos.y, pos.z - 200.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 1000.0,
                255, 255, 255, math.floor(200 * (1.0 - t)), false, false, 2, false, nil, nil, false)
            Wait(0)
        end
    end)
end

AddStateBagChangeHandler('c3rDuty', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, on)
    Notify(on and '~b~C~w~3~r~R~s~ You are ~g~on duty~s~.' or '~b~C~w~3~r~R~s~ You are ~r~off duty~s~.')
    if on then duty_fx() end
end)

RegisterNetEvent('c3r:dutyResult', function(ok, reason)
    if not ok then Notify('~b~C~w~3~r~R~s~ ' .. (reason == 'not_allowed' and 'You are not allowed to go on duty.' or 'Unable.')) end
end)
