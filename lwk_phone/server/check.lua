-- The start-up report: what the phone found on this server, anything that will get in its way, and
-- whether a newer version is out. Printed a few seconds after start, and by the `phonecheck` command
-- at any time. It is the first thing to paste when asking for help.

Check = {}

local REPO = 'lwkjacob/lwk_phone'

local ART = {
    [[ _      __        __  _  __       ____    _   _    ___    _   _   _____ ]],
    [[| |     \ \      / / | |/ /      |  _ \  | | | |  / _ \  | \ | | | ____|]],
    [[| |      \ \ /\ / /  | ' /       | |_) | | |_| | | | | | |  \| | |  _|  ]],
    [[| |___    \ V  V /   | . \       |  __/  |  _  | | |_| | | |\  | | |___ ]],
    [[|_____|    \_/\_/    |_|\_\      |_|     |_| |_|  \___/  |_| \_| |_____|]],
}

local FRAMEWORKS = { qbox = 'Qbox', qb = 'QBCore', esx = 'ESX', ox = 'ox_core', nd = 'ND_Core', standalone = 'none (standalone)' }
local INVENTORIES = {
    ox = 'ox_inventory', qb = 'qb-inventory', ps = 'ps-inventory', codem = 'codem-inventory', core = 'core_inventory',
    jaksam = 'jaksam_inventory', tgiann = 'tgiann-inventory', esx = "ESX's own", none = 'none',
}
local VOICES = { pma = 'pma-voice', salty = 'saltychat', mumble = 'mumble-voip', none = 'none' }

-- Other phones. Two of them on one server fight over the same key and the same command.
local PHONES = { 'npwd', 'qb-phone', 'qs-smartphone', 'qs-smartphone-pro', 'gksphone', 'high_phone', 'roadphone', 'yseries', 'sd-phone', 'okokPhone' }

local function started(res) return GetResourceState(res) == 'started' end

--- The version in this resource's manifest.
function Check.version()
    return GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?'
end

--- The newest release on GitHub: its version, or nil plus why not ('none' published yet, or 'unreachable').
local function latest()
    local p = promise.new()
    PerformHttpRequest(('https://api.github.com/repos/%s/releases/latest'):format(REPO), function(status, body)
        local ok, res = pcall(json.decode, body or '')
        if status == 200 and ok and type(res) == 'table' and type(res.tag_name) == 'string' then return p:resolve({ res.tag_name }) end
        p:resolve({ nil, status == 404 and 'none' or 'unreachable' })
    end, 'GET', '', { ['User-Agent'] = 'lwk_phone' })
    return table.unpack(Citizen.Await(p))
end

--- The database version, and whether it is new enough for the conversation list (window functions).
local function database()
    local v = MySQL.scalar.await('SELECT VERSION()')
    if type(v) ~= 'string' then return 'unknown', true end
    local major, minor = v:match('^(%d+)%.(%d+)')
    major, minor = tonumber(major) or 0, tonumber(minor) or 0
    if v:lower():find('mariadb', 1, true) then return v, major > 10 or (major == 10 and minor >= 2) end
    return v, major >= 8
end

--- The report as lines of text. `release` and `why` are what latest() answered.
function Check.lines(release, why)
    local rows, warnings = {}, {}
    local function row(name, value) rows[#rows + 1] = ('  ^7%-11s ^5%s'):format(name, value) end
    local function warn(text) warnings[#warnings + 1] = '  ^3! ' .. text end

    local version = Check.version()
    if release and Util.newer(release, version) then
        row('Version', ('%s  ^3update available: %s  ^7https://github.com/%s/releases/latest'):format(version, release, REPO))
    elseif release then
        row('Version', version .. '  ^2up to date')
    elseif why == 'none' then
        row('Version', version .. '  ^7(no release has been published to compare with yet)')
    else
        row('Version', version .. '  ^7(could not reach GitHub to look for a newer one)')
    end

    local fw = Bridge.framework
    row('Framework', (FRAMEWORKS[fw] or fw) .. (Bridge.nd1 and ' 1.x' or '') .. (Bridge.running() and '' or '  ^1not running'))
    if not Bridge.running() then
        warn(('%s is on the server but not running, so nobody can open the phone. Start it before lwk_phone in server.cfg (ensure %s) and check it is not in the resources folder twice. Or set framework = \'standalone\' in config/config.lua.'):format(
            FRAMEWORKS[fw] or fw, Bridge.resource))
    end
    row('Inventory', (INVENTORIES[Inv.kind] or Inv.kind) .. (Inv.unique and ': each phone item is its own phone' or Inv.required and ': a phone item is needed' or ': no item needed'))

    row('Voice', VOICES[Voice.kind] or Voice.kind)
    if Voice.kind == 'none' then warn('No voice script: calls will connect but nobody will hear anything. Install pma-voice.') end
    if Voice.kind == 'salty' then warn('saltychat: muting your microphone on a call does not silence you at the other end. Everything else works.') end

    if fw == 'standalone' then
        row('Bank', 'not used')
        row('Garage', 'not used')
        warn('No framework: Wallet, Crypto, Garage and Services need money, vehicles and jobs, so they are hidden.')
    else
        local bank = Bank.kind()
        row('Bank', bank == 'none' and 'none found' or bank == 'esx_addonaccount' and started('esx_society') and 'esx_society (its money is in esx_addonaccount)' or bank)
        if bank == 'none' then warn('No bank script this phone knows: the company account in Services is off. Wallet works with any bank. README, "Banks".') end

        if Bridge.has.vehicles then
            local g = Bridge.garage()
            row('Garage', (g.script or 'no garage script it knows by name') .. (#g.columns > 0 and (' (%s: %s)'):format(g.table, table.concat(g.columns, ', ')) or ''))
            if #g.columns == 0 then warn(('%s has none of the columns this phone reads, so every vehicle will show as garaged. README, "Garages".'):format(g.table)) end
        else
            row('Garage', 'not used')
            warn('ND_Core 1.x keeps no vehicles of its own, so the Garage app is hidden. README, "ND_Core".')
        end
    end

    row('Housing', Housing.kind() == 'none' and 'none found: the Home app is hidden' or Housing.kind())

    local old, oldName = Transfer.source()
    if old then row('Transfer', ('%s data found: %d numbers kept for their owners, the rest offered in setup'):format(old.label, Transfer.kept())) end
    if old and GetResourceState(oldName) == 'started' then
        warn(('%s is still running. Stop it: its data is brought over from the database, not from the running script.'):format(old.label))
    end

    local token = Phone.uploadToken() ~= ''
    local hosts = Config.upload.hosts or {}
    row('Uploads', (token and 'token set' or 'no token') .. (#hosts > 0 and ', media only from ' .. table.concat(hosts, ', ') or ', media from anywhere'))
    if not token then warn('No upload token: the camera, voice messages and voice memos are off. README, "Photos, video and voice messages".') end
    if #hosts == 0 then warn('Config.upload.hosts is empty: a player can make other phones load a picture from their own server and collect IP addresses.') end

    local db, recent = database()
    row('Database', db)
    if not recent then warn('This database is too old for the conversation list. It needs MariaDB 10.2+ or MySQL 8.') end

    local onesync = GetConvar('onesync', 'off') ~= 'off'
    row('OneSync', onesync and 'on' or 'off')
    if not onesync then warn('OneSync is off: AirShare, hiring, speakerphone and locating a vehicle need the server to know where players are.') end

    row('Language', Config.locale)

    for _, res in ipairs(PHONES) do
        if started(res) and res ~= oldName then warn(('Another phone is running: %s. Two phones fight over the same key and the same command; stop one of them.'):format(res)) end
    end
    -- The four-line resource that lets LB Phone apps find this phone has no page of its own. One that has is the real thing.
    if started('lb-phone') and GetNumResourceMetadata('lb-phone', 'ui_page') > 0 then
        warn('The real lb-phone is running. This phone answers under that name too, so they cannot share a server.')
    end

    local out = { '' }
    for _, line in ipairs(ART) do out[#out + 1] = '^5  ' .. line end
    out[#out + 1] = ''
    for _, line in ipairs(rows) do out[#out + 1] = line end
    out[#out + 1] = ''
    if #warnings == 0 then out[#out + 1] = '  ^2Nothing to fix.' end
    for _, line in ipairs(warnings) do out[#out + 1] = line end
    out[#out + 1] = '^7'
    return out
end

function Check.report()
    print(table.concat(Check.lines(latest()), '\n'))
end

-- A few seconds in, so the banks and garage scripts that start after the phone have started.
CreateThread(function()
    DB.wait()
    Wait(5000)
    Check.report()
end)

--- phonecheck: print the report again (console or an admin).
RegisterCommand('phonecheck', function(src)
    if src == 0 or Bridge.isAdmin(src) then Check.report() end
end, false)
