# Nomad's Seekers: Prototype

Godot 4.7, 3D, Forward+. Open `project.godot` in the editor and press **F5**.

Built in playable parts (see the Prototype Roadmap in the Claude project). Current: **Part 3, loadouts and blocking**.

## Part 1: movement
- **Seeker controller** (`scripts/player/player.gd`): camera-relative movement with snappy acceleration, a variable-height jump with coyote time and an input buffer, and a dash/dodge with i-frames, one air dash, and dash-jump (jump during a ground dash to keep momentum).
- **PSO-style camera** (`scripts/camera/camera_rig.gd`): a loose follow camera by default. It trails you like someone walking behind you with a camera: it doesn't turn when you turn, only swings around as you walk away from it, and backs up when you walk toward it. After you look up or down, it eases back to its default height. Set `follow_mode` to RIGID for a third-person shooter style camera. It avoids walls and supports right-stick and mouse look.
- **Lock-on** (R3): targets whatever is closest to where the camera faces, the Seeker strafes and orbits the target, flick the right stick to switch targets, and lock breaks when the target goes out of range. With nothing in range, R3 recenters the camera to where you were facing at the moment you pressed it.
- **Input map** (`scripts/autoload/input_setup.gd`): the full North Star control map, registered in code.

## Part 2: combat
- **Hand buttons** (`scripts/combat/combat_controller.gd`): X and Y are your two hands (`x_is_left` chooses which is which). Tap for a Normal attack, hold for a Hard attack.
- **Timing combos**: 3 steps per chain. The chain window opens when the current attack ends and stays open about as long as PSO's window. Pressing while the attack is still playing breaks the combo; too late starts a new chain. Timing is judged when the button goes down, so holding for a Hard attack that starts in the window still chains. Hard chains take longer (and are riskier), not tighter. Any attack from either hand can fill the next step.
- **Weapon steps**: each weapon counts its own consecutive uses. Sword, Sword, Sword plays Slash, Return Slash, Cleave with bonus damage. Sword, Pistol, Sword plays the sword's Slash both times.
- **PSO timing**: the starter weapons use PSO Blue Burst's frame data for hit frames, attack length and window length (30 fps) from the [Ephinea wiki](https://wiki.pioneer2.net/w/Game_mechanics/Frame_data): saber timings for the Sword, handgun for the Pistol, and Foie's cast time for spells. `tools/build_starter_weapons.gd` lists the source frame numbers next to each attack.
- **Starter weapons** (`data/weapons/*.tres`): Sword (melee), Pistol (projectiles, costs a little LP), Wand (casting item: Fire Bolt, or Frost Lance with RT held), and Dervish Blades (two-handed, sustained). Spells are standalone and end a chain. Edit the `.tres` files in the Inspector.
- **Moving while attacking** (PSU-style): each attack's `move_speed_scale` is 0 (rooted) or the fraction of run speed you keep. Melee roots you, except Dervish Blades. Normal shots and Normal spells let you walk at half speed; Charged shots and Hard spells plant your feet. With nothing targeted, a mobile shot fires where the stick points.
- **Dervish Blades**: the machinegun of melee. Tap for quick spinning slashes you can walk through (both buttons count as the same weapon for combo steps). Hold to spin continuously, hitting everything around you every 0.2 s while moving at 60% speed; release to stop.
- **LP**: spells and shots cost LP. It regenerates slowly for now so testing never stalls.
- **Damage types and stats**: damage = base x step multiplier x (1 + STR/DEX/SOL / 100), with crits from LCK. Every attack carries one element.
- **Dash cancel**: dashing cancels an attack once its hit is out.
- **Dummies with HP** (`scripts/enemies/target_dummy.gd`): floating damage numbers colored by element, hit flash, and respawn after death. DummyC is weak to Fire and resists Ice; DummyD is weak to Ice.
- **Navmesh movement**: the test room's `Navigation` region bakes a navmesh at startup from the level's collision. Dummies move with `NavigationAgent3D`: DummyB patrols, and DummyE chases you around obstacles. The same navmesh will later generate the area map.

