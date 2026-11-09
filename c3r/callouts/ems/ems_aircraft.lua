--[[
    c3r medical call: AIRCRAFT ACCIDENT.

    A light aircraft came down hard on the strip: the pilot is out, with broken legs, a chest wound, or smoke and a cut.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      landing   Pulled from the cockpit. Both legs hurt, dazed.
      chest     Thrown against the controls: a chest wound, short of breath.
      fire      Got out as it caught fire: coughing, their arm cut open.

    Spots marked rough are from memory: check them in game and move them with /c3rplace ems_aircraft.
]]

Callout(Ems.call({
    id = 'ems_aircraft',
    name = 'Aircraft accident',
    voice = 'call_aircraft', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    trauma = true, -- (now and then a wrist or ankle broken too: felt on the head-to-toe check)
    age = { 25, 70 },
    reports = {
        'Caller says a small plane has crashed on landing.',
        'Aircraft down at the airfield. The pilot is out of it but hurt.',
    },
    locations = {
        -- rough (placed from memory): check in game, move with /c3rplace ems_aircraft
        { street = 'Panorama Dr', at = vector3(1717.50, 3295.60, 41.20), points = {
            patient = vector4(1717.50, 3295.60, 41.20, 105.0),
            nearby = vector4(1718.30, 3296.20, 41.20, 0.0),
        } },
        -- rough (placed from memory): check in game, move with /c3rplace ems_aircraft
        { street = 'Panorama Dr', at = vector3(1747.00, 3279.00, 41.10), points = {
            patient = vector4(1747.00, 3279.00, 41.10, 105.0),
            nearby = vector4(1747.80, 3279.60, 41.10, 0.0),
        } },
        -- rough (placed from memory): check in game, move with /c3rplace ems_aircraft
        { street = 'Grapeseed Avenue', at = vector3(2121.00, 4794.00, 41.10), points = {
            patient = vector4(2121.00, 4794.00, 41.10, 290.0),
            nearby = vector4(2121.80, 4794.60, 41.10, 0.0),
        } },
    },
    stories = {
        landing = { weight = 2, conditions = { 'head', { 'fracture', 'lleg' }, { 'fracture', 'rleg' }, 'pain' },
            says = 'Pulled from the cockpit. Both legs hurt, dazed.', what = 'a pilot hurt in a hard landing', },
        chest = { weight = 1, conditions = { { 'hemorrhage', 'thorax' }, 'pneumothorax', 'pain' },
            says = 'Thrown against the controls: a chest wound, short of breath.', what = 'a pilot with a chest wound from a crash landing', },
        fire = { weight = 1, conditions = { 'respiratory', { 'hemorrhage', 'rarm' }, 'pain' },
            says = 'Got out as it caught fire: coughing, their arm cut open.', what = 'a pilot who got out of a burning aircraft', clue = { 'A fuel can', 'prop_jerrycan_01a', 'A fuel can, scorched black.' }, },
    },
}))
