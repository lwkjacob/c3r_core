--[[
    c3r — people and vehicles in SQL (oxmysql). Tables are created on start.

    Every person and vehicle c3r generates is kept: the same driver can turn up again next week,
    with the same name, licence and record. `truth` is what only c3r knows (what they're hiding,
    how they behave); it never leaves the server except through GetPedSubject.
]]

Db = {}

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS c3r_people (
        id INT AUTO_INCREMENT PRIMARY KEY,
        first VARCHAR(40) NOT NULL,
        last VARCHAR(40) NOT NULL,
        dob VARCHAR(10) NOT NULL,
        gender VARCHAR(10) NULL,
        address VARCHAR(80) NULL,
        dl VARCHAR(20) NOT NULL DEFAULT 'Valid',
        flags LONGTEXT NULL,
        warrant VARCHAR(120) NULL,
        truth LONGTEXT NULL,
        created INT NOT NULL,
        last_seen INT NOT NULL,
        UNIQUE KEY identity (first, last, dob)
    )]],
    [[CREATE TABLE IF NOT EXISTS c3r_vehicles (
        id INT AUTO_INCREMENT PRIMARY KEY,
        plate VARCHAR(8) NOT NULL UNIQUE,
        make VARCHAR(30) NULL,
        model VARCHAR(30) NULL,
        color VARCHAR(30) NULL,
        year SMALLINT NULL,
        owner_id INT NULL,
        reg_valid TINYINT(1) NOT NULL DEFAULT 1,
        ins_valid TINYINT(1) NOT NULL DEFAULT 1,
        stolen TINYINT(1) NOT NULL DEFAULT 0,
        bolo VARCHAR(120) NULL,
        created INT NOT NULL,
        last_seen INT NOT NULL,
        KEY owner (owner_id)
    )]],
    -- how someone looked the first time an officer met them (their ped model, face and clothes), and who has met
    -- them: someone stopped again looks like themselves (server/stops.lua meet)
    [[CREATE TABLE IF NOT EXISTS c3r_faces (
        person_id INT PRIMARY KEY,
        model BIGINT NOT NULL,
        look VARCHAR(255) NULL,
        met VARCHAR(255) NULL,
        seen INT NOT NULL,
        KEY model (model)
    )]],
    -- each officer's all-time totals (server/stats.lua). utf8mb4: a player picks their own name, emoji and all.
    [[CREATE TABLE IF NOT EXISTS c3r_officers (
        license VARCHAR(64) PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        stops INT NOT NULL DEFAULT 0,
        contacts INT NOT NULL DEFAULT 0,
        citations INT NOT NULL DEFAULT 0,
        warnings INT NOT NULL DEFAULT 0,
        arrests INT NOT NULL DEFAULT 0,
        pursuits_won INT NOT NULL DEFAULT 0,
        pursuits_lost INT NOT NULL DEFAULT 0,
        callouts INT NOT NULL DEFAULT 0,
        assists INT NOT NULL DEFAULT 0,
        seconds INT NOT NULL DEFAULT 0,
        first_seen INT NOT NULL,
        last_seen INT NOT NULL
    ) CHARACTER SET utf8mb4]],
}

-- Before the rename to CODE3RESPONSE the tables were lwk_pd_people / lwk_pd_vehicles: a server that had them keeps
-- its people and cars (renamed once, the first time c3r starts).
local RENAMED = { { 'lwk_pd_people', 'c3r_people' }, { 'lwk_pd_vehicles', 'c3r_vehicles' } }

