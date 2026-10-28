fx_version 'cerulean'
game 'gta5'

name 'lwk_mdt'
description 'MDT for c3r, built to work with lwk_control'
version '0.0.1'
author 'LWK DEVELOPMENT'
license 'CC-BY-NC-SA-4.0'

dependencies { 'oxmysql', 'c3r' }

ui_page 'ui/index.html'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/token.js',
    'charges.lua',
    'server/records.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

files {
    'sounds/*.ogg',
    'ui/index.html',
    'ui/app.js',
}
