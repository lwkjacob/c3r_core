--[[ c3r — client: duty, and the exports other resources read the officer's state from. ]]

function Notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function on_duty() return LocalPlayer.state.c3rDuty == true end

exports('isOnDuty', on_duty)
exports('getService', function() return on_duty() and 'police' or nil end) -- one role for now
exports('setDuty', function(on)
    TriggerServerEvent('c3r:setDuty', on == true)
    return true
end)

RegisterCommand(Config.DutyCommand, function() TriggerServerEvent('c3r:setDuty', not on_duty()) end, false)

-- The service screen (F11): pick a service to go on duty, or end the shift. Police only for now.
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
    SendNUIMessage({ type = 'duty', open = true, on = on_duty(), key = KeyName('+c3r_duty', 'F11') })
end, false)
RegisterCommand('-c3r_duty', function() end, false)
RegisterKeyMapping('+c3r_duty', 'Service screen: go on / off duty (c3r)', 'keyboard', Config.DutyKey)

RegisterNUICallback('duty', function(d, cb)
    cb({})
    close_duty()
    if d.service == 'police' then TriggerServerEvent('c3r:setDuty', not on_duty()) end
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

RegisterNetEvent('c3r:config:open', function(files, msg)
    if IsNuiFocused() and not cfg_open then return end -- another menu is up
    cfg_open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'config', open = true, files = files, msg = msg })
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

AddStateBagChangeHandler('c3rDuty', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, on)
    Notify(on and '~b~C~w~3~r~R~s~ You are ~g~on duty~s~.' or '~b~C~w~3~r~R~s~ You are ~r~off duty~s~.')
end)

RegisterNetEvent('c3r:dutyResult', function(ok, reason)
    if not ok then Notify('~b~C~w~3~r~R~s~ ' .. (reason == 'not_allowed' and 'You are not allowed to go on duty.' or 'Unable.')) end
end)
