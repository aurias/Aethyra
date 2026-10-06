Aethyra - Gale starter test demo
================================

HOSTING A GAME
 1. Run aethyra.exe. Choose SDL or OpenGL when asked (SDL is the safe choice).
 2. On the login screen press "Host World". Your world starts on this PC.
 3. Press "Register", pick a name and password, then create a character.
 The first time, Windows Firewall asks whether aethyra-server.exe may
 accept connections: allow it (private networks at least), or friends
 cannot join.

JOINING A FRIEND
 1. Run aethyra.exe, type the host's address in "Server" (port 6901).
 2. Press "Register" for a new account on their world, then log in.
 Over the internet the host forwards TCP ports 6901, 6121 and 5121 to their
 PC, or everyone joins the same VPN (Tailscale or ZeroTier) and uses the
 host's VPN address.

CONTROLS
 Arrow keys    walk (or click where to go)
 X             Dash - rush up to 6 tiles in the direction you face
 C             Gust - blow nearby Gust Hoppers away (no damage)
 V             Wind Scythe - cut grass, herbs and flowers in front of you
 F             Featherfall - drift down a cliff you face
 G             Upward Jump - leap up onto a ledge you face
 T             Spark (Ember) - fire at your target; may set it burning
 Y             add Spark to your next Gust (fire on the wind)
 Shift+key     use it anyway after a warning that vessels may burst
 Ctrl          attack the targeted monster       A   target nearest monster
 Facing a cliff edge shows where you would land, or why you can't.
 Z             pick up                           F3  inventory
 Click an NPC to talk. All keys can be changed under Setup > Keyboard.

 The green bar is your Gale energy. Each skill uses some; it refills by
 itself in a few seconds. Under it: how many Gale actions are running and
 how much energy your selected vessels hold.

 Hues (menu)    your Gale mastery, energy, how much current you can
                channel, and your selected vessels
 Skills (menu)  what each skill does and costs, your proficiency, and
                what the next rank needs; spend skill points there
                (you gain one per character level)
 Inventory      select a Breeze Reed stack and press Supply: skills then
                draw on it when you cannot channel enough current alone.
                Overloading reeds can make the whole stack burst.

WHAT TO DO
 Talk to Wren the Ridge-runner at the top of the stairs to learn
 Featherfall and Upward Jump. Jump onto the high lookout in the east,
 where Skyreeds give Breeze Reeds, and blow Gust Hoppers off the terrace
 edge with Gust. Talk to Windkeeper Ama next to where you arrive. Harvest Meadow Grass
 anywhere, Wild Herbs on the terrace up the stairs and Windflowers by the
 pond. Gust Hoppers bite: push them away with Gust and Dash clear. Bring
 Ama three Meadow Herbs and three Windflower Petals for a Gale Tonic.

Spark is Ember, a second hue; until Ember altars exist, a world's
administrator grants it. To make yourself administrator of a world you
host: quit the game, open .aethyra\worlds\NAME\save\gm_account.txt in
your user folder and add the line "2000000 99" (2000000 is the first
account registered on that world), then host again and type in chat:
  @huegrant hue ember
  @huegrant skill 6 1

Worlds are saved in your user folder under .aethyra\worlds. This version
upgrades worlds from the first demo the first time it opens them (keeping
a copy of the old saves as *.pre-hue1); the first demo cannot open them
afterwards. Everyone must use this same version to join.

The art is placeholder art. The server is derived from tmwAthena and is
licensed under the GNU AGPL; see server\PROVENANCE.md.
