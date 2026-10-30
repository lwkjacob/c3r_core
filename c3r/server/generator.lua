--[[
    c3r — the hidden truth generator. One secret per driver decides everything else, so every system
    tells the same story: the plate return, the name return, what they carry, what they say.

    truth = {
      secret    = 'clean' | 'nervous' | 'unlicensed' | 'suspended' | 'expired' | 'drunk' | 'drugs' | 'warrant' | 'stolen',
      demeanor  = 'polite' | 'nervous' | 'rude' | 'chatty',
      id        = 'hands' | 'forgot' | 'alias'   (what happens when asked for their licence)
      alias     = { first, last, dob } | nil    (the false name they give, 'alias' only)
      bac       = 0.12 | nil                    ('drunk' only)
    }
]]

Generator = {}

local function pick(list) return list[math.random(#list)] end

local function weighted(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local roll = math.random() * total
    local keys = {}
    for k in pairs(weights) do keys[#keys + 1] = k end
    table.sort(keys) -- pairs order is random: sort so the same roll always picks the same key
    for _, k in ipairs(keys) do
        roll = roll - weights[k]
        if roll <= 0 then return k end
    end
    return keys[#keys]
end
Generator.weighted = weighted

-- MM/DD/YYYY. Built from parts: os.date can't go before 1970 on Windows servers.
local function dob(min_age, max_age)
    return ('%02d/%02d/%d'):format(math.random(1, 12), math.random(1, 28),
        os.date('*t').year - math.random(min_age, max_age))
end

local function name(male)
    return pick(male and Data.first.male or Data.first.female), pick(Data.last)
end

-- A brand-new person with that secret. -> person fields for Db.createPerson (truth included)
function Generator.person(male, secret)
    local first, last = name(male)
    local p = {
        first = first, last = last, dob = dob(18, 75), gender = male and 'Male' or 'Female',
        address = math.random(100, 9999) .. ' ' .. pick(Data.streets), dl = 'Valid', flags = {},
        truth = { secret = secret, demeanor = weighted(Config.Demeanors), id = 'hands' },
    }
    local t = p.truth
    if secret == 'unlicensed' then
        p.dl, t.id = 'None', 'forgot'
    elseif secret == 'suspended' then
        p.dl = math.random() < 0.75 and 'Suspended' or 'Revoked'
    elseif secret == 'warrant' then
        p.warrant = pick(Data.warrants)
        t.id = math.random() < 0.6 and 'alias' or 'forgot'
        if t.id == 'alias' then
            local af, al = name(male)
            t.alias = { first = af, last = al, dob = dob(18, 75) }
        end
    elseif secret == 'drunk' then
        t.bac = math.random(9, 18) / 100
    end
    if secret == 'nervous' then t.demeanor = 'nervous' end
    if math.random() < Config.FlagChance or secret == 'drugs' then
        p.flags[1] = secret == 'drugs' and 'DRUG RELATED' or pick(Data.flags)
    end
    return p
end

-- ─── someone met before, back again ──────────────────────────────────────────

-- What their record says they're hiding (a warrant, a licence that isn't valid): that's theirs every time.
local RECORD = { warrant = true, suspended = true, unlicensed = true }
local function on_record(p)
    if p.warrant then return 'warrant' end
    if p.dl == 'Suspended' or p.dl == 'Revoked' then return 'suspended' end
    if p.dl == 'None' then return 'unlicensed' end
end

-- What they're hiding today, or nil when they can't be the one: their record decides a warrant or (driving) a bad
-- licence; otherwise free = the weights it was rolled from (pedestrians, passengers, a car not on file): often the
-- same as last time; not free (a car's papers, a staged violator's driving): it has to be this secret.
local function today(person, last, secret, free, driving)
    local bound = on_record(person)
    if bound ~= 'warrant' and not driving then bound = nil end -- (a licence is nothing to hide on foot)
    if bound then return (bound == secret or (free and (free[bound] or 0) > 0)) and bound or nil end
    if RECORD[secret] then return nil end -- (a record they haven't got)
    if free and last and not RECORD[last] and (free[last] or 0) > 0 and math.random() < (Config.RepeatSameSecret or 0.5) then
        return last
    end
    return secret
end

-- Their truth for today: what they're like stays, what they're hiding is today's. (A plain copy: exports
-- serialise it.)
local function truth_for(truth, secret)
    local t = {}
    for k, v in pairs(truth or {}) do t[k] = v end
    t.secret = secret
    if secret == 'drunk' then t.bac = t.bac or math.random(9, 18) / 100 else t.bac = nil end
    if secret == 'nervous' then t.demeanor = 'nervous' end
    if secret == 'unlicensed' then t.id = 'forgot' elseif secret ~= 'warrant' and t.id ~= 'hands' then t.id = 'hands' end
    return t
end

-- Picked for a car or a contact that's still being made up (bound once it's started): nobody else may take them
-- meanwhile. [person id] = when.
local Reserved = {}

-- Someone already someone's stop, in a callout, a car's recent driver (stops.lua), or being picked right now.
local function taken(id)
    local at = Reserved[id]
    if at and os.time() - at < 60 then return true end
    Reserved[id] = nil
    return SubjectInUse(id) or (HeldByRecent and HeldByRecent(id)) or false
end
Generator.taken = taken
function Generator.reserve(id) Reserved[id] = os.time() end
function Generator.release(id) Reserved[id] = nil end

--[[ The ped looks like someone the town has met before (same model, same gender): Config.RepeatChance that it's
     them, back again with their own record, unless they're somebody already. opts = { free (see today), driving,
     not_id (never this person: a stolen car's own owner) }. Waits on SQL. -> person, truth (today's) | nil ]]
function Generator.again(male, secret, model, opts)
    opts = opts or {}
    if not model or model == 0 or math.random() >= (Config.RepeatChance or 0.33) then return nil end
    for _, id in ipairs(Db.faces(model, male and 'Male' or 'Female')) do
        if id ~= opts.not_id and not taken(id) then
            local person, truth = Db.getPerson(id)
            local s = person and today(person, truth and truth.secret, secret, opts.free, opts.driving)
            if s then
                Generator.reserve(id)
                return person, truth_for(truth, s)
            end
        end
    end
end

-- A passenger: their own person and hidden truth (Config.PassengerSecrets: nothing to do with the
-- car's papers or driving), or someone met before (model: their ped's). Waits on SQL. -> { person, truth, items }
function Generator.passenger(male, model)
    local secret = weighted(Config.PassengerSecrets)
    local person, truth = Generator.again(male, secret, model, { free = Config.PassengerSecrets })
    if not person then
        for _ = 1, 3 do -- a name already on file keeps its own story: try another
            person, truth = Db.createPerson(Generator.person(male, secret))
            if truth.secret == secret then break end
        end
    end
    return { person = person, truth = truth, items = Generator.items(truth.secret) }
end

-- Things on them or in the car that matter to the story.
function Generator.items(secret)
    local items = {}
    if secret == 'drugs' then
        items[1] = pick(Data.drugs)
        if math.random() < 0.4 then items[2] = pick(Data.drugs) end
    elseif secret == 'drunk' and math.random() < 0.5 then
        items[1] = pick(Data.drink)
    elseif secret == 'stolen' then
        items[1] = pick(Data.stolen)
    end
    if items[2] == items[1] then items[2] = nil end
    if (secret == 'warrant' and math.random() < 0.3) or (secret == 'drugs' and math.random() < 0.15) then
        items[#items + 1] = pick(Data.weapons)
    end
    return items
end

-- Where what they carry is: on them (a pat-down finds it) or stashed in the car (a search does).
-- Bottles, cans, tools and anything bulky stay in the car. -> on_person, in_car
local CAR_ONLY = { 'beer', 'vodka', 'bottle', 'cans', 'screwdriver', 'slim jim', 'mail', '28 g', 'revolver' }
function Generator.stash(items)
    local on, car = {}, {}
    for _, item in ipairs(items or {}) do
        local big = false
        for _, w in ipairs(CAR_ONLY) do big = big or item:lower():find(w, 1, true) ~= nil end
        local t = (big or math.random() < 0.5) and car or on
        t[#t + 1] = item
    end
    return on, car
end

-- A couple of everyday things from a list, so a search never comes back empty-handed.
function Generator.some(list, n)
    local out, used = {}, {}
    while #out < n and #out < #list do
        local x = pick(list)
        if not used[x] then used[x], out[#out + 1] = true, x end
    end
    return out
end

-- The car's papers, from the driver's secret. owner_id = whoever it's registered to.
function Generator.vehicle(plate, info, secret, owner_id)
    local v = {
        plate = plate, make = info.make, model = info.model, color = info.color, year = math.random(2006, 2026),
        owner_id = owner_id, reg_valid = true, ins_valid = true, stolen = false,
    }
    if secret == 'expired' then
        if math.random() < 0.5 then v.reg_valid = false else v.ins_valid = false end
    elseif secret == 'stolen' then
        v.stolen = math.random() < 0.7 -- not every stolen car has been reported yet
    end
    return v
end

local CAR_SECRETS = { stolen = true, expired = true } -- secrets that live in the car's papers

-- A car seen before keeps its papers: its secret comes from them, never a new roll that contradicts them.
local function secret_for(vehicle)
    if not vehicle then return weighted(Config.Secrets) end
    if vehicle.stolen then return 'stolen' end
    if not vehicle.reg_valid or not vehicle.ins_valid then return 'expired' end
    local w = {}
    for k, v in pairs(Config.Secrets) do
        if not CAR_SECRETS[k] then w[k] = v end
    end
    return next(w) and weighted(w) or 'clean'
end

--[[ Who is driving the car with this plate. The first time it's stopped, the driver and the car's
     papers are made up and saved; after that the registered owner is usually the one driving it.
     info = { make, model, color, male, secret?, ped_model? } from the officer's game; secret (a staged violator's)
     is only used for a car not on file: one on file keeps its own story. ped_model: the driver's, so someone met
     before can be back at the wheel (Generator.again).
     Waits on SQL. -> { person, truth, vehicle, items } ]]
function Generator.stop(plate, info)
    local gender = info.male and 'Male' or 'Female'
    local vehicle = Db.findVehicle(plate)
    -- a stolen car's owner isn't driving it
    if vehicle and vehicle.owner_id and not vehicle.stolen and math.random() < Config.OwnerDrivesChance then
        local owner, truth = Db.getPerson(vehicle.owner_id)
        -- the ped at the wheel has to fit the owner: their gender, the model they were met as (if they were), and
        -- not somebody somewhere else right now
        local face = owner and info.ped_model and Db.face(owner.id)
        if owner and owner.gender == gender and not (face and face.model ~= info.ped_model) and not taken(owner.id) then
            Generator.reserve(owner.id)
            local car = secret_for(vehicle)
            if car == 'expired' and (truth.secret == 'clean' or truth.secret == 'nervous') then
                local copy = { secret = 'expired' } -- their papers lapsed (a plain copy: exports serialise it)
                for k, v in pairs(truth) do if k ~= 'secret' then copy[k] = v end end
                truth = copy
            end
            return { person = owner, truth = truth, vehicle = vehicle, items = Generator.items(truth.secret) }
        end
    end

    local secret = (not vehicle and info.secret) or secret_for(vehicle)
    -- someone met before: free to be what they were last time only when nothing here decided it (no papers on file,
    -- not a staged violator's driving)
    local driver, truth = Generator.again(info.male, secret, info.ped_model, { driving = true,
        free = not vehicle and not info.secret and Config.Secrets or nil, not_id = vehicle and vehicle.owner_id })
    if not driver then
        for _ = 1, 3 do -- a new name: someone already on file keeps their own story, which may not fit this car
            driver, truth = Db.createPerson(Generator.person(info.male, secret))
            if truth.secret == secret then break end
        end
    end
    secret = truth.secret or secret

    if not vehicle then
        local owner_id = driver.id
        if secret == 'stolen' then
            owner_id = Db.createPerson(Generator.person(math.random() < 0.5, 'clean')).id
        elseif math.random() < Config.BorrowedChance then -- a relative's car: same last name
            local o = Generator.person(math.random() < 0.5, 'clean')
            o.last, o.dob = driver.last, dob(40, 80)
            owner_id = Db.createPerson(o).id
        end
        vehicle = Db.createVehicle(Generator.vehicle(plate, info, secret, owner_id))
    end
    return { person = driver, truth = truth, vehicle = vehicle, items = Generator.items(secret) }
end
