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

-- The map marks who / what my objective is about (the caller, then the person or the car...), following them once
-- they're near enough to be in my game.
local marks = {} -- { { blip, net?, label, kind } }
local SPRITE = { person = 280, vehicle = 225, clue = 586 } -- UNVERIFIED: blip sprite ids (person / car / magnifier)

local function clear_marks()
    for _, m in ipairs(marks) do if DoesBlipExist(m.blip) then RemoveBlip(m.blip) end end
    marks = {}
end

local function mark(m)
    local ent = m.net and NetworkDoesNetworkIdExist(m.net) and NetToEnt(m.net) or 0
    local blip = DoesEntityExist(ent) and AddBlipForEntity(ent) or AddBlipForCoord(m.at.x, m.at.y, m.at.z)
    SetBlipSprite(blip, SPRITE[m.kind] or 1)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.85)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(m.label or 'Objective')
    EndTextCommandSetBlipName(blip)
    m.blip, m.on_entity = blip, DoesEntityExist(ent)
    marks[#marks + 1] = m
end

local function set_marks(card)
    clear_marks()
    for _, item in ipairs(card and card.mine or {}) do
        for _, b in ipairs(item.blips or {}) do mark(b) end
    end
end

CreateThread(function() -- a mark on a spot becomes one on the person / car once they're in my game
    while true do
        Wait(2000)
        for i, m in ipairs(marks) do
            if not m.on_entity and m.net and NetworkDoesNetworkIdExist(m.net) and DoesEntityExist(NetToEnt(m.net)) then
                if DoesBlipExist(m.blip) then RemoveBlip(m.blip) end
                table.remove(marks, i)
                mark(m)
                break
            end
        end
    end
end)

RegisterNetEvent('c3r:callout:board', function(list) board = type(list) == 'table' and list or {} end)

RegisterNetEvent('c3r:callout:offer', function(r)
    if call then return end
    local ms = ((Config.Callouts or {}).offer_window or 30) * 1000
    offer = r
    offer.until_t = GetGameTimer() + ms
    for _, b in ipairs(board) do if b.id == r.id then r.units = b.units end end
    SendNUIMessage({ type = 'callout', offer = { name = r.name, street = r.street, distance = r.distance, report = r.description,
        priority = r.priority, units = r.units, key = KeyName('+c3r_respond', 'Y'), decline = KeyName('+c3r_leavecall', 'X'), ms = ms } })
    -- dispatch over the radio: "Incoming 911 call." (lwk_control_assets voice/incoming_call_*.ogg), the details as text
    local said = pcall(function()
        exports.lwk_control:say({ 'incoming_call' }, ('Incoming 911 call: %s, %s. Priority %d.'):format(r.name:lower(), r.street, r.priority))
    end)
    if not said then Notify(('~b~DISPATCH~s~ Incoming 911 call: %s, %s.'):format(r.name:lower(), r.street)) end
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
    set_marks(card)
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
    clear_marks()
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

-- /c3rpos [name]: where you are, as a callout point, copied to the clipboard (and printed in F8) to paste into a
-- callout's locations. Sat in a car: the car's position and heading (for a c:vehicle point).
RegisterCommand('c3rpos', function(_, args)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local e = veh ~= 0 and veh or ped
    local p, h = GetEntityCoords(e), GetEntityHeading(e)
    local text = ('%svector4(%.2f, %.2f, %.2f, %.1f),'):format(args[1] and (args[1] .. ' = ') or '', p.x, p.y, p.z, h)
    print(text)
    SendNUIMessage({ type = 'copy', text = text })
    Notify('~b~C~w~3~r~R~s~ Copied: ' .. text)
end, false)

RegisterCommand('+c3r_objective', function()
    -- (Backspace also closes the who-to-talk-to and driver pickers: those turn it off while they're open)
    if not call or CalloutPlacing() or IsNuiFocused() or not IsControlEnabled(0, 177) then return end
    hidden = not hidden
    SendNUIMessage({ type = 'callout', hidden = hidden })
end, false)
RegisterCommand('-c3r_objective', function() end, false)
RegisterKeyMapping('+c3r_objective', 'Callout: hide / show the objective (c3r)', 'keyboard', Config.ObjectiveKey or 'BACK')

RegisterCommand('+c3r_leavecall', function()
    -- (X is also the taser's arc and the Stop Stick's let-go: not while either is in hand)
    if confirming or CalloutPlacing() or IsNuiFocused() or LocalPlayer.state.taser or LocalPlayer.state.stopstick then return end
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
    clear_marks()
end)

-- ─── the call's people, on whichever game owns them (any player's: the server sends it to that one) ───────

local function with_dict(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

-- What they're doing when nobody's dealing with them: a scenario ('WORLD_HUMAN_...'), an anim { dict, name, flag },
-- or just standing there.
local function scene(ped, sc)
    ClearPedTasks(ped)
    if type(sc) == 'string' then
        TaskStartScenarioInPlace(ped, sc, 0, true) -- UNVERIFIED per scenario: the callout names it
    elseif type(sc) == 'table' and sc[1] and with_dict(sc[1]) then
        TaskPlayAnim(ped, sc[1], sc[2], 4.0, -4.0, -1, sc[3] or 1, 0.0, false, false, false)
    else
        TaskStandStill(ped, -1)
    end
end

local function nearest_player_ped(from)
    local best, best_d = PlayerPedId(), math.huge
    for _, pl in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pl)
        local d = #(GetEntityCoords(p) - from)
        if d < best_d then best, best_d = p, d end
    end
    return best
end

local function run(ped, name, args, sc)
    if name == 'go' and args then -- (walking there round buildings and cars, not through them)
        TaskFollowNavMeshToCoord(ped, args.x, args.y, args.z, 1.0, -1, 1.5, 0, type(args) == 'vector4' and args.w or 0.0)
    elseif name == 'flee' then
        RunFrom(ped, nearest_player_ped(GetEntityCoords(ped))) -- (client/stop.lua)
    elseif name == 'surrender' then
        TaskHandsUp(ped, -1, nearest_player_ped(GetEntityCoords(ped)), -1, false)
    elseif name == 'wander' then
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedKeepTask(ped, false)
        TaskWanderStandard(ped, 10.0, 10)
    else
        scene(ped, sc)
    end
end

local function their_ped(net)
    local deadline = GetGameTimer() + 2000
    while not NetworkDoesNetworkIdExist(net) and GetGameTimer() < deadline do Wait(50) end
    local ped = NetworkDoesNetworkIdExist(net) and NetToEnt(net) or 0
    return DoesEntityExist(ped) and ped or nil
end

-- Evidence: lying on the ground (a /c3rpos point is at hip height), and staying there.
local function lay(obj, a)
    SetEntityAsMissionEntity(obj, true, true)
    if a.place then PlaceObjectOnGroundProperly(obj) end
    FreezeEntityPosition(obj, true)
end

-- A parked car in the story: its paint, its plate, locked, engine off, wheels on the ground; damage = 'front': the
-- front end caved in (the first game to own it only: dents add up).
local function park(veh, a)
    SetEntityAsMissionEntity(veh, true, true)
    if a.place then SetVehicleOnGroundProperly(veh) end
    if a.paint then SetVehicleColours(veh, a.paint, a.paint) end
    if a.plate then SetVehicleNumberPlateText(veh, a.plate) end
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleDoorsLocked(veh, a.locked and 2 or 1)
    if a.damage == 'front' then
        local _, max = GetModelDimensions(GetEntityModel(veh)) -- (the front bumper is at max.y)
        SetVehicleDamage(veh, 0.0, max.y, 0.1, 400.0, 1.2, true)
        SetVehicleDamage(veh, max.x * 0.6, max.y, 0.2, 300.0, 0.8, true) -- (one corner worse: the headlight)
        SetVehicleBodyHealth(veh, 550.0)
        SetVehicleEngineHealth(veh, 700.0) -- (dented, not on fire)
    end
end

-- a = { net, scene, task, place (the first time: facing the point's heading), heading, down } (a person), or
-- { net, vehicle = true, paint, plate, locked, place, damage } (a car)
RegisterNetEvent('c3r:callout:apply', function(a)
    CreateThread(function()
        local ped = their_ped(a.net)
        if not ped then return end
        if a.vehicle then return park(ped, a) end
        if a.prop then return lay(ped, a) end
        if IsPedInAnyVehicle(ped, false) then return end -- (in an ambulance by now)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true) -- (they do the story, not whatever the street is doing)
        SetPedKeepTask(ped, true)
        if a.place and a.heading then SetEntityHeading(ped, a.heading) end -- (stood exactly where the callout says)
        -- hurt, on the ground (client/medical.lua holds them there), unless paramedics have just seen to them
        if a.down and IsCasualty(ped) then
            if GetEntityHealth(ped) >= GetEntityMaxHealth(ped) then SetEntityHealth(ped, 140) end -- (hurt)
            return HoldDown(ped)
        end
        if a.task then run(ped, a.task.name, a.task.args, a.scene) else scene(ped, a.scene) end
    end)
end)

RegisterNetEvent('c3r:callout:task', function(net, name, args, sc)
    CreateThread(function()
        local ped = their_ped(net)
        if ped then run(ped, name, args, sc) end
    end)
end)

-- ─── evidence ─────────────────────────────────────────────────────────────────

local clues, clue_call = {}, nil -- what can be inspected on my call: { { key, label, at | on (a net), range, glow } }
local looked = {} -- [clue key] = true: inspected by me (it stops glowing)

RegisterNetEvent('c3r:callout:clues', function(id, list) clue_call, clues = id, type(list) == 'table' and list or {} end)
AddEventHandler('c3r:callout:ended', function() clues, clue_call, looked = {}, nil, {} end)

-- Where it is: the person or car it's on, its prop (which may have rolled a little as it landed), or its point.
local function clue_pos(cl)
    local net = cl.on or cl.glow
    if net then
        local ent = NetworkDoesNetworkIdExist(net) and NetToEnt(net) or 0
        if DoesEntityExist(ent) then return GetEntityCoords(ent) end
        if cl.on then return nil end
    end
    return cl.at and vector3(cl.at.x, cl.at.y, cl.at.z)
end

local function nearest_clue()
    local me = PlayerPedId()
    if not call or IsPedInAnyVehicle(me, false) then return nil end
    local here, best, best_d = GetEntityCoords(me), nil, math.huge
    for _, cl in ipairs(clues) do
        local at = clue_pos(cl)
        local d = at and #(at - here)
        if d and d < (cl.range or 1.6) and d < best_d then best, best_d = cl, d end
    end
    return best, best and clue_pos(best)
end

-- E (client/menu.lua asks first): evidence beside you is looked at before anyone's talked to.
function CalloutInspect()
    local cl = nearest_clue()
    if not cl then return false end
    TriggerServerEvent('c3r:callout:inspect', clue_call, cl.key)
    return true
end

RegisterNetEvent('c3r:callout:found', function(label, text, key)
    Prompt('evidence', 'info', tostring(label), tostring(text), 9000)
    if key then looked[key] = true end
end)

-- Evidence I haven't looked at yet is outlined in white (the prop, or the car it's on) once I'm within GLOW_RANGE of
-- it, so it's easy to spot. The thin solid outline: the soft one is a full-screen blur, every frame. Outlines are drawn
-- by each game for itself.
local GLOW_RANGE = 30.0
CreateThread(function()
    local lit = {} -- [entity] = true
    while true do
        local want = {}
        local me = GetEntityCoords(PlayerPedId())
        for _, cl in ipairs(call and clues or {}) do
            if cl.glow and not looked[cl.key] and NetworkDoesNetworkIdExist(cl.glow) then
                local ent = NetToEnt(cl.glow)
                if DoesEntityExist(ent) and #(GetEntityCoords(ent) - me) < GLOW_RANGE then want[ent] = true end
            end
        end
        for ent in pairs(lit) do
            if not want[ent] then
                if DoesEntityExist(ent) then SetEntityDrawOutline(ent, false) end
                lit[ent] = nil
            end
        end
        for ent in pairs(want) do
            if not lit[ent] then
                SetEntityDrawOutlineColor(255, 255, 255, 255)
                SetEntityDrawOutlineShader(1)
                SetEntityDrawOutline(ent, true)
                lit[ent] = true
            end
        end
        Wait(500)
    end
end)

-- Up close: a small marker on it, and the game's help text with the key.
CreateThread(function()
    while true do
        local cl, at = nil, nil
        if call and clues[1] then cl, at = nearest_clue() end
        if cl then
            if not cl.on or (cl.range or 0) > 2 then -- (on the spot, or above the car; not on a person's head)
                DrawMarker(20, at.x, at.y, at.z + (cl.on and 1.3 or 0.6), 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.25, 0.25, 0.2, 240, 176, 64, 200,
                    true, true, 2, false, nil, nil, false)
            end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ Inspect: ' .. cl.label)
            EndTextCommandDisplayHelp(0, false, false, -1)
            Wait(0)
        else
            Wait(call and clues[1] and 250 or 1000)
        end
    end
end)

TriggerServerEvent('c3r:callout:sync') -- (the calls open now)

-- ─── /c3rplace (server/callouts.lua): walk out a new location for a callout, point by point ──────────────────────

local placing = nil -- { id, name, points = { { name, what, kind } }, index, i, got = { [name] = { x, y, z, h } }, ghosts }
function CalloutPlacing() return placing ~= nil end -- (client/menu.lua: E sets a point, it doesn't talk to anyone)

-- A see-through stand-in where a point was set, so the whole layout shows as it's built (only in this game).
local function ghost(kind, p)
    local model = GetHashKey(kind == 'car' and 'asea' or 'a_m_y_hipster_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return nil end
    local e = kind == 'car' and CreateVehicle(model, p.x, p.y, p.z, p.h, false, false)
        or CreatePed(4, model, p.x, p.y, p.z - 1.0, p.h, false, false) -- (a ped's position is its hips: its feet are lower)
    SetModelAsNoLongerNeeded(model)
    if kind == 'car' then SetVehicleOnGroundProperly(e) else SetBlockingOfNonTemporaryEvents(e, true) end
    SetEntityAlpha(e, 140, false)
    SetEntityCollision(e, false, false)
    SetEntityInvincible(e, true)
    FreezeEntityPosition(e, true)
    return e
end

local function clear_ghosts()
    for _, e in pairs(placing and placing.ghosts or {}) do if DoesEntityExist(e) then DeleteEntity(e) end end
end

local function stop_placing(msg)
    clear_ghosts()
    placing = nil
    ClearPrompt('place')
    if msg then Prompt('place', 'info', 'Placing', msg, 5000) end
end

local function show_point()
    local pt = placing.points[placing.i]
    Prompt('place', 'info', ('%s %d/%d: %s'):format(placing.name, placing.i, #placing.points, pt[1]),
        pt[2] .. (pt[3] == 'car' and ' Sit in the car, then E.' or ' Stand there, facing their way, then E.')
        .. ' Backspace: back. X: cancel.')
end

local function where(at)
    local s1 = GetStreetNameAtCoord(at.x, at.y, at.z)
    local street = s1 and s1 ~= 0 and GetStreetNameFromHashKey(s1) or ''
    if street == '' then street = GetLabelText(GetNameOfZone(at.x, at.y, at.z)) end
    return street
end

local function finish_placing()
    local first = placing.got[placing.points[1][1]] -- (the scene: where the first point is, the caller's)
    Prompt('place', 'info', 'Placing', 'Saving...', 4000)
    local streets = {} -- (each point's: a home round the corner is on another street)
    for name, p in pairs(placing.got) do streets[name] = where(vector3(p.x, p.y, p.z)) end
    TriggerServerEvent('c3r:place:save', placing.id, placing.index,
        { street = where(vector3(first.x, first.y, first.z)), streets = streets, points = placing.got })
end

RegisterNetEvent('c3r:place:start', function(d)
    if placing then stop_placing() end
    placing = { id = d.id, name = d.name, points = d.points, index = d.index, i = 1, got = {}, ghosts = {} }
    show_point()
    CreateThread(function()
        while placing and placing.i <= #placing.points do
            for _, c in ipairs({ 38, 73, 177 }) do DisableControlAction(0, c, true) end -- (E, X, Backspace are the placer's)
            local me = PlayerPedId()
            if IsDisabledControlJustPressed(0, 38) then
                local pt = placing.points[placing.i]
                local veh = GetVehiclePedIsIn(me, false)
                if pt[3] == 'car' and veh == 0 then
                    Prompt('place_warn', 'info', 'A car point', 'Sit in a car parked where it should be, then E.', 4000)
                elseif pt[3] ~= 'car' and veh ~= 0 then
                    Prompt('place_warn', 'info', 'On foot', 'Get out and stand where they should stand, then E.', 4000)
                else
                    local e = pt[3] == 'car' and veh or me
                    local c, h = GetEntityCoords(e), GetEntityHeading(e)
                    local p = { x = c.x, y = c.y, z = c.z, h = h }
                    placing.got[pt[1]] = p
                    CreateThread(function() local g = ghost(pt[3], p) if g and placing then placing.ghosts[pt[1]] = g elseif g then DeleteEntity(g) end end)
                    placing.i = placing.i + 1
                    if placing.i > #placing.points then finish_placing() else show_point() end
                end
            elseif IsDisabledControlJustPressed(0, 177) and placing.i > 1 then
                placing.i = placing.i - 1
                local name = placing.points[placing.i][1]
                placing.got[name] = nil
                if placing.ghosts[name] and DoesEntityExist(placing.ghosts[name]) then DeleteEntity(placing.ghosts[name]) end
                placing.ghosts[name] = nil
                show_point()
            elseif IsDisabledControlJustPressed(0, 73) then
                return stop_placing('Cancelled: nothing saved.')
            end
            Wait(0)
        end
    end)
end)

RegisterNetEvent('c3r:place:saved', function(msg, entry)
    stop_placing()
    Prompt('place', 'ok', 'Location saved', msg, 7000)
    SendNUIMessage({ type = 'copy', text = entry }) -- (and on the clipboard, in case)
end)

RegisterNetEvent('c3r:place:msg', function(msg)
    if placing and placing.i > #placing.points then stop_placing() end -- (the save was refused)
    Prompt('place', 'info', 'Placing', tostring(msg), 8000)
end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and placing then stop_placing() end end)

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
