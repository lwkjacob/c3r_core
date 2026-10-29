--[[
    c3r — client: callouts (server/callouts.lua). The offer card (Y responds), the waypoint to the call, the objective
    card (Backspace hides / shows it), and leaving the call (X, then "Leave this call?"). Clearing with dispatch
    (lwk_control's "code four") leaves it too, through completeCallout.
]]

local board = {}   -- the open calls: { { id, name, street, coords, priority, description, units } }
local offer = nil  -- the call on the offer card while it's up
local call = nil   -- the call I'm on: its record, and its blip
local hidden, last_text = false, nil
local confirming = false

local REFUSED = { already_on_call = 'You are already on a call.', off_duty = 'You are not on duty.',
                  no_callout = 'No call available near you right now.' }

local function clear_blip()
    if call and call.blip and DoesBlipExist(call.blip) then RemoveBlip(call.blip) end
end

RegisterNetEvent('c3r:callout:board', function(list) board = type(list) == 'table' and list or {} end)

RegisterNetEvent('c3r:callout:offer', function(r)
    if call then return end
    local ms = ((Config.Callouts or {}).offer_window or 30) * 1000
    offer = r
    offer.until_t = GetGameTimer() + ms
    for _, b in ipairs(board) do if b.id == r.id then r.units = b.units end end
    SendNUIMessage({ type = 'callout', offer = { name = r.name, street = r.street, distance = r.distance, report = r.description,
        priority = r.priority, units = r.units, key = KeyName('+c3r_respond', 'Y'), decline = KeyName('+c3r_leavecall', 'X'), ms = ms } })
    pcall(function() exports.lwk_control:say(nil, ('All units, %s, %s. Priority %d.'):format(r.name:lower(), r.street, r.priority)) end)
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false) -- UNVERIFIED: sound name / set
end)

RegisterNetEvent('c3r:callout:joined', function(r)
    offer = nil
    SendNUIMessage({ type = 'callout', offer = false })
    clear_blip()
    call, hidden, last_text = r, false, nil
    local at = r.coords
    call.blip = AddBlipForCoord(at.x, at.y, at.z)
    SetBlipSprite(call.blip, 280) -- (a person with an exclamation mark)
    SetBlipColour(call.blip, 1)
    SetBlipRoute(call.blip, true)
    SetBlipRouteColour(call.blip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(r.name)
    EndTextCommandSetBlipName(call.blip)
end)

RegisterNetEvent('c3r:callout:card', function(card)
    if not call or card.id ~= call.id then return end
    if card.arrived and call.blip and DoesBlipExist(call.blip) then SetBlipRoute(call.blip, false) end
    local text = card.mine[1] and card.mine[1].text
    if hidden and text and text ~= last_text then Prompt('callout', 'info', 'New objective', text, 5000) end
    last_text = text
    SendNUIMessage({ type = 'callout', card = card, hidden = hidden, keys = { hide = KeyName('+c3r_objective', 'BACKSPACE'),
        leave = KeyName('+c3r_leavecall', 'X') } })
end)

local function close_confirm()
    if not confirming then return end
    confirming = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'callout', confirm = false })
    NoPause()
end

RegisterNetEvent('c3r:callout:ended', function(completed, summary)
    close_confirm()
    clear_blip()
    call = nil
    SendNUIMessage({ type = 'callout', card = false })
    if completed then
        Prompt('callout', 'ok', 'Callout complete', summary or 'Dispatch shows you clear.', 7000)
    else
        Prompt('callout', 'info', 'Off the call', 'You are clear of the call.', 5000)
    end
end)

RegisterNetEvent('c3r:callout:refused', function(why)
    Prompt('callout', 'info', 'Unable', REFUSED[why] or tostring(why), 4000)
end)

-- A radio update from the call (the story): dispatch says it.
RegisterNetEvent('c3r:callout:dispatch', function(text, clips)
    local ok = pcall(function() exports.lwk_control:say(clips, text) end)
    if not ok then Notify('~b~DISPATCH~s~ ' .. tostring(text)) end
end)

-- ─── keys ─────────────────────────────────────────────────────────────────────

local function respond(id) TriggerServerEvent('c3r:callout:respond', id) end

RegisterCommand('+c3r_respond', function()
    if call or not offer or GetGameTimer() > offer.until_t or IsNuiFocused() then return end
    respond(offer.id)
end, false)
RegisterCommand('-c3r_respond', function() end, false)
RegisterKeyMapping('+c3r_respond', 'Callout: respond (c3r)', 'keyboard', Config.RespondKey or 'Y')

RegisterCommand('respond', function() if not call then respond(nil) end end, false) -- the nearest open call

RegisterCommand('+c3r_objective', function()
    -- (Backspace also closes the who-to-talk-to and driver pickers: those turn it off while they're open)
    if not call or IsNuiFocused() or not IsControlEnabled(0, 177) then return end
    hidden = not hidden
    SendNUIMessage({ type = 'callout', hidden = hidden })
end, false)
RegisterCommand('-c3r_objective', function() end, false)
RegisterKeyMapping('+c3r_objective', 'Callout: hide / show the objective (c3r)', 'keyboard', Config.ObjectiveKey or 'BACK')

RegisterCommand('+c3r_leavecall', function()
    -- (X is also the taser's arc and the Stop Stick's let-go: not while either is in hand)
    if confirming or IsNuiFocused() or LocalPlayer.state.taser or LocalPlayer.state.stopstick then return end
    if not call and offer and GetGameTimer() < offer.until_t then -- an offer up: decline it (it stays open for others)
        offer = nil
        return SendNUIMessage({ type = 'callout', offer = false })
    end
    if not call then return end
    confirming = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'callout', confirm = true, name = call.name })
end, false)
RegisterCommand('-c3r_leavecall', function() end, false)
RegisterKeyMapping('+c3r_leavecall', 'Callout: decline the offer / leave the call (c3r)', 'keyboard', Config.LeaveCallKey or 'X')

RegisterNUICallback('calloutLeave', function(d, cb)
    cb({})
    close_confirm()
    if d.leave and call then TriggerServerEvent('c3r:callout:leave') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    close_confirm()
    clear_blip()
end)

TriggerServerEvent('c3r:callout:sync') -- (the calls open now)

-- ─── the contract (docs/contract.md) ──────────────────────────────────────────

exports('isOnCallout', function() return call ~= nil end)
exports('isOfferedCallout', function() return call == nil and board[1] ~= nil end) -- an open call I could join
exports('acceptCallout', function()
    if call then return nil, 'already_on_call' end
    if not board[1] then return nil, 'no_callout' end
    respond(offer and GetGameTimer() < offer.until_t and offer.id or nil)
    return true
end)
exports('completeCallout', function() -- clearing with dispatch: off the call
    if not call then return nil, 'not_attached' end
    TriggerServerEvent('c3r:callout:leave')
    return true
end)
