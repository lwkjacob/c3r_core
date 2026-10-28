-- The deployed sleeve as a physics chain: 4 joints (1 = cord end/grommet, 2 and 3 = the stitched waists, 4 = far
-- end) with the 3 sticks between them. Shared by server and clients and stepped at a fixed rate in plain numbers, so
-- every machine computes the same result: the server knows where it ends up, every client draws the same motion.

local LENS = { 0.975, 1.0, 0.975 }  -- stick lengths joint to joint (models/build_stopstick.py JOINTS)
local DT = 1.0 / 120.0
local DAMP = math.exp(-6.0 * DT)    -- ground friction: a sliding stick loses ~63% of its speed every 1/6 s
local SETTLE = 0.9                  -- seconds the sticks keep skidding after the cord end has stopped
local FOLD = 0.55                   -- a joint can't fold tighter than this (keeps the sticks from passing through each other)

StopStickLens, StopStickDT = LENS, DT

-- resting chain from the cord end and each stick's heading (degrees)
function StopStickChain(x, y, angles)
    local c = { x = { x }, y = { y } }
    for i = 1, 3 do
        local a = math.rad(angles[i])
        c.x[i + 1] = c.x[i] + math.cos(a) * LENS[i]
        c.y[i + 1] = c.y[i] + math.sin(a) * LENS[i]
    end
    return c
end

function StopStickCopy(c) return { x = { table.unpack(c.x) }, y = { table.unpack(c.y) } } end

function StopStickCenter(c)
    return (c.x[1] + c.x[2] + c.x[3] + c.x[4]) / 4.0, (c.y[1] + c.y[2] + c.y[3] + c.y[4]) / 4.0
end

-- one yank: full speed (Config.YankSpeed) the instant the cord goes taut, then even friction to a stop
function StopStickYankTime(dist) return math.min(math.max(2.0 * dist / Config.YankSpeed, 0.25), 1.2) end

function StopStickYankStart(c, dx, dy, dist)
    local s = StopStickCopy(c)
    s.px, s.py = { table.unpack(c.x) }, { table.unpack(c.y) } -- previous positions (verlet): starts at rest
    s.lx, s.ly, s.dx, s.dy, s.dist = c.x[1], c.y[1], dx, dy, dist
    s.dur = StopStickYankTime(dist)
    s.n, s.steps = 0, math.ceil((s.dur + SETTLE) / DT)
    return s
end

local function keep(s, i, j, len, wi, wj) -- move joints i/j (weights wi/wj) so they are len apart
    local dx, dy = s.x[j] - s.x[i], s.y[j] - s.y[i]
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-6 then return end
    local k = (d - len) / d
    s.x[i], s.y[i] = s.x[i] + dx * k * wi, s.y[i] + dy * k * wi
    s.x[j], s.y[j] = s.x[j] - dx * k * wj, s.y[j] - dy * k * wj
end

-- advance one fixed step; returns true when the chain has come to rest
function StopStickYankStep(s)
    s.n = s.n + 1
    local k = math.min(s.n * DT / s.dur, 1.0)
    local f = s.dist * k * (2.0 - k)
    s.px[1], s.py[1] = s.x[1], s.y[1]
    s.x[1], s.y[1] = s.lx + s.dx * f, s.ly + s.dy * f -- the cord end follows the hand's yank
    for i = 2, 4 do                                    -- the rest: momentum, bled off by the road
        local vx, vy = (s.x[i] - s.px[i]) * DAMP, (s.y[i] - s.py[i]) * DAMP
        s.px[i], s.py[i] = s.x[i], s.y[i]
        s.x[i], s.y[i] = s.x[i] + vx, s.y[i] + vy
    end
    for _ = 1, 8 do
        keep(s, 1, 2, LENS[1], 0.0, 1.0) -- the cord end is held by the cord
        keep(s, 2, 3, LENS[2], 0.5, 0.5)
        keep(s, 3, 4, LENS[3], 0.5, 0.5)
        for i = 1, 2 do                  -- fold limit across each waist
            local dx, dy = s.x[i + 2] - s.x[i], s.y[i + 2] - s.y[i]
            local min = FOLD * (LENS[i] + LENS[i + 1])
            if dx * dx + dy * dy < min * min then keep(s, i, i + 2, min, i == 1 and 0.0 or 0.5, i == 1 and 1.0 or 0.5) end
        end
    end
    return s.n >= s.steps
end

-- run a whole yank (server): the resting chain it ends in
function StopStickYankFinal(c, dx, dy, dist)
    local s = StopStickYankStart(c, dx, dy, dist)
    while not StopStickYankStep(s) do end
    return { x = s.x, y = s.y }, s
end
