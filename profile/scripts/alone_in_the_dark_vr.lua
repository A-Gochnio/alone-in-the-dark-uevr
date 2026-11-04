-- Alone in the Dark (2024) UEVR motion controls.
--
-- UEVR exposes Quest controls to the game as XInput. The stock game binds aim
-- to LT, fire to RT, and melee to RB. Swap LT and RB so the physical right grip
-- aims, the physical right trigger still fires, and the physical left trigger
-- retains the displaced melee action.

local XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200
local TRIGGER_THRESHOLD = 30
local XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100
local XINPUT_DPAD_UP, XINPUT_DPAD_DOWN, XINPUT_DPAD_LEFT, XINPUT_DPAD_RIGHT = 0x0001, 0x0002, 0x0004, 0x0008
local DPAD_STICK_THRESHOLD = 20000

-- Verified in-headset on Quest 3: this makes the revolver barrel point along
-- the right controller. Quaternion component order is x, y, z, w.
local REVOLVER_LOCATION = Vector3f.new(-3.98251152, 2.8273344, 5.70884609)
local REVOLVER_ROTATION = Vector4f.new(
    0.5958555383855734,
    0.4436286447764134,
    -0.5349530050684181,
    -0.4024612469031347
)

-- Fine correction on top of REVOLVER_ROTATION, in degrees about the controller's right (pitch)
-- and up (yaw) axes, so the visible barrel lines up with the gameplay shot ray (which follows the
-- controller aim pose). Tunable live by writing "pitch=<deg>" and "yaw=<deg>" lines to
-- data/aitd_aim_tune.txt in the UEVR profile.
local REVOLVER_PITCH_TRIM = -9.59 -- tools/Invoke-AitDBarrelCalibration.ps1 against the muzzle-flash axis, 0.17 deg residual
local REVOLVER_YAW_TRIM = 6.76 -- Arek: straight at 3 m after a +2 nudge
-- Position correction (cm, attachment frame) so the muzzle sits on the shot ray, which starts
-- off the barrel: with only the angle matched, the dot drifted sideways as the target got closer.
-- Live keys: "lx", "ly", "lz".
local REVOLVER_LOCATION_TRIM = { x = 0.0, y = 0.0, z = 0.0 }

local attached_revolver_root = nil
local attached_revolver_state = nil
local attached_revolver_object = nil

local function exists(obj)
    if obj == nil then return false end
    if UEVR_UObjectHook == nil or UEVR_UObjectHook.exists == nil then return true end
    local ok, alive = pcall(function() return UEVR_UObjectHook.exists(obj) end)
    return ok and alive
end
local last_tune_text = nil

local function quat_mul(a, b)
    return Vector4f.new(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    )
end

local function trimmed_revolver_rotation()
    local p = math.rad(REVOLVER_PITCH_TRIM) / 2
    local y = math.rad(REVOLVER_YAW_TRIM) / 2
    local pitch = Vector4f.new(0, math.sin(p), 0, math.cos(p))
    local yaw = Vector4f.new(0, 0, math.sin(y), math.cos(y))
    return quat_mul(quat_mul(yaw, pitch), REVOLVER_ROTATION)
end

local function trimmed_revolver_location()
    return Vector3f.new(REVOLVER_LOCATION.x + REVOLVER_LOCATION_TRIM.x,
        REVOLVER_LOCATION.y + REVOLVER_LOCATION_TRIM.y, REVOLVER_LOCATION.z + REVOLVER_LOCATION_TRIM.z)
end

-- Shared with aitd_vr_weapons.lua, which derives every weapon's hand offset from the revolver's.
AITD_REVOLVER_ROTATION = trimmed_revolver_rotation
AITD_REVOLVER_LOCATION = trimmed_revolver_location

local function read_aim_tune()
    if fs == nil or fs.read == nil then return end
    local text = fs.read("aitd_aim_tune.txt")
    if text == nil or text == last_tune_text then return end
    last_tune_text = text
    REVOLVER_PITCH_TRIM = tonumber(text:match("pitch%s*=%s*([%-%d%.]+)")) or REVOLVER_PITCH_TRIM
    REVOLVER_YAW_TRIM = tonumber(text:match("yaw%s*=%s*([%-%d%.]+)")) or REVOLVER_YAW_TRIM
    for _, k in ipairs({ "x", "y", "z" }) do
        REVOLVER_LOCATION_TRIM[k] = tonumber(text:match("l" .. k .. "%s*=%s*([%-%d%.]+)")) or REVOLVER_LOCATION_TRIM[k]
    end
    if attached_revolver_state ~= nil and exists(attached_revolver_object) then
        pcall(function() attached_revolver_state:set_rotation_offset(trimmed_revolver_rotation()) end)
        pcall(function() attached_revolver_state:set_location_offset(trimmed_revolver_location()) end)
    end
    print(string.format("[AitD VR] Revolver trim pitch %.2f yaw %.2f", REVOLVER_PITCH_TRIM, REVOLVER_YAW_TRIM))
