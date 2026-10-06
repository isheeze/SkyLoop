# Skyloop — art to generate in Google Flow

The board, buildings and tokens are built in code (3D). Flow makes the 2D art around them.
Save every result into `D:\Work\Skyloop\art\incoming\` with the file name given; I cut, size
and wire them in.

## Shared style line (paste at the end of every prompt)

> Stylized 3D miniature diorama, tilt-shift, bright golden-hour light, a floating sky island
> above a sea of soft pink and peach sunset clouds, soft clay-like matte materials, gentle rim
> light, clean and modern, cheerful premium mobile game art, no text, no logos, no watermark.

Colour anchors: gold #ffc23d, coral #ff5d73, mint #3ddc97, sky #5cc8ff, peach clouds, ink #1d2340.

**Status (2026-10-06):** style bible, icon, the four tycoon portraits (Broker is a woman) and the
key art were generated in Flow project "Oct 06 - 17:11" and installed into `art/tycoons/` and
`art/ui/`. Originals are in `art/incoming/`. The navy dusk look was dropped for sunset clouds
after user feedback.

## 1. Style bible (do this first, then use it as the reference image for everything else)

`style_bible.png` · 16:9
> A small floating square city block at dusk: a ring of tiny streets around a central park
> with a pond and little trees, pastel low-rise houses and two glowing towers with lit
> windows, a gold coin stack on a corner tile, a small lighthouse on another corner. Viewed
> from a high three-quarter angle. + style line

## 2. App icon

`icon.png` · 1:1, 1024×1024
> A single glowing miniature skyscraper standing on a rounded square city tile, gold accent
> light at its tip, deep navy background with a soft radial glow, centred, bold simple
> silhouette that reads at small size. + style line

## 3. Tycoon portraits (four, same framing)

Square 1:1, head and shoulders, facing slightly left, plain navy gradient background, soft
studio light, stylized 3D character (Pixar-like, not realistic). Each on its own.

- `tycoon_developer.png` — a confident architect in a hard hat with rolled blueprints, warm
  orange accents.
- `tycoon_shark.png` — a sharp-suited landlord with slicked hair and a sly smile, coral accents.
- `tycoon_broker.png` — a fast-talking dealmaker with headset and two phones, mint accents.
- `tycoon_drifter.png` — a relaxed traveller with a scarf, goggles on the forehead and a
  metro card, sky-blue accents.

## 4. Splash / key art

`key_art.png` · 9:16 portrait
> The whole Skyloop city ring seen from above at dusk, a gold die mid-air above it trailing
> light, four coloured game tokens (gold, coral, mint, sky blue) on the streets. Empty space
> in the top third for the logo. + style line

## 5. Menu background loop (video)

`menu_loop.mp4` · 9:16, 6–8 s, seamless loop
> Slow orbiting camera around a miniature dusk city diorama, windows flickering on, tiny
> cars with headlights moving along the ring road, gentle fog. No text. + style line

## 6. Later (milestone 4): Headline card illustrations

One 3:2 image per headline (Boom Times, Blackout, Tax Reform, Stimulus, Construction Subsidy,
Hot Spot, Slump, Payday Bonus, Rent Freeze, Gold Rush, Wealth Tax, Open House, Quiet Day).
Prompt pattern:
> Miniature dusk city scene illustrating "<headline>": <one-line visual idea>. + style line
