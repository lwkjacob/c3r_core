fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lwk_k9'
description 'Police dogs and pets for CODE3RESPONSE: Heel, Sit, Down, Speak, ride in your car, Sniff, Attack, Track'
version '0.0.1'
author 'LWK DEVELOPMENT'
license 'CC-BY-NC-SA-4.0'

shared_scripts { 'config/main.lua', 'shared/config_live.lua' }
client_scripts { 'client/main.lua', 'client/options.lua' }
server_script 'server/main.lua'

ui_page 'nui/index.html'
files { 'nui/index.html' }

dependency 'c3r'
