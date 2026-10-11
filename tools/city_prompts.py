"""Flow prompts for each city's board kit (see docs/city_kits.md). Order matches KIT_FILES."""

S = ("Cute stylized 3D, soft clay materials, warm light from the top left, short soft shadow, premium mobile "
     "game asset. Isolated on a plain pure white background, no text, no letters.")
GRID = ("Game asset sheet for a mobile board game, 2x2 grid of four separate objects, each centred in its own "
        "quarter with lots of empty space around it, all in the same true isometric view (classic 2:1 angle), "
        "facing the viewer. ")
DIAMOND = ("Isometric game asset, classic 2:1 isometric view: one big square diorama tile seen as a perfect "
           "diamond, its flat top face filling the image width with perfectly straight edges and only a very thin "
           "base. ")
ISLAND = ("A cute floating sky island for a mobile board game in true isometric view (classic 2:1 isometric "
          "angle), portrait image. The island top is a big perfectly square flat surface rotated 45 degrees so it "
          "appears as a wide diamond with slightly rounded corners, completely empty and flat with nothing on it: "
          "no road, no buildings, no trees on top. ")
ISLAND_END = (" The island fills the width of the image. Cute stylized 3D diorama, soft clay materials, warm light "
              "from the top left, premium mobile game asset. Isolated on a plain pure white background, no clouds, "
              "no sky, no text.")
COLOURS = [("gold", "GOLDEN YELLOW"), ("coral", "CORAL PINK"), ("mint", "MINT GREEN"), ("blue", "SKY BLUE")]

