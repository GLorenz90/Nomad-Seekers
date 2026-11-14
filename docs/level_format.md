# Nomad's Seekers level format (version 2)

The contract between the game and the level editor. The editor writes this
format and the game builds levels from it. The code that reads, writes and
checks it is `addons/seeker_data/level_data.gd` (`LevelData`); the navmesh,
rooms and hitboxes come from `addons/seeker_data/level_nav.gd` (`LevelNav`).
Neither depends on the game's classes, so the editor uses the same two files
(copy them across when they change).

**Version 2** (Grayson, 2026-11-13): levels are built only from placed pieces.
There are no generated rooms or corridors. Every piece is a **floor**, an
**obstacle** or **intangible**. Rooms and corridors are **areas of the
navmesh**, split by **room boundaries**, and the size follows the room
count. Version 1 levels aren't read any more.

The worked example is `levels/test_1/demo/`, written by
`tools/build_demo_level.gd`. It uses something from every layer, and
`tests/level_test.gd` plays it.

## Folders, areas and sessions

```
levels/
  forest_1/            one folder per area (Grayson, 2026-11-12)
    glade/             a level
    ravine/            another level
  forest_2/
  forest_boss/         boss areas get their own folder too
quests/
  foremans_favour/     a quest folder made in the editor (see Quests)
  demo_run.json        an older single-file quest
```

- A teleporter, quest or menu can send a Seeker to **`area:forest_1`**. The
  game picks one level from that folder the first time it's needed in a
  session, and keeps that pick until the player quits to the title
  (`Maps.pick`, `Maps.new_session`). In co-op everyone shares the same picks.
- A destination can also be a level folder (`res://levels/forest_1/glade`), a
  scene (`res://scenes/arena.tscn`) or `hub` (Nomad-2).
