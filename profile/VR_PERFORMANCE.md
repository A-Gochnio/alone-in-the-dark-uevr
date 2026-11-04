# VR performance tuning

## 2026-10-24 result: locked 90 FPS (verified in the headset)

Quest 3 over Virtual Desktop (target 90 FPS, SSW disabled, Ultra preset, HEVC 10-bit, 5 GHz Wi-Fi), RTX 4070 Ti. The user confirmed in the headset: a very stable 90 FPS, VD game latency 8 ms (was ~23 ms), smooth head turns, first person, no per-eye artifacts, and the revolver pointing along the controller.

### Root cause of the old ~42 FPS ceiling

**The uevr-mcp bridge plugin** (`plugins/uevr_mcp.dll`). Its per-frame callbacks (Lua frame dispatch, property watch, `on_present`) each took ~4 ms and held the engine at a fixed ~23.6 ms per tick in every mode. With it loaded, the GPU was only 30–40% busy, and the rate stayed at 42 regardless of GPU load (DLSS -1 + lowfx at 6.3 ms of GPU work gave the same 42.2 FPS as stock), VD 80 vs 90 FPS, SSW on/off, `rhi.SyncInterval`, UEVR synchronization modes 0/1, `bSmoothFrameRate`, `t.MaxFPS` and OptiScaler removal. Moving the DLL out of `plugins/` immediately gave 88–90 encoded FPS with the GPU at 100% (stock settings).

Consequences:

- **Keep `uevr_mcp.dll` out of the profile for play and benchmarks.** It is backed up in `backups/mcp-off-20261024-094822/`. Put it back only for debugging sessions, and don't trust FPS numbers while it is loaded. Yesterday's sweep numbers were all taken with it loaded, so only their relative GPU work remains useful.
- Without the plugin nothing activates UObjectHook, which the first-person camera (`uobjecthook/camera_state.json`) needs; the game falls back to third person. Fixed with `UObjectHook_EnabledAtStartup=true`.
- Earlier measurements: the bridge's Lua frame callback undercounts ticks (32/s vs the CSV profiler's 42/s). `Measure-AitDPerf.ps1` now uses `csvprofile start/stop` with the bridge and the UEVR Lua tick logger without it.

Also removed (not the cause, but they hooked every frame): yesterday's stock and stereo OptiScaler/OFXR installs, via `Set-AitDStereoOptiScaler.ps1 -Mode Remove` and `Set-AitDOptiScaler.ps1 -Mode Remove`. The game binary folder is stock again.

### Measurements without the bridge (Native Stereo: one tick = one VR frame)

From `Measure-AitDPerf.ps1 -NoBridge` (Lua tick log + per-process 3D busy time + NVENC FPS), steady state after the save loaded, standing in the greenhouse. The frame time is VD-paced at 11.1 ms; GPU ms is per VR frame at 2880 MHz.

| Settings | FPS | avg / worst p95 / max ms | GPU ms (busy) | Headset |
|---|---|---|---|---|
| Synchronized Sequential, DLSS 1, stock fx, **bridge loaded** | 21 VR (42 ticks) | 23.6 / 31 / – | 13.3 (30%) | VD game latency ~23 ms |
| Synchronized Sequential, DLSS 1, stock fx, no bridge | encoder 88 | – | 3D engine 82% | not checked |
| C72: Native Stereo + fix, DLSS -1, lowfx, sh0 | 90.0 | 11.11 / 12.4 / 13.6 | 7.75 (70%) | 90 FPS, 8 ms, smooth, "could be sharper" |
| + UObjectHook at startup | 90.1 | 11.10 / 12.4 / 15.7 | 6.94 (63%) | first person again, no eye artifacts |
| DLSS 0 (Balanced) | 89.6–90.1 | 11.1 / 12.3 / – | 7.5 (68%) | "not noticeably sharper" |
| DLSS 1 (Quality) + `r.DisableDistortion 1` | 90.0 | 11.11 / 12.3 / 14.7 | 8.5 (77%) | "maybe a little better", distant heat-haze wiggle reduced |
| **Final:** + View Distance/Detail Epic, Shading/Foliage 2, pool 5 GB, AF 16x, skel LOD bias -1, mip bias -0.5 | 89.9 | 11.12 / 12.5 / 13.4 | 8.6 (78%), VRAM 7.9/12 GB | no new shimmer, "runs amazing" |

