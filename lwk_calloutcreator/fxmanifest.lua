fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lwk_calloutcreator'
description 'LWK Callout Creator: make CODE3RESPONSE callouts in game, without writing code'
version '0.0.1'
author 'LWK DEVELOPMENT'
license 'CC-BY-NC-SA-4.0'

dependency 'c3r'

shared_scripts { 'config/main.lua' }
client_script 'client/main.lua'
server_scripts { 'server/generator.lua', 'server/main.lua' }

ui_page 'nui/index.html'
files { 'nui/index.html', 'nui/app.js', 'nui/style.css', 'nui/data.js' }

-- packs/: the packs made here (index.json lists them; <pack>.<callout>.lua each callout). export/: packs written out as
-- standalone resources, to copy to any c3r server.
