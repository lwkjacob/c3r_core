fx_version 'cerulean'
game 'gta5'

name 'lwk_control'
description 'Offline voice dispatch for c3r'
version '0.0.1'
author 'LWK DEVELOPMENT'
license 'GPL-3.0-only'

ui_page 'nui/index.html'

-- The speech model, voice clips and clicks live in lwk_control_assets (see its fxmanifest for why).
dependencies { 'lwk_control_assets', 'c3r' }

shared_scripts {
    'config.lua',
    'shared/brain.lua',
}

client_scripts {
    'client/voice.lua',
    'client/intents.lua',
    'client/pa.lua',
    'client/checks.lua',
    'client/traffic.lua',
    'client/units.lua',
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
    'server/asr.js', -- recognition for players whose game browser has no WebAssembly
}

files {
    'nui/index.html',
    'nui/ears.js',
    'nui/ears-worklet.js',
    'nui/voice.js',
    'nui/settings.js',
    'nui/hotwords.txt',
    'nui/bpe.vocab',
}
