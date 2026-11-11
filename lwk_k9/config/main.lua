Config = {}

Config.Debug = false -- true: F8 logs what the dog is doing

-- Who gets what is c3r's call, no aces of its own: on duty as police in c3r (c3r's Config.DutyAce decides who can),
-- a police dog (Sniff, Attack, Track); anyone else, a pet (Heel, Sit, Down, Speak, the car, Dismiss).

-- Rebindable in Settings > Key Bindings > FiveM. Empty = no default, bind it there if you like.
-- The K9 slice is on c3r's G wheel for officers on patrol; the wheel key opens it anywhere (pets off duty too).
Config.Keys = {
    wheel = 'K',
    heel = '',
    sit = '',
    down = '',
    speak = '',
    car = '',     -- in / out of your car
    options = '', -- the dog's breed, name and look (also /k9)
}

-- The breeds players can pick. police = true: it can be a police dog (an officer without the ace still only gets a pet).
-- anims: which set of Config.Anims it uses. Add-on animals: stream the model, add a line with its model name.
Config.Breeds = {
    { model = 'a_c_shepherd', label = 'German Shepherd', police = true, anims = 'shepherd' },
    { model = 'a_c_rottweiler', label = 'Rottweiler', police = true, anims = 'rottweiler' },
    { model = 'a_c_husky', label = 'Husky', police = true, anims = 'retriever' },
    { model = 'a_c_pug', label = 'Pug', anims = 'small' },
    { model = 'a_c_westy', label = 'Westie', anims = 'small' },
    { model = 'a_c_poodle', label = 'Poodle', anims = 'small' },
    { model = 'a_c_cat_01', label = 'Cat', anims = 'cat' },
}

-- What each command plays: { scenario = name } or { dict, anim }. car = sat in a seat.
-- Every name is in GTA's files (DurtyFree's scenario and animation dumps). Not yet seen in game: that the shepherd
-- (rottweiler rig) and husky (retriever rig) take the clips below well, and the in-car sit for the smaller ones.
Config.Anims = {
    rottweiler = {
        sit = { scenario = 'WORLD_DOG_SITTING_ROTTWEILER' },
        down = { dict = 'creatures@rottweiler@amb@sleep_in_kennel@', anim = 'sleep_in_kennel' },
        bark = { scenario = 'WORLD_DOG_BARKING_ROTTWEILER' },
        car = { dict = 'creatures@rottweiler@in_vehicle@std_car', anim = 'sit' },
    },
    shepherd = {
        sit = { scenario = 'WORLD_DOG_SITTING_SHEPHERD' },
        down = { dict = 'creatures@rottweiler@amb@sleep_in_kennel@', anim = 'sleep_in_kennel' },
        bark = { scenario = 'WORLD_DOG_BARKING_SHEPHERD' },
        car = { dict = 'creatures@rottweiler@in_vehicle@std_car', anim = 'sit' },
    },
    retriever = {
        sit = { scenario = 'WORLD_DOG_SITTING_RETRIEVER' },
        down = { dict = 'anim@scripted@freemode@animals@dogs@retriever@sleeping_in_kennel@', anim = 'sleep_in_kennel' },
        bark = { scenario = 'WORLD_DOG_BARKING_RETRIEVER' },
        car = { dict = 'creatures@retriever@amb@world_dog_sitting@base', anim = 'base' },
    },
    small = {
        sit = { scenario = 'WORLD_DOG_SITTING_SMALL' },
        down = { scenario = 'WORLD_DOG_SITTING_SMALL' }, -- (small dogs have no lie-down of their own)
        bark = { scenario = 'WORLD_DOG_BARKING_SMALL' },
        car = { dict = 'creatures@pug@amb@world_dog_sitting@base', anim = 'base' },
    },
    cat = {
        sit = { scenario = 'WORLD_CAT_SLEEPING_LEDGE' },
        down = { scenario = 'WORLD_CAT_SLEEPING_GROUND' },
        bark = { scenario = 'WORLD_CAT_SLEEPING_LEDGE' }, -- (a cat doesn't bark on command)
        car = { dict = 'creatures@cat@amb@world_cat_sleeping_ground@base', anim = 'base' },
    },
}

-- Sniff: the dog only alerts on what it can smell. An item counts when its name has one of these words in it.
Config.Smells = { 'marijuana', 'weed', 'cannabis', 'cocaine', 'crack', 'powder', 'meth', 'heroin', 'fentanyl', 'pills',
                  'pipe', 'drug', 'pistol', 'revolver', 'gun', 'rifle', 'shotgun', 'ammo', 'round', 'explosive' }

-- Where the dog sat, as the card and the report say it
Config.Where = {
    driver = 'driver door', passenger = 'front passenger door', rear_left = 'rear left door',
    rear_right = 'rear right door', trunk = 'trunk', person = 'on the person',
}

Config.Bite = {
    hold_seconds = 6,  -- how long it holds them once it has them
    range = 80.0,      -- m from you: further than this and it's called off
    min_health = 130,  -- the dog never takes them below this (200 = full, 100 = dead)
}

Config.Track = {
    minutes = 5,      -- how old a trail can be
    pick_up = 40.0,   -- m: a player's trail has to pass this close to you for the dog to pick it up
    wait_for = 18.0,  -- m: further behind than this and the dog waits for you
}
