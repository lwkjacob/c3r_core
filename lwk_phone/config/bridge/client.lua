-- Framework bridge (client): when the player's character is ready, when it goes away, and
-- the few things that differ per framework on the client.

Bridge = Bridge or {}

local function present(res) return GetResourceState(res) ~= 'missing' end

-- A framework that is running wins over one whose folder is merely on the server (a leftover, or a copy
-- that never started). Failing that, one that is installed is taken: it may be started after the phone.
local FRAMEWORKS = { { 'qbox', 'qbx_core' }, { 'qb', 'qb-core' }, { 'esx', 'es_extended' }, { 'ox', 'ox_core' }, { 'nd', 'ND_Core' } }

local function detect()
    for _, f in ipairs(FRAMEWORKS) do
        local state = GetResourceState(f[2])
        if state == 'started' or state == 'starting' then return f[1] end
    end
    for _, f in ipairs(FRAMEWORKS) do
        if present(f[2]) then return f[1] end
    end
    return 'standalone'
end

local fw = Config.framework ~= 'auto' and Config.framework or detect()
Bridge.framework = fw

local ESX = fw == 'esx' and exports.es_extended:getSharedObject() or nil

-- The ND_Core before 2.0: one NDCore object instead of exports (see config/bridge/framework.lua).
local nd1 = fw == 'nd' and (tonumber((GetResourceMetadata('ND_Core', 'version', 0) or ''):match('^%d+')) or 2) < 2

--- True when a character is in the world.
function Bridge.loaded()
    if fw == 'esx' then return ESX.IsPlayerLoaded() end
    if fw == 'qb' or fw == 'qbox' then return LocalPlayer.state.isLoggedIn == true end
    if fw == 'ox' then   -- a character has been chosen once the player has a charId
        local ok, p = pcall(function() return exports.ox_core:GetPlayer() end)
        return ok and type(p) == 'table' and p.charId ~= nil
    end
    if fw == 'nd' then
        if GetResourceState('ND_Core') ~= 'started' then return false end
        if nd1 then return exports.ND_Core:GetCoreObject().Functions.GetSelectedCharacter() ~= nil end
        return exports.ND_Core:getPlayer() ~= nil
    end
    return NetworkIsPlayerActive(PlayerId())
end

--- onLoad: a character finished loading. onUnload: logged out or switched character.
function Bridge.watch(onLoad, onUnload)
    if fw == 'esx' then
        RegisterNetEvent('esx:playerLoaded', onLoad)
        RegisterNetEvent('esx:onPlayerLogout', onUnload)
    elseif fw == 'qb' or fw == 'qbox' then
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', onLoad)
        RegisterNetEvent('QBCore:Client:OnPlayerUnload', onUnload)
    elseif fw == 'ox' then   -- raised inside the player's own game, not sent from the server
        AddEventHandler('ox:playerLoaded', function() onLoad() end)
        AddEventHandler('ox:playerLogout', function() onUnload() end)
    elseif nd1 then   -- one event, for the first character and for every change of character after it
        RegisterNetEvent('ND:setCharacter', function()
            onUnload()
            onLoad()
        end)
    elseif fw == 'nd' then
        RegisterNetEvent('ND:characterLoaded', function() onLoad() end)
        RegisterNetEvent('ND:characterUnloaded', function() onUnload() end)
    end
end

--- Whether the phone may be raised right now. Add your own checks (cuffed, in a menu...).
function Bridge.canOpen()
    local ped = PlayerPedId()
    return not IsEntityDead(ped) and not IsPedCuffed(ped) and not IsPauseMenuActive()
end

--- Called after the valet spawns a vehicle, to hand the player its keys.
--- An event nothing listens for does nothing, so each key script's own event is simply fired.
--- For a key script that needs something else, add its call here.
function Bridge.giveKeys(vehicle, plate)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)   -- qb-vehiclekeys, qbx_vehiclekeys, and key scripts that copy them
    TriggerEvent('cd_garage:AddKeys', plate)
    if GetResourceState('okokGarage') == 'started' then TriggerServerEvent('okokGarage:GiveKeys', plate) end
end

