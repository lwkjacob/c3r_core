-- The server owns every stick: where it is, who holds its cord. Clients only draw it and test their own wheels.

-- ---------------------------------------------------------------- framework bridge (jobs + item)
local core = Config.Framework
if core == 'auto' then
    core = GetResourceState('qbx_core') ~= 'missing' and 'qbx'
        or GetResourceState('qb-core') ~= 'missing' and 'qb'
        or GetResourceState('es_extended') ~= 'missing' and 'esx'
        or 'standalone'
end
local inv = GetResourceState('ox_inventory') ~= 'missing' and 'ox' or (core == 'qbx' and 'qb' or core)
local QB = core == 'qb' and exports['qb-core']:GetCoreObject()
local ESX = core == 'esx' and exports.es_extended:getSharedObject()

local source_ = Config.Source
if source_ == 'auto' then source_ = inv ~= 'standalone' and 'item' or 'vehicle' end
GlobalState.stopstickSource = source_
print(('[lwk_stopstick] framework: %s, inventory: %s, sticks from: %s'):format(core, inv, source_))

local function player(src)
    if core == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if core == 'qb' then return QB.Functions.GetPlayer(src) end
    if core == 'esx' then return ESX.GetPlayerFromId(src) end
end

local function allowed(src)
    if core == 'standalone' then return not Config.Ace or IsPlayerAceAllowed(src, Config.Ace) end
    if not next(Config.Jobs) then return true end
    local p = player(src)
    if not p then return false end
    local job = core == 'esx' and p.job or p.PlayerData.job
    return job ~= nil and Config.Jobs[job.name] == true and (core == 'esx' or job.onduty ~= false)
end

local function takeItem(src)
    local item = Config.Item
    if inv == 'ox' then return exports.ox_inventory:RemoveItem(src, item, 1) == true end
    local p = player(src)
    if not p then return false end
    if inv == 'qb' then return p.Functions.RemoveItem(item, 1) == true end
    local it = p.getInventoryItem(item)
    if not it or it.count < 1 then return false end
    p.removeInventoryItem(item, 1)
    return true
end

local function giveItem(src)
    local item = Config.Item
    if inv == 'ox' then return exports.ox_inventory:AddItem(src, item, 1) == true end
    local p = player(src)
    if not p then return false end
    if inv == 'qb' then return p.Functions.AddItem(item, 1) ~= false end
    p.addInventoryItem(item, 1)
    return true
end

local function notify(src, key) TriggerClientEvent('lwk_stopstick:notify', src, Config.Text[key]) end
local function debug(...) if Config.Debug then print('[lwk_stopstick]', ...) end end

-- ---------------------------------------------------------------- holding state (replicated: everyone draws the props)
local function hold(src) return Player(src).state.stopstick end
local function setHold(src, v) Player(src).state:set('stopstick', v, true) end

local function nearVehicle(src, net)
    local veh = net and NetworkGetEntityFromNetworkId(net) or 0
    if veh == 0 or not DoesEntityExist(veh) then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 8.0 then return end
    if next(Config.Vehicles) then
        local m, ok = GetEntityModel(veh), false
        for _, name in ipairs(Config.Vehicles) do ok = ok or m == joaat(name) end
        if not ok then return end
    end -- ponytail: the emergency-class check is client side (no server native); the model list is the hard gate
    local st = Entity(veh).state
    if st.stopsticks == nil then st:set('stopsticks', Config.PerVehicle, true) end
    return st
end

-- take one out: from the item, a vehicle's bay, or (free mode) from nowhere
local function take(src, net)
    if not allowed(src) then return notify(src, 'no_access') end
    if hold(src) then return notify(src, 'hands_full') end
    if source_ == 'item' then
        if not takeItem(src) then return notify(src, 'no_item') end
    elseif source_ == 'vehicle' then
        local st = nearVehicle(src, net)
        if not st then return notify(src, 'no_vehicle') end
        if st.stopsticks < 1 then return notify(src, 'none_left') end
        st:set('stopsticks', st.stopsticks - 1, true)
    end
    setHold(src, { s = 'carry' })
end

local function stow(src, net)
    local h = hold(src)
    if not h or h.s ~= 'carry' then return end
    if source_ == 'item' then
        if not giveItem(src) then return end
    elseif source_ == 'vehicle' then
        local st = nearVehicle(src, net)
        if not st then return notify(src, 'no_vehicle') end
        if st.stopsticks >= Config.PerVehicle then return notify(src, 'full') end
        st:set('stopsticks', st.stopsticks + 1, true)
    end
    setHold(src, nil)
end

