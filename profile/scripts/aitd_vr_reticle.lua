-- Alone in the Dark (2024) VR aiming reticle.
--
-- The game's 2D crosshair sits at the centre of the head-locked UI panel (aitd_vr_ui.lua hides
-- it). Instead, while aiming, this places a small unlit dot in the world where the gun's own
-- gameplay trace hits: the weapon's GetTraceStart/GetTraceEnd ray, traced against the level.
-- It therefore shows where the shot actually lands, whatever the visual gun model does.

-- Size, glow and brightness are live-tunable through data/aitd_reticle_tune.txt
-- (size=, min=, glow=, radius=, bright=), re-read every 2 s.
local DOT_ANGULAR_SIZE = 0.003   -- dot diameter relative to its distance from the camera
local DOT_MIN_SCALE = 0.007      -- engine sphere is 100 cm across: 0.01 = 1 cm
local SURFACE_OFFSET = 2.0       -- cm in front of the hit surface, so the dot is not buried
local GLOW_INTENSITY = 10.0      -- point light around the dot (laser spill on the surface)
local GLOW_RADIUS = 10.0         -- cm
local DOT_BRIGHTNESS = 12.0      -- red channel of the unlit dot; above 1 it blooms

local api = uevr.api
local kismet_system = nil
local hit_result_struct = nil
local color_struct = nil
local sphere_mesh = nil
local gizmo_material = nil
local dot = nil
local dot_owner = nil
local glow = nil                 -- small red point light that makes the surface glow around the dot
local material_instance = nil
local failed = false
local debug_frames = 0

-- Vectors come back either as Vector3f userdata (x, y, z) or as struct objects (X, Y, Z).
local function xyz(v)
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if ok and x ~= nil then return x, y, z end
    return v.X, v.Y, v.Z
end

local function log(text)
    print("[AitD VR reticle] " .. text)
    -- print() does not reach UEVR's log.txt; keep the latest message where tools can read it.
    if fs ~= nil and fs.write ~= nil then pcall(fs.write, "aitd_reticle.txt", text .. "\n") end
end

local function static(name)
    local c = api:find_uobject(name)
    if c == nil then return nil end
    return c:get_class_default_object()
end

local function alive(obj)
    if obj == nil then return false end
    if UEVR_UObjectHook == nil or UEVR_UObjectHook.exists == nil then return true end
    local ok, exists = pcall(function() return UEVR_UObjectHook.exists(obj) end)
    return ok and exists
end

-- The sphere and gizmo material are not guaranteed to stay loaded once the dot that referenced
-- them is destroyed with its pawn, so they are re-found whenever they no longer exist.
local function init_statics()
    if kismet_system ~= nil and alive(sphere_mesh) and (gizmo_material == nil or alive(gizmo_material)) then
        return true
    end
    kismet_system = static("Class /Script/Engine.KismetSystemLibrary")
    hit_result_struct = api:find_uobject("ScriptStruct /Script/Engine.HitResult")
    color_struct = api:find_uobject("ScriptStruct /Script/CoreUObject.LinearColor")
    sphere_mesh = api:find_uobject("StaticMesh /Engine/BasicShapes/Sphere.Sphere")
    gizmo_material = api:find_uobject("Material /Engine/EngineMaterials/GizmoMaterial.GizmoMaterial")
    return kismet_system ~= nil and hit_result_struct ~= nil and color_struct ~= nil and sphere_mesh ~= nil
end

