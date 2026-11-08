# Nomad's Seekers: Prototype

Godot 4.7, 3D, Forward+. Open `project.godot` in the editor and press **F5**.

Built in playable parts (see the Prototype Roadmap in the Claude project). Current: **Part 6, SyncAIDa**.

Two scenes: `scenes/main.tscn` is the test room (F5), and `scenes/arena.tscn` has two wave rooms full of real enemies (open it and press F6).

## Part 1: movement
- **Seeker controller** (`scripts/player/player.gd`): camera-relative movement with snappy acceleration, a variable-height jump with coyote time and an input buffer, and a dash/dodge with i-frames, one air dash, and dash-jump (jump during a ground dash to keep momentum).
- **PSO-style camera** (`scripts/camera/camera_rig.gd`): a loose follow camera by default. It trails you like someone walking behind you with a camera: it doesn't turn when you turn, only swings around as you walk away from it, and backs up when you walk toward it. After you look up or down, it eases back to its default height. Set `follow_mode` to RIGID for a third-person shooter style camera. It avoids walls and supports right-stick and mouse look.
- **Lock-on** (R3): targets whatever is closest to where the camera faces, the Seeker strafes and orbits the target, flick the right stick to switch targets, and lock breaks when the target goes out of range. With nothing in range, R3 recenters the camera to where you were facing at the moment you pressed it.
- **Input map** (`scripts/autoload/input_setup.gd`): the full North Star control map, registered in code.

## Part 2: combat
- **Hand buttons** (`scripts/combat/combat_controller.gd`): X is your right hand and Y your left (`x_is_left` swaps them). Tap for a Normal attack, hold for a Hard attack.
- **Timing combos**: 3 steps per chain, using PSO's windows. The chain window opens when the swing ends (PSO's "combo" frame, just after the hit) and closes when the recovery ends; chaining cancels the rest of the recovery. Timing is judged when the button goes down, so a Hard hold that starts in the window still chains. `early_tolerance` (0.15 s) is an input buffer: a press slightly before the window counts and fires the moment the window opens, never cutting the swing short. Earlier than that breaks the combo; too late starts a new chain. Any attack from either hand can fill the next step.
- **Weapon steps**: each weapon counts its own consecutive uses. Sword, Sword, Sword plays Slash, Return Slash, Cleave with bonus damage. Sword, Pistol, Sword plays the sword's Slash both times.
- **PSO timing**: the starter weapons use PSO Blue Burst's frame data for hit frames, attack length and window length (30 fps) from the [Ephinea wiki](https://wiki.pioneer2.net/w/Game_mechanics/Frame_data): saber timings for the Sword, handgun for the Pistol, and Foie's cast time for spells. `tools/build_starter_weapons.gd` lists the source frame numbers next to each attack.
- **Starter weapons** (`data/weapons/*.tres`): Sword (melee), Pistol (projectiles, costs a little LP), Wand (casting item: Fire Bolt, or Frost Lance with RT held), and Dervish Blades (two-handed, sustained). Spells are standalone and end a chain. Sustained weapons (Dervish Blades, Machine Pistol, Assault Rifle) don't combo either: hold to sustain, and each tap is a single standalone attack. Edit the `.tres` files in the Inspector.
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
- **Target markers** (PSU-style, `scripts/ui/target_markers.gd`): rings on every enemy each hand's next attack would hit, shown for both hands at once: **blue** for the right hand (X), **yellow** for the left hand (Y), **green** when both would hit the same enemy. You can see a Great Sword sweep catching two enemies, or a piercing Frost Lance lining up a row. The locked-on enemy also gets a larger red ring, dimmed when neither hand would reach it. Predictions include the attack's lunge and update while you hold RT (specials and second spells).
- **Sword hitbox narrowed** to match PSO's single-target saber; the Great Sword is the wide sweep.
- **Shield hand button**: Shield **Deflect** opens a parry window; Heavy Shield **Shove** knocks enemies back.
- **Dodge**: hits during the dash's i-frames are dodged.
- **New weapons**: Shield, Heavy Shield, Great Sword (PSO sword frames), Axe (PSO partisan frames), Frost Sword (an Ice sword that powerstances with the Sword).
- **Block practice** in the test room: the Swinger glows orange, then swings; the Shooter fires slow pink bolts. Parry the Swinger to stagger it (it glows blue).
- **Taking damage**: the Seeker now has HP that enemies can reduce, and respawns at the start on death.

