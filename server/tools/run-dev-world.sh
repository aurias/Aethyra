#!/bin/sh
# Run the three server services against a scratch copy of server/world.
#
#   run-dev-world.sh BUILD_DIR [RUN_DIR]
#
# The world template is copied to RUN_DIR (default /tmp/aethyra-run) so saves
# and logs never land in the repository. On Linux the servers refuse to run
# as root; when started as root this script drops to the "nobody" user.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build=$(cd "$1" && pwd)
run=${2:-/tmp/aethyra-run}

rm -rf -- "$run"
cp -r "$here/../world" "$run"
mkdir -p "$run/log" "$run/bin"
# Copy the binaries in so a dropped-privilege user can always run them.
cp "$build"/tmwa-login "$build"/tmwa-char "$build"/tmwa-map "$build"/libtmwa-shared.so* "$run/bin/"

as_user=""
if [ "$(id -u)" = 0 ]; then
    chown -R nobody "$run"
    as_user="runuser -u nobody --"
fi

cd "$run"
for service in login char map; do
    $as_user env LD_LIBRARY_PATH="$run/bin" "$run/bin/tmwa-$service" \
        > "log/$service.out" 2>&1 < /dev/null &
    sleep 1
done
echo "world running in $run (logs in $run/log)"
