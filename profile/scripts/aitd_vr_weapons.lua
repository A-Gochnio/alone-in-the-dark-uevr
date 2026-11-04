-- Alone in the Dark (2024) UEVR: every hitscan weapon in the right hand, with two-handed aiming.
--
-- One-handed: the active weapon's root is attached to the right controller (UObjectHook motion
-- controller state). Its rotation offset is derived from the headset-verified revolver offset in
-- alone_in_the_dark_vr.lua: Q_rel = O_revolver * M_revolver is the muzzle frame in controller
-- space, and any weapon gets O = Q_rel * M_weapon^-1, where M is the MuzzleFlash component's
-- rotation relative to the weapon root. So every barrel sits in the hand like the revolver's.
--
-- Two-handed: while aiming, pressing the left grip with the left hand in front of the right near the
-- barrel line takes hold; until it is released the barrel runs from the right hand through the left.
-- Shots follow (aitd_vr_muzzle_ray.lua fires along the barrel).
--
-- Controller world poses come from two empty scene components attached to the controllers.
-- Quaternions are (x, y, z, w), Hamilton product, UE axes (X forward, Y right, Z up).

local api = uevr.api

local TWO_HAND_ENTER = 30.0      -- cm from the one-handed barrel line to take hold (left grip)
                                 -- (a hand on the fore-end sits ~13 cm below that line)
local TWO_HAND_MIN_REACH = 12.0  -- left hand must be at least this far in front of the right
local TWO_HAND_MAX_REACH = 75.0

-- How far the right hand sits toward the muzzle compared with the revolver grip, in cm (Arek).
local GRIP_FORWARD = { Shotgun = 5.0, TommyGun = 10.0 }

local hands = {}                 -- [0] left, [1] right: scene components following controllers
local hands_owner = nil
local attached = {}              -- root address -> motion controller state
local applied = {}               -- root address -> rotation offset set last frame
local q_rel = nil                -- revolver muzzle frame in controller space
local two_handed = false
local last_weapon = nil
local debug_timer = 0

AITD_WEAPONS_ACTIVE = true       -- alone_in_the_dark_vr.lua leaves attaching to this script

local log_lines = {}

