# Weapon VFX (Phase 3)

The effects are **physical**: real blade trails, sparks, dust, smoke, debris, muzzle flashes, shell casings, air streaks and geometry shockwave rings. Ordinary weapon attacks never use runes, glyphs or energy beams. Magic only appears on magic abilities (Witch and Sorcerer schools), as their own visuals.

All effects are client-side and cosmetic. Damage and hit detection always happen on the server (see [COMBAT.md](COMBAT.md)).

## The 10 reusable effects

| # | Effect (module) | Used by | What you see |
|---|---|---|---|
| 1 | **Basic Slash** (`BasicSlash`) | scythe / sword / shuriken M1 | the weapon's real `SlashTrail` (TrailA→TrailB on the blade) during the swing window, a metallic glint at the strike, air-slice streaks off the tip |
| 2 | **Heavy Slash** (`HeavySlash`) | Z on scythes, Tsubaki blade, spider sweep | wider, longer trail and a bigger glint; if the blade meets the ground: dust burst, debris, warm flash, short camera shake |
| 3 | **Multi-Hit Combo** (`MultiHitCombo`) | sword / chain / segmented arm combos | alternating slashes or punches, each timed from the attack's hit list; shortened trail lifetime so old slashes never pile up |
| 4 | **Chain Swing** (`ChainSwing`) | Tsunami, Gevurah, kusarigama | the real linked chain whips outward through the chain simulator, with air streaks off the end and a brief trail stretch. No energy rope. |
| 5 | **Ground Slam** (`GroundSlam`) | slams (scythe, flail, arm, spider) | expanding dust ring, rock fragments, a thin 3D shockwave ring of geometry, low warm flash, distance-scaled shake |
| 6 | **Shuriken Throw** (`ShurikenThrow`) | Star weapon Z/X | a pooled copy of the real shuriken model spinning on its hub, with an air trail; metal sparks on contact; flight from `ProjectileController`, so it matches the server |
| 7 | **Gun Shot** (`GunShot`) | Twin Pistols | two-frame 3D muzzle flash, light pop, smoke, ejected shell casing, short tracer to the hit point (never a lasting beam); Patty's flash is wider and smokier |
| 8 | **Drill Attack** (`DrillAttack`) | Drill form | the bit spins (`BitSpin` motor) with a spiral trail; scraping sparks, dust in the surface color and chips while the tip touches a surface; stops instantly when the attack ends |
| 9 | **Rapid Dash Slash** (`RapidDashSlash`) | dash attacks | dust kicks at the start and end of the dash, fading afterimage silhouettes (skipped on Low), the blade's real trail during swings |
| 10 | **Weapon Impact** (`WeaponImpact`) | every hit, by `ImpactType` | **Blade:** metal sparks, directional streak, small flash. **Heavy:** dust burst, debris, strong flash, small shake. **Gun:** compact flash, sparks, surface-colored dust. **Chain:** metal-on-metal sparks. |

Ability visuals (`Effects/Ability`) cover 16 kinds: Telegraph, Slam, Judgment, Buff, Heal, Blink, Pulse, Cone, AreaBlast, Well, Projectile, Construct, MasteryUp, Dash, Wrap and Rooted. Soul orbs float from defeated enemies to the player who killed them.

## Configuration (`ReplicatedStorage.Modules.VFXConfig`)

- **Per-effect tuning:** colors, counts, sizes, lifetimes, trail widths, camera shake, and placeholder sounds (`rbxassetid://0`, never played until you replace them).
- **Textures:** built-in Roblox particle textures by default. To use your own, put a `ParticleEmitter` named after the template (`Spark`, `Glint`, `Dust`, `DustRing`, `Smoke`, `Streak`, `Puff`, `Soul`) into `ReplicatedStorage.VFXAssets`. It is cloned instead of the built-in template, keeping your texture and colors.
- **Quality tiers:** Low / Medium / High scale particle counts, debris, afterimages, lights and ring segments. *Auto* picks Medium on phones and otherwise follows the Roblox graphics level. Players can override it in Settings.
- **Accessibility:** *Reduced motion* removes screen shake, flashes and UI pulsing, and also follows the device setting. *Camera shake* can be turned off separately.

## Performance

- **Emitter reuse:** one invisible anchored host per emitter template. Spawning particles moves the host and calls `:Emit(n)`, so no emitters are created per hit.
- **Part pools:** debris, ring segments, tracers, streaks, muzzle petals, shells, afterimages and orbs all come from pools. Finished effects park their parts and return them.
- **One update loop:** a single `BindToRenderStep` loop updates every transient effect; there are no per-effect connections.
- **Local only:** everything lives in `workspace.ClientVFX`, on the client only.
- **Distance culling:** the server sends `CombatFX` only to players within 260 studs (`FXBroadcast`). The attacker's own client predicts its effects immediately and is excluded from its own broadcast.
- **Tested:** the headless play-test runs every effect and ability visual with strict property checks. It verifies particles are emitted and every pooled part is returned afterwards (`tests/ui/run_vfx.luau`).
