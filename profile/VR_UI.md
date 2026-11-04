# VR UI, controls and aiming pass (2026-10-25)

Baseline: stable profile from `VR_PERFORMANCE.md` (Native Stereo + fix, DLSS 4 Quality preset E, pop-in fixes, VD at 90). Everything below was tested by Arek in the headset unless marked otherwise. Final measurement: 88.2 FPS, GPU 8.1–9.1 ms per VR frame, same as before the pass.

## What the game shows

- Menus are full-screen 2D screens: pause, options, the investigation menu (map, objectives, documents, collectibles), document reading, archive. Tab headers sit along the top edge; button prompts in the bottom-left corner.
- Gameplay HUD (`WBP_HudCombat`): health bar, weapon panel bottom-right (`WBP_InGame_Equipment`, with a `T_corner_gradient` vignette image `background_corner`), item/d-pad circle bottom-left (`WBP_InGame_QuickSlot`), crosshair while aiming (`WBP_Crosshair`), subtitles, objective text, tutorial pop-ups. No HUD scale or safe-zone option exists.
- Arek plays with hints "Old school" and environment interaction points off, so the screen-projected interaction icons (`WBP_InteractionHUD`) mostly do not appear.
- The game's UI state is `GameSubsystem_PlayState.GetMainState()` (`EGameMainState`): 0 gameplay, 3 investigation menu, 4 pause menu/options, 6 loading, 7 main menu.
- Key bindings live in `IMC_Default`; gamepad: inventory = View/Back (`Gamepad_Special_Left`), pause = Menu/Start, tabs = LB/RB, weapons = DPad (right revolver, down shotgun, left tommy gun, up health item), stealth = Y.

## In place

Game options: camera shake 0%, subtitles Large.

`uobjecthook/camera_state.json` (copy in `profile/uobjecthook/camera_state.json`): camera base 72 cm above the capsule centre (168 cm above the floor) instead of 50 cm below it. The old value put the view about 45 cm above the floor, because UEVR's standing origin is the first headset pose, not the floor.

`scripts/alone_in_the_dark_vr.lua`:
- Standing origin re-captured from the headset pose whenever a new pawn spawns (save load, chapter change) and once on first controller use in a session. Arek: height OK, no more 20 cm drop.
- Right grip = aim, right trigger = fire, left trigger = melee (LT/RB swap), except in the investigation and pause menus (states 3, 4), where the grips stay LB/RB so they switch tabs.
- Y tap = inventory (View), Y hold = pause (Start), X tap = reload (sent on release), X hold = stealth (Y). Verified: Y and Y-hold.
- Weapons stay on the DPad through UEVR's virtual d-pad (`VR_DPadShiftingMethod=5`: right controller near the head, then right stick). The gesture rumble works; switching was untestable because Edward had no other weapon or item yet.
- Revolver attachment with a pitch/yaw trim on top of the verified `Right90Pre` rotation: pitch 6.02°, yaw 0.18°. Tunable live through `data/aitd_aim_tune.txt`.

`scripts/aitd_vr_reticle.lua`: while aiming a hitscan weapon, a small unlit red dot (engine sphere + `GizmoMaterial`) sits where the weapon's own trace (`GetTraceStart` → `GetTraceEnd`, line-traced against the level) hits. Arek: shots land exactly on the dot.

`scripts/aitd_vr_ui.lua`:
- Keeps `WBP_Crosshair` and the weapon panel's `background_corner` gradient hidden. Arek: no head-locked crosshair.
- Gameplay UI panel: follows the head, 2.5 m, size 1.6 (about 36° wide), so the corner HUD items are visible. Arek: "way better".
- Menu UI panel (states 3, 4, 6, 7 and no pawn): room-fixed, 3 m, size 2.0 (about 37° wide). Arek: readable and stable.
- Writes `data/aitd_ui_state.txt` and shares the state with the motion script as the global `AITD_MAIN_STATE`.

