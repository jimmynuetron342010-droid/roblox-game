# Testing, checklist and troubleshooting (Phase 6)

## Automated checks (run outside Roblox)

| Command | What it proves |
|---|---|
| `scripts/check.sh` | Rojo sourcemap, **luau-lsp** type analysis against the Roblox API definitions, **selene** lint, **StyLua** formatting |
| `scripts/test.sh` | **114 unit/integration tests** (Lune). See the breakdown below. |
| `scripts/playtest.sh` | **headless play-test of the whole game**: server session, every effect and the full UI (below) |
| `scripts/render.sh [weapon] [pose]` | renders weapons in a character's hands (`Idle`, `Walk`, `Run`, `M1@0.45`, `Z@0.5`, `ScytheHeavy@0.6`, …) to PNG |
| `lune run tools/export_animations.luau [weapon]` | re-bakes the editable animation saves |

### Unit and integration tests (`tests/specs`)

- **race_rolls:**
  - weights sum to exactly 100%;
  - the distribution matches the table over 1,000,000 rolls (chi-square);
  - every probability is shown correctly.
- **race_roll_logic:** idempotent request ids (no double charge); pending keep/replace; cooldown; currency; mastery kept on replace; Soul Echo.
- **persistence:**
  - the session lock prevents loads on two servers;
  - stale locks are taken over;
  - migrations work;
  - save/load round-trips.
- **stat_calculator:**
  - additive vs multiplicative stacking, soft caps with diminishing returns, hard caps and absolute clamps;
  - every race × role × full mastery build stays inside the limits at levels 1/15/30/50;
  - prints an effective-power balance table.
- **gameplay_rules:**
  - fuzzing: student creation (3,000 random payloads) and settings (1,000);
  - all build-rule combinations;
  - Kishin is never rollable;
  - ability slots and costs;
  - mastery needs XP *and* objectives;
  - quest chain and level gates;
  - projectile reach and kinematics.
- **weapons:**
  - WeaponConfig consistency;
  - for all 12 weapons and Tsubaki forms: hierarchy, `Grip`/`SupportGrip`/trail attachments, every part welded to the Handle, collision flags, part budget;
  - equip / holster / re-equip / unequip;
  - **hand stays on the grip in idle, walk, run and every attack frame**.
- **animations:** all 102 baked clips exist; seamless loops; attack lengths match gameplay; every pose maps to a real Motor6D.
- **geometry:** the triangle and wedge math and the weld offsets.

### Headless play-test (`scripts/playtest.sh`)

Every run uses **strict mock Instances** checked against the Roblox API dump. Reading or writing a property that doesn't exist, writing a read-only property, assigning the wrong type or Enum, or calling an unknown method fails exactly as it would in Roblox.

1. **Server session** (`tests/server/run_server.luau`, 45 checks):
   - **Boot:** all 16 services start; the 1,300-part map builds; enemies spawn.
   - **Join:** a player joins and the profile loads.
   - **Creation and rolls:**
     - name filtering;
     - student creation;
     - the race roll, including retry replay, rate limit and cooldown;
     - weapon locks.
   - **Combat:**
     - killing a real enemy with M1 and Z, with souls, EXP, kill stats and race mastery awarded;
     - cooldown rejection;
     - the role technique's Soul Energy cost;
     - dash stamina;
     - malformed requests.
   - **Persistence:** settings save; leave and rejoin restores the save.
2. **Client 3D** (`tests/ui/run_vfx.luau`): equips every weapon on an R15 character and plays every attack (animation + effect + impact) plus all 16 ability visuals, soul orbs and quality switches. Checks that particles are emitted and every pooled part is released.
3. **Client UI** (`tests/ui/run_ui.luau`) on **desktop, laptop, tablet (touch) and phone (touch)**:
   - **Create Your Student:** can't be skipped; inline errors; a double click sends one request.
   - **Soul Altar:** probability table; reveal; fast reveal unlocking; keep/replace with hold-to-confirm; Soul Echo; out of currency.
   - **Menus:** Race Index, Lore, Stats, all Skills tabs, Inventory with Tsubaki forms, Settings, editing the student.
   - **Touch controls** on touch devices.

   Each step is saved as a snapshot. With `RENDER_DEPS` (a `node_modules` folder containing `playwright`) and `CHROMIUM_PATH` set, every snapshot is rendered to PNG and checked for **text overflow** and **off-screen elements**. Fetch the matching fonts once with `scripts/fetch_ui_fonts.sh`.

### Tools

