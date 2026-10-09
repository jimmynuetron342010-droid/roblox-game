# Combat integration and multiplayer (Phase 4)

## Authority: clients ask, the server decides

```
Client (WeaponClient)                         Server (CombatService)
──────────────────────                        ──────────────────────────────────────────
M1 / Z / X pressed
  ├─ predicts animation + VFX locally   ──►   AttackRequest(slot, aim, seq)
  └─ remembers seq                            1. rate limit (RemoteGuard, 12/s)
                                              2. validate: alive · not staggered · weapon equipped
                                                 · combo step / combo window · per-slot cooldown
                                                 · stamina · aim is a finite unit vector
                                              3. schedule each hit at its server time (scaled by
                                                 Attack Speed); positions read on the server
                                              4. shapes: Arc · Circle · Line · Projectile
                                                 (ProjectileController.Simulate) · Hitscan · Ticks
                                              5. damage = base × attacker multiplier (additive pool
                                                 + capped buffs) → target mitigation (defense curve,
                                                 ranged/poison reduction) → statuses, stagger,
                                                 knockback, rewards, quest & mastery events
  ◄── Reject(seq, reason) if refused          6. broadcast CombatFX to nearby players only
  ◄── DamageFeedback (numbers, hurt flinch)
```

- **Prediction.** The client plays its own swing at once so the controls feel instant. If the server refuses (`Reject`: Busy, Cooldown, Staggered, NoWeapon, Stamina…), the client cancels the predicted action. It never decides a hit.
- **PvP.** Players can only damage each other when **both** stand in a `PvPZone`. PvE is everywhere.
- **Abilities** (`AbilityService`). The slot resolves on the server from the saved profile (race, mastery stage, role, unlocks). Then cost, cooldown (with capped Cooldown Reduction) and Soul Energy are checked before anything happens. Telegraphed abilities (Golem slam, Death's Authority) show their area to everyone before they land. Interrupting a Golem's slam wind-up cancels it, with half the cooldown refunded.
- **Statuses** (`StatusService`). Root, Slow, Stagger, Burn, Judged, Cursed, Invulnerable and Pull are stored as timed attributes on the character, so every client can show them without extra traffic. Durations use the attacker's Status Effectiveness against the target's Status Resistance, both capped.
- **Enemies** (`EnemyService`). One 10 Hz AI loop runs all enemies: chase, then a visible wind-up, then attack and recover. Enemies leash back to their spawn and fully heal if pulled too far. An enemy adapts its level to the player who engages it (within the zone's range), keeping its current health ratio. Rewards and quest/mastery events go to every player who did damage.

## Replication

| What | How |
|---|---|
| Weapon models | built and mounted **on the server** (`WeaponService` → `WeaponBuilder.Equip`), replicated like any part |
| Weapon motion | animated **on each client** (`AnimationController` → `AnimatorCore` writes `Motor6D.Transform`). Every client animates every visible armed character, so motion costs no network traffic. |
| Cosmetic events | `CombatFX` from `FXBroadcast`, sent only to players within 260 studs; the instigator is excluded when its client already predicted the effect |
| Health / statuses / cooldowns / resources | Humanoid health plus attributes: `Status_*`, `CD_*`, `Stamina`, `SoulEnergy`, `Madness`, `Resonance`… |
| Profile | `ProfileChanged`: a trimmed snapshot to its owner only, coalesced so a burst of changes sends one message |

## Performance and cleanup

- **Server loops:** one Heartbeat loop for projectiles, one 10 Hz loop for enemy AI, one resource-regen loop. There are no per-entity loops.
- **Client animation:** characters within 70 studs update every frame and those up to 180 studs at 20 Hz; farther ones freeze.
- **Client effects:** VFX use pools and one render loop (see [VFX.md](VFX.md)).
- **Cleanup on the server:** leaving or respawning clears a player's combat state, cooldowns, busy locks, rate-limit buckets and partner links. Enemies that die are cleaned up and respawn from their marker. Projectiles end at their range or lifetime.
- **Cleanup on the client:** unequipping or dying turns off trails and stops actions and uploaded tracks.

## Anti-exploit summary

- **Never trusted from the client:** damage, hit targets, cooldowns, currency, rolls and race changes.
- **Validated input:** every payload is type- and range-checked (`Core/Validate`): finite numbers, unit directions, whitelisted strings, bounded table sizes.
- **Rate limits:** token buckets on every remote; floods are dropped and logged.
- **Idempotency:** request ids make rolls and choices safe to retry.
- **Session-locked saves:** no item or currency duplication across servers.

The headless server play-test (`tests/server/run_server.luau`) checks this end to end. It covers kills and rewards, cooldown rejection, stagger, malformed requests, rate limits and leave/rejoin persistence.