The p95 of ~12.4 ms with an 11.1 ms average is VD frame-pacing jitter, not missed frames: the engine averages exactly 90 ticks/s.

### Quality pass: pop-in, sharpness and the DLSS "heat haze" (same day)

Changes from here on were made live through the Lua CVar channel (`data/aitd_cvar_set.txt`, see `profile/README.md`) where possible. VD was at 90 FPS unless noted.

| Change | FPS | GPU ms | Headset verdict |
|---|---|---|---|
| Sharpen 0.8, static mesh LOD distance 0.5, foliage LOD x2, streaming boost 2, full update 2 frames, hidden-primitive scale 1 | 90 | 8.9 | pop-in "way better"; only the big greenhouse tree popped; new leaf flicker |
| + static mesh LOD 0.35, foliage LOD x3, sharpen 0.4, `r.PostProcessing.DisableMaterials 1` | 90 | 8.6 | the tree no longer pops; haze unchanged (post-process materials reverted) |
| DLSS off, TAA 70% | 90 | 8.0 | **haze gone**, much softer; leaves still flicker |
| Sharpen 0, mip bias 0 (TAA) | – | – | leaves still flicker. The flicker is also visible on the flat monitor, so it is game-side, not VR. The user ranks it below pop-in; leave it |
| DLSS 3.1.1 → **DLSS 4 310.9.16** (official NVIDIA GitHub, Authenticode-valid; SHA-256 `D00B5B0A…6123E`; original in `backups/dlss-3.1.1-20261024-103308/`), default transformer preset, Quality | 76.6 | 10.7 | – |
| transformer at Balanced / Performance | 84.9 / 84.2 | 9.9 / 10.4 | cost scales with output resolution, not input |
| `r.NGX.DLSS.Preset=5` (CNN E), Quality | 89.1 | 9.2 | sharp, haze "back and quite strong" |
| preset 3 | 76.4 | 11.2 | heavier; the plugin's preset numbering is not A=1 |
| + `r.NGX.DLSS.DilateMotionVectors 0` | ~90 | ~9.2 | **haze weaker** (kept) |
| TAAU 85% / 75%, current-frame weight 0.2, sharpen 0.6 | 82.5 / 90 | 10.5 / 9.0 | no haze, but jagged/shiny swimming edges and a foggy look |
| TAA 100% | 61 | 14.4 | too heavy |
| transformer, Quality, dilation off, VD 72 | 78 (72 locked at VD 72) | 11.1 | "very sharp", haze still there |
| + `VR_NativeStereoFixSamePass=false` | 72 | 11.2 | haze **very strong** (reverted) |
| Synchronized Sequential + `VR_GhostingFix`, transformer | 72 (144 ticks) | 11.6 | strong haze plus ghost images (reverted) |

Conclusion: every DLSS variant (3.1.1/4, CNN/transformer, all levels) shows a motion-dependent haze in Native Stereo, and TAA does not. DLSS is getting imperfect motion vectors or jitter from UEVR's stereo rendering. Disabling motion-vector dilation reduces it. UEVR nightly 01143 (2026-08-30) is the newest official build, and UEVR main has no later commits. The remaining lead is PureDark's UEVR fork (Discord/Patreon only; the user would fetch it).

### Alternative UEVR builds (evening session)