RegisterNetEvent('lwk_stopstick:take', function(net) take(source, net) end)
RegisterNetEvent('lwk_stopstick:stow', function(net) stow(source, net) end)

-- Usable item. ox_inventory: give the item `server = { export = 'lwk_stopstick.useItem' }` (see README)
exports('useItem', function(event, _, inventory)
    if event == 'usedItem' then take(inventory.id) end
end)
CreateThread(function()
    if source_ ~= 'item' then return end
    if core == 'qbx' and inv ~= 'ox' then exports.qbx_core:CreateUseableItem(Config.Item, function(src) take(src) end) end
    if core == 'qb' and inv ~= 'ox' then QB.Functions.CreateUseableItem(Config.Item, function(src) take(src) end) end
    if core == 'esx' and inv ~= 'ox' then ESX.RegisterUsableItem(Config.Item, function(src) take(src) end) end
end)

-- ---------------------------------------------------------------- sticks
local sticks, nextId = {}, 0
local last = {} -- per player: last action time (rate limit)

local function now() return GetGameTimer() end

local function busy(src, gap)
    local t = now()
    if last[src] and t - last[src] < gap then return true end
    last[src] = t
end


-- what a client needs to draw it: positions plus how far into the flight / drag it is
local function pack(s)
    return { id = s.id, owner = s.cord and s.owner or nil, c = s.c, z = s.z, land = s.land, from = s.from, flight = s.flight, age = now() - s.t0 }
end

local function broadcast(name, ...) TriggerClientEvent('lwk_stopstick:' .. name, -1, ...) end

local function remove(id)
    if not sticks[id] then return end
    sticks[id] = nil
    broadcast('remove', id)
end

local function letGo(src)
    local h = hold(src)
    if h and h.s == 'cord' then
        local s = sticks[h.id]
        if s then s.cord, s.t0 = false, now(); broadcast('cord', s.id, nil) end
        setHold(src, nil)
    end
end

RegisterNetEvent('lwk_stopstick:throw', function(from, to)
    local src = source
    local h = hold(src)
    if not h or h.s ~= 'carry' or busy(src, 800) then return end
    local ped = GetPlayerPed(src)
    local me = GetEntityCoords(ped)
    from, to = vec3(from.x, from.y, from.z), vec3(to.x, to.y, to.z)
    if #(from - me) > 2.5 or #(to.xy - me.xy) > Config.ThrowRange + 1.5 then return debug('throw rejected', src) end
    nextId = nextId + 1
    local d = #(to.xy - from.xy)
    -- it unfurls along the throw, each stick a few degrees off the last (a thrown sleeve never lies dead straight),
    -- centred on the aim point with the cord end toward the officer
    local h = math.deg(math.atan(to.y - from.y, to.x - from.x))
    local c = StopStickChain(0.0, 0.0, { h + math.random(-6, 6), h + math.random(-8, 8), h + math.random(-8, 8) })
    local cx, cy = StopStickCenter(c)
    for i = 1, 4 do c.x[i], c.y[i] = c.x[i] + to.x - cx, c.y[i] + to.y - cy end
    local s = { id = nextId, owner = src, cord = true, c = c, z = to.z, pos = to, from = from,
                land = vec3((c.x[1] + c.x[2]) / 2.0, (c.y[1] + c.y[2]) / 2.0, to.z), -- the pack comes down where stick A lies
                flight = math.min(math.max(d / 9.0, 0.35), 0.9), t0 = now() }
    sticks[s.id] = s
    setHold(src, { s = 'cord', id = s.id })
    broadcast('spawn', pack(s))
    debug(('stick %d thrown by %d, %.1f m'):format(s.id, src, d))
end)

