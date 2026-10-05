# Server provenance

The Aethyra server is derived from **tmwAthena (tmwa)**, The Mana World's
server, itself forked from eAthena in 2004.

| | |
|---|---|
| Upstream | https://git.themanaworld.org/tmw/tmwa (mirror: https://github.com/themanaworld/tmwa) |
| Imported commit | `f9356d349c5fe14760fac7bb5297fad0aff456c0` (2026-06-11) |
| Imported as | source snapshot (`git archive`), without upstream history |
| License | GPL-3.0-or-later combined with AGPL-3.0-or-later; see `COPYING`, `gpl-3.0.txt`, `agpl-3.0.txt` |

## Changes made on import

- Removed upstream CI files and the `deps/googletest` submodule reference
  (`TMWA_BUILD_TESTS` therefore needs googletest supplied separately).
- `CMakeLists.txt` pins the version instead of reading git tags, and sets the
  vendor to Aethyra.

All later changes are recorded in this repository's history.

## AGPL obligation for hosts

Anyone who runs a modified server for other players must offer those players
the server's corresponding source (AGPL-3.0 section 13). The server reports
`VENDOR_SOURCE` for this purpose; keep it pointing at a public copy of the
code you are actually running.
