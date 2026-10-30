--[[
    c3r callout: SUSPICIOUS PERSON. The example: copy this file to write your own callout.

    ── How a callout works ────────────────────────────────────────────────────────────────────────────────────────
    Dispatch puts the call out to every officer on duty. Anyone can respond; units on the same call share it, and its
    objectives are split between them (each unit on scene holds one, whoever does it, it's done).

    A callout is: what the caller said (the REPORT), where (a LOCATION), and what really happened (a STORY, picked at
    random). The report never gives the story away: every story shares the same reports, so the officer has to find
    out. Each story's setup() puts people and evidence in the scene and objectives on the card, and says what happens
    when the officer does things (on(...)).

    ── What setup(c) can use ──────────────────────────────────────────────────────────────────────────────────────
      c:person(key, { at, label, model?, male?, secret?, demeanor?, flags?, warrant?, items?, scene?, questions?, lines?, facts? })
          Someone in the story, made when the first unit gets close. They're a real person (name checks find them),
          with a hidden truth (secret: 'clean', 'nervous', 'drunk', 'drugs', 'warrant'...). Walk up and press E to talk:
          the usual menu (ID, questions, search, cuffs, tests...) plus their own questions under "The call".
            at        a point name from the location's points, or a vector3 / vector4
            items     what a search finds on them that matters (it shows as evidence)
            pockets   everyday things a search finds that aren't evidence ('Gas station receipt')
            age       { min, max }: how old their ID says they are ({ 18, 19 } for a teenager)
            home      true: they live at the call's address; a point's name: on the street that point is on
            injured   true: on the ground hurt. E beside them is first aid; paramedics take them ('aid' fires)
            scene     what they're doing: a scenario ('WORLD_HUMAN_SMOKING') or an anim { dict, name, flag }
            questions { { id = 'c_...', label = 'What did you see?', needs?, hide?, press?, stress? } }
                      needs = { c_fact = 'value' | true | { list } }: only once they've said it (see lines)
                      press = asking again gets a fresh answer (pushing them); stress = nerves show in it
            lines     what they say: lines[question id] = { 'one', 'or another' }, and a line can give a fact away:
                      { 'He went that way.', set = { c_saw_direction = 'north' } }. Facts start with c_.
                      Lines can also replace their answer to any normal question (e.g. lines.where), and a line can
                      be a function that returns the list, decided as it's asked:
                      c_safe = function() return c:apart('a', 'b') and TRUTH or COVER end
      c:vehicle(key, { at, model, make, name, color, paint?, owner?, stolen?, locked?, damage? })
          A parked car, on file: run its plate and it comes back registered to `owner` (a person key) or someone else.
          model = the spawn name ('asea'); make / name / color = what the plate check says ('Declasse', 'Asea', 'Silver');
          paint = GTA colour id; locked defaults to true; damage = 'front': the front end smashed in.
      c:clue(key, { at | on, label, text, prop?, hidden? })
          Evidence: up close, "E Inspect: <label>" shows text and puts it on every unit's MDT. on = a vehicle key puts
          it on that car (for something about a person, give them a question instead).
          prop = an object model laid on the ground there ('prop_npc_phone_02'); it, or the car it's on, has an
          amber arrow over it until you've looked at it. Check model names against the game's object list.
      c:objective(id, text, { after?, who?, hint?, hidden?, blip? })
          A line on the card. after = { ids } that must be done first; who = 'one' (one unit takes it, the default)
          or 'all' (on everyone's card); hidden = off the card until c:reveal(id); blip = the person / vehicle / clue
          key (or a list) it's about, marked on the map of whoever has it.
      c:done(id)  c:reveal(id)  c:is_done(id)
      c:on(event, function(...) end)
          'arrive' (src)                       a unit got there
          'contact' (person, src)              someone started talking to a person
          'act' (person, action, arg, src)     anything done with them: 'ask' (arg = question id), 'licence', 'frisk',
                                               'cuff', 'release', 'warn', 'cite', 'escort', 'seat'...
          'fact' (person, fact, value, src)    something they gave away (a line's set)
          'contact_ended' (person, outcome, src)   'released', 'arrested', 'cited', 'warning', 'cancelled' (walked off)
          'inspect' (clue, src)                evidence looked at (the first time)
          'tick' (seconds)                     once a second
          'gone' (person)                      they're gone (taken away by a unit, or deleted)
          'custody' (person, how, src)         a prisoner taken in: 'booked' at a station, or 'transport'
          'aid' (person, what, src)            someone injured seen to: 'vitals', 'pressure', 'cpr' (first aid), or by
                                               paramedics: 'hospital' (taken away) or 'treated' (at the scene)
      c:custody(person)        they're under arrest: "Take <name> in: book them at a station, or call prisoner
                               transport" goes on the card (with a blip on them) until they are; then 'custody' fires
      c:hide(id)               an objective off the card again (e.g. custody, after an uncuff)
      c:talking()              is an officer talking to anyone on the call right now
      c:questions(person)      after giving them a fact from elsewhere: the officer talking to them sees what it opens
      c:who(person)            their record on the call: .facts, .cuffed, .identified ...
      c:name(person)           their real name; c:plate(vehicle) its plate; c:street() the call's street
      c:owner(vehicle)         who the car's registered to: { first, last, address }
      c:apart(a, b)            out of each other's earshot (10 m, or either cuffed / in a car)
      c:task(person, 'go' | 'flee' | 'surrender' | 'wander' | 'scene', point?)   ('go': they walk to the point)
      c:say(person, text)      a line heard on scene
      c:dispatch(text)         a radio update to the units on it
      c:note(text)             a line on their MDT incident
      c:set(k, v) / c:get(k)   the call's own memory
      c:finish(summary)        it's dealt with: completed, the summary on the MDT

    ── Rules that keep a callout good ─────────────────────────────────────────────────────────────────────────────
      · Same reports for every story, and the same objectives at the start: story-specific ones are hidden until
        something found reveals them. Otherwise players learn to read the card instead of doing police work.
      · Start with objectives that can be done at the same time, so a second unit has real work.
      · Every objective needs something in on(...) that marks it done.
      · An error in your file cancels that one call and prints why (in the server console); nothing else breaks.
      · Scenario, anim and prop names: check them against the game files; a wrong one just does nothing.
]]

-- What the caller tells the officer, the same in every story (only the answers change).
local CALLER_QUESTIONS = {
    { id = 'c_what', label = 'What did you see?' },
    { id = 'c_where', label = 'Where are they now?' },
    { id = 'c_looks', label = 'What do they look like?' },
    { id = 'c_before', label = 'Have you seen them around here before?' },
}
-- What the officer can ask the person they called about.
local SUBJECT_QUESTIONS = {
    { id = 'c_doing', label = 'What are you doing out here?', stress = true },
    { id = 'c_whichcar', label = 'Which car is yours?', needs = { c_car = true } },
    { id = 'c_doors', label = 'Someone saw you trying car doors.', needs = { c_heard = true }, stress = true, press = true },
}

Callout({
    id = 'example',
    name = 'Suspicious person',
    priority = 3,
    enabled = true, -- false: a template only (no calls made from it)
    reports = {
        'Caller reports someone hanging around the parked cars, looking in the windows.',
        'Caller says a man has been walking up and down the street, trying car doors.',
        'Suspicious male by the parked cars. Caller is watching from across the road.',
    },
    -- Where it can happen. street: on the card; at: the scene (units are "on scene" within Config.Callouts.arrive m of it);
    -- points: exactly where each person stands and the car is parked, as vector4(x, y, z, heading):
    --   caller              the person who rang it in, waiting nearby on their phone
    --   suspicious_person   the man they called about
    --   parked_car          the silver car he was at (sit in a car parked where it should be, then /c3rpos parked_car)
    -- To get one, stand there in game and type /c3rpos <name>: it's copied, ready to paste.
    points = { -- the order /c3rplace example walks you through them ('car': sit in a car)
        { 'caller', 'The person who rang it in, waiting nearby on their phone.' },
        { 'suspicious_person', 'The man they called about.' },
        { 'parked_car', 'The silver car he was at. Sit in a car parked where it should be.', 'car' },
    },
    locations = {
        { street = 'Panorama Drive', at = vector3(1781.00, 3329.44, 40.25), points = {
            caller = vector4(1777.95, 3326.33, 41.43, 297.6),
            suspicious_person = vector4(1784.80, 3332.46, 41.32, 269.7),
            parked_car = vector4(1787.24, 3331.89, 41.23, 208.5),
        } },
        { street = 'Paleto Blvd', at = vector3(182.31, 6604.51, 30.85), points = {
            caller = vector4(170.94, 6632.75, 31.65, 247.6),
            suspicious_person = vector4(179.30, 6608.62, 31.87, 339.6),
            parked_car = vector4(182.27, 6606.63, 31.85, 189.9),
        } },
        
        { street = 'Grapeseed Avenue', at = vector3(1693.48, 4781.81, 40.92), points = {
            caller = vector4(1690.38, 4758.41, 41.92, 46.0),
            suspicious_person = vector4(1694.96, 4780.10, 42.00, 99.4),
            parked_car = vector4(1690.55, 4782.33, 41.92, 267.4),
        } },
        { street = 'Grove Street', at = vector3(100.4, -1937.0, 20.8), points = {
            caller = vector4(118.13, -1945.35, 20.69, 84.6),
            suspicious_person = vector4(106.35, -1953.22, 20.72, 330.2),
            parked_car = vector4(109.04, -1950.60, 20.63, 297.6),
        } },
        { street = 'Vespucci Beach', at = vector3(-1184.42, -1502.47, 3.38), points = {
            caller = vector4(-1185.59, -1508.61, 4.38, 1.9),
            suspicious_person = vector4(-1189.95, -1490.42, 4.38, 107.4),
            parked_car = vector4(-1186.86, -1490.78, 4.38, 307.2),
        } },
        { street = 'Mirror Park', at = vector3(1102.0, -458.0, 67.0), points = {
            caller = vector4(1087.52, -484.08, 65.17, 90.1),
            suspicious_person = vector4(1087.51, -468.35, 64.76, 121.0),
            parked_car = vector4(1091.50, -471.66, 66.21, 77.7),
        } },
        { street = 'Vinewood Boulevard', at = vector3(250.0, 222.0, 106.3), points = {
            caller = vector4(232.81, 210.23, 105.43, 159.1),
            suspicious_person = vector4(242.40, 198.82, 105.22, 22.1),
            parked_car = vector4(239.18, 196.08, 105.11, 69.9),
        } },
    },
    stories = {
        -- ── He's breaking into cars. ──────────────────────────────────────────────────────────────────────────
        thief = {
            weight = 2,
            setup = function(c)
                c:person('caller', { at = 'caller', label = 'Caller', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_QUESTIONS,
                    lines = {
                        c_what = { { "He's going car to car, pulling the handles. He got into the silver one for a second.",
                                     set = { c_saw = 'doors' } } },
                        c_where = { 'Still over there, by the cars. Smoking, like nothing happened.' },
                        c_looks = { "Hoodie, jeans. Keeps looking around, like he's waiting for someone to see him." },
                        c_before = { "Never. And I'm out here every night with the dog." },
                    } })
                c:person('subject', { at = 'suspicious_person', label = 'Person', male = true, demeanor = 'nervous',
                    secret = math.random() < .4 and 'warrant' or 'clean', scene = 'WORLD_HUMAN_SMOKING',
                    items = { 'Slim jim', 'Flathead screwdriver' }, questions = SUBJECT_QUESTIONS,
                    lines = {
                        c_doing = { { "Just waiting for a friend. That a crime now?", set = { c_car = 'none' } },
                                    { 'Having a smoke. Waiting on my ride.', set = { c_car = 'none' } } },
                        c_whichcar = { "I don't have a car. I told you, I'm waiting for my ride." },
                        c_doors = { "I wasn't touching anything.", "What? No. Who said that?",
                                    { "...Alright. The door was open. I only looked. I didn't take nothing.", set = { c_admit = 'yes' } } },
                    } })
                c:vehicle('car', { at = 'parked_car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4,
                    label = 'Silver sedan' }) -- (someone else's: he has no car here)
                c:clue('car', { on = 'car', label = 'Silver sedan', hidden = true,
                    text = "The driver's door lock is scratched and bent. Fresh marks: someone's had a tool in it." })

                c:objective('caller', 'Talk to the caller', { hint = 'They said they would wait nearby.', blip = 'caller' })
                c:objective('find', 'Find the person they called about', { hint = 'Near the parked cars.', blip = 'subject' })
                c:objective('car', 'Check the car they tried', { hidden = true, hint = 'The caller said the silver one.', blip = 'car' })
                c:objective('deal', 'Deal with them: arrest, ticket or warn, or let them go', { after = { 'find' }, who = 'all', blip = 'subject' })

                c:on('act', function(who, action, arg)
                    if who == 'caller' and action == 'ask' and arg == 'c_what' then c:done('caller') end
                end)
                c:on('fact', function(who, fact)
                    if who == 'caller' and fact == 'c_saw' then
                        c:reveal('car') -- the objective and the clue (same id): now there's something to look at
                        c:who('subject').facts.c_heard = true -- and something to put to him
                    end
                end)
                c:on('contact', function(who) if who == 'subject' then c:done('find') end end)
                c:on('inspect', function(clue) if clue == 'car' then c:done('car') end end)
                local function proof()
                    local s = c:who('subject')
                    return c:is_done('car') or s.facts.found or s.facts.c_admit
                end
                -- cuffed: the card says to take him in, and it's over when he's booked or transported
                c:on('act', function(who, action)
                    if who ~= 'subject' then return end
                    if action == 'cuff' and c:who('subject').cuffed then c:custody('subject') end
                    if action == 'cite' or action == 'warn' then -- (a ticket or a warning: dealt with)
                        c:finish(('Subject given a %s%s.'):format(action == 'cite' and 'ticket' or 'warning',
                            proof() and ' despite evidence of tampering' or ''))
                    end
                end)
                c:on('custody', function()
                    c:finish(proof() and 'Suspect arrested for vehicle tampering; tools and damage recorded.'
                        or 'Suspect arrested. No evidence of tampering recorded.')
                end)
                c:on('contact_ended', function(who, outcome)
                    if who == 'subject' and not c:who('subject').cuffed
                        and (outcome == 'released' or outcome == 'cited' or outcome == 'warning') then
                        c:finish(proof() and 'Suspect released despite evidence of tampering.' or 'Subject spoken to and released.')
                    end
                end)
            end,
        },

        -- ── He locked himself out of his own car. ─────────────────────────────────────────────────────────────
        lockout = {
            weight = 1,
            setup = function(c)
                c:person('caller', { at = 'caller', label = 'Caller', scene = 'WORLD_HUMAN_STAND_MOBILE', questions = CALLER_QUESTIONS,
                    lines = {
                        c_what = { { "He was at the silver car with a bit of wire, working at the door. Looked dodgy to me.",
                                     set = { c_saw = 'wire' } } },
                        c_where = { "Still there. He hasn't even tried to hide." },
                        c_looks = { 'Normal enough. Work clothes. Sweating a lot.' },
                        c_before = { "Maybe? There's a lot of people parking here for the shops." },
                    } })
                c:person('subject', { at = 'suspicious_person', label = 'Person', male = true, demeanor = 'polite', secret = 'clean',
                    scene = 'WORLD_HUMAN_STAND_IMPATIENT', items = {}, questions = SUBJECT_QUESTIONS,
                    lines = {
                        c_doing = { { "Honestly? I locked my keys in my car. I've been trying to get the door open with a coat hanger.",
                                      set = { c_car = 'mine' } } },
                        c_whichcar = { "The silver one. Look, the keys are right there on the seat. I'm such an idiot." },
                        c_doors = { "Only my own! I swear it's mine, my name's on the papers in the glovebox." },
                    } })
                c:vehicle('car', { at = 'parked_car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4,
                    label = 'Silver sedan', owner = 'subject' }) -- (his: run the plate)
                c:clue('car', { on = 'car', label = 'Silver sedan', hidden = true,
                    text = 'Through the window: a key fob on the driver\'s seat, and a coat hanger bent into a hook by the door.' })

                -- the same objectives as the other story: the card doesn't tell you which one it is
                c:objective('caller', 'Talk to the caller', { hint = 'They said they would wait nearby.', blip = 'caller' })
                c:objective('find', 'Find the person they called about', { hint = 'Near the parked cars.', blip = 'subject' })
                c:objective('car', 'Check the car they tried', { hidden = true, hint = 'The caller said the silver one.', blip = 'car' })
                c:objective('deal', 'Deal with them: arrest, ticket or warn, or let them go', { after = { 'find' }, who = 'all', blip = 'subject' })

                c:on('act', function(who, action, arg)
                    if who == 'caller' and action == 'ask' and arg == 'c_what' then c:done('caller') end
                end)
                c:on('fact', function(who, fact)
                    if who == 'caller' and fact == 'c_saw' then
                        c:reveal('car')
                        c:who('subject').facts.c_heard = true
                    end
                end)
                c:on('contact', function(who) if who == 'subject' then c:done('find') end end)
                c:on('inspect', function(clue) if clue == 'car' then c:done('car') end end)
                c:on('act', function(who, action)
                    if who ~= 'subject' then return end
                    if action == 'cuff' and c:who('subject').cuffed then c:custody('subject') end
                    if action == 'cite' or action == 'warn' then
                        c:finish(('The owner, locked out of his own car, given a %s. No crime.'):format(action == 'cite' and 'ticket' or 'warning'))
                    end
                end)
                c:on('custody', function() c:finish('Arrested the owner of the car. No crime found: he was locked out.') end)
                c:on('contact_ended', function(who, outcome)
                    if who == 'subject' and not c:who('subject').cuffed
                        and (outcome == 'released' or outcome == 'cited' or outcome == 'warning') then
                        c:finish('Owner locked out of his own car. No crime; caller advised.')
                    end
                end)
            end,
        },
    },
})
