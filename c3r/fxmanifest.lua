fx_version 'cerulean'
game 'gta5'

name 'c3r'
description 'CODE3RESPONSE: free, open-source police game mode'
version '0.2.0'
author 'LWK DEVELOPMENT'
license 'GPL-3.0-only'

dependency 'oxmysql'

ui_page 'nui/index.html'

shared_scripts { -- config/main.lua first: it makes Config
    'config/main.lua',
    'config/stops.lua',
    'config/people.lua',
    'config/patrol.lua',
    'config/backup.lua',
    'config/medical.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/data.lua',
    'server/generator.lua',
    'server/dialogue.lua',
    'server/main.lua',
    'server/stops.lua',
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
}

files { 'nui/index.html', 'nui/img/code3response.png', 'nui/voice/*.ogg' }
