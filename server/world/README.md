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

## Layout

| Path | Contents |
|---|---|
| `conf/` | Service configuration. `tmwa-{login,char,map}.conf` are the entry points. |
| `save/` | Accounts and characters. `account.txt` holds the internal server account and a test account (`aethyra-test` / `test-pass`). |
| `data/` | Server walk maps (`.wlk`) generated from the client maps with `tools/tmx2wlk.py`. |
| `db/` | Items, monsters, skills and script constants. |
| `npc/` | NPC scripts. |

New accounts can register by logging in with `_M` or `_F` appended to the
user name (`new_account` is on).

The internal account password (`change-me-char`) only guards the loopback
link between services. Hosted worlds will generate their own.