-- The dot and glow are components of the pawn and die with it on a save reload or level change.
-- Drop every reference to them (and the dot's material) then, instead of calling into them.
local function forget_dot(hide)
    if dot == nil and glow == nil then return end
    -- Only outside loading: hide them if they still exist (a pawn change without a reload keeps
    -- the old pawn alive).
    if hide and alive(dot) then pcall(function() dot:SetVisibility(false, false) end) end
    if hide and alive(glow) then pcall(function() glow:SetVisibility(false, false) end) end
    dot = nil
    dot_owner = nil
    glow = nil
    material_instance = nil
end

local function create_dot(pawn)
    material_instance = nil
    local mesh_class = api:find_uobject("Class /Script/Engine.StaticMeshComponent")
    local comp = api:add_component_by_class(pawn, mesh_class)
    if comp == nil then return nil end
    comp:SetStaticMesh(sphere_mesh)
    comp:SetCollisionEnabled(0)
    comp:SetCastShadow(false)
    comp:SetGenerateOverlapEvents(false)
    if gizmo_material ~= nil then
        material_instance = comp:CreateDynamicMaterialInstance(0, gizmo_material, "AitDReticle")
        if material_instance ~= nil then
            local c = StructObject.new(color_struct)
            -- Over-bright (HDR) red so it reads as a laser and blooms.
            c.R, c.G, c.B, c.A = DOT_BRIGHTNESS, DOT_BRIGHTNESS / 30.0, DOT_BRIGHTNESS / 60.0, 1.0
            pcall(function() material_instance:SetVectorParameterValue("GizmoColor", c) end)
        end
    end
    -- Detach from the pawn so the location set each frame is a pure world location.
    pcall(function() comp:K2_DetachFromComponent(1, 1, 1, false) end)
    comp:SetVisibility(false, false)
    local light_class = api:find_uobject("Class /Script/Engine.PointLightComponent")
    glow = light_class ~= nil and api:add_component_by_class(pawn, light_class) or nil
    if glow ~= nil then
        pcall(function()
            local lc = StructObject.new(color_struct)
            lc.R, lc.G, lc.B, lc.A = 1.0, 0.05, 0.02, 1.0
            glow:SetLightColor(lc, true)
            glow:SetIntensity(GLOW_INTENSITY)
            glow:SetAttenuationRadius(GLOW_RADIUS)
            glow:SetCastShadows(false)
            glow:K2_DetachFromComponent(1, 1, 1, false)
            glow:SetVisibility(false, false)
        end)
    end
    log("created")
    return comp
end

local function hide_dot()
    if alive(dot) then
        pcall(function() dot:SetVisibility(false, false) end)
    end
    if alive(glow) then
        pcall(function() glow:SetVisibility(false, false) end)
    end
end

local function trace(pawn, from, to, ignore)
    local hit = StructObject.new(hit_result_struct)
    local color = StructObject.new(color_struct)
    local ok, blocked = pcall(function()
        return kismet_system:LineTraceSingle(pawn, from, to, 0, true, ignore or {}, 0, hit, true, color, color, 0.0)
    end)
    if not ok then log("trace error: " .. tostring(blocked)) end
    if not ok or not blocked then return nil end
    local location = hit.Location or hit.ImpactPoint
    local normal = hit.ImpactNormal or hit.Normal
    return location, normal
end

local tune_timer = 0.0
local last_tune_text = nil

local function read_tune(delta)
    tune_timer = tune_timer + delta
    if tune_timer < 2.0 or fs == nil or fs.read == nil then return end
    tune_timer = 0.0
    local ok, text = pcall(fs.read, "aitd_reticle_tune.txt")
    if not ok or text == nil or text == last_tune_text then return end
    last_tune_text = text
    local function num(key, current) return tonumber(text:match(key .. "%s*=%s*([%-%d%.]+)")) or current end
    DOT_ANGULAR_SIZE = num("size", DOT_ANGULAR_SIZE)
    DOT_MIN_SCALE = num("min", DOT_MIN_SCALE)
    GLOW_INTENSITY = num("glow", GLOW_INTENSITY)
    GLOW_RADIUS = num("radius", GLOW_RADIUS)
    DOT_BRIGHTNESS = num("bright", DOT_BRIGHTNESS)
    if alive(glow) then
        pcall(function() glow:SetIntensity(GLOW_INTENSITY) glow:SetAttenuationRadius(GLOW_RADIUS) end)
    end
    if alive(material_instance) then
        pcall(function()
            local c = StructObject.new(color_struct)
            c.R, c.G, c.B, c.A = DOT_BRIGHTNESS, DOT_BRIGHTNESS / 30.0, DOT_BRIGHTNESS / 60.0, 1.0
            material_instance:SetVectorParameterValue("GizmoColor", c)
        end)
    end
    log(string.format("tune size %.4f min %.4f glow %.1f radius %.1f bright %.1f", DOT_ANGULAR_SIZE, DOT_MIN_SCALE, GLOW_INTENSITY, GLOW_RADIUS, DOT_BRIGHTNESS))
end

local function update()
    if failed then return end
    local pawn = api:get_local_pawn(0)
    -- aitd_vr_ui.lua: false while loading and briefly after a new pawn appears.
    if pawn == nil or AITD_WORLD_SETTLED == false then forget_dot(false) return end
    if dot_owner ~= nil and dot_owner ~= pawn:get_address() then forget_dot(true) end
    if aitd_options ~= nil and aitd_options.laser_dot == false then hide_dot() return end

    local ok_aim, aiming = pcall(function() return pawn:IsAiming() end)
    if not ok_aim or not aiming then hide_dot() return end

    local ok_weapon, weapon = pcall(function() return pawn:GetActiveWeapon() end)
    if not ok_weapon or weapon == nil or not weapon:get_full_name():find("HitscanWeapon", 1, true) then
        hide_dot()
        return
    end

    if not init_statics() then
        failed = true
        log("missing engine classes, reticle disabled")
        return
    end

    if dot_owner ~= pawn:get_address() or not alive(dot) then
        dot = create_dot(pawn)
        dot_owner = pawn:get_address()
        if dot == nil then failed = true log("could not create the dot") return end
    end

    -- With aitd_vr_muzzle_ray.lua loaded, shots leave the muzzle along the barrel; follow them.
    -- GetTraceStart/End must not be called then: they run the deprojection that script hooks, and
    -- re-entering the Lua state from that hook fails with "resource deadlock would occur".
    local from, to
    local mx, my, mz, fx, fy, fz
    local muzzle_aim = aitd_options == nil or aitd_options.muzzle_aim ~= false
    if muzzle_aim and aitd_muzzle_ray ~= nil then mx, my, mz, fx, fy, fz = aitd_muzzle_ray(weapon) end
    if mx == nil and aitd_muzzle_ray ~= nil then
        -- The game's own ray (screen centre from the view, starting 80 cm ahead), rebuilt here
        -- because GetTraceStart would re-enter the deprojection hook.
        local pcm = api:get_player_controller(0).PlayerCameraManager
        local cx, cy, cz = xyz(pcm:GetCameraLocation())
        local r = pcm:GetCameraRotation()
        local pitch, yaw = math.rad(r.x or r.Pitch), math.rad(r.y or r.Yaw)
        fx, fy, fz = math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)
        mx, my, mz = cx + fx * 80.0, cy + fy * 80.0, cz + fz * 80.0
    end
    if mx ~= nil then
        from = Vector3f.new(mx, my, mz)
        to = Vector3f.new(mx + fx * 10000.0, my + fy * 10000.0, mz + fz * 10000.0)
    else
        from = weapon:GetTraceStart()
        to = weapon:GetTraceEnd()
    end
    -- The ray now starts at the muzzle, so the revolver itself must not catch it.
    local location, normal = trace(pawn, from, to, { weapon })
    if location == nil then
        location = to
        normal = nil
    end
    debug_frames = (debug_frames or 0) + 1
    if debug_frames % 90 == 0 then
        local fx, fy, fz = xyz(from)
        local lx, ly, lz = xyz(location)
        log(string.format("from %.0f,%.0f,%.0f dot %.0f,%.0f,%.0f hit=%s", fx, fy, fz, lx, ly, lz, tostring(normal ~= nil)))
    end

    local x, y, z = xyz(location)
    if normal ~= nil then
        local nx, ny, nz = xyz(normal)
        x, y, z = x + nx * SURFACE_OFFSET, y + ny * SURFACE_OFFSET, z + nz * SURFACE_OFFSET
    end

    local cam = api:get_player_controller(0).PlayerCameraManager:GetCameraLocation()
    local cx, cy, cz = xyz(cam)
    local dx, dy, dz = x - cx, y - cy, z - cz
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local scale = math.max(DOT_MIN_SCALE, distance * DOT_ANGULAR_SIZE / 100.0)

    dot:K2_SetWorldLocation(Vector3f.new(x, y, z), false, StructObject.new(hit_result_struct), false)
    dot:SetWorldScale3D(Vector3f.new(scale, scale, scale))
    dot:SetVisibility(true, false)
    if alive(glow) then
        pcall(function()
            glow:K2_SetWorldLocation(Vector3f.new(x, y, z), false, StructObject.new(hit_result_struct), false)
            glow:SetVisibility(normal ~= nil, false)
        end)
    end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    pcall(read_tune, delta)
    local ok, err = pcall(update)
    if not ok then
        failed = true
        log("disabled after error: " .. tostring(err))
    end
end)

log("loaded")
