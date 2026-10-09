# Blender workflow: replacing weapon parts with meshes

The procedural weapons are complete as they are. Use this workflow when you want sculpted detail, such as a smoother scythe crescent, engraved guards or a skull with real geometry. You replace one **part group** at a time; the rest of the weapon, its attachments, IK grips, trails and animation keep working.

## 1. Know the target group

Each weapon is built from named groups inside each unit model (`EquippedWeapon › Main › <Group>`). A MeshPart named `<WeaponId>_<Group>` in `ReplicatedStorage › WeaponAssets` replaces that group automatically.

| Weapon id | Static groups you can replace | Moving groups (keep procedural) |
|---|---|---|
| `MakaScythe` | `Blade`, `Head`, `Shaft`, `Grips` | — |
| `SoulScythe` | `Blade`, `Head`, `Shaft`, `Grips` | — |
| `Ragnarok` | `Blade`, `Skull`, `Shaft`, `Grips` | — |
| `SoulEaterBlade` | `Blade`, `Guard`, `Grip` | — |
| `StarShuriken` | `Blades`, `Hub` | — |
| `TsubakiForms` | `Blade`, `Guard`, `Handle`, `Sickle` | `Chain`, `ChainEnd` |
| `TsunamiChain` | `Handle`, `TopBlade`, `EndBlade` | `Chain` |
| `GevurahChain` | `Handle`, `SpikedCollars` | `Chain`, `Ball` |
| `AsuraArm` | `Sleeve`, `Fist` | `Segments` |
| `TwinPistols` | `Frame`, `Barrel` | `SlideAssembly` |
| `PattyDrill` | `Housing` | `Bit` |
| `ArachneSpider` | `Body`, `Harness` | `Legs` |

Moving groups are Motor6D-jointed: chain links, the drill bit, the pistol slide, spider legs and arm segments. Replacing one with a single static mesh would freeze it, so keep those procedural. For Twin Pistols the units are `Liz` and `Patty`, but the override name stays `TwinPistols_<Group>` and applies to both.

## 2. Model in Blender with the game's conventions

- **Units:** model at real stud sizes, with 1 Blender unit = 1 stud. Match `WeaponConfig.Weapons.<Id>.Dimensions` (blade length, shaft length, etc.), so swapping the mesh doesn't change reach or hit timing.
- **Pivot = grip point.** Put the object origin exactly where the right hand holds the weapon. In-game the mesh is pivoted onto the unit's `Handle`, which *is* the grip.
- **Axes (Roblox model space):** **+Y** runs along the handle toward the business end (blade above the fist), **−Z** is the edge / facing side (barrels point −Z), and **X** is blade thickness. In Blender (Z-up) that means: handle along **+Z**, edge toward **+Y**. The FBX export below converts the axes.
- **Budget:** about 2–5k triangles per group and one material per mesh. Use a `SurfaceAppearance` (color / normal / roughness / metalness maps) for detail rather than geometry.
- **Apply transforms** before exporting (**Ctrl+A → All Transforms**). Make the mesh one object per group with no armature.

## 3. Export

**File → Export → FBX**:

- **Selected Objects** only
- **Forward: −Z Forward**, **Up: Y Up**
- **Apply Scalings: FBX All**
- Uncheck *Add Leaf Bones*; no animation

## 4. Import into Studio

1. **Avatar / Home → Import 3D** (3D Importer), pick the FBX and check the preview size against `Dimensions`.
2. Rename the resulting MeshPart to `<WeaponId>_<Group>`, e.g. `MakaScythe_Blade`, and move it into `ReplicatedStorage › WeaponAssets`.
3. Optional: add a `SurfaceAppearance` as a child, and set `RenderFidelity = Automatic`. Set `CollisionFidelity = Box`, since weapons never collide anyway.
4. Press **Play**. The builder replaces the procedural group with your mesh, welds it to the handle and disables collision, touch and query. All attachments stay: `Grip`, `SupportGrip`, `TrailA`/`TrailB`, `Impact`, `Muzzle`.

## 5. Check it

- **Inventory turntable and weapon rack:** the mesh should sit exactly where the procedural part was. If it's offset, the pivot isn't at the grip; if it's rotated, re-export with −Z forward / Y up.
- **Trails:** these still run from `TrailA` to `TrailB`. If your blade is longer or shorter, move those attachments in the weapon's builder (`WeaponBuilder/Models/<Id>.luau`) to the new edge.
- **Tests:** run `scripts/test.sh weapons`. Hierarchy, welds and IK reach don't depend on the meshes, so they should still pass.
