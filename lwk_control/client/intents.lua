--[[
    lwk_control — built-in intents. Each intent:
      id      unique string
      say     phrases (every word must be in the model vocabulary)
      verb    'request' | 'cancel' | nil   (nil = verb ignored)
      slot    'plate' | 'code' | nil
      confirm true to ask "affirmative / negative" before running (or a function: ask when it returns true)
      label   text used in the confirm prompt
      run     function(ctx)  ctx = { verb, text, plate?, code? }
    Other resources add intents with exports.lwk_control:addIntent(def).
]]

Intents = {}
-- status = last status code said (10-8 / 10-6 / 10-97), calls_held = callout offers paused by voice
-- stop / pursuit = c3r traffic stop or pursuit in progress (relayed by the server)
State = { offer_until = 0, plate_cooldown_until = 0, status = nil, calls_held = false, stop = false, pursuit = false }

-- ─── c3r calls ─────────────────────────────────────────────────────────────

-- Calls a c3r client export; returns nil, 'reason' instead of erroring when c3r (or that export,
-- which a later phase adds) is missing. See c3r/docs/contract.md.
function Pd(fn, ...)
    if GetResourceState('c3r') ~= 'started' then return nil, 'c3r is not running' end
    local res = exports.c3r
    local ok, a, b = pcall(function(...) return res[fn](res, ...) end, ...)
    if not ok then return nil, 'not available' end
    return a, b
end

local function reason_text(r)
    return r and tostring(r):gsub('_', ' ') or 'unable'
end

-- Commands that fit what the player is doing right now; the sound-alike matcher leans toward them.
function LikelyIntents()
    local set = {}
    local function add(list) for _, id in ipairs(list) do set[id] = true end end
    if State.stop then
        add({ 'plate_check', 'name_check', 'request_tow', 'request_police', 'request_ambulance',
              'hold_traffic', 'release_traffic', 'pursuit_backup', 'request_cover', 'complete_callout' })
    end
    if State.pursuit then add({ 'cancel_pursuit', 'pursuit_backup', 'air_support', 'cancel_backup', 'panic', 'plate_check' }) end
    if GetGameTimer() < State.offer_until or Pd('isOfferedCallout') then add({ 'accept_callout' }) end
    if Pd('isOnCallout') then
        add({ 'complete_callout', 'where_call', 'status_10-97', 'request_ambulance', 'request_coroner',
              'request_fire', 'request_tow', 'request_police', 'hold_traffic', 'release_traffic' })
    end
    return set
end

-- ─── registry ─────────────────────────────────────────────────────────────────

