--[[
    lwk_scene — server: the scene's list (every cone, flare, barrier and span of tape out there), sent to every game.
    Only police on duty in c3r place or pick up; an officer's things go when they go off duty or leave; flares burn
    out; tape tied to a car snaps when the car moves off. BY LWK DEVELOPMENT
]]

local function log(...) if Config.Debug then print('[lwk_scene]', ...) end end

local Items = {}   -- [id] = item (shared/scene.lua), as every game has it
local Extra = {}   -- [id] = { expires (os.time), anchors = { { net, at } } }: the server's own
local last = 0

local PROPS = setmetatable({}, { __index = function(_, k) return Scene.props[k] end })
local STYLES = setmetatable({}, { __index = function(_, k) return Scene.styles[k] end })

local function police(src) return exports.c3r:isOnDuty(src) == true and Player(src).state.c3rService == 'police' end
local function at(src) local ped = GetPlayerPed(src) return ped ~= 0 and GetEntityCoords(ped) or nil end

local function num(v) return type(v) == 'number' and v == v and math.abs(v) < 100000 and v or nil end
local function point(t)
    if type(t) ~= 'table' then return nil end
    local x, y, z = num(t.x), num(t.y), num(t.z)
    return x and y and z and { x = x, y = y, z = z } or nil
end

local function set(id, it)
    Items[id] = it
    if not it then Extra[id] = nil end
    TriggerClientEvent('lwk_scene:set', -1, id, it)
end

local function remove(id)
    local it = Items[id]
    if not it then return end
    set(id, nil)
    if it.kind == 'prop' then -- (its tape goes with it)
        local r = PROPS[it.prop] and tonumber(PROPS[it.prop].tie)
        for tid, t in pairs(Items) do
            if t.ap == id or t.bp == id or Scene.tiedTo(t, it.pos, r) then set(tid, nil) end
        end
    end
end

local function clear(src)
    for id, it in pairs(Items) do if it.owner == src then remove(id) end end -- (and tape tied to theirs)
end

-- a car the tape is tied to: where it stood
local function anchor(net)
    net = tonumber(net)
    local ent = net and NetworkGetEntityFromNetworkId(net) or 0
    if ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 2 then return nil end
    return { net = net, at = GetEntityCoords(ent) }
end

-- a modded game spamming events: at most 10 a second each
local budget = {}
local function spam(src)
    local now, b = GetGameTimer(), budget[src]
    if not b or now - b.t >= 1000 then budget[src] = { t = now, n = 1 } return false end
    b.n = b.n + 1
    return b.n > 10
end

RegisterNetEvent('lwk_scene:place', function(d)
    local src = source
    if spam(src) or not police(src) or type(d) ~= 'table' then return end
    if Scene.count(Items, src) >= Config.Cap then return TriggerClientEvent('lwk_scene:no', src, 'cap') end
    local me = at(src)
    if not me then return end
    local it, extra
    if d.kind == 'prop' then
        local pos, h = point(d.pos), num(d.h)
        if not PROPS[d.prop] or not pos or not h or Scene.dist2d(pos, me) > Config.Reach + 3.0 or math.abs(pos.z - me.z) > 5.0 then return end
        it = { kind = 'prop', prop = d.prop, pos = pos, h = h % 360.0 }
        if PROPS[d.prop].flare then extra = { expires = os.time() + Config.FlareMinutes * 60 } end
    elseif d.kind == 'tape' then
        local a, b = point(d.a), point(d.b)
        if not STYLES[d.style] or not a or not b then return end
        local len = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
        if len < 0.3 or len > Config.Tape.max + 0.5 or Scene.dist2d(b, me) > 30.0 or Scene.dist2d(a, me) > Config.Tape.max + 30.0
            or math.abs(a.z - me.z) > 8.0 or math.abs(b.z - me.z) > 8.0 then return end
        it = { kind = 'tape', style = d.style, a = a, b = b }
        for _, k in ipairs({ 'ap', 'bp' }) do -- (an end tied to a scene prop: drawn from it, and goes with it)
            local pid = tonumber(d[k])
            if pid and Items[pid] and Items[pid].kind == 'prop' then it[k] = pid end
        end
        local anchors = {}
        for _, net in ipairs({ d.an or false, d.bn or false }) do anchors[#anchors + 1] = net and anchor(net) or nil end
        extra = anchors[1] and { anchors = anchors } or nil
    else
        return
    end
    last = last + 1
    it.id, it.owner = last, src
    Extra[last] = extra
    log(('%d placed %s #%d'):format(src, it.prop or ('tape ' .. it.style), last))
    set(last, it)
end)

RegisterNetEvent('lwk_scene:pickup', function(id)
    local src = source
    local it = Items[tonumber(id) or -1]
    local me = at(src)
    if spam(src) or not police(src) or not it or not me or Scene.itemDist(it, me) > Config.PickupReach + 2.0 then return end
    log(('%d picked up #%d'):format(src, it.id))
    remove(it.id)
end)

RegisterNetEvent('lwk_scene:clear', function()
    local src = source
    if not spam(src) and police(src) then clear(src) end
end)

RegisterNetEvent('lwk_scene:sync', function() TriggerClientEvent('lwk_scene:all', source, Items) end)

AddEventHandler('c3r:duty', function(src, on) if not on then clear(src) end end)
AddEventHandler('playerDropped', function() clear(source) budget[source] = nil end)
-- c3r restarting puts everyone off duty without c3r:duty: their things go too
AddEventHandler('onResourceStart', function(res)
    if res ~= 'c3r' then return end
    for id in pairs(Items) do set(id, nil) end
end)

-- flares burn out; tape tied to a car snaps when it drives off (or it's gone)
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for id, x in pairs(Extra) do
            local gone = x.expires and now >= x.expires
            for _, a in ipairs(x.anchors or {}) do
                local ent = NetworkGetEntityFromNetworkId(a.net)
                if ent == 0 or not DoesEntityExist(ent) or #(GetEntityCoords(ent) - a.at) > 1.5 then gone = true end
            end
            if gone then remove(id) end
        end
    end
end)
