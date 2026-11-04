-- Test-only: simulated Quest controller input (tools/Send-AitDSimQuest.ps1). Copy to the UEVR profile scripts/ only for tests; it is not part of the play profile or the release.
--
-- Reads data/aitd_sim_input.txt, one command per write:
--   seq=<n> buttons=A,RB,LS lt=<0-255> rt=<0-255> lx=<-32768..32767> ly= rx= ry= dur=<seconds>
-- Each new seq replaces the physical XInput state for dur seconds, as UEVR would report the Quest
-- controllers (grips = LB/RB, triggers = LT/RT, A/B/X/Y, sticks, LS/RS = stick clicks), before
-- alone_in_the_dark_vr.lua's remap runs on it. Writes data/aitd_sim_ack.txt with the applied seq.

local BUTTONS = {
    DPAD_UP = 0x0001, DPAD_DOWN = 0x0002, DPAD_LEFT = 0x0004, DPAD_RIGHT = 0x0008,
    START = 0x0010, BACK = 0x0020, LS = 0x0040, RS = 0x0080,
    LB = 0x0100, RB = 0x0200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000,
}

local clock = 0.0
local read_timer = 0.0
local last_seq = nil
local active_until = 0.0
local pad = nil
local calls = 0
local retval_info = nil

local function parse(text)
    local seq = text:match("seq=(%d+)")
    if seq == nil then return nil end
    local p = { seq = tonumber(seq), buttons = 0 }
    for name in (text:match("buttons=([%w_,]*)") or ""):gmatch("[%w_]+") do
        p.buttons = p.buttons | (BUTTONS[name] or 0)
    end
    for _, k in ipairs({ "lt", "rt", "lx", "ly", "rx", "ry" }) do
        p[k] = math.tointeger(tonumber(text:match(k .. "=(%-?%d+)")) or 0)
    end
    p.dur = tonumber(text:match("dur=([%d%.]+)")) or 0.2
    return p
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    clock = clock + delta
    if pad ~= nil and clock >= active_until then pad = nil end
    AITD_SIM_PAD = pad
    read_timer = read_timer + delta
    if read_timer < 0.03 or fs == nil then return end
    read_timer = 0.0
    local text = fs.read("aitd_sim_input.txt")
    if text == nil then return end
    local p = parse(text)
    if p == nil or p.seq == last_seq then return end
    last_seq = p.seq
    pad = p
    active_until = clock + p.dur
    AITD_SIM_PAD = pad
    fs.write("aitd_sim_ack.txt", string.format("seq=%d clock=%.2f calls=%d retval=%s\n", p.seq, clock, calls,
        tostring(retval_info)))
end)

AITD_SIM_APPLY = function(retval, state)
    local p = AITD_SIM_PAD
    calls = calls + 1
    if retval_info == nil then retval_info = type(retval) .. ":" .. tostring(retval) end
    local gp = state.Gamepad
    gp.wButtons = p.buttons
    gp.bLeftTrigger = p.lt
    gp.bRightTrigger = p.rt
    gp.sThumbLX, gp.sThumbLY = p.lx, p.ly
    gp.sThumbRX, gp.sThumbRY = p.rx, p.ry
end

-- Probe: does UEVR call the XInput callback at all here, and what is retval?
local probe_calls = 0
local probe_timer = 0.0
local retval_dump = nil
local per_index = {}
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    probe_calls = probe_calls + 1
    local e = per_index[user_index] or { n = 0, b = 0 }
    e.n = e.n + 1
    if state ~= nil and state.Gamepad ~= nil and state.Gamepad.wButtons ~= 0 then e.b = state.Gamepad.wButtons end
    e.r = tostring(retval)
    per_index[user_index] = e
    AITD_SIM_PER_INDEX = per_index
    if retval_info == nil then retval_info = type(retval) .. ":" .. tostring(retval) end
    if retval_dump == nil then
        local parts = {}
        local mt = getmetatable(retval)
        if type(mt) == "table" then
            for k, v in pairs(mt) do parts[#parts + 1] = tostring(k) .. "=" .. type(v) end
            local idx = rawget(mt, "__index")
            if type(idx) == "table" then
                for k, v in pairs(idx) do parts[#parts + 1] = "idx." .. tostring(k) .. "=" .. type(v) end
            end
        else
            parts[#parts + 1] = "mt=" .. tostring(mt)
        end
        local ok, v = pcall(function() return retval[0] end)
        parts[#parts + 1] = "[0]=" .. tostring(ok) .. ":" .. tostring(v)
        ok, v = pcall(function() return retval.value end)
        parts[#parts + 1] = "value=" .. tostring(ok) .. ":" .. tostring(v)
        retval_dump = table.concat(parts, " ")
        if fs ~= nil then fs.write("aitd_sim_retval.txt", retval_dump .. "\n") end
    end
    -- Apply the simulated pad. This script loads before alone_in_the_dark_vr.lua (alphabetical),
    -- so this callback runs first and the remap sees the simulated state, as it would see Quest input.
    if AITD_SIM_PAD ~= nil and state ~= nil and state.Gamepad ~= nil then
        AITD_SIM_APPLY(retval, state)
    end
end)
uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
    probe_timer = probe_timer + delta
    if probe_timer < 1.0 or fs == nil then return end
    probe_timer = 0.0
    local idx = {}
    for i, e in pairs(per_index) do idx[#idx + 1] = string.format("[%d n=%d lastbtn=0x%X ret=%s]", i, e.n, e.b, e.r) end
    fs.write("aitd_sim_probe.txt", string.format("clock=%.1f xinput_calls=%d retval=%s state=%s %s\n", clock,
        probe_calls, tostring(retval_info), tostring(AITD_MAIN_STATE), table.concat(idx, " ")))
end)

print("[AitD VR] Test input simulation loaded (data/aitd_sim_input.txt)")
