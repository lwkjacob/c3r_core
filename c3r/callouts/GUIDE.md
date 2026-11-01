# Writing callouts for CODE3RESPONSE

A callout is one Lua file in this folder. c3r loads every `.lua` file here when it starts. There's nothing to register and no manifest to edit. This guide takes you from an empty file to a call that works on a live server.

The shipped callouts are worked examples worth reading:
- `_example.lua`, the template, with every option explained
- `domestic.lua`
- `robbery.lua`
- `hitrun.lua`
- `armed.lua`, which has armed people who draw, fire and give up
- `stalking.lua`, which has someone who drives off from spot to spot
- `crisis.lua`, where how the officer behaves matters more than what they find
- `hazard.lua`, with something to drag, tyres to burst, traffic to hold and a road crew to call
- `shots.lua`, with real bangs, a standoff that can be talked down and a shooter who runs
- `bar.lua`, with two people fighting each other and a taxi home
- `overdose.lua`, with a clock on someone's life
- `racing.lua`, with several cars running in different directions and a crowd scattering

> **Back up your own callouts.** An update can replace this folder. Keep a copy of your files somewhere else, and put them back after you update.

## How a call plays

1. Every few minutes dispatch puts a call out to every officer on duty: "Incoming 911 call". Anyone can press **Y** to respond, and several units can share one call.
2. A unit getting close (300 m, `Config.Callouts.build`) makes the scene: the people, the cars and the evidence. The people are real records, so name checks, plate checks and the MDT all find them.
3. Each unit on scene holds one **objective** on its card, and units get different ones. Whoever completes an objective, it's done for everyone.
4. Officers press **E** on people to talk to them. The usual menu (ID, questions, search, tests, cuffs) comes with your own questions on top, under **The call**. Evidence shows **E Inspect**.
5. Your code decides what's true and how it ends. When it's dealt with, `c:finish(summary)` completes the call, and the summary goes on every unit's MDT report.

## The one rule that makes a callout good

The report says one thing; the truth is one of several **stories**, picked at random. Every story shares the same reports and the same opening objectives, so the card never gives the story away. Story-specific objectives stay **hidden** until something the officer finds reveals them. Players should have to do police work, not read the card.

## Step by step

### 1. Copy the template

Copy `_example.lua` to a new file, for example `noise.lua`, and give it a unique `id`:

```lua
Callout({
    id = 'noise',              -- unique; /requestcall noise asks for it
    name = 'Noise complaint',  -- on the offer and the card
    priority = 3,              -- 1 (urgent) to 3
    voice = 'call_noise',      -- optional: dispatch's line (lwk_control_assets/nui/voice/call_noise_1.ogg; call_noise_to_1.ogg leads into the location). Left out, or no such file: "Incoming 911 call."
    weight = 1,                -- how often it comes up, against the other callouts
    enabled = true,            -- false: never offered (still /requestcall-able)
    reports = {                -- what the caller said: one is picked, the same pool for every story
        'Caller reports loud music and shouting from a house party.',
        'Neighbour says a party has been going since midnight and someone is screaming.',
    },
    points = { ... },
    locations = { ... },
    stories = { ... },
})
```

### 2. Name the points

`points` lists every spot a location needs, in the order `/c3rplace` will walk you through them. The first point is where the call is: units count as "on scene" within 40 m of it (`Config.Callouts.arrive`). Add `'car'` as a third value for a spot where a car is parked.

```lua
points = {
    { 'caller', 'The neighbour who called, on their own doorstep.' },
    { 'host', 'Whoever is throwing the party, at the front door.' },
    { 'yard', 'Something in the front yard: on the ground.' },
    { 'car', 'A car parked badly on the lawn. Sit in a car parked there.', 'car' },
},
```

Write each description so someone placing it in game knows exactly where to stand.

**Optional points:** add `optional = true` to a point that not every location has:

```lua
{ 'witness', 'A witness outside, on the pavement.', optional = true },
{ 'car', 'The getaway car.', 'car', optional = true },
```