local function table_exists(name)
    local rows = MySQL.query.await('SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name })
    return type(rows) == 'table' and rows[1] ~= nil
end

MySQL.ready(function()
    for _, t in ipairs(RENAMED) do
        if table_exists(t[1]) and not table_exists(t[2]) then
            MySQL.query.await(('RENAME TABLE `%s` TO `%s`'):format(t[1], t[2]))
            print(('[c3r] kept your records: table %s is now %s'):format(t[1], t[2]))
        end
    end
    for _, sql in ipairs(SCHEMA) do MySQL.query.await(sql) end
end)

local function decode(s)
    local ok, v = pcall(json.decode, s or '')
    return ok and type(v) == 'table' and v or {}
end

-- Row -> the public person record (what a name check returns). truth stays out.
local function person(row)
    if not row then return nil end
    return {
        id = row.id, first = row.first, last = row.last, dob = row.dob, gender = row.gender, address = row.address,
        dl = row.dl, dl_valid = row.dl == 'Valid', flags = decode(row.flags), warrant = row.warrant,
    }
end

local function vehicle(row)
    if not row then return nil end
    local owner = row.owner_first and (row.owner_first .. ' ' .. row.owner_last) or nil
    return {
        id = row.id, plate = row.plate, make = row.make, model = row.model, color = row.color,
        year = row.year and tostring(row.year) or nil, owner = owner, owner_id = row.owner_id,
        reg_valid = row.reg_valid == 1 or row.reg_valid == true, ins_valid = row.ins_valid == 1 or row.ins_valid == true,
        stolen = row.stolen == 1 or row.stolen == true, bolo = row.bolo ~= nil, bolo_reason = row.bolo,
    }
end

local VEHICLE_SELECT = [[SELECT v.*, p.first AS owner_first, p.last AS owner_last
    FROM c3r_vehicles v LEFT JOIN c3r_people p ON p.id = v.owner_id ]]

-- -> public record, truth table
function Db.getPerson(id)
    local row = MySQL.single.await('SELECT * FROM c3r_people WHERE id = ?', { id })
    return person(row), row and decode(row.truth) or nil
end

function Db.getVehicle(id)
    return vehicle(MySQL.single.await(VEHICLE_SELECT .. 'WHERE v.id = ?', { id }))
end

function Db.findVehicle(plate)
    plate = type(plate) == 'string' and plate:upper():gsub('%s+', '') or nil
    if not plate or plate == '' then return nil end
    return vehicle(MySQL.single.await(VEHICLE_SELECT .. 'WHERE v.plate = ?', { plate }))
end

-- p = { first, last, dob, gender?, address?, dl?, flags?, warrant?, truth? }. An existing identity
-- (same name + DOB) is returned as it is, so the generator can't overwrite someone's record.
function Db.createPerson(p)
    local now = os.time()
    MySQL.insert.await([[INSERT IGNORE INTO c3r_people
        (first, last, dob, gender, address, dl, flags, warrant, truth, created, last_seen)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        p.first, p.last, p.dob, p.gender, p.address, p.dl or 'Valid', json.encode(p.flags or {}), p.warrant,
        json.encode(p.truth or {}), now, now,
    })
    local row = MySQL.single.await('SELECT * FROM c3r_people WHERE first = ? AND last = ? AND dob = ?',
        { p.first, p.last, p.dob })
    return person(row), row and decode(row.truth) or nil
end

-- People on file by name, as an officer types it ('rachel white', 'white rachel', 'whi'): every word starts their
-- first or last name. -> up to 10 public records, the most recently seen first
function Db.findPeople(q)
    local words = {}
    for w in tostring(q or ''):gmatch("[%a%-']+") do if #words < 3 then words[#words + 1] = w end end
    if not words[1] then return {} end
    local where, args = {}, {}
    for _, w in ipairs(words) do -- (letters, - and ' only: nothing LIKE would read as a wildcard)
        where[#where + 1] = '(first LIKE ? OR last LIKE ?)'
        args[#args + 1], args[#args + 2] = w .. '%', w .. '%'
    end
    local rows = MySQL.query.await('SELECT * FROM c3r_people WHERE ' .. table.concat(where, ' AND ')
        .. ' ORDER BY last_seen DESC LIMIT 10', args)
    local out = {}
    for _, r in ipairs(type(rows) == 'table' and rows or {}) do out[#out + 1] = person(r) end
    return out
end

-- Someone's face: { model, look ('d,t,...|i,t,...'), met = { officer ids } } | nil
function Db.face(person_id)
    local row = MySQL.single.await('SELECT * FROM c3r_faces WHERE person_id = ?', { person_id })
    if not row then return nil end
    local met = {}
    for id in (row.met or ''):gmatch('[^,]+') do met[#met + 1] = id end
    return { model = tonumber(row.model), look = row.look, met = met }
end

-- Met again (or for the first time): the first model and look are kept; the officer joins who has met them
-- (the last 5: a licence id is 48 characters). f = Db.face(person_id) if it's just been read.
function Db.seenFace(person_id, model, look, officer, f)
    f = f or Db.face(person_id)
    local met = f and f.met or {}
    for i = #met, 1, -1 do if met[i] == officer then table.remove(met, i) end end
    if officer then met[#met + 1] = officer end
    while #met > 5 do table.remove(met, 1) end
    MySQL.insert.await([[INSERT INTO c3r_faces (person_id, model, look, met, seen) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE look = COALESCE(look, VALUES(look)), met = VALUES(met), seen = VALUES(seen)]],
        { person_id, model, look, table.concat(met, ','):sub(1, 255), os.time() })
end

-- People met before with this ped model and gender, a few at random: -> { person_id, ... }
-- ponytail: ORDER BY RAND() over one model's rows; fine for thousands, a random offset if it ever isn't.
function Db.faces(model, gender)
    local rows = MySQL.query.await([[SELECT f.person_id FROM c3r_faces f JOIN c3r_people p ON p.id = f.person_id
        WHERE f.model = ? AND p.gender = ? ORDER BY RAND() LIMIT 8]], { model, gender })
    local out = {}
    for _, r in ipairs(type(rows) == 'table' and rows or {}) do out[#out + 1] = r.person_id end
    return out
end

-- v = { plate, make?, model?, color?, year?, owner_id?, reg_valid?, ins_valid?, stolen?, bolo? }
function Db.createVehicle(v)
    local now = os.time()
    MySQL.insert.await([[INSERT IGNORE INTO c3r_vehicles
        (plate, make, model, color, year, owner_id, reg_valid, ins_valid, stolen, bolo, created, last_seen)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        v.plate:upper(), v.make, v.model, v.color, tonumber(v.year), v.owner_id, v.reg_valid ~= false,
        v.ins_valid ~= false, v.stolen == true, v.bolo, now, now,
    })
    return Db.findVehicle(v.plate)
end

Db.STATS = { 'stops', 'contacts', 'citations', 'warnings', 'arrests', 'pursuits_won', 'pursuits_lost', 'callouts', 'assists', 'seconds' }

-- An officer's new counts added to their totals. p = { name, [stat] = n }. wait: waits on SQL (in a thread).
function Db.addStats(license, p, now, wait)
    local cols, marks, adds, args = {}, {}, {}, { license, p.name }
    for _, stat in ipairs(Db.STATS) do
        cols[#cols + 1], marks[#marks + 1] = stat, '?'
        adds[#adds + 1] = ('%s = %s + VALUES(%s)'):format(stat, stat, stat)
        args[#args + 1] = p[stat] or 0
    end
    args[#args + 1], args[#args + 2] = now, now
    local sql = ([[INSERT INTO c3r_officers (license, name, %s, first_seen, last_seen) VALUES (?, ?, %s, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), %s, last_seen = VALUES(last_seen)]]):format(
        table.concat(cols, ', '), table.concat(marks, ', '), table.concat(adds, ', '))
    if wait then MySQL.insert.await(sql, args) else MySQL.insert(sql, args) end
end

function Db.officer(license) return MySQL.single.await('SELECT * FROM c3r_officers WHERE license = ?', { license }) end

function Db.officers()
    local rows = MySQL.query.await('SELECT * FROM c3r_officers ORDER BY seconds DESC LIMIT 200')
    return type(rows) == 'table' and rows or {}
end

-- A warrant on someone's record (text), or served (nil). An active one stands: a second doesn't replace it.
-- -> true when their record changed
function Db.setWarrant(id, text)
    local n
    if text then n = MySQL.update.await('UPDATE c3r_people SET warrant = ? WHERE id = ? AND warrant IS NULL', { text, id })
    else n = MySQL.update.await('UPDATE c3r_people SET warrant = NULL WHERE id = ? AND warrant IS NOT NULL', { id }) end
    return (tonumber(n) or 0) > 0
end

-- The same for a car's BOLO. id = its record id.
function Db.setBolo(id, text)
    local n
    if text then n = MySQL.update.await('UPDATE c3r_vehicles SET bolo = ? WHERE id = ? AND bolo IS NULL', { text, id })
    else n = MySQL.update.await('UPDATE c3r_vehicles SET bolo = NULL WHERE id = ? AND bolo IS NOT NULL', { id }) end
    return (tonumber(n) or 0) > 0
end

-- The plate of a car of that model with a BOLO on it, one at random | nil
function Db.boloCar(model)
    if not model then return nil end
    local row = MySQL.single.await('SELECT plate FROM c3r_vehicles WHERE bolo IS NOT NULL AND model = ? ORDER BY RAND() LIMIT 1', { model })
    return row and row.plate
end
