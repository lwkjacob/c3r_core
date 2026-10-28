-- c3r config: AI backup and the tow truck.

-- AI backup (lwk_control's radio: "I need an ambulance", "send a transport unit", "request backup", "air support"...).
-- Model names from FiveM's game references (docs.fivem.net/docs/game-references/). One unit of each kind at a time.
Config.Backup = {
    spawn = { 150.0, 210.0 },   -- m from the scene a unit appears, out of your sight
    speed = 25.0,               -- m/s on lights and siren (others drive at 15)
    timeout = 120,              -- s to get there; stuck in traffic, it turns up anyway
    job_timeout = 90,           -- s the work at the scene may take before they pack up
    cover_minutes = 5,          -- a cover unit stands by this long at most
    pursuit = { light = 1, medium = 2, heavy = 3, max = 6 }, -- cars per request, and at most in a chase
    units = {
        police = { car = 'policet', crew = { 's_m_y_cop_01', 's_m_y_cop_01' }, lights = true },        -- prisoner transport
        ambulance = { car = 'ambulance', crew = { 's_m_m_paramedic_01', 's_m_m_paramedic_01' }, lights = true },
        fire = { car = 'firetruk', crew = { 's_m_y_fireman_01', 's_m_y_fireman_01' }, lights = true },
        coroner = { car = 'speedo', crew = { 's_m_m_doctor_01', 's_m_m_scientist_01' } },
        mechanic = { car = 'burrito3', crew = { 's_m_y_xmech_01' } },
        roadservice = { car = 'utillitruck3', crew = { 's_m_y_xmech_02' } },
        animalrescue = { car = 'pranger', crew = { 's_m_y_ranger_01' } },
        taxi = { car = 'taxi', crew = { 'a_m_y_stlat_01' } },
        cover = { car = 'police3', crew = { 's_m_y_cop_01' }, lights = true, muted = true },
        pursuit = { cars = { 'police', 'police2', 'police3' }, crew = { 's_m_y_cop_01', 's_m_y_cop_01' }, lights = true },
        air = { car = 'polmav', crew = { 's_m_y_pilot_01' } },
    },
}
-- Each unit above can also say how it looks (all optional, any unit, the tow truck too):
--   livery = 1                             the vehicle's livery (on police cars, the decal set)
--   colours = { 111, 0 }                   paint: primary, secondary (GTA colour ids)
--   extras = { [1] = true, [2] = false }   the vehicle's extras on / off (light bars, push bars: depends on the car)
--   outfit = { [11] = { 0, 0 } }           what the crew wear: component = { drawable, texture }
--                                          (3 arms, 4 legs, 6 shoes, 8 undershirt, 9 vest, 11 jacket)
--   props = { [0] = { 1, 0 } }             hats and glasses: prop = { drawable, texture } (0 hat, 1 glasses)
-- e.g.  Config.Backup.units.cover.livery = 2
Config.Backup.spikes = 0.5 -- in a car chase, how often a pursuit request's first car lays a Stop Stick up ahead (needs lwk_stopstick)

-- The tow truck: it comes up the road from `distance` m behind the car; stuck for `timeout_ms`, it turns up anyway.
Config.Tow = { truck = 'flatbed', driver = 's_m_m_trucker_01', distance = 120.0, timeout_ms = 90000 }
Config.Tow.tries = 3 -- failed tows of the same car before it's just removed
