-- c3r config: callouts. Dispatch puts out a call to every officer on duty; anyone can respond, and units on the same
-- call split its objectives between them. The calls themselves are in c3r/callouts/.

Config.Callouts = {
    enabled = true,
    every = { 240, 480 },   -- s between new calls, while anyone is on duty
    max_open = 2,           -- calls open at once
    min_distance = 400.0,   -- m: a new call is at least this far from the officer it's made near...
    max_distance = 2500.0,  -- ...and no further than this
    expire = 300,           -- s a call nobody responds to stays open
    offer_window = 30,      -- s the offer card stays up
    arrive = 40.0,          -- m from the call: on scene
    build = 300.0,          -- m: each person, car and prop is made when a unit gets this close to it
    max_minutes = 30,       -- a call still open after this long is cancelled
}