end
local attachment_timer = 0.0

local function attach_active_revolver()
    local pawn = uevr.api:get_local_pawn(0)
    if pawn == nil then
        return
    end

    local ok, weapon = pcall(function()
        return pawn:GetActiveWeapon()
    end)
    if not ok or weapon == nil then
        return
    end

    if not weapon:get_full_name():find("BP_HitscanWeapon_Base_Revolver_C", 1, true) then
        return
    end

    local root = weapon.RootComponent
    if root == nil then
        return
    end

    local root_address = root:get_address()
    if attached_revolver_root == root_address and exists(attached_revolver_object) then
        return
    end

    local state = UEVR_UObjectHook.get_or_add_motion_controller_state(root)
    if state == nil then
        return
    end

    state:set_hand(1)
    state:set_permanent(true)
    state:set_location_offset(trimmed_revolver_location())
    state:set_rotation_offset(trimmed_revolver_rotation())
    attached_revolver_root = root_address
    attached_revolver_state = state
    attached_revolver_object = root

    print(string.format("[AitD VR] Revolver attached to right controller: 0x%X", root_address))
end

-- First-person height. uobjecthook/camera_state.json puts the camera base 72 cm above the
-- capsule centre (168 cm above the floor). UEVR adds the head's offset from its standing origin,
-- which it captures from the first headset pose, usually while the headset still lies on the
-- desk. Re-capture it once the headset is worn (controllers in use) and whenever a new pawn
-- spawns (save load, chapter change), so the camera starts at the character's eye height.
local origin_set_for_pawn = nil

local base_origin_y = nil    -- tracking metres
local crouch_offset = 0.0    -- metres the origin is raised while crouched

-- Only the height is written: roomscale movement shifts the origin horizontally as the player
-- walks, and restoring a stored x/z made crouching jerk the character sideways.
local function apply_standing_origin()
    if base_origin_y == nil then return end
    local o = UEVR_Vector3f.new()
    uevr.params.vr.get_standing_origin(o)
    o.y = base_origin_y + crouch_offset
    uevr.params.vr.set_standing_origin(o)
end

local function reset_standing_origin()
    local vr = uevr.params.vr
    local pos = UEVR_Vector3f.new()
    local rot = UEVR_Quaternionf.new()
    vr.get_pose(vr.get_hmd_index(), pos, rot)
    vr.set_standing_origin(pos)
    base_origin_y = pos.y
    apply_standing_origin()
    print(string.format("[AitD VR] Standing origin set to the headset pose (%.2f, %.2f, %.2f)", pos.x, pos.y, pos.z))
end

local origin_set_after_controllers = false

-- Re-capture 1.5 s after each load finishes (main state back to gameplay, new pawn), when the
-- headset pose is valid and the player is settled; and once on the first controller use in a
-- session, for a save loaded while the headset still lay on the desk. Capturing at the moment
-- the pawn spawned still started the view too high.
local ORIGIN_SETTLE_SECONDS = 1.5
local origin_pending_at = nil
local origin_clock = 0.0

local function update_standing_origin(delta)
    origin_clock = origin_clock + delta
    local pawn = uevr.api:get_local_pawn(0)
    if pawn == nil or AITD_MAIN_STATE == 6 or AITD_MAIN_STATE == 7 then
        origin_set_for_pawn = nil
        return
    end

    local address = pawn:get_address()
    if origin_set_for_pawn ~= address then
        origin_set_for_pawn = address
        origin_pending_at = origin_clock + ORIGIN_SETTLE_SECONDS
    end
    if origin_pending_at ~= nil and origin_clock >= origin_pending_at then
        origin_pending_at = nil
        pcall(reset_standing_origin)
    elseif not origin_set_after_controllers and uevr.params.vr.is_using_controllers() then
        origin_set_after_controllers = true
        pcall(reset_standing_origin)
    end
end

-- Stealth crouch. The game's stealth ability (GA_Player_Stealth, bIsActive) only lowers the
-- body animation and the flat-screen camera modifier, not the VR camera, which is attached to
-- the capsule. While it is active, raise UEVR's standing origin, which lowers the view and the
-- tracked hands together (VR_CameraUpOffset moved only the view, leaving the revolver up).
local CROUCH_CAMERA_DROP = 0.35    -- metres; at 0.5 the view sank below the body-mounted items
local CROUCH_EASE_SECONDS = 0.3
local stealth_ability = nil
local stealth_owner = nil
local stealth_retry = 0.0

