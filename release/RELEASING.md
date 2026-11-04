# Releasing the mod

Player-facing files live here; `tools/Build-AitDRelease.ps1` turns them and `profile/` into the Discord package.

```powershell
git pull
.\tools\Build-AitDRelease.ps1                 # same version, rebuilt
.\tools\Build-AitDRelease.ps1 -Version 0.2.0  # bump release/VERSION, then commit it
```

Output (ignored `dist/`): `dist/AloneInTheDark-VR-v<version>.zip` containing

- `AloneInTheDark-Win64-Shipping.zip`: the UEVR profile. UEVRInjector's Import Config names the profile after the zip, so the name must stay the game exe's.
- `README.txt`: `release/README.md` with `{{VERSION}}`, `{{UEVR_TAG}}` and `{{UEVR_BUILD}}` filled in.
- `Engine-ini-additions.txt`: the recommended CVars from the approved performance baseline (`profile/VR_PERFORMANCE.md`).
- `Install.bat` / `Install.ps1`: copies the profile to `%APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping` (an existing one is moved to `-backup-<time>`) and writes the CVars into the game's `Engine.ini` between `; AitD VR` markers (backup first, rerun replaces the block, keys already in `[SystemSettings]` are replaced). `-SkipEngineIni`, `-Uninstall`. It never deletes anything.

Next to the zip: `AloneInTheDark-VR-v<version>-discord-post.txt`, the post text from `DISCORD_POST.md`.

## What goes in

Only the play files from `profile/`: `config.txt`, `cvars_data.txt`, `uobjecthook/*.json` (first-person camera, hidden body mesh) and the scripts `Restart-AitDVR.ps1` deploys (`alone_in_the_dark_vr.lua`, `aitd_vr*.lua`). A new play script must be named `aitd_vr_*.lua` to be packaged. `aitd_perf_log.lua` and `aitd_diag_height.lua` are dev-only. Plugins (`uevr_mcp.dll`), tune files under `data/`, logs, saves, OptiScaler and AFW files are never packaged.

The package is built from the last commit (`git archive HEAD`), so uncommitted edits and test files in the clone never ship; they are listed as a warning. `-WorkingTree` packages the working copy instead, for test builds only.

The script fails if `config.txt` is not the play setup (OpenXR, menu closed, UObjectHook at startup, Native Stereo, controllers on) or if a packaged file mentions local paths, the debug bridge, test hooks, OptiScaler or AFW. It also compares the live profile in `%APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping` with the package: settings changed in the UEVR menu land only there, so a `config.txt`/`uobjecthook` difference stops the build (copy wanted changes into `profile/` and commit, or pass `-IgnoreLiveDiff`). Script differences are only reported.

## Checklist

1. Change log entry in `CHANGELOG.md`, version bump.
2. Update `README.md` here, and the repository's root `README.md` (the public player page), if controls, options or settings changed. No story spoilers: name places and mechanics only as far as the first chapter shows them.
3. Commit, build, and test the zip once with Import Config on a clean profile folder.
4. Post `dist/AloneInTheDark-VR-v<version>.zip` with the text from `DISCORD_POST.md`.
5. Sync the public repo (`tools/Export-AitDPublic.ps1`), push it, and publish a GitHub release tagged `v<version>` there with the zip attached and the `CHANGELOG.md` entry as notes.

Changing the required UEVR build: pass `-UevrTag nightly-NNNNN-<hash>` (and update its default in the script) after testing the new build.
