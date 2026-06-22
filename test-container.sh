#!/bin/sh

# Container integration test for angie-ctl.sh.
#
# Unlike test.sh (which stubs `angie -t`), this drives the script against a REAL
# `angie -t` inside the official Angie image. It verifies the actual premise of
# the tool end to end: that enabling a config by symlink into an included
# directory produces a configuration Angie accepts, and that run_config_test
# invokes the real binary and reports its verdict correctly.
#
# Opt-in and self-skipping: if Docker or the image is unavailable it prints a
# notice and exits 0, so it never breaks a Docker-less `make check`.
# Run: ./test-container.sh   (or: make test-container)

set -u

IMAGE="${ANGIE_IMAGE:-docker.angie.software/angie:latest}"
# shellcheck disable=SC1007  # CDPATH= is a deliberate per-command reset, not a typo
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

skip() {
  echo "SKIP container test: $1" >&2
  exit 0
}

command -v docker >/dev/null 2>&1 || skip "docker not installed"
docker info >/dev/null 2>&1 || skip "docker daemon not reachable"
docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || skip "image '$IMAGE' not present locally (run: docker pull $IMAGE)"

# The script under test is mounted read-only as the `angie-ctl` command. The
# guest body sets up /etc/angie (the default ANGIE_ETC) with the a2enconf-style
# layout and a main config that includes the managed dir, then exercises the
# real `angie -t` through the tool. A quoted heredoc keeps $VARS literal so they
# expand inside the container, not on the host.
docker run --rm -i \
  -v "$SCRIPT_DIR/angie-ctl.sh:/usr/local/bin/angie-ctl:ro" \
  "$IMAGE" sh -u <<'GUEST'
ETC=/etc/angie
mkdir -p "$ETC/http-conf-available.d" "$ETC/http-conf.d"

# Minimal main config whose http block pulls in the managed enabled dir.
cat > "$ETC/angie.conf" <<CONF
events {}
http {
    include $ETC/http-conf.d/*.conf;
}
CONF

printf 'server { listen 8080; server_name ok.test; }\n' \
  > "$ETC/http-conf-available.d/ok.conf"
printf 'server { not_a_real_directive on; }\n' \
  > "$ETC/http-conf-available.d/broken.conf"
printf 'server { also_not_a_directive on; }\n' \
  > "$ETC/http-conf-available.d/rollme.conf"

fail=0
check() { # desc want -- command...
  desc=$1
  want=$2
  shift 2
  "$@" >/tmp/o 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc (exit $got, want $want)"
    sed 's/^/       /' /tmp/o
    fail=1
  fi
}
present() {
  if [ -L "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1 (missing $2)"; fail=1; fi
}
absent() {
  if [ -L "$2" ]; then echo "FAIL - $1 (still present $2)"; fail=1; else echo "ok   - $1"; fi
}

check   "baseline real angie -t passes"                 0 angie -t
check   "status reports a disabled config off"          1 angie-ctl httpconf status ok
check   "enable valid config passes real angie -t"      0 angie-ctl httpconf en ok
present "valid config symlinked"                          "$ETC/http-conf.d/ok.conf"
check   "status reports an enabled config on"           0 angie-ctl httpconf status ok
check   "enable broken config fails real angie -t"      1 angie-ctl httpconf en broken
present "broken config kept after failed test"            "$ETC/http-conf.d/broken.conf"
check   "--rollback undoes a change on failed test"     1 angie-ctl --rollback httpconf en rollme
absent  "rolled-back config left no symlink"             "$ETC/http-conf.d/rollme.conf"
check   "--no-test bypasses the real angie -t"          0 angie-ctl --no-test httpconf dis broken
absent  "broken config disabled via --no-test"           "$ETC/http-conf.d/broken.conf"

# Orphan an enabled config (drop its source), then prune it; real angie -t
# must still pass once the dangling include is gone.
ln -s ../http-conf-available.d/gone.conf "$ETC/http-conf.d/gone.conf"
check   "prune removes the orphan and config stays valid" 0 angie-ctl httpconf prune
absent  "orphan removed by prune"                        "$ETC/http-conf.d/gone.conf"

check   "disable leaves a valid configuration"          0 angie-ctl httpconf dis ok

echo
if [ "$fail" -eq 0 ]; then
  echo "container: all checks passed"
else
  echo "container: FAILURES"
fi
exit $fail
GUEST