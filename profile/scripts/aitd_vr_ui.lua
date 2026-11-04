-- Alone in the Dark (2024) UEVR UI handling.
--
-- 1. The game's crosshair is drawn at the centre of the head-locked UI panel, but with motion
--    controls the shots follow the right controller, so the crosshair points the wrong way.
--    Hide it.
-- 2. Sizes the UI panel per game state: gameplay (subtitles, health bar) and full-screen menus
--    (pause, options, investigation, documents, map, archive, loading, main menu) get their own
--    distance and size. Gameplay follows the head; menus are fixed in the room (Arek's choice).
--
-- The mode comes from the game's own GameSubsystem_PlayState main state (observed values:
-- 0 gameplay, 3 investigation menu with map/documents, 4 pause menu and options, 6 loading,
-- 7 main menu). Other values are logged to data/aitd_ui_state.txt so they can be classified.
--
-- Each mode's panel distance and size can be tuned below. Size divided by distance sets the
-- panel's angular width: 2.0 / 2.0 is about 53 degrees, 2.2 / 2.5 about 47,
-- 1.6 / 2.5 about 36, 2.7 / 4.0 about 37.
-- Arek: menus too close and too big, HUD items at the panel edges hard to see; both shrunk,
-- and menus moved further back.

local GAMEPLAY_UI = { follow_view = true, distance = 2.5, size = 1.6 }
local MENU_UI = { follow_view = false, distance = 4.0, size = 2.7 }
-- Room-fixed menus sometimes appeared above or below eye level and tilted. Likely cause (not yet
-- confirmed): with decoupled pitch, UEVR tilts the UI by the game camera pitch, which follows the
-- right controller's aim. So VR_DecoupledPitchUIAdjust is turned off.
local MENU_STATES = { [3] = true, [4] = true, [6] = true, [7] = true }
local HIDE_CROSSHAIR = true

local ESLATE_HIDDEN = 2
local CHECK_INTERVAL = 0.1
local RESCAN_INTERVAL = 1.0

local crosshair_class = nil
local equipment_class = nil
local image_class = nil
local found_corner = false
local corner_retry = 0.0
local play_state_class = nil
local crosshairs = {}
local play_state = nil
local check_timer = 0.0
local rescan_timer = RESCAN_INTERVAL
local current_mode = nil
local seen_states = {}
local last_state = -1

local function find_class(name)
    local ok, c = pcall(function() return uevr.api:find_uobject(name) end)
    if ok then return c end
    return nil
end

local function instances(class)
    if class == nil then return {} end
    local ok, list = pcall(function() return class:get_objects_matching(false) end)
    if ok and list ~= nil then return list end
    return {}
end

local function alive(obj)
    if obj == nil then return false end
    if UEVR_UObjectHook == nil or UEVR_UObjectHook.exists == nil then return true end
    local ok, exists = pcall(function() return UEVR_UObjectHook.exists(obj) end)
    return ok and exists
end

local shift_objective_text -- defined below

