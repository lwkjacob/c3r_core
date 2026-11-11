Config = {}

Config.Debug = false -- true: F8 and the server console log what's placed and picked up

-- Who can use it is c3r's call, no aces of its own: on duty as police in c3r, on patrol (c3r's Config.DutyAce decides
-- who can go on). Scene ▸ is on c3r's G wheel; anyone on duty as police can pick up anyone's things.

-- What Scene ▸ places. id: its name in code (keep it). icon: cone, flare, barrier, post or tape. model: any prop (all four are in GTA's files: DurtyFree's ObjectList.ini).
-- slow: AI traffic slows near it. close: AI traffic can't drive through, the road under it is switched off.
-- Tape clicked onto any of these ties at its top (the tape post is for that: not seen in game yet, swap the model if it's wrong).
-- freeze: stays put when a car hits it (a knocked one would only move in that one game). flare: burns red, then goes out
-- (Config.FlareMinutes). tie: metres from its middle that tape counts as tied to it (picked up, the tape goes too).
Config.Props = {
    { id = 'cone', label = 'Cone', icon = 'cone', model = 'prop_roadcone02a', slow = true, close = false, freeze = true, flare = false, tie = 0.6 },
    { id = 'flare', label = 'Flare', icon = 'flare', model = 'prop_flare_01', slow = true, close = false, freeze = true, flare = true, tie = 0.6 },
    { id = 'police_barrier', label = 'Police barrier', icon = 'barrier', model = 'prop_barrier_work05', slow = true, close = true, freeze = true, flare = false, tie = 1.5 },
    { id = 'work_barrier', label = 'Work barrier', icon = 'barrier', model = 'prop_barrier_work06a', slow = true, close = true, freeze = true, flare = false, tie = 1.5 },
    { id = 'tape_post', label = 'Tape post', icon = 'post', model = 'prop_roadpole_01a', slow = false, close = false, freeze = true, flare = false, tie = 0.6 },
}

Config.Cap = 25          -- props and tape spans out at once, per officer
Config.FlareMinutes = 10 -- a flare burns this long, then it's gone
Config.Reach = 6.0       -- metres: how far in front of the officer a prop can go down
Config.PickupReach = 1.6 -- metres from a prop or a span of tape to pick it up
Config.DrawDistance = 150.0 -- metres: props and tape show within this

-- Rebindable in Settings > Key Bindings > FiveM. c3r's own E does nothing while something's in reach to pick up.
Config.Keys = {
    pickup = 'E',
}

-- AI traffic near cones, flares and barriers: one zone per group of them.
Config.Slow = {
    radius = 25.0, -- metres around the group
    speed = 2.5,   -- metres a second (2.5 is about 5 mph, a crawl)
}

-- Barriers switch the road off this far around them: cars route another way and none spawn there.
Config.Close = {
    radius = 6.0, -- metres
}

-- The flare's glow.
Config.FlareLight = {
    range = 6.0,     -- metres
    intensity = 4.0,
}

-- Police tape: strung from one point to the next.
Config.Tape = {
    max = 14.0,       -- metres a span can be
    height = 0.08,    -- metres, how wide the tape is
    ground = 0.9,     -- metres above the ground when it's tied to the ground itself
    sag = 0.02,       -- how much it droops: metres per metre of span (never more than 0.3 m)
    into = 0.15,      -- metres an end tied to a post, cone or barrier runs on into it (no gap where it's tied)
    wind = 1.0,       -- how much the game's wind moves it (0: still)
    styles = {
        { id = 'police', label = 'Police line', file = 'img/tape_police.png', colour = { 245, 196, 0 } },
        { id = 'crime', label = 'Crime scene', file = 'img/tape_crime.png', colour = { 25, 70, 190 } },
    },
}
