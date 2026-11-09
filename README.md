# Nomad's Seekers: Prototype

Godot 4.7, 3D, Forward+. Open `project.godot` in the editor and press **F5**.

Built in playable parts (see the Prototype Roadmap in the Claude project). Current: **Part 8, title screen, characters and Nomad-2**.

F5 starts at the title screen (`scenes/title.tscn`). From there you reach Nomad-2 (`scenes/hub.tscn`), whose teleporter goes to the gym test room (`scenes/main.tscn`) and the test arena (`scenes/arena.tscn`, two wave rooms of real enemies). Any level can still be opened and run on its own with F6; it plays your last character.

## Part 1: movement
- **Seeker controller** (`scripts/player/player.gd`): camera-relative movement with snappy acceleration, a variable-height jump with coyote time and an input buffer, and a dash/dodge with i-frames, one air dash, and dash-jump (jump during a ground dash to keep momentum).
- **PSO-style camera** (`scripts/camera/camera_rig.gd`): a loose follow camera by default. It trails you like someone walking behind you with a camera: it doesn't turn when you turn, only swings around as you walk away from it, and backs up when you walk toward it. After you look up or down, it eases back to its default height. Set `follow_mode` to RIGID for a third-person shooter style camera. It avoids walls and supports right-stick and mouse look.
- **Lock-on** (R3): targets whatever is closest to where the camera faces, the Seeker strafes and orbits the target, flick the right stick to switch targets, and lock breaks when the target goes out of range. With nothing in range, R3 recenters the camera to where you were facing at the moment you pressed it.
- **Input map** (`scripts/autoload/input_setup.gd`): the full North Star control map, registered in code.

