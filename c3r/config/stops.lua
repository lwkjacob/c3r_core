-- c3r config: traffic stops: picking the car, how it pulls over, the mode key, orders, felony stops, running.

-- Picking the car to stop.
Config.Target = {
    distance = 9.0,        -- m ahead of the patrol car the circle sits
    radius = 2.6,          -- m: a car whose centre is this close to the circle is picked
    lose_distance = 60.0,  -- m: let the picked car get this far away and it's let go
    color = { 200, 72, 66 }, -- the circle: a muted red
}

-- How the AI pulls over. These are tuning knobs: GTA's driving AI differs per road, so adjust them
-- if drivers stop too far, too short, or in the lane.
Config.Pullover = {
    ahead = 30.0,          -- m: where they aim to stop, ahead of where they were
    kerb_gap = 0.35,       -- m: between the car's right side and the kerb when they've stopped
    kerb_inset = 1.4,      -- m: roads with no kerb: how far in from GTA's road edge they stop
    straighten = 7.0,      -- m: the slow glide along the kerb onto the final spot
    glide = 1.0,           -- m: how far out from the kerb they aim before that glide (stops nose-in parking)
    speed = 7.0,           -- m/s while pulling over (~15 mph)
    -- Straight at each point, no route-finding: on divided and one-way roads the route to a kerb point can
    -- be a U-turn or a long detour. Still stops for cars and people and steers round parked cars:
    -- StopForCars 1 + StopForPeds 2 + SteerAroundStationaryCars 8 + SteerAroundObjects 32 +
    -- ForceStraightLine 16777216. (No StopAtLights 128: they're being pulled over.)
    driving_style = 16777259,
    bend_style = 786475,   -- on a bend: normal road-following driving (still no waiting at red lights)
    timeout_ms = 15000,    -- give up steering for the kerb and just stop
}
Config.CancelDistance = 150.0 -- m: drive this far from the stop and it's cancelled

-- The mode key's driving modes.
Config.Modes = {
    speed = 12.0,       -- m/s (~27 mph) top speed while following in front / behind
    gap = 4.0,          -- m they keep from your car while following
    steer_speed = 8.0,  -- m/s (~18 mph) top speed while you steer them with the arrow keys
}

-- Roadside tests. bac_limit: at or over this, the breathalyzer shows over the limit.
Config.Tests = { bac_limit = 0.08 }

-- Not everyone goes quietly. Chances by hidden truth (0-1; missing = never).
Config.Flee = {
    car = { warrant = 0.3, stolen = 0.4, drugs = 0.1, drunk = 0.08, suspended = 0.08, unlicensed = 0.05 }, -- run instead of pulling over
    foot = { warrant = 0.25, stolen = 0.25, drugs = 0.1 }, -- run when ordered out, or when you go to cuff them
    bail = 0.5,               -- a car chase that ends: they run for it on foot instead of giving up
    refuse = 0.35,            -- rude, or with something to hide: refuse the first order to get out
    lose_distance = 250.0,    -- m: further than this for 10 s and they got away
    catch_distance = 2.5,     -- m: on foot, this close and they give up
}

-- Shouted orders (the PA, a felony stop) reach this far; talking to someone still needs you beside them.
Config.PaRange = 40.0 -- m

-- Felony stops (G at a stopped car, or "felony stop" on the PA): each person is ordered out, walked back and put on
-- their knees, one at a time. Chances by hidden truth (0-1).
Config.Felony = {
    freeze = 0.2,                                        -- doesn't move the first time they're told (asked again: they do)
    run = { warrant = 0.3, stolen = 0.3, drugs = 0.15 }, -- bolts on foot instead (once)
    drive = { stolen = 0.2, warrant = 0.15 },            -- the driver floors it when the felony stop starts
}
