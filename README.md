# Nomad's Seekers: Prototype Part 1 (Movement Core)

Godot 4.7, 3D, Forward+. Open `project.godot` in the editor and press **F5**.

## What's in this part
- **Seeker controller** (`scripts/player/player.gd`): camera-relative movement with snappy acceleration, a variable-height jump with coyote time and an input buffer, and a dash/dodge with i-frames, one air dash, and dash-jump (jump during a ground dash to keep momentum).
- **PSO-style camera** (`scripts/camera/camera_rig.gd`): over-the-shoulder spring-arm camera that avoids walls, plus right-stick and mouse look.
- **Lock-on** (R3): targets whatever is closest to where the camera faces, the Seeker strafes and orbits the target, flick the right stick to switch targets, and lock breaks when the target goes out of range. With nothing in range, R3 recenters the camera behind you.
- **Input map** (`scripts/autoload/input_setup.gd`): the full North Star control map, combat buttons included, registered in code.
- **Test room** (`scenes/main.tscn`): grid blockout with 0.5 m stairs, a 20° ramp, a 3–7 m gap course, pillars, a low tunnel and five target dummies (two of them patrol).

## Controls
| Action | Gamepad | Keyboard / mouse |
|---|---|---|
| Move | Left stick | WASD |
| Camera | Right stick | Mouse / arrows |
| Jump | A | Space |
| Dash / dodge | B | Shift |
| Lock on / recenter | R3 | Q / middle mouse |
| Switch target | Flick right stick | Sweep mouse |
| Toggle debug panel | Select | F3 |

Click to capture the mouse, Esc to release it.

## Tuning
Every feel value is an exported variable. Select **Player** or **CameraRig** in `main.tscn` and edit them in the Inspector, even while the game is running (use the Remote tree).

Useful starting points:
- `move_speed`, `acceleration`, `deceleration` set how snappy the Seeker feels.
- `jump_height`, `time_to_peak`, `time_to_land` shape the jump arc. Faster falls feel weightier.
- `dash_distance`, `dash_duration`, `dash_exit_speed_scale` control the dash and the length of a dash-jump.
- `shoulder_offset` (set to 0 for a centered PSO camera), `distance`, `pivot_height` frame the camera.

## Physics layers
1 = world, 2 = player, 3 = enemy. The camera and lock-on line-of-sight checks only collide with layer 1.

## Known limits (deliberate for Part 1)
- No animation: a capsule with a visor that squashes on jump, land and dash.
- No step-up for small ledges yet. The 0.5 m stairs are meant to be jumped.
- Input is bound to all devices. Per-player devices come with couch co-op.
