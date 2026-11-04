--[[
    c3r medical call: SPORTS INJURY.

    Hurt playing sport or working out. A broken leg, a heart that gave out mid-workout, or a weight dropped on the chest.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      leg       Clutching their shin, lower leg bent.
      heart     Grey, sweating, chest tight.
      weights   Wincing with every breath after a bar fell on their chest.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_sports (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_sports',
    name = 'Sports injury',
    voice = 'call_sports', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    age = { 16, 60 },
    reports = {
        'Caller says someone got hurt while exercising.',
        'Person down while working out. They are in pain.',
    },
    locations = {
        { street = 'Vespucci Beach', at = vector3(-1185.59, -1508.61, 4.38), points = {
            patient = vector4(-1185.59, -1508.61, 4.38, 1.9),
            nearby = vector4(-1184.79, -1508.01, 4.38, 0.0),
        } },
        { street = 'Mirror Park', at = vector3(1087.51, -468.35, 64.76), points = {
            patient = vector4(1087.51, -468.35, 64.76, 121.0),
            nearby = vector4(1088.31, -467.75, 64.76, 0.0),
        } },
        { street = 'Legion Square', at = vector3(190.00, -938.00, 30.70), points = {
            patient = vector4(190.00, -938.00, 30.70, 40.0),
            nearby = vector4(190.80, -937.40, 30.70, 0.0),
        } },
    },
    stories = {
        leg = { weight = 3, conditions = { { 'fracture', 'rleg' }, 'pain' },
            says = 'Clutching their shin, lower leg bent.', what = 'with a broken leg from sport', },
        heart = { weight = 1, conditions = { 'cardiac' },
            says = 'Grey, sweating, chest tight.', what = 'who had a heart attack while exercising', clue = { 'A water bottle', 'prop_ld_flow_bottle', 'A water bottle, dropped mid-workout.' }, },
        weights = { weight = 1, conditions = { 'pain', 'respiratory' },
            says = 'Wincing with every breath after a bar fell on their chest.', what = 'hurt by a weight dropped on their chest', clue = { 'A barbell', 'prop_barbell_20kg', 'A barbell, lying where it fell.' }, },
    },
}))
