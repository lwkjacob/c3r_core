--[[
    c3r medical call: DIFFICULTY BREATHING.

    Someone fighting for breath. Asthma or a chest infection, choking on food, or vomit after a drink.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      chest     Sitting forward, lips tinged blue, every breath a wheeze.
      choking   Hands at their throat, making no sound.
      vomit     Out cold on their back, gurgling.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_breathing (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_breathing',
    name = 'Difficulty breathing',
    voice = 'call_breathing', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    reports = {
        'Caller can barely speak. Says they cannot breathe.',
        'Person struggling to breathe, called in by a passer-by who did not stay.',
    },
    locations = {
        { street = 'Calafia Rd', at = vector3(92.51, 3744.59, 40.77), points = {
            patient = vector4(92.51, 3744.59, 40.77, 56.7),
            nearby = vector4(93.31, 3745.19, 40.77, 0.0),
        } },
        { street = 'Bridge St', at = vector3(878.73, -210.25, 70.78), points = {
            patient = vector4(878.73, -210.25, 70.78, 258.2),
            nearby = vector4(879.53, -209.65, 70.78, 0.0),
        } },
        { street = 'Palomino Ave', at = vector3(-709.33, -917.77, 19.21), points = {
            patient = vector4(-709.33, -917.77, 19.21, 153.9),
            nearby = vector4(-708.53, -917.17, 19.21, 0.0),
        } },
        { street = 'Vinewood Boulevard', at = vector3(242.40, 198.82, 105.22), points = {
            patient = vector4(242.40, 198.82, 105.22, 22.1),
            nearby = vector4(243.20, 199.42, 105.22, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-129.26, 6550.46, 29.52), points = {
            patient = vector4(-129.26, 6550.46, 29.52, 241.0),
            nearby = vector4(-128.46, 6551.06, 29.52, 0.0),
        } },
    },
    stories = {
        chest = { weight = 3, conditions = { 'respiratory' },
            says = 'Sitting forward, lips tinged blue, every breath a wheeze.', what = 'with a severe asthma attack', },
        choking = { weight = 2, conditions = { 'airway' },
            says = 'Hands at their throat, making no sound.', what = 'who choked on their food', clue = { 'A burger', 'prop_cs_burger_01', 'A burger with a big bite out of it, dropped on the ground.' }, },
        vomit = { weight = 1, secret = 'drunk', conditions = { 'airway', 'head' },
            says = 'Out cold on their back, gurgling.', what = 'who choked on vomit after drinking', clue = { 'A bottle', 'prop_cs_whiskey_bottle', 'An empty bottle of whiskey.' }, },
    },
}))