## Part 2: combat
- **Hand buttons** (`scripts/combat/combat_controller.gd`): X is your **primary hand** and Y your **off hand** (Part 8: menus list the primary hand first; a character's handedness, picked at creation, only decides which side the primary weapon is drawn on). Tap for a Normal attack, hold for a Hard attack.
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
- **Two-handed weapons are one item**, held in the primary hand and used by both buttons.
- **Target markers** (PSU-style, `scripts/ui/target_markers.gd`): rings on every enemy each hand's next attack would hit, shown for both hands at once: **blue** for the primary hand (X), **yellow** for the off hand (Y), **green** when both would hit the same enemy. You can see a Great Sword sweep catching two enemies, or a piercing Frost Lance lining up a row. The locked-on enemy also gets a larger red ring, dimmed when neither hand would reach it. Predictions include the attack's lunge and update while you hold RT (specials and second spells).
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
- **Jobs.** Each weapon lists the jobs that can use it (S Striker, R Ranger, I Invoker). Loadouts holding a weapon your job can't use say "job locked" and LB/RB skips them. The job is chosen at character creation and can't change afterwards (unlike PSU); the Debug tab has a switch for testing.
- **Special tags.** Found weapons can roll a tag line in tiers (PSO's specials: Heat → Fire → Flame → Burning, Dim → … → Hell, Draw → … → Gush, and so on). The tag names the weapon ("Flame Sword"), gives elemental lines their element, and unlocks the weapon's **RT special**: hold RT and press that hand. The special is a stronger first attack that costs LP and applies the tag: elemental status buildup, instant kill (never bosses), heal from damage, LP steal, EXP steal, HP cut, or the Charge line's x3 hit (paid in Oro, LP or HP).
- **Monster-type bonuses** (PSO's "% vs Native"): +5–30% damage vs one of the six monster types.
- **Drops.** Enemies give EXP and roll a drop where they fall: Oro, a consumable, or a weapon. Weapons come from your **emblem's pool**: each of the 12 emblems (Crimson, Orange, Gold, Green, Teal, Cyan, Blue, Purple, Magenta, Pink, White, Black; from name + race + gender + job, like PSO section IDs) favors two weapon families and carries its own **rares** (Emberfang, Glacier Maw, Stormcaller, Gravesong, Lifeleech Coil, Lumen Edge, Kingmaker). Oro (and Lumidium) is picked up by walking over it and drifts to you when you're close; everything else waits for **A** (there will be an inventory limit).
- **Heal and Cure** (Talisman, Totem, Staff): Heal restores HP, Cure clears every status. Both reach other Seekers within 10 m.
- **Consumables:** HP Gel, LP Cell, Cure Salt, Trap Scanner. D-pad left / up / right / down or 1 / 2 / 3 / 4.
- **Lumidium.** Crystal deposits in the arena break after 3 hits into Lumidium of their color. Carried Lumidium is lost when you die; stand on a **teleporter** pad to bank it.
- **Menu tabs** (LB/RB in the menu): Loadouts (the picker now lists found weapons first, greyed out if your job can't use them), Inventory, Character.
- **Save file:** `user://save.tres` holds the character, loadouts and inventory. It's written when the menu closes and at teleporters. Part 3's `loadouts.tres` is imported once.

## SyncAIDa (merged into Part 5)
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

## Part 6: magic, traps and hit chance
![Granfajro clearing a wave](docs/screenshots/magic_granfajro.png)

- **Hit chance (ATA vs EVA).** Seekers and enemies now have **ATA** (accuracy) and **EVA** (evasion). Every weapon hit rolls, PSO-style but kinder:
  - Hit % = 60 + effective ATA − EVA × 0.2 + streak, clamped to 5–100%.
  - Effective ATA = ATA × attack type × combo step. Combo steps 1 / 2 / 3 give ×1.0 / ×1.3 / ×1.69, so finishers almost always land.
  - Attack type: Normal ×1.0, Hard ×0.9, but **opening** a combo with a Hard is ×0.7. Specials ×0.8.
  - **Streak (Chrono Cross):** every hit that lands adds +4% to the next one in the combo, up to +12%.
  - Frozen targets have 30% less EVA, Shocked or Paralyzed 15% less.
  - **Spells, traps and hazards never miss.** Misses show "Miss".
  - Enemy EVA / ATA: Ooze 30 / 40, Drone 50 / 60, Hound 60 / 50, Umbral 70 / 55, Crawler 90 / 55, Sprite 140 / 60. EVA no longer lowers ranged damage; DEF covers both.
- **Hit reactions.** Light and sustained hits only interrupt an enemy if one hit takes half its max HP. Hard hits **push back and flinch** 90% of the time (bosses 25%), like PSO.
- **Magic** follows Grayson's spell grid: 6 elements × 7 spell types, plus Heal, Cure, Teleportal and Revive.
  - Spells live in the **casting item's slots**, set in the menu's **Spells** tab. One-handed items have 2 slots (tap / hold RT + tap), two-handed items 4 (X, Y, RT + X, RT + Y). Hold the button for a **Hard cast**: ×1.6 power and LP, a bit slower, rooted, 25% bigger area.
  - Damage uses PSO's formula: (SOL + technique power) / 5 × the item's spell power. Fire, Ice and Lightning use the real Foie / Barta / Zonde tables; Nature, Light and Dark are my best guesses in the same shape.
  - **Shapes:** single target (Fajro, Glacio's piercing line, Fulmo, Arbo's ground thorns, Lumo, Malbo), small bursts (ring, spear fan, chain, 30° and 60° cones, rolling gravity ball), large areas (Granfajro and friends; Granmalbo pulls enemies to the center), sustained channels (hold to keep casting), buffs (+STR / DEF / DEX / SOL / ATA / EVA), debuffs on enemies around you, and auras that pulse damage near you.
  - Single-target spells and Fire / Ice / Lightning / Nature / Light auras don't inflict status; everything else can. Pasmalbo can.
  - **Cure** clears one more status per level in order of annoyance (Slow, Burn, Poison, Blind, Drain, Shock, Paralyze, Freeze); level 9 also clears debuffs. **Teleportal** opens a pad to the ship (the gym for now). **Revive** waits for co-op.
- **Learning.** Each spell needs SOL to learn: its base, +20 a level for the first half, +40 after (Cure +25, Revive +30 / +60). Max spell level: **15**, Lumera 20, Coresian 10. **Invokers reach 30 in everything**, whatever their race. Strikers reach 5 levels less in buff spells, Rangers 5 less in debuff spells (a Human Ranger tops out at 10 in debuffs). Cure, Revive and Teleportal always reach their own max. New Seekers know Fajro, Glacio and Fulmo.

  | Max level | Striker (buffs) | Ranger (debuffs) | Invoker |
  |---|---|---|---|
  | Human | 15 (10) | 15 (10) | 30 |
  | Lumera | 20 (15) | 20 (15) | 30 |
  | Coresian | 10 (5) | 10 (5) | 30 |
  | Goluman (traps) | 15 | 15 | can't be Invokers |
- **Spell discs** drop from enemies (about 6% of kills). A disc you can read is learned; one you can't yet is stored (read it from the Spells tab later); one you already know is sold for Oro.
- **Race stat bonuses:** Humans +5 STR / DEX / SOL, Coresian +10 STR, Lumera +10 SOL, Goluman +10 DEX.
- **Goluman** can't cast and can't be Invokers. In return they **slowly regenerate HP** (0.5% of max HP a second). They set **traps** instead (Damage, Slow, Shock, Poison, Confuse, Freeze, Paralyze) from the same slots, learned with DEX. Up to 4 at once; they arm after 0.6 s and spring on the first enemy. Trap discs only drop for Goluman.
- **Level hazards.** Six hidden traps sit in the arena; each springs once. Each has a small device that can be locked on to and destroyed with any attack, but **only while the trap is visible**: after a **Trap Scanner** (D-pad down) reveals the room you're in, or always for Goluman. Hidden traps can't be hit by anything, area spells included.
- **Paralyze** is a new status: 2.5 s, no moving or acting.
- **Materials (PSO).** Each use permanently raises one stat by 2: Power (STR), Dex (DEX, new), Mind (SOL), Def (DEF), Res (RES, new), Evade (EVA), Accuracy (ATA, new), Luck (LCK), HP and LP (PSO's TP Material). Use them from the **Inventory** tab (Part 9; the Character tab is now Status).
  - PSO's limits: the eight stat materials share one limit: **Humans 275, Lumera and Coresian 175** (PSO's 250 / 150, +25 for the new materials), **Goluman 150**. HP and LP have their own 125 each.
  - Goluman can't use Mind Materials (no magic), and can use only 75 LP Materials.
  - They drop from enemies (about 2.4% of kills). Debug tab: +10 of each. Reset character forgets the ones used.
  - Accuracy has no other source yet; character levels and gear will add to it.

![Materials in the Character tab (Part 6; they are used from the Inventory now)](docs/screenshots/materials_character_tab.png)

![The Spells tab](docs/screenshots/magic_spells_tab.png)
![Hazards seen by a Goluman](docs/screenshots/magic_hazards.png)
![Trap Scanner: revealed traps and their devices, and the A prompt](docs/screenshots/traps_scanned.png)

## Part 7: armor
![The Armor tab](docs/screenshots/armor_tab.png)

- **One set per character** (like PSO and PSU): **Head**, **Torso** and **Legs**. Head and Legs take the place of PSO's barrier.
- **Light and Heavy** pieces. **Invokers wear Light only**; Strikers and Rangers wear either.
  - Light: Field, Weave, Lumen and Aether sets (Frame / Hood / Treads).
  - Heavy: Plate, Bastion, Core and Titan sets (Armor / Helm / Greaves).
  - Heavy pieces give more DEF; Light pieces give more EVA and RES. Head and Legs are about 40% of a Torso.
  - **Job-locked sets:** Core is Ranger-only, Titan Striker-only, Aether Invoker-only.
- **Drops roll like PSO frames:** a DEF / EVA bonus within the piece's range, and **augment slots**: a Torso has 0-4, a Head or Legs piece 0-1.
- **Augments** (PSO's units) are items that go in and out of slots freely:
  - Stat augments I / II / III: STR, DEX, SOL, DEF, RES, EVA, ATA, LCK (+5 / 10 / 15), HP (+20 / 40 / 60), LP (+10 / 20 / 30).
  - Element Wards I / II: 10% / 20% less damage of that element.
  - Monster Guards: 15% less damage from one enemy type (Beast, Mutated, Synthetic, Dark, Alchemic, Light).
  - **Double-Heavy augment** (rare): any slot, and two Heavy one-handed items are allowed. It replaces Part 3's menu toggle.
  - Resistances stack up to 75%.
- **Rares** break the usual rules: Ironclad Shell (Goluman only), Veil of the Nomad (Invoker, +10 SOL, Light / Dark resist), Huntress Treads (female only, +8 DEX), Warden's Crown (Striker, +10 STR, **2 slots**), Pathfinder Treads (+5 ATA, **2 slots**).
- **Drops:** armor from about 5% of kills (the **Blue emblem** finds it twice as often), augments about 2.4%. 4% of armor drops are rare.
- Every Seeker starts in a **Field Frame** with one slot (old saves get one too). Armor you can no longer wear after a race, gender or job change comes off.
- **Dash cooldown:** 5 s between dashes (shown next to the chain pips on the HUD).

## Part 8: title screen, characters and Nomad-2
![Character select](docs/screenshots/title_select.png)

- **Title screen** (gamepad: A or Start accepts, B goes back): **Continue** (your last character), **Character select**, Quit.
- **Every menu recovers focus for the controller:** if nothing is focused (say, after clicking the window to bring it forward), the first A or d-pad press focuses the menu's default button instead of doing nothing. Character creation starts on Race, so the d-pad isn't caught in the name box.
- **4 character slots**, like PSO. Each slot is a whole save (character, loadouts, inventory, spells, armor, SyncAIDa) in `user://characters/slot_N.tres`. X on a slot asks, and a second X deletes it. Your Part 5-7 save moves into slot 1 the first time.
- **Primary and off hand:** loadouts read primary hand (X) first, then off hand (Y), everywhere. The code uses the same names (`Hand.PRIMARY` / `Hand.OFF`, `Loadout.primary` / `off_hand`), so **saves from before this change don't keep their loadouts**: make a new character. Creation asks for the **primary hand** (right or left): a left-handed Seeker holds the primary weapon on the left side, still on X. The Debug tab can change it for testing.

![Loadouts read Primary (X) first](docs/screenshots/loadouts_primary.png)
![A left-handed Seeker: Sword (X) on the left, Shield (Y) on the right](docs/screenshots/left_handed.png)

- **Starter kit:** every new character carries a Sword, a Pistol and a Wand, plus 2 Trap Scanners; only loadout 1 is filled (X Pistol, Y Sword).
- **Lock-on:** when the locked target dies, the lock moves to the next closest one.
- **Character creation:** name (type it, or "New name" on a gamepad), race, gender, job and starter SyncAIDa, with a preview of the race and job rules and the emblem the choices make. Goluman can't pick Invoker. Creating saves the slot and drops you into Nomad-2.
- **Nomad-2** (`scenes/hub.tscn`, built by `tools/build_hub.gd`): the lobby. Its counters (guild, bank, shops, armorer) are placeholders. Its **teleporter asks where to go**: the gym or the test arena (B or "Stay here" cancels; step off and back on to ask again).
- The gym has a pad back to Nomad-2, and the arena's exit now returns there too. Teleportal opens a pad to Nomad-2.
- **Saving:** every teleport, closing the menu, quitting to the title (Options tab) and closing the window save the character's slot.

![Creating a character](docs/screenshots/title_create.png)
![The Nomad-2 teleporter](docs/screenshots/hub_teleporter.png)

## Part 9: the pack, the satchel and the menu
![The Inventory tab](docs/screenshots/inventory.png)

PSO's item pack with PSU's palettes (Grayson, 2026-11-09).

- **The pack holds 30 slots** of items and gear, PSO's size. Everything counts, including weapons on your palettes and the armor you wear (augments slotted into armor are part of it and don't). **Stacks hold 10 and take one slot**: HP Gel, LP Cell, Cure Salt, Trap Scanner and every material.
- **The satchel holds Oro (up to 999,999) and carried Lumidium**, outside the pack, so a pile of Lumidium never stops you picking up a rare. The satchel carries **15 Lumidium at most, all colors together**. Carried Lumidium is still lost if you fall, until a teleporter banks it.
- **Picking up takes only what fits.** With 7 HP Gels, a stack of 4 gives you 3 and leaves 1 on the ground. With the pack full, items stay where they are and the prompt says why ("pack full", "10 max", "satchel full"). Oro and Lumidium are still picked up by walking over them.
- **Dropping (trading, making room):** anything in the pack can be dropped from the Inventory tab, and so can Oro and Lumidium, **in part**: pick the amount and it lands as **one stack** in front of you (4 Lumidium is one pickup). What you drop always waits for A, Oro and Lumidium included, so walking over it doesn't take it back. As in PSO, equipped gear can't be dropped: take it off the palette (or take the armor off) first.
- **Palettes are filled from the pack**, like PSU. The palette picker lists only the weapons you carry (no more free copies of every base weapon), leaving out the one already in the other hand. A new character's palette 1 holds the pack's own Pistol and Sword. The Debug tab can add any weapon, rares included, to the pack.
- **Older saves:** weapons on a palette that weren't in the inventory are added to the pack when the save loads. A save already over 30 slots keeps everything but can't pick up more until it's under.
- **Cards and Thrown Daggers pick their targets from a 40° cone** (20° either side of the aim; it was 100°, and they fired too wide). The Burstbow keeps the PSO shotgun's 100°. **The Grenade's three-in-a-row finisher fans its three grenades over 50°** (was 30°), and all three land as far out as the target.

**The menu (Start / Tab)** now has six tabs: **Inventory, Equip, Status, SyncAIDa, Options, Debug** (LB / RB). Equip has three sections, **Palette, Spells, Armor** (LT / RT, or the buttons along the top).

![Equip: Palette](docs/screenshots/equip_palette.png)
![Debug](docs/screenshots/debug_tab.png)

## Part 10: shops, the bank and the Guild
![The curatives shop](docs/screenshots/shop_curatives.png)

Nomad-2's counters work (Grayson, 2026-11-09). Walk up to a counter and press **A**. Each counter pauses the game and works like PSO's: the clerk's commands on the left, the list in the middle, and the details and offer on the right. A picks (command → item → confirm), B steps back, Start leaves. Stacks get an amount (- / + / All).

- **Shops** (east wall): **Weapons**, **Armor** (pieces and augments) and **Curatives**. 1 Oro = 1 Meseta.
  - **Curatives use PSO's tool shop prices** for the matching item: HP Gel 50 (Monomate), LP Cell 100 (Monofluid), Cure Salt 300 (Sol Atomizer, cures everything), Trap Scanner 100 (Trap Vision).
  - **Weapons and armor are priced on a PSO-like scale**, from the item's own numbers. PSO's exact shop formula isn't used. A weapon costs 200 + 25 × base damage (Pistol 500, Sword 700), ×1.3 if two-handed, with more for a special tag (+50% per tier) or a monster bonus. Torso armor costs 300 × tier², Heavy +20%, Head / Legs 40%, plus per slot and per bonus point. Augments cost 1,000 / 3,000 / 8,000 by grade.
  - **Stock changes every time you arrive in Nomad-2**, as PSO's arms shop did each time you entered Pioneer 2. Every listing can be bought again and again. The Weapons shop has 10 common weapons, some with low-tier tags or monster bonuses. The Armor shop has 8 tier 1-2 pieces and 4 grade I augments. Never rares.
  - **Any shop buys anything from your pack for 1/8 of its price** (my pick). Discs sell for 20 Oro per level and materials for 100 each. Palette weapons and worn armor have to come off first.
- **Bank** (PSO's Check Room, west wall): **200 item slots and up to 999,999,999 Oro** per character, the numbers on the Ephinea PSO wiki. Deposit and withdraw items, and Oro in both directions. A bank stack holds up to 99 of one item (my pick; the pack's stacks hold 10). Banked Lumidium is shown here too.
- **Guild** (west wall, PSO's Hunter's Guild): pick a quest and accept it. The hub teleporter then lists **"Quest: …"** first. Do it, come back and **Report** for the reward. You can take one quest at a time, and **Abandon quest** drops it. The quest and its progress stay in your save until you report or abandon it. There are three quests for now, all in the test arena:
  - **Arena Trial:** clear every room in one trip. 600 Oro.
  - **Hound Cull:** defeat 6 Grub Hounds. 300 Oro.
  - **Crystal Survey:** bank 10 Lumidium at teleporters. 400 Oro.
  - A banner says "Quest complete: report to the Guild" when it's done.
- The pause menu doesn't open over a counter or the teleporter's list.

![The bank](docs/screenshots/bank.png)
![The Guild](docs/screenshots/guild.png)

## Travel
Nomad-2's teleporter goes to the gym or the arena. The gym has pads to the arena and back to Nomad-2. The arena's exit pad at the far end of Room B stays dark until every room is cleared, then takes you back to Nomad-2. Every trip loads the level fresh. **Press A on a pad** to use it (it banks carried Lumidium and saves first); standing on it does nothing.

**Arena doors (PSO-style):** the way into a room stays open, and the way on is locked ("LOCKED") until the room is cleared. Clearing the last room wakes the exit pad.

## Menu (Start / Tab)
Fully usable with a gamepad: d-pad or left stick moves, **A** accepts, **B** goes back (closes a list or the actions, then the menu), **LB / RB** switch tabs, **LT / RT** switch the Equip sections, Start closes.

| Tab | What's there |
|---|---|
| Inventory | The pack (30 slots: `[P1,3]` marks palette weapons, `[W]` worn armor) and the satchel (Oro, carried Lumidium). The focused item is described on the right. **A** lists what you can do with it: equip a weapon to the current palette (primary or off hand), take it off every palette, wear or take off armor, slot an augment into a free slot, use a consumable or material, read a disc, drop (with an amount for stacks, Oro and Lumidium) |
| Equip: Palette | 8 PSU-style palettes (X / Delete unequips the highlighted hand, Y / Shift+Delete clears that palette), the weapon picker (your pack's weapons by group; job-locked weapons are grey and A on one says which job needs it), Double-Heavy status |
| Equip: Spells | Casting items on your palettes → their slots → your learned spells (A picks, X clears a slot, B goes back). Also lists stored discs to read |
| Equip: Armor | Head / Torso / Legs and their augment slots → armor or augments in your pack (A wears or slots, X takes off or empties, B goes back), totals and resists |
| Status | Name, race, gender, job, hand, emblem, EXP, HP / LP, every stat with everything applied, materials used, spell level caps, drop pool |
| SyncAIDa | Starter choice, pairing, feeding (consumables from the pack, Lumidium from the bank), active Sync Burst |
| Options | Save and quit to the title screen, the control reference. Settings will go here |
| Debug | Everything for testing, in one tab that can be removed with one line (`LoadoutMenu._build`): name / race / gender / hand edits and the job switch, level select, refills, Oro, filling consumable stacks, materials, every armor piece and augment, Lumidium (bank or satchel), add any weapon to the pack, learn tools, Infinite LP, **No pack limit**, free feeding, debug readout, hitboxes, resets, clear all palettes |

Show hitboxes (Debug tab, on by default) also draws enemy melee hit areas on the ground: faint during the windup, bright when the strike lands, with the exact reach and arc the hit uses. The debug readout is off by default. Select / F3 or the Debug tab turns it on.

## Controls
| Action | Gamepad | Keyboard / mouse |
|---|---|---|
| Move | Left stick | WASD |
| Camera | Right stick | Mouse / arrows |
| Jump | A | Space |
| Dash / dodge (5 s cooldown) | B | Shift |
| Lock on / recenter | R3 | Q / middle mouse |
| Switch target | Flick right stick | Sweep mouse |
| Hand attacks (tap / hold) | X / Y | Left / right click |
| Cast (tap) / Hard cast (hold) | X / Y with a casting item | Left / right click |
| Spell slots 2 / 4 (hold while casting) / special | RT | E |
| Use HP Gel / LP Cell / Cure Salt / Trap Scanner | D-pad left / up / right / down | 1 / 2 / 3 / 4 |
| Activate a teleporter / pick up an item (when the prompt shows; otherwise jump) | A | Space |
| Sync Burst | L3 | R |
| Cycle palettes | LB / RB | Z / C |
| Block / powerstance | LT | F |
| Menu | Start | Tab |
| Toggle debug panel | Select | F3 |

Click to capture the mouse, Esc to release it.

## Tuning
Every feel value is an exported variable or a `.tres` field. Edit them in the Inspector, even while the game is running (use the Remote tree).

- **Player**: `move_speed`, `acceleration`, `jump_height`, `time_to_peak`, `dash_distance`, `dash_duration`.
- **CameraRig**: `follow_mode`, `leash_radius`, `follow_speed`, `pitch_return_delay`, `pitch_return_speed`, `shoulder_offset`, `default_pitch_deg`.
- **Player/Combat**: `hold_threshold` (tap vs hold), `swap_hand_buttons` (X on the off hand), soft-aim range and angle, `show_hitboxes`.
- **Each attack** in a weapon `.tres`: `move_speed_scale`, `face_movement`, `sustained_tick`, `duration`, `active_start`/`active_end` (hit timing), `window_open`/`window_close` (combo timing), `damage_mult`, `lp_cost`, lunge, hitbox size, projectile settings.

## Physics layers
1 = world, 2 = player, 3 = enemy. The camera, lock-on line-of-sight checks and navmesh bake only use layer 1.

## Known limits (deliberate for now)
- No animation: capsules, with weapons swung by simple tweens. Melee hitboxes show as red boxes (`show_hitboxes`).
- Normal attacks fire when the button is released, so tap and hold can share one button.
- Only the arena has Lumidium nodes, and every Guild quest happens there until real levels exist. Shop stock has no character-level tiers yet (armor stops at tier 2).
- Weapon grinding, armor and augments aren't in yet. Untagged weapons have no RT special.
- EXP is counted but there are no levels yet.
- Revive has nothing to revive until co-op. Teleportal goes to the gym until the ship exists.
- Party bursts (several Seekers firing together) wait for co-op. SyncAIDa have no feeding cooldown and no personalities yet.
- The game pauses while the menu is open. Co-op will need a non-pausing version.
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
godot --headless --path . --script res://tests/magic_test.gd
godot --headless --path . --script res://tests/materials_test.gd
godot --headless --path . --script res://tests/armor_test.gd
godot --headless --path . --script res://tests/flow_test.gd
godot --headless --path . --script res://tests/inventory_test.gd
godot --headless --path . --script res://tests/services_test.gd
```

- `movement_test.gd`: walking, stopping, jump height, short hops, dash distance, the 5 s dash cooldown, lock-on, orbiting, recentering, camera height return.
- `combat_test.gd`: tap and hold, 3-step rhythm combos, PSO pistol cadence, rooted vs mobile attacks, Dervish Blades combo and spin, step damage bonuses, too-early and too-late presses, mixed-weapon steps, LP, projectiles, spells and Shift, elemental weakness, dash cancel, death and respawn, navmesh bake, chase and patrol pathing.

- `loadout_test.gd`: one-Heavy and two-handed rules, the augment, cycling past empty and invalid loadouts, LT mode per loadout, shield / arms-up / two-handed block percentages, parry and stagger, no block from behind, Deflect, dash dodge, Heavy Shield shove, blocking a real Shooter bolt, powerstance twin hits and twin combos, twin pistols, the powerstance option, and the menu opening and pausing.

- `targeting_test.gd`: default buttons (X = primary hand); Sword marks one of two side-by-side enemies and Great Sword marks both, and real swings hit exactly what was marked; blue / yellow / green per hand, and using one hand doesn't hide the other hand's marker; the Pistol and Fire Bolt mark the first enemy in line and Frost Lance marks the whole line; lock-on shows the large ring and hides it on release, and the lock moving to the next closest target when the locked one dies.

- `enemy_test.gd` (in the arena): all six monster types, DEF / RES math, hit chance (ATA vs EVA, combo steps, Hard openers, the streak, statuses lowering EVA, spells never missing), every status (Burn ticks, Slow then Freeze, Shock, Blind, Drain healing its source), a Hound pathing to you and hitting for its damage, Hard hits pushing and flinching (light hits never interrupting), a Frozen enemy standing still, a Drone keeping its distance and shooting, Ward reflecting a Drone bolt into the Drone, and a full three-wave room (doors close, waves follow each other, doors open), and PSO doors (the exit locked until the room is cleared).

- `loot_test.gd` (in the arena): the full weapon list and every emblem's favored families, job locks, the 7 rares covering all 10 emblems, drop rates and emblem weighting, tag tiers, tag names and RT specials, the +30% vs Beast bonus, Gush / Mind / King's / Hell effects (and Hell never killing a boss), the Charge special paying Oro, Shotgun pellets, a Grenade arc and its blast (and its prediction), the Boomerang lock chain, the Gigarang hitting out and back, the Thrown Daggers finisher, Machine Pistol automatic fire, the Staff's four spells, Heal and Cure, EXP and drops, pickups and an HP Gel, a Lumidium node breaking, losing carried Lumidium on death, a teleporter deposit, and a save round-trip, Oro picked up on touch while items wait for A, and teleporters needing A.

- `syncaida_test.gd` (in the arena): no SyncAIDa until a starter is chosen, the four starters at level 5 in their stat and the instant bonus, level-10 forms following stats rather than job, feeding from inventory and bank, the stat math, the Seeker stat bonus following the paired SyncAIDa, every evolution (job, strongest stat, top two, Prime), burst unlocks, the 200 cap, the gauge from damage dealt and taken, L3 firing Lumen Nova (in range only), Aegis Pulse in both directions, Mending Bloom, feeding from the menu, and a save round-trip.

- `menu_test.gd` (in the arena): drives every tab with real joypad button and trigger events: Start opens, starter pick with the d-pad and A, re-pressing the paired SyncAIDa, feeding, RB / LB tab switching with focus following (the six tabs in order), the Palette picker (only the pack's weapons, B backs out, a job-locked weapon explains itself, A equips), LT / RT switching the Equip sections, the Debug tab's New name, dropdowns and tools, Options, B closing the menu, and switching levels.

The tests always use a fresh save and never write yours.

`tools/build_starter_weapons.gd`, `tools/build_enemies.gd` and `tools/build_arena.gd` regenerate the weapons, enemies and arena with their default values (this overwrites any edits).

- `magic_test.gd` (in the arena): the spell book (46 spells, 7 traps, grid names), PSO technique power and LP tables, SOL requirements, level caps by race and job (buff / debuff caps, Invokers 30, special spells), Goluman rules, casting from loadout slots (empty and unlearned slots), the damage formula, every damage shape reaching the enemies it should, holding a sustained spell, buffs scaled by support power, debuffs around you, auras, Heal, Cure 9 keeping buffs, Teleportal, trap placing, springing and the 4-trap limit, hazards visible only to Goluman, trap devices (untouchable while hidden, even by area spells; the Trap Scanner on D-pad down revealing only the current room; destroyed by a spell once revealed), discs (learn, store, read later, sell), disc drop rates, and the Spells tab driven by a gamepad.

- `materials_test.gd` (in the arena): the ten materials, the 275 / 175 / 150 shared limits and the separate HP / LP 125, Goluman restrictions (no Mind, 75 LP), STR / DEX / RES / ATA / max HP gains, Goluman +10 DEX and HP regen, Invokers refused as Goluman, the learn-at-level-1 and Infinite LP tools (and ATA improving hit chance), the limits refusing more, the save keeping materials used and re-applying them once, drops and pickups, using one from the Inventory tab with a gamepad, and Reset character forgetting them.

- `armor_test.gd` (in the arena): the armor book (24 tiered pieces, 5 rares, slot rules, job-locked sets), drop rolls (0-4 / 0-1 slots, DEF / EVA bonus), the starter Field Frame, who can wear what (Invokers Light only, job, race and gender locks), swapping pieces with their augments, stat augments, Fire Wards and a Beast Guard in real hits, Double-Heavy from an augment, unwearable armor coming off after a race change, drop rates (Blue emblem 2x), pickups, the save, old saves, and the Armor tab with a gamepad.

- `flow_test.gd`: the old single save moving into slot 1, the title screen with a gamepad (main menu, character select, B back, Start, focus surviving a background click and coming back after it's lost, in the title, the teleporter picker and the pause menu), creation (Goluman can't be Invokers, the preview), the new character's starter kit (Sword, Pistol, Wand; only loadout 1 filled), saved to its slot with its SyncAIDa and Field Frame, Nomad-2's teleporter (pauses, lists the gym, arena and stay; B cancels), travel to the gym and back and to the arena with saves on the way, quitting to the title, Continue, deleting with a double X, and full slots. It uses its own folder, so real characters are never touched.

- `inventory_test.gd` (in the arena): a new Seeker's pack (Sword, Pistol, Wand; palette 1 holding the pack's own Pistol and Sword), worn armor and palette weapons taking slots, stacks of 10 in one slot, a stack pickup taking only what fits and leaving the rest, the 30-slot limit (items refused, Oro still taken, existing stacks still filling), the 15-Lumidium satchel, and the Inventory tab with a gamepad: equip to a palette, equipped and worn gear refusing to drop, use, wear, a material, dropping part of a stack, Oro and Lumidium as one pickup each, dropped Oro and Lumidium waiting for A, and the palette picker listing only the pack.

- `services_test.gd` (in Nomad-2, then the arena): the five clerks and their prompts, PSO's curative prices, weapon prices, stock (sizes, no rares, armor tiers, rerolled per visit), buying stacks with an amount, gear, armor and augments with a gamepad, not enough Oro, a full pack, selling back at 1/8 (palette weapons refused, stacks by amount), Start leaving without the pause menu, B backing out, the bank (200 slots, items, stacks, Oro both ways, kept in the save), and the Guild (accept, one at a time, reporting early, the teleporter listing the quest first, defeats, room clears and banked Lumidium completing quests, the reward, abandoning).
