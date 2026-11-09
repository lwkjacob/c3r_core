--[[
    c3r medical call: PERSON SEIZING.

    Someone who had a seizure. Low blood sugar set it off, they hit their head going down, or vomited during it.
    Just the patient (and, in some stories, something beside them). The stories, and what the treatment screen finds:
      sugar     Drowsy now the shaking has stopped, sweating.
      head      Groggy after the fit, blood in their hair.
      vomit     Not waking, gurgling.

    Placed at spots other calls use. Add or move them in game with /c3rplace ems_seizure (it writes the location in below).
]]

Callout(Ems.call({
    id = 'ems_seizure',
    name = 'Person seizing',
    voice = 'call_seizure', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    priority = 1,
    reports = {
        'Caller says someone is shaking on the ground.',
        'Person having a fit. It has stopped now but they will not wake up.',
    },
    locations = {
        { street = 'Legion Square', at = vector3(200.00, -945.00, 30.70), points = {
            patient = vector4(200.00, -945.00, 30.70, 0.0),
            nearby = vector4(200.80, -944.40, 30.70, 0.0),
        } },
        { street = 'West Mirror Drive', at = vector3(1157.64, -327.44, 69.22), points = {
            patient = vector4(1157.64, -327.44, 69.22, 191.1),
            nearby = vector4(1158.44, -326.84, 69.22, 0.0),
        } },
        { street = 'Joshua Rd', at = vector3(412.09, 2966.05, 41.89), points = {
            patient = vector4(412.09, 2966.05, 41.89, 352.7),
            nearby = vector4(412.89, 2966.65, 41.89, 0.0),
        } },
        { street = 'Grapeseed Main St', at = vector3(1700.36, 4933.74, 42.08), points = {
            patient = vector4(1700.36, 4933.74, 42.08, 83.2),
            nearby = vector4(1701.16, 4934.34, 42.08, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-0.40, 6513.03, 31.88), points = {
            patient = vector4(-0.40, 6513.03, 31.88, 140.8),
            nearby = vector4(0.40, 6513.63, 31.88, 0.0),
        } },
        -- Sandy Shores, rough (placed from memory): check them in game, move any that are off with /c3rplace ems_seizure
        { street = 'Alhambra Dr', at = vector3(1931.50, 3730.00, 32.84), points = {
            patient = vector4(1931.50, 3730.00, 32.84, 210.0),
            nearby = vector4(1932.30, 3730.60, 32.84, 0.0),
        } },
        { street = 'Alhambra Dr', at = vector3(1853.00, 3689.50, 34.27), points = {
            patient = vector4(1853.00, 3689.50, 34.27, 210.0),
            nearby = vector4(1853.80, 3690.10, 34.27, 0.0),
        } },
    },
    stories = {
        sugar = { weight = 2, conditions = { 'hypoglycemia' },
            says = 'Drowsy now the shaking has stopped, sweating.', what = 'who had a seizure from low blood sugar', },
        head = { weight = 2, conditions = { 'head', { 'hemorrhage', 'head' }, 'pain' },
            says = 'Groggy after the fit, blood in their hair.', what = 'who hit their head in a seizure', },
        vomit = { weight = 1, conditions = { 'airway', 'pain' },
            says = 'Not waking, gurgling.', what = 'who vomited during a seizure', },
    },
}))
