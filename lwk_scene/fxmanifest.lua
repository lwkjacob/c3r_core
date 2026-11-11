fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lwk_scene'
description 'Scene control for CODE3RESPONSE: cones, flares, barriers and police tape from the G wheel'
version '0.0.1'
author 'LWK DEVELOPMENT'
license 'CC-BY-NC-SA-4.0'

shared_scripts { 'config/main.lua', 'shared/config_live.lua', 'shared/scene.lua' }
client_script 'client/main.lua'
server_script 'server/main.lua'

files { 'img/tape_police.png', 'img/tape_crime.png' }

dependency 'c3r'
