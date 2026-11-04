--[[
    c3r medical call: PERSON DOWN.

    Someone down, nobody knows why. An overdose, low sugar, a heart, or a head injury from a fall nobody saw.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      overdose  Barely breathing, pinpoint pupils.
      sugar     Clammy and confused.
      heart     Grey, clutching their chest.
      head      Bleeding from the head, drowsy.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_mandown (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_mandown',
    name = 'Person down',
    voice = 'call_mandown', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    reports = {
        'Caller says someone is lying on the ground and not responding.',
        'Person down. Unknown problem.',
    },
    locations = {
        { street = 'Panorama Dr', at = vector3(1572.29, 3683.56, 34.78), points = {
            patient = vector4(1572.29, 3683.56, 34.78, 343.3),
            nearby = vector4(1573.09, 3684.16, 34.78, 0.0),
        } },
        { street = 'Great Ocean Hwy', at = vector3(160.58, 6357.87, 31.39), points = {
            patient = vector4(160.58, 6357.87, 31.39, 278.3),
            nearby = vector4(161.38, 6358.47, 31.39, 0.0),
        } },
        { street = 'San Andreas Ave', at = vector3(382.56, -833.80, 29.29), points = {
            patient = vector4(382.56, -833.80, 29.29, 151.3),
            nearby = vector4(383.36, -833.20, 29.29, 0.0),
        } },
        { street = 'Algonquin Blvd', at = vector3(1385.67, 3601.34, 34.90), points = {
            patient = vector4(1385.67, 3601.34, 34.90, 52.1),
            nearby = vector4(1386.47, 3601.94, 34.90, 0.0),
        } },
    },
    stories = {
        overdose = { weight = 3, secret = 'drugs', conditions = { 'opioid' },
            says = 'Barely breathing, pinpoint pupils.', what = 'who had overdosed', clue = { 'A needle', 'p_syringe_01_s', 'A needle on the ground nearby.' }, },
        sugar = { weight = 2, conditions = { 'hypoglycemia' },
            says = 'Clammy and confused.', what = 'with very low blood sugar', },
        heart = { weight = 1, conditions = { 'cardiac' },
            says = 'Grey, clutching their chest.', what = 'having a heart attack', },
        head = { weight = 1, conditions = { 'head', { 'hemorrhage', 'head' } },
            says = 'Bleeding from the head, drowsy.', what = 'with a head injury from a fall', },
    },
}))