[Rojo 7](https://rojo.space), [Lune 0.10](https://lune-org.github.io/docs), [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) with Roblox `globalTypes.d.luau` (set `SOUL_TOOLS_DIR`, or `LUAU_LSP` + `ROBLOX_DEFS`), [selene](https://github.com/Kampfkarren/selene) and [StyLua](https://github.com/JohnnyMorganz/StyLua). Renders also need Node 18+ with `playwright` (and `three` for weapon renders).

### Limits of offline testing

The harness runs the real game code, but it is not the Roblox engine:

- **No physics:** humanoids don't walk by themselves, so the tests position characters.
- **No network latency.**
- **Approximate fonts:** stand-ins for Roblox's fonts are used.
- **3D previews:** UI ViewportFrames show offline renders.

Lune 0.10.5's `CFrame.lookAt` flips the Z axis, so the harness uses a Roblox-equivalent version (`tests/harness/Polyfills.luau`, checked by `tools/diag/lookat_check.luau`). The game code itself is unaffected.

Final feel, network behaviour and art direction still need a pass in Studio. Use the checklist below.

## Manual Studio checklist

Press **Play** (or **Test › Start** with 2 players for the partner and PvP checks).

**Create Your Student**
- [ ] The creator opens by itself; Esc, the M key and the HUD can't skip it
- [ ] Short, long or digit-first names show an inline error; a filtered name shows "not allowed"
- [ ] Skin, hair, hairstyle and uniform update the preview; *My Avatar Outfit* keeps your clothes
- [ ] *Enroll* once → the HUD appears with your starter weapon in hand

**Soul Altar** (the glowing altar in the plaza, or the HUD button)
- [ ] The probability table shows all 9 races, totaling 100%
- [ ] The first roll animates, then applies your origin; the HUD badge and nameplate update
- [ ] The second roll shows Keep / Replace with a stat comparison; once invested, replace needs a hold
- [ ] After one full reveal, *Fast reveal* and *Skip* unlock (Settings)
- [ ] Spam-clicking Roll never charges twice; leaving mid-choice and rejoining shows the pending choice

**Weapons** (Inventory, or the rack in the training yard)
- [ ] Each of the 12 weapons equips, draws (E) and holsters on the back
- [ ] The weapon stays in the hand(s) while idle, walking, running and attacking
- [ ] Tsubaki switches Blade → Kusarigama → Chain Sickle (T)
- [ ] Chains swing and settle on the ground; the drill bit spins; pistol slides recoil; spider legs move

**Combat and VFX** (training dummies, graveyard)
- [ ] M1 combos chain; Z/X cooldowns show on the HUD; trails appear only during swings
- [ ] Impacts match the weapon (blade sparks, heavy dust, gun flash, chain sparks); no runes or beams
- [ ] Shuriken flies and spins; pistols fire tracers with shell casings; slams leave dust rings
- [ ] Enemies telegraph before attacking; killing one gives souls, EXP, quest progress and a soul orb
- [ ] C/V abilities work per origin and role; the Witch/Sorcerer school spell matches the equipped school

**Menus, settings and devices**
- [ ] Stats shows the sources and soft/hard cap markers; Skills shows locked slots and reasons
- [ ] Reduced motion removes shake, flashes and pulsing; UI scale changes every menu
- [ ] Phone (Device Emulator): touch buttons work, clear of the jump button; text is readable
- [ ] Gamepad: the menus are navigable; B closes them (except the first student creation)

**Saving** (needs *Enable Studio Access to API Services*)
- [ ] Stop and Play again: the student, origin, mastery, settings and weapons persist

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| **Weapon trails are invisible** | Trails only show during an action's trail window; the weapon is holstered; or a custom mesh replaced the group that held `TrailA`/`TrailB` | Swing while drawn (E). For custom meshes, keep `TrailA`/`TrailB` (they sit on the Handle) and move them to your new edge in the weapon's builder. Trail color, width, lifetime and transparency are in `WeaponConfig.Weapons.<Id>.Trail`. |
| **Weapon points the wrong way / sideways** | A mesh override was exported with the wrong axes, or its pivot isn't at the grip | Re-export with **−Z forward, Y up**, apply transforms, and put the origin at the grip ([BLENDER_WORKFLOW.md](BLENDER_WORKFLOW.md)) |
| **Weapon floats away from the hand / detached parts** | The character is R6 (no R15 joints), or a script destroyed the `MountJoint` | Set *Avatar Type: R15*. Don't parent other welds to weapon parts. Run `scripts/test.sh weapons` after changing builders. |
| **Parts fall off or drop to the ground** | A new part added to a builder without a weld | Create parts through `GeometryKit` (welds are automatic). The weapon test fails if any part isn't connected to the Handle. |
| **Other players don't see my weapon or effects** | The weapon was built on the client, or an effect was played only locally | Weapons must be equipped through `WeaponService` (server). Effects come from `CombatFX`, which only reaches players within 260 studs (`FXBroadcast.DefaultRadius`). |
| **Hits don't register on enemies** | The player is staggered or out of range; the attack was rejected (see the `Reject` reasons); PvP only works when both players are in a `PvPZone` | Watch the Output for `Reject` reasons. Enemies leash home and fully heal when dragged too far from their spawn. |
| **Projectiles pass through walls / hit nothing** | The server sphere-casts each step, so anything with `CanQuery = false` is ignored | Give walls `CanQuery = true`; keep decorative parts `CanQuery = false`. Projectile radius and speed are in `WeaponConfig.Projectiles` and the attack's `Hits`. |
| **Projectiles look out of sync with damage** | The client visual uses the same `ProjectileController` kinematics, but starts on the broadcast | Expected small latency. Don't add client-side damage; tune `Speed`/`Range` in one place (`WeaponConfig`). |
| **"Using in-memory MockDataStore" warning** | Studio API access is off | *Game Settings → Security → Enable Studio Access to API Services* (on a published place) |
| **Kicked: "save still in use on another server"** | The session lock from a crashed server hasn't expired yet | Wait about 2.5 minutes (`GameConfig.Data.SessionLockStaleAfter` = 150 s) or test with a different account |
| **Uploaded animation doesn't play** | Not all of Idle/Walk/Run are set, the id isn't yours or the group's, or the rig isn't R15 | Set all three `AnimationIds`; publish under the experience owner; check the Output for "could not load animation" |
| **UI too small or large** | UI scale | *Settings → Interface size*; the UI also adapts to the screen size automatically |
| **Phone UI overlaps** | A custom HUD element in the thumb zones | Keep the bottom-right (actions) and bottom-left (thumbstick) clear; run `scripts/playtest.sh phone` with rendering enabled |