- In `/c3rplace`, **Z** skips it. The first point can't be optional.
- At a location without it, any person, car or clue placed there isn't made, and an objective that only marks them isn't on the card. Everything else carries on, but `c:who(key)` is nil for them, so check before reading their facts.
- A story that can't work without some points says so, and only plays at locations that have them:

```lua
active = { weight = 2, needs = { 'holdup', 'window' }, setup = function(c) ... end },
```

### 3. Place locations in game

As an admin (the `command.c3rconfig` ace), type `/c3rplace noise`. Stand on each point, face the way the person should face, and press **E**. For a car point, sit in a car parked where it should be. **Z** skips an optional point, **Backspace** goes back a point, and **X** cancels.

On the last point, the location is written into your file and is in use straight away. `/c3rplace noise 2` replaces location 2. It also saves the street each point is on, which matters for addresses (see `home` below).

You can write locations by hand too. `/c3rpos <name>` copies your position as `vector4(...)`, ready to paste:

```lua
locations = {
    { street = 'Grove St', at = vector3(100.4, -1937.0, 20.8), points = {
        caller = vector4(118.13, -1945.35, 20.69, 84.6),
        host = vector4(106.35, -1953.22, 20.72, 330.2),
        ...
    } },
},
```

Points can be any distance from the call. Each person, car and prop is made when a unit gets within 300 m of it, so a hiding place or a house round the corner is fine.

### 4. Write the stories

