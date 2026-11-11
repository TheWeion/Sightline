# Sightline

**Adaptive view distance for World of Warcraft: Forever.**

Turn your view distance up and let Sightline decide where it is worth paying for. It keeps
the distance long where you can see far, shortens it where buildings, walls or water are in
the way, and calibrates every place you visit so your frame rate stays at or above a goal.

Sightline is not occlusion culling. An addon cannot change what the game draws. It changes
the view-distance settings the game already has, using what the game reports about where you
are, and it puts your own settings back when you log out.

## What it does

- **Your settings are the 100%.** Sightline only scales down from the values you set, picks
  up any change you make, and restores them on logout and `/reload`.
- **Three bands.** Terrain and horizon drop the most near walls. Building detail drops about
  half as much. Ground clutter and characters barely change, so the ground around you stays
  as it was.
- **A calibration for every subzone.** On your first visit Sightline lowers the distances a
  step at a time until you hold at least 60 FPS, then remembers it. If FPS drops there later
  it recalibrates from the saved value, and a step that makes no difference is reverted.
- **Optional target FPS.** Aim for a frame rate instead of a minimum. With frames to spare,
  distances can be raised too.
- **Knows when you have alt-tabbed.** A background FPS cap is not mistaken for a drop.
- **Engine maximum.** One button sets every view-distance setting to the highest the game
  allows, so there is more to scale. A welcome dialog offers it on first login, and it can
  be undone.
- **Everything in one window.** Live values, every setting, and the list of calibrations,
  each of which you can set by hand, lock, redo or delete.

## Getting started

1. Log in. Sightline asks whether to start from the engine maximum or from your current
   view distances.
2. Play. Each new subzone is calibrated as you enter it.
3. `/sight` or the minimap button opens the window. Right-click the minimap button to pause
   Sightline and get your own settings back.

## Commands

| Command | Does |
| --- | --- |
| `/sight` | Opens or closes the window |
| `/sight on`, `/sight off` | Resumes, or pauses and restores your settings |
| `/sight fps 75`, `/sight fps off` | Sets a target FPS, or turns it off |
| `/sight here 60`, `/sight zone 60` | Saves how open this subzone or zone is (0 to 100) |
| `/sight minimap` | Shows or hides the minimap button |
| `/sight debug` | Prints each change and test to chat |

## Good to know

- It estimates how far you can see from the kind of place you are in. Where it is wrong (a
  narrow canyon, a dense forest), stand there and save how open the spot is on the Zones tab.
- Lowering view distance helps when your graphics card is the limit. In a crowded city the
  processor usually is; Sightline notices that lowering did not help and gives the distance
  back.
- To check a drop in frame rate it may switch the game's background FPS cap off for a few
  seconds. It always switches it back on, and you can turn this off on the Performance tab.
- Changing view distance makes the game load or unload terrain, so values move gradually and
  small changes are skipped.

## Source and feedback

Source code, bug reports and ideas: [github.com/TheWeion/Sightline](https://github.com/TheWeion/Sightline)

Sightline is free software under the GNU General Public License, version 3.
