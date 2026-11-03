-- c3r config: the Ambulance role.

-- /duty ambulance or the F11 card. ace = nil: anyone can; set one (e.g. 'c3r.ambulance') to limit it.
-- A shift brings the vehicle to the road beside you and puts you in uniform; ending it takes both back.
Config.Ems = {
    ace = nil,
    vehicle = 'f450ambo',
    uniform = true,                 -- false: keep what you're wearing (a server with its own clothing script)
    ped = 's_m_m_paramedic_01',     -- the uniform, for a player who isn't an online character
    -- An online character (mp_m_freemode_01, mp_f_freemode_01) keeps their face and only changes clothes, as a backup
    -- unit's crew does (config/backup.lua): outfit = { [11] = { 0, 0 } }, props = { [0] = { 1, 0 } }. Empty: no change.
    outfit_m = {},
    outfit_f = {},
}

-- What's in the bag, by pouch (group: assess, treat, airway, drugs), in order. count: how many, restocked at the
-- ambulance; no count: it never runs out. part = true: used on a body part (pick one first); at: always on that part.
Config.Ems.tools = {
    { id = 'hands', label = 'Hands', icon = 'hand', group = 'assess', part = true },
    { id = 'look', label = 'Look', icon = 'search', group = 'assess', part = true },
    { id = 'ask', label = 'Ask', icon = 'talk', group = 'assess', at = 'head' },
    { id = 'pulse', label = 'Pulse', icon = 'pulse', group = 'assess', part = true },
    { id = 'stethoscope', label = 'Stethoscope', icon = 'pulse', group = 'assess', part = true },
    { id = 'penlight', label = 'Pen light', icon = 'search', group = 'assess', part = true },
    { id = 'glucometer', label = 'Glucometer', icon = 'test', group = 'assess', part = true },
    { id = 'shears', label = 'Trauma shears', icon = 'bandage', group = 'assess', part = true },
    { id = 'tourniquet', label = 'Tourniquet', icon = 'bandage', group = 'treat', part = true, count = 2 },
    { id = 'dressing', label = 'Trauma dressing', icon = 'bandage', group = 'treat', part = true, count = 4 },
    { id = 'splint', label = 'Splint', icon = 'bandage', group = 'treat', part = true, count = 2 },
    { id = 'monitor', label = 'Monitor', icon = 'pulse', group = 'treat' },
    { id = 'cpr', label = 'CPR', icon = 'cpr', group = 'treat' },
    { id = 'defib', label = 'Defib', icon = 'pulse', group = 'treat' },
    { id = 'suction', label = 'Suction', icon = 'medic', group = 'airway' },
    { id = 'opa', label = 'Oral airway', icon = 'medic', group = 'airway', count = 2 },
    { id = 'npa', label = 'Nasal airway', icon = 'medic', group = 'airway', count = 2 },
    { id = 'bvm', label = 'BVM', icon = 'medic', group = 'airway' },
    { id = 'igel', label = 'i-gel', icon = 'medic', group = 'airway', count = 1 },
    { id = 'laryngoscope', label = 'Laryngoscope', icon = 'search', group = 'airway' },
    { id = 'tube', label = 'ET tube', icon = 'medic', group = 'airway', count = 2 },
    { id = 'pull_tube', label = 'Pull tube', icon = 'out', group = 'airway' },
    { id = 'oxygen', label = 'Oxygen', icon = 'medic', group = 'drugs' },
    { id = 'morphine', label = 'Morphine', icon = 'medic', group = 'drugs', count = 2 },
    { id = 'epi', label = 'Epinephrine', icon = 'medic', group = 'drugs', count = 4 },
    { id = 'narcan', label = 'Narcan', icon = 'medic', group = 'drugs', count = 2 },
    { id = 'glucose', label = 'Glucose', icon = 'medic', group = 'drugs', count = 2 },
    { id = 'saline', label = 'Saline IV', icon = 'medic', group = 'drugs', count = 2 },
    { id = 'aspirin', label = 'Aspirin', icon = 'medic', group = 'drugs', count = 2 },
}
Config.Ems.use_ms = 3000            -- how long a tool that helps takes
Config.Ems.wrong_ms = 1500          -- how long a wrong one costs
Config.Ems.assess_ms = 2000         -- how long an assessment takes (hands, stethoscope, shears...)

-- revive: how often CPR and the defib bring back someone found dead (a fresh arrest does better).
Config.Ems.revive = 0.6
Config.Ems.grade = { 6, 12 }        -- minutes from starting treatment to the handover: excellent, good

-- The first model of each list that your server's game build has. All UNVERIFIED by eye: swap the order to taste.
Config.Ems.bag = { 'xm_prop_x17_bag_med_01a', 'prop_med_bag_01', 'h4_prop_h4_med_bag_01b' }
Config.Ems.stretcher = { 'c3r_gurney', 'm25_2_prop_m52_gurney_01a', 'm23_2_prop_m32_lgstretcher_01a', 'v_med_trolley' }
Config.Ems.cam_height = 2.6         -- m above the patient, on the treatment screen
Config.Ems.lie_height = 0.12        -- m above the stretcher's top that a patient's back lies
Config.Ems.lie_turn = 0.0           -- degrees, extra: they're turned head to the head end by themselves

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

-- The patient (server/ems_body.lua). bleed: % of their blood an untreated limb bleed loses a second (a body wound, 1.4x).
-- misplace: how often a tube goes into the wrong place. dead_minutes: arrest without a pulse back before they're gone.
-- cardiac_minutes: a heart attack with no aspirin, before it gets worse (then about 40 s of alarms, then it stops).
Config.Ems.bleed = 0.12
Config.Ems.misplace = 0.15
Config.Ems.dead_minutes = 10
Config.Ems.cardiac_minutes = 6
