--[[
    c3r medical call: CHEST PAIN.

    Someone with chest pain, alone. A heart attack, a heart going far too slow, or their lungs.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      heart     Grey and sweating, one hand pressed to their chest.
      slow      Pale and dizzy. Says the room keeps tipping.
      lungs     Sharp pain when they breathe in, and they can barely catch a breath.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_chestpain (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_chestpain',
    name = 'Chest pain',
    voice = 'call_chestpain', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    age = { 40, 85 },
    reports = {
        'Caller says they have bad chest pain and feel sick.',
        'Chest pain, called it in themselves. Sounds short of breath.',
    },
    locations = {
        { street = 'Nikola Pl', at = vector3(1386.08, -593.52, 74.47), points = {
            patient = vector4(1386.08, -593.52, 74.47, 229.4),
            nearby = vector4(1386.88, -592.92, 74.47, 0.0),
        } },
        { street = 'Cockingend Dr', at = vector3(-1008.69, 480.12, 79.41), points = {
            patient = vector4(-1008.69, 480.12, 79.41, 331.6),
            nearby = vector4(-1007.89, 480.72, 79.41, 0.0),
        } },
        { street = 'Route 68', at = vector3(1163.76, 2701.92, 38.18), points = {
            patient = vector4(1163.76, 2701.92, 38.18, 157.0),
            nearby = vector4(1164.56, 2702.52, 38.18, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-0.10, 6519.90, 31.48), points = {
            patient = vector4(-0.10, 6519.90, 31.48, 31.8),
            nearby = vector4(0.70, 6520.50, 31.48, 0.0),
        } },
    },
    stories = {
        heart = { weight = 3, conditions = { 'cardiac' },
            says = 'Grey and sweating, one hand pressed to their chest.', what = 'a heart attack', },
        slow = { weight = 2, conditions = { 'bradycardia' },
            says = 'Pale and dizzy. Says the room keeps tipping.', what = 'with a dangerously slow heart', },
        lungs = { weight = 2, conditions = { 'respiratory', 'pain' },
            says = 'Sharp pain when they breathe in, and they can barely catch a breath.', what = 'with a chest infection', },
    },
}))