CITIES = {
    "forest": {
        "island": "The top is soft mossy forest-floor grass. Below it a thick earthy cliff with tree roots, mossy "
                  "rocks and hanging ferns, and two little waterfalls pouring off the front edges.",
        "tiles": "Top left: one flat square mossy grey stone board space tile, softly bevelled, slightly raised. "
                 "Top right: the same square tile in shiny gold. Bottom left: one empty square building plot of flat "
                 "dark forest soil with a neat low rustic wooden log fence around all four sides, completely empty "
                 "inside. Bottom right: one flat square piece of mossy flagstone forest path.",
        "marks": "Top left: a rustic wooden forest start gate arch with lanterns and a pile of gold coins. Top right: "
                 "a cute ranger hut with a giant magnifying glass sign. Bottom left: a golden jackpot fountain carved "
                 "from a mossy tree stump overflowing with gold coins. Bottom right: a treasure vault door set into a "
                 "big mossy boulder with a red alarm lantern on top. Each landmark is compact on a small square base.",
        "centre": "On top: a magical forest glade with ferns and tiny mushrooms along all four diamond edges, and "
                  "inside it a calm forest pond sunk level into the ground (flat water level with the ground, no "
                  "visible water sides), a mossy rock island in the exact centre holding a giant shiny golden pair of "
                  "dice on a tree-stump pedestal with a little waterfall, lily pads and two ducks.",
        "decor_a": "Top left: a round fluffy oak tree. Top right: a cluster of ferns and wildflowers. Bottom left: a "
                   "wooden lantern post. Bottom right: a rustic log bench.",
        "decor_b": "Top left: a tall slim pine tree. Top right: a cluster of red-capped mushrooms. Bottom left: a "
                   "wooden trail signpost. Bottom right: a mossy rock with small flowers.",
        "bld": "forest buildings: top left a tiny log cabin, top right a two-storey timber lodge, bottom left a "
               "three-storey treehouse shop with an awning, bottom right a tall grand wooden lookout tower with a "
               "golden finial. Warm wood walls",
        "ground": "mossy grass",
    },
    "desert": {
        "island": "The top is smooth golden desert sand. Below it a thick layered sandstone cliff in warm orange and "
                  "red bands, with a little oasis spring pouring off the front edges as two small waterfalls.",
        "tiles": "Top left: one flat square cream sandstone board space tile, softly bevelled, slightly raised. Top "
                 "right: the same square tile in shiny gold. Bottom left: one empty square building plot of flat "
                 "smooth sand with a neat low terracotta brick border around all four sides, completely empty "
                 "inside. Bottom right: one flat square piece of patterned terracotta tile road.",
        "marks": "Top left: a desert palace start gate arch with blue tiles, palm leaves and a pile of gold coins. "
                 "Top right: a cute sandstone audit house with a giant magnifying glass sign. Bottom left: a golden "
                 "jackpot fountain in a blue-tiled basin overflowing with gold coins. Bottom right: a treasure vault "
                 "in a sandstone fort with a red alarm light on top. Each landmark is compact on a small square base.",
        "centre": "On top: a desert oasis with soft sand and small palm trees along all four diamond edges, and inside "
                  "it a turquoise oasis pool sunk level into the sand (flat water level with the ground, no visible "
                  "water sides), a small sandstone island in the exact centre holding a giant shiny golden pair of "
                  "dice on a blue-tiled pedestal with a little fountain, lotus flowers and a tiny boat.",
        "decor_a": "Top left: a palm tree. Top right: a cluster of desert flowers and succulents. Bottom left: a "
                   "brass Arabian lantern post. Bottom right: a striped market umbrella with cushions.",
        "decor_b": "Top left: a tall saguaro cactus. Top right: a pair of big clay pots. Bottom left: a wooden "
                   "signpost. Bottom right: a small camel resting.",
        "bld": "desert buildings: top left a tiny adobe hut, top right a two-storey sandstone house with a roof "
               "terrace, bottom left a three-storey bazaar shop with an awning, bottom right a tall grand palace "
               "tower with a golden onion dome. Cream sandstone walls",
        "ground": "sand",
    },
    "city": {
        "island": "The top is a smooth green park lawn. Below it a thick cliff of grey stone and brick foundations "
                  "with pipes and two little waterfalls pouring off the front edges.",
        "tiles": "Top left: one flat square light grey paving stone board space tile, softly bevelled, slightly "
                 "raised. Top right: the same square tile in shiny gold. Bottom left: one empty square building plot "
                 "of flat brown soil with a neat low black iron railing around all four sides, completely empty "
                 "inside. Bottom right: one flat square piece of red brick city pavement.",
        "marks": "Top left: a grand city start arch with flags and a pile of gold coins. Top right: a cute brick "
                 "audit office with a giant magnifying glass sign. Bottom left: a golden jackpot fountain in a stone "
                 "plaza overflowing with gold coins. Bottom right: a classic bank vault building with columns and a "
                 "red alarm light on top. Each landmark is compact on a small square base.",
        "centre": "On top: a city park with neat hedges and flower beds along all four diamond edges, and inside it a "
                  "rectangular pond sunk level into the ground (flat water level with the ground, no visible water "
                  "sides), a round stone island in the exact centre holding a giant shiny golden pair of dice on a "
                  "marble pedestal with fountain jets, lily pads and a little paddle boat.",
        "decor_a": "Top left: a round street tree in a planter. Top right: a cluster of tulips. Bottom left: a classic "
                   "black street lamp. Bottom right: a park bench.",
        "decor_b": "Top left: a slim poplar tree. Top right: a round trimmed hedge. Bottom left: a red post box. "
                   "Bottom right: a small fire hydrant with flowers.",
        "bld": "city buildings: top left a tiny corner cafe, top right a two-storey brick townhouse, bottom left a "
               "three-storey shop with an awning, bottom right a tall grand clock tower with a golden top. Red brick "
               "and cream walls",
        "ground": "grass",
    },
    "metro": {
        "island": "The top is a smooth modern pale grey city plaza. Below it a thick cliff of concrete, steel beams "
                  "and glowing windows of underground floors, with two little waterfalls pouring off the front edges.",
        "tiles": "Top left: one flat square white concrete board space tile, softly bevelled, slightly raised. Top "
                 "right: the same square tile in shiny gold. Bottom left: one empty square building plot of flat "
                 "dark asphalt with neat low glass barriers around all four sides, completely empty inside. Bottom "
                 "right: one flat square piece of modern grey asphalt road with a white lane marking.",
        "marks": "Top left: a modern glass start gate with screens and a pile of gold coins. Top right: a sleek glass "
                 "audit office with a giant magnifying glass sign. Bottom left: a golden jackpot fountain in a "
                 "modern plaza overflowing with gold coins. Bottom right: a high-tech bank vault cube with red alarm "
                 "lights. Each landmark is compact on a small square base.",
        "centre": "On top: a modern rooftop plaza with clipped green planters along all four diamond edges, and "
                  "inside it a sleek reflecting pool sunk level into the floor (flat water level with the ground, no "
                  "visible water sides), a round platform in the exact centre holding a giant shiny golden pair of "
                  "dice on a glass pedestal with light fountain jets.",
        "decor_a": "Top left: a round tree in a square concrete planter. Top right: a modern flower planter. Bottom "
                   "left: a sleek modern street light. Bottom right: a modern bench.",
        "decor_b": "Top left: a tall slim cypress tree in a planter. Top right: a round clipped bush. Bottom left: a "
                   "bus stop sign. Bottom right: a small yellow taxi.",
        "bld": "big city buildings: top left a small glass cafe, top right a two-storey modern apartment, bottom "
               "left a three-storey glass shop, bottom right a tall skyscraper with a golden spire. Glass and white "
               "walls",
        "ground": "plaza",
    },
    "future": {
        "island": "The top is a smooth glowing white futuristic platform with faint cyan light lines. Below it a "
                  "thick floating crystal and metal underside with glowing cyan crystals, hover engines and two little "
                  "streams of light pouring off the front edges.",
        "tiles": "Top left: one flat square white glowing hexagon-patterned board space tile, softly bevelled, "
                 "slightly raised. Top right: the same square tile in shiny gold. Bottom left: one empty square "
                 "building plot of flat dark violet surface with a neat low glowing cyan light rail around all four "
                 "sides, completely empty inside. Bottom right: one flat square piece of white futuristic road with "
                 "glowing lines.",
        "marks": "Top left: a futuristic hologram start gate with light rings and a pile of gold coins. Top right: a "
                 "sleek white audit pod with a giant holographic magnifying glass. Bottom left: a golden jackpot "
                 "fountain with floating gold coins and light beams. Bottom right: a futuristic vault pod with red "
                 "warning lights. Each landmark is compact on a small square base.",
        "centre": "On top: a futuristic garden with glowing plants along all four diamond edges, and inside it a "
                  "glowing turquoise energy pool sunk level into the floor (flat level with the ground, no visible "
                  "sides), a floating platform in the exact centre holding a giant shiny golden pair of dice on a "
                  "levitating pedestal with light rings.",
        "decor_a": "Top left: a round glowing crystal tree. Top right: a cluster of glowing alien flowers. Bottom left: "
                   "a futuristic light post. Bottom right: a floating hover bench.",
        "decor_b": "Top left: a tall slim futuristic spire plant. Top right: a glowing round bush. Bottom left: a "
                   "hologram sign post. Bottom right: a tiny cute robot.",
        "bld": "futuristic buildings: top left a tiny white pod home, top right a two-storey dome home, bottom left "
               "a three-storey glass shop with a glowing awning, bottom right a tall futuristic spire with a golden "
               "tip. White and pearl walls",
        "ground": "glowing platform",
    },
}

KIT_FILES = ["island_iso", "sheet_a", "landmarks", "centres/pond", "decor_a", "decor_b",
             "bld_gold", "bld_coral", "bld_mint", "bld_blue"]


def prompts(city):
    c = CITIES[city]
    out = [ISLAND + c["island"] + ISLAND_END,
           GRID + c["tiles"] + " " + S,
           GRID + c["marks"] + " " + S,
           DIAMOND + c["centre"] + " Only the golden dice in the centre is tall, everything near the edges is low "
                                   "and flat. " + S,
           GRID + c["decor_a"] + " Each object stands directly on the ground with no base or tile under it. " + S,
           GRID + c["decor_b"] + " Each object stands directly on the ground with no base or tile under it. " + S]
    for _, name in COLOURS:
        out.append(GRID + "Four " + c["bld"] + " and bright %s roofs, %s awnings and %s accents, each standing on "
                   "its own small square %s footprint." % (name, name.lower(), name.lower(), c["ground"]) + " " + S)
    return out


if __name__ == "__main__":
    import json
    import sys
    print(json.dumps(prompts(sys.argv[1]), indent=1))
