local weapons = {}
for name in pairs(Config.Weapons) do weapons[GetHashKey(name) & 0xFFFFFFFF] = true end

local function holding(ped)
    return ped ~= 0 and weapons[GetSelectedPedWeapon(ped) & 0xFFFFFFFF]
end

-- Inventory bridge: the only framework touch point is "take one cartridge"
local inv = Config.Framework
if inv == 'auto' then
    inv = GetResourceState('ox_inventory') ~= 'missing' and 'ox'
        or GetResourceState('qb-core') ~= 'missing' and 'qb'
        or GetResourceState('es_extended') ~= 'missing' and 'esx'
        or 'standalone'
end
local QB = inv == 'qb' and exports['qb-core']:GetCoreObject()
local ESX = inv == 'esx' and exports.es_extended:getSharedObject()
print(('[lwk_taser] inventory: %s'):format(inv))

local function takeCartridge(src)
    local item = Config.CartridgeItem
    if inv == 'ox' then
        return exports.ox_inventory:RemoveItem(src, item, 1) == true
    elseif inv == 'qb' then
        local p = QB.Functions.GetPlayer(src)
        return p ~= nil and p.Functions.RemoveItem(item, 1) == true
    elseif inv == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        local it = x and x.getInventoryItem(item)
        if not it or it.count < 1 then return false end
        x.removeInventoryItem(item, 1)
        return true
    end
    return true
end

-- IDs are minted here so every framework (and standalone) gets the same audit trail
local function mint() return ('CRT-%06X'):format(math.random(0, 0xFFFFFF)) end

local function deviceId(src)
    local key = 'device:' .. (GetPlayerIdentifierByType(src, 'license') or ('src' .. src))
    local id = GetResourceKvpString(key)
    if not id then
        id = ('TSR-%06X'):format(math.random(0, 0xFFFFFF))
        SetResourceKvp(key, id)
    end
    return id
end

-- ponytail: bays live in memory, a relog resets them; persist per device if that matters
local officers, barbs = {}, {}

-- One magazine = Config.Probes single probes, IDs CRT-XXXXXX-01..10
local function loadMag(o)
    o.mag = mint()
    for i = 1, Config.Probes do o.bays[i] = { s = 'live', id = ('%s-%02d'):format(o.mag, i) } end
    return o.mag
end

local function officer(src)
    local o = officers[src]
    if not o then
        o = { device = deviceId(src), bays = {}, busy = 0, last = {} }
        if inv == 'standalone' then
            loadMag(o)
        else
            for i = 1, Config.Probes do o.bays[i] = { s = 'empty' } end
        end
        officers[src] = o
    end
    return o
end

local function sendBays(src, o) TriggerClientEvent('lwk_taser:bays', src, o.bays, o.device) end

