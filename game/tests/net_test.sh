#!/bin/sh
# Two real game instances over ENet: a headless host and a headless friend.
# Run from game/: tests/net_test.sh
set -u
dir=$(mktemp -d)
world="NetTest$$"
port=$((25000 + $$ % 2000))
fail=0
check() {   # check <file> <pattern> <description>
	if grep -q -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3"; fail=1; fi
}

godot --headless --path . --audio-driver Dummy -- --host "$world" Hosty --port "$port" --log-events \
	--quit-after 14 --do "wait 5;say hello from the host;say @spawn 1010 13 30;wait 1;key 2" > "$dir/host.log" 2>&1 &
host=$!
sleep 3
godot --headless --path . --audio-driver Dummy -- --join 127.0.0.1 Friendo --port "$port" --log-events \
	--quit-after 8 --do "wait 1;say hi host;click 15 29;wait 1.5;say @hueset energy gale 0" > "$dir/client.log" 2>&1
sleep 1
godot --headless --path . --audio-driver Dummy -- --join 127.0.0.1 Friendo --port "$port" --log-events \
	--quit-after 3 > "$dir/client2.log" 2>&1
wait $host

check "$dir/client.log" '"t":"welcome"' "the friend is welcomed into the host's world"
check "$dir/client.log" '"name":"Hosty"' "the friend sees the host's character"
check "$dir/host.log" '"text":"hi host"' "the host hears the friend"
check "$dir/client.log" '"text":"hello from the host"' "the friend hears the host"
check "$dir/host.log" '"t":"move","x":15,"y":29' "the host sees the friend walk"
check "$dir/client.log" 'Only the host can use @ commands' "friends cannot use host commands"
check "$dir/client.log" '"t":"slide"' "the friend sees the host's Gust push the hopper"
check "$dir/client2.log" '"t":"welcome"' "the friend can rejoin"
check "$dir/client2.log" '"name":"Friendo","x":15,"y":29' "rejoining keeps the character where it was"
save="$HOME/.local/share/godot/app_userdata/Aethyra/worlds/$(echo "$world" | tr 'A-Z' 'a-z')/characters"
check "$save/friendo.json" '"name": "Friendo"' "the host saved the friend's character"
check "$save/hosty.json" '"name": "Hosty"' "the host saved its own character on quit"
if grep -q "SCRIPT ERROR" "$dir/host.log" "$dir/client.log"; then
	echo "  FAIL script errors:"; grep -A2 "SCRIPT ERROR" "$dir/host.log" "$dir/client.log" | head -20; fail=1
fi
[ $fail = 0 ] && rm -rf "$(dirname "$save")" "$dir" || echo "logs kept in $dir"
[ $fail = 0 ] && echo "network test passed" || echo "network test FAILED"
exit $fail
