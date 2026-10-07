#!/bin/sh
# Parse-check every script: tools/lint.sh (from game/)
status=0
for f in $(find core net ui tests tools -name '*.gd'); do
	out=$(timeout 60 godot --headless --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|at: GDScript::reload" | grep -v "^$" | grep -v -B0 "Identifier not found: Net" )
	if [ -n "$out" ]; then
		echo "== $f"; echo "$out"; status=1
	fi
done
exit $status
