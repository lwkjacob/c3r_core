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

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then close_duty() end
end)

AddStateBagChangeHandler('c3rDuty', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, on)
    Notify(on and '~b~C~w~3~r~R~s~ You are ~g~on duty~s~.' or '~b~C~w~3~r~R~s~ You are ~r~off duty~s~.')
end)

RegisterNetEvent('c3r:dutyResult', function(ok, reason)
    if not ok then Notify('~b~C~w~3~r~R~s~ ' .. (reason == 'not_allowed' and 'You are not allowed to go on duty.' or 'Unable.')) end
end)
