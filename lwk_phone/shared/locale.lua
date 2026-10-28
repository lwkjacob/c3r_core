-- Locale loader shared by server and client. Strings live in config/locales/<code>.json:
--   "server": messages sent from Lua (errors, notifications)
--   "ui":     every string the phone shows (sent to the UI when the phone loads)
-- Missing keys fall back to English, then to the key itself.

local function load(code)
    local raw = LoadResourceFile(GetCurrentResourceName(), ('config/locales/%s.json'):format(code))
    return raw and json.decode(raw) or nil
end

local fallback = load('en') or {}
local active = (Config.locale ~= 'en' and load(Config.locale)) or fallback

Locale = {}

--- Message with %s placeholders filled in order.
function L(key, ...)
    local s = (active.server and active.server[key]) or (fallback.server and fallback.server[key]) or key
    if select('#', ...) > 0 then s = s:format(...) end
    return s
end

--- The UI string table for a non-English server, or nil (the UI bundles English itself).
function Locale.ui()
    if active == fallback then return nil end
    return active.ui
end

function Locale.intl()
    return (active.meta and active.meta.intl) or 'en-US'
end