## Findings worth keeping

- Shots follow the right controller's OpenXR aim pose exactly (trace pitch = aim-pose pitch in 29 samples). The game camera rotation equals it while aiming. The visible revolver is a separate attachment, so its barrel needed its own calibration.
- The revolver's barrel is the skeletal mesh's +Y axis (its Arrow component agrees; the muzzle-flash component is ~6° off). `tools/Invoke-AitDBarrelCalibration.ps1` measures the shot ray against it while the player aims, probes the live trims and solves for them: 9.9° error → 0.18° in three iterations. Rerun it for other weapons or after changing the attachment.
- UEVR freezes a room-fixed UI panel (`UI_FollowView=false`) at the head pose of the moment it is switched, so a menu opened while looking up or down is tilted. The HMD rotation that UEVR's API returns to scripts (and the bridge) stays at identity, so the script cannot wait for a level head; it pins immediately. Open menus while looking roughly ahead.
- Writing a widget's `Visibility` field through the bridge does not repaint it; call `SetVisibility`.
- PowerShell on this PC formats numbers with a decimal comma (Polish locale); use the invariant culture when writing values for Lua.

## Tools added

`tools/Get-AitDWindowShot.ps1` (posts keys, captures the game window with the UI), `tools/Watch-AitDAim.ps1` and `tools/Watch-AitDBarrel.ps1` (bridge samplers), `tools/Invoke-AitDBarrelCalibration.ps1` (live barrel calibration; needs the bridge, so about 40 FPS while it runs).

## Weapons and two-handing (2026-10-25/26, Arek-verified)

`scripts/aitd_vr_weapons.lua` attaches every hitscan weapon to the right hand with the revolver's muzzle frame.
- Two-handing: while aiming, press the left grip with the left hand in front of the right near the barrel line (buzz); the barrel then runs from the right hand through the left on both axes until the grip is released. The left grip is hidden from the game while aiming.
- Right-hand grip shift toward the muzzle: shotgun 5 cm, `TommyGun` 10 cm (the class name is spelled so). Live tuning: `data/aitd_grip_tune.txt`, lines `Shotgun=5`.
- During automatic fire the game re-aims the `MuzzleFlash` Niagara component toward a lagging direction (drifted ~20° in a sweeping burst); a post-engine-tick hook pins it back to the cached barrel frame. Arek: a slight tilt per shot remains, acceptable.
- UEVR motion-controller offsets are not in UE axes (UObjectHook.cpp): the Lua `Vector4f` is read as a (w, x, y, z) quaternion in VR axes (x right, y up, z back), the world rotation is hand * inverse(offset), and the location offset is in the component's frame, also in VR axes; measured, adding the barrel direction moves the gun back. Helpers `world_of`/`offset_of` in the script convert. A tracker with `Vector4f(1,0,0,0)` has an identity offset, so its world rotation is the controller's.
- If both thumbsticks read zero (also in the VD overlay), restart the Quest; restarting VD does not help.

## Puzzles and map floors (2026-10-26, from the walkthrough-video audit, not yet tried in the headset)

