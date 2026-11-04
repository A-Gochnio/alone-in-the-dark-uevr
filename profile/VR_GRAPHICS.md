# VR graphics tuning notes

Captured 2026-10-23 before changing graphics settings. These are verified local observations unless marked as a proposed next step.

## Hardware and runtime

- GPU: NVIDIA GeForce RTX 4070 Ti. WMI misreported dedicated memory because its `AdapterRAM` field overflowed; query `nvidia-smi` or DXGI next session instead of recording that value.
- CPU: AMD Ryzen 7 7800X3D.
- RAM: approximately 64 GB.
- Runtime: Virtual Desktop OpenXR, UEVR render resolution 2688 x 2880 per eye.
- Saved game cap: 90 FPS; VSync and dynamic resolution are disabled.

## Current game settings

`GameUserSettings.ini` still reports `GraphicsMode=Performance`. Textures and anisotropic filtering are now level 3; the remaining custom scalability categories stay at 0 or 1. Motion blur, depth of field, chromatic aberration, and the extra post effect are saved as disabled. The pre-change files are preserved under ignored `backups/graphics-20261023-184509/`.

Upscaling state observed live:

- `r.NGX.DLSS.Enable=1`
- `r.NGX.DLSS.Quality=-2`, matching `DLSSQualityLevel=-2` in the saved settings
- `r.FidelityFX.FSR2.Enabled=0`
- `r.ScreenPercentage=100`
- `DLAAEnabled=False`

Live A/B testing mapped the useful DLSS values at the 2688 x 2880 UEVR output:

- `-2`: 896 x 960 internal, 33.3% per dimension.
- `-1`: 1344 x 1440 internal, 50%.
- `0`: 1581 x 1694 internal, about 58.8%.
- `2`: 2068 x 2215 internal, about 77%.
- `3`: fell back to 1581 x 1694 in this build.

The current live process uses `r.NGX.DLSS.Quality=2`, high textures, 16x anisotropy, and the VR post-effect disables. In the Derceto courtyard the user reports a stable image without flicker at about 45 application FPS. The saved `settings.sav` and `GameUserSettings.ini` still contained `DLSSQualityLevel=-2` after restart, proving that editing only `GameUserSettings.ini` is insufficient. `tools/Set-AitDVRGraphics.ps1` now updates both files while the game is stopped; the startup script applies that candidate before launch.

VR-unfriendly effects observed live:

- `vr.AllowMotionBlurInVR=0` and `r.DefaultFeature.MotionBlur=0`, but the dormant quality CVar remains `r.MotionBlurQuality=3` despite the menu value being Off.
- `r.DepthOfFieldQuality=0`.
- `r.SceneColorFringeQuality=0`.

The next profile should explicitly hold motion blur at zero so a game state or post-process volume cannot re-enable it. Depth of field and chromatic aberration are already correctly disabled.

## Frame generation finding

The loaded game exposes the DLSS Super Resolution plugin but no Streamline or frame-generation CVars: searches for `FrameGeneration` and `Streamline` returned zero results, and `r.Streamline.DLSSG.Enable` does not exist. Native DLSS Frame Generation therefore cannot be enabled in this build through the loaded plugin.

UEVR's own published setup notes recommend disabling DLSS Frame Generation before injection. Do not force an undocumented DLL/config hack into the stereo render path. If native frame rate is insufficient, inspect Virtual Desktop's Spacewarp/SSW option as a separate reprojection test, with artifact and latency validation in the headset.

Sources:

- UEVR setup notes: https://github.com/praydog/UEVR
- UEVR nightly setup notes: https://github.com/praydog/UEVR-nightly/releases

## Tuning sequence

The first candidate is applied live and prepared for persistent installation. It still needs representative gameplay testing beyond the courtyard.

1. Establish a repeatable scene and collect native frame time/FPS with the current Performance preset. Use `stat unit`/`stat fps`, a frame-time capture tool, or Virtual Desktop's performance overlay. Record GPU and CPU frame times separately if possible.
2. Enforce the VR comfort baseline: motion blur 0, depth of field 0, chromatic aberration 0, film grain 0, and lens flare 0. Preserve bloom unless it causes stereo artifacts. Keep VSync and dynamic resolution off.
3. Determine what the game's DLSS numeric levels mean by changing one menu value at a time and reading `r.NGX.DLSS.Quality`. Start visual/performance comparison at DLSS Quality and Balanced. Avoid FSR2 on the RTX card unless DLSS has a game-specific stereo defect.
4. Raise texture quality and anisotropic filtering first; these usually improve clarity with modest frame-time cost on this GPU. Then raise view distance and model/detail quality. Increase shadows, volumetrics, reflections, foliage, particles, and ambient occlusion individually while recording frame time.
5. Target native headset refresh when practical. If the 90 Hz budget cannot be held in representative combat and outdoor scenes, compare a lower headset refresh against a locked half-rate Virtual Desktop Spacewarp mode. Judge controller latency and ghosting in the headset before keeping reprojection.
6. Save the chosen values under `profile/`, install them into the active configuration, document the measured scene/result, and commit. Do not call a profile “smooth” based only on desktop rendering or menu FPS.

Likely first quality candidate for measurement, not yet validated: high textures and anisotropic filtering; medium view distance, effects, shadows, and ambient occlusion; low volumetrics, foliage, particles, and screen-space reflections; DLSS Quality or Balanced; all VR-unfriendly post effects disabled.
