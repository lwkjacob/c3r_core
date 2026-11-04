--[[
    c3r medical call: ELDERLY FALL.

    An older person who fell at home. A broken hip, a head injury, or a heart so slow it made them fall.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      hip       Leg turned out, too sore to move.
      head      A bleeding cut on the head, muddled.
      heart     Dizzy, pale. Says they blacked out.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_elderly (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_elderly',
    name = 'Elderly fall',
    voice = 'call_elderly', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 2,
    age = { 70, 92 },
    reports = {
        'Caller says an elderly person has fallen and cannot get up.',
        'Elderly person on the floor, called in by a neighbour who had to leave.',
    },
    locations = {
        { street = 'Goma St', at = vector3(-1153.73, -1516.03, 4.38), points = {
            patient = vector4(-1153.73, -1516.03, 4.38, 305.4),
            nearby = vector4(-1152.93, -1515.43, 4.38, 0.0),
        } },
        { street = 'Grove St', at = vector3(98.20, -1956.10, 20.70), points = {
            patient = vector4(98.20, -1956.10, 20.70, 90.0),
            nearby = vector4(99.00, -1955.50, 20.70, 0.0),
        } },
        { street = 'Nikola Pl', at = vector3(1380.09, -578.04, 74.26), points = {
            patient = vector4(1380.09, -578.04, 74.26, 91.0),
            nearby = vector4(1380.89, -577.44, 74.26, 0.0),
        } },
        { street = 'Cockingend Dr', at = vector3(-1006.32, 490.23, 79.33), points = {
            patient = vector4(-1006.32, 490.23, 79.33, 26.4),
            nearby = vector4(-1005.52, 490.83, 79.33, 0.0),
        } },
    },
    stories = {
        hip = { weight = 3, conditions = { { 'fracture', 'lleg' }, 'pain' },
            says = 'Leg turned out, too sore to move.', what = 'an elderly fall with a broken hip', },
        head = { weight = 2, conditions = { 'head', { 'hemorrhage', 'head' } },
            says = 'A bleeding cut on the head, muddled.', what = 'an elderly fall onto the head', },
        heart = { weight = 1, conditions = { 'bradycardia', 'pain' },
            says = 'Dizzy, pale. Says they blacked out.', what = 'who fell because their heart was too slow', },
    },
}))
