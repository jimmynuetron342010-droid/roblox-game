# Architecture (Phase 1)

This is the layout you get in Roblox Studio, either by opening `build/SoulEater.rbxl` or by syncing with Rojo (`default.project.json`). Every script is server-authoritative. Clients only send *requests* and draw the results.

## Explorer hierarchy

```
ReplicatedStorage
├─ Modules                      (src/shared — required by server and client)
│  ├─ WeaponConfig              12 weapons: dimensions, palettes, movesets, attacks, placeholders
│  ├─ WeaponBuilder             builds / spawns / equips / holsters / destroys weapon models
│  │  ├─ BladeKit, ChainKit     shared geometry helpers (crescent blades, linked chains)
│  │  └─ Models/                one builder per weapon (MakaScythe … ArachneSpider)
│  ├─ VFXController             effect runtime (pools, emitter hosts, one render loop)
│  │  └─ Effects/               the 10 weapon effects + WeaponImpact + Ability visuals
│  ├─ VFXConfig                 per-effect tuning, quality tiers, camera shake, textures
│  ├─ ProjectileController      one projectile model for server simulation and client visuals
│  ├─ Animation/                AnimatorCore, AnimationLibrary, RigMath (IK), ChainSimulator, PosePreview
│  ├─ Config/                   races, rarities, stats, abilities, roles, magic, mastery, quests,
│  │                            enemies, lore codex, student options, build rules, game constants
│  ├─ Core/                     StatCalculator, WeightedRoll, Validate, Net, Signal, Maid,
│  │                            GeometryKit, BuildModifiers, AbilitySlots, Util
│  ├─ Race/                     race features + student appearance on characters
│  └─ Rig/PreviewRig            block R15 rig used by UI previews and offline tests
├─ Remotes                      every RemoteEvent / RemoteFunction (declared in the project file)
├─ WeaponAssets                 optional: your MeshParts named "<WeaponId>_<Group>" replace parts
└─ VFXAssets                    optional: your ParticleEmitters replace built-in templates

ServerScriptService
└─ Server
   ├─ Main (Script)             boots 16 services: Init (wire) → Start (connect), each isolated
   ├─ Core/                     RemoteGuard (rate limits), FXBroadcast, Notifier, GameEvents
   ├─ Data/                     SessionStore (session-locked DataStore), ProfileCore, MockDataStore
   ├─ Race/RaceRollLogic        pure roll + keep/replace logic (unit tested)
   ├─ World/EnemyRig            enemy models
   └─ Services/                 Data, Status, Stat, Progression, Map, Character, Weapon, Race,
                                Mastery, Quest, Loadout, Partner, Madness, Combat, Ability, Enemy

ServerStorage
├─ RBX_ANIMSAVES/<Weapon>Rig/   baked KeyframeSequences (Idle, Walk, Run, every attack) to edit/publish
└─ AnimationRigs/               R15 rigs holding each weapon, for the Animation Editor

StarterPlayer
├─ StarterPlayerScripts
│  └─ Client
│     ├─ Main (LocalScript)     boots controllers, mounts the HUD and registers every screen
│     ├─ Controllers/           ClientState, InputController, WeaponClient, VFXClient,
│     │                         AnimationController, PerceptionController
│     └─ UI/                    UIController, HUD, Theme, Components, Icons, Viewport,
│                               Notifications, DamageNumbers, MobileControls, Screens/*
└─ StarterCharacterScripts
   └─ Health                    empty override: health regeneration is server-controlled
```

### Changes to the requested structure (and why)

| Requested | Here | Reason |
|---|---|---|
| `ReplicatedStorage.Modules.WeaponConfig/WeaponBuilder/VFXController/ProjectileController` | same names, inside `ReplicatedStorage.Modules` | Same as asked. `WeaponBuilder` and `VFXController` are folders-with-`init` so their sub-modules (models, effects) sit next to them. |
| `ReplicatedStorage.WeaponAssets`, `VFXAssets`, `Remotes` | same | Remotes are declared in `default.project.json`, so they exist before any script runs and a client can never race the server creating them. |
| `ServerScriptService.WeaponService`, `CombatService` | `ServerScriptService.Server.Services.WeaponService` / `CombatService` | All 16 services are ModuleScripts booted by one `Main` script in a fixed order. This avoids require cycles and double starts, and logs a clear error if one service fails. |
| `StarterPlayerScripts.WeaponClient`, `VFXClient` | `StarterPlayerScripts.Client.Controllers.WeaponClient` / `VFXClient` | Same idea on the client: one `Main` LocalScript boots every controller after `ClientState` has the profile. |
| — | `Animation/`, `Config/`, `Core/` | Race rolling, stats, mastery, UI and procedural animation need shared, testable modules. |
| — | `ServerStorage.RBX_ANIMSAVES`, `AnimationRigs` | Editable animation saves, generated from the procedural clips (see [ANIMATION.md](ANIMATION.md)). |