function AddIntent(def)
    assert(type(def) == 'table' and type(def.id) == 'string', 'intent needs an id')
    assert(type(def.say) == 'table' and #def.say > 0, 'intent ' .. def.id .. ' needs say phrases')
    assert(def.run, 'intent ' .. def.id .. ' needs run')
    for i, it in ipairs(Intents) do
        if it.id == def.id then Intents[i] = def return end
    end
    Intents[#Intents + 1] = def
end

-- ─── services: request_<type> / cancel_<type> via RequestNPCBackup ────────────

local SERVICES = {
    { type = 'ambulance',    label = 'ambulance',      say = { 'ambulance', 'ems', 'medic', 'bus', 'paramedics' } },
    { type = 'police',       label = 'transport unit', say = { 'prisoner transport', 'transport', 'transport unit' } },
    { type = 'tow',          label = 'tow truck',      say = { 'tow truck', 'tow', 'wrecker' } },
    { type = 'coroner',      label = 'coroner',        say = { 'coroner', 'medical examiner' } },
    { type = 'fire',         label = 'fire department', say = { 'fire department', 'fire truck', 'fire engine', 'fire' } },
    { type = 'mechanic',     label = 'mechanic',       say = { 'mechanic' } },
    { type = 'roadservice',  label = 'road service',   say = { 'road service', 'roadside assistance' } },
    { type = 'animalrescue', label = 'animal control', say = { 'animal control', 'animal rescue' } },
    { type = 'taxi',         label = 'taxi',           say = { 'taxi', 'cab' } },
    { type = 'dot',          label = 'DOT crew',       say = { 'dot', 'd o t', 'dot crew', 'd o t crew', 'dot unit', 'department of transportation',
                                                               'road crew', 'cleanup crew', 'clean up crew' } },
}

-- Closest vehicle within max_dist m that isn't the one you're in or an emergency vehicle (class 18).
local function nearest_vehicle(max_dist)
    local ped = PlayerPedId()
    local own, pos = GetVehiclePedIsIn(ped, false), GetEntityCoords(ped)
    local best, best_d = nil, max_dist
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if veh ~= own and GetVehicleClass(veh) ~= 18 then
            local d = #(GetEntityCoords(veh) - pos)
            if d < best_d then best, best_d = veh, d end
        end
    end
    return best
end

-- Street, cross street and area at the player, as the game names them.
function LocationAt(p)
    local s1, s2 = GetStreetNameAtCoord(p.x, p.y, p.z)
    local zone = GetNameOfZone(p.x, p.y, p.z)
    return {
        street = GetStreetNameFromHashKey(s1),
        cross = s2 ~= 0 and GetStreetNameFromHashKey(s2) or nil,
        zone = zone, zone_name = GetLabelText(zone),
    }
end

local function current_location() return LocationAt(GetEntityCoords(PlayerPedId())) end

-- "<lead_to clip> <location>", e.g. "Copy, rolling an ambulance to | Strawberry Avenue | and | Davis Avenue".
-- Falls back to the plain line when the location has no clips.
local function en_route_reply(lead_to, plain, text)
    local where_items, where = Brain.location_words(current_location(), PlaceClipExists)
    if not where_items then return Reply(plain, text .. '.') end
    local clips = { lead_to }
    for _, it in ipairs(where_items) do clips[#clips + 1] = it end
    Reply(nil, text .. ' to ' .. where .. '.')
    Speak(clips, nil, true)
end

-- "Copy, tow truck en route for the Bravado Buffalo on Strawberry Avenue." The vehicle part needs a
-- vehicle within 15 m with make / model clips (an English game language); otherwise it's the
-- location-only reply.
local function tow_reply()
    local veh = Pd('towTarget') or nearest_vehicle(15.0) -- (the car the truck is actually coming for)
    local words, name
    if veh then
        local hash = GetEntityModel(veh)
        local make = GetLabelText(GetMakeNameFromVehicleModel(hash))
        local model = GetLabelText(GetDisplayNameFromVehicleModel(hash))
        make, model = make ~= 'NULL' and make or nil, model ~= 'NULL' and model or nil
        words = Brain.vehicle_words({ make = make, model = model }, VehicleClipExists)
        name = ((make or '') .. ' ' .. (model or '')):match('^%s*(.-)%s*$')
    end
    if not words then return en_route_reply('en_route_tow_to', 'en_route_tow', 'Copy, tow truck en route') end

    local clips = { 'en_route_tow_for' }
    for _, k in ipairs(words) do clips[#clips + 1] = ('nui/voice/vehicle/%s.ogg'):format(k) end
    local where_items, where = Brain.location_words(current_location(), PlaceClipExists)
    if where_items then
        clips[#clips + 1] = 'loc_on'
        for _, it in ipairs(where_items) do clips[#clips + 1] = it end
    end
    Reply(nil, 'Copy, tow truck en route for the ' .. name .. (where and (' on ' .. where) or '') .. '.')
    Speak(clips, nil, true)
end

for _, s in ipairs(SERVICES) do
    AddIntent({
        id = 'request_' .. s.type, say = s.say, verb = 'request',
        run = function()
            local dispatched, reason = Pd('requestService', s.type)
            if not dispatched then return Reply('unable', '~r~Unable to send ' .. s.label .. ': ' .. reason_text(reason)) end
            if s.type == 'tow' then return tow_reply() end
            en_route_reply('en_route_' .. s.type .. '_to', 'en_route_' .. s.type, 'Copy, ' .. s.label .. ' en route')
        end,
    })
    AddIntent({
        id = 'cancel_' .. s.type, say = s.say, verb = 'cancel',
        run = function()
            local ok, reason = Pd('cancelService', s.type)
            if not ok then Reply('unable', '~r~Unable: ' .. reason_text(reason)) else Reply('cancelled') end
        end,
    })
end

-- A cover unit: one patrol car to stand by at the scene (c3r's kind 'cover', beyond the contract's services).
AddIntent({
    id = 'request_cover', verb = 'request',
    say = { 'cover unit', 'cover car', 'cover', 'another unit', 'second unit' },
    run = function()
        local dispatched, reason = Pd('requestService', 'cover')
        if not dispatched then return Reply('unable', '~r~Unable to send a cover unit: ' .. reason_text(reason)) end
        en_route_reply('units_en_route_to', 'units_en_route', 'Copy, cover unit en route')
    end,
})
AddIntent({
    id = 'cancel_cover', verb = 'cancel',
    say = { 'cover unit', 'cover car', 'cover' },
    run = function()
        local ok, reason = Pd('cancelService', 'cover')
        if not ok then Reply('unable', '~r~Unable: ' .. reason_text(reason)) else Reply('cancelled') end
    end,
})

-- ─── shift ────────────────────────────────────────────────────────────────────

AddIntent({
    id = 'on_duty',
    say = { 'in service', 'show me in service', 'ten forty one', 'on duty', 'going on duty', 'starting my shift' },
    run = function()
        if Pd('isOnDuty') then return Reply('already_in_service', 'You are already in service.') end
        local ok, reason = Pd('setDuty', true)
        if not ok then return Reply('unable', '~r~Unable: ' .. reason_text(reason)) end
        State.status = nil
        Reply('in_service', 'Copy, show you in service.')
    end,
})

AddIntent({
    id = 'off_duty', confirm = true, label = 'go out of service',
    say = { 'out of service', 'show me out of service', 'ten forty two', 'off duty', 'going off duty', 'ending my shift' },
    run = function()
        if not Pd('isOnDuty') then return Reply('not_in_service', 'You are not in service.') end
        Pd('setDuty', false)
        State.status, State.stop, State.pursuit = nil, false, false
        Reply('out_of_service', 'Copy, show you out of service.')
    end,
})

-- ─── callouts ─────────────────────────────────────────────────────────────────

AddIntent({
    id = 'accept_callout',
    say = { 'accept call out', 'accepting call out', 'accept the call', 'attach me', 'attach me to that call',
            'put me on that call', 'i will take that call', 'i will take it', 'en route', 'responding' },
    run = function()
        if not (Pd('isOfferedCallout') or GetGameTimer() < State.offer_until) then
            return Reply('no_callout', '~r~No callout currently offered.')
        end
        local ok, reason = Pd('acceptCallout')
        if not ok then return Reply('unable', '~r~Unable: ' .. reason_text(reason)) end
        Reply('accept_callout')
    end,
})

AddIntent({
    id = 'complete_callout', confirm = true, label = 'complete the callout',
    say = { 'code four', 'scene is code four', 'scene is clear', 'scene clear', 'call out complete',
            'marking scene clear', 'clear the call' },
    run = function()
        if not Pd('isOnCallout') then return Reply('not_attached', '~r~You are not attached to a callout.') end
        State.status = nil
        ClearCall()
    end,
})

-- Off the call (code four, or 10-8 while on one): the last unit off calls it off, so dispatch says it's cancelling.
function ClearCall()
    local ok, how = Pd('completeCallout')
    if not ok then return Reply('unable', '~r~Unable: ' .. reason_text(how)) end
    if how == 'cancelled' then return Reply('cancelled', 'Copy, cancelling the call.') end
    Reply('code4')
end

AddIntent({
    -- Only phrases that clearly ask for a call: a bare "call outs" is too easy to hit by accident
    -- ("[hold] my call outs" with "hold" misheard would otherwise request one).
    id = 'request_callout',
    say = { 'any calls', 'any call outs', 'a new call', 'give me a call', 'calls holding', 'any calls holding',
            'requesting a call out', 'request a call out', 'can i get a call out', 'give me a call out' },
    run = function() TriggerServerEvent('lwk_control:requestCallout') end,
})

-- Special taskings (c3r's planned jobs: a protection detail, event security, a business check): asked for, never offered.
-- Any one, or a kind by name. c3r hands it over and dispatch says what and where (its own line).
for _, t in ipairs({
    { id = 'request_tasking', say = { 'special tasking', 'a special tasking', 'special assignment', 'a special assignment', 'tasking' } },
    { id = 'request_tasking_protection', kind = 'protection', say = { 'protection detail', 'a protection detail', 'protective detail' } },
    { id = 'request_tasking_event', kind = 'event', say = { 'event security', 'event detail', 'an event detail', 'security detail' } },
    { id = 'request_tasking_business', kind = 'business', say = { 'business check', 'business checks', 'a business check', 'business inspection' } },
}) do
    AddIntent({
        id = t.id, verb = 'request', say = t.say,
        run = function() TriggerServerEvent('lwk_control:requestTasking', t.kind) end,
    })
end

AddIntent({
    id = 'hold_callouts',
    say = { 'hold my call outs', 'hold call outs', 'pause my call outs', 'pause call outs', 'no more call outs', 'stop call outs' },
    run = function()
        State.calls_held = true
        TriggerServerEvent('lwk_control:setOffers', false)
    end,
})

AddIntent({
    id = 'resume_callouts',
    say = { 'resume call outs', 'resume my call outs', 'available for call outs', 'send me call outs' },
    run = function()
        State.calls_held = false
        TriggerServerEvent('lwk_control:setOffers', true)
    end,
})

-- The same, typed: dispatch answers as it does on the radio.
RegisterCommand('togglecalls', function()
    if not LocalPlayer.state.c3rDuty then return end
    State.calls_held = not State.calls_held
    TriggerServerEvent('lwk_control:setOffers', not State.calls_held)
end, false)

-- ─── checks ───────────────────────────────────────────────────────────────────

function RunPlateCheck(plate)
    local now = GetGameTimer()
    if now < State.plate_cooldown_until then return end
    State.plate_cooldown_until = now + Config.PlateCooldownMs
    TriggerServerEvent('lwk_control:plateCheck', plate)
end

AddIntent({
    id = 'plate_check', slot = 'plate',
    say = { 'plate', 'plate check', 'run plate', 'run the plate', 'run that plate', 'run a plate',
            'check the plate', 'ten twenty eight' },
    run = function(ctx) RunPlateCheck(ctx.plate) end,
})

AddIntent({
    id = 'name_check',
    say = { 'name check', 'run a name', 'run the name', 'run that name', 'check the name',
            'ten twenty nine', 'warrant check' },
    run = function()
        Speak({ 'name_intro' }, nil, true) -- intro plays while the server looks the subject up
        TriggerServerEvent('lwk_control:nameCheck')
    end,
})

-- ─── pursuit ──────────────────────────────────────────────────────────────────

local PURSUIT_BY_CODE = { 'light', 'medium', 'heavy' }

local function pursuit_backup(unit)
    local dispatched, reason = Pd('requestPursuitBackup', unit)
    if not dispatched then return Reply('unable', '~r~Unable: ' .. reason_text(reason)) end
    if reason == 'cover' then -- no chase on: c3r sent a cover unit instead
        return en_route_reply('units_en_route_to', 'units_en_route', 'Copy, cover unit en route')
    end
    local key = unit == 'air' and 'air_en_route' or 'units_en_route'
    en_route_reply(key .. '_to', key, 'Copy, ' .. unit .. ' units en route')
end

AddIntent({
    id = 'pursuit_backup', verb = 'request', slot = 'code',
    say = { 'backup', 'back up', 'additional units', 'more units' },
    -- (in a chase, the helicopter is the only backup: the AI pursuit cars weren't up to it; no chase, c3r sends cover)
    run = function(ctx) pursuit_backup(State.pursuit and 'air' or PURSUIT_BY_CODE[ctx.code or 2] or 'medium') end,
})

AddIntent({
    id = 'air_support', verb = 'request',
    say = { 'air support', 'air unit', 'air one', 'helicopter', 'chopper' },
    run = function() pursuit_backup('air') end,
})

AddIntent({
    id = 'cancel_backup', verb = 'cancel',
    say = { 'backup', 'back up', 'additional units', 'air support', 'air unit', 'helicopter', 'chopper' },
    run = function()
        local ok, reason = Pd('cancelPursuitBackup')
        if not ok then return Reply('unable', '~r~Unable: ' .. reason_text(reason)) end
        Reply('cancelled')
    end,
})

AddIntent({ -- "cancel the pursuit", "call off the chase": not chasing them any more (the same as /cancelpursuit)
    id = 'cancel_pursuit', verb = 'cancel', confirm = true, label = 'call off the pursuit',
    say = { 'the pursuit', 'the chase' },
    run = function()
        local ok, reason = Pd('cancelPursuit')
        if not ok then return Reply('unable', '~r~Unable: ' .. reason_text(reason)) end
        Reply('cancelled')
    end,
})

-- ─── panic + status ───────────────────────────────────────────────────────────

AddIntent({
    id = 'panic',
    say = { 'ten ninety nine', 'officer down', 'officer needs assistance', 'officer needs help', 'panic button' },
    run = function()
        Reply('panic', '~r~10-99 — OFFICER NEEDS ASSISTANCE')
        Config.OnPanic()
    end,
})

local STATUS = {
    { code = '10-8',  say = { 'ten eight', 'back in service', 'available' } },
    { code = '10-6',  say = { 'ten six', 'busy' } },
    { code = '10-97', say = { 'ten ninety seven', 'on scene', 'arrived on scene', 'arriving on scene' } },
}

for _, s in ipairs(STATUS) do
    AddIntent({
        id = 'status_' .. s.code, say = s.say,
        -- 10-8 on a call clears it: asked first, as "code four" is ("available" is easy to mishear)
        confirm = s.code == '10-8' and function() return Pd('isOnCallout') == true end or nil,
        label = s.code == '10-8' and 'show ten eight and clear the call' or nil,
        run = function()
            State.status = s.code
            TriggerEvent('lwk_control:status', s.code)
            if s.code == '10-8' and Pd('isOnCallout') then return ClearCall() end -- (back in service: off the call)
            Reply('status_' .. s.code:gsub('%-', '_'), 'Copy, ' .. s.code .. '.')
        end,
    })
end

-- "What's my status?" - duty from c3r, then the most specific of: in pursuit, on a traffic stop,
-- on a callout, last status code said, calls on hold, available.
AddIntent({
    id = 'status_check',
    say = { "what's my status", 'what is my status', 'status check', 'how am i showing', 'what am i showing',
            'am i in service', 'show me my status', 'my status', 'status' },
    run = function()
        if not Pd('isOnDuty') then return Reply('status_out', 'You are showing out of service.') end
        local key, text
        if State.pursuit then key, text = 'status_detail_pursuit', 'in pursuit'
        elseif State.stop then key, text = 'status_detail_stop', 'on a traffic stop'
        elseif Pd('isOnCallout') then key, text = 'status_detail_call', 'attached to an active call'
        elseif State.status == '10-97' then key, text = 'status_detail_onscene', 'showing on scene'
        elseif State.status == '10-6' then key, text = 'status_detail_busy', 'showing 10-6, busy'
        elseif State.calls_held then key, text = 'status_detail_held', 'calls on hold'
        else key, text = 'status_detail_available', 'available for calls' end
        Reply(nil, 'In service, ' .. text .. '.')
        Speak({ 'status_in', key }, nil, true)
    end,
})

-- ─── traffic holds ────────────────────────────────────────────────────────────

AddIntent({
    id = 'hold_traffic', verb = 'request',
    say = { 'hold traffic', 'traffic hold', 'stop traffic', 'block traffic', 'shut down traffic', 'close the road' },
    run = function() TriggerServerEvent('lwk_control:holdTraffic', GetEntityCoords(PlayerPedId())) end,
})

local function release_traffic() TriggerServerEvent('lwk_control:releaseTraffic') end

AddIntent({
    id = 'release_traffic',
    say = { 'release traffic', 'resume traffic', 'open traffic', 'open the road', 'reopen the road',
            'let traffic go', 'let traffic through', 'traffic can resume', 'release the hold', 'clear the hold',
            'road is open' },
    run = release_traffic,
})

AddIntent({ -- "cancel the traffic hold"
    id = 'cancel_traffic_hold', verb = 'cancel',
    say = { 'traffic hold', 'hold traffic', 'the hold' },
    run = release_traffic,
})

-- ─── directions ───────────────────────────────────────────────────────────────

-- GPS waypoint to the closest Config.Places[kind] entry: "Copy, routing you to Pillbox Hill Medical Center."
local function route_to_nearest(kind, label)
    local places = Config.Places and Config.Places[kind] or {}
    local pos, best, best_d = GetEntityCoords(PlayerPedId()), nil, math.huge
    for _, p in ipairs(places) do
        local d = #(p.coords - pos)
        if d < best_d then best, best_d = p, d end
    end
    if not best then return Reply('unable', '~r~No ' .. label .. ' on file.') end
    SetNewWaypoint(best.coords.x, best.coords.y)
    if best.clip and PlaceClipExists('poi_' .. best.clip) then
        Reply(nil, 'Copy, routing you to ' .. best.name .. '.')
        Speak({ 'route_to', ('nui/voice/places/poi_%s.ogg'):format(best.clip) }, nil, true)
    else
        Reply('route_' .. kind, 'Copy, route set to the nearest ' .. label .. ' (' .. best.name .. ').')
    end
end

local DIRECTIONS = {
    { kind = 'hospital', label = 'hospital',
      say = { 'nearest hospital', 'closest hospital', 'route to the hospital', 'directions to the hospital',
              'take me to the hospital', 'hospital' } },
    { kind = 'police', label = 'police station',
      say = { 'nearest police station', 'closest police station', 'police station', 'nearest station',
              'route to the station', 'directions to the station', 'take me to the station' } },
    { kind = 'fire', label = 'fire station',
      say = { 'nearest fire station', 'closest fire station', 'fire station', 'firehouse' } },
    { kind = 'impound', label = 'impound lot',
      say = { 'nearest impound', 'impound lot', 'impound', 'route to the impound' } },
}

for _, d in ipairs(DIRECTIONS) do
    AddIntent({ id = 'route_' .. d.kind, say = d.say, run = function() route_to_nearest(d.kind, d.label) end })
end

-- ─── small talk ───────────────────────────────────────────────────────────────
-- Voice only, a random variant each time. chat = true: dropped when said alongside a real command
-- ("tow truck, thanks"), so it never ends up in a confirm prompt.

local CHAT = {
    { id = 'thanks',   say = { 'thanks dispatch', 'thank you', 'thanks', 'appreciate it', 'much appreciated' } },
    { id = 'morning',  say = { 'good morning' } },
    { id = 'evening',  say = { 'good evening', 'good afternoon' } },
    { id = 'hello',    say = { 'hello dispatch', 'hey dispatch', 'hello' } },
    { id = 'radio',    say = { 'radio check', 'how do you copy', 'do you copy' } },
    { id = 'howareyou', say = { 'how are you', 'how is your night', 'how is it going', 'how are things' } },
    { id = 'love',     say = { 'i love you' } },
    { id = 'joke',     say = { 'tell me a joke' } },
    { id = 'quiet',    say = { "it's quiet", 'it is quiet', 'quiet night', 'pretty quiet' } },
    { id = 'coffee',   say = { 'coffee', 'donut', 'donuts' } },
    { id = 'bye',      say = { 'goodbye', 'good night', 'have a good night', 'see you later' } },
    { id = 'whoami',   say = { 'who is this', 'who am i talking to', 'what is your name' } },
}

for _, c in ipairs(CHAT) do
    AddIntent({ id = 'chat_' .. c.id, say = c.say, chat = true, run = function() Speak({ 'chat_' .. c.id }, nil, true) end })
end

-- ─── other units ──────────────────────────────────────────────────────────────

AddIntent({
    id = 'nearest_unit',
    say = { 'nearest unit', 'closest unit', 'who is closest', 'who is nearest', 'any units nearby', 'any units close',
            'where is the nearest unit' },
    run = function() TriggerServerEvent('lwk_control:nearestUnit') end,
})

-- "Dispatch, have Two Boy Four meet me": the callsign is matched against the on-duty units.
AddIntent({
    id = 'meet_unit',
    say = { 'meet me', 'to meet me', 'meet me at my location', 'meet at my location', 'meet up with me' },
    run = function(ctx)
        local unit = Brain.find_unit(ctx.text, OtherUnits)
        if not unit then return Reply('meet_unknown_cs', "Say again the unit's callsign.") end
        TriggerServerEvent('lwk_control:meet', unit.id)
    end,
})

-- ─── time / weather ───────────────────────────────────────────────────────────

AddIntent({
    id = 'time_check',
    say = { 'time check', 'what time is it', 'what is the time', 'current time', 'give me a time check' },
    run = function()
        local items, text = Brain.time_words(GetClockHours(), GetClockMinutes())
        table.insert(items, 1, 'time_intro')
        Reply(nil, 'Time is ' .. text .. '.')
        Speak(items, nil, true)
    end,
})

-- Game weather type -> voice line key.
local WEATHER = {
    CLEAR = 'clear', NEUTRAL = 'clear', EXTRASUNNY = 'sunny', CLOUDS = 'clouds', OVERCAST = 'overcast',
    RAIN = 'rain', RAIN_HALLOWEEN = 'rain', CLEARING = 'clearing', THUNDER = 'thunder', SMOG = 'smog',
    FOGGY = 'fog', SNOW = 'snow', XMAS = 'snow', SNOW_HALLOWEEN = 'snow', SNOWLIGHT = 'snowlight',
    BLIZZARD = 'blizzard', HALLOWEEN = 'halloween',
}
local WEATHER_TEXT = {
    clear = 'Clear skies, good visibility', sunny = 'Clear and sunny', clouds = 'Partly cloudy',
    overcast = 'Overcast skies', rain = 'Rain, roads are wet', clearing = 'Rain clearing, roads still wet',
    thunder = 'Thunderstorms in the area, use caution', smog = 'Smog, reduced visibility',
    fog = 'Heavy fog, visibility is low', snow = 'Snow on the roads, use caution', snowlight = 'Light snow',
    blizzard = 'Blizzard conditions, visibility near zero', halloween = 'Dark and stormy',
}

AddIntent({
    id = 'weather_check',
    say = { 'weather check', 'what is the weather', 'how is the weather', 'weather', 'weather conditions',
            'road conditions', 'current conditions' },
    run = function()
        local now = GetPrevWeatherTypeHashName() & 0xFFFFFFFF
        for name, key in pairs(WEATHER) do
            if GetHashKey(name) & 0xFFFFFFFF == now then return Reply('weather_' .. key, WEATHER_TEXT[key] .. '.') end
        end
        Reply('weather_unknown', 'No weather report available.')
    end,
})

-- ─── where's my call / say again ──────────────────────────────────────────────

AddIntent({
    id = 'where_call',
    say = { "where's my call", 'where is my call', 'where is the call', 'repeat the address', 'what is the address',
            'address of the call', 'location of the call', 'where am i going' },
    run = function()
        if not Pd('isOnCallout') then
            return Reply('not_attached', '~r~You are not attached to a callout.')
        end
        local c = State.call_coords
        if not c and IsWaypointActive() then c = GetBlipInfoIdCoord(GetFirstBlipInfoId(8)) end
        if not c then return Reply('call_unknown', "I don't have a location for your call.") end
        SetNewWaypoint(c.x, c.y)
        local me = GetEntityCoords(PlayerPedId())
        local dist_items, dist_text = Brain.distance_words(#(vector2(c.x, c.y) - vector2(me.x, me.y)))
        local where_items, where = Brain.location_words(LocationAt(c), PlaceClipExists)
        local items
        if where_items then
            items = { 'call_at' }
            for _, it in ipairs(where_items) do items[#items + 1] = it end
            items[#items + 1] = 'nui/voice/pause.ogg'
        else
            items = { 'call_is' }
        end
        for _, it in ipairs(dist_items) do items[#items + 1] = it end
        items[#items + 1] = 'dist_out'
        Reply(nil, 'Your call: ' .. (where and (where .. ', ') or '') .. dist_text .. ' out. Route set.')
        Speak(items, nil, true)
    end,
})

AddIntent({
    id = 'repeat_last',
    say = { 'say again', 'say again your last', 'repeat your last', 'repeat that', 'repeat last', 'come again',
            'repeat the return', 'repeat' },
    run = function() RepeatLast() end,
})
