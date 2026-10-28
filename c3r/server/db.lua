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
