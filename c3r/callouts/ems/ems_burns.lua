--[[
    c3r medical call: BURNS.

    Someone burnt at home. A barbecue flare-up, or smoke from a fire breathed in.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      bbq       Arm blistered and raw, in agony.
      smoke     Soot round the mouth, coughing, voice hoarse.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_burns (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_burns',
    name = 'Burns',
    voice = 'call_burns', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    reports = {
        'Caller says someone has been burnt.',
        'Person hurt in a fire at a house. The fire is out.',
    },
    locations = {
        { street = 'Grove St', at = vector3(103.10, -1958.40, 20.70), points = {
            patient = vector4(103.10, -1958.40, 20.70, 150.0),
            nearby = vector4(103.90, -1957.80, 20.70, 0.0),
        } },
        { street = 'Bridge St', at = vector3(878.60, -193.28, 70.78), points = {
            patient = vector4(878.60, -193.28, 70.78, 258.8),
            nearby = vector4(879.40, -192.68, 70.78, 0.0),
        } },
        { street = 'Senora Fwy', at = vector3(2631.22, 3301.63, 55.35), points = {
            patient = vector4(2631.22, 3301.63, 55.35, 161.3),
            nearby = vector4(2632.02, 3302.23, 55.35, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(407.23, 2954.20, 40.92), points = {
            patient = vector4(407.23, 2954.20, 40.92, 352.8),
            nearby = vector4(408.03, 2954.80, 40.92, 0.0),
        } },
    },
    stories = {
        bbq = { weight = 2, conditions = { 'pain' },
            says = 'Arm blistered and raw, in agony.', what = 'burnt by a barbecue', clue = { 'A barbecue', 'prop_bbq_1', 'A barbecue, still smoking.' }, },
        smoke = { weight = 2, conditions = { 'respiratory', 'pain' },
            says = 'Soot round the mouth, coughing, voice hoarse.', what = 'who breathed in smoke from a fire', clue = { 'A fuel can', 'prop_jerrycan_01a', 'A fuel can, scorched black.' }, },
    },
}))
