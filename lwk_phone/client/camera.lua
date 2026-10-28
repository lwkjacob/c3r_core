-- Camera mode. The game's own phone camera does the framing (and the selfie pose); the UI
-- draws that view inside the phone's viewfinder and captures it from there.
--
-- Aiming: Config.cursorKey hands the mouse back to the game. The rear camera then looks around
-- like first person. The selfie camera does not move on its own, so the mouse is turned into
-- movement of the phone around the player's face here.
--
-- Walking: the game's phone camera roots the player to the spot. The walk key swaps it for a view
-- the player can move with (and back again): first person for the rear camera, and for selfies a
-- camera held out in front of the face. The viewfinder shows whatever the game is drawing, so it
-- simply follows.

Camera = {}

local on, selfie = false, false
local walking, selfieCam, viewMode = false, nil, nil

-- Where the walking selfie camera sits, relative to the player: metres in front, metres above the
-- hips, and its field of view.
-- ponytail: picked by reasoning, not by eye. Nudge these three after looking at it in the game.
local SELFIE_AHEAD, SELFIE_UP, SELFIE_FOV = 0.9, 0.65, 55.0

--- The game's own phone camera, up or away.
local function cellCam(up)
    if up then
        CreateMobilePhone(0)
        CellCamActivate(true, true)
        CellCamActivateSelfieMode(selfie)
    else
        CellCamActivate(false, false)
        DestroyMobilePhone()
    end
end

--- Leave whichever walking view is up. Does not bring the phone camera back: the caller decides.
local function stopWalking()
    if selfieCam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(selfieCam, false)
        selfieCam = nil
    end
    if viewMode then
        SetFollowPedCamViewMode(viewMode)
        viewMode = nil
    end
    walking = false
end

local function startWalking()
    cellCam(false)
    walking = true
    if selfie then
        local ped = PlayerPedId()
        selfieCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        AttachCamToEntity(selfieCam, ped, 0.0, SELFIE_AHEAD, SELFIE_UP, true)
        PointCamAtEntity(selfieCam, ped, 0.0, 0.0, SELFIE_UP, true)
        SetCamFov(selfieCam, SELFIE_FOV)
        RenderScriptCams(true, false, 0, true, false)
    else
        viewMode = GetFollowPedCamViewMode()
        SetFollowPedCamViewMode(4)   -- first person
    end
    -- In a selfie the player is seen holding the phone; from first person it would only be in the way.
    Prop.hide(not selfie)
    SetTimeout(250, function()
        if on and walking then Prop.call(false) end
    end)
end

-- Selfie framing. Each native takes one number and the game does not document its range.
-- If the phone moves too slowly, too fast, or stops short of where it should, tune these two.
local PAN_SPEED, PAN_LIMIT = 0.05, 1.0
local pan = { x = 0.0, y = 0.0 }

local function clamp(v) return math.max(-PAN_LIMIT, math.min(PAN_LIMIT, v)) end

local function frame()
    if walking or not selfie or not GameHasMouse() then return end
    local dx, dy = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)   -- look left/right, up/down
    if dx == 0 and dy == 0 then return end
    pan.x, pan.y = clamp(pan.x + dx * PAN_SPEED), clamp(pan.y + dy * PAN_SPEED)
    CellCamSetHorizontalOffset(pan.x)
    CellCamSetVerticalOffset(pan.y)
end

local function recentre()
    pan.x, pan.y = 0.0, 0.0
    CellCamSetHorizontalOffset(0.0)
    CellCamSetVerticalOffset(0.0)
end

function Camera.start(front)
    local flipped = selfie ~= (front == true)
    selfie = front == true
    if on then
        if walking then
            -- The two sides walk with different views: change over.
            if flipped then
                stopWalking()
                startWalking()
            end
            return
        end
        CellCamActivateSelfieMode(selfie)
        if flipped then recentre() end
        return
    end
    on = true
    Prop.hide(true)
    cellCam(true)
    recentre()
    CreateThread(function()
        while on do
            HideHudAndRadarThisFrame()
            DisableControlAction(0, 36, true)   -- duck / stealth: the walk key's default is the same key
            frame()
            Wait(0)
        end
    end)
end

--- Whether the camera is up, and whether it is the selfie camera.
function Camera.state() return on, on and selfie end

function Camera.stop()
    if not on then return end
    on = false
    if walking then stopWalking() else cellCam(false) end
    Prop.hide(false)
    -- The game's phone took over the arm while the camera was up. Once it lets go, hold ours again.
    SetTimeout(250, function()
        if IsPhoneOpen() and not on then Prop.call(false) end
    end)
end

Local['camera'] = function(data)
    if not data.on then return Camera.stop() end
    Camera.start(data.selfie)
    return { ok = true, keys = { aim = KeyLabel(Keys.cursor), shutter = KeyLabel(Keys.shutter), flip = KeyLabel(Keys.flip), walk = KeyLabel(Keys.walk) } }
end

-- Walk around with the camera up, and stand still again for the steadier phone camera.
Keys.walk = lib.addKeybind({
    name = 'lwk_phone_walk',
    description = L('key_walk'),
    defaultKey = 'LCONTROL',
    onPressed = function()
        if not on then return end
        if walking then
            stopWalking()
            Prop.hide(true)
            cellCam(true)
            recentre()
        else
            startWalking()
        end
    end,
})

-- With the mouse handed back to the game (Config.cursorKey) the shutter needs a key.
Keys.shutter = lib.addKeybind({
    name = 'lwk_phone_shutter',
    description = L('key_shutter'),
    defaultKey = 'RETURN',
    onPressed = function()
        if on then SendNUIMessage({ action = 'camera', event = 'shutter' }) end
    end,
})

Keys.flip = lib.addKeybind({
    name = 'lwk_phone_flip',
    description = L('key_flip'),
    defaultKey = 'UP',
    onPressed = function()
        if on then SendNUIMessage({ action = 'camera', event = 'flip' }) end
    end,
})
