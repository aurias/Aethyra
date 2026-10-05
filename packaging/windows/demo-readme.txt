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
 Ctrl          attack the targeted monster       A   target nearest monster
 Z             pick up                           F3  inventory
 Click an NPC to talk. All keys can be changed under Setup > Keyboard.

 The green bar is your Gale energy. Each skill uses some; it refills by
 itself in a few seconds.

WHAT TO DO
 Talk to Windkeeper Ama next to where you arrive. Harvest Meadow Grass
 anywhere, Wild Herbs on the terrace up the stairs and Windflowers by the
 pond. Gust Hoppers bite: push them away with Gust and Dash clear. Bring
 Ama three Meadow Herbs and three Windflower Petals for a Gale Tonic.

Worlds are saved in your user folder under .aethyra\worlds.

The art is placeholder art. The server is derived from tmwAthena and is
licensed under the GNU AGPL; see server\PROVENANCE.md.
