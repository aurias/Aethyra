# Development world

A minimal world for running and testing the server: one placeholder map
(`gale-1`, the Windswept Meadow test map), one NPC, and a single item.
It is a template; run it through `tools/run-dev-world.sh`, which copies it
to a scratch directory so saves and logs never land in the repository.

```
cmake -S server -B build/server && cmake --build build/server
server/tools/run-dev-world.sh build/server
python3 server/tools/protoclient.py create-char 127.0.0.1 6901 aethyra-test test-pass Wanderer
aethyra --data ./data -U aethyra-test -P test-pass -u -D   # with host 127.0.0.1, port 6901 in config.xml
```

## Hosted worlds

Players host from the client (Host World on the login screen, or
`aethyra --host-world NAME`). The client copies this template to
`<home>/.aethyra/worlds/NAME` on first use, gives it a random internal
password and no accounts, and runs `aethyra-server` for it. The client
expects `server/aethyra-server[.exe]` and this template as `server/world`
next to its own executable; the `hostServerPath` and `hostWorldTemplate`
config options override those paths.

Friends connect to the host's address on port 6901. Over the internet the
host forwards TCP ports 6901, 6121 and 5121 (or uses a VPN such as
Tailscale or ZeroTier).

The Windows server cross-compiles with MinGW-w64:

```
cmake -S server -B build/server-win -DCMAKE_TOOLCHAIN_FILE=server/cmake/mingw-w64-x86_64.cmake
cmake --build build/server-win --target aethyra-server
```

## Layout

| Path | Contents |
|---|---|
| `conf/` | Service configuration. `tmwa-{login,char,map}.conf` are the entry points. |
| `save/` | Accounts and characters. `account.txt` holds a test account (`aethyra-test` / `test-pass`). |
| `data/` | Server walk maps (`.wlk`) generated from the client maps with `tools/tmx2wlk.py`. |
| `db/` | Items, monsters, skills and script constants. |
| `npc/` | NPC scripts. |

New accounts can register by logging in with `_M` or `_F` appended to the
user name (`new_account` is on).

The services authenticate to each other with `userid`/`passwd` from the
conf files (`change-me-char` here). That only guards their loopback link;
worlds hosted from the client get a random password of their own.
