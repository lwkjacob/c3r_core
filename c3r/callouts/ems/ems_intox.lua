--[[
    c3r medical call: INTOXICATED PERSON.

    Someone very drunk. Out cold and vomiting, a fall onto their head, or drink and something stronger.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      vomit     Out cold, lying in their own vomit.
      fell      Slurring, blood running from their scalp.
      drugs     Barely breathing, pinpoint pupils.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_intox (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_intox',
    name = 'Intoxicated person',
    voice = 'call_intox', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    age = { 18, 60 },
    reports = {
        'Caller says a very drunk person is lying on the ground.',
        'Person passed out, smells of alcohol.',
    },
    locations = {
        { street = 'Paleto Blvd', at = vector3(-301.52, 6254.26, 31.53), points = {
            patient = vector4(-301.52, 6254.26, 31.53, 240.4),
            nearby = vector4(-300.72, 6254.86, 31.53, 0.0),
        } },
        { street = 'Strawberry Ave', at = vector3(117.10, -1294.64, 29.27), points = {
            patient = vector4(117.10, -1294.64, 29.27, 316.2),
            nearby = vector4(117.90, -1294.04, 29.27, 0.0),
        } },
        { street = 'Vinewood Boulevard', at = vector3(242.40, 198.82, 105.22), points = {
            patient = vector4(242.40, 198.82, 105.22, 22.1),
            nearby = vector4(243.20, 199.42, 105.22, 0.0),
        } },
        { street = 'Grove St', at = vector3(118.13, -1945.35, 20.69), points = {
            patient = vector4(118.13, -1945.35, 20.69, 84.6),
            nearby = vector4(118.93, -1944.75, 20.69, 0.0),
        } },
    },
    stories = {
        vomit = { weight = 3, secret = 'drunk', conditions = { 'airway' },
            says = 'Out cold, lying in their own vomit.', what = 'drunk and choking on vomit', clue = { 'A bottle', 'prop_cs_whiskey_bottle', 'An empty bottle of whiskey.' }, },
        fell = { weight = 2, secret = 'drunk', conditions = { 'head', { 'hemorrhage', 'head' }, 'pain' },
            says = 'Slurring, blood running from their scalp.', what = 'drunk, who fell and hit their head', clue = { 'A bottle', 'prop_amb_beer_bottle', 'A beer bottle, rolled away.' }, },
        drugs = { weight = 1, secret = 'drugs', conditions = { 'opioid', 'airway' },
            says = 'Barely breathing, pinpoint pupils.', what = 'drunk, and on opioids too', clue = { 'A needle', 'p_syringe_01_s', 'A needle, half hidden under them.' }, },
    },
}))
