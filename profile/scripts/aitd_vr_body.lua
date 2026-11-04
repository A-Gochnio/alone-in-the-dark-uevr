-- Alone in the Dark (2024) UEVR: hide the props on Edward's body that float in first person.
-- His body only turns toward the walking direction, so when the stick turns the view, the chest
-- flashlight (FlashlightMesh on FlashlightSocket) and the holstered revolver (an attached
-- BP_HitscanWeapon actor) stay behind and can block the view, especially when crouched.
-- Only the flashlight mesh is hidden; its light still works. A weapon is hidden while it is not
-- the active (drawn) one. The "Show belt items" option (aitd_vr_options.lua) turns this off.

local api = uevr.api

local CHECK_INTERVAL = 0.25
local timer = 0.0
local hidden_state = nil

local function apply(pawn, hide)
    pcall(function()
        local mesh = pawn.FlashlightMesh
        if mesh ~= nil then mesh:SetHiddenInGame(hide, false) end
    end)
    local active = nil
    pcall(function() active = pawn:GetActiveWeapon() end)
    local active_address = active ~= nil and active:get_address() or nil
    pcall(function()
        local class = api:find_uobject("Class /Script/ObsidianFox.HitscanWeaponActor")
        local pawn_address = pawn:get_address()
        for _, actor in ipairs(UEVR_UObjectHook.get_objects_by_class(class, false) or {}) do
            local parent = actor:GetAttachParentActor()
            if parent ~= nil and parent:get_address() == pawn_address then
                actor:SetActorHiddenInGame(hide and actor:get_address() ~= active_address)
            end
        end
    end)
    -- A drawn weapon hangs off the motion controller, not the pawn, so unhide it explicitly.
    if active ~= nil then pcall(function() active:SetActorHiddenInGame(false) end) end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    timer = timer + delta
    if timer < CHECK_INTERVAL then return end
    timer = 0.0
    -- aitd_vr_ui.lua: false while loading, when old weapon actors may be mid-destruction.
    if AITD_WORLD_SETTLED == false then return end
    local pawn = api:get_local_pawn(0)
    if pawn == nil then return end
    local hide = not (aitd_options ~= nil and aitd_options.show_belt_items == true)
    -- Unhide once when the option is switched on; otherwise re-apply, since drawing and
    -- holstering change which weapon is active.
    if hide or hidden_state ~= false then apply(pawn, hide) end
    hidden_state = hide
end)
