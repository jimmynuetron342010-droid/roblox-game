# Installing in Roblox Studio (Phase 5)

There are two ways to get the game into Studio. Both give the same Explorer tree, described in [ARCHITECTURE.md](ARCHITECTURE.md).

## Option A — open the ready-made place (fastest)

1. Download `build/SoulEater.rbxl` from this repository.
2. In Roblox Studio: **File → Open from File…** and pick `SoulEater.rbxl`.
3. Press **Play** (F5). The server builds the Death City map. Then the "Create Your Student" screen opens.
4. To publish: **File → Publish to Roblox As…**.

## Option B — sync the source with Rojo (for development)

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) 7.x and the Rojo Studio plugin.
2. In the repository folder run `rojo serve default.project.json`.
3. In Studio, open an empty Baseplate, open the **Rojo** plugin and press **Connect**.
4. Rojo creates every folder and script listed below. Edits in your editor sync live.
5. To rebuild the place file yourself, run `rojo build default.project.json -o build/SoulEater.rbxl`.

## Where everything goes (exact Explorer locations)

| Explorer location | Contents |
|---|---|
| `ReplicatedStorage › Modules` | All shared ModuleScripts. Key ones: `WeaponConfig`, `WeaponBuilder`, `VFXController`, `VFXConfig`, `ProjectileController`. Folders: `Animation`, `Config`, `Core`, `Race`, `Rig` |
| `ReplicatedStorage › Remotes` | RemoteFunctions: `GetProfile`, `CreateStudent`, `RollRace`, `ResolveRaceRoll`, `EquipWeapon`, `SetLoadout`, `UpdateSettings`, `PartnerAction`. RemoteEvents: `ProfileChanged`, `Notify`, `AttackRequest`, `AbilityRequest`, `MovementRequest`, `CombatFX`, `DamageFeedback`, `StatsChanged` |
| `ReplicatedStorage › WeaponAssets` | (optional) your MeshParts, see [BLENDER_WORKFLOW.md](BLENDER_WORKFLOW.md) |
| `ReplicatedStorage › VFXAssets` | (optional) your ParticleEmitters, see [VFX.md](VFX.md) |
| `ServerScriptService › Server` | `Main` (Script) plus `Core`, `Data`, `Race`, `World`, `Services` |
| `ServerStorage › RBX_ANIMSAVES` | baked animation saves per weapon |
| `ServerStorage › AnimationRigs` | R15 rigs holding each weapon |
| `StarterPlayer › StarterPlayerScripts › Client` | `Main` (LocalScript) plus `Controllers` and `UI` |
| `StarterPlayer › StarterCharacterScripts` | `Health` (empty — health regen is handled by the server) |

If you copy scripts by hand instead of using Rojo: `.server.luau` files are **Scripts**, `.client.luau` files are **LocalScripts**, and every other `.luau` file is a **ModuleScript**. A folder that contains `init.luau` becomes a ModuleScript of the folder's name, and its other files become its children.

## Settings the project expects

The project file already sets these. If you build the place by hand, set them yourself:

| Setting | Value | Why |
|---|---|---|
| `Players.CharacterAutoLoads` | **false** | The server spawns each character once the map exists and the profile has loaded |
| `Players.RespawnTime` | 4 | |
| Game Settings → Avatar → **Avatar Type** | **R15** | Procedural animation, IK and weapon mounts need R15. R6 characters keep default animations. |
| `StarterGui.ResetPlayerGuiOnSpawn` | false | The UI survives respawns |
| `StarterPlayer.CameraMaxZoomDistance` | 40 | |
| `Lighting.Technology` | Future | Night lighting, neon glow on effects |
| `Workspace.Gravity` | 196.2 | |

### Saving data

- **Live servers:** use DataStores with session locking, so a profile is never loaded on two servers at once.
- **In Studio:** if *Game Settings → Security → Enable Studio Access to API Services* is **off**, the game automatically falls back to an in-memory store. Nothing is saved after you stop, and a warning is printed. Turn it on to test real saves; the place must be published first.
- **Studio-only debug grants:** `GameConfig.Debug` gives 25 rolls, 5000 souls, level 15 and all weapons, so every system can be tried right away. Published servers ignore these grants.

## Replacing the placeholders with your own assets

Every asset id in the project is the clearly marked placeholder `rbxassetid://0`. The game never invents real ids, and placeholders are silently skipped, so everything works without assets. To add yours:

| What | Where |
|---|---|
| Weapon swing / hit / equip / shot sounds | `WeaponConfig.Weapons.<Id>.Sounds` |
| Reveal stingers, UI clicks | `src/client/UI/UISound.luau` (`UISound.Ids`) |
| Effect and ability sounds | `VFXConfig` (sound fields) |
| Uploaded weapon Idle / Walk / Run | `WeaponConfig.Weapons.<Id>.AnimationIds` (all three must be set) |
| Uploaded attack / gesture clips | `AnimationLibrary.UploadedIds[<ActionName>]` |
| Mesh weapons | MeshParts in `ReplicatedStorage.WeaponAssets` named `<WeaponId>_<Group>` |
| Particle textures | ParticleEmitters in `ReplicatedStorage.VFXAssets` named like the templates (`Spark`, `Dust`, `Smoke`, …) |

To publish the baked animations, see [ANIMATION.md](ANIMATION.md).

## Using your own map

`MapService` builds a complete test map at server start. This includes:

- **Areas:** the plaza and spawn, the Academy, the graveyard district, the madness fields, the Pharaoh's Tomb and the PvP arena.
- **Interactables:** the Soul Altar, the Race Index lectern, the training yard and the weapon rack.

To use your own map, set `MapService.Enabled = false`, then add:

- **Proximity prompts** with the attribute `OpensUI` = `RaceRoll`, `RaceIndex` or `Inventory`.
- **Enemy spawn markers** under `Workspace.Map.EnemySpawns`, with attributes `EnemyType`, `MinLevel` and `MaxLevel`.
- **A part named `PvPZone`** where PvP is allowed.