-- Keeps the last 60 lines in data/aitd_weapons.txt.
local function log(text)
    print("[aitd_weapons] " .. text)
    log_lines[#log_lines + 1] = text
    if #log_lines > 60 then table.remove(log_lines, 1) end
    if fs ~= nil and fs.write ~= nil then pcall(fs.write, "aitd_weapons.txt", table.concat(log_lines, "\n") .. "\n") end
end

local function pitch_yaw(x, y, z)
    return math.deg(math.atan(z, math.sqrt(x * x + y * y))), math.deg(math.atan(y, x))
end

local function xyz(v) return v.x or v.X, v.y or v.Y, v.z or v.Z end

local function q_mul(a, b)
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
             y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
             w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end

local function q_inv(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end

local function q_rotate(q, vx, vy, vz)
    local p = q_mul(q_mul(q, { x = vx, y = vy, z = vz, w = 0 }), q_inv(q))
    return p.x, p.y, p.z
end

-- Rotation whose columns are the forward, right and up axes.
local function q_from_axes(fx, fy, fz, rx, ry, rz, ux, uy, uz)
    local m00, m11, m22 = fx, ry, uz
    local tr = m00 + m11 + m22
    local q
    if tr > 0 then
        local s = math.sqrt(tr + 1.0) * 2
        q = { w = 0.25 * s, x = (rz - uy) / s, y = (ux - fz) / s, z = (fy - rx) / s }
    elseif m00 > m11 and m00 > m22 then
        local s = math.sqrt(1.0 + m00 - m11 - m22) * 2
        q = { w = (rz - uy) / s, x = 0.25 * s, y = (rx + fy) / s, z = (ux + fz) / s }
    elseif m11 > m22 then
        local s = math.sqrt(1.0 + m11 - m00 - m22) * 2
        q = { w = (ux - fz) / s, x = (rx + fy) / s, y = 0.25 * s, z = (uy + rz) / s }
    else
        local s = math.sqrt(1.0 + m22 - m00 - m11) * 2
        q = { w = (fy - rx) / s, x = (ux + fz) / s, y = (uy + rz) / s, z = 0.25 * s }
    end
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end

local function q_of(component)
    local fx, fy, fz = xyz(component:GetForwardVector())
    local rx, ry, rz = xyz(component:GetRightVector())
    local ux, uy, uz = xyz(component:GetUpVector())
    return q_from_axes(fx, fy, fz, rx, ry, rz, ux, uy, uz)
end

-- Shortest rotation taking unit vector a to unit vector b.
local function q_between(ax, ay, az, bx, by, bz)
    local d = ax * bx + ay * by + az * bz
    local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    local q = { x = cx, y = cy, z = cz, w = 1.0 + d }
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-6 then return { x = 0, y = 0, z = 1, w = 0 } end
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end

-- UEVR's motion controller offsets are not in UE axes (UObjectHook.cpp, UEVR master):
-- * the Lua Vector4f is read as a quaternion in (w, x, y, z) order;
-- * that quaternion is in VR axes (x right, y up, z back), and the component's world rotation is
--   hand * inverse(offset);
-- * the location offset is in the component's own frame, also in VR axes.
-- UE (x fwd, y right, z up) = (-z_vr, x_vr, y_vr). As a quaternion, a VR rotation's vector part
-- maps to UE as (z, -x, -y) (the axis change flips handedness, which negates an axial vector).
local function glm_of(o) return { w = o.x, x = o.y, y = o.z, z = o.w } end
local function raw_of(g) return { x = g.w, y = g.x, z = g.y, w = g.z } end
local function vr_to_ue_q(g) return { x = g.z, y = -g.x, z = -g.y, w = g.w } end
local function ue_to_vr_q(q) return { x = -q.y, y = -q.z, z = q.x, w = q.w } end
local function ue_to_vr(x, y, z) return y, z, -x end

-- World rotation (UE) of a component attached with offset o, given the controller rotation (UE).
local function world_of(cue, o) return q_mul(cue, q_inv(vr_to_ue_q(glm_of(o)))) end

-- Offset that gives world rotation w for controller rotation cue.
local function offset_of(cue, w) return raw_of(ue_to_vr_q(q_mul(q_inv(w), cue))) end

local function alive(obj)
    if obj == nil then return false end
    local ok, exists = pcall(function() return UEVR_UObjectHook.exists(obj) end)
    return ok and exists
end

local function ensure_hands(pawn)
    if hands_owner == pawn:get_address() and alive(hands[0]) and alive(hands[1]) then return true end
    local class = api:find_uobject("Class /Script/Engine.SceneComponent")
    for hand = 0, 1 do
        local comp = api:add_component_by_class(pawn, class)
        if comp == nil then return false end
        local state = UEVR_UObjectHook.get_or_add_motion_controller_state(comp)
        state:set_hand(hand)
        state:set_permanent(true)
        state:set_location_offset(Vector3f.new(0, 0, 0))
        state:set_rotation_offset(Vector4f.new(1, 0, 0, 0)) -- identity in UEVR's (w, x, y, z)
        hands[hand] = comp
    end
    hands_owner = pawn:get_address()
    log("hand trackers created")
    return true
end

-- Muzzle rotation and position relative to the weapon root, captured the first time each weapon
-- is seen: the game spins the MuzzleFlash effect randomly on every shot, so reading it live made
-- the gun (and the shot) swing to a random direction after firing.
local muzzle_cache = {}

local function muzzle_relative(weapon)
    local key = weapon:get_address()
    local c = muzzle_cache[key]
    if c ~= nil then return c.q, c end
    local flash = weapon.MuzzleFlash
    local root = weapon.RootComponent
    if flash == nil or root == nil then return nil end
    local qr = q_of(root)
    local rx, ry, rz = xyz(root:K2_GetComponentLocation())
    local mx, my, mz = xyz(flash:K2_GetComponentLocation())
    local px, py, pz = q_rotate(q_inv(qr), mx - rx, my - ry, mz - rz)
    c = { q = q_mul(q_inv(qr), q_of(flash)), x = px, y = py, z = pz }
    muzzle_cache[key] = c
    return c.q, c
end

-- Muzzle position and barrel direction from the weapon root and the cached muzzle offset. Used by
-- aitd_vr_muzzle_ray.lua (shot ray) and aitd_vr_reticle.lua (dot) through aitd_muzzle_ray.
function aitd_weapon_muzzle(weapon)
    local root = weapon.RootComponent
    if root == nil then return nil end
    local _, c = muzzle_relative(weapon)
    if c == nil then return nil end
    local qr = q_of(root)
    local rx, ry, rz = xyz(root:K2_GetComponentLocation())
    local ox, oy, oz = q_rotate(qr, c.x, c.y, c.z)
    local fx, fy, fz = q_rotate(q_mul(qr, c.q), 1, 0, 0)
    return rx + ox, ry + oy, rz + oz, fx, fy, fz
end
-- The revolver's muzzle rotation relative to its root (M_revolver). Emily starts without a
-- revolver, so the class may never be loaded; this value (measured on Edward's holstered
-- revolver through the bridge, 2026-10-26) stands in for it.
local REVOLVER_MUZZLE = { x = 0.099250, y = -0.099149, z = 0.699656, w = 0.700570 }

local function revolver_q_rel()
    if q_rel ~= nil then return q_rel end
    if AITD_REVOLVER_ROTATION == nil then return nil end
    local m = nil
    local class = api:find_uobject("Class /Script/ObsidianFox.HitscanWeaponActor")
    for _, w in ipairs(UEVR_UObjectHook.get_objects_by_class(class, false) or {}) do
        if w:get_full_name():find("Revolver_C", 1, true) then
            m = muzzle_relative(w)
            if m ~= nil then
                log(string.format("revolver muzzle x=%.6f y=%.6f z=%.6f w=%.6f", m.x, m.y, m.z, m.w))
                break
            end
        end
    end
    m = m or REVOLVER_MUZZLE
    if m == nil then return nil end
    local o = AITD_REVOLVER_ROTATION()
    q_rel = q_mul({ x = o.x, y = o.y, z = o.z, w = o.w }, m)
    log("revolver reference captured")
    return q_rel
end

local function weapon_name(weapon)
    return weapon:get_full_name():match("BP_HitscanWeapon_Base_([%w_]+)_C") or "weapon"
end

-- Live grip tuning: data/aitd_grip_tune.txt with lines like "Shotgun=5", re-read every 2 s.
local grip_applied = {}          -- root address -> grip shift applied
local grip_timer = 0.0
local grip_text = nil

local function read_grip_tune(delta)
    grip_timer = grip_timer + delta
    if grip_timer < 2.0 or fs == nil or fs.read == nil then return end
    grip_timer = 0.0
    local ok, text = pcall(fs.read, "aitd_grip_tune.txt")
    if not ok or text == nil or text == grip_text then return end
    grip_text = text
    for k, v in text:gmatch("(%a+)%s*=%s*([%-%d%.]+)") do GRIP_FORWARD[k] = tonumber(v) end
end

-- Everything above is keyed by object address. A save reload or level change destroys the pawn
-- and its weapons, and new objects can reuse the old addresses, so a new gun could inherit a dead
-- gun's motion controller state, muzzle frame or grip shift. Forget it all when the pawn changes
-- or a load screen starts.
local state_owner = nil

local function forget_objects()
    attached = {}
    applied = {}
    grip_applied = {}
    muzzle_cache = {}
    hands = {}
    hands_owner = nil
    two_handed = false
    last_weapon = nil
    AITD_TWO_HANDED = false
end

-- Set by aitd_vr_ui.lua: false while loading and briefly after a new pawn appears.
local function loading()
    return AITD_WORLD_SETTLED == false
end

local function update(delta)
    pcall(read_grip_tune, delta)
    local pawn = api:get_local_pawn(0)
    if pawn == nil or loading() then
        if state_owner ~= nil then forget_objects() state_owner = nil end
        return
    end
    if state_owner ~= pawn:get_address() then
        if state_owner ~= nil then log("new pawn, cleared weapon state") end
        forget_objects()
        state_owner = pawn:get_address()
    end
    local ok, weapon = pcall(function() return pawn:GetActiveWeapon() end)
    if not ok or weapon == nil or not weapon:get_full_name():find("HitscanWeapon", 1, true) then return end
    local root = weapon.RootComponent
    if root == nil or not ensure_hands(pawn) then return end
    local qr = revolver_q_rel()
    if qr == nil then return end
    local m = muzzle_relative(weapon)
    if m == nil then return end
    local o_one = q_mul(qr, q_inv(m))

    local key = root:get_address()
    local entry = attached[key]
    if entry ~= nil and not alive(entry.root) then
        attached[key] = nil
        grip_applied[key] = nil
        entry = nil
    end
    if entry == nil then
        local s = UEVR_UObjectHook.get_or_add_motion_controller_state(root)
        if s == nil then return end
        s:set_hand(1)
        s:set_permanent(true)
        entry = { root = root, state = s }
        attached[key] = entry
        log("attached " .. weapon_name(weapon))
    end
    local state = entry.state
    local name = weapon_name(weapon)
    local g = GRIP_FORWARD[name] or 0.0
    if grip_applied[key] ~= g and AITD_REVOLVER_LOCATION ~= nil then
        -- Shift the gun back along its barrel so the hand grips further forward. The location
        -- offset lives in the weapon's own frame in VR axes; m * X is the barrel in its UE frame.
        -- Measured: adding the barrel direction moves the gun back (the offset is subtracted).
        local l = AITD_REVOLVER_LOCATION()
        local vx, vy, vz = ue_to_vr(q_rotate(m, 1, 0, 0))
        state:set_location_offset(Vector3f.new(l.x + vx * g, l.y + vy * g, l.z + vz * g))
        grip_applied[key] = g
        log(string.format("%s grip %.1f cm forward", name, g))
    end
    if last_weapon ~= key then two_handed = false last_weapon = key end

    -- Right controller rotation in UE axes: the right tracker has an identity offset.
    local cue = q_of(hands[1])
    local w_one = world_of(cue, o_one)
    local fx, fy, fz = q_rotate(q_mul(w_one, m), 1, 0, 0) -- one-handed barrel direction

    debug_timer = debug_timer + delta
    local log_now = debug_timer > 0.25
    if log_now then debug_timer = 0 end

    local o = o_one
    local aiming = false
    pcall(function() aiming = pawn:IsAiming() end)
    if aiming then
        local rx, ry, rz = xyz(hands[1]:K2_GetComponentLocation())
        local lx, ly, lz = xyz(hands[0]:K2_GetComponentLocation())
        local dx, dy, dz = lx - rx, ly - ry, lz - rz
        local along = dx * fx + dy * fy + dz * fz
        local px, py, pz = dx - along * fx, dy - along * fy, dz - along * fz
        local off = math.sqrt(px * px + py * py + pz * pz)
        -- Take hold with the left grip near the barrel; keep hold while the grip stays pressed.
        local was_two_handed = two_handed
        local grip = AITD_LEFT_GRIP == true
        local reach = math.sqrt(dx * dx + dy * dy + dz * dz)
        if not grip then
            two_handed = false
        elseif two_handed then
            two_handed = reach > TWO_HAND_MIN_REACH * 0.5 and reach < TWO_HAND_MAX_REACH * 1.3
        else
            two_handed = along > TWO_HAND_MIN_REACH and along < TWO_HAND_MAX_REACH and off < TWO_HAND_ENTER
        end
        AITD_TWO_HANDED = two_handed
        if two_handed and not was_two_handed then
            -- A short buzz in the left hand when it takes hold of the barrel.
            pcall(function()
                local vr = uevr.params.vr
                vr.trigger_haptic_vibration(0.0, 0.06, 1.0, 0.6, vr.get_left_joystick_source())
            end)
        end
        if two_handed then
            -- World rotation d turns the one-handed barrel onto the line from the right hand to the
            -- left: W = d * W_one, converted back into UEVR's offset.
            local len = math.sqrt(dx * dx + dy * dy + dz * dz)
            local d = q_between(fx, fy, fz, dx / len, dy / len, dz / len)
            o = offset_of(cue, q_mul(d, w_one))
        end
        if log_now and two_handed then
            local _, _, _, bx, by, bz = aitd_weapon_muzzle(weapon)
            local hp, hy = pitch_yaw(dx, dy, dz)
            local bp, byaw = pitch_yaw(bx, by, bz)
            local fp, fyaw = pitch_yaw(fx, fy, fz)
            log(string.format("along %.0f off %.0f two=%s hands p%.1f y%.1f barrel p%.1f y%.1f one-handed p%.1f y%.1f",
                along, off, tostring(two_handed), hp, hy, bp, byaw, fp, fyaw))
        end
    else
        two_handed = false
        AITD_TWO_HANDED = false
    end
    state:set_rotation_offset(Vector4f.new(o.x, o.y, o.z, o.w))
    applied[key] = o
end

-- FQuat -> FRotator (UE's own formula), degrees.
local function rotator_of(q)
    local s = q.z * q.x - q.w * q.y
    local pitch = math.deg(math.asin(math.max(-1, math.min(1, 2 * s))))
    local yaw = math.deg(math.atan(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)))
    local roll = math.deg(math.atan(-2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)))
    return pitch, yaw, roll
end

-- During automatic fire the game keeps re-aiming the MuzzleFlash effect toward a lagging world
-- direction (relative pitch drifted 10 -> 25 deg over a sweeping burst), so the flash smeared
-- back toward where the burst started. After the game's tick, put it back on the barrel.
local hit_struct = nil
local function pin_muzzle_flash()
    if loading() then return end
    local pawn = api:get_local_pawn(0)
    if pawn == nil then return end
    local weapon = pawn:GetActiveWeapon()
    if weapon == nil then return end
    local c = muzzle_cache[weapon:get_address()]
    local flash = weapon.MuzzleFlash
    local root = weapon.RootComponent
    if c == nil or flash == nil or root == nil or not flash.bIsActive then return end
    hit_struct = hit_struct or api:find_uobject("ScriptStruct /Script/Engine.HitResult")
    local p, y, r = rotator_of(q_mul(q_of(root), c.q))
    flash:K2_SetWorldRotation(Vector3f.new(p, y, r), false, StructObject.new(hit_struct), false)
end

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
    local ok, err = pcall(pin_muzzle_flash)
    if not ok then log("flash error: " .. tostring(err)) end
end)

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    local ok, err = pcall(update, delta)
    if not ok then log("error: " .. tostring(err)) end
end)

log("loaded")
