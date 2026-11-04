-- c3r config: the basics. Loaded first (it makes Config); the other files in this folder add to it.
-- Every file here is plain Lua, read by both the server and the players' games: edit, then restart c3r.

Config = {}

Config.Debug = false

-- /duty toggles your police shift. nil ace = anyone can go on duty; set one (e.g. 'c3r.police')
-- and grant it with  add_ace group.police c3r.police allow  to restrict it.
Config.DutyCommand = 'duty'
Config.DutyKey = 'F11' -- the service screen: pick a service to go on duty, or end the shift
Config.DutyAce = nil

-- Keys (players rebind them in Settings -> Key Bindings -> FiveM -> c3r). A change here only reaches players who
-- haven't got that key saved yet: a game keeps the binding it first saw.
Config.TargetKey = 'LSHIFT' -- in a police vehicle: the red circle ahead; drive it under a car to pick it (again: cancel)
Config.ModeKey = 'U'        -- during a stop: what the driver does (follow in front / behind, steer, halt, cancel)
Config.InteractKey = 'E'    -- on foot, beside a car or a person: talk to them
Config.RadialKey = 'G'      -- pressed: on foot at a car, its radial menu (search, tow, everyone out / in); anywhere else, the dispatch wheel
Config.RespondKey = 'Y'     -- a callout offered: respond to it
Config.ObjectiveKey = 'BACK' -- on a callout: hide / show the objective card
Config.LeaveCallKey = 'X'   -- a callout offered: decline it; on a callout: leave the call (asks first)
Config.IdCardKey = 'BACK'   -- someone's ID or registration showing: hide / show it (first, if it's the same key as ObjectiveKey)

-- The officer's lines out loud (asking for ID, the Miranda rights, a search, the breathalyzer): heard this far (m)
-- by any player, quieter further off; volume 0-1 (0 = off). The clips are nui/voice/officer_*.ogg.
Config.Voice = { range = 20.0, volume = 1.0 }
