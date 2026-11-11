--[[
    lwk_scene — shared: the sums both sides need, on plain { x, y, z } (vector3s work too). BY LWK DEVELOPMENT
    An item: { id, owner (server id), kind = 'prop', prop (Config.Props id), pos, h } or { id, owner, kind = 'tape', style, a, b }.
]]

Scene = {}

-- Config.Props / Config.Tape.styles by id, kept in step with /c3rconfig (c3r:configSet)
Scene.props, Scene.styles = {}, {}
function Scene.index()
    Scene.props, Scene.styles = {}, {}
    for _, p in ipairs(Config.Props) do Scene.props[p.id] = p end
    for _, s in ipairs(Config.Tape.styles) do Scene.styles[s.id] = s end
end
Scene.index()
if IsDuplicityVersion and IsDuplicityVersion() then AddEventHandler('c3r:configSet', function() Scene.index() end)
elseif RegisterNetEvent then RegisterNetEvent('c3r:configSet', function() Scene.index() end) end

local function d2(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
Scene.dist2d = d2

-- p's distance from the line a-b, flat (heights only have to be near: within 3 m)
function Scene.segDist(p, a, b)
    local abx, aby, apx, apy = b.x - a.x, b.y - a.y, p.x - a.x, p.y - a.y
    local l2 = abx * abx + aby * aby
    local t = l2 > 0 and math.max(0, math.min(1, (apx * abx + apy * aby) / l2)) or 0
    local z = a.z + (b.z - a.z) * t
    if math.abs(p.z - z) > 3.0 then return math.huge end
    return math.sqrt((apx - abx * t) ^ 2 + (apy - aby * t) ^ 2)
end

-- how far p is from an item: a prop's spot, a span of tape
function Scene.itemDist(it, p)
    if it.kind == 'tape' then return Scene.segDist(p, it.a, it.b) end
    if math.abs(p.z - it.pos.z) > 3.0 then return math.huge end
    return d2(p, it.pos)
end

-- how many an officer has out
function Scene.count(items, owner)
    local n = 0
    for _, it in pairs(items) do if it.owner == owner then n = n + 1 end end
    return n
end

-- does the tape end at (is it tied to) this prop, within r of its middle? (a cone picked up takes its tape with it)
function Scene.tiedTo(it, pos, r)
    if it.kind ~= 'tape' then return false end
    for _, e in ipairs({ it.a, it.b }) do
        if d2(e, pos) < (r or 0.6) and math.abs(e.z - pos.z) < 1.5 then return true end
    end
    return false
end

-- Groups of points for the traffic zones: each joins the first group whose first point is within r.
-- -> { { x, y, z, spread (furthest member from the middle) } }
function Scene.clusters(points, r)
    local groups = {}
    for _, p in ipairs(points) do
        local g
        for _, c in ipairs(groups) do if d2(c[1], p) <= r then g = c break end end
        if g then g[#g + 1] = p else groups[#groups + 1] = { p } end
    end
    local out = {}
    for _, g in ipairs(groups) do
        local x, y, z = 0, 0, 0
        for _, p in ipairs(g) do x, y, z = x + p.x, y + p.y, z + p.z end
        local c = { x = x / #g, y = y / #g, z = z / #g, spread = 0 }
        for _, p in ipairs(g) do c.spread = math.max(c.spread, d2(c, p)) end
        out[#out + 1] = c
    end
    return out
end
