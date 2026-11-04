--[[
    c3r — client: the PA. lwk_control hears the officer on its PA key and calls exports.c3r:pa(commands);
    the G wheel's felony steps use the same orders. Orders are shouted: they reach Config.PaRange, so a felony
    stop is run from cover. One order at a time on a felony stop (said in one breath, only the first counts).
]]

local SEAT_NAMES = { [-1] = 'Driver', [0] = 'Passenger', [1] = 'Rear passenger', [2] = 'Rear passenger' }
function FelonyWho(o) return SEAT_NAMES[o.seat] or 'Passenger' end

local function act(action, o) TriggerServerEvent('c3r:stop:act', action, nil, o.net, true) end

-- The stop's people, by seat (driver first), that `keep` lets through.
local function people(s, keep)
    local out = {}
    for _, o in pairs(s.occ) do
        if DoesEntityExist(o.ped) and not IsEntityDead(o.ped) and not o.cuffed and not o.escaped and not o.fleeing and keep(o) then
            out[#out + 1] = o
        end
    end
    table.sort(out, function(a, b) return (a.seat or 9) < (b.seat or 9) end)
    return out
end
local function in_car(s, o) return DoesEntityExist(s.veh) and IsPedInVehicle(o.ped, s.veh, false) end

-- A felony stop's next steps: the person out now (walk them back, then down), and the next one still in the car.
-- -> { { action, o, label } }
function FelonySteps(s)
    local steps = {}
    for _, o in ipairs(people(s, function(o) return o.felony == 'out' or o.felony == 'back' end)) do
        steps[#steps + 1] = o.felony == 'out' and { action = 'fel_back', o = o, label = FelonyWho(o) .. ': walk back' }
            or { action = 'fel_kneel', o = o, label = FelonyWho(o) .. ': on your knees' }
    end
    local next_in = people(s, function(o) return in_car(s, o) end)[1]
    if next_in then steps[#steps + 1] = { action = 'fel_out', o = next_in, label = FelonyWho(next_in) .. ': step out' } end
    return steps
end

local function first_step(s, action)
    for _, st in ipairs(FelonySteps(s)) do if st.action == action then return st.o end end
end

-- cmd -> true when an order went out
local PA = {}

function PA.pull_over() return PaPullOver() end

function PA.felony(s)
    if not s or s.felony or s.foot or s.empty or not s.stopped then return false end
    for _, o in pairs(s.occ) do if o.out and not o.cuffed then return false end end -- someone's out already
    act('felony', s.occ[s.ped_net] or { net = s.ped_net })
    return true
end

function PA.driver_out(s)
    local d = s.occ[s.ped_net]
    if not d or not in_car(s, d) or d.cuffed then return false end
    act(s.felony and 'fel_out' or 'exit', d)
    return true
end

function PA.passenger_out(s)
    local p = people(s, function(o) return o.seat ~= -1 and in_car(s, o) end)[1]
    if not p then return false end
    act(s.felony and 'fel_out' or 'exit', p)
    return true
end

function PA.everyone_out(s)
    local list = people(s, function(o) return in_car(s, o) end)
    if #list == 0 then return false end
    if s.felony then act('fel_out', list[1]) return true end -- one at a time
    for _, o in ipairs(list) do act('exit', o) end
    return true
end

function PA.walk_back(s)
    local o = s.felony and first_step(s, 'fel_back')
    if not o then return false end
    act('fel_back', o)
    return true
end

-- Everyone out of the car, off a felony stop (there, it's one at a time).
local function all_out(s, action)
    local list = people(s, function(o) return not in_car(s, o) end)
    for _, o in ipairs(list) do act(action, o) end
    return #list > 0
end

function PA.kneel(s)
    if not s.felony then return all_out(s, 'kneel') end
    local o = first_step(s, 'fel_kneel') or first_step(s, 'fel_back') -- (told to kneel where they stand)
    if not o then return false end
    act('fel_kneel', o)
    return true
end

function PA.turn_around(s) return not s.felony and all_out(s, 'turn') end -- (on a felony stop they already are)

function PA.hands_up(s)
    local list = people(s, function(o) return not o.felony and o.doing ~= 'fel_out' end)
    for _, o in ipairs(list) do act('handsup', o) end
    return #list > 0
end

function PA.back_in(s)
    if s.felony or s.foot then return false end
    local list = people(s, function(o) return o.out and not in_car(s, o) end)
    for _, o in ipairs(list) do act('back', o) end
    return #list > 0
end

function PA.engine_off(s)
    if s.foot or not DoesEntityExist(s.veh)
        or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(s.veh)) > Config.PaRange then return false end
    CreateThread(function()
        NetworkRequestControlOfEntity(s.veh)
        local deadline = GetGameTimer() + 1000
        while not NetworkHasControlOfEntity(s.veh) and GetGameTimer() < deadline do Wait(0) end
        SetVehicleEngineOn(s.veh, false, true, true)
    end)
    TriggerEvent('c3r:stop:say', 'Turn off the engine!', 'officer')
    return true
end

-- One command, as the G wheel sends it.
function PaCommand(cmd)
    local run = PA[cmd]
    if not run then return false end
    local s = Stop
    if cmd ~= 'pull_over' and (not s or s.pursuit or not s.stopped) then return false end
    return run(s) == true
end

local OUT = { driver_out = true, passenger_out = true, everyone_out = true }

-- An order shouted at whoever the officer has their gun on, on foot and in earshot: them, not whoever they last spoke to.
local AT_GUNPOINT = { hands_up = 'handsup', kneel = 'kneel', turn_around = 'turn' }
function AimedPed()
    local me = PlayerId()
    local ok, ped = GetEntityPlayerIsFreeAimingAt(me)
    if not ok or ped == 0 then ok, ped = GetPlayerTargetEntity(me) end -- (locked on, not free aiming)
    if not ok or ped == 0 or not IsEntityAPed(ped) or IsPedAPlayer(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then return nil end
    return #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) < Config.PaRange and ped or nil
end

-- ─── the PA by hand: aim at someone, E, click the order (when the voice PA isn't heard right) ──────────────

-- Who the officer has their gun on, on foot and in earshot: anyone on foot, or one of this stop's people in its car
-- (aimed at the car: the first of them still inside, driver first). Not anyone cuffed, down or running.
local function pa_target()
    local me = PlayerId()
    if not LocalPlayer.state.c3rDuty or not OnPatrol() or IsPedInAnyVehicle(PlayerPedId(), false)
        or not IsPedArmed(PlayerPedId(), 4) then return nil end -- (a gun: not a fist's lock-on)
    local ok, e = GetEntityPlayerIsFreeAimingAt(me)
    if not ok or e == 0 then ok, e = GetPlayerTargetEntity(me) end
    if not ok or e == 0 then return nil end
    local s = Stop
    if IsEntityAVehicle(e) then
        if not (s and e == s.veh) then return nil end
        local list = people(s, function(o) return in_car(s, o) end)
        e = list[1] and list[1].ped
        if not e then return nil end
    end
    if not IsEntityAPed(e) or IsPedAPlayer(e) or IsEntityDead(e) or IsDowned(e) then return nil end
    local o = s and NetworkGetEntityIsNetworked(e) and s.occ[PedToNet(e)]
    if (o and (o.cuffed or o.fleeing)) or (not o and IsPedInAnyVehicle(e, false)) then return nil end
    if not o and s and not Casual(s) then return nil end -- (a stop on: only its people; a stranger would end it)
    local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(e))
    return d > 3.0 and d < Config.PaRange and e or nil -- (close enough to cuff: E is for that)
end

local function pa_orders(ped)
    local s = Stop
    local o = s and NetworkGetEntityIsNetworked(ped) and s.occ[PedToNet(ped)]
    local list = {}
    local function add(arg, label, icon) list[#list + 1] = { action = 'pa', arg = arg, label = label, icon = icon } end
    if o and IsPedInAnyVehicle(ped, false) then
        add('out', 'Step out of the vehicle', 'out')
        add('handsup', 'Hands up', 'handsup')
        return list
    end
    add('handsup', 'Hands up', 'handsup')
    if o and s.felony then -- one step at a time: only the next one (FelonySteps)
        if o.felony == 'out' then add('back', 'Walk back toward me', 'walk')
        elseif o.felony == 'back' then add('kneel', 'On your knees', 'handsup') end
        return list
    end
    add('kneel', 'On your knees', 'handsup')
    add('turn', 'Turn around', 'walk')
    if o and not s.foot then add('in', 'Back in the vehicle', 'in') end
    if o then add('stay', 'Stay right there', 'hand') end
    return list
end

-- One order, picked on the wheel (client/radial.lua).
function PaAt(ped, cmd)
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    local s = Stop
    local o = s and NetworkGetEntityIsNetworked(ped) and s.occ[PedToNet(ped)]
    if not o then
        local action = ({ handsup = 'handsup', kneel = 'kneel', turn = 'turn' })[cmd]
        if action and not (s and not s.foot) then RequestContact(ped, action) end -- (a car stop on: they're not part of it)
        return
    end
    local f = s.felony
    local action = ({ out = f and 'fel_out' or 'exit', back = 'fel_back', kneel = f and 'fel_kneel' or 'kneel', handsup = 'handsup',
                      turn = 'turn', ['in'] = 'back', stay = 'stay' })[cmd]
    if action then act(action, o) end
end

local pa_ped -- who E would open the PA on now
-- (menu.lua's E: the PA wheel first, while aiming at someone) -> true when it opened
function PaAim()
    if not pa_ped or not DoesEntityExist(pa_ped) then return false end
    return OpenPaWheel(pa_ped, pa_orders(pa_ped)) == true
end

CreateThread(function()
    while true do
        pa_ped = not IsNuiFocused() and pa_target() or nil
        if pa_ped then
            local h = GetPedBoneCoords(pa_ped, 31086, 0.0, 0.0, 0.0) -- SKEL_Head
            local on, x, y = GetScreenCoordFromWorldCoord(h.x, h.y, h.z + 0.5)
            if on then
                SetTextFont(4)
                SetTextScale(0.0, 0.4)
                SetTextCentre(true)
                SetTextOutline()
                SetTextColour(255, 255, 255, 230)
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(('Press ~b~%s~s~ to open the PA System'):format(KeyName('+c3r_interact', 'E')))
                EndTextCommandDisplayText(x, y)
            end
            Wait(0)
        else
            Wait(150)
        end
    end
end)

-- cmds: a command or a list of them, in the order said. On a felony stop only the first runs: one order at a time.
exports('pa', function(cmds)
    if not OnPatrol() then return false end
    if type(cmds) == 'string' then cmds = { cmds } end
    if type(cmds) ~= 'table' then return false end
    for _, cmd in ipairs(cmds) do
        local action = AT_GUNPOINT[cmd]
        local ped = action and not (Stop and Stop.felony) and AimedPed()
        if ped then
            local o = Stop and Stop.occ[NetworkGetEntityIsNetworked(ped) and PedToNet(ped) or -1]
            if o then act(action, o) return true end -- (on this stop: only them)
            if Stop and not Stop.foot then return false end -- (a car stop on: they're not part of it)
            RequestContact(ped, action) -- (anyone else: whoever was being spoken to on foot is left, and it's them now)
            return true
        end
    end
    local any, ordered_out = false, false
    for _, cmd in ipairs(cmds) do
        -- "step out with your hands up": the hands-up order would cancel getting out
        local skip = cmd == 'hands_up' and ordered_out
        if type(cmd) == 'string' and not skip and PaCommand(cmd) then
            any = true
            ordered_out = ordered_out or OUT[cmd] == true
            if cmd == 'felony' or (Stop and Stop.felony) then break end
        end
    end
    return any
end)
