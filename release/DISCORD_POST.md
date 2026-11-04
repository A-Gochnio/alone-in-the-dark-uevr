**Alone in the Dark (2024) VR: motion controls profile v{{VERSION}} (public beta)**

A UEVR profile that turns the Steam version of Alone in the Dark (2024) into a first-person VR game:
- 6DOF head tracking at eye height; crouching lowers your view.
- Guns sit in your hand and shoot where the barrel points, with a red laser aim dot.
- Two-handed shotgun and Tommy gun: hold the left grip near the barrel.
- VR control layout: right grip aims, right trigger fires, left trigger melee, X reload / hold to sneak, Y inventory / hold for pause, left grip + right stick for weapons and items.
- Menus fixed in the room, a smaller HUD that follows your head, no head-locked crosshair.
- Close-up puzzles switch to the plain controller layout automatically; the telescope is shown on a flat virtual screen (no flicker).
- Deleting saves is disabled, so a stray button press can't wipe a save.
- Works for both Edward and Emily.

**Needs:** Steam version of the game, UEVR nightly 01143 (github.com/praydog/UEVR-nightly; other UEVR builds are untested), an OpenXR runtime (Virtual Desktop: VDXR).
**Tested on:** Quest 3 over Virtual Desktop with an RTX 4070 Ti, steady 90 FPS with the recommended settings in the README.

**Install:** extract the zip, double-click `Install.bat` (installs the UEVR profile and a few Engine.ini tweaks, backs up anything it replaces; `Install.bat -Uninstall` undoes it). Then start the game, inject UEVR with OpenXR, and close the UEVR menu (Insert, or hold both sticks). Controls and graphics settings are in README.txt.

**Beta, please read:** it hasn't been played through to the end in VR yet, so later parts may need fixes. Puzzles, menus and the telescope were checked with simulated controller input rather than all in the headset. Changing floors on the map is untested.

**Found a problem?** Reply here with your headset, GPU, the mod version, Edward or Emily, and what happened (describe where you were without spoilers). Thanks for testing!