--- The other end of a call muted (or unmuted) their microphone: stop (or go back to) hearing
--- player `id` over the call. The voice script resets this by itself when the call ends.
function Bridge.callMute(id, muted)
    if GetResourceState('pma-voice') == 'started' then
        MumbleSetVolumeOverrideByServerId(id, muted and 0.0 or exports['pma-voice']:getCallVolume())
    elseif GetResourceState('mumble-voip') == 'started' then
        MumbleSetVolumeOverrideByServerId(id, muted and 0.0 or 1.0)   -- 1.0 is what it gives everyone on a call
    end
    -- saltychat carries voice over TeamSpeak, where this game cannot turn one player down.
end

-- mumble-voip takes the call channel from the player's own game and nowhere else.
RegisterNetEvent('lwk_phone:voice', function(channel)
    if GetResourceState('mumble-voip') == 'started' then exports['mumble-voip']:SetCallChannel(channel) end
end)

-- Housing ------------------------------------------------------------------------------------------
-- The part of the Home app that has to happen in the player's own game, because that is the only
-- place the housing script takes it from (see the table at the top of config/bridge/housing.lua).
-- Each branch is that script's own documented export, event or callback.

Bridge.home = {}

local function running(res) return GetResourceState(res) == 'started' end

--- The player's houses, for a script that only says so on the client (vms_housing). Nil otherwise.
function Bridge.home.list()
    if not running('vms_housing') then return nil end
    local vms, out = exports['vms_housing'], {}
    -- With keys as items there is nobody to list or revoke: a key is whoever holds the item.
    local items = vms:GetConfiguration('UseKeysOnItem')
    for _, p in ipairs(vms:GetPlayerProperties() or {}) do
        local meta = Util.decode(p.metadata)
        local at = meta.enter or meta.menu
        if p.object_id then
            local building = vms:GetProperty(p.object_id)
            if building and building.type == 'building' and building.metadata and building.metadata.enter then at = building.metadata.enter end
        end
        local keys
        if not items then
            keys = {}
            for identifier, name in pairs(Util.decode(p.keys)) do keys[#keys + 1] = { id = identifier, name = name } end
        end
        out[#out + 1] = { id = p.id, name = p.name, x = at and at.x, y = at and at.y, keys = keys }
    end
    return out
end

--- Carry out what the server could not: { action = 'lock' | 'key', id, give, identifier, target }.
--- `identifier` is the character, `target` their server id when they are online.
function Bridge.home.run(step)
    local id, key = step.id, step.action == 'key'
    if running('nolag_properties') then
        if key and step.give then exports.nolag_properties:AddKey(id, step.identifier) end
        if key and not step.give then exports.nolag_properties:RemoveKey(id, step.identifier) end
    elseif running('vms_housing') then
        if key and step.give and step.target then
            TriggerServerEvent('vms_housing:sv:buyKey', id, step.target)
            TriggerServerEvent('vms_housing:sv:giveKey', id, step.target)
        elseif key and not step.give then
            TriggerServerEvent('vms_housing:sv:removeKey', id, step.identifier)
        end
    elseif running('ps-housing') then
        if key and step.give and step.target then TriggerServerEvent('ps-housing:server:addAccess', id, step.target) end
        if key and not step.give then TriggerServerEvent('ps-housing:server:removeAccess', id, step.identifier) end
    elseif running('qb-houses') then
        if key and step.give and step.target then TriggerServerEvent('qb-houses:server:giveHouseKey', step.target, id) end
        if key and not step.give then TriggerServerEvent('qb-houses:server:removeHouseKey', id, { citizenid = step.identifier }) end
    elseif running('esx_property') then
        local ESX = exports.es_extended:getSharedObject()
        local done = function() end
        if step.action == 'lock' then
            ESX.TriggerServerCallback('esx_property:toggleLock', done, id)
        elseif step.give and step.target then
            ESX.TriggerServerCallback('esx_property:GiveKey', done, id, step.target)
        elseif key and not step.give then
            ESX.TriggerServerCallback('esx_property:RemoveKey', done, id, step.identifier)
        end
    end
end

--- Set a waypoint to a house whose position only its script knows.
function Bridge.home.waypoint(id)
    if running('nolag_properties') then exports.nolag_properties:SetWaypointToProperty(id) end
end
