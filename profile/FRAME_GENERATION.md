# Frame-generation investigation

The user has successfully used frame generation in other modded VR games and explicitly authorizes experimenting with downloaded or borrowed DLLs. Every experiment here is installed through a manifest-backed script and can be rolled back without Steam verification.

## Stock OptiScaler v0.9.4 result

The official OptiScaler v0.9.4 path was installed and tested in DX12 with UEVR/OpenXR. OptiFG accepted AoTD's DLSS upscaler input, created its D3D12 context, and logged successful generated-frame dispatches. It is unusable in this stereo path:

- The desktop mirror and headset alternated between the two eye images.
- Closing either eye stopped the left/right alternation, but the remaining eye still flickered.
- The End hotkey did not reliably destroy the active frame-generation context after it had started.
- A full game restart with `[FrameGen] Enabled=false` was the reliable rollback.

After restart, the log contained `FSRFG_Dx12::Dispatch No fg context` and no `numGeneratedFrames` callbacks. The user confirmed the flicker was gone. This establishes stock OptiFG as rejected for AoTD+UEVR, while leaving OptiScaler available for DLSS interception and logging.

## Verified local state

- GPU: NVIDIA GeForce RTX 4070 Ti, 12,282 MiB reported by `nvidia-smi`.
- NVIDIA driver: 621.01.
- AoTD ships exactly one NGX runtime: `AloneInTheDark/Plugins/DLSS/Binaries/ThirdParty/Win64/nvngx_dlss.dll`.
- Shipped DLL version: 3.1.1.0, size 36,687,416 bytes.
- SHA-256: `84E161DF5D6173F7110BD1C1146C2DA933703215197CF59C7C3BD60488F50A65`.
- Authenticode signature: valid.
- No `nvngx_dlssg.dll`, Streamline DLL, or other frame-generation runtime was found in the game tree.
- The running engine registers DLSS Super Resolution CVars, including `r.NGX.DLSS.Enable=1` and `r.NGX.DLSS.Quality=-2`, but registers no CVar containing `FrameGeneration` or `Streamline`.

Copying a newer `nvngx_dlss.dll` can update Super Resolution but cannot by itself add frame generation. Copying `nvngx_dlssg.dll` from another game is also insufficient because AoTD lacks the native Streamline/DLSS-FG integration that calls it.

## Candidate order

### 1. NVIDIA Smooth Motion

NVIDIA officially supports driver-level Smooth Motion on RTX 40-series GPUs for DirectX 11/12 games that lack native frame generation. It works independently of native DLSS FG and can run alongside DLSS Super Resolution. This is the cleanest first experiment because it does not replace game DLLs.

Source: https://www.nvidia.com/en-us/geforce/news/nvidia-app-global-dlss-overrides-rtx-40-series-smooth-motion/

The NVIDIA App was not found by the quick AppX/process query, but that does not prove it is absent as a conventional Win32 install. Locate it before downloading. If absent, use NVIDIA's official installer only. Enable Smooth Motion for `AloneInTheDark-Win64-Shipping.exe`, restart the game, inject UEVR, and verify the result inside the headset. A driver present hook may affect only the desktop mirror rather than the OpenXR eye swapchains; headset observation and frame-time data decide whether it works.

### 2. OptiScaler OptiFG

OptiScaler is the strongest DLL-level candidate because AoTD already supplies DLSS2 inputs and OptiFG can add experimental FSR3 frame generation to DX12 games without native FG. Its documentation explicitly distinguishes this from `dlssg-to-fsr3`, which requires a game that already has native DLSS-FG.

Primary sources:

- https://github.com/optiscaler/OptiScaler
- https://github.com/optiscaler/OptiScaler/blob/master/Features.md

Before installation, confirm the running game is using DX12. Download a tagged release only from the official repository, record the release URL and hashes, scan/extract it under ignored `local/tools/`, and back up every destination file it would replace. Follow the project's current installation instructions rather than guessing a proxy DLL name. Configure OptiFG with FSR3 FG and its HUD fix. Change OptiScaler's overlay hotkey away from Insert because UEVR already uses Insert. Expect possible conflicts because both OptiScaler and UEVR hook the graphics pipeline; test clean launch, injection, stereo correctness, controller latency, UI ghosting, and crash-free save/load.

### 3. Other wrappers

- Nukem's `dlssg-to-fsr3` is not a standalone match because its documented path requires native DLSS-FG input, which AoTD lacks.
- DLSS Enabler may integrate with OptiScaler, but should only be considered if the current OptiScaler documentation requires it for the chosen FG output.
- A borrowed DLSS SR DLL is a separate image-quality experiment and must not be described as enabling FG.

