--[[
    c3r — server: /c3rconfig, the in-game config editor. Admins only: the command.c3rconfig ace
    (add_ace group.admin command.c3rconfig allow). It lists every value written in the config/ files and writes
    a change back over just that value, so the comments and the layout stay as they were. Lists (the stations,
    a unit's crew...) can be added to, copying their last entry, and taken from. A change is live at once for
    everyone; a key or a command name only after a restart of c3r.
]]

local RES = GetCurrentResourceName()

-- The config files, in the order fxmanifest.lua loads them.
local function config_files()
    local out = {}
    for i = 0, GetNumResourceMetadata(RES, 'shared_script') - 1 do
        local f = GetResourceMetadata(RES, 'shared_script', i)
        if f and f:match('^config/[%w_]+%.lua$') then out[#out + 1] = f end
    end
    return out
end

-- The file's tokens ({ t = 'name' | 'num' | 'str' | 'lit' | 'op', v, s, e = where in the text, line }) and its
-- comments by line ({ text, alone = nothing else on the line }).
-- ponytail: no long strings ([[ ]]) as values; a value written that way just isn't listed.
local function tokens(src)
    local out, notes, i, line, n = {}, {}, 1, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c == '\n' then
            line, i = line + 1, i + 1
        elseif c:match('%s') then
            i = i + 1
        elseif src:sub(i, i + 1) == '--' then
            local eq = src:match('^%-%-%[(=*)%[', i)
            if eq then -- a block comment
                local close = ']' .. eq .. ']'
                local e = src:find(close, i, true) or n
                for _ in src:sub(i, e):gmatch('\n') do line = line + 1 end
                i = e + #close
            else
                local e = (src:find('\n', i, true) or n + 1) - 1
                notes[line] = { text = src:sub(i + 2, e):match('^%-*%s*(.-)%s*$'), alone = not out[1] or out[#out].line ~= line }
                i = e + 1
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n and src:sub(j, j) ~= c do j = j + (src:sub(j, j) == '\\' and 2 or 1) end
            out[#out + 1] = { t = 'str', s = i, e = j, line = line }
            i = j + 1
        elseif c:match('%d') or (c == '.' and src:sub(i + 1, i + 1):match('%d')) then
            local e = select(2, src:find('^0[xX]%x+', i)) or select(2, src:find('^%d*%.?%d*[eE][%+%-]?%d+', i))
                or select(2, src:find('^%d*%.?%d*', i))
            out[#out + 1] = { t = 'num', s = i, e = e, line = line }
            i = e + 1
        elseif c:match('[%a_]') then
            local e = select(2, src:find('^[%w_]+', i))
            local w = src:sub(i, e)
            out[#out + 1] = { t = (w == 'true' or w == 'false' or w == 'nil') and 'lit' or 'name', v = w, s = i, e = e, line = line }
            i = e + 1
        else
            out[#out + 1] = { t = 'op', v = c, s = i, e = i, line = line }
            i = i + 1
        end
    end
    return out, notes
end

local function read_literal(text)
    local fn = load('return ' .. text, 'config value', 't', {})
    if not fn then return false end
    return pcall(fn)
end

local function path_name(keys)
    local s = ''
    for _, k in ipairs(keys) do s = s .. (type(k) == 'number' and ('[' .. k .. ']') or (s == '' and k or '.' .. k)) end
    return s
end

-- Every plain value (number, string, true / false / nil) the file sets on Config, however deep in a table:
-- { keys, path, kind, value, s, e (where its text is), line, note (its line's comment), about (the comment above) },
-- and every list (a table with only unnamed entries): { keys, path, multi (one entry a line), items = { { s, e,
-- comma = where the comma after it ends, own_line = alone on its line(s) } } }.
local function parse(src)
    local tk, notes = tokens(src)
    local entries, lists, p = {}, {}, 1
    local function op(i, v) return tk[i] and tk[i].t == 'op' and tk[i].v == v end
    local function about(line) -- the comment lines straight above a statement
        local out = {}
        for l = line - 1, 1, -1 do
            if not (notes[l] and notes[l].alone) then break end
            table.insert(out, 1, notes[l].text)
        end
        return out[1] and table.concat(out, '\n') or nil
    end
    local function skip() -- something that isn't a plain value: up to the next , ; or closing bracket, or the next statement
        local depth, from = 0, tk[p] and tk[p].line
        while tk[p] do
            local t = tk[p]
            if t.t == 'op' and (t.v == '{' or t.v == '(' or t.v == '[') then depth = depth + 1
            elseif t.t == 'op' and (t.v == '}' or t.v == ')' or t.v == ']') then
                if depth == 0 then return end
                depth = depth - 1
            elseif depth == 0 and ((t.t == 'op' and (t.v == ',' or t.v == ';')) or (t.t == 'name' and t.line > from)) then
                return
            end
            p = p + 1
        end
    end
    local value
    local function tbl(keys, ab)
        local open, items, named = tk[p], {}, false
        p = p + 1
        local idx = 0
        while tk[p] and not op(p, '}') do
            local key
            if tk[p].t == 'name' and op(p + 1, '=') then
                key, p, named = tk[p].v, p + 2, true
            elseif op(p, '[') and tk[p + 1] and (tk[p + 1].t == 'str' or tk[p + 1].t == 'num') and op(p + 2, ']') and op(p + 3, '=') then
                key = select(2, read_literal(src:sub(tk[p + 1].s, tk[p + 1].e)))
                p, named = p + 4, true
            else
                idx = idx + 1
                key = idx
            end
            local child = {}
            for i, k in ipairs(keys) do child[i] = k end
            child[#child + 1] = key
            local first = p
            value(child, ab)
            local comma = (op(p, ',') or op(p, ';')) and tk[p] or nil
            if key == idx and p > first then
                local after = tk[comma and p + 1 or p]
                items[#items + 1] = { s = tk[first].s, e = tk[p - 1].e, comma = comma and comma.e,
                                      own_line = tk[first - 1].line < tk[first].line and (not after or after.line > tk[p - 1].line) }
            end
            if comma then p = p + 1 end
        end
        if items[1] and not named then
            lists[#lists + 1] = { keys = keys, path = path_name(keys), items = items, multi = tk[p] and tk[p].line > open.line }
        end
        p = p + 1
    end
    value = function(keys, ab)
        if op(p, '{') then return tbl(keys, ab) end
        local first = p
        if op(p, '-') and tk[p + 1] and tk[p + 1].t == 'num' then p = p + 1 end
        local t, nx = tk[p], tk[p + 1]
        local plain = t and (t.t == 'num' or t.t == 'str' or t.t == 'lit')
            and not (nx and nx.t == 'op' and nx.v ~= ',' and nx.v ~= ';' and nx.v ~= '}') -- (not 60 * 1000)
        local ok, v = false, nil
        if plain then ok, v = read_literal(src:sub(tk[first].s, t.e)) end
        if not ok then
            p = first
            return skip()
        end
        local note = notes[t.line]
        entries[#entries + 1] = { keys = keys, path = path_name(keys), kind = type(v), value = v, s = tk[first].s, e = t.e,
                                  line = t.line, note = note and not note.alone and note.text or nil, about = ab }
        p = p + 1
    end
    while tk[p] do
        local t = tk[p]
        if t.t == 'name' and t.v == 'Config' and (p == 1 or tk[p - 1].line < t.line) then
            local keys, q = {}, p + 1
            while op(q, '.') and tk[q + 1] and tk[q + 1].t == 'name' do
                keys[#keys + 1] = tk[q + 1].v
                q = q + 2
            end
            if keys[1] and op(q, '=') and not op(q + 1, '=') then
                p = q + 1
                value(keys, about(t.line))
            else
                p = p + 1
            end
        else
            p = p + 1
        end
    end
    return entries, lists
end

-- A new value written the way the old one was: 9.0 stays 9.0-style, quotes stay as they were.
local function literal(old, v)
    if type(v) == 'number' then
        local s = ('%.14g'):format(v)
        if old:find('.', 1, true) and not s:find('[%.eE]') then s = s .. '.0' end
        return s
    end
    if type(v) == 'string' then
        local q = old:sub(1, 1) == '"' and '"' or "'"
        return q .. v:gsub('\\', '\\\\'):gsub(q, '\\' .. q) .. q
    end
    return tostring(v)
end

-- What the editor sent, as the value to write: the same kind as before. A blank text box on a named setting is nil.
local function accept(entry, v)
    local key = entry.keys[#entry.keys]
    if (entry.kind == 'string' or entry.kind == 'nil') and v == '' and type(key) == 'string' then return true, nil end
    if type(v) == 'string' then v = v:gsub('%c', ''):sub(1, 200) end -- (one line, kept short)
    if entry.kind == 'nil' and type(v) == 'string' then return true, v end
    if type(v) ~= entry.kind then return false end
    if type(v) == 'number' and (v ~= v or v == math.huge or v == -math.huge) then return false end
    return true, v
end

-- The file's text with a list's entry added (a copy of its last one, as written) or taken away (not its only one).
local function line_start(src, i) return src:sub(1, i - 1):match('.*\n()') or 1 end
local function list_edit(src, list, action, index)
    local items = list.items
    if action == 'add' then
        local last = items[#items]
        local copy = src:sub(last.s, last.e)
        if not list.multi then return src:sub(1, last.e) .. ', ' .. copy .. src:sub(last.e + 1) end
        local at = last.comma or last.e
        local indent = src:sub(line_start(src, last.s), last.s - 1):match('^%s*$') or '    '
        return src:sub(1, at) .. (last.comma and '' or ',') .. '\n' .. indent .. copy .. (last.comma and ',' or '') .. src:sub(at + 1)
    end
    local it = items[index]
    if action ~= 'remove' or not it or #items < 2 then return nil end
    if list.multi and it.own_line then -- its whole line(s), comment and all
        local stop = src:find('\n', it.comma or it.e, true) or #src
        return src:sub(1, line_start(src, it.s) - 1) .. src:sub(stop + 1)
    end
    if it.comma then return src:sub(1, it.s - 1) .. src:sub(it.comma + 1):gsub('^ *', '', 1) end
    return src:sub(1, items[index - 1].e) .. src:sub(it.e + 1) -- the last one: from the comma before it
end

-- What a config file sets, run on its own (nothing but Config to touch).
local function evaluate(src)
    local env = { Config = {} }
    local fn = load(src, 'config', 't', env)
    if fn and pcall(fn) then return env.Config end
end

local function get(t, keys)
    for _, k in ipairs(keys) do t = type(t) == 'table' and t[k] or nil end
    return t
end

local function set(keys, v)
    local t = Config
    for i = 1, #keys - 1 do t = type(t) == 'table' and t[keys[i]] or nil end
    if type(t) == 'table' then t[keys[#keys]] = v end
end

local changed = {} -- [file .. path] = { keys, value }: what's been changed since c3r started, for players joining later

local function allowed(src) return src > 0 and IsPlayerAceAllowed(src, 'command.c3rconfig') end

local function open(src, msg)
    local list = {}
    for _, f in ipairs(config_files()) do
        local entries, lists = {}, {}
        local all, all_lists = parse(LoadResourceFile(RES, f) or '')
        for _, e in ipairs(all) do
            entries[#entries + 1] = { path = e.path, kind = e.kind, value = e.value, note = e.note, about = e.about }
        end
        for _, l in ipairs(all_lists) do lists[#lists + 1] = { path = l.path, count = #l.items } end
        list[#list + 1] = { file = f, entries = entries, lists = lists }
    end
    TriggerClientEvent('c3r:config:open', src, list, msg)
end

RegisterCommand('c3rconfig', function(src)
    if allowed(src) then open(src) end
end, true)

-- changes = { { file, path, value } }: each written into its file, then set live everywhere.
RegisterNetEvent('c3r:config:save', function(changes)
    local src = source
    if not allowed(src) or type(changes) ~= 'table' or #changes > 500 then return end
    local files, live, failed = {}, {}, {}
    for _, f in ipairs(config_files()) do files[f] = true end
    for _, c in ipairs(changes) do
        local text = type(c) == 'table' and files[c.file] and LoadResourceFile(RES, c.file)
        local entry
        for _, e in ipairs(text and parse(text) or {}) do if e.path == c.path then entry = e break end end
        local ok, v = false, nil
        if entry then ok, v = accept(entry, c.value) end
        if ok then
            SaveResourceFile(RES, c.file, text:sub(1, entry.s - 1) .. literal(text:sub(entry.s, entry.e), v) .. text:sub(entry.e + 1), -1)
            set(entry.keys, v)
            changed[c.file .. ':' .. entry.path] = { keys = entry.keys, value = v }
            live[#live + 1] = { keys = entry.keys, value = v }
        else
            failed[#failed + 1] = type(c) == 'table' and tostring(c.path) or '?'
        end
    end
    if live[1] then TriggerClientEvent('c3r:config:set', -1, live) end
    print(('[c3r] %s changed %d config value(s) with /c3rconfig'):format(GetPlayerName(src) or src, #live))
    open(src, failed[1] and ('Not saved: ' .. table.concat(failed, ', ')) or ('Saved %d change%s.'):format(#live, #live == 1 and '' or 's'))
end)

-- A list's entry added or taken away: the file rewritten there, and the whole list set live again.
RegisterNetEvent('c3r:config:list', function(file, path, action, index)
    local src = source
    if not allowed(src) or type(file) ~= 'string' or type(path) ~= 'string' then return end
    local known = false
    for _, f in ipairs(config_files()) do known = known or f == file end
    local text = known and LoadResourceFile(RES, file)
    if not text then return end
    local list
    for _, l in ipairs(select(2, parse(text))) do if l.path == path then list = l break end end
    local new = list and list_edit(text, list, action, tonumber(index))
    local fresh = new and evaluate(new)
    local v = fresh and get(fresh, list.keys)
    if type(v) ~= 'table' then return open(src, 'Not saved: ' .. path) end
    SaveResourceFile(RES, file, new, -1)
    set(list.keys, v)
    local prefix = file .. ':' .. path
    for k in pairs(changed) do -- (its entries' own changes are in it now, and may be about other entries)
        if k:sub(1, #prefix + 1) == prefix .. '[' or k:sub(1, #prefix + 1) == prefix .. '.' then changed[k] = nil end
    end
    changed[prefix] = { keys = list.keys, value = v }
    TriggerClientEvent('c3r:config:set', -1, { { keys = list.keys, value = v } })
    print(('[c3r] %s %s %s with /c3rconfig'):format(GetPlayerName(src) or src, action == 'add' and 'added to' or 'took from', path))
    open(src, action == 'add' and ('Added to %s: a copy of its last entry, to edit.'):format(path) or ('Taken from %s.'):format(path))
end)

-- A player joining after a change: their game loaded the files as they were when c3r started.
RegisterNetEvent('c3r:config:sync', function()
    local list = {}
    for _, c in pairs(changed) do list[#list + 1] = c end
    if list[1] then TriggerClientEvent('c3r:config:set', source, list) end
end)