## Part 4: enemies and rooms
- **Arena** (`scenes/arena.tscn`, built by `tools/build_arena.gd`): a start corridor and two PSO-style **wave rooms**. Walking in closes the doors (glowing orange), each wave spawns when the last enemy of the previous one falls, and the doors open after the final wave. Room A has three waves, Room B two (the last one has all six enemy types).
- **Wave rooms** (`scripts/rooms/wave_room.gd`): add `WaveData` resources (a list of enemies) to `waves`, put CSG doors under `Doors` (outside the Navigation region, so the navmesh is baked with the doorways open) and `Marker3D` spawn points under `SpawnPoints`.
- **Enemies** (`scripts/enemies/enemy.gd`, data in `data/enemies/*.tres`): navmesh AI. They idle until you come within aggro range or hit them, then path to you. Melee enemies close in; ranged and spell enemies hold their distance and back off if you get too close. Every attack is telegraphed: the enemy glows in its element's color, then strikes. Hard hits and big hits stagger them, a parry staggers them longer, and a shove knocks them back.
- **One enemy per monster type** (North Star §2.6):

| Enemy | Type | Fights by | Element |
|---|---|---|---|
| Grub Hound | BEAST | Charges and swipes | — |
| Mutated Crawler | MUTATED | Fast, evasive bite | Nature (Poison) |
| Sentry Drone | SYNTHETIC | Hovers, keeps ~9 m, shoots | Lightning (Shock) |
| Umbral Eye | DARK | Floats back, slow casts | Dark (Drain) |
| Caustic Ooze | ALCHEMIC | Slow, tanky, slams all around it | Fire (Burn) |
| Lumen Sprite | LIGHT | Evasive, darting caster | Light (Blind) |

- **Status effects** (`scripts/combat/status_effects.gd`) on enemies, dummies and the Seeker: elemental hits build up; past the threshold the status starts. Burn and Poison deal damage over time, Ice Slows (more Ice while Slowed Freezes), Lightning Shocks (stunned), Light Blinds (half your attacks miss), Dark Drains (damage over time that heals whoever applied it). Frozen or shocked means no moving, attacking or dodging. Your statuses show above the HUD bars; enemies list theirs under their HP.
- **Defense stats**: DEF reduces melee damage, RES reduces magic, EVA reduces ranged and gives a chance for melee and ranged attacks to miss (spells always land). Reduction is 100 / (100 + stat). Enemies have their own DEF / RES / EVA, weaknesses and resistances.
- **Ward and Barrier** (magic shields): block 50% / 75%. Their hand button (Reflect) and a fresh LT press open a reflect window: an enemy shot or spell that hits you then flies back at the shooter, faster. They can't parry melee, only block it. Add them to a loadout in the menu.
- **All hits go through `HitResolver`**, so blocks, parries, reflects, misses, defense and status work the same for every weapon and enemy.

