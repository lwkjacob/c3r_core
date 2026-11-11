--[[
    lwk_calloutcreator server: packs and their callouts on disk, saving (the generator writes the Lua), loading them into
    c3r, a test call, and writing a pack out as a resource of its own. Talks to c3r only through its exports
    (loadCallout, unloadCallout, getCallout, requestCallout: c3r/docs/contract.md).

    On disk, in this resource:
      packs/index.json            the packs: { packs = { { id, name, author, version, description, licence, callouts = { ids } } } }
      packs/<pack>.<callout>.lua  each callout (FXServer can't make folders, so they sit side by side)
      export/<pack>/              a pack written out: fxmanifest.lua (c3r_callout lines) and its callouts
    Packs other resources carry (c3r_callout lines in their own fxmanifest) show too, and their callouts made here can
    be edited where they are.
]]

local RES = GetCurrentResourceName()
local MAX_DOC = 400000 -- bytes of JSON: a callout bigger than this is a mistake

local function log(fmt, ...) if Config.Debug then print(('[lwk_calloutcreator] ' .. fmt):format(...)) end end
local function c3r() return GetResourceState('c3r') == 'started' end
local function allowed(src) return src > 0 and IsPlayerAceAllowed(src, Config.Ace) end
local function ident(s) return type(s) == 'string' and #s <= 40 and s:match('^[%a_][%w_]*$') ~= nil end
local function text(s, max) return type(s) == 'string' and #s <= max end

-- ─── the index ──────────────────────────────────────────────────────────────────────────────────────────────

local DEFAULT = { packs = { { id = 'example', name = 'Example pack', author = 'LWK DEVELOPMENT', version = '1.0.0', licence = 'CC BY-NC-SA 4.0',
    description = 'One callout to open, play and copy. Shoplifting is never offered by itself: Test it from the creator, or /requestcall shoplift.',
    callouts = { 'shoplift' } } } }

local function read_index()
    local raw = LoadResourceFile(RES, 'packs/index.json')
    local ok, t = pcall(json.decode, raw or '')
    if ok and type(t) == 'table' and type(t.packs) == 'table' then return t end
    return json.decode(json.encode(DEFAULT))
end
local Index = read_index()

local function save_index()
    SaveResourceFile(RES, 'packs/index.json', json.encode(Index, { indent = true }), -1)
end

local function pack_of(id)
    for _, p in ipairs(Index.packs) do if p.id == id then return p end end
end

local function file_of(pack, id) return ('packs/%s.%s.lua'):format(pack, id) end

local function load_one(res, file)
    if not c3r() then return nil, 'c3r is not running' end
    local ok, ids, why = pcall(function() return exports.c3r:loadCallout(res, file) end)
    if not ok then return nil, tostring(ids) end
    return ids, why
end

local function load_all()
    for _, p in ipairs(Index.packs) do
        for _, id in ipairs(p.callouts or {}) do
            local ids, why = load_one(RES, file_of(p.id, id))
            if not ids then print(('[lwk_calloutcreator] %s/%s not loaded: %s'):format(p.id, id, tostring(why))) end
        end
    end
end

CreateThread(function() if c3r() then load_all() end end)
AddEventHandler('onResourceStart', function(res)
    if res == 'c3r' then SetTimeout(500, load_all) end -- (c3r started again: it has none of ours)
end)

-- ─── packs other resources carry ────────────────────────────────────────────────────────────────────────────

-- { { res, files = { { file, doc } } } }: every started resource with c3r_callout lines, and its creator-made files.
local function others()
    local out = {}
    for i = 0, GetNumResources() - 1 do
        local res = GetResourceByFindIndex(i)
        if res and res ~= RES and res ~= 'c3r' and GetResourceState(res) == 'started' then
            local n = GetNumResourceMetadata(res, 'c3r_callout')
            if n > 0 then
                local p = { res = res, name = GetResourceMetadata(res, 'description', 0) or res,
                            author = GetResourceMetadata(res, 'author', 0) or '', version = GetResourceMetadata(res, 'version', 0) or '', files = {} }
                for j = 0, n - 1 do
                    local file = GetResourceMetadata(res, 'c3r_callout', j)
                    local doc, edited = Gen.read(LoadResourceFile(res, file))
                    p.files[#p.files + 1] = { file = file, id = doc and doc.id, name = doc and doc.name, edited = edited, made = doc ~= nil }
                end
                out[#out + 1] = p
            end
        end
    end
    return out
end

-- where a callout lives: our pack, or someone else's resource. -> res, file
local function where(req)
    if type(req.res) == 'string' and req.res ~= RES then
        if GetResourceState(req.res) ~= 'started' then return nil end
        for j = 0, GetNumResourceMetadata(req.res, 'c3r_callout') - 1 do
            if GetResourceMetadata(req.res, 'c3r_callout', j) == req.file then return req.res, req.file end
        end
        return nil
    end
    local p = pack_of(req.pack)
    if not p or not ident(req.id) then return nil end
    return RES, file_of(p.id, req.id), p
end

-- ─── what the editor asks ───────────────────────────────────────────────────────────────────────────────────

local function live(id)
    if not c3r() then return nil end
    local ok, info = pcall(function() return exports.c3r:getCallout(id) end)
    return ok and info or nil
end

local function status(res, file, id)
    local info = id and live(id)
    return info and info.resource == res and info.file == file
end

local H = {}

function H.list()
    local packs = {}
    for _, p in ipairs(Index.packs) do
        local cs = {}
        for _, id in ipairs(p.callouts or {}) do
            local doc, edited = Gen.read(LoadResourceFile(RES, file_of(p.id, id)))
            cs[#cs + 1] = { id = id, name = doc and doc.name or id, edited = edited, loaded = status(RES, file_of(p.id, id), id),
                            stories = doc and #(doc.stories or {}) or 0, locations = doc and #(doc.locations or {}) or 0 }
        end
        packs[#packs + 1] = { id = p.id, name = p.name, author = p.author, version = p.version, description = p.description,
                              licence = p.licence, callouts = cs }
    end
    local ext = others()
    for _, o in ipairs(ext) do
        for _, f in ipairs(o.files) do f.loaded = f.id and status(o.res, f.file, f.id) end
    end
    return { packs = packs, others = ext, c3r = c3r() }
end

function H.open(src, req)
    local res, file = where(req)
    if not res then return nil, 'No such callout.' end
    local doc, edited = Gen.read(LoadResourceFile(res, file))
    if not doc then return nil, 'That file was not made with the creator, so it can only be edited by hand.' end
    local info = live(doc.id)
    if info and info.resource == res and info.file == file then
        doc.locations = info.locations -- (the ones /c3rplace has added since are in the file, not in the doc)
    end
    return { doc = doc, edited = edited, res = res ~= RES and res or nil, file = res ~= RES and file or nil }
end

-- Is that id free (not a callout someone else loaded)?
local function clash(id, res, file)
    local info = live(id)
    if info and not (info.resource == res and info.file == file) then
        return ('The id "%s" is already used by %s (%s). Pick another.'):format(id, info.resource or 'c3r', info.file or '')
    end
end

function H.save(src, req)
    local doc = req.doc
    if type(doc) ~= 'table' then return nil, 'Nothing to save.' end
    if #json.encode(doc) > MAX_DOC then return nil, 'This callout is too big to save.' end
    local errs = Gen.check(doc)
    if errs[1] then return { errors = errs } end
    local res, file, pack
    if req.res then
        res, file = where(req)
        if not res then return nil, 'That pack is not running any more.' end
        local old = Gen.read(LoadResourceFile(res, file))
        if old and old.id ~= doc.id then return nil, "A callout in another resource's pack keeps its id." end
    else
        pack = pack_of(req.pack)
        if not pack then return nil, 'No such pack.' end
        res, file = RES, file_of(pack.id, doc.id)
        if doc.id ~= req.was then
            for _, id in ipairs(pack.callouts) do
                if id == doc.id then return nil, ('Another callout in this pack is called "%s". Pick another id.'):format(doc.id) end
            end
        end
    end
    local why = clash(doc.id, res, file)
    if why then return nil, why end
    local before = LoadResourceFile(res, file)
    if before and before ~= '' and not req.force then
        local _, edited = Gen.read(before)
        if edited then return { edited = true } end
    end
    -- renamed: the old file goes, and the old id with it
    local old_id = pack and ident(req.was) and req.was ~= doc.id and req.was or nil
    SaveResourceFile(res, file, Gen.lua(doc, Config.Credit), -1)
    if pack then
        local listed = false
        for i, id in ipairs(pack.callouts) do
            if id == old_id then pack.callouts[i] = doc.id listed = true
            elseif id == doc.id then listed = true end
        end
        if not listed then pack.callouts[#pack.callouts + 1] = doc.id end
        local seen, list = {}, {}
        for _, id in ipairs(pack.callouts) do if not seen[id] then seen[id] = true list[#list + 1] = id end end
        pack.callouts = list
        save_index()
        if old_id then
            SaveResourceFile(RES, file_of(pack.id, old_id), '', -1)
            pcall(function() return exports.c3r:unloadCallout(old_id) end)
        end
    end
    local ids, lerr = load_one(res, file)
    print(('[lwk_calloutcreator] %s saved %s (%s/%s)'):format(GetPlayerName(src) or src, doc.id, res, file))
    return { saved = true, loaded = ids and true or false, why = lerr }
end

function H.delete(src, req)
    local p = pack_of(req.pack)
    if not p or not ident(req.id) then return nil, 'No such callout.' end
    for i = #p.callouts, 1, -1 do if p.callouts[i] == req.id then table.remove(p.callouts, i) end end
    save_index()
    SaveResourceFile(RES, file_of(p.id, req.id), '', -1) -- (FXServer can't delete a file: an empty one loads nothing)
    if c3r() and status(RES, file_of(p.id, req.id), req.id) then pcall(function() return exports.c3r:unloadCallout(req.id) end) end
    print(('[lwk_calloutcreator] %s deleted %s/%s'):format(GetPlayerName(src) or src, p.id, req.id))
    return { deleted = true }
end

local function meta(m)
    if type(m) ~= 'table' then return nil end
    local out = {}
    for _, k in ipairs({ 'name', 'author', 'version', 'description', 'licence' }) do
        local v = m[k]
        if v ~= nil and not text(v, k == 'description' and 400 or 60) then return nil end
        out[k] = (v or ''):gsub('[%c]', ' ')
    end
    if out.name == '' then return nil end
    return out
end

function H.pack(src, req)
    local m = meta(req.meta)
    if not m then return nil, 'A pack needs a name, and nothing too long.' end
    local p = req.pack and pack_of(req.pack)
    if not p then
        local id = (req.id or m.name):lower():gsub('[^%w_]+', '_'):gsub('^_+', ''):gsub('_+$', ''):sub(1, 30)
        if not ident(id) then id = 'pack_' .. id end
        if not ident(id) then return nil, 'Give the pack a name with some letters in it.' end
        local base, n = id, 1
        while pack_of(id) do n = n + 1 id = base .. n end
        p = { id = id, callouts = {} }
        Index.packs[#Index.packs + 1] = p
    end
    for k, v in pairs(m) do p[k] = v end
    save_index()
    return { pack = p.id }
end

function H.droppack(src, req)
    local p = pack_of(req.pack)
    if not p then return nil, 'No such pack.' end
    if p.callouts[1] then return nil, 'Delete its callouts first.' end
    for i, x in ipairs(Index.packs) do if x == p then table.remove(Index.packs, i) break end end
    save_index()
    return { deleted = true }
end

local REASONS = { off_duty = 'Go on duty first.', no_callout = 'No free location: place one, or end the call already open there.',
                  wrong_service = 'This call is for the other service: go on duty as that.', nobody_on_duty = 'Go on duty first.' }

function H.test(src, req)
    local res, file = where(req)
    if not res then return nil, 'No such callout.' end
    local doc = Gen.read(LoadResourceFile(res, file))
    if not doc then return nil, 'Save it first.' end
    if not (doc.locations or {})[1] then return nil, 'Place a location first (Locations tab), then save: the call needs somewhere to happen.' end
    local ids, why = load_one(res, file)
    if not ids then return nil, 'It would not load: ' .. tostring(why) end
    local story = ident(req.story) and req.story or nil
    local ok, done, reason = pcall(function() return exports.c3r:requestCallout(src, doc.id, story) end)
    if not ok then return nil, tostring(done) end
    if not done then return nil, REASONS[reason] or ('c3r would not start it (%s).'):format(tostring(reason)) end
    return { started = true }
end

-- A pack written out as a resource of its own, to copy to any c3r server.
local function mkdir(path)
    if not (os and os.execute) then return false end
    local win = package and package.config and package.config:sub(1, 1) == '\\'
    local ok = os.execute(win and ('if not exist "%s" mkdir "%s"'):format(path:gsub('/', '\\'), path:gsub('/', '\\'))
        or ("mkdir -p '%s'"):format(path))
    return ok == true or ok == 0
end

function H.export(src, req)
    local p = pack_of(req.pack)
    if not p then return nil, 'No such pack.' end
    if not p.callouts[1] then return nil, 'The pack has no callouts.' end
    local name = 'c3rpack_' .. p.id
    local dir = 'export/' .. name
    if not mkdir(GetResourcePath(RES) .. '/' .. dir) then
        return nil, ('This server cannot make folders. Make the folder lwk_calloutcreator/%s yourself, then Export again.'):format(dir)
    end
    local lines = {
        "fx_version 'cerulean'", "game 'gta5'", '',
        ('name %s'):format(Gen.q(name)),
        ('description %s'):format(Gen.q(p.name or name)),
        ('author %s'):format(Gen.q(p.author ~= '' and p.author or 'Unknown')),
        ('version %s'):format(Gen.q(p.version ~= '' and p.version or '1.0.0')), '',
        "dependency 'c3r'", '',
        '-- CODE3RESPONSE callouts, made with ' .. Config.Credit .. '. c3r runs each file listed here.',
    }
    local missing = {}
    for _, id in ipairs(p.callouts) do
        local t = LoadResourceFile(RES, file_of(p.id, id))
        if t and t ~= '' then
            if not SaveResourceFile(RES, dir .. '/' .. id .. '.lua', t, -1) then missing[#missing + 1] = id end
            lines[#lines + 1] = ('c3r_callout %s'):format(Gen.q(id .. '.lua'))
        end
    end
    SaveResourceFile(RES, dir .. '/fxmanifest.lua', table.concat(lines, '\n') .. '\n', -1)
    SaveResourceFile(RES, dir .. '/README.txt', table.concat({
        (p.name or name) .. (p.version ~= '' and (' ' .. p.version) or '') .. (p.author ~= '' and (' by ' .. p.author) or ''),
        p.description or '', '',
        'CODE3RESPONSE callouts. Put this folder in your server\'s resources and add "ensure ' .. name .. '" after c3r in server.cfg.',
        'Nothing else is needed: c3r runs the callouts. To edit them in game, install lwk_calloutcreator.',
        'Place more locations in game with /c3rplace <callout id>.', '',
        'Licence: ' .. ((p.licence and p.licence ~= '') and p.licence or 'not given by the author'),
        'Made with ' .. Config.Credit .. '.',
    }, '\n') .. '\n', -1)
    if missing[1] then return nil, 'Some files could not be written: ' .. table.concat(missing, ', ') end
    print(('[lwk_calloutcreator] %s exported %s to %s/%s'):format(GetPlayerName(src) or src, p.id, RES, dir))
    return { path = RES .. '/' .. dir, name = name }
end

-- ─── the wire ───────────────────────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('lwk_calloutcreator:req', function(n, action, req)
    local src = source
    if not allowed(src) then return TriggerClientEvent('lwk_calloutcreator:res', src, n, false, 'You do not have the creator ace (' .. Config.Ace .. ').') end
    local h = H[action]
    if type(h) ~= 'function' then return TriggerClientEvent('lwk_calloutcreator:res', src, n, false, 'Unknown request.') end
    local ok, out, why = pcall(h, src, type(req) == 'table' and req or {})
    if not ok then
        print(('[lwk_calloutcreator] %s: %s'):format(action, tostring(out)))
        return TriggerClientEvent('lwk_calloutcreator:res', src, n, false, 'Something went wrong (see the server console).')
    end
    log('%s %s -> %s', GetPlayerName(src) or src, action, out and 'ok' or tostring(why))
    TriggerClientEvent('lwk_calloutcreator:res', src, n, out ~= nil, out or why)
end)

RegisterNetEvent('lwk_calloutcreator:may', function()
    local src = source
    TriggerClientEvent('lwk_calloutcreator:may', src, allowed(src))
end)
