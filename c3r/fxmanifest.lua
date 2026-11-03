fx_version 'cerulean'
game 'gta5'

name 'c3r'
description 'CODE3RESPONSE: free, open-source police game mode'
version '0.0.1'
author 'LWK DEVELOPMENT'
license 'CC-BY-NC-SA-4.0'

dependency 'oxmysql'

ui_page 'nui/index.html'

shared_scripts { -- config/main.lua first: it makes Config
    'config/main.lua',
    'config/stops.lua',
    'config/people.lua',
    'config/patrol.lua',
    'config/backup.lua',
    'config/medical.lua',
    'config/ems.lua',
    'config/callouts.lua',
    'config/presence.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/data.lua',
    'server/generator.lua',
    'server/dialogue.lua',
    'server/main.lua',
    'server/stops.lua',
    'server/callouts.lua',
    'server/ems_body.lua',
    'server/ems.lua',
    'server/stats.lua',
    'server/presence.lua',
    'callouts/*.lua', -- the calls (server only: the truth never reaches a game)
    'callouts/ems/*.lua', -- medics' calls
    'server/config_labels.lua',
    'server/config_edit.lua',
}

client_scripts {
    'client/main.lua',
    'client/ui.lua',
    'client/stop.lua',
    'client/menu.lua',
    'client/radial.lua',
    'client/pa.lua',
    'client/staged.lua',
    'client/backup.lua',
    'client/medical.lua',
    'client/ems.lua',
    'client/callouts.lua',
    'client/presence.lua',
}

-- stream/: c3r_gurney (the ambulance stretcher, c3r/models/build_gurney.py), and the custom@ animations
data_file 'DLC_ITYP_REQUEST' 'stream/c3r_gurney.ytyp'

files { 'nui/index.html', 'nui/img/code3response.png', 'nui/voice/*.ogg' }
