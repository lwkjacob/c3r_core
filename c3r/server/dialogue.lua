--[[
    c3r — scripted dialogue: what the people in the car say, from their hidden truth. Pure Lua, no natives.
    Good on its own without lwk_npcai.

    A dialogue tree with memory. Each person keeps what they've said (o.answers) and the facts that came
    out of it (o.facts: where they're headed, whether they admit drinking, whose car it is...).
      · Asked again, they repeat themselves ("Like I said, ...") - except the questions that press them.
      · Answers unlock follow-ups: admit a drink and "How much?" opens; deny it and "Are you sure? I can
        smell alcohol." opens, and pressing can break the lie.
      · Lines can use what was said before: {dest}, {from}, {amount}... and the other person's story:
        a passenger asked where you're headed may not tell the driver's story.

    Lines take {first} {last} {dob} {age} {street} {owner} {owner_first} {dest} {from} {amount} {when} {drug}
    {driver_first} {driver_dest} {p_dest}. A line is a string, or { 'text', set = { fact = 'value' } }; a list
    can carry a `set` for all its lines. LINES[q] picks: a question's own chooser, then passenger, the
    secret, the demeanor, default.

    Callout people (server/callouts.lua) bring their own: o.extra = { questions, lines }. Their questions are asked
    under "The call"; their lines (for those, or to replace the usual answer to any question) are a list, or keyed
    like LINES (secret / demeanor / default), or a function returning one (decided at the moment they're asked).
]]

Dialogue = {}

-- ─── the questions ────────────────────────────────────────────────────────────

Dialogue.CALL = { id = 'call', label = 'The call', desc = 'What happened, and what they know about it.' } -- (callout people only)

Dialogue.CATEGORIES = {
    { id = 'stop',       label = 'The stop',              desc = 'Why they were stopped, where they are going and coming from.' },
    { id = 'id',         label = 'Licence & ID',          desc = 'Their licence, name, age and address.' },
    { id = 'vehicle',    label = 'The vehicle',           desc = 'Who owns it, its papers, its condition.', who = 'driver' },
    { id = 'driving',    label = 'Their driving',         desc = 'Speed, signals, phone, seatbelt.' },
    { id = 'intox',      label = 'Alcohol & drugs',       desc = 'Drinking, drug use, medication.' },
    { id = 'contraband', label = 'Contraband',            desc = 'Drugs, weapons, open containers, consent to search.' },
    { id = 'record',     label = 'Record',                desc = 'Arrests, probation, warrants.' },
    { id = 'passenger',  label = 'About the driver',      desc = 'How they know the driver, and what the driver has been doing.', who = 'passenger' },
}

-- foot: how it's asked of someone on foot. who: only the driver or only a passenger is asked it. needs: facts they've given that open it
-- (true = any answer; a list = any of these). hide: facts that close it again. press: not remembered,
-- so asking again gets a fresh answer. stress: nerves and attitude show in the answer.
Dialogue.QUESTIONS = {
    -- the stop
    { id = 'why',        cat = 'stop', label = 'Do you know why I stopped you?' },
    { id = 'where',      cat = 'stop', label = 'Where are you headed?' },
    { id = 'dest_where', cat = 'stop', label = 'Whereabouts is that?', needs = { dest = true } },
    { id = 'from',       cat = 'stop', label = 'Where are you coming from?' },
    { id = 'from_what',  cat = 'stop', label = 'What were you doing there?', needs = { from = true } },
    { id = 'hurry',      cat = 'stop', label = 'Are you in a hurry today?' },
    { id = 'live',       cat = 'stop', label = 'Do you live around here?' },
    { id = 'work',       cat = 'stop', label = 'What do you do for work?' },
    { id = 'nervous',    cat = 'stop', label = 'You seem nervous. Is everything okay?', stress = true, press = true },
    { id = 'whyran',     cat = 'stop', label = 'Why did you run?', needs = { ran = true }, stress = true },
    { id = 'others',     cat = 'stop', label = 'Who else is in the car with you?', who = 'driver' },
    { id = 'pdest',      cat = 'stop', label = 'Your passenger says you are headed to {p_dest}.', who = 'driver',
      stress = true, when = function(o, ctx) return ctx.p_dest and o.facts.dest and ctx.p_dest ~= o.facts.dest end },
    -- licence and identity
    { id = 'name',       cat = 'id', label = "What's your name and date of birth?" },
    { id = 'age',        cat = 'id', label = 'How old are you?' },
    { id = 'address',    cat = 'id', label = "What's your current address?" },
    { id = 'valid',      cat = 'id', label = "Do you have a valid driver's licence?", who = 'driver', stress = true },
    { id = 'why_susp',   cat = 'id', label = 'Why is your licence suspended?', needs = { licence = 'suspended' } },
    { id = 'why_none',   cat = 'id', label = "Why don't you have a licence?", needs = { licence = 'none' } },
    { id = 'renew',      cat = 'id', label = "Why haven't you renewed it?", needs = { licence = 'expired' } },
    { id = 'sure_lic',   cat = 'id', label = "You're sure your licence is valid?", needs = { licence = 'valid' },
      who = 'driver', stress = true, press = true },
    { id = 'otherid',    cat = 'id', label = 'Do you have any other ID on you?' },
    -- the vehicle
    { id = 'owner',      cat = 'vehicle', label = 'Is this your vehicle?', who = 'driver' },
    { id = 'ownername',  cat = 'vehicle', label = "What's the owner's name?", who = 'driver', needs = { owns = { 'family', 'friend' } } },
    { id = 'ownerknows', cat = 'vehicle', label = 'Does the owner know you have the car?', who = 'driver',
      needs = { owns = { 'family', 'friend' } }, stress = true },
    { id = 'howlong',    cat = 'vehicle', label = 'How long have you had the car?', who = 'driver', needs = { owns = 'mine' } },
    { id = 'reg',        cat = 'vehicle', label = 'Is the registration up to date?', who = 'driver' },
    { id = 'insurance',  cat = 'vehicle', label = 'Is the vehicle insured?', who = 'driver' },
    { id = 'problems',   cat = 'vehicle', label = 'Any problems with the vehicle?', who = 'driver' },
    -- their driving
    { id = 'speed',      cat = 'driving', label = 'Do you know how fast you were going?', who = 'driver' },
    { id = 'limit',      cat = 'driving', label = 'Do you know the speed limit here?', who = 'driver' },
    { id = 'signal',     cat = 'driving', label = "Why didn't you use your signal?", who = 'driver' },
    { id = 'light',      cat = 'driving', label = 'Did you see that red light back there?', who = 'driver' },
    { id = 'phone',      cat = 'driving', label = 'Were you on your phone while driving?', who = 'driver' },
    { id = 'belt',       cat = 'driving', label = 'Were you wearing your seatbelt?' },
    -- alcohol and drugs
    { id = 'drink',      cat = 'intox', label = 'Have you had anything to drink today?' },
    { id = 'howmuch',    cat = 'intox', label = 'How much have you had to drink?', needs = { drank = 'yes' } },
    { id = 'lastdrink',  cat = 'intox', label = 'When was your last drink?', needs = { drank = 'yes' } },
    { id = 'smell',      cat = 'intox', label = 'Are you sure? I can smell alcohol.', needs = { drank = 'no' },
      stress = true, press = true },
    { id = 'drugsuse',   cat = 'intox', label = 'Have you taken any drugs today?', stress = true },
    { id = 'whatdrug',   cat = 'intox', label = 'What did you take, and when?', needs = { used = 'yes' } },
    { id = 'eyes',       cat = 'intox', label = 'Your eyes are bloodshot. Have you smoked anything?', needs = { used = 'no' },
      stress = true, press = true },
    { id = 'meds',       cat = 'intox', label = 'Are you on any medication?' },
    -- contraband and search
    { id = 'illegal',    cat = 'contraband', label = 'Anything illegal in the vehicle?', foot = 'Do you have anything illegal on you?' },
    { id = 'drugsincar', cat = 'contraband', label = 'Any drugs in the vehicle?', foot = 'Do you have any drugs on you?', stress = true },
    { id = 'contra_what', cat = 'contraband', label = 'What is it, and how much?', needs = { contra = 'yes' } },
    { id = 'weapons',    cat = 'contraband', label = 'Any weapons in the vehicle?', foot = 'Are you carrying any weapons?', stress = true },
    { id = 'open',       cat = 'contraband', label = 'Any open containers of alcohol?', foot = 'Are you carrying any open alcohol?' },
    { id = 'cash',       cat = 'contraband', label = 'Carrying any large amounts of cash?' },
    { id = 'search',     cat = 'contraband', label = 'Mind if I search the vehicle?', foot = 'Mind if I search you?', stress = true },
    { id = 'nosearch',   cat = 'contraband', label = "Why don't you want me to search it?", foot = "Why don't you want me to search you?",
      needs = { consent = 'no' },
      stress = true, press = true },
    { id = 'explain',    cat = 'contraband', label = 'Want to explain the {found}?', needs = { found = true },
      stress = true, press = true },
    -- record and warrants
    { id = 'arrested',   cat = 'record', label = 'Have you ever been arrested?', stress = true },
    { id = 'arrest_for', cat = 'record', label = 'What were you arrested for?', needs = { arrested = 'yes' } },
    { id = 'probation',  cat = 'record', label = 'Are you on probation or parole?', stress = true },
    { id = 'warrants',   cat = 'record', label = 'Do you have any warrants out for you?', stress = true },
    { id = 'warrant_for', cat = 'record', label = 'What is the warrant for?', needs = { warrant = 'yes' } },
    { id = 'lastpolice', cat = 'record', label = 'When did you last deal with the police?' },
    -- a passenger, about the driver
    { id = 'knowdriver', cat = 'passenger', label = 'How do you know the driver?', who = 'passenger' },
    { id = 'pwhere',     cat = 'passenger', label = 'Where are you two headed?', who = 'passenger' },
    { id = 'pdrink',     cat = 'passenger', label = 'Has the driver been drinking?', who = 'passenger' },
    { id = 'pdriving',   cat = 'passenger', label = 'How was the driver driving?', who = 'passenger' },
    { id = 'pcar',       cat = 'passenger', label = 'Whose car is this?', who = 'passenger' },
}

local DEF = {}
for _, q in ipairs(Dialogue.QUESTIONS) do DEF[q.id] = q end
Dialogue.DEF = DEF

-- ─── what they say ────────────────────────────────────────────────────────────

local GUILTY = { drunk = true, drugs = true, warrant = true, stolen = true }

local LINES = {
    greet = {
        default = { 'Hi, officer.', 'Evening, officer.', 'Hello. Is everything okay?' },
        nervous = { 'Uh, hi. Hi, officer.', 'Oh. Hello.' },
        rude = { 'What?', 'Yeah, what is it?' },
        chatty = { 'Hey officer! How are you doing today?', 'Hi! Long day for you too, huh?' },
    },
    -- the greeting when they've been stopped before (server/stops.lua meet): by this officer, or another unit
    met_you = {
        default = { 'Oh. You again.', "Officer. We've met before, haven't we?", 'Not you again.' },
        nervous = { 'Oh no. Not you again.', 'Uh. Hi again, officer.' },
        warrant = { "Oh, come on. Not you.", "You again? Look, I don't want any trouble." },
        rude = { 'You again? Seriously?', 'Great. You. Again.' },
        chatty = { 'Hey, I know you! How have you been?', 'Officer! Small world, huh?' },
    },
    met_us = {
        default = { 'Again? One of you lot stopped me just the other day.', "I've already been stopped once this week." },
        rude = { 'Another one of you. Every week, I swear.', 'Do you lot ever give it a rest?' },
        chatty = { "Hi! I think I've met one of your colleagues. Nice guy." },
    },

    -- the stop
    whyran = {
        default = { 'I panicked. I just panicked.', "I don't know. I freaked out.", "I wasn't thinking, man." },
        warrant = { "I've got a warrant. I wasn't going back.", 'I knew you were going to run my name.',
                    "I can't go back to jail, man." },
        drugs = { { "I had stuff on me. I didn't want to get caught.", set = { contra = 'yes' } }, "I don't know... I panicked.",
                  'I just wanted to get rid of it.' },
        stolen = { "The car's not mine. I knew how it'd look.", "I borrowed it. Kind of. I panicked." },
        drunk = { "I've been drinking. I didn't want a DUI.", "I knew I'd blow over. I'm sorry." },
        suspended = { "My licence is suspended. I can't get another ticket.", 'I knew I was driving on a suspended licence.' },
        unlicensed = { "I don't have a licence. I panicked.", "I'm not supposed to be driving." },
        expired = { "The car's not registered. I panicked.", 'I just... I panicked.' },
        rude = { "I don't have to tell you anything.", 'Because you people are always out to get me.' },
    },
    why = {
        ran = { "...Because I ran. I know.", 'I know, I know. I ran.', "Yeah. I know why I'm here." },
        passenger = { "No idea. You'd have to ask the driver.", "I'm just the passenger.", "Don't look at me." },
        default = { 'No, officer. Was I speeding?', 'Not really, no.', 'I have no idea, sorry.', 'Was it my tail light?' },
        drunk = { "Was I swerving? Sorry, it's late.", 'No... no idea, officer.', 'I was driving fine, I swear.' },
        stolen = { "No. Can I go? I'm kind of in a hurry.", 'No idea.', "I didn't do anything." },
        drugs = { 'No. Is there a problem?', "I wasn't doing anything wrong." },
        expired = { "Is it the tags? I've been meaning to sort that out.", 'No, sir.' },
        warrant = { 'No. Is this going to take long?', 'Not a clue.' },
        still = {
            default = { 'No, officer. I was just standing here.', 'Not really. Is something wrong?', 'No idea. Did something happen?' },
            drunk = { "I'm just out for a walk, officer.", "No... I'm not doing anything." },
            drugs = { "I wasn't doing anything wrong.", 'No. Is there a problem?' },
            warrant = { 'No. Is this going to take long?', 'Not a clue.' },
            nervous = { 'No, sorry. Did I do something?', 'Am I in trouble?' },
            stolen = { "No. Can I go? I'm kind of in a hurry.", "I didn't do anything." },
        },
    },
    where = {
        default = { { 'Just heading home.', set = { dest = 'home' } }, { 'Going to work.', set = { dest = 'work' } },
                    { 'Picking up a friend.', set = { dest = "a friend's place" } },
                    { 'Grabbing some food.', set = { dest = 'the diner' } },
                    { "To my sister's place.", set = { dest = "my sister's place" } } },
        drunk = { { "Home. Just... home. Coming from a friend's place.", set = { dest = 'home', from = "a friend's place" } },
                  { 'Home from the bar. I mean, from dinner.', set = { dest = 'home', from = 'dinner' } } },
        drugs = { { 'Nowhere really. Just driving around.', set = { dest = 'nowhere' } },
                  { 'Meeting a friend. Why?', set = { dest = "a friend's place" } } },
        stolen = { { "Uh, my friend's place. Up the road.", set = { dest = "a friend's place" } },
                   { 'Just around.', set = { dest = 'nowhere' } } },
        warrant = { { 'Home.', set = { dest = 'home' } }, { 'Nowhere. Just driving.', set = { dest = 'nowhere' } } },
        foot = {
            default = { { 'Just heading home.', set = { dest = 'home' } }, { 'Going to work.', set = { dest = 'work' } },
                        { 'Meeting a friend.', set = { dest = "a friend's place" } },
                        { 'Grabbing some food.', set = { dest = 'the diner' } }, { 'Just to the store.', set = { dest = 'the store' } } },
            drunk = { { 'Home. Just... walking home.', set = { dest = 'home', from = "a friend's place" } },
                      { 'Home from the bar. I mean, from dinner.', set = { dest = 'home', from = 'dinner' } } },
            drugs = { { 'Nowhere really. Just walking around.', set = { dest = 'nowhere' } },
                      { 'Meeting a friend. Why?', set = { dest = "a friend's place" } } },
            warrant = { { 'Home.', set = { dest = 'home' } }, { 'Nowhere. Just out.', set = { dest = 'nowhere' } } },
        },
    },
    dest_where = {
        default = { "It's off {street}.", 'Not far. Ten minutes that way.', 'Over in Mirror Park.', 'Up by Vinewood.' },
        drugs = { "Just... around. It doesn't matter.", "Why do you need to know that?" },
        stolen = { "I don't know the address. I just know how to get there.", 'Somewhere near the freeway.' },
        warrant = { "Does it matter? It's close.", 'Around the corner.' },
    },
    from = {
        default = { { 'From work.', set = { from = 'work' } }, { 'The gym.', set = { from = 'the gym' } },
                    { "My mom's house.", set = { from = "my mom's house" } },
                    { 'The store, just grabbing a few things.', set = { from = 'the store' } } },
        drunk = { { "A friend's place. We were watching the game.", set = { from = "a friend's place" } },
                  { 'Just... dinner.', set = { from = 'dinner' } },
                  { 'The bar on Vespucci. But I only had one.', set = { from = 'the bar', drank = 'yes', amount = 'one drink' } } },
        drugs = { { "A friend's house.", set = { from = "a friend's house" } }, { 'Nowhere. Just out.', set = { from = 'nowhere' } } },
        stolen = { { 'Uh, Sandy Shores.', set = { from = 'Sandy Shores' } }, { "My buddy's. Where I got the car.", set = { from = "my buddy's" } } },
        warrant = { { 'Out.', set = { from = 'out' } }, { "A friend's.", set = { from = "a friend's" } } },
    },
    from_what = {
        default = { 'Just finishing my shift.', 'Visiting.', 'Picking some stuff up.', 'Hanging out, nothing special.' },
        drunk = { 'Watching the game. Had some food.', 'Just catching up with friends. Nothing crazy.' },
        drugs = { 'Just hanging out.', 'Nothing. Why?', "What does it matter what I was doing at {from}?" },
        stolen = { 'Picking up the car.', 'Uh... visiting.' },
    },
    hurry = {
        default = { 'Not really.', 'A little, I\'m running late.', 'No, officer.' },
        stolen = { 'Kind of, yeah. Can we make this quick?', 'Yeah. Is this going to take long?' },
        warrant = { 'Yeah. I need to get going.', "I've got somewhere to be." },
        drugs = { 'Sort of. Can I go soon?', 'A bit.' },
        chatty = { "Always! You know how it is. Never enough hours in the day." },
    },
    live = {
        default = { 'Yeah, on {street}.', 'Not far, over on {street}.', 'A few minutes from here.' },
        stolen = { 'No. I\'m from out of town.', 'Sort of.' },
        warrant = { 'Kind of. Why?', 'Not really.' },
    },
    work = {
        default = { "I work at a warehouse.", "I'm a nurse at Pillbox.", "Construction.", "I drive for a delivery company.",
                    "Retail. I'm a manager at a store downtown.", "I'm between jobs right now.", "I work in an office in Downtown." },
        drugs = { "I'm self-employed.", "A bit of everything.", "I do... sales." },
        warrant = { "I'm between jobs.", 'Odd jobs, here and there.' },
        stolen = { 'I do odd jobs.', 'Nothing right now.' },
    },
    nervous = {
        ran = { "You chased me. Of course I'm nervous.", "I'm out of breath, that's all." },
        default = { "Yeah, sorry. Getting pulled over just makes me nervous.", "I'm fine, I'm just not used to this.",
                    "Everything's fine, officer." },
        nervous = { "Sorry, I always get nervous around police. I haven't done anything.", "I'm fine. Just shaky. Long day." },
        drugs = { "I'm not nervous. It's just cold.", "I'm fine. Can I go?", "Who wouldn't be nervous?" },
        stolen = { "I'm fine! Just... in a hurry.", "Nervous? No. Why would I be nervous?" },
        warrant = { "I just don't like cops. No offense.", "I'm fine. Is this going to take much longer?" },
        drunk = { "I'm not nervous. I'm just tired.", "I'm fine, really." },
        rude = { "I'm nervous because you're holding me up.", "I'm not nervous. I'm annoyed." },
        still = {
            default = { 'Yeah, sorry. Police make me nervous.', "I'm fine, I'm just not used to this.", "Everything's fine, officer." },
            nervous = { "Sorry, I always get nervous around police. I haven't done anything.", "I'm fine. Just shaky. Long day." },
            drugs = { "I'm not nervous. It's just cold.", "I'm fine. Can I go?", "Who wouldn't be nervous?" },
            stolen = { "I'm fine! Just... in a hurry.", 'Nervous? No. Why would I be nervous?' },
            warrant = { "I just don't like cops. No offense.", "I'm fine. Is this going to take much longer?" },
            drunk = { "I'm not nervous. I'm just tired.", "I'm fine, really." },
            rude = { "I'm nervous because you're holding me up.", "I'm not nervous. I'm annoyed." },
        },
    },
    others = {
        default = { "It's just me.", "Just me, officer." },
        passengers = { 'Just my friend.', "My buddy. I'm giving him a ride.", 'My girlfriend.', 'My cousin.' },
        stolen = { "Just a friend. Doesn't matter.", "Some guy I'm giving a ride to." },
    },
    pdest = {
        default = { "Oh, yeah. We're dropping them off there first.", "Right, we're stopping there too. I forgot.",
                    "That's after. I'm taking them there, then going to {dest}." },
        guilty = { "Uh... yeah. Yeah, that's what I meant.", "They don't know what they're talking about.",
                   "I said {dest}. I don't know why they'd say that.", "...We're going to both. Does it matter?" },
    },

    -- licence and identity
    name = {
        default = { '{first} {last}. Born {dob}.', "It's {first} {last}, {dob}." },
    },
    age = {
        default = { "I'm {age}.", '{age}.', "{age}, officer." },
        chatty = { "{age}. Don't remind me!" },
    },
    address = {
        default = { "{street}, in Los Santos.", "It's {street}." },
        warrant = { "I'm staying with a friend right now.", "I move around a lot. Last place was on {street}." },
        stolen = { "I'm kind of between places.", "Uh, {street}. I think the number's changed." },
    },
    valid = {
        default = { "Yes, it's valid.", 'Yes, officer.', set = { licence = 'valid' } },
        expired = { { "I think so? It might have expired, actually.", set = { licence = 'expired' } },
                    { 'Yes.', set = { licence = 'valid' } } },
        suspended = { { 'Yes.', set = { licence = 'valid' } }, { "Yeah, it's fine.", set = { licence = 'valid' } },
                      { "...No. It's suspended.", set = { licence = 'suspended' } } },
        unlicensed = { { 'Yeah, of course.', set = { licence = 'valid' } }, { 'I have one. Just not on me.', set = { licence = 'valid' } },
                       { "No. I never got one.", set = { licence = 'none' } } },
    },
    sure_lic = {
        default = { "Yes, I'm sure. Check it.", 'Positive.' },
        suspended = { { "Okay... it's suspended. I'm sorry.", set = { licence = 'suspended' } }, "I'm pretty sure.",
                      'Yes. Why do you keep asking?' },
        unlicensed = { { "Alright. I don't have one. I never got it.", set = { licence = 'none' } }, 'Yes. I just left it at home.' },
        expired = { { "Actually... it might be expired.", set = { licence = 'expired' } }, "I think so." },
    },
    why_susp = {
        default = { 'Too many tickets.', 'Unpaid fines. I was going to sort it out.', 'A DUI a couple of years back.',
                    "I didn't have insurance for a while." },
    },
    why_none = {
        default = { "Never got around to it.", "I failed the test. Twice.", "Couldn't afford the lessons.",
                    "I've been meaning to. I just haven't." },
    },
    renew = {
        default = { "I forgot, honestly.", "The DMV line was three hours. I gave up.", "I didn't get the letter.",
                    "I've been busy. I'll do it this week." },
    },
    otherid = {
        default = { 'Just my bank card.', "No, that's it.", "I've got my work badge." },
        warrant = { "No. Nothing.", "I don't carry any." },
        stolen = { 'No.', "Just what I gave you." },
    },

    -- the vehicle
    owner = {
        mine = { "Yes, it's mine.", "Yeah, it's in my name.", "Yes, officer, it's my car.", set = { owns = 'mine' } },
        family = { "It's my family's car. It's in {owner_first}'s name.", "No, it's {owner}'s. We share it.", set = { owns = 'family' } },
        passenger = { "It's not mine. I'm just getting a ride.", "No, I'm only the passenger." },
        stolen = { { "It's my buddy's. I'm borrowing it.", set = { owns = 'friend' } },
                   { "It's my cousin's car.", set = { owns = 'family' } }, { "Yeah, it's mine.", set = { owns = 'mine' } } },
    },
    ownername = {
        family = { "{owner}.", "It's {owner}'s.", "{owner}. It's on the registration." },
        stolen = { "Uh... Mike. Mike something.", "Chris. I don't know his last name.", "It's... I just call him Smitty.",
                   "Why do you need his name?" },
    },
    ownerknows = {
        default = { 'Yes, of course.', "Yeah, I asked first.", "It's fine, they let me use it all the time." },
        stolen = { "Yeah. Yeah, he knows.", "Of course he knows. You can call him. Well, not right now, he's asleep.",
                   "He said it was fine." },
    },
    howlong = {
        default = { 'A couple of years.', 'About six months.', 'Since it was new.', 'I bought it last year.' },
        stolen = { 'A while.', '...A few weeks?', "Not long. Why?" },
    },
    reg = {
        default = { "Yes, it's current.", 'Should be.', "Yes, I just renewed it." },
        lapsed = { "I think it's expired. I've been meaning to deal with it.", "Is it? I didn't know.",
                   "I'm sorry, the renewal's sitting on my kitchen table." },
        stolen = { "I'd have to check. It's not mine.", "No idea." },
    },
    insurance = {
        default = { "Yes, it's insured.", "Yeah, I've got the card here somewhere.", "Yes, officer." },
        lapsed = { "It... lapsed last month. I'm getting it sorted.", "I think so?", "I'm between policies." },
        stolen = { "Probably? It's not mine.", "You'd have to ask the owner." },
    },
    problems = {
        default = { 'No, it runs fine.', 'The check engine light comes on sometimes.', 'Not that I know of.' },
        stolen = { "I don't know, I've only had it a little while.", 'No.' },
    },

    -- their driving
    speed = {
        default = { 'Not really. Was I going too fast?', 'Around the limit, I think.', "I wasn't paying attention, sorry.",
                    'Maybe a little over?' },
        drunk = { "I was going slow. Really slow.", "Not fast. I was being careful." },
        stolen = { 'No.', 'I was going the speed limit.' },
        rude = { "I was keeping up with traffic.", "Not as fast as everyone else." },
    },
    limit = {
        default = { 'Forty-five?', "Thirty-five, I think.", "I'm not sure, sorry.", "Isn't it fifty here?" },
    },
    signal = {
        default = { "I thought I did.", "Sorry, I forgot.", "Nobody was behind me." },
        drunk = { 'I did signal. Didn\'t I?', 'Sorry. I forgot.' },
        rude = { "Nobody was there.", "Seriously? That's why you stopped me?" },
    },
    light = {
        default = { "It was yellow when I went through.", "I didn't see it, I'm sorry.", "I thought I had time." },
        drunk = { "What light?", "I'm pretty sure it was green." },
        rude = { "It was yellow.", "Come on, it had barely changed." },
    },
    phone = {
        default = { 'No, it was in my pocket.', 'Just the GPS.', "No, officer.", "I glanced at it, sorry." },
        chatty = { "Just changing the song! I know, I know." },
    },
    belt = {
        default = { 'Yes.', 'Yeah, always.', "I just took it off when you pulled me over." },
        rude = { "Yeah. Obviously.", 'Does it matter?' },
    },

    -- alcohol and drugs
    drink = {
        default = { 'No, nothing.', "No, officer, I don't drink.", 'Not a drop.', set = { drank = 'no' } },
        drunk = { { 'Just a couple of beers. Hours ago.', set = { drank = 'yes', amount = 'a couple of beers', when = 'hours ago' } },
                  { "No, nothing. I'm fine.", set = { drank = 'no' } }, { 'No.', set = { drank = 'no' } },
                  { 'One glass of wine with dinner.', set = { drank = 'yes', amount = 'one glass of wine', when = 'at dinner' } } },
        passenger = { 'Not tonight.', 'No.', { "A beer. But I'm not driving.", set = { drank = 'yes', amount = 'a beer', when = 'earlier' } },
                      set = { drank = 'no' } },
        foot = {
            default = { 'No, nothing.', "No, officer, I don't drink.", 'Not a drop.', set = { drank = 'no' } },
            drunk = { { 'Just a couple of beers. Hours ago.', set = { drank = 'yes', amount = 'a couple of beers', when = 'hours ago' } },
                      { "No, nothing. I'm fine.", set = { drank = 'no' } },
                      { "A few. But I'm walking home.", set = { drank = 'yes', amount = 'a few beers', when = 'tonight' } } },
        },
    },
    howmuch = {
        default = { 'Just {amount}.', "Like I said, {amount}. That's it.", 'Only {amount}, I swear.' },
        drunk = { 'Just {amount}.', "...Maybe a little more than {amount}.", "{amount}. Maybe three. I'm fine to drive." },
        foot = {
            default = { 'Just {amount}.', "Like I said, {amount}. That's it.", 'Only {amount}, I swear.' },
            drunk = { 'Just {amount}.', "...Maybe a little more than {amount}.", "{amount}. Maybe three. I'm walking home, it's fine." },
        },
    },
    lastdrink = {
        default = { 'A few hours ago.', '{when}.', 'With dinner. Hours ago.' },
        drunk = { '{when}. A while ago.', "I don't know. An hour? Less?", "Right before I left. But I'm fine." },
    },
    smell = {
        default = { "I'm sure. I haven't had anything.", "It might be my passenger. Not me.", "I haven't been drinking, I promise." },
        drunk = { { "Okay... okay. I had a few beers at a friend's.", set = { drank = 'yes', amount = 'a few beers', when = 'an hour ago' } },
                  "It's not me. Someone spilled a drink in here earlier.", "I said I haven't been drinking.",
                  { 'Fine. I had one. Just one.', set = { drank = 'yes', amount = 'one', when = 'a while ago' } } },
    },
    drugsuse = {
        default = { 'No, nothing.', "No. I don't do drugs.", 'Never.', set = { used = 'no' } },
        drugs = { { 'No.', set = { used = 'no' } }, { "No. Why would you ask that?", set = { used = 'no' } },
                  { 'I smoked a little earlier. Hours ago.', set = { used = 'yes' } } },
        drunk = { 'No. Just... no.', set = { used = 'no' } },
    },
    whatdrug = {
        default = { 'Just weed. This morning.', 'A joint. Hours ago.', "Some weed with a friend. I'm fine now." },
    },
    eyes = {
        default = { "I'm just tired. Long day.", "Allergies.", "I've been staring at a screen all day." },
        drugs = { { "...Okay. I smoked a little before I left.", set = { used = 'yes' } }, "It's allergies.",
                  "I'm tired. That's all.", "I haven't smoked anything." },
        drunk = { "I'm just tired.", "It's late." },
    },
    meds = {
        default = { 'No.', 'Just allergy pills.', 'Blood pressure medication.', "Nothing that'd affect my driving." },
        drugs = { 'Some pills. For my back.', 'No.' },
        foot = { default = { 'No.', 'Just allergy pills.', 'Blood pressure medication.', 'Nothing strong.' },
                 drugs = { 'Some pills. For my back.', 'No.' } },
    },

    -- contraband and search
    illegal = {
        default = { 'No, nothing.', 'No, officer.', 'Just my gym bag.', 'Nope. You can look if you want.', set = { contra = 'no' } },
        drugs = { { 'No. Nothing. Why would there be?', set = { contra = 'no' } }, { "No, it's clean.", set = { contra = 'no' } },
                  { "I don't think so. No.", set = { contra = 'no' } },
                  { 'Just a little weed. For personal use.', set = { contra = 'yes' } } },
        drunk = { 'No.', 'Nothing illegal, no.', set = { contra = 'no' } },
        stolen = { "Not that I know of. It's not my car.", 'No.', set = { contra = 'no' } },
        foot = {
            default = { 'No, nothing.', 'No, officer.', 'Just my wallet and phone.', 'Nope. You can check if you want.', set = { contra = 'no' } },
            drugs = { { 'No. Nothing. Why would I?', set = { contra = 'no' } }, { "No, I'm clean.", set = { contra = 'no' } },
                      { "I don't think so. No.", set = { contra = 'no' } },
                      { 'Just a little weed. For personal use.', set = { contra = 'yes' } } },
            drunk = { 'No.', 'Nothing illegal, no.', set = { contra = 'no' } },
        },
    },
    drugsincar = {
        default = { 'No.', 'No drugs, no.', "Absolutely not.", set = { contra = 'no' } },
        drugs = { { 'No.', set = { contra = 'no' } }, { 'Why does everyone ask that? No.', set = { contra = 'no' } },
                  { "There might be a little weed in the glovebox. It's not much.", set = { contra = 'yes' } } },
        stolen = { "I don't know what's in here. It's not my car.", 'No.' },
        foot = {
            default = { 'No.', 'No drugs, no.', 'Absolutely not.', set = { contra = 'no' } },
            drugs = { { 'No.', set = { contra = 'no' } }, { 'Why does everyone ask that? No.', set = { contra = 'no' } },
                      { "There might be a little weed in my pocket. It's not much.", set = { contra = 'yes' } } },
        },
    },
    contra_what = {
        default = { "Just a little weed. A gram, maybe.", "Some weed. That's all, I swear.", "Just a bit. For personal use." },
    },
    weapons = {
        default = { 'No.', 'No weapons.', "Nothing like that.", "No, officer." },
        warrant = { 'No.', "There's a knife in the door. For work.", "No. Why?" },
        drugs = { 'No.', 'No guns, no.', "Just a pocket knife." },
        stolen = { "Not that I know of.", 'No.' },
        foot = { default = { 'No.', 'No weapons.', 'Nothing like that.', 'No, officer.' },
                 warrant = { 'No.', 'Just a knife. For work.', 'No. Why?' }, drugs = { 'No.', 'No guns, no.', 'Just a pocket knife.' } },
    },
    open = {
        default = { 'No.', "No, nothing open.", 'No, officer.' },
        drunk = { "No. Well... there might be a can in the back. It's empty.", 'No.', "Those are my buddy's." },
        foot = { default = { 'No.', 'No, nothing open.', 'No, officer.' },
                 drunk = { "No. Well... I had a can earlier. It's empty.", 'No.', "That's not mine." } },
    },
    cash = {
        default = { 'No, just a few bucks.', "Nobody carries cash anymore.", 'Maybe twenty dollars.' },
        drugs = { "A bit. I got paid today.", "Not really. Why?", "A few hundred. I'm buying a TV." },
        stolen = { 'No.', 'Some. Why?' },
    },
    search = {
        default = { 'Sure, go ahead.', "I'd rather you didn't, but okay.", "Go ahead. There's nothing in there.", set = { consent = 'yes' } },
        drugs = { { "No. I don't consent to searches.", set = { consent = 'no' } }, { "Do you have a warrant?", set = { consent = 'no' } },
                  { "...I'd rather you didn't.", set = { consent = 'no' } } },
        stolen = { { "It's not my car. I can't say yes.", set = { consent = 'no' } }, { 'Go ahead, I guess.', set = { consent = 'yes' } } },
        warrant = { { 'No. I know my rights.', set = { consent = 'no' } }, { 'Sure.', set = { consent = 'yes' } } },
        rude = { { "No. You don't have a reason.", set = { consent = 'no' } } },
        foot = {
            default = { 'Sure, go ahead.', "I'd rather you didn't, but okay.", "Go ahead. I don't have anything.", set = { consent = 'yes' } },
            drugs = { { "No. I don't consent to searches.", set = { consent = 'no' } }, { 'Do you have a warrant?', set = { consent = 'no' } },
                      { "...I'd rather you didn't.", set = { consent = 'no' } } },
            warrant = { { 'No. I know my rights.', set = { consent = 'no' } }, { 'Sure.', set = { consent = 'yes' } } },
            rude = { { "No. You don't have a reason.", set = { consent = 'no' } } },
        },
    },
    nosearch = {
        default = { "It's my right.", "I just don't like people going through my stuff.", "It's the principle of it." },
        drugs = { "Because I know my rights.", "There's nothing in there, so why do you need to look?",
                  "I just don't want you to. Am I free to go?" },
        stolen = { "It's not my car. I don't want to get in trouble.", "I don't know what's in there." },
        foot = {
            default = { "It's my right.", "I just don't like being searched.", "It's the principle of it." },
            drugs = { 'Because I know my rights.', "I don't have anything, so why do you need to look?",
                      "I just don't want you to. Am I free to go?" },
        },
    },
    -- opened by a search that found something of theirs
    explain = {
        default = { "That's not mine. I swear.", "I've never seen that before.", "Somebody must have left it there." },
        drugs = { "It's for personal use. It's just a little.", "That's not mine, I'm holding it for a friend.",
                  "...I don't know how that got there." },
        drunk = { "It's empty. Well, nearly.", "That's from earlier, I wasn't drinking it while driving." },
        stolen = { "That stuff came with the car.", "My buddy lent me the car, that's his.", "I use it for work." },
        warrant = { "It's for protection. This city's dangerous.", "That's not mine.", "I want to talk to a lawyer." },
        rude = { "I don't have to explain anything to you.", "Talk to my lawyer." },
        foot = {
            default = { "That's not mine. I swear.", "I've never seen that before.", "I'm holding it for someone." },
            drugs = { "It's for personal use. It's just a little.", "That's not mine, I'm holding it for a friend.",
                      "...I don't know how that got there." },
            drunk = { "It's empty. Well, nearly.", "I was just finishing it. I'm walking home." },
            warrant = { "It's for protection. This city's dangerous.", "That's not mine.", 'I want to talk to a lawyer.' },
            rude = { "I don't have to explain anything to you.", 'Talk to my lawyer.' },
        },
    },

    -- record and warrants
    arrested = {
        default = { 'No, never.', "No, officer.", set = { arrested = 'no' } },
        warrant = { { 'No.', set = { arrested = 'no' } }, { 'Once. A long time ago.', set = { arrested = 'yes' } },
                    { "Yeah, a while back. I'm clean now.", set = { arrested = 'yes' } } },
        drugs = { { 'No.', set = { arrested = 'no' } }, { 'Once, for possession. Years ago.', set = { arrested = 'yes' } } },
        stolen = { { 'No.', set = { arrested = 'no' } }, { 'Maybe once. Why?', set = { arrested = 'yes' } } },
    },
    arrest_for = {
        default = { 'It was a misunderstanding.', 'A fight. Years ago.', 'Possession. Small amount.', 'Shoplifting, when I was a kid.' },
    },
    probation = {
        default = { 'No.', "No, officer.", 'Never been.' },
        warrant = { 'No.', "...I was. It's finished.", "No. Why?" },
        drugs = { 'No.', 'I just got off it.' },
    },
    warrants = {
        default = { 'No.', 'Not that I know of.', "No, I don't think so.", set = { warrant = 'no' } },
        warrant = { { 'No.', set = { warrant = 'no' } }, { 'Not that I know of.', set = { warrant = 'no' } },
                    { "...Maybe. I missed a court date.", set = { warrant = 'yes' } } },
    },
    warrant_for = {
        default = { 'I missed a court date.', 'Some unpaid tickets, I think.', "I don't know. Something stupid." },
    },
    lastpolice = {
        default = { "Never, really.", "A speeding ticket a few years ago.", "This is the first time in years." },
        warrant = { "Been a while.", "I don't remember." },
        drugs = { "A while ago.", "Why does it matter?" },
    },

    -- a passenger, about the driver
    knowdriver = {
        default = { "We're friends from work.", "That's my brother.", "We're dating.", "Old friend from school.",
                    "My roommate.", "Just a friend." },
        stolen = { "I just met them. They're giving me a ride.", "Friend of a friend." },
    },
    pwhere = {
        -- set by the chooser: the driver's story, or one of their own
        same = { "Same as them, {driver_dest}.", "{driver_dest}, I think.", "We're going to {driver_dest}.",
                 set = { dest = '{driver_dest}' } },
        own = { { 'Home.', set = { dest = 'home' } }, { "A party, I think.", set = { dest = 'a party' } },
                { "The beach.", set = { dest = 'the beach' } }, { "I don't know, I'm just along for the ride.", set = { dest = "I don't know" } } },
    },
    pdrink = {
        default = { "No, not at all.", "No. They're fine.", "They don't even drink." },
        drunk = { "...Maybe a couple.", "I don't know. I wasn't watching.", "No. Well... a little." },
    },
    pdriving = {
        default = { 'Fine, I think.', "Normal. I wasn't really paying attention.", 'A bit fast, maybe.' },
        drunk = { 'Kind of all over the place.', "I told them to slow down.", 'Fine. I think.' },
        stolen = { 'Fast.', "I don't know." },
    },
    pcar = {
        default = { "The driver's.", "It's theirs.", "Their family's, I think." },
        stolen = { "I don't know. Not mine.", "Theirs? I think?", "Ask them." },
    },

    -- menu actions, not questions
    licence = {
        hands = { 'Here you go.', 'Sure, one second... here.', 'Here, officer.' },
        forgot = { 'I left my wallet at home, sorry.', "I don't have it on me.", 'I... must have left it at home.' },
        alias = { "I don't have it on me.", 'I left it at home. I can just tell you my name.' },
    },
    breath = { default = { 'Okay.', 'Sure, fine.', "Do I have to? ...Okay." },
               drunk = { "I've only had a couple, I swear.", 'Is that really necessary?' } },
    drugtest = { default = { "Go ahead, I've got nothing to hide.", 'Okay.' },
                 drugs = { "Wait, what? Do I have to?", "...Fine." } },
    follow = { default = { 'Okay, coming.', 'Alright.' }, rude = { 'Fine. Whatever.' } },
    handsup = { default = { 'Okay! Okay!', "Alright, they're up!" }, nervous = { "Don't shoot! They're up!" } },
    exit = { default = { 'Okay.', 'Sure.', 'Alright.' }, rude = { 'Seriously? Fine.', 'Is this necessary?' },
             nervous = { 'Okay, okay.', 'Am I in trouble?' } },
    back = { default = { 'Thanks.', 'Okay.' } },
    cite = { default = { 'Okay. Thank you, officer.', 'Alright, I understand.' }, rude = { 'Unbelievable.', 'Whatever.' } },
    warn = { default = { "Thank you, officer. I'll be careful.", 'Thanks, I appreciate it.' } },
    release = { default = { 'Thanks, officer. Have a good one.', 'Thank you.' }, rude = { 'Finally.', 'Can I go now?' } },

    -- searches, tests and arrests
    frisk = { default = { 'No, nothing.', 'Just my wallet and phone.', 'Go ahead.' },
              drugs = { 'Uh, no. Nothing.', 'Do you have to?' }, warrant = { '...No.', 'Nothing, I swear.' },
              rude = { "Don't touch me.", 'This is harassment.' } },
    search_car = { default = { 'Okay.', "Go ahead, there's nothing in there." },
                   drugs = { "Wait, you can't just do that!", "Come on, there's nothing in there." },
                   stolen = { "That's not even my stuff in there.", 'Do you have to?' }, drunk = { '...Okay.' },
                   rude = { 'You need a warrant for that.', 'Unbelievable.' } },
    sobriety = { default = { 'Sure, okay.', 'Alright.' }, drunk = { 'I can do that, easy.', 'Right now? Okay...' },
                 drugs = { 'Is this really necessary?', 'Okay... okay.' } },
    cuff = { ran = { "Okay, okay... I shouldn't have run.", 'Alright. You got me.', "I know. I know. I'm done running." },
             default = { 'Wait, what? What for?', 'Am I under arrest?' }, warrant = { 'Come on, man...', "This is about that old thing, isn't it?" },
             rude = { "You're making a big mistake.", 'I want a lawyer.' }, nervous = { "Please, I didn't do anything!" } },
    uncuff = { default = { 'Thank you.', 'Finally.' } },
    escort = { default = { "Okay, okay. I'm walking.", 'Alright.' }, rude = { "Don't push me." } },
    seat = { default = { '...', 'Okay.' }, rude = { 'This is ridiculous.', 'I want a lawyer.' } },
    unseat = { default = { 'Okay.', 'Thanks.' } },
    sit = { default = { 'Okay.', 'Alright, alright.' }, rude = { 'On the ground? Seriously?' } },
    getup = { default = { 'Okay.', 'Thanks.' } },
    refuse = { default = { "I'm not getting out. What's this about?", 'Why do I need to get out?' },
               rude = { 'No. I know my rights.', "I'm not getting out of my car." } },
    run = { default = { 'No way!', "I'm not going back!", 'Forget this!' } },
    surrender = { default = { 'Okay! Okay! I give up!', "Don't shoot! I'm done!", 'Alright, alright...' } },

    -- a felony stop
    felony = { default = { "Okay! Okay! The engine's off!", "Don't shoot! Keys are out!", 'Alright! Alright!' },
               warrant = { '...Okay.', 'Alright, man. Alright.' }, stolen = { "It's not my car! I swear!", '...Okay.' } },
    freeze = { default = { "I- I can't- don't shoot!", 'What? What do you want me to do?', '...' },
               nervous = { "Please don't shoot! Please!", "I'm scared, I can't move!" }, rude = { 'For what?!', "I didn't do anything!" } },
    fel_out = { default = { "Okay! I'm coming out!", "Don't shoot! I'm getting out!", 'Hands are up! Hands are up!' },
                rude = { 'This is insane!', "Fine! I'm out!" } },
    fel_back = { default = { 'Okay, okay...', "I'm walking! I'm walking!", 'Like this?' } },
    fel_kneel = { default = { 'Okay! Okay!', "I'm down! I'm down!", "Please don't shoot." }, rude = { 'This is ridiculous.' } },
}
Dialogue.LINES = LINES

-- Questions whose answer depends on more than the secret: they choose their own line set.
local CHOOSE = {
    owner = function(o)
        if o.truth.secret == 'stolen' then return 'stolen' end
        local v = o.vehicle
        if v and v.owner_id and o.person and v.owner_id ~= o.person.id then return 'family' end
        return 'mine'
    end,
    ownername = function(o) return o.truth.secret == 'stolen' and 'stolen' or 'family' end,
    reg = function(o)
        if o.truth.secret == 'stolen' then return 'stolen' end
        return o.vehicle and o.vehicle.reg_valid == false and 'lapsed' or 'default'
    end,
    insurance = function(o)
        if o.truth.secret == 'stolen' then return 'stolen' end
        return o.vehicle and o.vehicle.ins_valid == false and 'lapsed' or 'default'
    end,
    others = function(o, ctx)
        if o.truth.secret == 'stolen' and (ctx.passengers or 0) > 0 then return 'stolen' end
        return (ctx.passengers or 0) > 0 and 'passengers' or 'default'
    end,
    pdest = function(o) return GUILTY[o.truth.secret] and 'guilty' or 'default' end,
    -- a passenger tells the driver's story, unless the driver has something to hide and didn't coach them
    pwhere = function(o, ctx)
        if ctx.driver_dest and not (ctx.driver_guilty and math.random() < .6) then return 'same' end
        return 'own'
    end,
    -- what a passenger says about the driver depends on the driver
    pdrink = function(o, ctx) return ctx.driver_secret == 'drunk' and 'drunk' or 'default' end,
    pdriving = function(o, ctx) return LINES.pdriving[ctx.driver_secret] and ctx.driver_secret or 'default' end,
    pcar = function(o, ctx) return ctx.driver_secret == 'stolen' and 'stolen' or 'default' end,
}

-- Nerves and attitude, layered on top of what they say.
local OPENERS = {
    nervous = { 'Uh... ', 'Um, ', 'I, uh... ' },
    rude = { 'Why does it matter? ', 'Is this really necessary? ' },
}
local CLOSERS = { chatty = { " It's been a long day.", ' Crazy traffic out tonight, huh?', ' My boss is going to kill me.' } }
local FLAVOURED = { why = true, where = true, illegal = true }
for _, q in ipairs(Dialogue.QUESTIONS) do if q.stress then FLAVOURED[q.id] = true end end
local REMEMBERED = { licence = true } -- answers kept for "Like I said": the questions (not the pressing ones) and the licence
for _, q in ipairs(Dialogue.QUESTIONS) do if not q.press then REMEMBERED[q.id] = true end end

local function pick(list) return list[math.random(#list)] end

local function fill(text, vars)
    return (text:gsub('{([%w_]+)}', function(k) return vars[k] or '' end))
end

-- The set of lines for question q.
local function lines_for(q, o, ctx, lines)
    local t = o.truth
    if lines[1] then return lines end -- (a callout's plain list)
    if o.facts and o.facts.ran and lines.ran then return lines.ran end -- they know what they did
    if o.role == 'pedestrian' and lines.foot then lines = lines.foot
    elseif (o.role == 'pedestrian' or ctx.still) and lines.still then lines = lines.still end
    if CHOOSE[q] then return lines[CHOOSE[q](o, ctx)] or lines.default end
    if o.role == 'passenger' and lines.passenger then return lines.passenger end
    if q == 'licence' then return lines[t.id or 'hands'] end
    return lines[t.secret] or lines[t.demeanor] or lines.default
end

-- What the other people in the car have said, for questions that weigh one story against another.
local function context(o, ctx)
    ctx = ctx or {}
    local s, out = ctx.stop, { passengers = 0 }
    if not s then return out end
    out.still = s.foot or s.parked -- not pulled over: walked up to on foot, or sat in a parked car
    for _, x in pairs(s.occ or {}) do
        if x.role == 'passenger' then
            out.passengers = out.passengers + 1
            if x.facts and x.facts.dest and not out.p_dest then out.p_dest = x.facts.dest end
        end
    end
    local d = s.driver
    if d and d ~= o then
        out.driver_first = d.person and d.person.first
        out.driver_dest = d.facts and d.facts.dest
        out.driver_secret = d.truth and d.truth.secret
        out.driver_guilty = GUILTY[out.driver_secret]
    end
    return out
end

local function vars_for(o, ctx)
    local p, t, f = o.person or {}, o.truth, o.facts
    local who = t.id == 'alias' and t.alias or p -- the false name, every time
    local owner = o.vehicle and o.vehicle.owner or ''
    local year = tonumber(tostring(who.dob or ''):match('(%d%d%d%d)$'))
    local drug = o.items and o.items[1] and o.items[1]:lower() or 'some weed'
    return {
        first = who.first, last = who.last, dob = who.dob, age = year and (os.date('*t').year - year) or '',
        street = (p.address or ''):gsub('^%d+%s+', ''), owner = owner, owner_first = owner:match('^(%S+)') or owner,
        dest = f.dest, from = f.from, amount = f.amount, when = f.when, drug = drug, found = f.found,
        driver_first = ctx.driver_first or 'the driver', driver_dest = ctx.driver_dest, p_dest = ctx.p_dest,
    }
end

-- A line, and the facts it gives away (its own, then its list's).
local function entry(list)
    local e = pick(list)
    if type(e) == 'table' then return e[1], e.set or list.set end
    return e, list.set
end

--[[ What they answer. o = the person: { person, truth, vehicle, items, role, answers = {}, facts = {} }.
     ctx = { stop = s } so they can weigh what the others in the car have said. ]]
local function extra_def(q, o)
    for _, d in ipairs(o.extra and o.extra.questions or {}) do if d.id == q then return d end end
end
local function def_of(q, o) return extra_def(q, o) or DEF[q] end

function Dialogue.answer(q, o, ctx)
    local own = o.extra and o.extra.lines and o.extra.lines[q]
    if type(own) == 'function' then own = own(o) end -- (a callout's: decided as it's asked, e.g. who can hear)
    if not (own or LINES[q]) then return nil end
    o.facts = o.facts or {}
    o.asked = o.asked or {}
    o.asked[q] = true -- (the menu's "Asked": pressing questions aren't in o.answers)
    local xd = extra_def(q, o)
    local remembered = REMEMBERED[q] or (xd and not xd.press)
    local again = remembered and o.answers[q]
    if again then return 'Like I said... ' .. again end -- unchanged: it may start with a name or "I"

    ctx = context(o, ctx)
    local vars = vars_for(o, ctx)
    local text, set = entry(lines_for(q, o, ctx, own or LINES[q]))
    for k, v in pairs(set or {}) do o.facts[k] = fill(v, vars) end
    for k, v in pairs(o.facts) do vars[k] = v end
    text = fill(text, vars)

    local t = o.truth
    if FLAVOURED[q] or (xd and xd.stress) then
        local open, close = OPENERS[t.demeanor], CLOSERS[t.demeanor]
        if open then text = pick(open) .. text:gsub('^%u', string.lower) end
        if close then text = text .. pick(close) end
    end
    if remembered then o.answers[q] = text end
    return text
end

-- Can this person be asked q now? (who it's for, and the facts it needs or that close it)
local CAR_TOPICS = { vehicle = true, driving = true, passenger = true }
local function open(def, o, ctx)
    if def.who and def.who ~= o.role then return false end
    if o.role == 'pedestrian' and CAR_TOPICS[def.cat] then return false end
    local f = o.facts or {}
    for k, want in pairs(def.needs or {}) do
        local have = f[k]
        if want == true then
            if have == nil then return false end
        elseif type(want) == 'table' then
            local any = false
            for _, w in ipairs(want) do any = any or have == w end
            if not any then return false end
        elseif have ~= want then
            return false
        end
    end
    if def.when and not def.when(o, ctx) then return false end
    return true
end

-- The officer's question, as asked of this person (some name what the other person said).
function Dialogue.label(q, o, ctx)
    local def = def_of(q, o)
    o.facts = o.facts or {}
    return def and fill(o.role == 'pedestrian' and def.foot or def.label, vars_for(o, context(o, ctx))) or q
end

function Dialogue.can_ask(q, o, ctx)
    local def = def_of(q, o)
    return def ~= nil and open(def, o, context(o, ctx))
end

--[[ The questions this person can be asked now, for the menu:
     { { id, cat, label, asked = bool, follow = bool } } - follow: opened by something they said. ]]
function Dialogue.available(o, ctx)
    o.facts = o.facts or {}
    ctx = context(o, ctx)
    local vars, out = vars_for(o, ctx), {}
    for _, def in ipairs(o.extra and o.extra.questions or {}) do -- a callout person's own, under "The call"
        if open(def, o, ctx) then
            out[#out + 1] = { id = def.id, cat = 'call', label = fill(def.label, vars),
                              asked = (o.asked or {})[def.id] == true, follow = def.needs ~= nil or def.when ~= nil }
        end
    end
    for _, def in ipairs(Dialogue.QUESTIONS) do
        if open(def, o, ctx) then
            out[#out + 1] = { id = def.id, cat = def.cat, label = fill(o.role == 'pedestrian' and def.foot or def.label, vars),
                              asked = (o.asked or {})[def.id] == true, follow = def.needs ~= nil or def.when ~= nil }
        end
    end
    return out
end