-- Every action passes through here: weapon in hand, taser state, rate limit (per action, so a held trigger
-- doesn't swallow the next shot, ARC or reload)
local function check(src, o, action, gap, needArmed)
    local ped = GetPlayerPed(src)
    if not holding(ped) then return end
    if needArmed and not Player(src).state.taser then return end
    local now = GetGameTimer()
    if now - (o.last[action] or 0) < gap then return end
    o.last[action] = now
    return ped
end

-- Audit: local event for MDTs etc, plus a paced Discord queue
local hook = GetConvar('lwk_taser_webhook', '')
local queue = {}

local function who(ent)
    if not ent or ent == 0 then return 'none' end
    if IsPedAPlayer(ent) then
        local s = NetworkGetEntityOwner(ent)
        return ('%s [%d]'):format(GetPlayerName(s) or '?', s)
    end
    return 'NPC'
end

local function log(src, action, d)
    local o = officers[src]
    local ped = GetPlayerPed(src)
    local c = ped ~= 0 and GetEntityCoords(ped) or vec3(0, 0, 0)
    local data = {
        action = action, officer = src, name = GetPlayerName(src) or '?',
        device = o and o.device or '?', cartridge = d.cart or 'n/a',
        target = d.target or 'n/a', outcome = d.outcome or '-', coords = c,
    }
    TriggerEvent('lwk_taser:used', data)
    if hook ~= '' then queue[#queue + 1] = data end
end

CreateThread(function()
    while true do
        Wait(1100) -- stays under Discord's webhook rate limit
        local d = table.remove(queue, 1)
        if d then
            local f = function(n, v) return { name = n, value = tostring(v), inline = true } end
            PerformHttpRequest(hook, function() end, 'POST', json.encode({
                username = 'Taser Audit',
                embeds = { {
                    title = d.action, color = 16766720,
                    fields = {
                        f('Officer', ('%s [%d]'):format(d.name, d.officer)), f('Device', d.device),
                        f('Cartridge', d.cartridge), f('Target', d.target), f('Outcome', d.outcome),
                        f('Location', ('%.1f, %.1f, %.1f'):format(d.coords.x, d.coords.y, d.coords.z)),
                    },
                    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                } },
            }), { ['Content-Type'] = 'application/json' })
        end
    end
end)

-- key: sounds with the same key continue one playback (an extended cycle keeps its clip running seamlessly)
local function sound(pos, name, key)
    for _, id in ipairs(GetPlayers()) do
        local p = GetPlayerPed(id)
        if p ~= 0 and #(GetEntityCoords(p) - pos) < Config.SoundRange then
            TriggerClientEvent('lwk_taser:sound', tonumber(id), pos, name, key)
        end
    end
end

-- The entity owner applies the ragdoll (works for players and networked NPCs)
local function shock(src, o, ent, mode)
    local owner = NetworkGetEntityOwner(ent)
    if owner and owner > 0 then
        TriggerClientEvent('lwk_taser:shock', owner, NetworkGetNetworkIdFromEntity(ent), mode)
    end
    o.busy = GetGameTimer() + Config.CycleTime * 1000
    TriggerClientEvent('lwk_taser:cycle', src)
end

-- rec = { probes = { { s = officer src, k = bay 1-10 it was fired from, b = bone, c = probe id, w = wired, o = hit offset, d = hit dir }, ... } }
-- One record per target; any number of officers can have probes in it, each keeps its own wires.
local function setBarbs(net, rec)
    if rec and #rec.probes == 0 then rec = nil end
    barbs[net] = rec
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent ~= 0 then
        local p = {}
        if rec then for i, x in ipairs(rec.probes) do p[i] = { s = x.s, k = x.k, b = x.b, w = x.w, o = x.o, d = x.d } end end
        Entity(ent).state:set('taserBarbs', rec and { p = p } or nil, true)
    end
end

-- any wired probe (of officer src, or of anyone)
local function wired(rec, src)
    for _, p in ipairs(rec.probes) do if p.w and (not src or p.s == src) then return true end end
    return false
end

local function carts(rec)
    local t = {}
    for i, p in ipairs(rec.probes) do t[i] = p.c end
    return table.concat(t, ', ')
end

-- cut wires: of officer src (or everyone), optionally only probes whose id starts with prefix
local function unwire(net, rec, prefix, src)
    local changed = false
    for _, p in ipairs(rec.probes) do
        if p.w and (not src or p.s == src) and (not prefix or p.c:find(prefix, 1, true) == 1) then p.w, changed = false, true end
    end
    if changed then setBarbs(net, rec) end
end

local BONES = {}
for _, b in ipairs({ 11816, 23553, 24816, 24817, 24818, 39317, 31086, 64729, 10706, 45509, 40269, 61163, 28252,
                     18905, 57005, 58271, 51826, 63931, 36864, 14201, 52301 }) do BONES[b] = true end

local function targetEnt(net, ped, pos, range)
    if type(net) ~= 'number' or net <= 0 then return 0 end
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent == 0 or ent == ped or GetEntityType(ent) ~= 1 or #(GetEntityCoords(ent) - pos) > range then return 0 end
    return ent
end

RegisterNetEvent('lwk_taser:sync', function()
    local src = source
    sendBays(src, officer(src))
end)

-- client-sent bone-space vector: must be a finite vector3 no longer than max, else dropped (barb falls back to bone spread)
local function boneVec(v, max)
    if type(v) ~= 'vector3' then return nil end
    local l = #v
    if l ~= l or l > max then return nil end
    return v
end

-- TASER 10: one probe per trigger pull, any hit = full cycle
RegisterNetEvent('lwk_taser:fire', function(bay, net, bone, off, dir)
    local src = source
    local o = officer(src)
    local ped = check(src, o, 'fire', 400, true)
    local b = ped and o.bays[bay]
    if not b or b.s ~= 'live' then return end
    b.s = 'spent'

    local pos = GetEntityCoords(ped)
    local ent = targetEnt(net, ped, pos, Config.Range + 1.5) -- client raycasts, server checks plausibility
    if ent ~= 0 then
        local tnet = NetworkGetNetworkIdFromEntity(ent)
        local rec = barbs[tnet] or { probes = {} } -- other officers' barbs stay
        local valid = BONES[bone] ~= nil
        off, dir = valid and boneVec(off, 0.6), valid and boneVec(dir, 1.5)
        if not (off and dir and #dir > 0.5) then off, dir = nil, nil end
        rec.probes[#rec.probes + 1] = { s = src, k = bay, b = valid and bone or 24817, c = b.id, w = true, o = off, d = dir }
        local mine = 0 -- cap per officer: drop this officer's oldest probe beyond one magazine
        for _, p in ipairs(rec.probes) do if p.s == src then mine = mine + 1 end end
        if mine > Config.Probes then
            for i, p in ipairs(rec.probes) do if p.s == src then table.remove(rec.probes, i) break end end
        end
        setBarbs(tnet, rec)
        o.lastNet = tnet
        shock(src, o, ent, 'lockout')
    end

    sound(pos, 'fire')
    if ent ~= 0 then sound(pos, 'cycle', src) end
    sendBays(src, o)
    log(src, 'Probe deployed (bay ' .. bay .. ')', { cart = b.id, target = who(ent), outcome = ent ~= 0 and 'hit' or 'miss' })
end)

-- another cycle through this officer's own wired barbs on their last target; false if there is no circuit
local function reEnergise(src, o, pos, how)
    local rec = o.lastNet and barbs[o.lastNet]
    local tgt = rec and NetworkGetEntityFromNetworkId(o.lastNet) or 0
    if not (rec and wired(rec, src) and tgt ~= 0) then return false end
    shock(src, o, tgt, 'lockout')
    sound(pos, 'cycle', src)
    log(src, how, { cart = carts(rec), target = who(tgt), outcome = 'lockout' })
    return true
end

-- ARC switch: re-energise wired barbs, else warning arc. Drive stun (TASER 10 has none) only with Config.DriveStun
RegisterNetEvent('lwk_taser:arc', function(net)
    local src = source
    local o = officer(src)
    local ped = check(src, o, 'arc', 1000, true)
    if not ped or GetGameTimer() < o.busy then return end
    local pos = GetEntityCoords(ped)

    local ent = Config.DriveStun and targetEnt(net, ped, pos, Config.DriveStunRange + 1.0) or 0
    if ent ~= 0 then
        local rec = barbs[net]
        local circuit = rec and wired(rec, src)
        local mode = (circuit or Config.DriveStunLockout) and 'lockout' or 'pain'
        shock(src, o, ent, mode)
        sound(pos, 'cycle', src)
        log(src, circuit and 'Drive stun (circuit completed)' or 'Drive stun', { cart = rec and carts(rec), target = who(ent), outcome = mode })
        return
    end

    if reEnergise(src, o, pos, 'Re-energised') then return end

    sound(pos, 'arc')
    log(src, 'Warning arc', {})
end)

-- Trigger held past the end of a cycle: TASER 10 keeps cycling until it is released
RegisterNetEvent('lwk_taser:hold', function()
    local src = source
    local o = officer(src)
    local ped = check(src, o, 'hold', 200, true)
    -- start the next cycle just before this one ends, so the ragdoll and the sound never drop out
    if not ped or GetGameTimer() < o.busy - 600 then return end
    reEnergise(src, o, GetEntityCoords(ped), 'Cycle extended (trigger held)')
end)

RegisterNetEvent('lwk_taser:reload', function()
    local src = source
    local o = officer(src)
    local ped = check(src, o, 'reload', 1500, false)
    if not ped then return end
    if (o.reloading or 0) > GetGameTimer() then return end
    local full = true
    for i = 1, Config.Probes do if o.bays[i].s ~= 'live' then full = false break end end
    if full or not takeCartridge(src) then return end -- no item: keep the current magazine

    local R = Config.Reload
    o.reloading = GetGameTimer() + R.length * 1000
    TriggerClientEvent('lwk_taser:reloadAnim', src)
    sound(GetEntityCoords(ped), 'reload')
    SetTimeout(math.floor(R.drop * R.length * 1000), function() -- old cartridge leaves the gun: wires cut
        if o.mag then
            for net, rec in pairs(barbs) do unwire(net, rec, o.mag, src) end
        end
    end)
    SetTimeout(math.floor(R.seat * R.length * 1000), function() -- new one clicks in
        if not GetPlayerName(src) then return end
        local mag = loadMag(o)
        sendBays(src, o)
        sound(GetEntityCoords(GetPlayerPed(src)), 'charge') -- arming charge-up once the new cartridge is in
        log(src, 'Magazine loaded', { cart = mag })
    end)
end)

RegisterNetEvent('lwk_taser:remove', function(net)
    local src = source
    local rec = barbs[net]
    if not rec then return end
    local ped = GetPlayerPed(src)
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent == 0 or ent == ped or #(GetEntityCoords(ent) - GetEntityCoords(ped)) > 3.0 then return end
    setBarbs(net, nil)
    log(src, 'Barbs removed', { cart = carts(rec), target = who(ent) })
end)

local lastToggle = {}
RegisterNetEvent('lwk_taser:toggle', function()
    local src = source
    local now = GetGameTimer()
    if now - (lastToggle[src] or 0) < 250 then return end
    lastToggle[src] = now
    sound(GetEntityCoords(GetPlayerPed(src)), 'click')
end)

-- Wire watchdog: rip out past WireLength, disconnect on holster / officer gone
CreateThread(function()
    while true do
        Wait(500)
        for net, rec in pairs(barbs) do
            local ent = NetworkGetEntityFromNetworkId(net)
            if ent == 0 or not DoesEntityExist(ent) then
                barbs[net] = nil
            else
                local seen = {}
                for _, p in ipairs(rec.probes) do
                    local src = p.s
                    if p.w and not seen[src] then -- each officer's wires on their own
                        seen[src] = true
                        local off = GetPlayerPed(src)
                        if off == 0 or not holding(off) then
                            unwire(net, rec, nil, src)
                        elseif #(GetEntityCoords(off) - GetEntityCoords(ent)) > Config.WireLength then
                            local gone, kept = {}, {}
                            for _, q in ipairs(rec.probes) do
                                if q.s == src then gone[#gone + 1] = q.c else kept[#kept + 1] = q end
                            end
                            rec.probes = kept
                            setBarbs(net, rec)
                            sound(GetEntityCoords(ent), 'rip')
                            log(src, 'Barbs ripped out (distance)', { cart = table.concat(gone, ', '), target = who(ent) })
                            break -- rec.probes changed under the loop
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    officers[source] = nil
    lastToggle[source] = nil
end)
