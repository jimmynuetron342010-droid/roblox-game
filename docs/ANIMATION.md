# Animation

Every weapon animates **without uploaded assets**. A procedural animator drives the R15 body and the weapon each frame. The same clips are also baked into editable `KeyframeSequence`s, so you can tweak them in Studio's Animation Editor, publish them, and swap them in.

## How the procedural animator works (`Modules/Animation`)

`AnimatorCore` runs per character on every client (`AnimationController`). It writes `Motor6D.Transform` *after* Roblox's Animator (in `Stepped`), in three blended layers:

1. **Locomotion**
   - **Idle:** breathing, a slow weight shift and a little head motion.
   - **Loose walk:** hip sway, torso counter-twist, a bounce on each step and a slight lean into the movement. The arms swing on springs, so they lag and settle naturally.
   - **Run:** a longer stride and more lean, with the weapon carried closer to the body.
   - **Airborne:** arms rise.
2. **Hold style** (`AnimationLibrary.Holds`), one per weapon type:

   | Hold style | Weapons |
   |---|---|
   | `ScytheTwoHand` | Maka & Soul scythes |
   | `CompactScythe` | Ragnarok |
   | `SwordOneHand` | Soul Eater Blade, Tsubaki blade |
   | `ShurikenHold` | Star shuriken |
   | `DualPistols` | Liz & Patty |
   | `ChainWeapon` | Tsunami |
   | `HeavyFlail` | Gevurah |
   | `Kusarigama` | Tsubaki chain forms |
   | `DrillArm` | Patty drill |
   | `ArmWeapon` | segmented arm |
   | `SpiderBack` | Arachnid rig |

   Each hold gives the weapon's frame in torso space. Both hands follow with **two-bone IK** (`RigMath.SolveArm`) onto the weapon's `Grip` and `SupportGrip`. If a target is beyond arm reach, the weapon slides back into reach (`RigMath.ReachableGrip`), so it never floats off the hand.
3. **Actions:** attacks and gestures as keyframes on a 0..1 timeline, stretched to each attack's gameplay duration and blended in and out. The catalog: ScytheSlashA/B, ScytheHeavy, ScytheSlam, DashSlash, SwordSlashA/B, SwordThrust, SwordMultiHit, SwordHeavy, StarSlashA/B, Throw, ThrowMulti, ChainSwingA/B, ChainSlam, FlailSwing/B, FlailSlam, PunchA/B/C, PunchSlam, DashPunch, PistolShotR/L, PistolCharged, DrillThrust, DrillGrind, DrillDash, SpiderStrikeA/B, SpiderSweep, SpiderSlam, CastSpell, Roar, GolemSlam, Pulse, Heal, Blink, Hurt. Trails switch on exactly during each action's trail window.

The weapon's own moving parts stay physical and procedural:

- **Chains:** verlet simulation with a floor, whipped outward on chain strikes.
- **Drill bit:** spins while drilling.
- **Pistol slides:** recoil when firing.
- **Spider legs:** step and strike.
- **Segmented arm:** extends.

Holstering fades the layer out, letting Roblox's default `Animate` script take over smoothly. Distant characters update less often (full rate within 70 studs, 20 Hz to 180 studs).

## Baked, editable animations (`ServerStorage.RBX_ANIMSAVES`)

`tools/export_animations.luau` samples the real `AnimatorCore` on an R15 rig holding each weapon. It writes the results as KeyframeSequences:

```
ServerStorage
├─ RBX_ANIMSAVES
│  ├─ MakaScytheRig/ Idle · Walk · Run · Scythe_SlashA · Scythe_SlashB · Scythe_SlashC · Scythe_Heavy · Scythe_DashSlash
│  ├─ TwinPistolsRig/ Idle · Walk · Run · Gun_ShotR · Gun_ShotL · Gun_Rapid · Gun_Charged
│  └─ … one folder per weapon and per Tsubaki form (14 folders, 102 clips)
└─ AnimationRigs
   └─ MakaScytheRig … R15 rigs with the weapon attached (pose names match these rigs)
```

- **Loops:** Idle, Walk and Run have `Loop = true`. They are made seamless with a one-cycle crossfade, and a test checks that the first and last keyframes match.
- **Attacks:** each attack is non-looping, and its length equals the attack's gameplay duration.
- **Pose tree:** follows the R15 Motor6D tree (`HumanoidRootPart › LowerTorso › UpperTorso › RightUpperArm › …`). Hand-held weapons add a `Handle` pose under the hand, so the weapon's `MountJoint` is animated too.
- **Priorities:** Idle, Movement and Action.

Re-generate after changing animation data: `lune run tools/export_animations.luau [weaponFilter]`.

### Editing and publishing a clip in Studio

1. Drag a rig from `ServerStorage › AnimationRigs` into `Workspace`, e.g. `MakaScytheRig`.
2. Open **Avatar → Animation Editor** and select the rig. The editor lists the saves stored under `ServerStorage › RBX_ANIMSAVES › MakaScytheRig`; load the clip you want (for example `Scythe_Heavy`).
   - If your Studio version doesn't list them, you can still publish a `KeyframeSequence` directly: right-click it → **Save to Roblox…**.
3. Edit the keyframes, then use **⋯ → Publish to Roblox** and copy the asset id.
4. Put the id where the game looks for it:
   - **Locomotion:** `WeaponConfig.Weapons.MakaScythe.AnimationIds = { Idle = "rbxassetid://…", Walk = "rbxassetid://…", Run = "rbxassetid://…" }`. All three must be set.
   - **Attacks and gestures:** `AnimationLibrary.UploadedIds.ScytheHeavy = "rbxassetid://…"`. The key is the attack's `Animation` name from `WeaponConfig.Attacks`.

### How uploaded clips are used at runtime

- **Locomotion:** when a weapon has all three ids, `AnimationController` loads them on the Humanoid's `Animator` while the weapon is drawn and blends Idle, Walk and Run by speed.
- **Attacks:** an uploaded attack plays as an `Action2` track, speed-matched to the attack's duration.
- **What stays procedural:** while tracks drive the body, `AnimatorCore.MuteBody` stops it from writing body joints. Chains, drill bit, slides and spider legs still move procedurally, and combat timing and trail windows still come from the action definitions.
- **Placeholders:** ids left as `rbxassetid://0` mean the procedural clip is used.

## Previewing poses without Studio

`scripts/render.sh [weaponFilter] [pose]` renders any weapon on an R15 rig in `Idle`, `Walk`, `Run`, `<Action>@t` or `M1@t`/`Z@t`/`X@t`. It uses the real WeaponBuilder and AnimatorCore and writes to `tests/renders/out`. See [TESTING.md](TESTING.md).
