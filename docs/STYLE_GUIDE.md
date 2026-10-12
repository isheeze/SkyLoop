# Skyloop style guide: "toy diorama"

Targets: concepts 7 and 8 (`art/incoming/concepts_v3/concept_06.jpg`, `concept_07.jpg`) for layout and
readability, 5 and 6 for detail, 3 and 4 for colour and light.

## Principles

1. **One focal point per area.** Corners and the centre are the heroes; tiles are calm.
2. **Every colour means something.** Player colours appear only on what a player owns
   (roof, flag, pawn). District colours appear only on the tile stripes.
3. **Chunky, soft, readable.** Low poly with generous bevels; silhouettes must read at phone
   size. No detail smaller than a window.
4. **Everything fits its slot.** A building never leaves its tile. Pawns stand on the front half.
5. **Light sells it.** Warm sun from the top left, crisp soft shadows, saturated colour, no haze.

## Palette

| Role | Colour |
|---|---|
| Tile top | `#fbf1de` cream, edges `#e9d6b4` |
| Grass | `#6cc04a` light, `#4f9c3a` shade |
| Cliff | `#b07a4f`, rock `#8d6a55` |
| Walls | `#fff4e2` |
| Windows | `#9fd8ff`, frames white |
| Wood | `#b9743f` |
| Gold | `#ffc531` metal |
| Sky | `#8fd3ff` to `#d9f1ff` |

District stripes: coral `#ff7a6b`, orange `#ffa94d`, gold `#ffd23f`, mint `#3ddc97`, teal
`#2ec4c6`, sky `#4dabff`, violet `#9b6bff`.
Players: gold `#ffc23d`, coral `#ff5d73`, green `#3ddc97`, blue `#5cc8ff`.

## Board

- 28 spaces on an 8 x 8 ring. Tiles are thick bevelled slabs (0.94 wide, 0.14 tall), cream on
  top, with the district stripe across the front edge.
- The centre is clean grass with one hero piece: the golden dice fountain.
- Grass border around the ring, a few round trees at the corners only. Island cliff below with
  two waterfalls.

## Tile layout (seen from the camera)

- Back half: the building (or a "for sale" sign when unowned).
- Front half: pawns.
- Front edge: the price plate, printed on the stripe.

## Buildings (roof and flag in the owner's colour)

| Level | Building | Height |
|---|---|---|
| 1 | Cottage, gable roof | 0.35 |
| 2 | Two-storey house, chimney | 0.5 |
| 3 | Shop with striped awning | 0.62 |
| 4 | Tower with cone roof | 0.85 |
| 5 | District landmark, gold details | 1.0 |

## Corners (hero landmarks, up to 1.25 wide)

Payday: golden gate arch with coins. Audit: police booth with barrier. Jackpot: coin fountain.
Tax raid: red vault.

## Pawns

Classic chunky pawn, glossy, in the player's colour, with a white rim on the base.

## Camera and light

Orthographic, turned 45 degrees and pitched 47 down (three-quarter view). Warm key light (`#fff0d6`, from the
top left), cool fill, shadows on, saturation +15%, no fog.

## Cities (one per table)

Every table shares the board kit (tiles, buildings, corners, pawns) and gets its own island and
park (`art/toy/<theme>/`, palettes in `THEMES` in `tools/blender/build_toy.py`), wall tints, sky
tint and sunlight (`game3d/themes.gd`).

| Table | Island top | Cliff | Park trees | Rim | Paths |
|---|---|---|---|---|---|
| Small Town | green | warm earth | round, pine, blossom | flower bushes | cream |
| Forest | deep green | dark earth | pines, oaks, red mushrooms | little pines | wood |
| Desert | sand | orange sandstone | palms, cacti | cacti, rocks | sandstone |
| City | warm paving, lawn inside | terracotta | round, topiary, blossom | planters | brick red |
| Big City | grey paving, lawn inside | slate | topiary, round | planters | white |
| Future City | pearl, mint lawn | violet with glowing seams | crystals, light orbs | crystals | white, neon lamps |

## Water

Every surface on the `Water` material uses `game3d/water.gdshader`: soft vertical streaks with
pulses running down the waterfalls, rings drifting across the fountain pool. Spray particles
rise where the falls land.