Each story has a `weight` (how often it's picked) and a `setup(c)` that builds it with the `c:` calls below:

```lua
stories = {
    loud = { weight = 3, setup = function(c)
        c:person('caller', { at = 'caller', label = 'Neighbour', scene = 'WORLD_HUMAN_STAND_MOBILE',
            questions = CALLER_Q, lines = { c_what = { 'Music. Loud. Since midnight. That is all.' } } })
        -- ...
    end },
    fight = { weight = 1, setup = function(c) ... end },
},
```

Put anything shared between stories (questions, the card, the ending) in local functions at the top of the file, as the shipped callouts do. Then every story builds the same card.

### 5. People and what they say

```lua
local HOST_Q = {
    { id = 'c_party', label = "Whose party is this?" },
    { id = 'c_scream', label = 'Someone heard screaming.', needs = { c_heard = true }, stress = true, press = true },
}

c:person('host', { at = 'host', label = 'Host', male = true, home = true, secret = 'drunk', demeanor = 'rude',
    scene = 'WORLD_HUMAN_DRINKING', questions = HOST_Q, items = { 'Bag of pills' }, lines = {
        c_party = { "Mine. It's my birthday. You want a drink?" },
        c_scream = { 'Screaming? Singing. Happy birthday. Badly.',
                     { '...Alright, there was a fight. It is over now.', set = { c_fight = 'yes' } } },
    } })
```

**Person options:**

| Option | What it does |
|---|---|
| `label` | What the card and the speech show until they've been identified ('Caller', 'Man'). |
| `male` | true or false. Left out: random. |
| `model` | A ped model name. Left out: an ordinary local. |
| `secret` | Their hidden truth: `clean`, `nervous`, `drunk`, `drugs`, `warrant`, `unlicensed`, `suspended`. Breath tests, searches and name checks all follow it. |
| `demeanor` | `polite`, `nervous`, `rude` or `chatty`. |
| `age` | `{ min, max }`: how old their ID says they are. |
| `home` | `true`: they live at the call's address. A point name such as `'driver'`: they live on that point's street. |
| `family` | `true`: everyone with `family = true` shares one surname. |
| `items` | What a search finds that **matters**: it shows as evidence and sets the `found` fact. |
| `pockets` | Everyday things a search finds that aren't evidence ('Gas station receipt'). |
| `injured` | `true`: on the ground hurt. E beside them opens first aid, paramedics take them, and `'aid'` fires. |
| `vitals` | What **Check vitals** says about someone `injured`, instead of the bleeding. |
| `runs` | `true`: pulled over while driving (see `c:task(..., 'drive')`), they floor it and it's a chase. `bail = 0.3`: how often it ends with them on foot. |
| `seated` | A vehicle key: they start at the wheel of it, engine running. Give them the car's point as `at`, and make the car `locked = false`. |
| `weapon` | A weapon name ('WEAPON_PISTOL'): what they use when told to `aim` or `shoot`. It's not shown until then. Put it in `items` too, so a search finds it. |
| `scene` | What they're doing: a scenario name, or `{ dict, anim }`. |
| `questions` | Their questions under **The call**: `{ id = 'c_...', label, needs?, press?, stress? }`. |
| `lines` | What they say: `lines[question id] = { 'one answer', 'or another' }`. |
| `facts` | Facts they start with. |

**Questions:**
- `needs = { c_fact = true }` shows the question only once that fact is known.
- `press = true` gives a fresh answer each time it's asked; without it they say "Like I said...".
- `stress = true` lets nerves show in the answer.

**Lines:**
- A line can give away a **fact**: `{ 'He went that way.', set = { c_way = 'north' } }`.
- Your facts must start with `c_`. c3r refuses a callout that sets any other fact, because the engine uses its own names.
- A line can be a **function**, decided at the moment it's asked: `c_safe = function(o) return c:apart('man', 'woman') and TRUTH or COVER end`.
- Lines can replace an answer to a normal question too (`where`, `live`, `address`...).

**Denial that cracks under pressure:** the pattern used in the shipped callouts, with a `press` question.

```lua
local function cracks(times, deny, admit, again)
    local n = 0
    return function(o)
        if o.facts.c_admit then return again end
        n = n + 1
        return n >= times and admit or deny
    end
end
-- c_store = cracks(3, { 'What store?' }, { { 'Alright. I needed the money.', set = { c_admit = 'yes' } } }, { 'I told you.' })
```

### 6. Cars and evidence

```lua
c:vehicle('car', { at = 'car', model = 'asea', make = 'Declasse', name = 'Asea', color = 'Silver', paint = 4,
    owner = 'host', stolen = false, locked = true, damage = 'front', label = 'His car' })

c:clue('yard', { at = 'yard', label = 'The yard', prop = 'prop_cs_beer_bot_01',
    text = 'Broken bottles all over the lawn, and a smear of blood on the path.' })
c:clue('car', { on = 'car', label = 'His car', hidden = true, text = 'A crack across the windscreen, from the inside.' })
```

**Vehicles:**
- The plate is made for you and is on file. Run it and it comes back registered to `owner` (a person key), or to someone else.
- `make`, `name` and `color` are what the plate check says. `paint` is the GTA colour index.
- `damage = 'front'` smashes the front end.

**Clues:**
- `scatter = { model = 'x', count = 8, radius = 4.0 }` lays more of the prop around it.
- `drag = true`: once inspected, **E** picks the prop up and **E** lets it go, and `dragged` fires.
- `spikes = 6.0`: any car driven within that many metres loses its tyres, until `c:clear`.
- A clue sits on a point (`at`) or on a car (`on`).
- With a `prop`, an object lies there. Until it's looked at, an amber arrow hangs over it (or over the car it's on).
- `hidden = true` keeps it out of reach until `c:reveal(id)`.
- The first look puts the text on every unit's MDT.

Check model, prop and scenario names against the game's lists. A wrong name just doesn't appear.

### 7. The card

```lua
c:objective('caller', 'Talk to the caller', { hint = 'Next door.', blip = 'caller' })
c:objective('door', 'Make contact at the door', { blip = 'host' })
c:objective('yard', 'Look around the yard', { blip = 'yard' })
c:objective('fight', 'Find who was hurt', { hidden = true, blip = 'guest' })
c:objective('decide', 'Deal with it: arrest, ticket or warn, or let them go', { after = { 'door' }, who = 'all', blip = 'host' })
```

**Objective options:**
- `who = 'one'` (the default) means one unit holds it. `'all'` puts it on everyone's card.
- `after = { ids }` keeps it locked until those are done.
- `hidden = true` keeps it off the card until `c:reveal(id)`.
- `blip` marks a person, car or clue key (or a list of them) on the map of whoever holds it.

**Start with three or so objectives that can be done at the same time**, so a second and third unit have real work.

