-- Alone in the Dark (2024) UEVR: player options page in the UEVR menu (LuaLoader > Script UI).
-- Options live in the global aitd_options table, which the other scripts read each frame (a nil
-- table or field means the default), and persist to data/aitd_options.txt as key=true/false lines.

local FILE = "aitd_options.txt"

local DEFAULTS = {
    { key = "laser_dot", label = "Laser aim dot", default = true,
      help = "Red dot where the revolver's shot will land, shown while aiming." },
    { key = "muzzle_aim", label = "Shoot from the barrel", default = true,
      help = "Shots leave the gun muzzle along the barrel. Off: the game's own ray from the head." },
    { key = "show_belt_items", label = "Show belt items", default = false,
      help = "Show the chest flashlight and holstered revolver, which do not turn with your view." },
}

aitd_options = {}
for _, o in ipairs(DEFAULTS) do aitd_options[o.key] = o.default end

local function load()
    if fs == nil or fs.read == nil then return end
    local ok, text = pcall(fs.read, FILE)
    if not ok or text == nil then return end
    for _, o in ipairs(DEFAULTS) do
        local v = text:match(o.key .. "%s*=%s*(%a+)")
        if v == "true" then aitd_options[o.key] = true elseif v == "false" then aitd_options[o.key] = false end
    end
end

local function save()
    if fs == nil or fs.write == nil then return end
    local lines = {}
    for _, o in ipairs(DEFAULTS) do lines[#lines + 1] = o.key .. "=" .. tostring(aitd_options[o.key]) end
    pcall(fs.write, FILE, table.concat(lines, "\n") .. "\n")
end

load()

uevr.sdk.callbacks.on_draw_ui(function()
    imgui.text("Alone in the Dark VR")
    for _, o in ipairs(DEFAULTS) do
        local changed, value = imgui.checkbox(o.label, aitd_options[o.key])
        if changed then
            aitd_options[o.key] = value
            save()
        end
        if imgui.is_item_hovered() then imgui.set_tooltip(o.help) end
    end
end)
