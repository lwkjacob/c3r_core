--[[
    c3r medical call: FALL INJURY.

    Someone's fallen and whoever's with them rang it in. Same report and card every time. The story is in how they
    fell, and the person with them may not be telling it straight:
      ladder    an honest accident: a broken leg and a bleeding arm.
      drunk     they fell down drunk, and their friend is embarrassed: a broken arm, a cut head and a head injury under it.
      pushed    the partner says they tripped. The wound isn't from a fall, and pressed, they crack. The medic radios it in.

    Points per location: walk them out in game with /c3rplace ems_fall (it writes the location in below).
]]

local WITH_Q = {
    { id = 'c_what', label = 'How did they fall?', stress = true, press = true },
    { id = 'c_long', label = 'How long ago?' },
}

local function people(c, conditions, vitals, secret, what, clue)
    c:person('patient', { at = 'patient', label = 'Patient', secret = secret, injured = true, age = { 21, 66 }, vitals = vitals, conditions = conditions })
    c:person('with', { at = 'with', label = 'Person with them', secret = 'nervous', demeanor = 'nervous', scene = 'WORLD_HUMAN_STAND_IMPATIENT',
        questions = WITH_Q, lines = { c_what = what, c_long = { 'Ten minutes? I rang as soon as I could.' } } })
    c:clue('nearby', { at = 'nearby', label = clue[1], prop = clue[2], text = clue[3] })
    Ems.card(c, 'patient')
    c:objective('with', 'Find out how they fell', { blip = 'with' })
    c:on('contact', function(who) if who == 'with' then c:done('with') end end)
    c:on('dead', function(who) if who == 'with' then c:done('with') end end)
end

-- Denies it until pressed `times` times, then admits it; once admitted, says so again.
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end

Callout({
    id = 'ems_fall',
    service = 'ambulance',
    name = 'Fall injury',
    priority = 2,
    voice = 'call_fall', -- (dispatch's line for it: lwk_control/tools/make_voice.py)
    weight = 1,
    enabled = true,
    reports = {
        'Caller says someone has had a bad fall and is hurt.',
        'Person fallen, conscious but in a lot of pain.',
    },
    points = {
        { 'patient', 'The patient, on the ground.' },
        { 'with', 'Whoever is with them, a few metres away.' },
        { 'nearby', 'Something on the ground beside the patient.' },
    },
    -- Add more with /c3rplace ems_fall in game (it writes them here). These are rough placeholders
    locations = {
        { street = 'Cockingend Dr', at = vector3(-1042.41, 503.58, 84.17), points = {
            patient = vector4(-1042.41, 503.58, 84.17, 90.0),
            with = vector4(-1039.41, 505.58, 84.17, 120.0),
            nearby = vector4(-1043.41, 502.58, 84.17, 0.0),
        } },
        { street = 'Senora Fwy', at = vector3(2632.80, 3258.56, 55.46), points = {
            patient = vector4(2632.80, 3258.56, 55.46, 90.0),
            with = vector4(2635.80, 3260.56, 55.46, 120.0),
            nearby = vector4(2631.80, 3257.56, 55.46, 0.0),
        } },
        { street = 'Paleto Blvd', at = vector3(-301.52, 6254.26, 31.53), points = {
            patient = vector4(-301.52, 6254.26, 31.53, 90.0),
            with = vector4(-298.52, 6256.26, 31.53, 120.0),
            nearby = vector4(-302.52, 6253.26, 31.53, 0.0),
        } },
        -- Sandy Shores, rough (placed from memory): check them in game, move any that are off with /c3rplace ems_fall
        { street = 'Panorama Dr', at = vector3(1717.50, 3295.60, 41.20), points = {
            patient = vector4(1717.50, 3295.60, 41.20, 105.0),
            with = vector4(1720.50, 3297.60, 41.20, 285.0),
            nearby = vector4(1718.30, 3296.20, 41.20, 0.0),
        } },
        { street = 'Zancudo Ave', at = vector3(1975.60, 3818.80, 33.40), points = {
            patient = vector4(1975.60, 3818.80, 33.40, 120.0),
            with = vector4(1978.60, 3820.80, 33.40, 300.0),
            nearby = vector4(1976.40, 3819.40, 33.40, 0.0),
        } },
    },

    stories = {
        ladder = {
            weight = 3,
            setup = function(c)
                people(c, { { 'fracture', 'rleg' }, { 'hemorrhage', 'larm' }, 'pain' }, 'Awake, in a lot of pain.', 'clean',
                    { 'Off the ladder. It slipped. I told them to tie it off.' },
                    { 'A ladder', 'prop_byard_ladder01', 'An aluminium ladder, buckled at the foot.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s fell from a ladder, and was treated and taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s fell from a ladder and died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
        drunk = {
            weight = 2,
            setup = function(c)
                people(c, { { 'fracture', 'rarm' }, { 'hemorrhage', 'head' }, 'head', 'pain' }, 'Smells of drink. Slurring, but awake.', 'drunk',
                    { "They, er, tripped. On the kerb. Okay, they've had a few. Quite a few." },
                    { 'A bottle', 'prop_cs_beer_bot_01', 'A smashed bottle, still wet.' })
                Ems.wire(c, 'patient', function(how)
                    if how == 'hospital' then return ('%s fell while drunk, and was treated and taken to hospital.'):format(c:name('patient')) end
                    if how == 'pronounced' then return ('%s fell while drunk and died at the scene.'):format(c:name('patient')) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
        pushed = {
            weight = 2,
            setup = function(c)
                people(c, { { 'hemorrhage', 'abdomen' }, { 'fracture', 'lfoot' }, 'pain' }, 'Frightened. Keeps looking past you at the person with them.', 'clean',
                    cracks(3, { 'They tripped. That is all. Just look after them.' },
                        { { "...We were arguing. I pushed them. I didn't mean it.", set = { c_admit = 'yes' } } },
                        { 'I told you. I pushed them.' }),
                    { 'Broken glass', 'prop_cs_beer_bot_01', 'Broken glass, and blood on it. This did not come from a fall.' })
                c:objective('tell', 'Radio it in: this was no accident', { hidden = true, who = 'all' })
                local told = false
                c:on('fact', function(_, fact)
                    if fact ~= 'c_admit' or told then return end
                    told = true
                    c:reveal('tell')
                    c:done('tell')
                    c:dispatch('Copy. Passing that to police.')
                    c:note('The person with them admitted pushing them')
                end)
                Ems.wire(c, 'patient', function(how)
                    local said = told and ' The person with them admitted pushing them, and police were told.' or ''
                    if how == 'hospital' then return ('%s was treated for a wound and a fall, and taken to hospital.%s'):format(c:name('patient'), said) end
                    if how == 'pronounced' then return ('%s died at the scene of a wound.%s'):format(c:name('patient'), said) end
                    return 'The patient was gone before treatment finished.'
                end)
            end,
        },
    },
})
