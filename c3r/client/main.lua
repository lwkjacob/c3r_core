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