-- Another resource lays one (an AI unit, c3r): thrown from `from` and landing straight across at `at`, its line at
-- `angle` degrees (math.atan(y, x) of the line), no cord. officer: the server id told about hits (their sticks go when
-- they drop). -> the stick's id, for remove(id)
exports('deploy', function(officer, at, angle, from)
    at = vec3(at.x, at.y, at.z)
    from = from and vec3(from.x, from.y, from.z) or at + vec3(0.0, 0.0, 1.0)
    nextId = nextId + 1
    local c = StopStickChain(0.0, 0.0, { angle, angle, angle })
    local cx, cy = StopStickCenter(c)
    for i = 1, 4 do c.x[i], c.y[i] = c.x[i] + at.x - cx, c.y[i] + at.y - cy end
    local s = { id = nextId, owner = officer, cord = false, c = c, z = at.z, pos = at, from = from,
                land = vec3((c.x[1] + c.x[2]) / 2.0, (c.y[1] + c.y[2]) / 2.0, at.z),
                flight = math.min(math.max(#(at.xy - from.xy) / 9.0, 0.35), 0.9), t0 = now() }
    sticks[s.id] = s
    broadcast('spawn', pack(s))
    debug(('stick %d laid for %s'):format(s.id, tostring(officer)))
    return s.id
end)
exports('remove', function(id) remove(id) end)

-- A yank pulls the sleeve along the cord toward the officer in one go: from the far shoulder into the lane, then
-- out of it. The cord end is hauled, the other sticks follow as a physics chain (shared/tow.lua); every client runs the
-- same steps from the same start, the server just needs the resting state for pickups and the next yank.
RegisterNetEvent('lwk_stopstick:yank', function()
    local src = source
    local h = hold(src)
    local s = h and h.s == 'cord' and sticks[h.id]
    if not s or busy(src, 700) or now() - s.t0 < s.flight * 1000 + 400 or now() < (s.sliding or 0) then return end
    local me = GetEntityCoords(GetPlayerPed(src))
    local vx, vy = me.x - s.c.x[1], me.y - s.c.y[1]
    local d = math.sqrt(vx * vx + vy * vy)
    local dist = math.min(Config.YankDistance, d - Config.MinDistance)
    if dist <= 0.05 then return end
    local start = s.c
    local final, sim = StopStickYankFinal(start, vx / d, vy / d, dist)
    s.c = final
    local cx, cy = StopStickCenter(final)
    s.pos = vec3(cx, cy, s.z)
    s.sliding = now() + sim.steps * StopStickDT * 1000
    broadcast('yank', s.id, vx / d, vy / d, dist, start)
end)

RegisterNetEvent('lwk_stopstick:release', function() letGo(source) end)

RegisterNetEvent('lwk_stopstick:pickup', function(id)
    local src = source
    local s = sticks[id]
    local h = hold(src)
    if not s or (h and not (h.s == 'cord' and h.id == id)) or busy(src, 800) or not allowed(src) then return end
    if #(GetEntityCoords(GetPlayerPed(src)).xy - s.pos.xy) > 3.0 then return end
    if s.cord then letGo(s.owner) end -- whoever held its cord (maybe you) lets go
    remove(id)
    setHold(src, { s = 'carry' })
end)

-- the wheel's owner reports a hit (the burst itself already happened there and syncs with the vehicle). The front
-- and rear axles cross a few frames apart, so reports for one car are gathered for a moment and the officer who
-- threw the stick gets a single "Hit! 4 tyres" notice per pass.
local passes = {}

RegisterNetEvent('lwk_stopstick:hit', function(id, net, tyres, label)
    local s = sticks[id]
    if not s or type(tyres) ~= 'table' then return end
    local key = ('%d:%s'):format(id, tostring(net or source))
    local p = passes[key]
    if not p then
        p = { tyres = {}, label = tostring(label or '?'):sub(1, 40), officer = s.owner }
        passes[key] = p
        CreateThread(function()
            Wait(1500)
            passes[key] = nil
            local list = {}
            for t in pairs(p.tyres) do list[#list + 1] = t end
            local n = #list
            if GetPlayerPing(p.officer) > 0 then
                TriggerClientEvent('lwk_stopstick:notify', p.officer, Config.Text.hit:format(p.label, n, n == 1 and '' or 's'))
            end
            TriggerEvent('lwk_stopstick:vehicleHit', { stick = id, officer = p.officer, vehicle = net, tyres = list, label = p.label, coords = s.pos })
            debug(('stick %d hit %s (%s), tyres %s'):format(id, p.label, tostring(net), json.encode(list)))
        end)
    end
    for _, t in ipairs(tyres) do
        if type(t) == 'number' and t >= 0 and t <= 7 then p.tyres[t] = true end
    end
end)

RegisterNetEvent('lwk_stopstick:sync', function()
    local list = {}
    for _, s in pairs(sticks) do list[#list + 1] = pack(s) end
    TriggerClientEvent('lwk_stopstick:sync', source, list)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for id, s in pairs(sticks) do
        if s.owner == src then remove(id) end -- nobody left to pull it out of the lane
    end
    last[src] = nil
end)

CreateThread(function() -- sticks nobody holds the cord of are cleared after Config.Despawn
    while true do
        Wait(10000)
        if Config.Despawn > 0 then
            for id, s in pairs(sticks) do
                if not s.cord and now() - s.t0 > Config.Despawn * 1000 then remove(id) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do Player(id).state:set('stopstick', nil, true) end
end)
