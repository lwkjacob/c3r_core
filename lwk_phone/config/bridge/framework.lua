-- Framework bridge (server). Everything framework-specific lives here so the rest of the
-- resource only speaks: identifier, name, bank money, job, vehicles, admin.
-- Detected once: qbx_core > qb-core > es_extended > ox_core > ND_Core > standalone. Config.framework can force one.
--
-- ox_core differs from the other three in shape, and each difference is dealt with here:
--   a character is known by a number (charId), which this bridge hands out as text like the others;
--   money is in accounts (the character's default account is "the bank");
--   there are no jobs, only groups, and a character can be in several: their job is the group they have
--     made active, or failing that their group of type 'job';
--   grades start at 1, and the top grade (or the grade whose account role is 'owner') is the boss;
--   vehicles have a table of their own, and ox_core has to spawn one itself for it to stay tracked.
-- A player and an account there are plain data whose methods are called by name: the exports used below
-- are the ones ox_core's own Lua library is built on (ox_core/lib/server).
--
-- ND_Core (github.com/ND-Framework/ND_Core, ndcore.dev) sits between the two shapes:
--   a character is known by a number (`id`, the charid), handed out here as text;
--   cash and bank are two numbers on the character, moved with addMoney / deductMoney;
--   a character has groups, and exactly one of them is their job. There is no duty;
--   ranks are whatever weights the server gave the group, and a rank can be marked as the boss;
--   vehicles have a table of their own (`nd_vehicles`), and ND_Core spawns one itself (with its keys).
-- The ND_Core before 2.0 shares only the name with it: see "ND_Core 1.x" below.
--
-- Standalone has no characters, money, jobs or owned vehicles: the identifier is the
-- player's licence and the apps that need the rest are hidden (see Bridge.has).

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

--- The framework's own resource, and whether it is running. A framework that is not cannot be asked anything:
--- until it is, nobody has a character and the phone stays away (the start-up report says why).
for _, f in ipairs(FRAMEWORKS) do
    if f[1] == fw then Bridge.resource = f[2] end
end

function Bridge.running()
    return Bridge.resource == nil or GetResourceState(Bridge.resource) == 'started'
end

local QB, ESX
local function core()
    if fw == 'qb' and not QB then QB = exports['qb-core']:GetCoreObject() end
    if fw == 'esx' and not ESX then ESX = exports.es_extended:getSharedObject() end
end

-- ND_Core 1.x ----------------------------------------------------------------------------------------
-- Told apart by its version. It hands out one NDCore object (GetCoreObject) whose functions take the player
-- as an argument, and keeps characters in `characters`. A job there is a plain name (a department) with a
-- rank and nobody in charge: the top rank of a group listed in its config (config_client.lua, groups) is taken
-- as the boss. Nobody can be fired, because a character always has a department. It has no vehicles of its
-- own, so the Garage app is hidden. A 1.x character is handed on in the shape of a 2.x player, so the rest of
-- this file reads both the same way.
local nd1 = fw == 'nd' and (tonumber((GetResourceMetadata('ND_Core', 'version', 0) or ''):match('^%d+')) or 2) < 2
Bridge.nd1 = nd1

local ND1
local function nd1Core()
    ND1 = ND1 or exports.ND_Core:GetCoreObject()
    return ND1
end

--- A group's ranks as the 1.x config lists them (lowest first) and its name as spelt there. None: an empty list.
local function nd1Ranks(job)
    for name, ranks in pairs(nd1Core().Config.groups or {}) do
        if name:lower() == tostring(job):lower() then return ranks, name end
    end
    return {}, job
end

local function nd1Player(src)
    local nd = nd1Core()
    local c = nd.Functions.GetPlayer(tonumber(src))
    if not c then return nil end
    return {
        id = c.id, source = src, cash = c.cash, bank = c.bank,
        fullname = (('%s %s'):format(c.firstName or '', c.lastName or ''):gsub('^%s+', ''):gsub('%s+$', '')),
        -- 1.x returns nothing from either: it writes the database and re-reads the balance before coming back.
        addMoney = function(kind, amount, reason) nd.Functions.AddMoney(amount, src, kind, reason) return true end,
        deductMoney = function(kind, amount, reason) nd.Functions.DeductMoney(amount, src, kind, reason) return true end,
        getJob = function()
            if not c.job then return nil end
            local ranks, group = nd1Ranks(c.job)
            local held = type(c.data) == 'table' and type(c.data.groups) == 'table' and c.data.groups[group] or {}
            local rank = tonumber(held.rank) or 1
            return c.job, { label = c.job, rank = rank, rankName = ranks[rank], isBoss = #ranks > 0 and rank == #ranks }
        end,
        setJob = function(job, rank) nd.Functions.SetPlayerJob(c.id, job, rank) return true end,
        removeGroup = function() end,   -- see above: nobody is fired
    }
end

local function player(src)
    if not Bridge.running() then return nil end
    core()
    if fw == 'qbox' then return exports.qbx_core:GetPlayer(src) end
    if fw == 'qb' then return QB.Functions.GetPlayer(src) end
    if fw == 'esx' then return ESX.GetPlayerFromId(src) end
    if fw == 'ox' then
        local p = exports.ox_core:GetPlayer(src)
        return p and p.charId and p or nil   -- connected but still choosing a character: not a player yet
    end
    if nd1 then return nd1Player(src) end
    if fw == 'nd' then return exports.ND_Core:getPlayer(src) end   -- nil until a character is chosen
end

local ox = {}

--- Call a method of an ox_core player: ox.call(src, 'get', 'name').
function ox.call(src, ...) return exports.ox_core:CallPlayer(src, ...) end

--- The id of a character's default account. The character goes in as a number: text is read as a state id.
function ox.account(charId)
    local a = exports.ox_core:GetCharacterAccount(tonumber(charId))
    return a and a.accountId
end

function ox.balance(account)
    return account and tonumber(exports.ox_core:CallAccount(account, 'get', 'balance')) or 0
end

--- 'addBalance' or 'removeBalance'. ox_core refuses an overdraft itself and writes its own history.
function ox.move(account, method, amount, reason)
    local res = account and exports.ox_core:CallAccount(account, method, { amount = amount, message = reason })
    return type(res) == 'table' and res.success == true
end

--- A character's place in a group: the one asked for, else the one they have made active, else their
--- group of type 'job'. Nil when they have none.
function ox.job(src, want)
    local active = ox.call(src, 'get', 'activeGroup')
    local name = want or active
    local grade = name and ox.call(src, 'getGroup', name)
    if not grade and not want then
        local found = ox.call(src, 'getGroupByType', 'job')
        name, grade = found and found[1], found and found[2]
    end
    if not name or not grade then return nil end
    local g = GlobalState['group.' .. name] or {}
    local grades, roles = g.grades or {}, g.accountRoles or {}
    return {
        name = name, label = g.label or name, grade = grade, gradeLabel = grades[grade],
        isBoss = grade == #grades or (roles[grade] or roles[tostring(grade)]) == 'owner', duty = active == name,
    }
end

--- What this server can do. The UI hides apps whose feature is missing.
Bridge.has = {
    money    = fw ~= 'standalone',
    jobs     = fw ~= 'standalone',
    vehicles = fw ~= 'standalone' and not nd1,
}

--- True once the player has a character (always true on standalone).
function Bridge.ready(src)
    if fw == 'standalone' then return GetPlayerName(src) ~= nil end
    return player(src) ~= nil
end

function Bridge.identifier(src)
    if fw == 'standalone' then
        return GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifierByType(src, 'fivem')
    end
    local p = player(src)
    if not p then return nil end
    if fw == 'esx' then return p.getIdentifier() end
    if fw == 'ox' then return tostring(p.charId) end
    if fw == 'nd' then return tostring(p.id) end
    return p.PlayerData.citizenid
end

function Bridge.name(src)
    local p = player(src)
    if not p then return GetPlayerName(src) or 'Unknown' end
    if fw == 'esx' then return p.getName() end
    if fw == 'ox' then return ox.call(src, 'get', 'name') or GetPlayerName(src) or 'Unknown' end
    if fw == 'nd' then return p.fullname or GetPlayerName(src) or 'Unknown' end
    local c = p.PlayerData.charinfo or {}
    return (('%s %s'):format(c.firstname or '', c.lastname or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

--- A character's name from their identifier, whether or not they are online.
function Bridge.charName(identifier)
    local src = Bridge.sourceOf(identifier)
    if src then return Bridge.name(src) end
    local ok, name
    if fw == 'esx' then
        ok, name = pcall(MySQL.scalar.await, "SELECT CONCAT(firstname, ' ', lastname) FROM users WHERE identifier = ?", { identifier })
    elseif fw == 'qb' or fw == 'qbox' then
        ok, name = pcall(MySQL.scalar.await,
            "SELECT CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) FROM players WHERE citizenid = ?",
            { identifier })
    elseif fw == 'ox' then
        ok, name = pcall(MySQL.scalar.await, 'SELECT fullName FROM characters WHERE charId = ?', { tonumber(identifier) })
    elseif nd1 then
        ok, name = pcall(MySQL.scalar.await, "SELECT CONCAT(first_name, ' ', last_name) FROM characters WHERE character_id = ?", { tonumber(identifier) })
    elseif fw == 'nd' then
        ok, name = pcall(MySQL.scalar.await, "SELECT CONCAT(firstname, ' ', lastname) FROM nd_characters WHERE charid = ?", { tonumber(identifier) })
    end
    return ok and name or tostring(identifier)
end

-- Money: the phone only ever touches the bank account ------------------------------------

function Bridge.getBank(src)
    local p = player(src)
    if not p then return 0 end
    if fw == 'esx' then
        local acc = p.getAccount('bank')
        return acc and acc.money or 0
    end
    if fw == 'ox' then return ox.balance(ox.account(p.charId)) end
    if fw == 'nd' then return tonumber(p.bank) or 0 end
    return p.Functions.GetMoney('bank') or 0
end

function Bridge.getCash(src)
    local p = player(src)
    if not p then return 0 end
    if fw == 'esx' then
        local acc = p.getAccount('money')
        return acc and acc.money or 0
    end
    if fw == 'ox' then   -- cash there is an item
        return GetResourceState('ox_inventory') == 'started' and exports.ox_inventory:GetItemCount(src, 'money') or 0
    end
    if fw == 'nd' then return tonumber(p.cash) or 0 end
    return p.Functions.GetMoney('cash') or 0
end

function Bridge.addBank(src, amount, reason)
    local p = player(src)
    if not p or amount <= 0 then return false end
    if fw == 'esx' then
        p.addAccountMoney('bank', amount, reason)
        return true
    end
    if fw == 'ox' then return ox.move(ox.account(p.charId), 'addBalance', amount, reason) end
    if fw == 'nd' then return p.addMoney('bank', amount, reason) == true end
    return p.Functions.AddMoney('bank', amount, reason) ~= false
end

-- Checks the balance itself: never trust a framework to refuse an overdraft.
function Bridge.removeBank(src, amount, reason)
    local p = player(src)
    if not p or amount <= 0 or Bridge.getBank(src) < amount then return false end
    if fw == 'esx' then
        p.removeAccountMoney('bank', amount, reason)
        return true
    end
    if fw == 'ox' then return ox.move(ox.account(p.charId), 'removeBalance', amount, reason) end
    if fw == 'nd' then return p.deductMoney('bank', amount, reason) == true end   -- it does not check the balance: the line above did
    return p.Functions.RemoveMoney('bank', amount, reason) == true
end

--- Bank money for a player who is not online: edit the stored JSON directly.
function Bridge.addBankOffline(identifier, amount)
    if amount <= 0 then return false end
    if fw == 'qb' or fw == 'qbox' then
        return MySQL.update.await(
            "UPDATE players SET money = JSON_SET(money, '$.bank', CAST(JSON_EXTRACT(money, '$.bank') AS SIGNED) + ?) WHERE citizenid = ?",
            { amount, identifier }) > 0
    end
    if fw == 'esx' then
        return MySQL.update.await(
            "UPDATE users SET accounts = JSON_SET(accounts, '$.bank', CAST(JSON_EXTRACT(accounts, '$.bank') AS SIGNED) + ?) WHERE identifier = ?",
            { amount, identifier }) > 0
    end
    if fw == 'ox' then return ox.move(ox.account(identifier), 'addBalance', amount) end   -- an account is there whether or not its owner is
    if nd1 then
        return MySQL.update.await('UPDATE characters SET bank = bank + ? WHERE character_id = ?', { amount, tonumber(identifier) }) > 0
    end
    if fw == 'nd' then
        return MySQL.update.await('UPDATE nd_characters SET bank = bank + ? WHERE charid = ?', { amount, tonumber(identifier) }) > 0
    end
    return false
end

-- Jobs -----------------------------------------------------------------------------------------

--- { name, label, grade, gradeLabel, isBoss, duty } or nil. `duty` is nil where the framework has no duty.
--- `as` only matters where a character can have more than one job (ox_core): their place in that one.
function Bridge.getJob(src, as)
    local p = player(src)
    if not p then return nil end
    if fw == 'ox' then return ox.job(src, as) end
    if fw == 'nd' then   -- the one of their groups that is marked as the job
        local name, g = p.getJob()
        if not name or type(g) ~= 'table' then return nil end
        return {
            name = name, label = g.label or name, grade = tonumber(g.rank) or 1, gradeLabel = g.rankName and tostring(g.rankName) or nil,
            isBoss = g.isBoss == true or g.isBoss == 1,
        }
    end
    if fw == 'esx' then
        local j = p.getJob()
        return { name = j.name, label = j.label, grade = j.grade, gradeLabel = j.grade_label, isBoss = j.grade_name == 'boss' }
    end
    local j = p.PlayerData.job
    return {
        name = j.name, label = j.label, grade = j.grade and j.grade.level or 0, gradeLabel = j.grade and j.grade.name,
        isBoss = j.isboss == true, duty = j.onduty == true,
    }
end

--- Sources of every player working `job` right now (on duty, where duty exists).
function Bridge.onDuty(job)
    core()
    local out = {}
    if fw == 'ox' then return exports.ox_core:GetGroupActivePlayers(job) or out end
    if fw == 'nd' then   -- no duty there: everyone in the city with the job
        local with
        if nd1 then with = nd1Core().Functions.GetPlayers('job', job) else with = exports.ND_Core:getPlayers('job', job, true) end
        for _, p in pairs(with or {}) do out[#out + 1] = tonumber(p.source) end
        return out
    end
    if fw == 'esx' then
        for _, p in pairs(ESX.GetExtendedPlayers('job', job)) do out[#out + 1] = p.source end
    elseif fw == 'qb' or fw == 'qbox' then
        local players = fw == 'qb' and QB.Functions.GetQBPlayers() or exports.qbx_core:GetQBPlayers()
        for _, p in pairs(players) do
            local j = p.PlayerData.job
            if j.name == job and j.onduty then out[#out + 1] = p.PlayerData.source end
        end
    end
    return out
end

function Bridge.toggleDuty(src)
    if fw == 'ox' then   -- on duty there is having the group active
        local j = ox.job(src)
        if not j then return false end
        if j.duty then return ox.call(src, 'setActiveGroup') == true end
        return ox.call(src, 'setActiveGroup', j.name) == true
    end
    if fw ~= 'qb' and fw ~= 'qbox' then return false end
    local p = player(src)
    if not p then return false end
    p.Functions.SetJobDuty(not p.PlayerData.job.onduty)
    return true
end

--- Give an online player a job and grade (hiring, firing, promoting). Returns success.
--- `from` is the job they are leaving when `job` is Bridge.unemployed: needed where a character can have several.
function Bridge.setJob(src, job, grade, from)
    local p = player(src)
    if not p then return false end
    if fw == 'ox' then
        if job == Bridge.unemployed then return from ~= nil and ox.call(src, 'setGroup', from, 0) == true end
        return ox.call(src, 'setGroup', job, math.max(grade or 1, 1)) == true   -- 0 there means out of the group
    end
    if fw == 'nd' then
        if job == Bridge.unemployed then return from ~= nil and p.removeGroup(from) ~= nil end
        -- Hiring asks for grade 0, the bottom: there that is the group's lowest rank, whatever number the server gave it.
        local lowest = Bridge.grades(job)[1]
        return p.setJob(job, grade and grade > 0 and grade or lowest and lowest.level or 1) ~= nil
    end
    if fw == 'esx' then
        p.setJob(job, grade)
        return true
    end
    return p.Functions.SetJob(job, grade) ~= false
end

--- A job's grades, lowest first: { { level, name } }.
function Bridge.grades(job)
    core()
    local out = {}
    if fw == 'ox' then
        for level, name in ipairs((GlobalState['group.' .. job] or {}).grades or {}) do out[level] = { level = level, name = name } end
        return out
    end
    if nd1 then
        for level, name in ipairs((nd1Ranks(job))) do out[level] = { level = level, name = name } end
        return out
    end
    if fw == 'nd' then
        for level, rank in pairs((exports.ND_Core:getGroupData(job) or {}).ranksData or {}) do out[#out + 1] = { level = tonumber(level) or 0, name = rank.label } end
    end
    if fw == 'esx' then
        local ok, rows = pcall(MySQL.query.await, 'SELECT grade, label FROM job_grades WHERE job_name = ?', { job })
        for _, r in ipairs(ok and rows or {}) do out[#out + 1] = { level = tonumber(r.grade) or 0, name = r.label } end
    elseif fw == 'qb' or fw == 'qbox' then
        local def
        if fw == 'qbox' then def = exports.qbx_core:GetJob(job) else def = QB.Shared.Jobs[job] end
        -- QBCore keys its grades '0', '1', ...; Qbox uses numbers.
        for level, g in pairs(def and def.grades or {}) do out[#out + 1] = { level = tonumber(level) or 0, name = g.name } end
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

--- Name of the "no job" job, for firing someone.
Bridge.unemployed = 'unemployed'

--- Everyone with `job`, online or not: { { id, name, grade, gradeLabel } }.
function Bridge.employees(job)
    local ok, rows
    if fw == 'esx' then
        ok, rows = pcall(MySQL.query.await, [[
            SELECT u.identifier AS id, CONCAT(u.firstname, ' ', u.lastname) AS name, u.job_grade AS grade, g.label AS gradeLabel
            FROM users u LEFT JOIN job_grades g ON g.job_name = u.job AND g.grade = u.job_grade WHERE u.job = ?]], { job })
    elseif fw == 'qb' or fw == 'qbox' then
        ok, rows = pcall(MySQL.query.await, [[
            SELECT citizenid AS id,
                   CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) AS name,
                   JSON_EXTRACT(job, '$.grade.level') AS grade, JSON_UNQUOTE(JSON_EXTRACT(job, '$.grade.name')) AS gradeLabel
            FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?]], { job })
    elseif fw == 'ox' then
        ok, rows = pcall(MySQL.query.await, [[
            SELECT CAST(c.charId AS CHAR) AS id, c.fullName AS name, g.grade AS grade, gg.label AS gradeLabel
            FROM character_groups g JOIN characters c ON c.charId = g.charId
            LEFT JOIN ox_group_grades gg ON gg.`group` = g.name AND gg.grade = g.grade
            WHERE g.name = ? AND c.deleted IS NULL]], { job })
    elseif nd1 then
        -- The job is a column of its own; the rank is in `data`, under the group of that name.
        local ranks, group = nd1Ranks(job)
        if tostring(group):match('^[%w_%- ]+$') then
            local path = '$.groups."' .. group .. '"'
            ok, rows = pcall(MySQL.query.await, [[
                SELECT CAST(character_id AS CHAR) AS id, CONCAT(first_name, ' ', last_name) AS name,
                       COALESCE(JSON_EXTRACT(`data`, CONCAT(?, '.rank')), 1) AS grade
                FROM characters WHERE job = ?]], { path, job })
            for _, r in ipairs(ok and rows or {}) do r.gradeLabel = ranks[tonumber(r.grade) or 1] end
        end
    elseif fw == 'nd' and job:match('^[%w_%-]+$') then
        -- A character's groups are one JSON object keyed by group name; the job is the one with `isJob`.
        local path = '$."' .. job .. '"'
        ok, rows = pcall(MySQL.query.await, [[
            SELECT CAST(charid AS CHAR) AS id, CONCAT(firstname, ' ', lastname) AS name,
                   JSON_EXTRACT(`groups`, CONCAT(?, '.rank')) AS grade,
                   JSON_UNQUOTE(JSON_EXTRACT(`groups`, CONCAT(?, '.rankName'))) AS gradeLabel
            FROM nd_characters
            WHERE JSON_UNQUOTE(JSON_EXTRACT(`groups`, CONCAT(?, '.isJob'))) = 'true' AND deleted_at IS NULL]], { path, path, path })
    end
    return ok and rows or {}
end

--- Source of an online character by identifier, or nil.
function Bridge.sourceOf(identifier)
    core()
    if fw == 'qbox' then
        local p = exports.qbx_core:GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source
    elseif fw == 'qb' then
        local p = QB.Functions.GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromIdentifier(identifier)
        return p and p.source
    elseif fw == 'ox' then
        local p = tonumber(identifier) and exports.ox_core:GetPlayerFromCharId(tonumber(identifier))
        return p and tonumber(p.source)
    elseif nd1 then
        local p = tonumber(identifier) and nd1Core().Functions.GetPlayerByCharacterId(tonumber(identifier))
        return p and tonumber(p.source)
    elseif fw == 'nd' then
        local p = tonumber(identifier) and (exports.ND_Core:getPlayers('id', tonumber(identifier), true) or {})[1]
        return p and tonumber(p.source)
    end
    for _, src in ipairs(GetPlayers()) do
        if Bridge.identifier(tonumber(src)) == identifier then return tonumber(src) end
    end
end

-- Vehicles ---------------------------------------------------------------------------------------
-- Rows come back as { plate, model, garage, state = 'out' | 'garaged' | 'impound', held, fuel, engine, body, props }.
-- `model` is a spawn name or hash; the client turns it into a display name. `props` is the saved
-- tuning, handed back to the client when the valet spawns the vehicle.
--
-- Garage scripts all keep vehicles in the framework's table (player_vehicles / owned_vehicles) and
-- differ in which columns say where a vehicle is. Rather than naming scripts, this reads whichever
-- of those columns the table has:
--   in_garage, garage_id, impound     jg-advancedgarages, cd_garage
--   state, garage                     qb-garages, qbx_garages (0 out, 1 garaged, 2 impound)
--   stored, parking, pound            esx_garage and most ESX garages
--   stored, garage                    esx_advancedgarage
--   stored                            lunar_garage (on QBCore it adds `stored` and leaves `state` alone)
--   parking                           okokGarage (next to state / stored)
--   garage, garageSpotID, impound_*   vms_garagesv2 (`garage` is empty while the vehicle is out)
-- A garage script with other columns: edit `where` and Bridge.vehicleOut below.

local TABLE = fw == 'esx' and 'owned_vehicles' or 'player_vehicles'
local OWNER = fw == 'esx' and 'owner' or 'citizenid'
local cols

--- The vehicle table's columns, as a set. Read once.
local function columns()
    if cols then return cols end
    local found = {}
    local ok, rows = pcall(MySQL.query.await, ('SHOW COLUMNS FROM %s'):format(TABLE))
    for _, r in ipairs(ok and rows or {}) do found[r.Field] = true end
    if next(found) then cols = found end
    return found
end

local function yes(v) return v == true or v == 1 end

--- Where a vehicle is: state, garage name, and whether it is held in an impound it may not leave.
local function where(r, c)
    -- vms_garagesv2, as its own phone integrations read it. An impound there is a fine paid at the counter.
    if c.garageSpotID then
        local name = r.garage
        if name and GetResourceState('vms_garagesv2') == 'started' then
            local ok, label = pcall(function() return (exports['vms_garagesv2']:getGarageInfo(name)) end)
            if ok and type(label) == 'string' then name = label end
        end
        if r.impound_date and r.impound_data then return 'impound', name or '', true end
        return r.garage and 'garaged' or 'out', name or ''
    end
    local garage = r.garage_id or r.parking or r.garage or ''
    if c.garage_id and GetResourceState('cd_garage') == 'started' then
        local ok, label = pcall(function() return exports.cd_garage:GetGarageLabelFromGarageId(r.garage_id) end)
        if ok and type(label) == 'string' then garage = label end
    end
    if c.impound and (tonumber(r.impound) or 0) > 0 then
        return 'impound', garage, c.impound_retrievable and not yes(tonumber(r.impound_retrievable))
    end
    if c.in_garage then return yes(tonumber(r.in_garage) or r.in_garage) and 'garaged' or 'out', garage end
    local lunar = c.stored and GetResourceState('lunar_garage') == 'started'
    if c.state and not lunar then return r.state == 0 and 'out' or r.state == 2 and 'impound' or 'garaged', garage end
    if c.pound and r.pound and r.pound ~= '' then return 'impound', r.pound end
    if c.stored then
        local stored = tonumber(r.stored) or (r.stored and 1 or 0)
        return stored == 0 and 'out' or stored == 2 and 'impound' or 'garaged', garage
    end
    return 'garaged', garage
end

function Bridge.vehicles(src)
    local out = {}
    if not Bridge.has.vehicles then return out end
    if fw == 'nd' then
        -- Its own table. An impounded vehicle stays at the impound: releasing it is the impound script's business.
        local ok, rows = pcall(MySQL.query.await, 'SELECT id, plate, properties, `stored`, impounded FROM nd_vehicles WHERE owner = ?', { tonumber(Bridge.identifier(src)) })
        for _, r in ipairs(ok and rows or {}) do
            local props = Util.decode(r.properties)
            local impounded = yes(tonumber(r.impounded) or r.impounded)
            out[#out + 1] = {
                id = r.id, plate = r.plate, model = props.model, garage = '',
                state = impounded and 'impound' or yes(tonumber(r.stored) or r.stored) and 'garaged' or 'out', held = impounded or nil,
                fuel = math.floor(tonumber(props.fuelLevel) or 100),
                engine = math.floor((tonumber(props.engineHealth) or 1000) / 10),
                body = math.floor((tonumber(props.bodyHealth) or 1000) / 10),
                props = props,
            }
        end
        return out
    end
    if fw == 'ox' then
        -- Its own table: `stored` is the garage, 'impound', or empty while the vehicle is out in the world.
        local ok, rows = pcall(MySQL.query.await, 'SELECT id, plate, model, data, `stored` FROM vehicles WHERE owner = ?', { tonumber(Bridge.identifier(src)) })
        for _, r in ipairs(ok and rows or {}) do
            local props = Util.decode(r.data).properties or {}
            out[#out + 1] = {
                id = r.id, plate = r.plate, model = r.model, garage = r.stored or '',
                state = r.stored == nil and 'out' or r.stored == 'impound' and 'impound' or 'garaged',
                fuel = math.floor(tonumber(props.fuelLevel) or 100),
                engine = math.floor((tonumber(props.engineHealth) or 1000) / 10),
                body = math.floor((tonumber(props.bodyHealth) or 1000) / 10),
                props = props,
            }
        end
        return out
    end
    local c = columns()
    local ok, rows = pcall(MySQL.query.await, ('SELECT * FROM %s WHERE %s = ?'):format(TABLE, OWNER), { Bridge.identifier(src) })
    for _, r in ipairs(ok and rows or {}) do
        -- QBCore keeps the spawn name in `vehicle` and the tuning in `mods`; ESX keeps the tuning, model included, in `vehicle`.
        local props = Util.decode(fw == 'esx' and r.vehicle or r.mods)
        local state, garage, held = where(r, c)
        out[#out + 1] = {
            plate = r.plate, model = fw == 'esx' and props.model or r.vehicle or tonumber(r.hash), garage = garage, state = state, held = held or nil,
            fuel = math.floor(tonumber(r.fuel) or props.fuelLevel or 100),
            engine = math.floor((tonumber(r.engine) or props.engineHealth or 1000) / 10),
            body = math.floor((tonumber(r.body) or props.bodyHealth or 1000) / 10),
            props = props,
        }
    end
    return out
end

-- The columns that say where a vehicle is, and what each holds while the vehicle is out.
local OUT = { { 'in_garage', '0' }, { 'impound', '0' }, { 'state', '0' }, { 'stored', '0' }, { 'pound', 'NULL' } }
local OUT_VMS = { { 'garage', 'NULL' }, { 'garageSpotID', 'NULL' } }

local function outs(c) return c.garageSpotID and OUT_VMS or OUT end

--- Mark a vehicle as out of its garage / released from impound. Returns what those columns held
--- before (for Bridge.vehicleBack), or false when nothing was changed.
function Bridge.vehicleOut(src, plate)
    if not Bridge.has.vehicles then return false end
    if fw == 'ox' then
        -- Nothing is marked here: ox_core empties `stored` itself when it spawns the vehicle (Bridge.spawnVehicle).
        local id = MySQL.scalar.await('SELECT id FROM vehicles WHERE plate = ? AND owner = ? AND `stored` IS NOT NULL', { plate, tonumber(Bridge.identifier(src)) })
        return id and { id = id } or false
    end
    if fw == 'nd' then
        -- Nor here: ND_Core marks the vehicle as out itself when it spawns it (Bridge.spawnVehicle).
        local id = MySQL.scalar.await('SELECT id FROM nd_vehicles WHERE plate = ? AND owner = ? AND `stored` = 1 AND impounded = 0', { plate, tonumber(Bridge.identifier(src)) })
        return id and { id = id, src = src } or false
    end
    local c, names, sets = columns(), {}, {}
    for _, o in ipairs(outs(c)) do
        if c[o[1]] then
            names[#names + 1] = o[1]
            sets[#sets + 1] = o[1] .. ' = ' .. o[2]
        end
    end
    if #sets == 0 then return false end
    local owner = Bridge.identifier(src)
    local before = MySQL.single.await(('SELECT %s FROM %s WHERE plate = ? AND %s = ?'):format(table.concat(names, ', '), TABLE, OWNER), { plate, owner })
    if not before then return false end
    local changed = MySQL.update.await(('UPDATE %s SET %s WHERE plate = ? AND %s = ?'):format(TABLE, table.concat(sets, ', '), OWNER), { plate, owner })
    -- vms_garagesv2 frees the parking space when told a phone took the vehicle.
    if changed > 0 and c.garageSpotID and before.garage then TriggerEvent('vms_garagesv2:vehicleTakenByPhone', before.garage, before.garageSpotID) end
    return changed > 0 and before
end

--- Undo Bridge.vehicleOut: put the vehicle back where it was. `before` is what vehicleOut returned.
function Bridge.vehicleBack(src, plate, before)
    if fw == 'ox' or fw == 'nd' then return true end   -- nothing was changed (see Bridge.vehicleOut)
    local c, sets, params = columns(), {}, {}
    for _, o in ipairs(outs(c)) do
        local name, v = o[1], before[o[1]]
        if c[name] and v == nil then
            sets[#sets + 1] = name .. ' = NULL'
        elseif c[name] then
            sets[#sets + 1] = name .. ' = ?'
            params[#params + 1] = v == true and 1 or v == false and 0 or v
        end
    end
    params[#params + 1], params[#params + 2] = plate, Bridge.identifier(src)
    return MySQL.update.await(('UPDATE %s SET %s WHERE plate = ? AND %s = ?'):format(TABLE, table.concat(sets, ', '), OWNER), params) > 0
end

-- Garage scripts this phone can name in the start-up report. Naming one changes nothing: what
-- matters is the columns (see above), and those are read whatever the script is called.
local GARAGES = { 'jg-advancedgarages', 'cd_garage', 'vms_garagesv2', 'okokGarage', 'lunar_garage', 'qbx_garages', 'qb-garages', 'esx_advancedgarage', 'esx_garage' }

--- Bring a vehicle into the world at `coords`. Only defined where the framework has to do this itself for
--- the vehicle to stay that character's (ox_core, ND_Core): elsewhere it is nil and the player's game spawns it.
--- `before` is what Bridge.vehicleOut returned.
if fw == 'ox' then
    function Bridge.spawnVehicle(before, coords, heading)
        local ok, v = pcall(function() return exports.ox_core:SpawnVehicle(before.id, coords, heading) end)
        return ok and v ~= nil
    end
elseif fw == 'nd' and not nd1 then
    function Bridge.spawnVehicle(before, coords, heading)
        local ok, v = pcall(function() return exports.ND_Core:spawnOwnedVehicle(before.src, before.id, coords, heading) end)
        if ok and v ~= nil then return true end
        -- It marks the vehicle as out before it tries to create it: nothing arrived, so it is still in the garage.
        MySQL.update.await('UPDATE nd_vehicles SET `stored` = 1 WHERE id = ?', { before.id })
        return false
    end
end

--- What the Garage app is working with, for the start-up report: { script = name or nil, table, columns = { names } }.
function Bridge.garage()
    if fw == 'ox' then return { script = 'ox_core', table = 'vehicles', columns = { 'stored' } } end
    if fw == 'nd' then return { script = 'ND_Core', table = 'nd_vehicles', columns = { 'stored', 'impounded' } } end
    local script
    for _, res in ipairs(GARAGES) do
        if GetResourceState(res) == 'started' then script = res break end
    end
    local c, found = columns(), {}
    for _, o in ipairs(outs(c)) do
        if c[o[1]] then found[#found + 1] = o[1] end
    end
    return { script = script, table = TABLE, columns = found }
end

function Bridge.isAdmin(src)
    return IsPlayerAceAllowed(src, Config.adminAce)
end