The builds Rai Pal offers come from public GitHub releases (Rai Pal's `rai-pal-db/scripts/mod-db/uevr/uevr.ts`). They were downloaded to ignored `local/downloads/uevr-builds/<name>/x/` and injected with `Invoke-AitDUevrInject.ps1 -UevrDir`. The pinned nightly in Rai Pal's folder is untouched. The profile backup from before these tests is `backups/uevr-profile-before-alt-builds-20261024-111730/`. All binaries are unsigned.

| Build | zip SHA-256 (prefix) | Result |
|---|---|---|
| joeyhodge/UEVR `102626_FFR_SWGR_Patch` | `FDF325C62BA43BC1` | 90 FPS (GPU 8.0 ms), but **broken**: one eye blank, the other alternates both views out of sync. It also migrates `config.txt` with many new keys. Dropped. |
| PureDark/UEVR `UEVR_AFW_v1.0-beta.6` nightly AFW (log tag says beta.5) | `C5EB5D3F6C356D20` | best image so far (weak haze, very sharp), but **ghosting/rubber-banding when turning the head**, each eye independently. Not playable yet. |
| PureDark JoeyHodge AFW beta.6 | `BD2CA515E685B135` | not tested (based on the broken JoeyHodge build) |

AFW setup: `VR_RenderingMethod=3` (the menu order is Native Stereo, Synchronized Sequential, Alternating/AFR, Alternate Frame Warping) and `VR_GhostingFix=true`. `PDAFWPlugin.dll` loads from the build folder. Options are `VR_AFW_FramewarpMode` (1 AlternateEyeWarping, 2 PreviousFrameWarping, 3 CombinedWarping, the default), `VR_AFW_UltraResponsive` and `VR_AFW_ShadingRate`. DLSS must be on, and **changing DLSS CVars live while AFW runs crashes `PDAFWPlugin` (access violation)**, so restart instead.

| AFW variant (DLSS 4 E Balanced, pool 3 GB) | FPS / GPU | Verdict |
|---|---|---|
| mode 3, pool 5 GB, DLSS Quality, VD 72 | ~72, GPU 94% | choppy when turning; PC almost unresponsive (killed) |
| mode 3, pool 3 GB, Balanced | 75 ticks, GPU 97–98%, VRAM 8.9 GB | per-eye rubber-banding on rotation only; PC still crawled. The cause was VD Streamer's **"Boost game priority"**: after the user disabled it, the PC stayed responsive |
| + UltraResponsive on | ~72 | same rubber-banding |
| mode 1 (Alternate Eye), UltraResponsive on | **90 locked, GPU 9.0 ms** | "performance amazing, like butter", but turning ghosting remains |
| mode 1, UltraResponsive off | 90 | "a little better", still unacceptable |
| mode 2 (Previous Frame), dilation off → on | 90 | same as mode 1; "better than the first runs, not acceptable" |

Untested AFW leads: the game's original DLSS 3.1.1 with default presets (no `Preset=5`); AFW through SteamVR's runtime instead of VDXR; `VR_AFW_ShadingRate`; `VR_AFW_FixObjectMotionVector` off. The final AFW config is kept in `backups/uevr-config-afw-final-*/` for a later retry.

### AFW follow-up tests (2026-10-25 morning)

VD at 90, SSW off, "Boost game priority" off. All tests used AFW mode 1 (Alternate Eye), Ultra Responsive off, Ghosting fix on, DLSS Balanced, 3 GB pool. Backup of the baseline from before these tests: `backups/baseline-before-afw-tests-20261025-092054/` (`config.txt`, DLSS 4 DLL, `steamvr.vrsettings`).

| Test | Result |
|---|---|
| Game's original DLSS 3.1.1 (restored from `backups/dlss-3.1.1-*`), no preset override, dilation default, VDXR | 90 FPS, but **worse**: more turning ghosting, abstract artifacts flashing every few seconds, strong haze |
| DLSS 4 preset E, dilation off, UEVR **OpenVR** mode on SteamVR (through VD's SteamVR driver) | **GPU TDR** (`LiveKernelEvent 141`, nvlddmkm) ~10 s after injection. The game died, and the log showed `VRCompositor failed to submit left eye: 108` before it. SteamVR and VD survived |
| Same, OpenXR with SteamVR as the runtime for the game process only (`XR_RUNTIME_JSON=...\SteamVR\steamxr_win64.json`) | the game hung ("Not responding") before UEVR could be injected and never reached VR |

Conclusion: no tested AFW variant fixes the turning ghosting. AFW stays rejected for this game until PureDark ships a newer build. The remaining untested knobs are `VR_AFW_ShadingRate` and `VR_AFW_FixObjectMotionVector=false`, on VDXR only.

Side notes:
- SteamVR had `driver_VirtualDesktop.blocked_by_safe_mode=true` in `C:\Program Files (x86)\Steam\config\steamvr.vrsettings`, so it found no HMD. This was set to `false`, and SteamVR now sees the Quest 3 through VD. The original file is in the backup above.
- `Invoke-AitDUevrInject.ps1` attaches to *any* game PID it finds. A stalled run from an earlier attempt injected the AFW build into the next relaunch. Stop leftover inject jobs before relaunching, and check the `Tag:` line at the top of the UEVR log (pinned nightly = `1.05`, AFW = `UEVR_AFW_v1.0-beta.5`).
- Turning the Quest's USB stay-awake off while the user is in the headset darkened the view (session lost focus). Keep `quest-keep-awake.ps1 -Mode On -Continuous` running for the whole session and run `-Mode Off` only at the very end.

VD state at the end: target frame rate 72 at the user's last setting (set back to 90 for the baseline), SSW disabled, "Boost game priority" disabled.

### Final profile (in place on the PC; approved by the user on 2026-10-25, performance work marked solved)

Current baseline (supersedes the list below where they differ): Native Stereo + Native Stereo Fix (SamePass true), UObjectHook at startup, DLSS 4 310.9.16 with `r.NGX.DLSS.Preset=5` and `r.NGX.DLSS.DilateMotionVectors=0` at Quality, `r.Tonemapper.Sharpen=0.4`, `r.StaticMeshLODDistanceScale=0.35`, `foliage.LODDistanceScale=3`, `r.Streaming.Boost=2`, `r.Streaming.FramesForFullUpdate=2` and `r.Streaming.HiddenPrimitiveScale=1`, plus the settings below. VD target: 90 FPS.

Earlier list:

- UEVR `config.txt` (copy in `profile/config.txt`): `VR_RenderingMethod=0`, `VR_NativeStereoFix=true`, `UObjectHook_EnabledAtStartup=true`, `OpenXR_ResolutionScale=1.0`. Original config: `backups/uevr-config-20261024-095501/`.
- Game `GameUserSettings.ini` + `settings.sav` (via `Set-AitDVRGraphics.ps1 -Override`): `DLSSQualityLevel=1`, `sg.ShadowQuality=0`, `sg.ViewDistanceQuality=3`, `sg.DetailQuality=3`, `sg.ShadingQuality=2`, `sg.FoliageQuality=2`, plus the script's defaults (textures 3, AF 3, no motion blur/DoF/CA).
- `Engine.ini [SystemSettings]` (via `-SystemSettings`): `r.ContactShadows=0`, `r.CapsuleShadows=0`, `r.BloomQuality=1`, `r.MotionBlurQuality=0`, `r.EyeAdaptationQuality=0`, `r.DisableDistortion=1`, `r.Streaming.PoolSize=5000`, `r.MaxAnisotropy=16`, `r.SkeletalMeshLODBias=-1`, `r.MipMapLODBias=-0.5`.
- Game settings backups from before this session: `backups/graphics-20261024-095501/` (restore with `Set-AitDVRGraphics.ps1 -Mode Restore -BackupDirectory …`, which also restores Engine.ini).

Reproduce (game stopped, headset streaming in VD, keep-awake on):

```powershell
.\tools\Set-AitDUevrConfig.ps1 -Assignment 'VR_RenderingMethod=0','VR_NativeStereoFix=true','UObjectHook_EnabledAtStartup=true'
.\tools\Set-AitDVRGraphics.ps1 -Override @{ DLSSQualityLevel='1'; 'sg.ShadowQuality'='0'; 'sg.ViewDistanceQuality'='3'; 'sg.DetailQuality'='3'; 'sg.ShadingQuality'='2'; 'sg.FoliageQuality'='2' } -SystemSettings @{ 'r.ContactShadows'='0'; 'r.CapsuleShadows'='0'; 'r.BloomQuality'='1'; 'r.MotionBlurQuality'='0'; 'r.EyeAdaptationQuality'='0'; 'r.DisableDistortion'='1'; 'r.Streaming.PoolSize'='5000'; 'r.MaxAnisotropy'='16'; 'r.SkeletalMeshLODBias'='-1'; 'r.MipMapLODBias'='-0.5'; 'r.Tonemapper.Sharpen'='0.4'; 'r.StaticMeshLODDistanceScale'='0.35'; 'foliage.LODDistanceScale'='3'; 'r.Streaming.Boost'='2'; 'r.Streaming.FramesForFullUpdate'='2'; 'r.Streaming.HiddenPrimitiveScale'='1'; 'r.NGX.DLSS.Preset'='5'; 'r.NGX.DLSS.DilateMotionVectors'='0' }
# DLSS 4: copy NVIDIA's nvngx_dlss.dll 310.9.16 over AloneInTheDark\Plugins\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll (back up 3.1.1 first)
# launch AloneInTheDark-Win64-Shipping.exe -dx12, then:
.\tools\Invoke-AitDUevrInject.ps1          # auto-detects that uevr_mcp.dll is absent
# load the save (E in the main menu), then:
.\tools\Measure-AitDPerf.ps1 -NoBridge -Label check -Seconds 15
```

When calling the PowerShell tools from another `powershell -File` invocation, pass array/hashtable arguments through `-Command "& .\tools\… "` instead: `-File` joins arrays into one string.

### Remaining leads for clarity

GPU headroom is ~17% (~9.2 of 11.1 ms with DLSS 4 preset E). The open issues are the DLSS haze (see above; PureDark's UEVR fork is the remaining lead) and a game-side leaf shimmer. Other clarity levers:

- VD side (in the headset): codec AV1 10-bit (Quest 3 supports it), a higher bitrate, the Godlike preset.
- UEVR `OpenXR_ResolutionScale` 1.1–1.2 (applies on injection). It costs a large share of the remaining headroom.
- `r.Tonemapper.Sharpen` (cheap).

# 2026-10-23 session

Target: 72 FPS minimum, 90 preferred, on a Quest 3 at 90 Hz over Virtual Desktop. Hardware: RTX 4070 Ti, Ryzen 7 7800X3D.

## Measurement validity (read first)

No measurement in this session is a valid absolute VR FPS. The headset was disconnected throughout, and its battery died during the session: Virtual Desktop sent ~0 Mbit/s, the HMD pose was identity, ADB saw no device (so `local/quest-keep-awake.ps1` was running but had no effect), and `usingControllers=false`. In this state VD's OpenXR runtime paces the engine to 10–32 VR frames/s, the GPU sits at P3 (360–1300 MHz) and is ~35% busy, and the busiest CPU thread is ~10%. Earlier captures in `local/perf/` from 19:37–19:41 (all ~32 ticks/s) are invalid for the same reason.

`tools/Measure-AitDPerf.ps1` now records `valid=True` only when the HMD pose changes and the network is sending more than 5 Mbit/s, and it warns otherwise.

### What can still be compared

- **Game-side CPU** is valid. The CSV profiler (`csvprofile frames=N`, which works in this shipping build; output goes to `%LOCALAPPDATA%\AloneInTheDark\Saved\Profiling\CSV`) shows real game- and render-thread work of only a few ms. The rest is `EventWait` on the runtime. The CPU is far from the 11.1 ms budget, so the GPU is the limit.
- **Relative GPU work** is compared by `gpuWork` = process 3D-engine busy ms per VR frame × average graphics clock (GHz). The busy time comes from the Windows `GPU Engine … Running Time` counter, which needs no admin. Busy % alone is useless because the driver lowers the clock to keep the GPU ~35% busy. `gpuWork` scales as expected with DLSS level (monotonic), but it is only a proxy: memory-bound passes don't scale with core clock, and results differ by ±10–20% between runs in different clock regimes. Compare within a run only.
- PresentMon (`C:\Program Files\NVIDIA Corporation\FrameViewSDK\bin\PresentMon_x64.exe`) needs elevation, and `r.GPUStatsEnabled` / `r.GPUCsvStatsEnabled` are compiled out, so there is no per-pass GPU timing.

## Results (relative GPU work, Synchronized Sequential + DLSS 2 = 100)

Steps are applied live by `tools/Invoke-AitDPerfSweep.ps1`. "lowfx" means `r.ContactShadows 0`, `r.CapsuleShadows 0`, `r.BloomQuality 1`, `r.MotionBlurQuality 0` and `r.EyeAdaptationQuality 0`. "sh0" means `sg.ShadowQuality 0`.

The estimated FPS column assumes the user's in-headset report of ~45 FPS for Synchronized Sequential + DLSS 2 was GPU-bound (22.2 ms per VR frame). It is an estimate, not a measurement.

| Setting | Run A | Run B | Est. FPS |
|---|---|---|---|
| Synchronized Sequential, DLSS 2 (77%), stock fx | 100 | 100 | ~45 (user report) |
| Synchronized Sequential, DLSS 1 (live default) | 82 | – | ~55 |
| Native Stereo, DLSS 2 | 104 | – | ~43 |
| Native Stereo, DLSS 1 | 80 | – | ~56 |
| Native Stereo, DLSS 0 (58.8%) | 74 | – | ~61 |
| Native Stereo, DLSS 0, volumetric fog off | 72 | – | ~62 |
| Native Stereo, DLSS 0, lowfx | 69 | – | ~65 |
| Native Stereo, DLSS 0, lowfx + sh0 | 69 | 57 | 65–79 |
| Native Stereo, DLSS -1 (50%) | 63 | 52 | 71–87 |
| Native Stereo, DLSS -1, lowfx + sh0 | – | 51 | ~76–88 |
| Native Stereo, DLSS 2, lowfx + sh0 | 96 | – | ~47 |

Run A had clocks of ~360–570 MHz and Run B ~650–1320 MHz. Raw JSON is in ignored `local/perf/` (`sweep-*`).

### Conclusions

1. **Resolution dominates.** Going from DLSS 2 to DLSS -1 removes ~40–50% of GPU work. The effect toggles together are worth only ~5–10%.
2. **Native Stereo doesn't reduce GPU work** in this game (within ±5% of Synchronized Sequential). Its benefits are one engine tick per VR frame instead of two (half the game/render-thread cost), both eyes rendered from the same moment (no sequential-eye judder), and lower latency. It still needs a visual check for one-eye artifacts.
3. A large share of the cost scales with the **output** resolution (2688 × 2880 per eye): the DLSS upscale, post-processing after DLSS, and UEVR compositing. That is why DLSS 2 → -1 cuts the internal pixels by 58% but the work by only ~45%. `OpenXR_ResolutionScale` targets exactly this cost, but it only applies when UEVR creates the OpenXR session, i.e. on injection. It was **not** measured: restarting with the headset off fails with `XR_ERROR_FORM_FACTOR_UNAVAILABLE`, which leaves UEVR without VR, so the config was restored to 1.0.
4. Live UEVR mode switches work through the bridge: `POST /api/vr/settings {"key":"VR_RenderingMethod","value":"0"}`. Changing `OpenXR_ResolutionScale` live is accepted but has no effect until the next session.

## Staged candidates (not persisted)

Nothing below is written to `config.txt`, `GameUserSettings.ini` or `settings.sav`. The persistent state is unchanged: Synchronized Sequential, scale 1.0. Backups are in `backups/perf-20261023-203926/`.

- **C72 – 72 FPS target:** Native Stereo + DLSS -1 + lowfx + sh0. Apply live with `tools/Invoke-AitDPerfSweep.ps1 -Only ns-dlss-1-lowfx-sh0 -KeepLast`. Estimated 76–88 FPS.
- **C72-sharp – fallback if C72 is too soft:** `-Only ns-dlss0-lowfx-sh0 -KeepLast`. Estimated 65–79 FPS.
- **C90 – 90 FPS target:** C72 plus `OpenXR_ResolutionScale=0.85`, set with the game stopped via `tools/Set-AitDUevrConfig.ps1 -Assignment 'OpenXR_ResolutionScale=0.850000'`, then launch and inject. Untested.
- **Fallback if 90 isn't held:** set the Quest/VD refresh to 72 Hz rather than missing 90 Hz frames; consider VD SSW as a separate latency/artifact test.

Persist a candidate only after the headset checks below. Use `Set-AitDUevrConfig.ps1` for UEVR keys, and extend `Set-AitDVRGraphics.ps1` for game keys: DLSS level and shadow quality live in both `settings.sav` and `GameUserSettings.ini`. The lowfx CVars aren't menu settings, so they would need the profile Lua script or an Engine.ini `[SystemSettings]` block.

## Headset checklist (about 30 s each; Claude runs all the commands)

0. Charge the Quest and connect Virtual Desktop **before** the game starts; UEVR can't create an OpenXR system without a connected headset. Claude then launches `-dx12`, runs `tools/Invoke-AitDUevrInject.ps1`, and loads the save with bridge key `e`.
1. **Stick test:** `tools/Watch-AitDStickInput.ps1 -Seconds 30`. Push the left stick forward for ~5 s, release, then push the right stick sideways for ~5 s. Zero joystick values point to OpenXR/VD; non-zero values without movement point to the XInput/DPad-shifting side (see `local/diag-20261023-2010/FINDINGS.md`).
2. **Real baseline:** stand still facing the courtyard while Claude runs `Measure-AitDPerf.ps1` (current Synchronized Sequential + DLSS live value). It must report `valid=True`.
3. **Full sweep with valid numbers:** stand still for ~3 min while `Invoke-AitDPerfSweep.ps1` runs. No input needed.
4. **C72 visual check:** with C72 applied, close each eye in turn and look for shadows, lighting, fog, reflections or particles that differ between the eyes or flicker (Native Stereo artifacts). Turn your head left and right: any judder? Is the image sharp enough to read a document or note? If anything is wrong in one eye only, Claude will try `VR_NativeStereoFix=1` live.
5. **C72-sharp check** (only if C72 is too blurry): the same 30 s look.
6. **C90:** requires a relaunch at scale 0.85. Check sharpness and text again, and check that the hand/weapon alignment still looks right.
