--[[
    c3r medical call: ASSAULT VICTIM.

    Someone attacked and left. Stabbed in the belly, beaten, or stabbed in the chest. Whoever did it is gone.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      stabbed   Holding their belly, blood through their fingers.
      beaten    Dazed, face swelling, holding their arm.
      chest     Gasping. Bubbles of blood at a wound in the chest.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_assault (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_assault',
    name = 'Assault victim',
    voice = 'call_assault', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    age = { 18, 60 },
    reports = {
        'Caller says someone has been attacked. The attacker ran off.',
        'Person hurt after a fight. Nobody else around now.',
    },
    locations = {
        { street = 'Grove St', at = vector3(-58.50, -1843.00, 26.60), points = {
            patient = vector4(-58.50, -1843.00, 26.60, 117.0),
            nearby = vector4(-57.70, -1842.40, 26.60, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-293.78, 6250.79, 31.33), points = {
            patient = vector4(-293.78, 6250.79, 31.33, 184.1),
            nearby = vector4(-292.98, 6251.39, 31.33, 0.0),
        } },
        { street = 'Calais Ave', at = vector3(-544.06, -1211.55, 17.58), points = {
            patient = vector4(-544.06, -1211.55, 17.58, 86.1),
            nearby = vector4(-543.26, -1210.95, 17.58, 0.0),
        } },
        { street = 'Invention Ct', at = vector3(-980.60, -1113.60, 2.15), points = {
            patient = vector4(-980.60, -1113.60, 2.15, 23.1),
            nearby = vector4(-979.80, -1113.00, 2.15, 0.0),
        } },
    },
    stories = {
        stabbed = { weight = 2, conditions = { { 'hemorrhage', 'abdomen' }, 'pain' },
            says = 'Holding their belly, blood through their fingers.', what = 'stabbed in the stomach', clue = { 'A knife', 'prop_cs_bowie_knife', 'A knife, blood on the blade.' }, },
        beaten = { weight = 2, conditions = { 'head', { 'fracture', 'rarm' }, 'pain' },
            says = 'Dazed, face swelling, holding their arm.', what = 'beaten up', },
        chest = { weight = 1, conditions = { { 'hemorrhage', 'thorax' }, 'pneumothorax', 'pain' },
            says = 'Gasping. Bubbles of blood at a wound in the chest.', what = 'stabbed in the chest', clue = { 'A bottle', 'prop_cs_beer_bot_01', 'A broken bottle, the jagged end bloody.' }, },
    },
}))
