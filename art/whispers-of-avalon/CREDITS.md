# Whispers of Avalon tileset

- **Artist:** Leonard Pabin ("Len"), with the barrel derived from work by Crush.
  The sheets also say "inspired by zyndikate".
- **Source:** <https://opengameart.org/content/whispers-of-avalon-grassland-tileset>,
  published 2 January 2010.
- **Licences:** CC-BY 3.0, GPL 3.0 or GPL 2.0, at your choice. Aethyra uses the
  art under **CC-BY 3.0** (<https://creativecommons.org/licenses/by/3.0/>);
  GPL 2.0+ also fits the rest of the game.

`source/` holds the files as they were published on OpenGameArt. They were fetched by
`.github/workflows/fetch-art.yml`. The saved page `opengameart-page.html` and
`files.txt` record where each file came from.

## What we changed

`tools/art/cut_avalon.py` crops the sheets into the pieces in
`game/assets/avalon/`, using the coordinates listed in the script.
`pieces.json` records which sheet and box each piece came from. It also does
the following:

- Flattens the "Trees" layer of `treesv6_0_0.psd`.
- Recolours nothing.
- Draws nothing new.

The game assembles cliffs, stairs and borders from these pieces at runtime.

## Credit line (in-game and in release notes)

> Grassland tileset "Whispers of Avalon" by Leonard Pabin (barrel after Crush),
> CC-BY 3.0, via OpenGameArt.org.