### 8. React to what officers do

`c:on(event, function(...) end)`:

| Event | Arguments | When |
|---|---|---|
| `build` | | The scene was made. |
| `arrive` | src | A unit got there. |
| `contact` | person, src | Someone started talking to them. |
| `act` | person, action, arg, src | Anything done with them. `ask` (arg = question id), `licence`, `frisk`, `breath`, `cuff`, `uncuff`, `cite`, `warn`, `release`... |
| `fact` | person, fact, value, src | Something they gave away (a line's `set`). |
| `contact_ended` | person, outcome, src | `released`, `cited`, `warning`, `arrested`, `fled`, or `cancelled` (walked off). |
| `inspect` | clue, src | Evidence looked at, the first time. |
| `custody` | person, how, src | A prisoner taken in: `booked` at a station, or `transport`. |
| `aid` | person, what, src | Someone injured seen to. First aid gives `vitals`, `pressure`, `cpr` or `narcan`; paramedics give `hospital` or `treated`. |
| `gone` | person | They no longer exist (taken away, or deleted). |
| `dead` | person | They've died, once. (`dead = true` on a person: they're found that way, such as an animal in the road; `gone` fires when the coroner or animal control takes them.) They become a casualty: paramedics and the coroner see to them, and `aid` gives `pronounced` too. Handle this for anyone an objective or the ending depends on, or the call can stick. See `resolve()` in `armed.lua`. |
| `fired` | person | Someone told to `shoot` really has fired, once. Announce shots here, not when you give the order. |
| `aimed` | person, src | A unit on the call has a gun on them, within 40 m. Fires every few seconds while they do. |
| `hail` | person, src | An officer told someone who's shooting to drop it: E beside them, or the PA with a gun on them. |
| `parked` | person | Someone told to `drive` has arrived and got out of the car. |
| `dragged` | clue, clear, src | A `drag` clue was let go. `clear`: moved a couple of metres and off the road. |
| `service` | kind, src | A backup unit finished its job at the call: `dot`, or `taxi` once a `c:fare` is aboard. |
| `stunned` | person | Someone in a `brawl` was tased, by lwk_taser or the game's stun gun. |
| `leave` | src | A unit left the call. |
| `tick` | seconds | Once a second. |

Every objective needs something here that marks it done. An objective nothing completes leaves the call stuck until the units leave.

### 9. End it

Call `c:finish(summary)` when it's dealt with. The summary is the last line of every unit's MDT report, so say what happened and what's on record.

