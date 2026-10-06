# Skyloop — rules as implemented

Source of truth for numbers is `core/board.gd`; this file explains intent. Update both together.

## Shape of a match
- 4 players, 12 rounds, 28-tile ring: 7 districts of 3 tiles, 4 corners, 3 specials.
- Everyone starts with equal net worth (1300): two dealt deeds from different districts, the
  rest in cash. Later seats get +75 cash per seat to offset moving second.
- Highest net worth after round 12 wins. Owning three full districts wins instantly.
- Net worth = cash − debt + tile prices + money invested in buildings (+500 for The Spire).

## A turn
1. **Roll** two dice. Moving by the **sum is free**; moving by a **single die costs a steer
   token** (start 2, +1 at each Payday, max 3).
2. **Payday** when passing tile 0: salary 200, then pick a perk: +80 cash, Permit (next build
   half price) or Shield (next rent halved).
3. **Land**:
   - Unowned tile: buy at list price or send it to a **blind auction** (all players, sealed
     bids, minimum half price).
   - Rival tile: pay rent, then optionally **take it over** for 2× its value (price plus
     buildings). Tiles in a district fully owned by one player cannot be taken.
   - Audit: pay 100 or collect no rent until your next turn.
   - Jackpot Plaza: collect the pot (fed by taxes and fees).
   - Tax Raid: 15% of cash to the pot.
   - Metro: move again 1–6 of your choice. Windfall: 40 + 10 × round. Permit Office: a Permit.
4. **Manage**: build, use your tycoon power, end turn.

## Rent and building
- Rent = price × 0.25 × level multiplier × district multiplier × demand multiplier.
- Levels 0–4 then a Landmark (level 5): ×1, 2, 3.5, 5.5, 8, 12. Each level costs half the tile price.
- Owning 1 / 2 / 3 tiles of a district: level cap 2 / 3 / 4 (+Landmark), rent ×1 / 1.4 / 2.
- Demand per district is 0–5 (rent ×0.7 to ×1.45). +1 on every landing, −1 after two quiet rounds.
- One Landmark per district, each with a power (see `DISTRICTS`).

## Debt instead of elimination
A player who cannot pay is bailed out: the payee is paid in full and the shortfall becomes
debt at ×1.25, growing 10% per round. All income repays debt first.

## Headlines
One per round, announced a round ahead (see `HEADLINES`).

## Tycoons
Passive plus a one-shot power (see `TYCOONS`). Balanced to 22–26% win rate each in 4-player
bot matches.

## Why the rules look like this (sim findings, 2026-10-02)
- Free choice between die A, die B and the sum let players dodge almost every rent
  (about 300 rent per whole game). Making single-die moves cost a token restored rent as the
  core tension (about 2000 per game).
- Without starting deeds the board filled too slowly for a 12-round match.
- Takeovers limited to unbuilt tiles almost never happened; pricing them on full value
  gives about one per game and lets districts complete without a trade screen.
- 2- and 3-player matches are **not** balanced yet (board too sparse, rent too low).

## Tools
- `tools/sim.gd` — bot-only balance simulator:
  `godot --headless --path . --script res://tools/sim.gd -- --games 3000`
- `ui/greybox.tscn` — playable placeholder client. Self-test:
  `godot --path . -- --auto --seed 7 --shot <png> --shot-after 90`