local function find_stealth_ability(pawn)
    local class = uevr.api:find_uobject(
        "BlueprintGeneratedClass /Game/ObsidianFox/Abilities/Player/GA_Player_Stealth.GA_Player_Stealth_C")
    if class == nil then return nil end
    local pawn_name = pawn:get_fname():to_string()
    for _, ability in ipairs(class:get_objects_matching(false)) do
        local ok, outer = pcall(function() return ability:get_outer() end)
        if ok and outer ~= nil and outer:get_fname():to_string() == pawn_name then
            return ability
        end
    end
    return nil
end

local function update_crouch_camera(delta)
    local pawn = uevr.api:get_local_pawn(0)
    if pawn == nil then return end
    local address = pawn:get_address()
    stealth_retry = stealth_retry - delta
    if stealth_owner ~= address or (stealth_ability == nil and stealth_retry <= 0) then
        stealth_owner = address
        stealth_retry = 2.0
        stealth_ability = find_stealth_ability(pawn)
    end

    local crouched = false
    if stealth_ability ~= nil and exists(stealth_ability) then
        local ok, active = pcall(function() return stealth_ability.bIsActive end)
        crouched = ok and active == true
    end

    local target = crouched and CROUCH_CAMERA_DROP or 0.0
    if crouch_offset == target then return end
    local step = CROUCH_CAMERA_DROP * delta / CROUCH_EASE_SECONDS
    if math.abs(target - crouch_offset) <= step then
        crouch_offset = target
    else
        crouch_offset = crouch_offset + (target > crouch_offset and step or -step)
    end
    apply_standing_origin()
end

