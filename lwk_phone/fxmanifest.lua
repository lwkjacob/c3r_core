fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lwk_phone'
author 'LWK Development'
version '1.1.2'
description 'LWK Phone - a phone for QBCore, Qbox, ESX, ox_core, ND_Core and standalone servers'
repository 'https://github.com/lwkjacob/lwk_phone'

ui_page 'web/dist/index.html'

files {
  'web/dist/index.html',
  'web/dist/theme.json',
  'web/dist/assets/*',
  'web/dist/themes/*',
  'web/dist/wallpapers/*',
  'web/dist/sounds/*',
  'web/dist/example-app/*',
  'tiles/**/*.webp',
  'config/locales/*.json',
}

shared_scripts {
  '@ox_lib/init.lua',
  'config/config.lua',
  'shared/util.lua',
  'shared/locale.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'config/keys.lua',
  'config/bridge/framework.lua',
  'config/bridge/banking.lua',
  'config/bridge/inventory.lua',
  'config/bridge/voice.lua',
  'config/bridge/housing.lua',
  'config/bridge/transfer.lua',
  'server/db.lua',
  'server/main.lua',
  'server/messages.lua',
  'server/calls.lua',
  'server/social.lua',
  'server/apps.lua',
  'server/exports.lua',
  'server/transfer.lua',
  'server/compat.lua',
  'server/check.lua',
}

client_scripts {
  'config/bridge/client.lua',
  'client/main.lua',
  'client/prop.lua',
  'client/camera.lua',
  'client/apps.lua',
  'client/exports.lua',
  'client/compat.lua',
}

dependencies {
  'ox_lib',
  'oxmysql',
}
