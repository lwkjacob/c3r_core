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

function PA.kneel(s)
    local o = s.felony and first_step(s, 'fel_kneel')
    if not o and s.felony then o = first_step(s, 'fel_back') end -- told to kneel where they stand
    if not o then return false end
    act('fel_kneel', o)
    return true
end

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

-- cmds: a command or a list of them, in the order said. On a felony stop only the first runs: one order at a time.
exports('pa', function(cmds)
    if not LocalPlayer.state.c3rDuty then return false end
    if type(cmds) == 'string' then cmds = { cmds } end
    if type(cmds) ~= 'table' then return false end
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