-- Button layer (Arek's layout):
--   Y tap  -> View/Back: investigation menu (inventory, map, documents); also closes it
--   Y hold -> Menu/Start: pause menu
--   X tap  -> X: reload (sent on release so a hold can mean something else)
--   X hold -> Y: stealth/crouch, which lost its button to the inventory
-- Weapon slots stay on the DPad, which UEVR's virtual DPad provides (VR_DPadShiftingMethod).
-- Applies in gameplay, the investigation menu and the pause menu (main states 0, 3, 4, read
-- from aitd_vr_ui.lua). Puzzles, cutscenes and every other state get the controllers unchanged.
local XINPUT_START = 0x0010
local XINPUT_BACK = 0x0020
local XINPUT_X = 0x4000
local XINPUT_Y = 0x8000
local HOLD_SECONDS = 0.5
local PULSE_SECONDS = 0.12
local REMAP_STATES = { [0] = true, [3] = true, [4] = true }

local now = 0.0
local pulses = {}          -- button mask -> time the injected press ends
local hold_start = {}      -- physical button -> press time, or nil
local hold_fired = {}      -- physical button -> long-press action already sent

local function pulse(mask)
    pulses[mask] = now + PULSE_SECONDS
end

-- Tap/hold handling for one physical button. Returns nothing; queues pulses.
local function tap_or_hold(pressed, key, tap_mask, hold_mask)
    if pressed then
        if hold_start[key] == nil then
            hold_start[key] = now
            hold_fired[key] = false
        elseif not hold_fired[key] and now - hold_start[key] >= HOLD_SECONDS then
            hold_fired[key] = true
            pulse(hold_mask)
        end
    elseif hold_start[key] ~= nil then
        if not hold_fired[key] then pulse(tap_mask) end
        hold_start[key] = nil
    end
end

-- Puzzle detection. EGameMainState (names in the shipping exe, in this order): 0 ThirdPerson,
-- 1 Cinematic, 2 Sequence, 3 InGameMenu, 4 PauseMenu, 5 Puzzle, 6 LoadingScreen, 7 MainMenu,
-- 8 PhotoMode. Puzzles also switch the view to a fixed close-up camera, so a view target other
-- than the pawn counts as a puzzle too. Computed here, never in the xinput callback.
AITD_PUZZLE_VIEW = false
local VIEW_CHECK_SECONDS = 0.1
local VIEW_LOG_LINES = 100
local view_check_timer = 0.0
local view_log_class = nil
local view_log_puzzle = nil
local view_log = {}

local function log_view(target)
    local class_address = 0
    if target ~= nil then
        pcall(function() class_address = target:get_class():get_address() end)
    end
    if class_address == view_log_class and AITD_PUZZLE_VIEW == view_log_puzzle then return end
    local full_name = "nil"
    if target ~= nil then pcall(function() full_name = target:get_full_name() end) end
    view_log_class = class_address
    view_log_puzzle = AITD_PUZZLE_VIEW
    view_log[#view_log + 1] = string.format("%.1f state=%s puzzle=%s target=%s", now,
        tostring(AITD_MAIN_STATE), tostring(AITD_PUZZLE_VIEW), full_name)
    while #view_log > VIEW_LOG_LINES do table.remove(view_log, 1) end
    if fs ~= nil and fs.write ~= nil then
        pcall(fs.write, "aitd_view_log.txt", table.concat(view_log, "\n") .. "\n")
    end
end

-- Views shown on UEVR's flat 2D screen instead of in stereo. The telescope's camera renders its
-- sight mask, blur and colour split as screen-space post-process materials, which flicker
-- between the eyes in Native Stereo.
local FLAT_SCREEN_TARGETS = { "BP_Telescope_C" }
local flat_target_address = nil
local flat_target_match = false
local flat_screen_on = false

local function set_flat_screen(on)
    if on == flat_screen_on then return end
    flat_screen_on = on
    uevr.params.vr.set_mod_value("VR_2DScreenMode", on and "true" or "false")
    print("[AitD VR] 2D screen mode " .. (on and "on" or "off"))
end

local function update_flat_screen(target)
    local address = target ~= nil and target:get_address() or nil
    if address ~= flat_target_address then
        flat_target_address = address
        flat_target_match = false
        if target ~= nil then
            local ok, class_name = pcall(function() return target:get_class():get_full_name() end)
            if ok and class_name ~= nil then
                for _, name in ipairs(FLAT_SCREEN_TARGETS) do
                    if class_name:find(name, 1, true) then flat_target_match = true end
                end
            end
        end
    end
    set_flat_screen(flat_target_match)
end

local function update_puzzle_view()
    local pawn = uevr.api:get_local_pawn(0)
    local pc = uevr.api:get_player_controller(0)
    local target = nil
    if pc ~= nil then
        local ok, result = pcall(function() return pc:GetViewTarget() end)
        if ok then target = result end
    end
    AITD_PUZZLE_VIEW = target ~= nil and pawn ~= nil and target:get_address() ~= pawn:get_address()
    log_view(target)
    update_flat_screen(target)
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    now = now + delta
    -- aitd_vr_ui.lua: false while loading and briefly after a new pawn appears. Leave the old
    -- world's objects alone then.
    if AITD_WORLD_SETTLED == false then
        stealth_ability = nil
        stealth_owner = nil
        AITD_PUZZLE_VIEW = false
        return
    end
    pcall(update_crouch_camera, delta)
    view_check_timer = view_check_timer + delta
    if view_check_timer >= VIEW_CHECK_SECONDS then
        view_check_timer = 0.0
        if not pcall(update_puzzle_view) then AITD_PUZZLE_VIEW = false end
    end
end)

local function apply_button_layer(gamepad)
    local state = AITD_MAIN_STATE
    if state ~= nil and not REMAP_STATES[state] then
        hold_start = {}
        return
    end

    local buttons = gamepad.wButtons
    tap_or_hold((buttons & XINPUT_Y) ~= 0, "Y", XINPUT_BACK, XINPUT_START)
    -- In the pause menu the X hold sends nothing: Y there is the Load Game screen's Delete Save.
    tap_or_hold((buttons & XINPUT_X) ~= 0, "X", XINPUT_X, state == 4 and 0 or XINPUT_Y)
    buttons = buttons & ~(XINPUT_X | XINPUT_Y)

    for mask, until_time in pairs(pulses) do
        if now < until_time then
            buttons = buttons | mask
        else
            pulses[mask] = nil
        end
    end
    if state == 4 then buttons = buttons & ~XINPUT_Y end
    gamepad.wButtons = buttons
end

-- Menu left grip: nil when released, else { flicked = bool, armed = bool }.
local menu_grip = nil

local function stick_dpad_bit(x, y)
    if math.abs(x) <= DPAD_STICK_THRESHOLD and math.abs(y) <= DPAD_STICK_THRESHOLD then return nil end
    if math.abs(x) > math.abs(y) then
        return x > 0 and XINPUT_DPAD_RIGHT or XINPUT_DPAD_LEFT
    end
    return y > 0 and XINPUT_DPAD_UP or XINPUT_DPAD_DOWN
end

