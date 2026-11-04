--[[
    c3r medical call: DIABETIC EMERGENCY.

    A diabetic with low blood sugar: confused, maybe hurt in a fall when they went down.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      low       Drenched in sweat, mumbling nonsense.
      fell      Confused, a cut on the head from the fall.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_diabetic (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_diabetic',
    name = 'Diabetic emergency',
    voice = 'call_diabetic', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    reports = {
        'Caller says a diabetic is acting confused and will not answer properly.',
        'Person sweating and confused. Someone shouted that they are diabetic.',
    },
    locations = {
        { street = 'Davis Ave', at = vector3(-52.11, -1760.34, 29.14), points = {
            patient = vector4(-52.11, -1760.34, 29.14, 93.8),
            nearby = vector4(-51.31, -1759.74, 29.14, 0.0),
        } },
        { street = 'Algonquin Blvd', at = vector3(1392.36, 3597.45, 35.04), points = {
            patient = vector4(1392.36, 3597.45, 35.04, 209.6),
            nearby = vector4(1393.16, 3598.05, 35.04, 0.0),
        } },
        { street = 'Strawberry Ave', at = vector3(138.36, -1301.14, 29.20), points = {
            patient = vector4(138.36, -1301.14, 29.20, 183.7),
            nearby = vector4(139.16, -1300.54, 29.20, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-98.27, 6540.20, 29.81), points = {
            patient = vector4(-98.27, 6540.20, 29.81, 135.1),
            nearby = vector4(-97.47, 6540.80, 29.81, 0.0),
        } },
    },
    stories = {
        low = { weight = 3, conditions = { 'hypoglycemia' },
            says = 'Drenched in sweat, mumbling nonsense.', what = 'a diabetic with low blood sugar', clue = { 'A bag', 'prop_ld_handbag', 'A bag, open. An insulin pen, no snacks.' }, },
        fell = { weight = 2, conditions = { 'hypoglycemia', 'head', { 'hemorrhage', 'head' }, 'pain' },
            says = 'Confused, a cut on the head from the fall.', what = 'a diabetic who fell when their sugar dropped', },
    },
}))
