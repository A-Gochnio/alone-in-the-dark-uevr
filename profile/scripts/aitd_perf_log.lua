-- Engine tick timing logger for benchmarks without the uevr-mcp bridge (which caps the game at ~42 FPS).
-- Every 2 s it writes one line to aitd_perf.csv in the UEVR profile's data folder:
-- unix time, ticks, average/p95/max tick ms. tools/Measure-AitDPerf.ps1 -NoBridge reads it.
-- 30 s after injection it also writes the live renderer CVars to aitd_cvars.txt.
-- Install it next to alone_in_the_dark_vr.lua only for measurement sessions.

local WINDOW = 2.0
local elapsed = 0.0
local deltas = {}

local function write_line(line)
    if fs ~= nil and fs.write ~= nil then
        local previous = fs.read("aitd_perf.csv") or ""
        if #previous > 200000 then previous = "" end
        fs.write("aitd_perf.csv", previous .. line .. "\n")
    end
end

-- Renderer CVars as the engine sees them, written once to aitd_cvars.txt after the game settings are applied.
local CVARS = {
    "r.NGX.DLSS.Enable", "r.NGX.DLSS.Quality", "r.ScreenPercentage", "r.TemporalAA.Upsampling",
    "r.DefaultFeature.AntiAliasing", "r.Tonemapper.Sharpen", "r.MipMapLODBias", "r.ViewDistanceScale",
    "r.Streaming.PoolSize", "r.Shadow.CSM.MaxCascades", "sg.ShadowQuality", "r.ContactShadows",
    "r.SkeletalMeshLODBias", "r.StaticMeshLODDistanceScale", "r.MaxAnisotropy", "r.Streaming.MipBias",
    "r.DisableDistortion", "sg.ViewDistanceQuality", "sg.DetailQuality", "sg.ShadingQuality",
    "foliage.LODDistanceScale", "r.Streaming.Boost", "r.Streaming.FramesForFullUpdate",
    "r.Streaming.HiddenPrimitiveScale", "r.PostProcessing.DisableMaterials",
}
local cvar_dump_at = 30.0
local total = 0.0
local last_requests = nil

local function get_manager()
    local ok, manager = pcall(function() return uevr.api:get_console_manager() end)
    if not ok or fs == nil then return nil end
    return manager
end

-- Live CVar changes without the bridge: write "name=value" lines to data/aitd_cvar_set.txt. They are
-- applied when the file changes and also added to the dump. The game re-applies some of its own
-- settings (e.g. r.NGX.DLSS.Enable) on load, so requests are re-applied after each level load too.
local function apply_requests(force)
    local manager = get_manager()
    if manager == nil then return false end
    local text = fs.read("aitd_cvar_set.txt") or ""
    if text == last_requests and not force then return false end
    last_requests = text
    for name, value in text:gmatch("([%w%._]+)%s*=%s*([^\r\n]+)") do
        local found, var = pcall(function() return manager:find_variable(name) end)
        if found and var ~= nil then
            pcall(function() var:set_float(tonumber(value)) end)
        end
        local listed = false
        for _, known in ipairs(CVARS) do if known == name then listed = true end end
        if not listed then CVARS[#CVARS + 1] = name end
    end
    return true
end

local function dump_cvars()
    local manager = get_manager()
    if manager == nil then
        return
    end
    local lines = {}
    for _, name in ipairs(CVARS) do
        local value = "missing"
        local found, var = pcall(function() return manager:find_variable(name) end)
        if found and var ~= nil then
            local got, v = pcall(function() return var:get_float() end)
            if got then value = tostring(v) end
        end
        lines[#lines + 1] = name .. "=" .. value
    end
    fs.write("aitd_cvars.txt", table.concat(lines, "\n") .. "\n")
end

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
    total = total + delta
    if cvar_dump_at ~= nil and total >= cvar_dump_at then
        cvar_dump_at = nil
        dump_cvars()
    end
    deltas[#deltas + 1] = delta
    elapsed = elapsed + delta
    if elapsed < WINDOW then
        return
    end

    table.sort(deltas)
    local n = #deltas
    -- A long tick means a level load; re-apply requested CVars after it.
    if apply_requests(deltas[n] > 0.5) then dump_cvars() end
    local p95 = deltas[math.max(1, math.floor(n * 0.95))]
    write_line(string.format("%d,%d,%.2f,%.2f,%.2f", os.time(), n, 1000.0 * elapsed / n, 1000.0 * p95, 1000.0 * deltas[n]))
    deltas = {}
    elapsed = 0.0
end)