local function apply_menu_grip(gp)
    local held = (gp.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) ~= 0
    gp.wButtons = gp.wButtons & ~XINPUT_GAMEPAD_LEFT_SHOULDER
    if held then
        if menu_grip == nil then menu_grip = { flicked = false, armed = true } end
        local bit = stick_dpad_bit(gp.sThumbRX, gp.sThumbRY)
        if bit == nil then
            menu_grip.armed = true
        elseif menu_grip.armed then
            menu_grip.armed = false
            menu_grip.flicked = true
            pulse(bit)
        end
        gp.sThumbRX, gp.sThumbRY = 0, 0
    elseif menu_grip ~= nil then
        if not menu_grip.flicked then pulse(XINPUT_GAMEPAD_LEFT_SHOULDER) end
        menu_grip = nil
    end
end

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
    attachment_timer = attachment_timer + delta
    if attachment_timer < 0.25 then
        return
    end

    attachment_timer = 0.0
    read_aim_tune()
    -- aitd_vr_weapons.lua attaches every weapon (using the revolver offset below) when loaded.
    if not AITD_WEAPONS_ACTIVE and AITD_WORLD_SETTLED ~= false then attach_active_revolver() end
    update_standing_origin(0.25)
end)

uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    if state == nil or state.Gamepad == nil then
        return
    end

    -- Puzzles, cutscenes and every other state: the game gets the controllers unchanged. Puzzles
    -- rotate and dial with LB/RB (grips), move with the sticks and use the telescope's right stick.
    local main_state = AITD_MAIN_STATE

    -- Main menu (state 7) passes through unchanged except Y, which is Delete Save on the Load Game
    -- screen. No save is ever deleted by an accidental Quest Y press.
    if main_state == 7 then
        state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_Y
    end

    -- In the investigation and pause menus the grips must stay LB/RB (tab switching), so the
    -- aim/melee swap only applies outside them. The left grip is a tap there (LB on release), and
    -- held with a right-stick flick it sends the D-pad (the map's Change Floor).
    if main_state == 3 or main_state == 4 then
        apply_menu_grip(state.Gamepad)
        apply_button_layer(state.Gamepad)
        return
    end
    menu_grip = nil

    if AITD_PUZZLE_VIEW or (main_state ~= nil and main_state ~= 0) then
        hold_start = {}
        pulses = {}
        AITD_LEFT_GRIP = false
        return
    end

    -- Weapon D-pad: hold the left grip (LB) and flick the right stick (right revolver, down
    -- shotgun, left tommy gun, up health item). Replaces UEVR's head-gesture D-pad shifting,
    -- which did nothing in the headset. The stick stops turning while the grip is held. Not while
    -- aiming (right grip): a two-handed hold must keep turning and never switch weapons.
    local gp = state.Gamepad
    -- The left grip also takes hold of a long gun's barrel while aiming (aitd_vr_weapons.lua);
    -- the game must not see it as LB then.
    AITD_LEFT_GRIP = (gp.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) ~= 0
    if AITD_LEFT_GRIP and (gp.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) ~= 0 then
        gp.wButtons = gp.wButtons & ~XINPUT_GAMEPAD_LEFT_SHOULDER
    end
    if (gp.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) ~= 0 and (gp.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) == 0 then
        local x, y = gp.sThumbRX, gp.sThumbRY
        if math.abs(x) > DPAD_STICK_THRESHOLD or math.abs(y) > DPAD_STICK_THRESHOLD then
            local bit
            if math.abs(x) > math.abs(y) then
                bit = x > 0 and XINPUT_DPAD_RIGHT or XINPUT_DPAD_LEFT
            else
                bit = y > 0 and XINPUT_DPAD_UP or XINPUT_DPAD_DOWN
            end
            gp.wButtons = (gp.wButtons | bit) & ~XINPUT_GAMEPAD_LEFT_SHOULDER
        end
        gp.sThumbRX, gp.sThumbRY = 0, 0
    end

    local buttons = state.Gamepad.wButtons
    local right_grip_pressed = (buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) ~= 0
    local left_trigger_pressed = state.Gamepad.bLeftTrigger > TRIGGER_THRESHOLD

    -- Right grip becomes the game's LT aim input.
    state.Gamepad.bLeftTrigger = right_grip_pressed and 255 or 0

    -- Physical LT becomes the game's RB melee input.
    if left_trigger_pressed then
        state.Gamepad.wButtons = buttons | XINPUT_GAMEPAD_RIGHT_SHOULDER
    else
        state.Gamepad.wButtons = buttons & ~XINPUT_GAMEPAD_RIGHT_SHOULDER
    end

    apply_button_layer(state.Gamepad)
end)

print("[AitD VR] Motion controls loaded: right grip=aim, right trigger=fire, left trigger=melee, "
    .. "Y=inventory (hold: pause), X=reload (hold: stealth)")