## Part 5: weapons and loot
- **The full weapon list** (North Star §5.3) plus the Gunblade and Burstbow, 41 weapons in `data/weapons/`. Timings come from PSO frame data (Ephinea, 30 fps) where PSO has the weapon or a close relative; the rest scale the nearest table (noted in `tools/build_starter_weapons.gd`).
  - **Melee:** Sword, Great Sword, Bladestaff, Dagger, Spear, Halberd, Mace, Maul, Flail, Axe, Great Axe, Glove, Dervish Blades.
  - **Ranged:** Pistol, Machine Pistol (automatic pistol: tap = single shot, hold = automatic; a powerstanced pair fires both), Hand Shotgun and Shotgun (pellet spreads), Rifle (piercing, long chain window), Assault Rifle (hold = automatic), Bazooka (rocket, big blast), Grenade (thrown in an arc; 3 in a row ends with a double throw), Grenade Launcher (lobbed, status-heavy), Thrown Daggers, Boomerang (homes in on up to 5 enemies in turn), Gigarang (hits on the way out and back), Bow, Crossbow, Arbalest, Burstbow.
  - **Magic:** Wand, Cane (stronger, slower damage spells), Staff (two-handed, four spells: X, Y, RT + X, RT + Y), Talisman and Totem (Heal and Cure), Cards (SOL damage, thrown at several enemies).
  - **Hybrid:** Gunblade (Heavy, two-handed, Striker / Ranger): a blade between the Sword and Great Sword when you're not locked on, a gun between the Pistol and Rifle when you are. The HUD shows which mode it's in.
  - **Burstbow** (Ranger): PSO's shotgun. Rifle-slow shots that pick 3, 3, then 5 enemies.
  - **Targeted volleys:** Thrown Daggers (1 / 3 / 5 enemies), Cards (1 / 2 / 4) and the Burstbow throw one projectile at each picked enemy, so no enemy is hit twice by one attack, and each projectile flies past everything but its target. Shotguns keep their even spread.
  - **Piercing:** only the Arbalest and Gigarang pass through enemies (the Boomerang homes from one to the next). Specific rares, like Stormcaller, can pierce too.
  - **Shields:** Shield, Heavy Shield, Ward, Barrier.
