Config = {}

Config.Debug = false

Config.OpenKey = 'F7'          -- players can rebind it in Settings -> Key Bindings -> FiveM -> lwk_mdt
Config.OpenCommand = 'mdt'
Config.DefaultStyle = 'modern' -- 'modern', 'command', 'enterprise' or 'classic'; each officer can switch theirs in the CAD's settings

-- c3r services allowed to open the MDT (checked on the player's game).
Config.AllowedServices = { 'police' }

-- Optional ACE needed to use the MDT at all (nil = anyone on duty in an allowed service).
Config.AcePermission = nil

-- ACE that can edit or delete anyone's report, run /mdtexport and use Delete All Drafts. Authors can always edit
-- their own.
Config.SupervisorAce = 'lwk_mdt.supervisor'

-- Citizen Portal (players not on duty): flags a civilian can set on their own character.
Config.CivFlags = { 'ACTIVE WARRANT', 'WANTED PERSON', 'ARMED AND DANGEROUS', 'GANG AFFILIATION', 'PROBATION',
                    'PAROLE', 'MENTAL HEALTH', 'DRUG RELATED', 'VIOLENT HISTORY' }

-- 911 calls from the portal: area circle radius (m), seconds between one player's calls, and minutes a
-- call waits for a unit before it drops off the board.
Config.CalloutPopup = true -- c3r's callout popup: false, calls only show in the MDT. Each officer can change it in Settings.
Config.Call911Radius = 180.0
Config.Call911Cooldown = 60
Config.Call911ExpireMinutes = 15

-- Player identifiers (any type: fivem:, license:, discord:...) that also get the Delete All Drafts button.
Config.Admins = {} -- e.g. { 'fivem:123456', 'license:abc...' }

-- Browser pop-out (the Pop Out button opens the MDT in the player's own browser, e.g. on a second
-- monitor). nil = the address the player's game is connected to, e.g. http://203.0.113.5:30120.
-- Set it to use your own domain, e.g. 'https://mdt.example.com' (proxied to the server's port 30120).
Config.PopoutBaseUrl = nil

-- Records older than this are deleted on server start (0 = keep forever).
Config.KeepDays = 60
-- Most incidents kept; the oldest go first.
Config.MaxIncidents = 5000

-- An incident with no c3r or radio activity for this long is closed and becomes a draft.
Config.IdleMinutes = 15

Config.DateFormat = '%m/%d/%Y' -- os.date format for report dates

-- Charges are in charges.lua (California: Penal, Health & Safety and Vehicle Code).

-- Buttons in the status bar that run lwk_control intents (dispatch answers by voice as usual).
Config.Quick = {
    { label = 'Tow',       intent = 'request_tow' },
    { label = 'EMS',       intent = 'request_ambulance' },
    { label = 'Transport', intent = 'request_police' },
    { label = 'Coroner',   intent = 'request_coroner' },
    { label = 'Hold traffic',    intent = 'hold_traffic' },
    { label = 'Release traffic', intent = 'release_traffic' },
    { label = '10-8',  intent = 'status_10-8' },
    { label = '10-97', intent = 'status_10-97' },
}
