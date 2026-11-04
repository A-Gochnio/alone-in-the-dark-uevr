-- Diagnostic only: every 2 s writes data/aitd_height.txt with the pawn, head bone, capsule and
-- rendered camera heights (Unreal units, cm) plus the HMD pose and UEVR standing origin, to tune
-- the first-person camera height. Remove from scripts/ when done.

local timer = 0.0

local function vec(v)
    if v == nil then return "nil" end
    return string.format("(%.1f, %.1f, %.1f)", v.X or v.x or 0, v.Y or v.y or 0, v.Z or v.z or 0)
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    timer = timer + delta
    if timer < 2.0 then return end
    timer = 0.0

    local lines = {}
    local function add(k, f)
        local ok, v = pcall(f)
        lines[#lines + 1] = k .. "=" .. (ok and tostring(v) or ("ERR " .. tostring(v)))
    end

    local pawn = uevr.api:get_local_pawn(0)
    local pc = uevr.api:get_player_controller(0)
    if pawn ~= nil then
        add("pawn", function() return vec(pawn:K2_GetActorLocation()) end)
        add("capsule_half", function() return pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
        add("head_bone", function() return vec(pawn.Mesh:GetSocketLocation("head")) end)
        add("mesh", function() return vec(pawn.Mesh:K2_GetComponentLocation()) end)
    end
    if pc ~= nil then
        add("cam_mgr", function() return vec(pc.PlayerCameraManager:GetCameraLocation()) end)
    end
    local vr = uevr.params.vr
    add("standing_origin", function()
        local o = UEVR_Vector3f.new()
        vr.get_standing_origin(o)
        return vec(o)
    end)
    add("hmd", function()
        local p, r = UEVR_Vector3f.new(), UEVR_Quaternionf.new()
        vr.get_pose(vr.get_hmd_index(), p, r)
        return vec(p)
    end)
    add("up_offset", function() return vr.get_mod_value("VR_CameraUpOffset") end)

    if fs ~= nil and fs.write ~= nil then
        fs.write("aitd_height.txt", table.concat(lines, "\n") .. "\n")
    end
end)

-- XInput as UEVR sends it to the game (before alone_in_the_dark_vr.lua remaps it if that runs
-- later): logs each change of buttons/triggers to data/aitd_input.txt, newest last.
local BUTTONS = {
    [0x0001] = "DPadUp", [0x0002] = "DPadDown", [0x0004] = "DPadLeft", [0x0008] = "DPadRight",
    [0x0010] = "Start", [0x0020] = "Back", [0x0040] = "L3", [0x0080] = "R3",
    [0x0100] = "LB", [0x0200] = "RB", [0x1000] = "A", [0x2000] = "B", [0x4000] = "X", [0x8000] = "Y",
}
local last_input = ""
local input_log = {}

uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    if state == nil or state.Gamepad == nil then return end
    local g = state.Gamepad
    local names = {}
    for mask, name in pairs(BUTTONS) do
        if (g.wButtons & mask) ~= 0 then names[#names + 1] = name end
    end
    table.sort(names)
    if g.bLeftTrigger > 30 then names[#names + 1] = "LT" end
    if g.bRightTrigger > 30 then names[#names + 1] = "RT" end
    local function stick(x, y, n)
        if math.abs(x) > 12000 or math.abs(y) > 12000 then
            names[#names + 1] = string.format("%s(%d,%d)", n, x // 3277, y // 3277)
        end
    end
    stick(g.sThumbLX, g.sThumbLY, "LS")
    stick(g.sThumbRX, g.sThumbRY, "RS")
    local text = table.concat(names, " ")
    if text == last_input then return end
    last_input = text
    input_log[#input_log + 1] = ((os ~= nil and os.date ~= nil) and os.date("%H:%M:%S ") or "") .. (text == "" and "-" or text)
    if #input_log > 60 then table.remove(input_log, 1) end
    if fs ~= nil and fs.write ~= nil then
        fs.write("aitd_input.txt", table.concat(input_log, "\n") .. "\n")
    end
end)
