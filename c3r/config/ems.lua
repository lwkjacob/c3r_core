-- c3r config: the Ambulance role.

-- /duty ambulance or the F11 card. ace = nil: anyone can; set one (e.g. 'c3r.ambulance') to limit it.
-- A shift brings the vehicle to the road beside you and puts you in uniform; ending it takes both back.
Config.Ems = {
    ace = nil,
    vehicle = 'ambulance',
    uniform = true,                 -- false: keep what you're wearing (a server with its own clothing script)
    ped = 's_m_m_paramedic_01',     -- the uniform, for a player who isn't an online character
    -- An online character (mp_m_freemode_01, mp_f_freemode_01) keeps their face and only changes clothes, as a backup
    -- unit's crew does (config/backup.lua): outfit = { [11] = { 0, 0 } }, props = { [0] = { 1, 0 } }. Empty: no change.
    outfit_m = {},
    outfit_f = {},
}

-- What's in the bag, in hotbar order. count: how many, restocked at the ambulance. No count: it never runs out.
Config.Ems.tools = {
    { id = 'stethoscope', label = 'Stethoscope', icon = 'pulse' },
    { id = 'shears', label = 'Trauma shears', icon = 'bandage' },
    { id = 'tourniquet', label = 'Tourniquet', icon = 'bandage', count = 2 },
    { id = 'dressing', label = 'Trauma dressing', icon = 'bandage', count = 4 },
    { id = 'splint', label = 'Splint', icon = 'bandage', count = 2 },
    { id = 'airway', label = 'Airway', icon = 'medic', count = 2 },
    { id = 'oxygen', label = 'Oxygen', icon = 'medic' },
    { id = 'narcan', label = 'Narcan', icon = 'medic', count = 2 },
    { id = 'glucose', label = 'Glucose', icon = 'medic', count = 2 },
    { id = 'cpr', label = 'CPR', icon = 'cpr' },
    { id = 'defib', label = 'Defib', icon = 'pulse', count = 2 },
}
Config.Ems.use_ms = 3000            -- how long a tool that helps takes
Config.Ems.wrong_ms = 1500          -- how long a wrong one costs

-- The clock: minutes from fine to their heart stopping, with something serious left untreated. Then arrest_seconds of
-- arrest before they're gone. revive: how often CPR and the defib bring back someone found dead.
Config.Ems.arrest_minutes = 4
Config.Ems.arrest_seconds = 120
Config.Ems.revive = 0.6
Config.Ems.grade = { 6, 12 }        -- minutes from starting treatment to the handover: excellent, good

-- The first model of each list that your server's game build has. All UNVERIFIED by eye: swap the order to taste.
Config.Ems.bag = { 'xm_prop_x17_bag_med_01a', 'prop_med_bag_01', 'h4_prop_h4_med_bag_01b' }
Config.Ems.stretcher = { 'm25_2_prop_m52_gurney_01a', 'm23_2_prop_m32_lgstretcher_01a', 'v_med_trolley' }
Config.Ems.cam_height = 2.6         -- m above the patient, on the treatment screen
Config.Ems.lie_height = 0.35        -- m above the stretcher's top that a patient lies
Config.Ems.lie_turn = 0.0           -- degrees: turn them on the stretcher, if they lie across it

-- Patients are handed over at the door (the marker) of the nearest of these, after stopping within hospital_radius m.
-- Positions are approximate: move them to suit.
Config.Ems.hospital_radius = 30.0
Config.Hospitals = {
    { name = 'Pillbox Hill', x = 357.4, y = -593.4, z = 28.8 },
    { name = 'Central Los Santos', x = 295.8, y = -1446.9, z = 29.97 },
    { name = 'Mount Zonah', x = -449.7, y = -340.8, z = 34.5 },
    { name = 'Sandy Shores', x = 1839.6, y = 3672.9, z = 34.3 },
    { name = 'Paleto Bay', x = -247.8, y = 6331.2, z = 32.4 },
}
