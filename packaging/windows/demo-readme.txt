Aethyra - Gale starter test demo
================================

HOSTING A GAME
 1. Run aethyra.exe. Choose SDL or OpenGL when asked (SDL is the safe choice).
 2. On the login screen press "Host World". Your world starts on this PC.
 3. Press "Register", pick a name and password, then create a character.

JOINING A FRIEND
 1. Run aethyra.exe, type the host's address in "Server" (port 6901).
 2. Press "Register" for a new account on their world, then log in.
 Over the internet the host forwards TCP ports 6901, 6121 and 5121 to their
 PC, or everyone joins the same VPN (Tailscale or ZeroTier) and uses the
 host's VPN address.

Worlds are saved in %USERPROFILE%\.aethyra\worlds (or under your user
folder's .aethyra directory).

The art is placeholder art. The server is derived from tmwAthena and is
licensed under the GNU AGPL; see server\PROVENANCE.md.