## Four independent systems

A character is the combination of four separate choices. Each one is validated on its own, and `Config/BuildRules` rejects contradictory combinations:

| System | Where it comes from | Config |
|---|---|---|
| **Origin (race)** | rolled at the Soul Altar | `RaceConfig`, `RarityConfig`, `MasteryConfig` |
| **Combat role** | chosen (creator / Skills) | `CombatRoleConfig` — Meister is a *role*, never a race |
| **Weapon** | unlocked by level, equipped in Inventory | `WeaponConfig` |
| **Magic school** | Witch / Sorcerer origins only | `MagicConfig` |

Build rules:

- **Demon Weapon** origins can't take the Meister role; they use Partner Weapon or Technician.
- **Magic schools** are available to Witch and Sorcerer origins only.
- **Changing origin** re-checks the build and notifies the player of anything it had to change.
- **Kishin** is an endgame questline and transformation, never a roll.
- **Black Blood** is a quest-unlocked status.

## Stat pipeline

Everything that changes a number goes through `Core/StatCalculator`:

```
final = base(level) × (1 + capped additive bonus) × Π(multiplicative buffs)  → clamp(AbsoluteMin, AbsoluteMax)
additive bonus: summed from race + mastery + role + weapon mastery + buffs
                above SoftCap only 50% counts, never above HardCap (per stat, StatDefinitions)
damage:         (1 + additive damage pool, soft 60% / hard 100%) × buffs (≤ ×1.4), total ≤ ×2.6
defense:        reduction = Defense / (Defense + 100 + 5·level), capped at 60%
```

`StatService` recomputes a player's stats whenever their profile, buffs or partner change. It sends the full breakdown (sources and cap state) to the Stats screen.

## Remotes (all validated server-side)

| Remote | Kind | Rate limit (per s / burst) | Server handler |
|---|---|---|---|
| GetProfile | Function | 2 / 4 | DataService |
| CreateStudent | Function | 1 / 3 | CharacterService (validates every field, filters the name with TextService) |
| RollRace / ResolveRaceRoll | Function | 2 / 3 | RaceService → RaceRollLogic (idempotent request ids, pending choice, cooldown, currency) |
| EquipWeapon | Function | 4 / 6 | WeaponService (ownership, cooldown, draw/holster, Tsubaki forms) |
| SetLoadout | Function | 3 / 5 | LoadoutService (role/school legality, not in combat) |
| UpdateSettings | Function | 3 / 6 | LoadoutService.CleanSettings (whitelisted keys, types, ranges) |
| PartnerAction | Function | 2 / 4 | PartnerService (invite / accept / leave) |
| AttackRequest | Event | 12 / 12 | CombatService (alive, not staggered, combo step, cooldowns, stamina) |
| AbilityRequest | Event | 6 / 8 | AbilityService (slot resolution, cost, cooldown) |
| MovementRequest | Event | 12 / 20 | StatService (dash, sprint, perception) |
| ProfileChanged, StatsChanged, Notify, CombatFX, DamageFeedback | Event (server → client) | — | replication / visuals only |

`RemoteGuard` wraps every handler with a per-player token bucket and `pcall` isolation. Failures return a consistent `{ Ok = false, Reason = … }`.

## Boot order

Server: Data → Status → Stat → Progression → Map → Character → Weapon → Race → Mastery → Quest → Loadout → Partner → Madness → Combat → Ability → Enemy. Each service gets `Init(registry)` first, then `Start` runs in its own protected thread.

Client:

1. `ClientState` and the input, VFX, animation, weapon and perception controllers start.
2. `UIController` starts, the HUD and screens are mounted, and mobile controls are added.
3. New players are sent straight to "Create Your Student".
