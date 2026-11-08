# Nomad's Seekers: Prototype

Godot 4.7, 3D, Forward+. Open `project.godot` in the editor and press **F5**.

Built in playable parts (see the Prototype Roadmap in the Claude project). Current: **Part 2, combat core**.

## Part 1: movement
- **Seeker controller** (`scripts/player/player.gd`): camera-relative movement with snappy acceleration, a variable-height jump with coyote time and an input buffer, and a dash/dodge with i-frames, one air dash, and dash-jump (jump during a ground dash to keep momentum).
- **PSO-style camera** (`scripts/camera/camera_rig.gd`): a loose follow camera by default. It trails you like someone walking behind you with a camera: it doesn't turn when you turn, only swings around as you walk away from it, and backs up when you walk toward it. After you look up or down, it eases back to its default height. Set `follow_mode` to RIGID for a third-person shooter style camera. It avoids walls and supports right-stick and mouse look.
- **Lock-on** (R3): targets whatever is closest to where the camera faces, the Seeker strafes and orbits the target, flick the right stick to switch targets, and lock breaks when the target goes out of range. With nothing in range, R3 recenters the camera to where you were facing at the moment you pressed it.
- **Input map** (`scripts/autoload/input_setup.gd`): the full North Star control map, registered in code.

## Part 2: combat
- **Hand buttons** (`scripts/combat/combat_controller.gd`): X and Y are your two hands (`x_is_left` chooses which is which). Tap for a Normal attack, hold for a Hard attack.
- **Timing combos**: 3 steps per chain. Press again inside the current attack's window to chain. Too early breaks the combo; too late starts a new chain. Any attack from either hand can fill the next step.
- **Weapon steps**: each weapon counts its own consecutive uses. Sword, Sword, Sword plays Slash, Return Slash, Cleave with bonus damage. Sword, Pistol, Sword plays the sword's Slash both times.
- **PSO timing**: the starter weapons use PSO Blue Burst's frame data (30 fps) from the [Ephinea wiki](https://wiki.pioneer2.net/w/Game_mechanics/Frame_data): saber timings for the Sword, handgun for the Pistol, and Foie's cast time for spells. `tools/build_starter_weapons.gd` lists the source frame numbers next to each attack.
- **Starter weapons** (`data/weapons/*.tres`): Sword (melee), Pistol (projectiles, costs a little LP), Wand (casting item: Fire Bolt, or Frost Lance with RT held), and Dervish Blades (two-handed, sustained). Spells are standalone and end a chain. Edit the `.tres` files in the Inspector.
- **Moving while attacking** (PSU-style): each attack's `move_speed_scale` is 0 (rooted) or the fraction of run speed you keep. Melee roots you, except Dervish Blades. Normal shots and Normal spells let you walk at half speed; Charged shots and Hard spells plant your feet. With nothing targeted, a mobile shot fires where the stick points.
- **Dervish Blades**: the machinegun of melee. Tap for quick spinning slashes you can walk through (both buttons count as the same weapon for combo steps). Hold to spin continuously, hitting everything around you every 0.15 s while moving at 60% speed; release to stop.
- **LP**: spells and shots cost LP. It regenerates slowly for now so testing never stalls.
- **Damage types and stats**: damage = base x step multiplier x (1 + STR/DEX/SOL / 100), with crits from LCK. Every attack carries one element.
- **Dash cancel**: dashing cancels an attack once its hit is out.
- **Prototype loadouts**: LB/RB cycles Sword+Pistol, Wand+Sword, Pistol+Pistol, Dervish Blades. Real loadout editing comes in Part 3.
- **Dummies with HP** (`scripts/enemies/target_dummy.gd`): floating damage numbers colored by element, hit flash, and respawn after death. DummyC is weak to Fire and resists Ice; DummyD is weak to Ice.
- **Navmesh movement**: the test room's `Navigation` region bakes a navmesh at startup from the level's collision. Dummies move with `NavigationAgent3D`: DummyB patrols, and DummyE chases you around obstacles. The same navmesh will later generate the area map.

## Controls
| Action | Gamepad | Keyboard / mouse |
|---|---|---|
| Move | Left stick | WASD |
| Camera | Right stick | Mouse / arrows |
| Jump | A | Space |
| Dash / dodge | B | Shift |
| Lock on / recenter | R3 | Q / middle mouse |
| Switch target | Flick right stick | Sweep mouse |
| Hand attacks (tap / hold) | X / Y | Left / right click |
| Second spell (hold while casting) | RT | E |
| Cycle loadouts | LB / RB | Z / C |
| Toggle debug panel | Select | F3 |

Click to capture the mouse, Esc to release it.

## Tuning
Every feel value is an exported variable or a `.tres` field. Edit them in the Inspector, even while the game is running (use the Remote tree).

- **Player**: `move_speed`, `acceleration`, `jump_height`, `time_to_peak`, `dash_distance`, `dash_duration`.
- **CameraRig**: `follow_mode`, `leash_radius`, `follow_speed`, `pitch_return_delay`, `pitch_return_speed`, `shoulder_offset`, `default_pitch_deg`.
- **Player/Combat**: `hold_threshold` (tap vs hold), `x_is_left`, soft-aim range and angle, `show_hitboxes`.
- **Each attack** in a weapon `.tres`: `move_speed_scale`, `face_movement`, `sustained_tick`, `duration`, `active_start`/`active_end` (hit timing), `window_open`/`window_close` (combo timing), `damage_mult`, `lp_cost`, lunge, hitbox size, projectile settings.

## Physics layers
1 = world, 2 = player, 3 = enemy. The camera, lock-on line-of-sight checks and navmesh bake only use layer 1.

## Known limits (deliberate for now)
- No animation: capsules, with weapons swung by simple tweens. Melee hitboxes show as red boxes (`show_hitboxes`).
- Normal attacks fire when the button is released, so tap and hold can share one button.
- Weapon specials (RT on a tagged weapon), powerstance, shields and the one-Heavy rule come with Parts 3 and 5.
- Dummies don't attack back yet (Part 4).
- The runtime navmesh bake prints a warning because the CSG blockout has no separate collision shapes. It's harmless at this size and goes away with real level geometry.
- No step-up for small ledges yet. Input is bound to all devices until couch co-op.

## Automated tests
Run from the project folder. Each prints `ok` or `FAIL` per check and exits with code 1 if anything fails.

```
godot --headless --path . --script res://tests/movement_test.gd
godot --headless --path . --script res://tests/combat_test.gd
```

- `movement_test.gd`: walking, stopping, jump height, short hops, dash distance, lock-on, orbiting, recentering, camera height return.
- `combat_test.gd`: tap and hold, 3-step rhythm combos, PSO pistol cadence, rooted vs mobile attacks, Dervish Blades combo and spin, step damage bonuses, too-early and too-late presses, mixed-weapon steps, LP, projectiles, spells and Shift, elemental weakness, dash cancel, death and respawn, navmesh bake, chase and patrol pathing.

`tools/build_starter_weapons.gd` regenerates the starter weapon `.tres` files with their default values (this overwrites any edits).