## Part 3: loadouts and blocking
- **Loadout menu** (Start / Tab, `scripts/ui/loadout_menu.gd`): 8 loadouts. Pick a hand, then a weapon. The game pauses while it's open, and closing saves to `user://loadouts.tres`. LB/RB cycles loadouts, skipping empty ones and ones that break a rule.
- **Rules** (`scripts/combat/loadout.gd`): a two-handed weapon uses both hands (equipping one clears the other hand). Only one Heavy item per loadout; the **Double-Heavy augment** (a menu toggle until armor exists) allows two Heavy one-handed items, including a Heavy Shield with an Axe.
- **LT depends on the loadout**:
  - Shield in either hand: full block at the shield's strength (Shield 60%, Heavy Shield 85%). A hit in the first 0.2 s of the block is **parried** (no damage, the attacker is staggered).
  - Two-handed weapon: weak block (Great Sword 35%, Dervish Blades 30%).
  - Anything else, including a powerstanced pair: arms-up block, 25%.
  - Blocks and parries only cover the front (140°). Blocking slows you to 40% speed.
  - With a shield you can attack without dropping the block; those attacks deal 66% damage. Other blocks drop while you attack.
- **Powerstance**: a pair of the same weapon type (even different items, like Sword + Frost Sword) always attacks with both weapons, each at 75% (1.5x total), on either button. Twin attacks chain their own 3 steps. Twin casting items cast both spells at full power and full LP.
- **RT + a hand's button** uses the special of the weapon in that hand (`WeaponData.special_attack`); with a powerstanced pair, the other hand swings normally at the same time. No weapon has a special until Part 5, so for now RT + a button is a normal attack (or the second spell on a casting item).
- **Two-handed weapons are one item**, held in the right hand and used by both buttons.
- **Target markers** (PSU-style, `scripts/ui/target_markers.gd`): small yellow rings mark every enemy your next attack would hit, so you can see a Great Sword sweep catching two enemies, or a piercing Frost Lance lining up a row. The locked-on enemy gets a larger red ring, dimmed when your next attack won't reach it. The preview follows the last hand you pressed, includes the attack's lunge, and updates with RT held (specials and second spells).
- **Sword hitbox narrowed** to match PSO's single-target saber; the Great Sword is the wide sweep.
- **Shield hand button**: Shield **Deflect** opens a parry window; Heavy Shield **Shove** knocks enemies back.
- **Dodge**: hits during the dash's i-frames are dodged.
- **New weapons**: Shield, Heavy Shield, Great Sword (PSO sword frames), Axe (PSO partisan frames), Frost Sword (an Ice sword that powerstances with the Sword).
- **Block practice** in the test room: the Swinger glows orange, then swings; the Shooter fires slow pink bolts. Parry the Swinger to stagger it (it glows blue).
- **Taking damage**: the Seeker now has HP that enemies can reduce, and respawns at the start on death.

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
| Block / powerstance | LT | F |
| Loadout menu | Start | Tab |
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
- Weapon specials (RT on a tagged weapon) come with Part 5. The magic shields (Ward, Barrier) and their reflect come with Part 4, when enemies cast spells.
- The game pauses while the loadout menu is open. Co-op will need a non-pausing version.
- The runtime navmesh bake prints a warning because the CSG blockout has no separate collision shapes. It's harmless at this size and goes away with real level geometry.
- No step-up for small ledges yet. Input is bound to all devices until couch co-op.

## Automated tests
Run from the project folder. Each prints `ok` or `FAIL` per check and exits with code 1 if anything fails.

```
godot --headless --path . --script res://tests/movement_test.gd
godot --headless --path . --script res://tests/combat_test.gd
godot --headless --path . --script res://tests/loadout_test.gd
godot --headless --path . --script res://tests/targeting_test.gd
```

- `movement_test.gd`: walking, stopping, jump height, short hops, dash distance, lock-on, orbiting, recentering, camera height return.
- `combat_test.gd`: tap and hold, 3-step rhythm combos, PSO pistol cadence, rooted vs mobile attacks, Dervish Blades combo and spin, step damage bonuses, too-early and too-late presses, mixed-weapon steps, LP, projectiles, spells and Shift, elemental weakness, dash cancel, death and respawn, navmesh bake, chase and patrol pathing.

- `loadout_test.gd`: one-Heavy and two-handed rules, the augment, cycling past empty and invalid loadouts, LT mode per loadout, shield / arms-up / two-handed block percentages, parry and stagger, no block from behind, Deflect, dash dodge, Heavy Shield shove, blocking a real Shooter bolt, powerstance twin hits and twin combos, twin pistols, the powerstance option, and the menu opening and pausing.

- `targeting_test.gd`: Sword marks one of two side-by-side enemies and Great Sword marks both, and real swings hit exactly what was marked; the Pistol and Fire Bolt mark the first enemy in line and Frost Lance marks the whole line; lock-on shows the large ring and hides it on release.

The tests always use the default loadouts and never overwrite your saved ones.

`tools/build_starter_weapons.gd` regenerates the starter weapon `.tres` files with their default values (this overwrites any edits).
