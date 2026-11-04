# Alone in the Dark VR

Play the Steam version of **Alone in the Dark (2024)** as a first-person VR game with motion controls. This is a profile for [UEVR](https://github.com/praydog/UEVR), praydog's VR injector for Unreal Engine games. It does not modify any game files.

> **Beta.** Only the start of the game has been played in VR so far, with both Edward and Emily. It hasn't been played through to the end yet, so later scenes may still need fixes. Please [report what you find](#reporting-problems).

## What you get

- **6DOF first person** at your real eye height. Crouching lowers your view.
- **Guns in your hand that shoot where the barrel points**, with a red laser aim dot. You can turn this off to shoot where you look instead.
- **Two-handed shotgun and Tommy gun:** hold the left grip near the barrel. You'll feel a buzz when it latches.
- **A VR control layout** built for the Quest controllers (see [Controls](#controls)).
- **Comfortable UI:** menus are fixed in the room, the HUD is smaller and follows your head, and there's no head-locked crosshair.
- **Puzzles just work:** close-up puzzles switch to the plain controller layout automatically, and the telescope is shown on a flat virtual screen so its lens effects don't flicker in 3D.
- **Safe saves:** deleting saves is disabled, so a stray button press can't wipe one.
- **Tuned graphics:** Engine.ini tweaks that reduce pop-in and DLSS shimmer, plus recommended settings for a steady 90 FPS.

Tested on a Meta Quest 3 over Virtual Desktop (VDXR / OpenXR) with an RTX 4070 Ti. Other OpenXR headsets should work, but nobody has tested them yet.

## Requirements

- **Alone in the Dark (2024), Steam version.**
- **UEVR nightly 01143.** Download `uevr.zip` from [UEVR-nightly release nightly-01143](https://github.com/praydog/UEVR-nightly/releases/tag/nightly-01143-4ee5c6b6162dee2291fc75f9dfc57667f6d45a2d) and extract it anywhere. Other UEVR builds are untested, and some forks break this game (one eye goes black).
- **An OpenXR runtime.** With Virtual Desktop, set the OpenXR runtime to **VDXR** in its settings.

## Install

1. Quit the game.
2. Download `AloneInTheDark-VR-v<version>.zip` from the [latest release](../../releases/latest) and extract the whole zip into any folder.
3. Double-click **`Install.bat`**. It does two things:
   - It installs the UEVR profile to `%APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping`. If you already have a profile for this game, it's moved to a `-backup-<date>` folder first so old scripts can't interfere.
   - It adds the recommended settings to the game's `Engine.ini`, after backing the file up.

   To install only the profile, run `Install.bat -SkipEngineIni`. Nothing is ever deleted.
4. Set the in-game graphics options from [Recommended graphics](#recommended-graphics).

### Manual install (instead of Install.bat)

1. Back up or delete `%APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping` if it exists.
2. Open `UEVRInjector.exe`, click **Import Config** and pick `AloneInTheDark-Win64-Shipping.zip` from the release. Don't rename the file, because UEVR uses its name to find the game.
3. Optional but recommended: add the lines from `Engine-ini-additions.txt` to `%LOCALAPPDATA%\AloneInTheDark\Saved\Config\WindowsNoEditor\Engine.ini`.

## Play

1. Connect your headset (for example, start Virtual Desktop and connect to the PC).
2. Start the game from Steam.
3. In `UEVRInjector.exe`, select **AloneInTheDark-Win64-Shipping.exe**, choose **OpenXR** and click **Inject**. You can do this in the main menu or after loading a save.
4. If the UEVR menu is open after injecting, close it with **Insert** on the keyboard or by holding both thumbsticks down. While it's open, the controllers don't reach the game.

## Controls

| Input | Action |
| --- | --- |
| Right grip | Aim |
| Right trigger | Fire |
| Left trigger | Melee |
| Left grip while aiming | Hold near the barrel to two-hand a long gun |
| Left grip + right stick flick | Weapons and items (D-pad: right, down, left, up) |
| X tap / X hold | Reload / stealth (crouch) |
| Y tap / Y hold | Inventory / pause menu |
| Hold both sticks | UEVR menu (a quick click of both does nothing) |

All other buttons and sticks keep the game's own controller layout.

- **Menus:** the grips switch tabs. Holding the left grip and pushing the right stick up or down changes the map floor.
- **Documents:** the right grip turns pages. Hold X to view the page itself.
- **Close-up puzzles:** the plain controller layout applies (grips rotate, sticks move, A selects).

### Options

In the UEVR menu, go to **Lua Loader > Script UI > Alone in the Dark VR**:

- **Laser aim dot** (on by default).
- **Shoot from the barrel** (on by default). Turn it off to shoot where you look, like the flat game.
- **Show belt items** (off by default). The chest flashlight and holstered gun don't turn with you, so they're hidden. The flashlight still lights the way.

## Recommended graphics

These in-game settings gave a steady 90 FPS on an RTX 4070 Ti at the Quest 3's full resolution:

| Setting | Value |
| --- | --- |
| Upscaler | DLSS Quality |
| Shadows | Low (shadows render per eye and cost the most) |
| View distance, Detail | Epic |
| Shading, Foliage | High |
| Textures | Epic |
| Anisotropic filtering | 16x |
| Motion blur, depth of field, chromatic aberration | Off |
| Camera shake | 0% (for comfort) |

- **Less than 12 GB of VRAM?** Lower `r.Streaming.PoolSize` in `Engine-ini-additions.txt` (for example to 3000) before you run `Install.bat`, or run it again after the change.
- **DLSS 4 (optional, recommended):** the game ships DLSS 3.1.1. Swapping in DLSS 310.x (for example with DLSS Swapper) gives a sharper image. The Engine.ini lines select the lighter CNN preset E, which holds 90 FPS. The default transformer model costs about 15 FPS more.
- **Virtual Desktop:** 90 FPS, SSW off. Keep **Boost game priority** off, because it froze the PC in testing.
- **Frame generation and UEVR's AFW mode aren't recommended:** they ghost when you turn your head.

## Known issues

- The game hasn't been played through to the end in VR yet. Puzzles were checked with simulated controller input, not all of them in the headset.
- Changing the map floor is untested, because the map unlocks later in the game.
- There's a slight heat haze around moving objects with DLSS in VR. TAA doesn't have it but looks much softer. The Engine.ini lines reduce it.
- A room-fixed menu stays where it opened, so open menus while looking roughly straight ahead.
- If Virtual Desktop disconnects mid-game, VR stops working until you restart the game.
- If both thumbsticks stop responding (also in the Virtual Desktop overlay), restart the headset.
- UEVR drops idle controllers after 30 seconds. Move them to wake them up.
- Some leaf flicker in the distance comes from the game itself. It's in flat mode too.

## Uninstall

Run `Install.bat -Uninstall` from a command prompt in the extracted folder. Or delete `%APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping` and remove the lines between `; AitD VR begin` and `; AitD VR end` from `Engine.ini`.

## Reporting problems

[Open an issue](../../issues/new) with:

- your headset and how it's connected (for example, Quest 3 + Virtual Desktop),
- your GPU and the mod version,
- Edward or Emily,
- what you did and what happened.

Please describe where you were without story spoilers, for example "a puzzle in the first house". A screenshot of the desktop window helps. If the game crashed, say whether it happened while loading, in a menu or in play.

## For modders

| Path | What it is |
| --- | --- |
| `profile/` | The UEVR profile: `config.txt`, CVars, UObjectHook camera and mesh settings, and the Lua scripts (`scripts/alone_in_the_dark_vr.lua` plus `aitd_vr_*.lua`). Design notes on graphics, performance, UI and frame generation live here too. |
| `release/` | Files that go into the release zip: the player README, changelog, installer and Engine.ini additions. |
| `tools/` | PowerShell dev tools for Windows: build the release zip, inject headlessly, restart into a save, measure performance and simulate Quest input. See [tools/README.md](tools/README.md). |

To build the release zip on Windows, run `.\tools\Build-AitDRelease.ps1` from the repository root. The zip lands in the ignored `dist/` folder; see [release/RELEASING.md](release/RELEASING.md).

The tools find the game through Steam automatically. To override the game folder, or to have the tools move the game window to a particular monitor, create the ignored `local/machine.psd1`:

```powershell
@{
    GameDir        = 'D:\Games\Steam\steamapps\common\AloneInTheDark'
    WindowPosition = @(0, 0)                  # top-left corner, in desktop coordinates
    PrivateWords   = @('myname', 'MY-PC')     # extra words the public export must not contain
}
```

Some debugging tools talk to the [uevr-mcp](https://github.com/elliotttate/uevr-mcp) bridge plugin on `127.0.0.1:8899`. Keep that plugin out of the profile for normal play, because its per-frame hooks cost a lot of FPS.

## Credits

- Made by Arek ([A-Gochnio](https://github.com/A-Gochnio)).
- [UEVR](https://github.com/praydog/UEVR) by praydog.
- Some UObjectHook settings (the hidden third-person body mesh) come from an earlier community UEVR profile for this game from 2024.

Alone in the Dark is a trademark of its respective owners. This is an unofficial fan project. It needs a legal copy of the game and includes no game files.

## License

[MIT](LICENSE)
