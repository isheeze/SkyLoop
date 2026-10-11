# City board kits (Flow prompts)

Every city uses the same layout and the same ten kit images, generated in Google Flow
(Nano Banana, 3:4). Shared suffix for sheets, written as {S}:
"Cute stylized 3D, soft clay materials, warm light from the top left, short soft shadow, premium
mobile game asset. Isolated on a plain pure white background, no text, no letters."

| File | What |
|---|---|
| island_iso.jpg | the floating island, empty diamond top (isolated on white) |
| sheet_a.jpg | space tile, gold tile, empty fenced plot, road tile (2x2) |
| landmarks.jpg | start gate, audit office, jackpot fountain, vault (2x2) |
| centres/pond.jpg | diamond centrepiece with the golden dice |
| decor_a.jpg / decor_b.jpg | 4 decorations each (2x2) |
| bld_gold / bld_coral / bld_mint / bld_blue .jpg | cottage, house, shop, tower (2x2) per player colour |

Compose with `python tools/compose_board.py --theme=<id> --export`.
