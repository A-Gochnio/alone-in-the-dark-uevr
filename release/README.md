Alone in the Dark (2024) VR: UEVR profile with motion controls
Version {{VERSION}} (BETA)

THIS IS A BETA. Only the start of the game has been played in VR so far, with both characters;
it has not been played through to the end. Puzzles, menus and the telescope were also checked
with simulated controller input. Expect rough spots later in the game, and please report them
(see REPORTING PROBLEMS at the end).

A UEVR profile for the Steam version of Alone in the Dark (2024): first person, 6DOF,
motion-controlled guns that shoot where the barrel points, two-handed long guns, a laser aim
dot and a comfortable VR HUD and menus. Works for both Edward and Emily.

Tested on: Meta Quest 3 over Virtual Desktop (VDXR / OpenXR), RTX 4070 Ti, 90 Hz, steady 90 FPS
with the settings below. Other headsets and runtimes should work through OpenXR but are untested.


REQUIREMENTS
------------
- Alone in the Dark (2024), Steam version.
- UEVR nightly {{UEVR_BUILD}} (newest official build at the time of release):
  https://github.com/praydog/UEVR-nightly/releases/tag/{{UEVR_TAG}}
  Other UEVR builds are untested. Some forks break this game (one eye black).
- An OpenXR runtime. Virtual Desktop: set the OpenXR runtime to VDXR.


INSTALL
-------
1. Quit the game. Extract this whole zip into any folder.
2. Double-click Install.bat. It:
   - installs the UEVR profile to %APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping
     (an existing profile for this game is moved to a "-backup-<date>" folder first, so old
     scripts can't interfere),
   - adds the recommended settings to the game's Engine.ini (backed up first).
   Install.bat -SkipEngineIni installs only the profile. Install.bat -Uninstall undoes both.
   Nothing is deleted: uninstalling moves the profile to a backup folder too.
3. Set the in-game graphics options (see RECOMMENDED GRAPHICS below).
4. Launch the game. In UEVRInjector select AloneInTheDark-Win64-Shipping.exe, choose OpenXR and
   click Inject. Do this in the main menu or after loading a save.
5. If the UEVR menu is open after injecting, close it (Insert on the keyboard, or hold both
   thumbsticks down). While it is open the controllers do not reach the game.

Manual install instead of Install.bat: delete or back up the profile folder above, then in
UEVRInjector click "Import Config" and pick AloneInTheDark-Win64-Shipping.zip (don't rename it:
UEVR uses its name to find the game), and add the lines from Engine-ini-additions.txt to
%LOCALAPPDATA%\AloneInTheDark\Saved\Config\WindowsNoEditor\Engine.ini.


CONTROLS
--------
Right grip ............ aim
Right trigger ......... fire
Left trigger .......... melee
Left grip (aiming) .... hold near the barrel to two-hand a long gun (you feel a buzz)
Left grip + right stick flick ... weapons / items (D-pad: right, down, left, up)
X tap / X hold ........ reload / stealth (crouch)
Y tap / Y hold ........ inventory / pause menu
Hold both sticks ...... UEVR menu (a quick click of both does nothing)
Other buttons and sticks keep the game's own controller layout.

Menus: the grips switch tabs. Left grip held + right stick up/down changes the map floor.
Documents: right grip turns pages, hold X to view the page itself.
Close-up puzzles get the plain controller layout (grips rotate, sticks move, A selects).
Looking through the telescope switches to a flat virtual screen (its lens effects flicker in
3D); it switches back when you leave.
Deleting saves is disabled: Y does nothing on the Load Game screens, so a stray press can't
delete a save.

Options: UEVR menu > Lua Loader / Script UI > "Alone in the Dark VR":
- Laser aim dot (on)
- Shoot from the barrel (on). Off: shots go where you look, like the flat game.
- Show belt items (off). The chest flashlight and holstered gun do not turn with you, so they
  are hidden by default. The flashlight still lights the way.


RECOMMENDED GRAPHICS
--------------------
In-game options (these gave a steady 90 FPS on an RTX 4070 Ti at the Quest 3's full resolution):
- Upscaler: DLSS Quality
- Shadows: Low (shadows render per eye and cost the most)
- View distance: Epic, Detail: Epic
- Shading: High, Foliage: High, Textures: Epic, Anisotropic filtering: 16x
- Motion blur, depth of field and chromatic aberration: off
- Camera shake: 0% (comfort)

Engine.ini tweaks (less pop-in, sharper image, less DLSS shimmer in VR): Install.bat adds them.
On a GPU with less than 12 GB of VRAM, lower r.Streaming.PoolSize in Engine-ini-additions.txt
(for example to 3000) before running Install.bat, or run it again after the change.

Optional, recommended: DLSS 4. The game ships DLSS 3.1.1. Swapping in DLSS 310.x (for example
with DLSS Swapper) gives a sharper image. The Engine.ini lines select the lighter CNN preset E,
which keeps 90 FPS; the default transformer model costs about 15 FPS more.

Virtual Desktop: 90 FPS, SSW off. Keep "Boost game priority" off (it froze the PC in testing).
Frame generation and UEVR's AFW mode are not recommended: they ghost when you turn your head.


KNOWN ISSUES
------------
- Beta: not yet played through to the end. Later scenes may still need VR fixes; please report them.
- Puzzles were checked with simulated controller input, not all of them in the headset.
- Changing the map floor (left grip + right stick) is untested: the map unlocks later in the game.
- A slight "heat haze" around moving objects with DLSS in VR. TAA does not have it, but looks
  much softer. The Engine.ini lines reduce it.
- A room-fixed menu stays where it opened: open menus while looking roughly straight ahead.
- If Virtual Desktop disconnects mid-game, VR stops working until you restart the game.
- If both thumbsticks stop responding (also in the VD overlay), restart the headset.
- UEVR drops idle controllers after 30 s. Move them to wake them up.
- Some leaf flicker in the distance comes from the game itself (it is in flat mode too).


UNINSTALL
---------
Run Install.bat -Uninstall (from a command prompt in this folder), or delete
%APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping and remove the "AitD VR" lines from Engine.ini.


REPORTING PROBLEMS
------------------
Open an issue at https://github.com/A-Gochnio/alone-in-the-dark-uevr/issues or reply to the
release post where you downloaded this. Please include: headset and how it is
connected (e.g. Quest 3 + Virtual Desktop), GPU, the mod version ({{VERSION}}), Edward or Emily,
what you did and what happened. Describe where you were without story spoilers (e.g. "a puzzle
in the first house"). A screenshot of the desktop window helps. If the game crashed, say whether
it happened while loading, in a menu or in play.


CREDITS
-------
Made by Arek.
Some UObjectHook settings (hidden third-person body mesh) come from an earlier community
UEVR profile for this game from 2024.
UEVR by praydog: https://github.com/praydog/UEVR
