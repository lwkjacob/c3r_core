-- LWK Phone configuration. Secrets (upload token, webhook) live in config/keys.lua, which only the server loads.

Config = {
    -- General -------------------------------------------------------------------
    locale    = 'en',          -- a file in config/locales/: 'en' or 'fr' (README, "Languages", for adding one)
    framework = 'auto',        -- auto | qbox | qb | esx | ox | nd | standalone
    bank      = 'auto',        -- company accounts: auto | a bank's resource name | none   (the list is in config/bridge/banking.lua)
    debug     = false,         -- prints every RPC to the server console

    -- Apps other resources add (community apps) go to the App Store, where players install the ones they want.
    -- true: an app that asks to be installed for everyone (defaultApp) is put straight on the home screen.
    autoInstallApps = false,

    -- Opening the phone -----------------------------------------------------------
    keybind = 'GRAVE',         -- the key under Escape. Default only; players rebind it in the game's key settings
    gameTime  = true,          -- the phone's clock shows the game's time of day; false for the player's own clock
    command = 'phone',
    walk    = true,            -- keep moving while the phone is up (false = full cursor focus)
    cursorKey = 'LMENU',       -- hold the phone up but hand the mouse back to the game (aim the camera)

    -- The phone as an item ----------------------------------------------------------
    -- 'auto' turns both on when a framework AND an inventory the phone knows are running (README,
    -- "The phone as an item"). `unique` needs an inventory whose items carry data; ESX's own does not.
    -- Standalone servers always get one phone per player.
    item = {
        name      = 'phone',
        inventory = 'auto',    -- auto | ox | qb | ps | codem | core | jaksam | tgiann | esx | none   (config/bridge/inventory.lua)
        require   = 'auto',    -- the player must carry the item to open the phone
        unique    = 'auto',    -- each item is its own phone: number and data live on the item, so phones can be stolen
    },

    -- Phone numbers: <prefix> plus `digits` random digits, shown as 555-0142 -------------
    numbers = { prefixes = { '555' }, digits = 4 },

    -- Calls ---------------------------------------------------------------------------
    calls = {
        ringSeconds = 30,      -- unanswered calls become missed calls after this
        voice       = 'auto',  -- auto | pma | salty | mumble | none   (none = calls connect but carry no audio)
    },

    -- Video and live streams travel player-to-player over WebRTC. Direct routes often fail
    -- across home networks, so add a TURN server here for reliable video.
    rtc = { iceServers = { { urls = 'stun:stun.l.google.com:19302' } } },

    -- Photo, video and audio hosting ------------------------------------------------------
    -- `hosts`: the only places a picture, video or voice message in a text or a post may be loaded from.
    -- Without it, anyone could send a link to their own server and collect the IP address of every
    -- player whose phone shows it. Leave it as your upload host. {} allows any host.
    upload = { provider = 'fivemanage', hosts = { 'fivemanage.com' } },   -- token goes in config/keys.lua; '' there disables capture

    -- Maps ----------------------------------------------------------------------------------
    -- The map of San Andreas ships with the phone (the tiles/ folder), as a road map and a satellite view.
    -- Only for a server with its own map: `image` is a URL to one picture that replaces it, and `bounds`
    -- are the game coordinates of that picture's edges.
    map = {
        image  = '',
        bounds = { minX = -4000.0, maxX = 4500.0, minY = -4000.0, maxY = 8000.0 },
    },
    places = {
        { name = 'Legion Square',      kind = 'Landmark',   x = 195.0,   y = -934.0 },
        { name = 'Del Perro Pier',     kind = 'Attraction', x = -1850.0, y = -1230.0 },
        { name = 'Pillbox Medical',    kind = 'Hospital',   x = 300.0,   y = -585.0 },
        { name = 'Mission Row PD',     kind = 'Police',     x = 428.9,   y = -984.5 },
        { name = 'Vinewood Sign',      kind = 'Landmark',   x = 711.0,   y = 1198.0 },
        { name = 'LS International',   kind = 'Airport',    x = -1037.0, y = -2737.0 },
    },

    -- Services: companies players can call or message. `job` is the framework job name. --------
    -- icon: police | ambulance | mechanic | taxi | realestate | lawyer
    companies = {
        { job = 'police',    name = 'Police',    desc = 'Los Santos Police Department', color = '#0a84ff', icon = 'police' },
        { job = 'ambulance', name = 'Ambulance', desc = 'Emergency Medical Services',   color = '#ff3b30', icon = 'ambulance' },
        { job = 'mechanic',  name = 'Mechanic',  desc = 'Repairs and towing',           color = '#ff9500', icon = 'mechanic' },
        { job = 'taxi',      name = 'Taxi',      desc = 'Downtown Cab Co.',             color = '#ffcc00', icon = 'taxi' },
    },

    -- Moving from another phone: when its tables are still in the database, everyone keeps the number they
    -- had there, and setup offers to bring their contacts, texts, calls, photos and notes across.
    -- 'auto' finds NPWD or GCPhone; 'none' switches it off. (README, "Moving from another phone".)
    transfer = 'auto',

    -- Home: the housing script behind the Home app. 'auto' finds nolag_properties, vms_housing, rtx_housing,
    -- bcs_housing, RxHousing, ps-housing, qbx_properties, qb-houses or esx_property; 'none' hides the app.
    -- (README, "Housing".)
    housing = 'auto',

    -- Garage -------------------------------------------------------------------------------------
    -- fromImpound = false: impounded vehicles cannot be released from the phone and have to be collected.
    garage = { valetFee = 100, impoundFee = 250, fromImpound = true },

    -- Music: no songs ship with the phone. Add your own (direct links to audio files). -------------
    -- The Music app is hidden while this list is empty.
    -- { title = 'Night Shift', artist = 'Vespucci Drive', album = 'Coastlines', url = 'https://...', cover = 'https://...', seconds = 214 }
    music = {},

    -- Crypto: made-up coins whose prices drift on their own. Bought and sold with bank money. --------
    crypto = {
        enabled = true,
        tickSeconds = 60,
        coins = {
            { id = 'LSC', name = 'Santos Coin', price = 41820.5, color = '#f7931a' },
            { id = 'VNW', name = 'Vinewood',    price = 2210.18, color = '#627eea' },
            { id = 'PLT', name = 'Paleto',      price = 96.42,   color = '#14f195' },
            { id = 'CHP', name = 'ChopCoin',    price = 0.0841,  color = '#c2a633' },
            { id = 'MZE', name = 'Maze',        price = 13.07,   color = '#e84142' },
        },
    },

    mailDomain = 'lsmail.net',
    licence    = '',           -- the heading on the Wallet's licence card, e.g. 'Liberty City · Driver Licence'. '' = the language file's text
    airShareRange = 8.0,       -- metres

    -- The phone in the player's hand -------------------------------------------------------------
    prop = { model = 'prop_npc_phone_02', bone = 28422 },
    anim = {
        dict = 'cellphone@',            carDict = 'cellphone@in_car@ds',
        open = 'cellphone_text_in',     idle = 'cellphone_text_read_base',
        call = 'cellphone_call_listen_base', close = 'cellphone_text_out',
    },

    -- Admins (delete any post, /phoneverify, /phonepassword) ------------------------------------------
    adminAce = 'lwk_phone.admin',
}
