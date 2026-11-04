--[[
    c3r medical call: PERSON NOT BREATHING.

    Found not breathing, no pulse. A heart that stopped, an overdose, or a massive bleed from a fall.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      heart     Not breathing. No pulse.
      overdose  Not breathing. Blue lips.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_arrest (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_arrest',
    name = 'Person not breathing',
    voice = 'call_arrest', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    age = { 30, 85 },
    reports = {
        'Caller says someone is not breathing. They are not moving at all.',
        'Person collapsed and is not breathing. Caller hung up to try CPR.',
    },
    locations = {
        { street = 'Forum Dr', at = vector3(-14.20, -1442.90, 31.10), points = {
            patient = vector4(-14.20, -1442.90, 31.10, 160.4),
            nearby = vector4(-13.40, -1442.30, 31.10, 0.0),
        } },
        { street = 'Senora Fwy', at = vector3(2634.11, 3291.89, 55.73), points = {
            patient = vector4(2634.11, 3291.89, 55.73, 174.3),
            nearby = vector4(2634.91, 3292.49, 55.73, 0.0),
        } },
        { street = 'Mirror Park', at = vector3(1087.51, -468.35, 64.76), points = {
            patient = vector4(1087.51, -468.35, 64.76, 121.0),
            nearby = vector4(1088.31, -467.75, 64.76, 0.0),
        } },
        { street = 'Procopio Dr', at = vector3(-221.82, 6403.79, 31.39), points = {
            patient = vector4(-221.82, 6403.79, 31.39, 204.6),
            nearby = vector4(-221.02, 6404.39, 31.39, 0.0),
        } },
    },
    stories = {
        heart = { weight = 3, arrest = true, conditions = { 'cardiac' },
            says = 'Not breathing. No pulse.', what = 'whose heart stopped', },
        overdose = { weight = 2, arrest = true, secret = 'drugs', conditions = { 'opioid' },
            says = 'Not breathing. Blue lips.', what = 'who stopped breathing after an overdose', clue = { 'A needle', 'p_syringe_01_s', 'A used needle beside them.' }, },
    },
}))