- **Jobs.** Each weapon lists the jobs that can use it (S Striker, R Ranger, I Invoker). Loadouts holding a weapon your job can't use say "job locked" and LB/RB skips them. The job is chosen at character creation and can't change afterwards (unlike PSU); the Levels tab has a debug switch for testing.
- **Special tags.** Found weapons can roll a tag line in tiers (PSO's specials: Heat → Fire → Flame → Burning, Dim → … → Hell, Draw → … → Gush, and so on). The tag names the weapon ("Flame Sword"), gives elemental lines their element, and unlocks the weapon's **RT special**: hold RT and press that hand. The special is a stronger first attack that costs LP and applies the tag: elemental status buildup, instant kill (never bosses), heal from damage, LP steal, EXP steal, HP cut, or the Charge line's x3 hit (paid in Oro, LP or HP).
- **Monster-type bonuses** (PSO's "% vs Native"): +5–30% damage vs one of the six monster types.
- **Drops.** Enemies give EXP and roll a drop where they fall: Oro, a consumable, or a weapon. Weapons come from your **emblem's pool**: each of the 12 emblems (Crimson, Orange, Gold, Green, Teal, Cyan, Blue, Purple, Magenta, Pink, White, Black; from name + race + gender + job, like PSO section IDs) favors two weapon families and carries its own **rares** (Emberfang, Glacier Maw, Stormcaller, Gravesong, Lifeleech Coil, Lumen Edge, Kingmaker). Pickups drift to you when you're close.
- **Heal and Cure** (Talisman, Totem, Staff): Heal restores HP, Cure clears every status. Both reach other Seekers within 10 m.
- **Consumables:** HP Gel, LP Cell, Cure Salt. D-pad left / up / right or 1 / 2 / 3.
- **Lumidium.** Crystal deposits in the arena break after 3 hits into Lumidium of their color. Carried Lumidium is lost when you die; stand on a **teleporter** pad to bank it.
- **Menu tabs** (LB/RB in the menu): Loadouts (the picker now lists found weapons first, greyed out if your job can't use them), Inventory, Character.
- **Save file:** `user://save.tres` holds the character, loadouts and inventory. It's written when the menu closes and at teleporters. Part 3's `loadouts.tres` is imported once.

## Part 6: SyncAIDa
- **Your SyncAIDa** floats just over and behind your right shoulder (the camera is centred on the Seeker, so future twin SyncAIDa can take both shoulders). Its color follows its strongest stat and its shape changes with each evolution.
- **Starter choice:** a new Seeker picks one of four starters in the menu's **SyncAIDa** tab (the menu opens there until you've chosen). Each starts at **level 5 in one stat**, so it boosts what your character needs right away: Aegi (DEF), Kindle (STR), Swift (DEX), Lumi (SOL). You can own several and pair one; with Free feeding on, the tab also lets you adopt more starters for testing.
- **Feeding** (SyncAIDa tab): consumables come from your inventory and Lumidium from your bank. Each item raises some of **DEF / STR / DEX / SOL** and may lower another, as in PSO, but a lowered stat only loses progress toward its next level: a stat level, once earned, is never lost. Every 100 XP in a stat is one stat level. The SyncAIDa's level is the sum of its stat levels, up to **200**. Each stat level adds to your matching stat: STR and DEF +2, DEX and SOL +1. The SyncAIDa tab shows each stat's level and a bar with its progress to the next level, as in PSO.
- **Evolution** (PSO-style formulas):
  - **Level 10:** takes a form from its strongest stat (Shell, Ember, Flit or Glimmer).
  - **Level 35:** takes a form from its strongest stat (Bastion, Talon, Kestrel or Wisp).
  - **Level 50 and up:** takes a form from its two strongest stats (Bulwark, Sentinel, Oracle, Falcon, Pyre or Zephyr), re-checked every 5 levels.
  - **Level 100:** adds "Prime".
  - Forms depend only on the SyncAIDa's stats, never your job, so one character can raise a SyncAIDa for another (PSO's mag meta-progression).
- **Sync Burst** (L3 / R when the gauge is full). The gauge fills from damage you deal and take. Each milestone (10 / 35 / 50) unlocks a burst, up to 3. Choose the active one in the SyncAIDa tab.
  - **Lumen Nova:** Light damage to every enemy within 8 m. Scales with level and SOL.
  - **Aegis Pulse:** for 15 s, nearby Seekers deal +30% damage and take -30%.
  - **Mending Bloom:** heals nearby Seekers 50% HP, restores 30 LP and clears statuses.
  - Firing a burst gives a moment of invulnerability.
- **Free feeding (debug)** in the SyncAIDa tab feeds without using items, so you can try evolutions quickly.

## Menu (Start / Tab)
Fully usable with a gamepad: d-pad or left stick moves, **A** accepts, **B** goes back (closes the weapon picker, then the menu), **LB / RB** switch tabs, Start closes.

| Tab | What's there |
|---|---|
| Loadouts | 8 loadouts, weapon picker (found weapons first, then Melee / Ranged / Magic / Shields, A-Z; job-locked weapons are grey and A on one says which job needs it), Double-Heavy augment |
| Inventory | Oro, Lumidium, consumables, found weapons (d-pad scrolls) |
| Character | Name (New name button for gamepads), race, gender, emblem and drop pool. The job is shown but fixed: it's chosen at character creation (Levels tab has a debug switch) |
| SyncAIDa | Starter choice, pairing, feeding, active Sync Burst |
| Levels | Prototype only: level select, refills, Oro / items / Lumidium, respawn, debug readout, hitboxes, free feeding |
| Controls | The control reference (moved out of the debug overlay) |

The debug readout is off by default. Select / F3 or the Levels tab turns it on.

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
| Second spell (hold while casting) / special | RT | E |
| Use HP Gel / LP Cell / Cure Salt | D-pad left / up / right | 1 / 2 / 3 |
| Sync Burst | L3 | R |
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
- Only the arena has Lumidium nodes and teleporters. Teleporters only bank Lumidium; travel arrives with the hub.
- Weapon grinding, armor and augments aren't in yet. Untagged weapons have no RT special.
- EXP is counted but there are no levels yet.
- Party bursts (several Seekers firing together) wait for co-op. SyncAIDa have no feeding cooldown and no personalities yet.
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
godot --headless --path . --script res://tests/enemy_test.gd
godot --headless --path . --script res://tests/loot_test.gd
godot --headless --path . --script res://tests/syncaida_test.gd
godot --headless --path . --script res://tests/menu_test.gd
```

- `movement_test.gd`: walking, stopping, jump height, short hops, dash distance, lock-on, orbiting, recentering, camera height return.
- `combat_test.gd`: tap and hold, 3-step rhythm combos, PSO pistol cadence, rooted vs mobile attacks, Dervish Blades combo and spin, step damage bonuses, too-early and too-late presses, mixed-weapon steps, LP, projectiles, spells and Shift, elemental weakness, dash cancel, death and respawn, navmesh bake, chase and patrol pathing.

- `loadout_test.gd`: one-Heavy and two-handed rules, the augment, cycling past empty and invalid loadouts, LT mode per loadout, shield / arms-up / two-handed block percentages, parry and stagger, no block from behind, Deflect, dash dodge, Heavy Shield shove, blocking a real Shooter bolt, powerstance twin hits and twin combos, twin pistols, the powerstance option, and the menu opening and pausing.

- `targeting_test.gd`: default buttons (X = right hand); Sword marks one of two side-by-side enemies and Great Sword marks both, and real swings hit exactly what was marked; blue / yellow / green per hand, and using one hand doesn't hide the other hand's marker; the Pistol and Fire Bolt mark the first enemy in line and Frost Lance marks the whole line; lock-on shows the large ring and hides it on release.

- `enemy_test.gd` (in the arena): all six monster types, DEF / RES / EVA math and miss rate, every status (Burn ticks, Slow then Freeze, Shock, Blind, Drain healing its source), a Hound pathing to you and hitting for its damage, Hard-hit stagger, a Frozen enemy standing still, a Drone keeping its distance and shooting, Ward reflecting a Drone bolt into the Drone, and a full three-wave room (doors close, waves follow each other, doors open).

- `loot_test.gd` (in the arena): the full weapon list and every emblem's favored families, job locks, the 7 rares covering all 10 emblems, drop rates and emblem weighting, tag tiers, tag names and RT specials, the +30% vs Beast bonus, Gush / Mind / King's / Hell effects (and Hell never killing a boss), the Charge special paying Oro, Shotgun pellets, a Grenade arc and its blast (and its prediction), the Boomerang lock chain, the Gigarang hitting out and back, the Thrown Daggers finisher, Machine Pistol automatic fire, the Staff's four spells, Heal and Cure, EXP and drops, pickups and an HP Gel, a Lumidium node breaking, losing carried Lumidium on death, a teleporter deposit, and a save round-trip.

- `syncaida_test.gd` (in the arena): no SyncAIDa until a starter is chosen, the four starters at level 5 in their stat and the instant bonus, level-10 forms following stats rather than job, feeding from inventory and bank, the stat math, the Seeker stat bonus following the paired SyncAIDa, every evolution (job, strongest stat, top two, Prime), burst unlocks, the 200 cap, the gauge from damage dealt and taken, L3 firing Lumen Nova (in range only), Aegis Pulse in both directions, Mending Bloom, feeding from the menu, and a save round-trip.

- `menu_test.gd` (in the arena): drives every tab with real joypad button events: Start opens, starter pick with the d-pad and A, re-pressing the paired SyncAIDa, feeding, RB / LB tab switching with focus following, the weapon picker (B backs out, a job-locked weapon explains itself, A equips), the Character tab's New name and dropdowns, a Levels tool, B closing the menu, and switching levels.

The tests always use a fresh save and never write yours.

`tools/build_starter_weapons.gd`, `tools/build_enemies.gd` and `tools/build_arena.gd` regenerate the weapons, enemies and arena with their default values (this overwrites any edits).
