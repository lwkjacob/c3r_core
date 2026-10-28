-- Inventory bridge (server): the phone as an item.
--
-- Unique phones need an inventory that stores data on each item. The phone's number is written
-- onto the item, every bit of phone data is keyed by that number, and so whoever holds the item
-- holds the phone.
--
--   inventory           unique phones   written from
--   ox_inventory        yes             its own documentation
--   qb-inventory        yes             its source
--   ps-inventory        yes             its source
--   codem-inventory     yes             its documentation (mInventory Remake)
--   jaksam_inventory    yes             its documentation
--   core_inventory      yes             its documentation; the names of an item's fields from other bridges
--   tgiann-inventory    yes             other open-source bridges (its documentation could not be read)
--   ESX's own           no              es_extended: its items carry no data, so the phone belongs to the character
--
-- ox_inventory item (data/items.lua):
--   ['phone'] = { label = 'Phone', weight = 190, stack = false, consume = 0, client = { export = 'lwk_phone.usePhone' } },
-- QBCore-style item lists (qb-core/shared/items.lua, or the inventory's own list): unique = true, useable = true, shouldClose = true.
-- ESX's own inventory: a row named `phone` in the `items` table. Without that row no item is asked for.
--
-- For another inventory: add an entry to ADAPTERS. `phones` lists the phone items a player carries,
-- `stamp` writes data onto the one in a slot (leave it out when items cannot carry data).

Inv = {}

local function started(res) return GetResourceState(res) == 'started' or GetResourceState(res) == 'starting' end

local cfg = Config.item
local ADAPTERS = {}

--- An item as the phone needs it. Inventories call the slot `slot` or `id`, and the data `metadata` or `info`.
local function item(s)
    local data = s.metadata or s.info
    return { slot = s.slot or s.id, number = type(data) == 'table' and data.number or nil }
end

local function listed(items)
    local out = {}
    for _, s in pairs(items or {}) do out[#out + 1] = item(s) end
    return out
end

ADAPTERS.ox = {
    phones = function(src) return listed(exports.ox_inventory:Search(src, 'slots', cfg.name)) end,
    stamp = function(src, slot, meta)
        exports.ox_inventory:SetMetadata(src, slot, meta)
        return true
    end,
}

ADAPTERS.qb = {
    phones = function(src) return listed(exports['qb-inventory']:GetItemsByName(src, cfg.name)) end,
    stamp = function(src, slot, meta) return exports['qb-inventory']:SetItemData(src, cfg.name, 'info', meta, slot) == true end,
}

-- Its SetItemData takes no slot (it changes the first item of that name), so the item in the slot is
-- changed the way that function does it: on the player, then handed back to QBCore.
ADAPTERS.ps = {
    phones = function(src) return listed(exports['ps-inventory']:GetItemsByName(src, cfg.name)) end,
    stamp = function(src, slot, meta)
        local p = exports['qb-core']:GetCoreObject().Functions.GetPlayer(src)
        local items = p and p.PlayerData.items
        if not items or not items[slot] then return false end
        items[slot].info = meta
        p.Functions.SetPlayerData('items', items)
        return true
    end,
}

ADAPTERS.codem = {
    phones = function(src) return listed(exports['codem-inventory']:GetItemsByName(src, cfg.name)) end,
    stamp = function(src, slot, meta)
        exports['codem-inventory']:SetItemMetadata(src, slot, meta)
        return true
    end,
}

ADAPTERS.jaksam = {
    phones = function(src) return listed(exports['jaksam_inventory']:getItemsByName(src, cfg.name)) end,
    stamp = function(src, slot, meta) return exports['jaksam_inventory']:setItemMetadataInSlot(src, slot, meta) == true end,
}

ADAPTERS.core = {
    phones = function(src) return listed(exports.core_inventory:getItems(src, cfg.name)) end,
    stamp = function(src, slot, meta)
        exports.core_inventory:setMetadata(src, slot, meta)
        return true
    end,
}

ADAPTERS.tgiann = {
    phones = function(src)
        local out = {}
        for _, s in pairs(exports['tgiann-inventory']:GetPlayerItems(src) or {}) do
            if type(s) == 'table' and s.name == cfg.name then out[#out + 1] = item(s) end
        end
        return out
    end,
    stamp = function(src, slot, meta)
        exports['tgiann-inventory']:UpdateItemMetadata(src, cfg.name, slot, meta)
        return true
    end,
}

-- ESX's own inventory: a count per item and nothing else.
ADAPTERS.esx = {
    phones = function(src)
        local p = exports.es_extended:getSharedObject().GetPlayerFromId(src)
        local held = p and p.getInventoryItem(cfg.name)
        return held and held.count > 0 and { { slot = 1 } } or {}
    end,
}

-- Looked for in this order. ESX's own comes last: every inventory above replaces it.
local ORDER = {
    { 'ox', 'ox_inventory' }, { 'jaksam', 'jaksam_inventory' }, { 'tgiann', 'tgiann-inventory' }, { 'codem', 'codem-inventory' },
    { 'core', 'core_inventory' }, { 'ps', 'ps-inventory' }, { 'qb', 'qb-inventory' },
}

local kind = cfg.inventory ~= 'auto' and cfg.inventory or nil
for _, o in ipairs(ORDER) do
    if not kind and started(o[2]) then kind = o[1] end
end
kind = kind or (Bridge.framework == 'esx' and 'esx') or 'none'
if Bridge.framework == 'standalone' or not ADAPTERS[kind] then kind = 'none' end
Inv.kind = kind

local adapter = ADAPTERS[kind]

local function auto(v) if v == 'auto' then return kind ~= 'none' end return v == true and kind ~= 'none' end
Inv.required = auto(cfg.require)
Inv.unique = Inv.required and auto(cfg.unique) and adapter.stamp ~= nil

-- ESX's own inventory only knows the items in its `items` table. A server that never added a phone
-- there keeps working as before: no item is asked for.
if kind == 'esx' and cfg.require == 'auto' then
    Inv.required = false
    CreateThread(function()
        local ok, found = pcall(MySQL.scalar.await, 'SELECT 1 FROM items WHERE name = ?', { cfg.name })
        Inv.required = ok and found ~= nil
    end)
end

--- Every phone item `src` carries: { { slot = n, number = '555-0142' or nil } }.
function Inv.phones(src)
    if not adapter then return {} end
    local ok, out = pcall(adapter.phones, src)
    if not ok then
        print(('^1[lwk_phone] the %s inventory bridge could not list items: %s^0'):format(kind, out))
        return {}
    end
    -- Lowest slot first. Slots are numbers nearly everywhere; where they are not, their order is still a steady one.
    table.sort(out, function(a, b)
        if type(a.slot) == 'number' and type(b.slot) == 'number' then return a.slot < b.slot end
        return tostring(a.slot) < tostring(b.slot)
    end)
    return out
end

--- Write a number (and a readable label) onto a blank phone item. Returns success.
function Inv.stamp(src, slot, number, owner)
    if not adapter or not adapter.stamp then return false end
    local ok, done = pcall(adapter.stamp, src, slot, { number = number, description = ('%s - %s'):format(number, owner or '') })
    return ok and done == true
end

--- Calls fn(src, slot) when a player uses the phone item. ox_inventory instead calls the
--- client export named in the item definition (client.export = 'lwk_phone.usePhone').
--- Every other inventory runs the framework's usable items, so that is where the phone is registered.
function Inv.onUse(fn)
    if kind == 'none' or kind == 'ox' then return end
    -- QBCore hands over the item. ESX hands over the item's name, and after it whatever the inventory adds.
    local function used(src, a, b)
        local it = type(a) == 'table' and a or type(b) == 'table' and b or nil
        fn(src, it and (it.slot or it.id))
    end
    if Bridge.framework == 'esx' then
        exports.es_extended:getSharedObject().RegisterUsableItem(cfg.name, used)
    elseif Bridge.framework == 'qbox' then
        exports.qbx_core:CreateUseableItem(cfg.name, used)
    elseif started('qb-core') then
        exports['qb-core']:GetCoreObject().Functions.CreateUseableItem(cfg.name, used)
    end
end