- `user://levels/` holds your own levels (and the workshop's, later). They can
  be played from the Debug tab but never join the area rotation.
- **Playtest:** run the game with `-- --level=<folder>` to go straight into a
  level with the last played character, skipping the title screen, or with
  `-- --quest=<quest folder>` to start that quest's session on Nomad-2 (it
  replaces that character's current quest).
- **Quest sessions** (see Quests): while a quest is on, the picks are rolled
  for it (an area it names a level for gets that level) and Nomad-2's
  teleporter offers only the quest's areas.
- **Exports:** levels are plain files, so an export preset must include
  `levels/*` and `quests/*` in its non-resource include filter.

## A level

```
my_level/
  level.json        meta
  map.json          Layer 1: Map
  interaction.json  Layer 2: Interaction
  combat.json       Layer 3: Combat
  assets/           glb / gltf models (and their textures), material images
  licenses/         optional: license files for what the level uses
```

`licenses/` holds plain text or document files (`.txt`, `.md`, `.pdf`,
`.rtf`, `.html`) that the builder keeps with the level: a model pack's
License.txt, a note from an artist. Nothing in the level refers to them, no
license is required, and the game never reads them; they travel with the
level when it's exported or shared.

Each layer is its own file, so the editor can switch between layers freely.
**A level never holds code.** Godot `.tres` / `.tscn` files can carry scripts
that run when they're loaded, so levels use only JSON and plain assets. The
game builds a level only from its own whitelisted pieces, and models load
through `GLTFDocument`, which can't carry scripts.

Shared conventions:
- **Positions** are `[x, y, z]` in metres, in world space. `y = 0` is the
  usual floor height and -Z is "north".
- **Rotation** is either `"yaw"` (degrees around Y) or `"rot": [x, y, z]`
  (degrees, Godot's rotation order). Map pieces, walls, boundaries and
  decorations use `rot`; objects and enemies use `yaw`. Imported models take
  `"scale": [x, y, z]`; built-in shapes take `"size"` instead.
- **Colors** are `[r, g, b]` or `[r, g, b, a]`, from 0 to 1.
- **Every** area, piece, wall, boundary, decoration, object, button group,
  dialogue and enemy has an `"id"` that is unique across the whole level. The layers refer
  to each other only by id.

### level.json

```json
{"format": 2, "name": "Glade", "area": "forest_1", "author": "", "description": ""}
```

`"kind": "nomad2"` marks a quest's Nomad-2 additions (see Quests): no rooms,
start or exit of its own. Anything else is an ordinary level (`"level"`).

There's no size to choose: it follows from the number of **rooms**
(`LevelData.size_for`). Corridors never count (Grayson, 2026-11-12). Any
other count (2–4, or over 25) fits no size and can't be published.

| size | rooms |
|---|---|
| `arena` | 1, and no corridors |
| `small` | 5–9 |
| `medium` | 10–14 |
| `large` | 15–19 |
| `huge` | 20–25 |

### map.json (Layer 1: Map)

```json
{
  "grid": 4.0,
  "lighting": {"preset": "dusk", "sun_energy": 1.0, "ambient_energy": 1.0,
               "exposure": 1.0, "fog_density": 0.0, "sun_angle": [-50, 35], "tint": [1, 1, 1]},
  "start": {"pos": [0, 0.1, 4], "yaw": 0},
  "assets": [{"id": "rock_big", "file": "assets/rock_big.glb",
              "surface": "obstacle", "hitbox": "convex", "category": "decoration", "folder": "Rocks"}],
  "materials": [{"id": "flagstone", "name": "Flagstone", "albedo": "assets/flagstone.png", "color": [1, 1, 1],
                 "tile": 4.0, "roughness": 0.9, "folder": "Stone"}],
  "folders": {"prefab": ["Buildings/Ruins"]},
  "pieces": [{"id": "floor_1", "asset": "builtin:box", "pos": [0, -0.5, 0], "size": [16, 0.5, 16],
              "color": [0.4, 0.45, 0.4], "surface": "floor"},
             {"id": "stairs_1", "asset": "builtin:stairs", "pos": [4, 0, -3.5], "size": [4, 1, 3],
              "steps": 5, "material": "flagstone", "surface": "floor"},
             {"id": "curve_1", "asset": "builtin:curved_wall", "pos": [-3, 0, -4], "size": [6, 0.8, 0.4],
              "bend": 90, "surface": "obstacle"},
             {"id": "rock_1", "asset": "rock_big", "pos": [3, 0, 2], "rot": [0, 30, 0], "scale": [1, 1.5, 1]},
             {"id": "grass_1", "asset": "grass", "pos": [5, 0, 1], "surface": "intangible",
              "animation": {"preset": "sway", "amount": 1.0, "speed": 1.0}}],
  "walls": [{"id": "pen", "pos": [-6, 0, -30], "size": [0.4, 2, 4], "rot": [0, 0, 0], "blocks": "seekers"}],
  "boundaries": [{"id": "boundary_1", "pos": [8, 0, 0], "rot": [0, 90, 0], "size": [4, 3]}],
  "areas": [{"id": "room_1", "kind": "room", "name": "Landing", "seed": [0, 0.2, 0],
             "color": [0.43, 0.64, 0.95], "polys": [[[-7.6, 0.2, -7.6], [7.6, 0.2, -7.6], [7.6, 0.2, 7.6]], ...]}],
  "decorations": [{"id": "lamp", "asset": "builtin:light", "pos": [0, 3, 0], "energy": 1.5, "range": 10}]
}
```

- **lighting**: `preset` is one of `day`, `dusk`, `overcast`, `night`,
  `cave`, `interior`. The game clamps each slider: `sun_energy` 0.3–1.6,
  `ambient_energy` 0.5–1.5, `exposure` 0.8–1.3, `fog_density` 0–0.03. The
  tint is held to 0.6–1 per channel, and the sun stays 10–90° up. A room
  meant to be dark uses the Darkness hazard instead.
- **assets**: imported models. `file` must be inside the level folder and end
  in `.glb` or `.gltf`. `surface` and `hitbox` are the defaults for every copy
  of it. (Older levels may have `license` and `author` here; they're ignored.
  Licenses live in `licenses/`.)
  `category` (`decoration` or `prefab`) and `folder` (names joined with `/`)
  only organise the editor's list; the game ignores them.
- **materials**: paint for pieces, built by `LevelMaterials.build` (shared by
  both repos; its header lists every key). All keys but `id` are optional.
  - Images (`.png`, `.jpg`, `.jpeg`, `.webp`, inside the level folder):
    `albedo` (colour), `normal`, `roughness_map`, `metallic_map`, `ao_map`
    (ambient occlusion), `emission_map` and `height_map`.
  - `roughness_map`, `metallic_map` and `ao_map` each read one channel
    (`roughness_channel` etc.: `red`, `green`, `blue`, `alpha` or `gray`).
    glTF packs occlusion, roughness and metallic into one image (red, green,
    blue), so the same file can serve all three.
  - `color` tints the colour image. `roughness` and `metallic` (0–1)
    multiply their maps. `normal_strength` 0–4, `ao_strength` 0–1.
  - `emission` (a color) and `emission_energy` (0–16) make it glow; with an
    `emission_map` and no color, the map glows in its own colors.
  - `transparency`: `none`, `cutout` (pixels below `alpha_cutoff` are
    dropped and both sides show: leaves, fences) or `alpha` (blended, times
    `opacity`). Transparency is only visual: solid pieces still collide.
  - `mapping`: `world` (default) projects the images in world space
    (triplanar), so stretching a shape doesn't stretch them; `tile` is how
    many metres one copy covers (0.1–100, default 2). `uv` uses the mesh's
    own UVs, repeated `uv_repeat` times: right for a model's own textures, and
    the only mapping where `height_map` (with `height_scale` 0–16) shows,
    since Godot can't draw height maps triplanar.
  - `name` and `folder` are for the editor.
- **folders**: the editor's empty folders, per category (`decoration`,
  `prefab`, `material`). The game ignores them.
- **pieces**: everything the level is built from. `asset` is an asset id, or
  one of `builtin:box`, `builtin:cylinder`, `builtin:ramp`, `builtin:stairs` or
  `builtin:curved_wall` (each takes `size` and `color`; the pivot is the bottom
  centre, ramps and stairs rise toward -Z).
  - `builtin:stairs` takes `steps` (1–64, default 8): each step is
    `size.y / steps` tall. Seekers climb about 0.4 m, so a flight with taller
    steps breaks the navmesh at it, which is how a builder finds the right pitch.
  - `builtin:curved_wall` takes `bend` in degrees (up to 360 either way,
    default 90; 0 is a plain box). `size.x` is its length along the curve,
    `size.z` its thickness; a positive bend curves the ends toward -Z.
  - `material` (optional): a material id. It replaces a shape's `color`, and
    overrides an imported model's own materials.
  - `surface` (on the piece, else its asset's, else `obstacle`):
    **`floor`**: solid, and the navmesh is built on top of it.
    **`obstacle`**: solid, and blocks the navmesh; nothing walks on top of it
    or inside it.
    **`intangible`**: no collision, ignored by the navmesh. Only intangible
    pieces may have an `animation` (`sway`, `bob`, `spin`, `pulse`,
    `sweep`; `amount` 0–2, `speed` 0.1–4), so collision and the navmesh stay put.
  - `hitbox` (on the piece, else its asset's, else `concave`): how a solid
    piece's collision is made from its own meshes with Godot's shape tools
    (`LevelNav.hitbox`). **`concave`** follows every triangle (exact, static
    only). **`convex`** wraps each mesh in one hull (faster, but fills in
    arches). Built-in boxes and cylinders always get their exact primitive
    shape. Scale is baked into the shapes. The editor shows the same hitbox
    the game builds.
- **walls**: invisible walls. `blocks` is `all`, which also blocks the
  navmesh, or `seekers`, which uses physics layer 5: enemies walk through it
  and the navmesh ignores it, so it can keep players in an arena while
  enemies still come in.
- **boundaries**: room boundaries. Each is an invisible vertical plane
  (`size` [wide, tall], in its local X and Y; `pos` is the middle of its
  bottom edge) that cuts the navmesh when rooms are worked out. It never
  blocks anything in the game. Put one across every doorway or gap between
  two rooms; it has to close the opening, or the navmesh goes round it.
- **areas**: the rooms and corridors, worked out by the editor and saved with
  the level. The editor bakes the navmesh a second time with every boundary
  cut in; each separate piece of that navmesh (2 m² or more) is an area
  (`LevelNav.assign_areas`). `kind` is `room` or `corridor`. `seed` is a
  point on the area's navmesh: it keeps the area's id, name, kind and color
  when the level changes. `also` lists extra seeds whose pieces count as part
  of the same area (a room split by a pit). `polys` are the area's navmesh
  polygons (convex, world space). The game uses them to tell which room a
  point is in (`LevelData.area_at`): combat starts when a Seeker enters a
  room's polygons, and the Trap Scanner reveals the traps in your room.
- **decorations**: built-in effects only: `builtin:fireflies` (`size`,
  `amount`, `color`), `builtin:light` (`color`, `energy` 0–3, `range`
  1–20 m) and `builtin:searchlight` (sweeps by default).

#### The navmesh

`LevelNav.bake` builds it the same way in the editor and the game. It's sized
for a Seeker (`LevelData.NAV`: radius 0.4 m, 1.8 m tall, steps up to 0.4 m,
slopes up to 45°, 0.2 m cells). It's baked from floors and obstacles, and from
invisible walls that block everyone. Afterwards anything standing on top of
an obstacle, or inside one, is dropped. The game sets its navigation map to
the same cell size.

### interaction.json (Layer 2: Interaction)

```json
{
  "objects": [ ... ],
  "button_groups": [{"id": "plates", "buttons": ["plate_a", "plate_b"], "once": true}],
  "dialogues": [{"id": "intro", "lines": [{"speaker": "Commander Brandt", "text": "..."}],
                 "choices": [{"id": "yes", "text": "On my way."}]}],
  "flags": {"lever_pulled": false},
  "rules": [ ... ]
}
```

**Objects** (`"type"`; every object takes `id`, `pos` and `yaw`/`rot`):

| type | fields | wiring actions it takes |
|---|---|---|
| `door` | `size` [4.2, 4, 0.6], `start` `open`/`closed`, `label`, `open_when_cleared` (room id), `shut_during_combat` (room id) | `open`, `close`, `toggle` |
| `teleporter` | `destination` (see Folders), `label`, `requires_clear` (every room cleared), `dormant` (asleep until woken) | `wake`, `disable`, `toggle` |
| `lumidium_depot` | — | — |
| `lumidium_node` | `color` (`fire`…`raw`), `yield` 1–10 | — |
| `box` | `contents`: `random`, `oro` or a consumable id | — |
| `trap` | `kind`: `damage`, `slow`, `shock`, `poison`, `confuse`, `freeze`, `stun` | `disable` |
| `button` | `mode` `press`/`floor` | — |
| `hazard` | `kind` `poison_mist`/`darkness`, `active`, `zones`: [{`pos`, `size`}] in world space | `enable`, `disable`, `toggle` |
| `trigger_zone` | `size`, `once` (default true), `whole_party` (waits for every Seeker on the map), `enabled` | `enable`, `disable` |
| `platform` | `points` (world positions of its top; ≥ 2), `size`, `mode` `loop`/`ping_pong`/`step`, `speed` 0.5–8 m/s, `wait` s, `running`, `color` | `start`, `stop`, `toggle`, `step` |
| `bridge` | `length` 1–64, `width`, `extended`, `speed`; it slides out along its forward (-Z) | `extend`, `retract`, `toggle` |
| `person` | `name`, `look` {`color`, `height` 0.5–4, `model` (an imported asset id)}, `talk`, `show_from`, `show_until`, `route` {`points` ≥ 2, `mode` `loop`/`back_and_forth`, `speed` 0.2–6, `wait` s}, `walking` | `show`, `hide`, `walk`, `stop`, `set_talk`, `escort`, `stop_escort` |

- **People** (2026-11-13): A on them starts their dialogue. `talk` is a list
  of `{"dialogue", "from_step", "flag", "flag_is", "story"}`: the last entry
  that holds is what they say. An entry holds when its `from_step` is done
  (if it has one) and its `flag` (a quest flag, or a story flag with
  `"story": true`) is `flag_is` (default true). `show_from` / `show_until` (quest
  step ids) keep them around only from that step being done until that step
  is done; outside a quest only people with neither set are there. A person
  can't be hurt, and enemies ignore them. An escort follows the nearest
  Seeker and comes along to the quest's other maps.

- **Door shortcuts**: `open_when_cleared` opens the door when that room's
  combat ends. `shut_during_combat` closes it while that room fights, then
  opens it again. Anything else is done with rules.
- **Buttons**: a group fires when all of its buttons are down. With fewer
  Seekers than floor plates, extra plates latch (Part 11's rule). A button
  that isn't in a group is a group of one.
- **Platforms** carry Seekers; for now enemies don't ride them. **Bridges**
  connect the navmesh with a NavigationLink3D that only works while the
  bridge is fully out.
- **Rooms with combat** take `start_combat`.

**Rules** say: when an event happens, if the conditions hold, do the actions.

```json
{"id": "r1",
 "when": {"event": "combat_ended", "source": "room_2"},
 "if": [{"check": "flag", "flag": "lever_pulled", "is": true}],
 "do": [{"action": "open", "target": "door_3"},
        {"action": "wait", "seconds": 1.5},
        {"action": "start_dialogue", "target": "brandt_call"}],
 "once": true}
```

| event | source | value (optional match) |
|---|---|---|
| `level_started` | — | |
| `entered` | trigger zone id | |
| `party_present` | trigger zone id (`whole_party`) | |
| `pressed` | button group id, or a lone button's id | |
| `combat_started` | room id | |
| `wave_cleared` | room id | wave number (1 = first) |
| `combat_ended` | room id | |
| `enemy_defeated` | enemy placement id | |
| `health_below` | enemy placement id | percent: fires once HP is at or below it |
| `dialogue_ended` | dialogue id | choice id |
| `box_broken` | box id | |
| `node_broken` | Lumidium node id | |
| `timer_done` | timer id | |
| `flag_set` | flag name | |
| `talked` | person id | |
| `step_completed` | quest step id | |

Conditions (`"check"`): `flag` (`flag`, `is`); `difficulty_at_least`
(`value`: `normal`, `hard`, `very_hard`, `ultimate`; tiers aren't built yet,
so this is always `normal`); `party_at_least` (`value`: Seekers on the map);
`quest_active` (`value`: quest id); `quest_step` (`step`, `is`: `done`
(default), `current` or `not_done`); `quest_flag` (`flag`, `is`);
`has_item` (`item`, `color` for Lumidium, `amount`, `is`: the Seeker who last
talked to someone, else the first Seeker here); `escort_near` (`target`
person, `distance` m, `is`); `story_flag` (`flag`, `is`).

Actions (`"action"`): the object actions in the table above (with
`target`), plus:
- `start_dialogue` (`target`: dialogue id). Dialogues play one at a time; a
  second one waits its turn.
- `set_flag` (`flag`, `value`)
- `start_timer` (`id`, `seconds`)
- `give_item` (`item`: `oro`, a consumable id, or `lumidium` with `color`;
  `amount`). It drops at each Seeker's feet.
- `complete_objective` (`key`: completes the current `event` step with that
  id; kept for Part 13a quests)
- `complete_step` (`step` or `target`: a step id). Only the current step
  completes; steps go in order.
- `set_quest_flag` (`flag`, `value`): lasts the whole quest session, on every
  map
- `set_story_flag` (`flag`, `value`): kept in every party member's save
  after the quest
- `take_item` (`item`, `color`, `amount`): from the Seeker who talked (check
  `has_item` first; nothing is taken unless they have it all)
- `set_talk` (`target` person, `dialogue`): what they say from now on
- `banner` (`text`)
- `wait` (`seconds`; holds back the rest of the rule's actions)

Rules run once by default (`"once": false` repeats them).

### combat.json (Layer 3: Combat)

```json
{
  "rooms": [{"room": "room_2", "start": "enter", "start_delay": 0.8, "wave_delay": 1.0,
             "waves": [{"enemies": [ {placement}, ... ]}, ...]}],
  "free": [ {placement}, ... ]
}
```

- `start`: `enter` starts the fight when a Seeker walks in. `event` leaves it
  to the wiring (`start_combat`), for example after a button or a
  dialogue.
- Each wave starts when the previous wave's last enemy dies. When no waves
  are left, the room reports `combat_ended`.
- `room` is an area id (map.json). The fight's trigger is the area's
  navmesh polygons, so it covers exactly the floor of the room.
- `free`: enemies outside waves, such as in corridors. They're there when the
  level loads, don't respawn and lock no doors.

A **placement**:

```json
{"id": "hound_1", "enemy": "grub_hound", "pos": [0, 0, -12], "yaw": 180,
 "spawn_delay": 0.5,
 "wander": true, "wander_radius": 3.0,
 "limited_chase": true, "chase_radius": 10.0,
 "aggro": "normal", "alert": false}
```

- `enemy`: a file name from `data/enemies/` (`grub_hound`, `mutated_crawler`,
  `sentry_drone`, `umbral_eye`, `caustic_ooze`, `lumen_sprite`). A level
  can't change an enemy's stats or attacks.
- `spawn_delay`: seconds after its wave starts (decimals allowed).
- `wander` + `wander_radius`: idles by wandering within that distance of its
  spawn point. Otherwise it stands still.
- `limited_chase` + `chase_radius`: gives up once its target is farther than
  that from its spawn point, walks home without healing, and can be pulled
  again once it's back.
- **Invalid:** both on with `chase_radius` < `wander_radius`. The publish
  check refuses it, and the game uses the wander radius for both.
- `aggro`: `short` (×0.6), `normal`, `long` (×1.5) of the enemy's own range.
- `alert`: comes straight for the Seekers when it appears. Defaults to true
  in waves (like PSO) and false in `free`.

## Quests

Quests are sessions, like PSO's (Grayson 2026-11-13). Accepting one at the
Guild starts a quest session: every map closes, the area picks roll again,
Nomad-2 reloads with the quest's people, and the teleporter offers only the
quest's areas. Its steps are done in order. Reporting (or abandoning) ends
the session and starts a fresh free-play one. The whole party must be on
Nomad-2 to start or end one. In co-op the leader's quest is the party's:
only the leader accepts or abandons, progress anywhere counts for the party,
and every Seeker gets the reward.

A quest is a folder in `quests/` (made in the level editor):

```
quests/foremans_favour/
  quest.json           the quest
  nomad2/              what it adds to Nomad-2: a level folder, kind "nomad2"
  levels/survey_site/  levels only this quest uses
```

```json
{"format": 1, "id": "foremans_favour", "title": "The Foreman's Favour",
 "client": "Petram Solidus, foreman", "text": "The briefing...", "reward": 800,
 "steps": [{"id": "talk_foreman", "type": "event", "goal": "Talk to the foreman."},
           {"id": "cull", "type": "defeat", "enemy": "grub_hound", "count": 6},
           {"id": "clear_ravine", "type": "clear", "area": "forest_1"},
           {"id": "bank", "type": "bank_lumidium", "count": 10}],
 "areas": [{"quest_level": "survey_site", "name": "Survey site", "opens_after": "talk_foreman"},
           {"area": "forest_1", "name": "The Forest", "opens_after": "cull"},
           {"area": "forest_2", "level": "res://levels/forest_2/ravine", "opens_with": "found_key"}],
 "endings": [{"if": [{"flag": "gave_crew", "is": true}], "reward": 1000,
              "sets": {"foreman_friend": true}, "text": "The crew struck a rich seam..."},
             {"text": "The survey office filed the readings..."}],
 "requires": [{"flag": "met_foreman", "is": true}]}
```

- **Steps** (up to 32), in order. `type`:
  - `event`: completed by wiring (`complete_step` with its `id`), for talking
    to someone, handing something over, reaching a spot.
  - `defeat`: `enemy` × `count`.
  - `clear`: every wave room of one of the quest's areas in one trip
    (`area`: an area name or quest level; blank for any of them).
  - `bank_lumidium`: `count`.
- **Areas** (up to 12) are where Nomad-2's teleporter goes during the quest:
  `{"area": "forest_1"}` (a fresh pick from that area's folder),
  `{"area": "forest_1", "level": "res://levels/forest_1/glade"}` (that level
  of the area, always), or `{"quest_level": "survey_site"}` (the quest's own
  level). `name` is shown on the teleporter.
  - **Opening in order** (2026-11-13): `opens_after` (a step id) and / or
    `opens_with` (a quest flag) keep an area off the teleporter until the step
    is done / the flag is on. A banner says when one opens. Use them for set
    maps done in order, with steps between (talk to someone to open the
    next map).
- **Endings**: told at the Guild when the quest is reported. The first
  ending whose `if` flags all hold is told (`story: true` checks a story
  flag instead of a quest flag); put one with no `if` last as the default.
  Its `reward`, if given, replaces the quest's; its `sets` become **story
  flags** for every Seeker in the party.
- **Story flags** (`SaveData.story_flags`) stay with the character after the
  quest: choices that change later quests. Set them with an ending's `sets`
  or the `set_story_flag` action; check them with `story_flag` (in any
  level's wiring), a person's talk line, an ending's `if`, or a quest's
  `requires` (the Guild only lists the quest while they hold). Setting one
  sets it for the whole party.
- **nomad2/** is laid over Nomad-2 (`HubLevel`), which itself is fixed: its
  pieces and decorations are added (floors and obstacles join Nomad-2's
  navmesh), and its Interaction layer runs (people, dialogue, wiring). Its
  start, lighting and combat are ignored. `tools/export_nomad2.gd` writes the
  copy of Nomad-2 the editor draws underneath.
- **Wiring** in Nomad-2's additions and in the quest's levels can use the
  quest: `step_completed`, `quest_step`, `quest_flag`, `complete_step`,
  `set_quest_flag`, and the people actions (see Layer 2). A level's
  `stop_escort` / `escort_near` may name a person from the quest's Nomad-2;
  they come along as escorts.
- The party's quest is kept in the leader's save (`SaveData.quest`:
  `id`, `step`, `progress`, `flags`, `escorts`). Continuing a character with
  a quest starts its quest session.

Single files `quests/*.json` (Part 13a) still work: one `objective`
(`clear`, `defeat`, `bank_lumidium` or `event` with its `key`) and one `scene`
read as a one-step quest with one area:

```json
{"id": "demo_run", "title": "Demo Run", "objective": "event", "key": "demo_boss",
 "goal": "Beat the boss.", "scene": "area:test_1", "place": "The demo level", "reward": 500}
```

## The publish check

`LevelData.validate(Enemy.known_ids())` lists the problems that block
publishing:
- the room count fits no size, or an Arena has corridors
- an area has no navmesh polygons saved (it wasn't saved by the editor)
- an animated piece isn't intangible, or a surface / hitbox is unknown
- there's no start, or no exit (a teleporter with a destination)
- an id is missing or used twice
- something points at an id that doesn't exist
- a piece or decoration uses an asset that isn't imported
- an object type, event, condition or action is unknown
- a combat room has no waves, or an empty wave
- an enemy is invalid, or is one the game doesn't have

The editor checks more before export, since it has the navmesh: the start
stands on it, every enemy stands on it (in a room or corridor), every room
can be walked to from the start (bridges and moving platforms count as
joining their two ends), and every boundary actually splits something.