The shipped callouts end:
- when everyone arrested has been taken in (after a cuff, `c:custody(person)` puts "Take them in" on the card, and `'custody'` fires when they're booked or transported);
- or when the person it's about is ticketed, warned, let go, gets away or dies;
- or when the main witness has been heard and every unit has left for 15 seconds (`c:near` / `c:talking` in a `tick`).

Copy `resolve()` from `robbery.lua` or `hitrun.lua` for a solid ending.

Units can always leave a call with **X** or by clearing with dispatch. The last unit off cancels it. A call also ends by itself after 30 minutes (`Config.Callouts.max_minutes`).

## Everything `c` can do

| Call | Does |
|---|---|
| `c:person(key, spec)` / `c:vehicle(key, spec)` / `c:clue(key, spec)` | Put someone, a car or evidence in the scene. |
| `c:objective(id, text, opts)` | A line on the card. |
| `c:done(id)` / `c:reveal(id)` / `c:hide(id)` / `c:is_done(id)` | Objective state. `reveal` also works on hidden clues. |
| `c:blip(id, keys)` | Change what an objective marks on the map. |
| `c:custody(person)` | They're under arrest: the card says to take them in. |
| `c:who(person)` | Their record on the call: `.facts`, `.cuffed`, `.person` (name, address...). Read it, don't replace it. |
| `c:name(person)` / `c:plate(vehicle)` / `c:owner(vehicle)` / `c:street()` | Real names, plates, who a car is registered to, the call's street. |
| `c:near(person, m)` / `c:near(nil, m)` | Is any unit within m metres of them, or of the call. |
| `c:apart(a, b)` | Out of each other's earshot: more than 10 m apart, or either cuffed or in a car. |
| `c:talking()` / `c:talking(person)` | Is an officer talking to anyone on the call, or to them. |
| `c:questions(person)` | After giving them a fact from elsewhere: the officer talking to them sees what it opens. |
| `c:task(person, 'go' \| 'flee' \| 'surrender' \| 'wander' \| 'scene', point?)` | What they do now. `go` walks them to a point. |
| `c:task(person, 'drive', { car = 'key', to = 'point', fast = true })` | `fast`: flat out, through traffic. With no `to` they just keep going. Into that car (make it `locked = false`) and off to the point, in traffic. They get out there and `parked` fires; if they're not there after 2 minutes they stop where they are. Officers can pull them over on the way, and it's still them. Returns false if it can't happen: the car or point isn't there, or an officer's talking to them. `stalking.lua` is the example. |
| `c:task(person, 'brawl', other)` | Fists, on another person on the call (give both the task, from `build` on). Nobody can talk to them until `surrender`; pressing E or the PA fires `hail`, and a taser fires `stunned`. `bar.lua` is the example. |
| `c:fare(person)` | They're waiting for a ride: a taxi called to the scene takes them, and `service` fires with `taxi`. |
| `c:task(person, 'aim', other)` | Their `weapon` out, pointed at another person on the call. Use it from `build` on. |
| `c:task(person, 'hold')` | Their `weapon` out, waiting. Nobody can talk to them until `surrender`; pressing E or the PA fires `hail`. `armed.lua`'s `inside` story is the example. |
| `c:patient(person)` | Someone unhurt who'll go with paramedics: an ambulance called to the scene takes them, and `aid` fires. `crisis.lua` is the example. |
| `c:bang('WEAPON_PISTOL', 'point', shots?)` | A real shot straight up from that point, sound and all, on the nearest unit's game. `WEAPON_FIREWORK` for a firework. Nobody's hurt. |
| `c:clear(clue, keep?)` | The clue's dealt with: its prop goes (stays, with `keep`), and it can't be inspected, dragged or burst tyres any more. |
| `c:held()` | Is anyone holding traffic at the call ("hold traffic" on the radio)? `nil` if `lwk_control` isn't running. |
| `c:remove(person, car?)` | Gone from the world, with their car: got clean away. `gone` fires. |
| `c:die(person)` | They die now: someone down whose time has run out. CPR and paramedics can still bring them back. |
| `c:collapse(person, vitals?)` | They drop where they stand, as if `injured`: first aid, paramedics and `aid`. Ends any conversation with them. |
| `c:task(person, 'shoot', point?)` | They fight every player near. With no `weapon`, with their fists. If an officer is talking to them, the talking ends. With a point (a window, a doorway), they go there and hold it, using cover. Without one, they come after the officer. They fire at up to about 40 m, so start it from no further than that. Nobody can talk to them until `surrender`, which your call must do: see `dangerous()` in `armed.lua`. |
| `c:health(person)` | Their health: 200 is unhurt, 100 or less is dead. |
| `c:say(person, text)` | A line heard by units within 30 m. |
| `c:tell(src, title, text)` | Something one officer notices (a card on their screen). |
| `c:dispatch(text)` | A radio update to every unit on the call. |
| `c:note(text)` | A line on every unit's MDT incident. |
| `c:set(k, v)` / `c:get(k)` | The call's own memory. |
| `c:finish(summary)` | Done: completed, with the summary on the MDT. |

## Testing

1. Save the file and `restart c3r` (or `refresh` then `restart c3r` for a new file).
2. `/requestcall noise` makes your call now, near you, even with `enabled = false`. `/requestcall noise fight` picks that story.
3. Watch the server console. A broken file prints `callout noise left out: <why>`. An error in a story prints `[c3r] callout noise (story): <error>` and cancels only that call. Nothing else on the server breaks.
4. Play every story. Request the call until each one comes up, and check that the opening card is identical in all of them.
5. Try it with a second officer: do both have something to do?