## Reversible test protocol

1. Exit the game and injector before replacing any DLL.
2. Create a timestamped backup containing the original DLLs plus SHA-256 manifest. Never overwrite the sole backup.
3. Keep one experiment per launch: baseline, Smooth Motion, then OptiFG. Do not combine them. NVIDIA warns against using native FG and Smooth Motion together.
4. Use the same save and scene. Record native FPS/GPU frame time, generated/display FPS where available, headset refresh, and whether Virtual Desktop Spacewarp is enabled.
5. In-headset checks: stereo consistency during head rotation, weapon-controller latency, hand-edge ghosting, transparent effects, menus/subtitles, cutscenes, and impacts while aiming away from the head direction.
6. Reject an option if it accelerates only the desktop mirror, breaks stereo, causes unstable pacing, or adds unacceptable controller latency even when its FPS counter rises.
7. Rollback must remove added proxy/config files and restore originals by hash. Run Steam verification only after preserving the mod/profile work outside the game directory.

## Next commands/actions

At the start of the next session:

1. Recheck the five-hour budget.
2. Determine DX12 from loaded modules or the UEVR log.
3. Locate the NVIDIA App and inspect whether Smooth Motion already appears for the shipping executable.
4. Back up the game binary/plugin directories and write a SHA-256 manifest.
5. Test Smooth Motion first. If it does not affect the headset, download and stage the latest tagged OptiScaler release from its official GitHub repository, inspect its current installation guide, and prepare a one-command install/rollback script before changing the game directory.

## Staged release update

The user chose OptiScaler. Official release v0.9.4 was downloaded to ignored `local/tools/` and its archive SHA-256 matched GitHub's published digest: `575cb4df866116093df75af607e37fd70e10f5163e0f23fd5c804142e80ef0ad`. The core `OptiScaler.dll` has a valid Authenticode signature. It is installed with a manifest and rollback backup; the stock FG result is recorded above.

The running process has DX12 modules loaded, satisfying OptiFG's API requirement. Current official OptiFG guidance confirms that a non-native-FG game should use `FGInput=upscaler`, select an FG output, enable the FG toggle, and use HUDFix. For this first experiment the prepared installer selects the existing DLSS upscaler, FSR frame generation, HUDFix with the Unreal-recommended limit 1, and keeps overlay blocking disabled so UEVR/XInput controller handling is not accidentally suppressed. The OptiScaler menu moves from Insert to Home because Insert belongs to UEVR. Frame generation starts disabled for the first compatibility boot; toggle it with End only after both OptiScaler and UEVR are confirmed loaded.

Use `tools/Set-AitDOptiScaler.ps1 -Mode Install` only after closing the game. It records every installed file and hash in ignored local state and backs up collisions. `-Mode Remove` removes only manifest-listed paths after validating that each resolves inside the game binary directory, then restores any prior files. Start with `-Mode Status`.

## Stereo-aware OFXR candidate

The next experiment uses `tig3rmast3r/OptiScaler_DLSSNR_VR`, whose VR branch keeps separate eye histories and publishes DLSS depth/motion guides to an OpenXR-aware frame generator. The author built it for Witcher 3 VR and labels wider game/runtime support experimental, so AoTD compatibility is unverified.

Prepared source and payload:

- Source branch `witcher3vr-stereo`, commit `0b4abc0808ac49679e73674d6d0ecc59303e0242` (V23244).
- Binary package: Witcher 3 VR v0.9.8v2.
- Package SHA-256: `A59F96F43DB9C9509D0EE07638A7F5D1EDD280010A836105B6E93F820B31BD5A`, matching the release manifest.
- Custom OptiScaler SHA-256: `D244828FC9742801B2184C04847097EB1D2BB6656F084BED0EC8DA86E7AADEAA`.
- OFXR layer SHA-256: `CE27A143568038A38778A9297582B70132FFE27D800E405A5F037E10ADDFBE9B`.
- The custom OptiScaler and OFXR layer are unsigned builds from the cited source/package. The FidelityFX helper is signed.

`tools/Set-AitDStereoOptiScaler.ps1` swaps only the required runtime files, records hashes and pre-existing files, and restores the stock OptiScaler installation on removal. `tools/Start-AitDVRDevelopment.ps1` requests the staged OpenXR layer only while the stereo experiment state file exists. The candidate uses OFXR `frame_generation=fsr3`; OptiScaler's ordinary `[FrameGen]` path remains disabled so the rejected swapchain generator cannot run at the same time.

Primary sources:

- https://github.com/tig3rmast3r/OptiScaler_DLSSNR_VR
- https://github.com/tig3rmast3r/witcher3-vr/releases/tag/v0.9.8v2