-- Widgets to keep hidden: the crosshair, and the dark corner gradient behind the weapon panel
-- (WBP_InGame_Equipment.background_corner), which only makes sense in a screen corner.
local function collect_hidden_widgets()
    local list = {}
    crosshair_class = crosshair_class
        or find_class("WidgetBlueprintGeneratedClass /Game/ObsidianFox/UI/WBP_Crosshair.WBP_Crosshair_C")
    for _, w in ipairs(instances(crosshair_class)) do list[#list + 1] = w end
    equipment_class = equipment_class
        or find_class("WidgetBlueprintGeneratedClass /Game/ObsidianFox/UI/HUD/WBP_InGame_Equipment.WBP_InGame_Equipment_C")
    for _, w in ipairs(instances(equipment_class)) do
        local live = w:get_full_name():find("/Engine/Transient", 1, true) ~= nil
        local ok, corner = pcall(function() return live and w.background_corner or nil end)
        if ok and corner ~= nil then
            list[#list + 1] = corner
            found_corner = true
        end
    end
    -- The objective text has the same corner gradient; find it by texture.
    image_class = image_class or find_class("Class /Script/UMG.Image")
    for _, image in ipairs(instances(image_class)) do
        local name = image:get_full_name()
        if name:find("Transient", 1, true) and name:find("WBP_ObjectiveText_C_", 1, true) then
            local ok, texture = pcall(function() return image.Brush.ResourceObject:get_fname():to_string() end)
            if ok and texture ~= nil and texture:find("corner_gradient", 1, true) then
                list[#list + 1] = image
            end
        end
    end
    return list
end

-- These objects belong to the game instance and normally live for the whole session. Searching
-- the object array is expensive, so it only happens while one of them is missing or destroyed.
local function rescan()
    corner_retry = corner_retry + RESCAN_INTERVAL
    local retry_corner = not found_corner and corner_retry >= 5.0
    if retry_corner then corner_retry = 0.0 end
    if retry_corner or #crosshairs == 0 or not alive(crosshairs[1]) or not alive(crosshairs[#crosshairs]) then
        crosshairs = collect_hidden_widgets()
        shift_objective_text()
    end
    if not alive(play_state) then
        play_state_class = play_state_class
            or find_class("Class /Script/ObsidianFox.GameSubsystem_PlayState")
        play_state = instances(play_state_class)[1]
    end
end

-- Objective updates appear in the top-left corner, too far out for a head-locked panel. Shift
-- the whole widget toward the centre (slate units; Arek asked for it to be closer).
local OBJECTIVE_SHIFT_X = 300.0
local OBJECTIVE_SHIFT_Y = 120.0
local objective_class = nil
local vector2d_struct = nil

shift_objective_text = function()
    objective_class = objective_class
        or find_class("WidgetBlueprintGeneratedClass /Game/ObsidianFox/UI/InGameHud/WBP_ObjectiveText.WBP_ObjectiveText_C")
    vector2d_struct = vector2d_struct or find_class("ScriptStruct /Script/CoreUObject.Vector2D")
    if objective_class == nil or vector2d_struct == nil then return end
    for _, w in ipairs(instances(objective_class)) do
        if w:get_full_name():find("/Engine/Transient", 1, true) then
            pcall(function()
                local t = StructObject.new(vector2d_struct)
                t.X, t.Y = OBJECTIVE_SHIFT_X, OBJECTIVE_SHIFT_Y
                w:SetRenderTranslation(t)
            end)
        end
    end
end

local function hide_crosshairs()
    for _, w in ipairs(crosshairs) do
        if not alive(w) then return end
        pcall(function()
            if w:GetVisibility() ~= ESLATE_HIDDEN then
                w:SetVisibility(ESLATE_HIDDEN)
            end
        end)
    end
end

local function write_state(state)
    if fs == nil or fs.write == nil then return end
    local list = {}
    for s in pairs(seen_states) do list[#list + 1] = tostring(s) end
    table.sort(list)
    fs.write("aitd_ui_state.txt", string.format("mode=%s state=%s seen=%s\n",
        tostring(current_mode), tostring(state), table.concat(list, ",")))
end

local function main_state()
    if not alive(play_state) then return nil end
    local ok, state = pcall(function() return play_state:GetMainState() end)
    if ok then return state end
    return nil
end

local function apply_mode(mode, state)
    local ui = mode == "menu" and MENU_UI or GAMEPLAY_UI
    local vr = uevr.params.vr
    vr.set_mod_value("VR_DecoupledPitchUIAdjust", "false")
    vr.set_mod_value("UI_FollowView", ui.follow_view and "true" or "false")
    vr.set_mod_value("UI_Distance", string.format("%.3f", ui.distance))
    vr.set_mod_value("UI_Size", string.format("%.3f", ui.size))
    current_mode = mode
    print(string.format("[AitD VR UI] %s panel (main state %s)", mode, tostring(state)))
end

-- AITD_WORLD_SETTLED is shared with the other scripts: false while loading (main state 6), in the
-- main menu (7), without a pawn, and for a short grace period after a new pawn appears (save
-- reload, chapter change), while the old world is torn down. Scripts skip their game calls and
-- spawning then.
local PAWN_SETTLE_SECONDS = 1.5
local settled_pawn = nil
local pawn_seen_at = 0.0
local clock = 0.0
AITD_WORLD_SETTLED = false

local function update_settled(delta)
    clock = clock + delta
    local pawn = uevr.api:get_local_pawn(0)
    local address = pawn ~= nil and pawn:get_address() or nil
    if address ~= settled_pawn then
        settled_pawn = address
        pawn_seen_at = clock
    end
    local state = AITD_MAIN_STATE
    AITD_WORLD_SETTLED = address ~= nil and state ~= 6 and state ~= 7
        and clock - pawn_seen_at >= PAWN_SETTLE_SECONDS
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    if not pcall(update_settled, delta) then AITD_WORLD_SETTLED = false end
    rescan_timer = rescan_timer + delta
    if rescan_timer >= RESCAN_INTERVAL then
        rescan_timer = 0.0
        rescan()
    end

    if HIDE_CROSSHAIR then
        hide_crosshairs()
    end

    check_timer = check_timer + delta
    if check_timer < CHECK_INTERVAL then
        return
    end
    check_timer = 0.0

    local state = main_state()
    AITD_MAIN_STATE = state -- shared with alone_in_the_dark_vr.lua (same Lua state)
    local mode = "gameplay"
    if uevr.api:get_local_pawn(0) == nil or state == nil or MENU_STATES[state] then
        mode = "menu" -- main menu, loading, or a full-screen game menu
    end

    if state ~= nil then seen_states[state] = true end

    if mode ~= current_mode then
        apply_mode(mode, state)
    end
    if state ~= last_state then
        last_state = state
        write_state(state)
    end
end)

print("[AitD VR UI] loaded")
