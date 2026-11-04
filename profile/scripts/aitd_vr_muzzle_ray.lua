-- Alone in the Dark (2024) UEVR: fire hitscan shots from the revolver muzzle along the barrel.
-- BP_HitscanWeapon_Base.TraceForTarget gets its ray from GetTraceParameters, which deprojects the
-- screen centre through the player camera, so shots leave the head (measured ~37 cm right of and
-- 14 cm above the muzzle, parallel to the barrel) and land beside the barrel line at close range.
-- hook_ptr never fires on these Blueprint functions (verified: 0 calls on GetTraceParameters and
-- TraceForTarget), but it does on the native PlayerController.DeprojectScreenPositionToWorld that
-- GetTraceParameters calls. While a hitscan weapon is aimed, around that call this script moves the camera manager's cached view
-- (CameraCachePrivate.POV, which the deprojection reads) to the MuzzleFlash component's position
-- and barrel rotation, then restores it. The red aim dot follows via aitd_muzzle_ray.

local api = uevr.api

local TRACE_FN = "Function /Script/Engine.PlayerController.DeprojectScreenPositionToWorld"
-- PlayerCameraManager.CameraCachePrivate (6912) + FCameraCacheEntry.POV (16); UE4 floats.
local POV_LOCATION = 6912 + 16
local TRACE_START_OFFSET = 80.0

local hooked = false
local failed = false
local saved = nil

local function log(message)
    print("[aitd_muzzle_ray] " .. message)
end

local function xyz(v)
    return v.X or v.x, v.Y or v.y, v.Z or v.z
end

-- Muzzle position and barrel direction of a hitscan weapon, or nil.
function aitd_muzzle_ray(weapon)
    -- aitd_vr_weapons.lua's version ignores the muzzle effect's random per-shot spin.
    if aitd_weapon_muzzle ~= nil then return aitd_weapon_muzzle(weapon) end
    local flash = weapon.MuzzleFlash
    if flash == nil then return nil end
    local mx, my, mz = xyz(flash:K2_GetComponentLocation())
    local fx, fy, fz = xyz(flash:GetForwardVector())
    return mx, my, mz, fx, fy, fz
end

aitd_muzzle_ray_stats = { calls = 0, moved = 0, last = "" }

local function camera_manager()
    local pc = api:get_player_controller(0)
    if pc == nil then return nil end
    return pc.PlayerCameraManager
end

local function on_pre(fn, obj, locals, result)
    local stats = aitd_muzzle_ray_stats
    stats.calls = stats.calls + 1
    saved = nil -- never restore a camera manager saved by an earlier call
    if aitd_options ~= nil and aitd_options.muzzle_aim == false then return end
    if AITD_WORLD_SETTLED == false then return end -- aitd_vr_ui.lua: loading or new pawn
    local ok, err = pcall(function()
        local pawn = api:get_local_pawn(0)
        if pawn == nil or not pawn:IsAiming() then return end
        local weapon = pawn:GetActiveWeapon()
        if weapon == nil or not weapon:get_full_name():find("HitscanWeapon", 1, true) then return end
        local mx, my, mz, fx, fy, fz = aitd_muzzle_ray(weapon)
        local pcm = camera_manager()
        if mx == nil or pcm == nil then return end
        saved = { pcm = pcm, values = {} }
        for i = 0, 5 do saved.values[i] = pcm:read_float(POV_LOCATION + i * 4) end
        local pitch = math.deg(math.asin(math.max(-1.0, math.min(1.0, fz))))
        local yaw = math.deg(math.atan(fy, fx))
        -- GetTraceParameters starts the trace a fixed 80 cm ahead of the view (measured from the head
        -- and from the muzzle alike), which would start point-blank shots past the wall. Back the view
        -- off along the barrel by that much so the trace starts at the muzzle.
        local d = TRACE_START_OFFSET
        local values = { [0] = mx - fx * d, my - fy * d, mz - fz * d, pitch, yaw, 0.0 }
        for i = 0, 5 do pcm:write_float(POV_LOCATION + i * 4, values[i]) end
        stats.moved = stats.moved + 1
    end)
    if not ok then stats.last = tostring(err) end
end

local function on_post(fn, obj, locals, result)
    if saved == nil then return end
    local ok, err = pcall(function()
        for i = 0, 5 do saved.pcm:write_float(POV_LOCATION + i * 4, saved.values[i]) end
    end)
    saved = nil
    if not ok then aitd_muzzle_ray_stats.last = tostring(err) end
end

local stats_timer = 0.0

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    stats_timer = stats_timer + delta
    if stats_timer > 2.0 and fs ~= nil and fs.write ~= nil then
        stats_timer = 0.0
        local s = aitd_muzzle_ray_stats
        fs.write("aitd_muzzle_ray.txt", string.format("hooked=%s failed=%s calls=%d moved=%d last=%s\n",
            tostring(hooked), tostring(failed), s.calls, s.moved, s.last))
    end
    if hooked or failed then return end
    -- find_uobject returns a plain UObject; hook_ptr lives on the UFunction view.
    local fn = api:find_uobject(TRACE_FN)
    if fn == nil then return end
    if fn.hook_ptr == nil then fn = fn:as_function() end
    local ok, err = pcall(function() fn:hook_ptr(on_pre, on_post) end)
    if ok then
        hooked = true
        log("hooked DeprojectScreenPositionToWorld")
    else
        failed = true
        aitd_muzzle_ray_stats.last = "hook failed: " .. tostring(err)
        log(aitd_muzzle_ray_stats.last)
    end
end)

log("loaded")
