--[[
    c3r medical call: SWIMMER IN DIFFICULTY.

    Someone pulled out of the sea. Coughing water up, or not breathing at all.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      coughing  Coughing up seawater, breathing fast and wet.
      gone      Pulled out still. Not breathing.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_drowning (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_drowning',
    name = 'Swimmer in difficulty',
    voice = 'call_drowning', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    reports = {
        'Caller says someone has been pulled out of the water.',
        'Swimmer in trouble, brought in to the beach.',
    },
    locations = {
        { street = 'Vespucci Beach', at = vector3(-1185.59, -1508.61, 4.38), points = {
            patient = vector4(-1185.59, -1508.61, 4.38, 1.9),
            nearby = vector4(-1184.79, -1508.01, 4.38, 0.0),
        } },
        { street = 'Vespucci Beach', at = vector3(-1189.95, -1490.42, 4.38), points = {
            patient = vector4(-1189.95, -1490.42, 4.38, 107.4),
            nearby = vector4(-1189.15, -1489.82, 4.38, 0.0),
        } },
        { street = 'Goma St', at = vector3(-1167.99, -1522.49, 4.40), points = {
            patient = vector4(-1167.99, -1522.49, 4.40, 349.0),
            nearby = vector4(-1167.19, -1521.89, 4.40, 0.0),
        } },
    },
    stories = {
        coughing = { weight = 3, conditions = { 'respiratory', 'airway' },
            says = 'Coughing up seawater, breathing fast and wet.', what = 'pulled from the sea', clue = { 'A towel', 'prop_beach_towel_01', 'A beach towel, left on the sand.' }, },
        gone = { weight = 2, arrest = true, conditions = { 'respiratory' },
            says = 'Pulled out still. Not breathing.', what = 'who drowned', clue = { 'A towel', 'prop_beach_towel_01', 'A beach towel, left on the sand.' }, },
    },
}))
