# Reproducible UEVR profile files

Copy these files into:

`%APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping\`

## Current baseline

`config.txt` is the working OpenXR baseline captured on 2026-10-23. The settings directly verified in the running game are:

- OpenXR (`Frontend_RequestedRuntime=openxr_loader.dll`) through Virtual Desktop.
- Motion controllers allowed and right-controller aiming (`VR_ControllersAllowed=true`, `VR_AimMethod=2`).
- Roomscale movement enabled.
- UEVR's menu configured closed with no remembered menu state. The menu still appeared immediately after injection in one run; press Insert to close it before diagnosing controller tracking.
- Custom near plane enabled at `79.695999`, inherited from the working profile. Visual comfort and clipping still need headset validation.

2026-10-24 performance profile (90 FPS verified in the headset, see `VR_PERFORMANCE.md`): `VR_RenderingMethod=0` (Native Stereo), `VR_NativeStereoFix=true`, and `UObjectHook_EnabledAtStartup=true`. The last one is required for first person: `uobjecthook/camera_state.json` only applies when UObjectHook is active, and without the uevr-mcp plugin nothing else activates it. Keep `plugins/uevr_mcp.dll` out of the profile for play and benchmarks, because it caps the game at ~42 FPS.

Other values are preserved from the user's working profile and should be changed only after an A/B test. The game/profile/saves were backed up before experimentation.

## Scripts

`scripts/aitd_perf_log.lua` is a measurement aid, installed only for benchmark sessions. It writes engine tick timings every 2 s to `data/aitd_perf.csv` (read by `tools/Measure-AitDPerf.ps1 -NoBridge`) and, 30 s after injection, the live renderer CVars to `data/aitd_cvars.txt`. It also applies `name=value` lines written to `data/aitd_cvar_set.txt` (within 2 s, and again after each level load), which gives live CVar control without the bridge.

`scripts/aitd_vr_ui.lua` hides the crosshair (it follows the head, not the barrel) and keeps the UI panel head-following in gameplay but fixed in the room for menus, documents and loading. See `VR_UI.md`.

`scripts/alone_in_the_dark_vr.lua` swaps the XInput LT and RB signals that UEVR sends to the game. With the stock game mapping this produces:

- right grip: aim
- right trigger: fire
- left trigger: melee

The same script discovers the active revolver and attaches its root to the right controller. The saved `Right90Pre` rotation and position were visually verified in-headset on Quest 3: the revolver is visible while aiming and its barrel points straight along the controller.

The input mapping loaded successfully after a restart and the user verified right-grip aim and right-trigger fire. The persistent attachment addition is installed for the next injection; the current process already has the identical attachment applied live. `../tools/Set-RevolverAttachment.ps1` remains a diagnostic and rollback tool.

The user reports that fired shots now land approximately along the barrel. A sequential snapshot taken while not aiming and after ammunition reached zero is not a valid shot-direction measurement. Do not add a trace override on that evidence. Reload or load a save, capture while actively aiming, and compare visible impact marks at several distances before deciding whether the Blueprint `GetTraceParameters` hook is necessary.

## Development launcher

Run `tools/Start-AitDVRDevelopment.ps1` from PowerShell to start the Quest keep-awake loop, launch Steam app 1310410 when needed, wait for the shipping process, and open the pinned UEVR nightly injector. It is safe to rerun: it detects an already-running game, injector, and injected bridge. Then inject with `tools/Invoke-AitDUevrInject.ps1` (headless, no frontend clicks), or by hand in the UEVR frontend: select the shipping process, select OpenXR, click Inject.
