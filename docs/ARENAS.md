# Arenas: review, fixes and tooling

Reviewed with `node tools/check-maps.js` (also part of `npm test`, errors only) which runs the real collision geometry from `shared/maps.json` on a 0.25 m grid with the game's constants (R 0.45, STEP 0.55, FH 2.3, jump 9.2 / GRAV 24; a jump clears roughly 2.2 m because you can clip a box top while still rising; bounce pads from the floor, ladders for the player only, 3.8 m gap leaps for the player). `npm run shots` (tools/shoot-maps.js) renders every level with the game's own thumbnail code into a folder for visual review.

What the checker verifies per map: spawns, bot starts, the player start and crate spots are on a surface and not inside a wall; every spawn can reach every other; no reachable pit/area a fighter cannot leave; crate heights match the surface (crates rest at the 3rd number of a drop spot, ignoring solids); standable platforms nobody can reach are listed (warnings).

Engine facts worth knowing when making maps: bot starts and the player start use y 0.01 unless a 3rd number is given (a start inside a raised box gets shoved sideways); respawns always drop in from y 4 (spawn[2] is ignored there); bots never climb ladders and avoid walking off edges (so void-gap maps need bridges for them); bounce pads only trigger below y 0.7; Godot loads only addBox/addStairs/addLadder/addBouncePad geometry.

## Findings and fixes

| Map | Verdict | Issues found | Fix |
|---|---|---|---|
| Sunny Arena | good | none; 40 m square, open edges on two sides, great for 2-5 players | none |
| Bouncy Rooftop | good | spawns 6 m apart at the closest | none |
| Slippery Rink | ok | 4 ice pillars (2.6 m) cannot be climbed: intended obstacles | none |
| Temple Ruins | ok but huge | 80 m, 6400 m2 walkable: slow with 2-3 players; broken columns (3.5 m) unclimbable by design | none (tagged Huge) |
| Rooftops | ok | the two spawns on the bridges land on a 4.2 m bridge (high ground); two bot starts sit under the bridges | none |
| Shrink Zone / Squeeze Chamber | ok | moving floor: geometry checks skipped | none |
| Tiered Tower | fixed | two bot starts inside the cover blocks on tier one; 5 crate spots sunk 0.5-1.2 m into blocks | starts and crates moved to open floor, summit crate to 5.6 |
| Grand Arena | good | none | none |
| Grand Rink | ok | 8 pillars unclimbable by design | none |
| Colosseum | good | 16 pillar caps unreachable, decoration | none |
| Fortress Yard | good | wall tops unreachable, ladders OK | none |
| Moon Base | fixed | centre crate sunk 0.3 m | crate to 1.5 |
| Volcano Rim | fixed | two spawns on the same island only 4 m apart | second one moved onto the middle island |
| Candy Land | fixed | cake crate sunk 1 m inside the cake | crate to 3.0 |
| Pirate Ship | ok | mast (10 m) is decoration; stern spawns land high | none |
| Haunted Hollow | ok | crypt-top crate reachable only by ladder: bots cannot fetch it (a player-only prize) | none |
| Sunset Beach | fixed | centre crate sunk 0.5 m in the sandcastle | crate to 2.9 |
| Moonlit Dojo (Ninja) | fixed | four bots started inside the corner pavilions (shoved out sideways); 4 crates sunk into the pavilion stairs; centre crate sunk | bot starts at y 1.2, crates moved to clear floor, centre crate 2.0 |
| Blast Yard (Explosive) | good | none | none |
| Firing Range (Guns) | good | none | none |
| Brawl Pit (Melee) | fixed | two bleacher crates sunk 0.85 m | crates to 2.85 |
| Crater Dome / Space Capsule (Moon Drift) | ok | floating crates are intentional in low gravity | none |
| Pillars / Pillars Lava | n/a | no solids, pillar-hop rules | none |
| Giant's Playroom | ok but huge | 98 m, only for Giant mode (giants cover ground) | none |
| Sunny Farm | ok | two crate spots 0.2 m above a surface | none |
| Test / Practice / Build Your Own | dev | skipped | none |

Phone notes: the 36-46 m maps (arena, park, ice, moonbase, candy, haunted, beach, dojo, brawlpit, tower) suit iPhone landscape with 2-6 players; the 60-98 m ones (Grand Arena, Rink, Colosseum, Fortress, Temple, Farm, Playroom) are team/8-player maps and empty with 2-3. Remaining soft spots: Temple and Playroom are very large; the menu thumbnails frame the whole sky so the map is a small part of the picture (a UI tweak in `previewCam`, left to the interface session).

## New arenas (small and fast, all use exported primitives only)

| Map | Size | Idea |
|---|---|---|
| Neon Crossroads (`crossroads`) | plus shape, 44 m arms | night city street, corners are open sky, raised hub, four bounce pads, chokepoints |
| Donut Drop (`donut`) | 38 m ring | a frosted ring round a dark hole; stairs and bounce pads to a sprinkle island in the hole |
| Chasm Bridge (`chasm`) | 54 x 22 m | two cliffs, two narrow bridges and a pad-fed island; long and thin for a landscape phone |
| Summit Rush (`summit`) | 42 x 22 m | seven terraces rising to a central peak, symmetrical spawns, pads at the foot |

They are in the Classic, Duel/2v2, Melee Only and Guns Only pools (the `NEW_ARENAS` list); 3v3/4v4 stay on the big arenas.
