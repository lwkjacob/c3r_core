fx_version 'cerulean'
game 'gta5'

name 'lwk_control_assets'
description 'Static files for lwk_control: speech model + runtime, dispatcher voice clips, radio clicks'
version '0.1.0'
author 'LWK DEVELOPMENT'
license 'GPL-3.0-only'

-- Kept out of lwk_control so code updates don't rebuild and re-download ~210 MB for every player:
-- FXServer packs each resource's client files into one archive and re-sends it when any file changes.
-- lwk_control's page loads these through https://cfx-nui-lwk_control_assets/ (FiveM allows that).

-- A (blank) ui_page so older FiveM clients register this resource's cfx-nui- address.
ui_page 'nui/blank.html'

files {
    'nui/blank.html',
    'nui/sherpa/*.js',
    'nui/sherpa/*.wasm',
    'nui/sherpa/*.data',
    'nui/clicks/*.wav',
    'nui/voice/*.ogg',
    'nui/voice/letters/*.ogg',
    'nui/voice/vehicle/*.ogg',
    'nui/voice/numbers/*.ogg',
    'nui/voice/places/*.ogg',
}
