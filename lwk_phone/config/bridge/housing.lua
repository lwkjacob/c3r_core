-- Housing bridge (server): what the Home app knows about the server's housing script.
--
-- Housing scripts share no interface, so each one below is written from that script's own
-- documentation or source, and does only what that script offers:
--
--   script             list   lock   keys   how
--   nolag_properties   yes    yes    yes    its server exports; keys and the waypoint through its client exports
--   vms_housing        yes    -      yes    its client exports and events (see config/bridge/client.lua)
--   rtx_housing        yes    yes    -      its server exports
--   ps-housing         yes    -      yes    its `properties` table; keys through its own events
--   qbx_properties     yes    -      yes    its `properties` table
--   esx_property       yes    yes    yes    its properties.json; lock and keys through its own callbacks
--   qb-houses          yes    -      yes    its `player_houses` table; keys through its own events
--   bcs_housing        yes    yes    yes    its server exports (the lock only for shell and IPL houses, as it says)
--   RxHousing          yes    -      yes    its server exports
--
-- "its own events / callbacks" means the player's game asks the housing script itself, which then
-- applies its own checks; this file never changes another script's data behind its back, except
-- qbx_properties' keyholder list, which that script re-reads from the database every time.
--
-- A house, as the phone shows it:
--   { id, name, addr?, x?, y?, locked = true|false|nil, keys = { { id, name } }|nil, way = true|nil }
-- `locked` nil: no door control. `keys` nil: no key control. `way`: the client has to set the waypoint.
-- `online = true` on a script: it hands a key to a player, not to a character, so they have to be in the city.
--
-- For another script: add an entry to SCRIPTS with the functions it can back, and (if it needs the
-- player's game to do something) a branch in Bridge.home in config/bridge/client.lua.

Housing = {}

local ORDER = { 'nolag_properties', 'vms_housing', 'rtx_housing', 'bcs_housing', 'RxHousing', 'ps-housing', 'qbx_properties', 'qb-houses', 'esx_property' }
local SCRIPTS = {}
local kind

--- Which housing script is running, or 'none'. Worked out on first use, by which time every resource has started.
function Housing.kind()
    if kind then return kind end
    kind = Config.housing ~= 'auto' and Config.housing or 'none'
    if Config.housing == 'auto' then
        for _, res in ipairs(ORDER) do
            if GetResourceState(res) == 'started' then kind = res break end
        end
    end
    if not SCRIPTS[kind] then kind = 'none' end
    return kind
end

local function holders(ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = { id = id, name = Bridge.charName(id) } end
    return out
end

--- A property from a script that documents its exports but not the fields inside a property: the
--- name and the position are looked for under the names such data usually has.
local function loose(d, id)
    local at = d.coords or d.entrance or d.enter or d.position or {}
    return d.name or d.label or d.address or ('Property %s'):format(id), tonumber(at.x), tonumber(at.y)
end

-- nolag_properties -------------------------------------------------------------------------------
-- docs.teamsgg.dev/paid-scripts/properties (the calls its own phone integration makes).
SCRIPTS['nolag_properties'] = {
    list = function(_, identifier)
        local out = {}
        for _, p in pairs(exports.nolag_properties:GetAllProperties(identifier, 'user', true) or {}) do
            local ids = {}
            for holder in pairs(exports.nolag_properties:GetKeyHolders(p.id) or {}) do ids[#ids + 1] = holder end
            out[#out + 1] = { id = p.id, name = p.label, locked = p.doorLocked == true, keys = holders(ids), way = true }
        end
        return out
    end,
    lock = function(src, id, locked)
        return exports.nolag_properties:ToggleDoorlock(src, id, locked) and true or false
    end,
    key = 'client',
}

-- vms_housing --------------------------------------------------------------------------------------
-- Everything it offers a phone is on the client (docs.vames-store.com, vms_housing > compatibility >
-- phones), so the list is filled in there and key changes are its own events.
SCRIPTS['vms_housing'] = {
    list = function() return {} end,
    key = 'client',
    online = true,
    unchecked = true,   -- the list is not known here, so ownership is left to the script's own checks
}

-- rtx_housing --------------------------------------------------------------------------------------
-- rtx-dev.gitbook.io/rtxdev/rtx-housing-system/exports-events/server-exports. The exports are
-- documented; the fields inside a property are not (see `loose` above). A property this cannot
-- name is listed as "Property <id>".
SCRIPTS['rtx_housing'] = {
    list = function(src)
        local out = {}
        for key, p in pairs(exports['rtx_housing']:GetPlayerOwnedProperties(src) or {}) do
            local id = type(p) == 'table' and (p.id or p.propertyId or p.propertyid or p.property_id) or p
            id = tonumber(id) or tonumber(key)
            if id then
                local name, x, y = loose(type(p) == 'table' and p or Util.decode(exports['rtx_housing']:GetPropertyData(id)), id)
                out[#out + 1] = { id = id, name = name, x = x, y = y, locked = exports['rtx_housing']:GetPropertyLockStatus(id) == true }
            end
        end
        return out
    end,
    lock = function(_, id, locked)
        exports['rtx_housing']:SetPropertyLockStatus(id, locked)
        return true
    end,
}

-- ps-housing ---------------------------------------------------------------------------------------
-- github.com/Project-Sloth/ps-housing: the `properties` table. Who has access is also held in the
-- script's memory, so it is changed through the script's own events, from the owner's game.
SCRIPTS['ps-housing'] = {
    list = function(_, identifier)
        local out = {}
        for _, r in ipairs(MySQL.query.await('SELECT property_id, street, region, apartment, has_access, door_data FROM properties WHERE owner_citizenid = ?', { identifier })) do
            local door = Util.decode(r.door_data)
            out[#out + 1] = {
                id = r.property_id, name = r.apartment or r.street or ('Property %d'):format(r.property_id), addr = r.region,
                x = tonumber(door.x), y = tonumber(door.y), keys = holders(Util.decode(r.has_access)),
            }
        end
        return out
    end,
    key = 'client',
    online = true,
}

-- qbx_properties -----------------------------------------------------------------------------------
-- Its `properties` table. The script reads owner and keyholders from the database each time someone
-- tries the door, so the keyholder list can be changed there directly.
SCRIPTS['qbx_properties'] = {
    list = function(_, identifier)
        local out = {}
        for _, r in ipairs(MySQL.query.await('SELECT id, property_name, coords, keyholders FROM properties WHERE owner = ?', { identifier })) do
            local at = Util.decode(r.coords)
            out[#out + 1] = { id = r.id, name = r.property_name, x = tonumber(at.x), y = tonumber(at.y), keys = holders(Util.decode(r.keyholders)) }
        end
        return out
    end,
    key = function(src, id, give, who)
        local owner = Bridge.identifier(src)
        local raw = MySQL.scalar.await('SELECT keyholders FROM properties WHERE id = ? AND owner = ?', { id, owner })
        if not raw then return false end
        local list, kept, had = Util.decode(raw), {}, false
        for _, holder in ipairs(list) do
            if holder == who.id then had = true else kept[#kept + 1] = holder end
        end
        if give then
            if had or who.id == owner then return false end
            list[#list + 1] = who.id
        else
            list = kept
        end
        return MySQL.update.await('UPDATE properties SET keyholders = ? WHERE id = ? AND owner = ?', { json.encode(list), id, owner }) > 0
    end,
}

-- esx_property -------------------------------------------------------------------------------------
-- It keeps everything in memory and in properties.json, and takes orders through ESX callbacks that
-- check the caller is the owner. So: read the file for the list, and let the owner's game ask for the
-- lock and the keys. (The file is written a little behind the game, so a change can take a moment to show.)
SCRIPTS['esx_property'] = {
    list = function(_, identifier)
        local out = {}
        for i, p in ipairs(Util.decode(LoadResourceFile('esx_property', 'properties.json'))) do
            if p.Owner == identifier then
                local keys = {}
                for id, k in pairs(type(p.Keys) == 'table' and p.Keys or {}) do
                    keys[#keys + 1] = { id = type(k) == 'table' and k.identifier or id, name = type(k) == 'table' and k.name or tostring(id) }
                end
                local at = p.Entrance or {}
                out[#out + 1] = {
                    id = i, name = (p.setName and p.setName ~= '') and p.setName or p.Name,
                    x = tonumber(at.x), y = tonumber(at.y), locked = p.Locked == true, keys = keys,
                }
            end
        end
        return out
    end,
    lock = 'client',
    key = 'client',
    online = true,
}

-- qb-houses ----------------------------------------------------------------------------------------
-- github.com/qbcore-framework/qb-houses: `player_houses` joined to `houselocations`. The key holders
-- are also held in the script's memory, so they are changed through its own events, from the owner's
-- game. Its lock is not kept anywhere the server can read, so the door is left alone.
SCRIPTS['qb-houses'] = {
    list = function(_, identifier)
        local out = {}
        for _, r in ipairs(MySQL.query.await([[SELECT h.house, h.keyholders, l.label, l.coords FROM player_houses h
            LEFT JOIN houselocations l ON l.name = h.house WHERE h.citizenid = ?]], { identifier })) do
            local at, ids = Util.decode(r.coords).enter or {}, {}
            for _, holder in ipairs(Util.decode(r.keyholders)) do   -- the owner is in their own list
                if holder ~= identifier then ids[#ids + 1] = holder end
            end
            out[#out + 1] = { id = r.house, name = r.label or r.house, x = tonumber(at.x), y = tonumber(at.y), keys = holders(ids) }
        end
        return out
    end,
    key = 'client',
    online = true,
}

-- bcs_housing --------------------------------------------------------------------------------------
-- docs.baguscodestudio.com/paid_scripts/housing/exports/server, and "Home Object (Server Side)" for
-- the fields. A key there is a named set of permissions: the phone hands out the first one the house has.
SCRIPTS['bcs_housing'] = {
    list = function(_, identifier)
        local bcs, out = exports.bcs_housing, {}
        for _, h in pairs(bcs:GetOwnedHomes(identifier) or {}) do
            local keys = {}
            for holder, k in pairs(bcs:GetKeyHolders(h.identifier) or {}) do
                if holder ~= identifier then keys[#keys + 1] = { id = holder, name = type(k) == 'table' and k.name or Bridge.charName(holder) } end
            end
            local locked
            if h.type ~= 'mlo' then locked = bcs:isLocked(h.identifier) == true end
            out[#out + 1] = { id = h.identifier, name = h.name, x = h.entry and tonumber(h.entry.x), y = h.entry and tonumber(h.entry.y), locked = locked, keys = keys }
        end
        return out
    end,
    lock = function(_, id, locked)
        -- LockHome turns the lock the other way, so it is only called when the door is the wrong way.
        if (exports.bcs_housing:isLocked(id) == true) ~= locked then exports.bcs_housing:LockHome(id) end
        return true
    end,
    key = function(_, id, give, who)
        if not give then
            exports.bcs_housing:RemoveKeyHolder(id, who.id)
            return true
        end
        local name = next(exports.bcs_housing:GetKeyList(id) or {})
        if not who.src or not name then return false end   -- it gives keys to a player, not to a character
        exports.bcs_housing:AddKeyHolder(id, who.src, name)
        return true
    end,
}

-- RxHousing ----------------------------------------------------------------------------------------
-- docs.rxscripts.xyz/scripts/general/housing/exports. As with rtx_housing the exports are documented
-- and the fields inside a property are not (see `loose` above). It has no export for the door.
SCRIPTS['RxHousing'] = {
    list = function(_, identifier)
        local rx, out = exports['RxHousing'], {}
        for key, p in pairs(rx:GetOwnedProperties(identifier) or {}) do
            local id = type(p) == 'table' and (p.id or p.propertyId or p.property_id) or p
            id = tonumber(id) or tonumber(key)
            if id then
                local keys = {}
                for k, v in pairs(rx:GetPropertyKeyholders(id) or {}) do
                    local holder = type(v) == 'table' and (v.identifier or v.id) or type(v) == 'string' and v or type(k) == 'string' and k
                    if holder and holder ~= identifier then
                        keys[#keys + 1] = { id = holder, name = type(v) == 'table' and v.name or Bridge.charName(holder) }
                    end
                end
                local name, x, y = loose(type(p) == 'table' and p or Util.decode(rx:GetProperty(id)), id)
                out[#out + 1] = { id = id, name = name, x = x, y = y, keys = keys }
            end
        end
        return out
    end,
    key = function(_, id, give, who)
        if give then return exports['RxHousing']:AddKeyholder(id, who.id) == true end
        return exports['RxHousing']:RemoveKeyholder(id, who.id) == true
    end,
}

-- What the rest of the phone calls -----------------------------------------------------------------

--- Houses the player owns.
function Housing.list(src)
    local s = SCRIPTS[Housing.kind()]
    if not s then return {} end
    local ok, list = pcall(s.list, src, Bridge.identifier(src))
    if not ok then print(('^1[lwk_phone] the %s bridge could not list houses: %s^0'):format(kind, list)) end
    return ok and list or {}
end

--- Does `src` own house `id`? Every change is checked against the list first: the housing scripts'
--- own exports take any id.
local function owns(src, id)
    local s = SCRIPTS[Housing.kind()]
    if s.unchecked then return true end
    for _, h in ipairs(Housing.list(src)) do
        if tostring(h.id) == tostring(id) then return h end
    end
    return false
end

--- Lock or unlock. Returns true when done, a table when the player's game has to do it
--- (config/bridge/client.lua), false when it could not be done.
function Housing.setLocked(src, id, locked)
    local s = SCRIPTS[Housing.kind()]
    if not s or not s.lock or not owns(src, id) then return false end
    if s.lock == 'client' then return { action = 'lock', id = id } end
    local ok, done = pcall(s.lock, src, id, locked)
    return ok and done == true
end

--- Give or take back a key. `who` is { id = character identifier, src = their source if they are online }.
--- Returns as Housing.setLocked does.
function Housing.key(src, id, give, who)
    local s = SCRIPTS[Housing.kind()]
    if not s or not s.key or not who or not who.id or not owns(src, id) then return false end
    if give and s.online and not who.src then return false end
    if s.key == 'client' then return { action = 'key', id = id, give = give, identifier = who.id, target = who.src } end
    local ok, done = pcall(s.key, src, id, give, who)
    return ok and done == true
end
