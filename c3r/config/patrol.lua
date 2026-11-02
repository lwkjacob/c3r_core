-- c3r config: on patrol: staged violators, and booking at the stations.

-- Staged violators: on duty in your car, every so often a car near you starts driving to match its hidden story (a
-- drunk weaves, a stolen car speeds, a suspended licence runs the lights). No marker: you have to spot it.
Config.Staged = {
    enabled = true,
    every = { 180, 300 },  -- s between violators
    lasts = 90,            -- s it keeps it up (pull it over before then)
    fault = 0.35,          -- how often it's a car fault instead: a light out, a stuck blinker, a flat tyre
    -- what they're up to (relative weights, any numbers; a car already on file keeps its own story)
    secrets = { drunk = 4, stolen = 2, drugs = 2, warrant = 2, suspended = 2, unlicensed = 1, expired = 1, clean = 1 },
}

-- Arrested people in the back of your car are booked when you stop in the blue circle at any of these
-- (the circle shows while you have someone in custody). Positions are approximate: move them to suit.
Config.BookingRadius = 5.0 -- m
Config.Stations = {
    { name = 'Mission Row', x = 441.0, y = -985.0, z = 30.7 },
    { name = 'Vespucci', x = -1108.0, y = -845.0, z = 19.3 },
    { name = 'Davis', x = 360.0, y = -1584.0, z = 29.3 },
    { name = 'La Mesa', x = 826.0, y = -1290.0, z = 28.2 },
    { name = 'Vinewood', x = 638.0, y = 1.0, z = 82.8 },
    { name = 'Rockford Hills', x = -561.0, y = -132.0, z = 38.0 },
    { name = 'Sandy Shores', x = 1853.0, y = 3686.0, z = 34.3 },
    { name = 'Paleto Bay', x = -448.0, y = 6012.0, z = 31.7 },
    { name = 'Bolingbroke', x = 1846.0, y = 2585.0, z = 45.7 },
}