- `EGameMainState` names, in order, from the shipping exe: 0 ThirdPerson, 1 Cinematic, 2 Sequence, 3 InGameMenu, 4 PauseMenu, 5 Puzzle, 6 LoadingScreen, 7 MainMenu, 8 PhotoMode.
- Every close-up puzzle rotates or dials with LB/RB, moves with the left stick or D-pad and selects with A; the telescope zooms and focuses with the right stick; the fuse box resets with L3. `alone_in_the_dark_vr.lua` now leaves the controllers completely untouched (grips = LB/RB, triggers = LT/RT, X/Y and sticks raw) in every state except 0, 3 and 4, and also in state 0 when the player controller's view target is not the pawn (`AITD_PUZZLE_VIEW`, checked every 0.1 s in the pre-engine tick). Before, "rotate right" sat on the left trigger and the right grip sent LT.
- Every change of view-target class or of the puzzle flag is appended to `data/aitd_view_log.txt` (last 100 lines). Live check 2026-10-26 without the headset: main menu target `BP_OFPLayerController_C` (no pawn, puzzle=false); after loading the save `BP_Edward_C`, puzzle=false, state 0. The first real puzzle should log state=5 or puzzle=true.
- Investigation and pause menus (states 3, 4): the left grip is now a tap (LB sent on release), so it still switches tabs; held with a right-stick flick it sends the D-pad direction (one pulse per flick, re-armed at centre) and the stick is zeroed. This gives the map's "Change Floor" (D-pad up/down). The right grip stays RB.
- Document reader "View" (Y/△, turn the page over) is reached by holding X (X hold = Y).
- `config.txt`: `FrameworkConfig_L3R3LongPress=true` (toggle still enabled), so clicking both sticks at once (sprint L3 + flashlight R3 while fleeing) no longer opens the UEVR overlay; hold both sticks to open it.

## Telescope: flat 2D screen (2026-10-26, Arek-verified)

- The telescope view switches the view target to `BP_Telescope_C`'s CameraComponent (main state 5) and draws the sight, out-of-focus blur and colour split as screen-space post-process materials (`TelescopeSightMaterial`, `MI_OutOfFocus`, chromatic aberration). In Native Stereo these flickered between the eyes (headset and mirror; one frame in six roughly doubled in brightness).
- `alone_in_the_dark_vr.lua` sets `VR_2DScreenMode=true` while the view target's class is in `FLAT_SCREEN_TARGETS` (only `BP_Telescope_C`) and back to false when it changes. Arek: no flicker in the headset or on the monitor.
- Controls verified with simulated Quest input: A fits the lens from the item picker, right stick left/right = focus, up/down = zoom, B leaves.

## Puzzle and menu checks with simulated Quest input (2026-10-26, flat mirror, no headset)

Method: `tools/README.md`, "Simulated Quest input". Every puzzle entered with A reported main state 5 and `puzzle=true` in `data/aitd_view_log.txt`, so the controller passes through unchanged.
- Dial safe (Ch2 mansion): prompt "B Back, LB RB Dial". Left grip turns down, right grip up; combination entered, solved.
- Symbol padlock (Ch2 mansion): left stick left/right selects the dial, up/down changes it; solved.
- Telescope: see above.
- Item picker (lens, medallions): left stick cycles, A selects, B backs out.
- Gameplay: right grip aims (`IsAiming` true), left trigger does not. Y tap opens the investigation menu (state 3), Y hold the pause menu (state 4), B closes.
- Investigation menu: left/right grip taps switch tabs (LB on release). Document reader: right grip turns pages, X hold = Y "View" (enlarged page), B back. Pick-up cards: A open, B back.
- Left grip held + right stick flick sends one D-pad press (checked on the collectibles list). The map tab stayed greyed out in every save available (the game unlocks it later), so "Change floor" itself is still untested.
- Save deletion is disabled: the game binds Y to "Delete save" on the Load Game screens (main menu = state 7, pause = state 4). `alone_in_the_dark_vr.lua` strips Y in state 7 and never emits Y in state 4 (the X hold sends nothing there). Verified 2026-10-26 with simulated Quest Y tap and hold on both Load screens: no prompt, all save hashes unchanged. No other state-4/7 screen (pause, options, save game) uses Y.

## Open

- Revolver/shotgun/Tommy gun done; flare gun and Remington not yet checked for grip and two-handing.
- A crash after reloading a save from the pause menu (access violation in the game) was investigated separately; save-reload fixes landed and it has not recurred.

Rollback: remove `aitd_vr_ui.lua` and `aitd_vr_reticle.lua` from the profile `scripts/`, restore `config.txt` and `uobjecthook/camera_state.json` from `backups/ui-pass-start-20261025-094703/`.
