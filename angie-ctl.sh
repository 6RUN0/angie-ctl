#!/bin/sh

# Simple a2enconf/a2enmod-like helper for Angie
# Works with:
#   /etc/angie/http-conf-available.d  -> http-conf.d
#   /etc/angie/modules-available.d    -> modules.d

set -u

: "${ANGIE_ETC:=/etc/angie}"

# ANGIE_ETC is interpolated into every path; require an absolute base so a
# caller-supplied relative value cannot redirect operations into the CWD.
case "$ANGIE_ETC" in
/*) ;;
*)
  echo "ANGIE_ETC must be an absolute path: $ANGIE_ETC" >&2
  exit 1
  ;;
esac
# A leading slash is not enough: '..' segments or symlink indirection could
# still redirect operations outside the intended tree, so reject traversal
# tokens up front. This matters when the tool is wrapped (sudo/CI) and the
# value comes from a less-trusted caller.
case "$ANGIE_ETC" in
*/../* | */.. | *//*)
  echo "ANGIE_ETC must not contain '..' or '//': $ANGIE_ETC" >&2
  exit 1
  ;;
esac

# Binary used for the post-change configuration test (see run_config_test).
: "${ANGIE_BIN:=angie}"

print_usage() {
  cat <<EOF
Usage:
  $0 [-n|--dry-run] [-T|--no-test] {httpconf|mod} {en|dis|ls|ls-available|ls-enabled} [name ...]

Options (must be given separately; -nT is not split into -n -T):
  -n, --dry-run   show what en/dis would change, without modifying anything
  -T, --no-test   skip the '$ANGIE_BIN -t' config test that otherwise runs
                  once after a successful en/dis batch
  -h, --help, help  show this help and exit

Environment:
  ANGIE_ETC   config root (default /etc/angie; must be absolute)
  ANGIE_BIN   binary for the config test (default angie)

Examples:
  $0 httpconf en drupal # resolves drupal or drupal.conf
  $0 httpconf en drupal.conf
  $0 httpconf dis drupal
  $0 mod en geoip
  $0 mod dis geoip
  $0 httpconf ls
  $0 mod ls
EOF
}

# Error exit: help to stderr, non-zero status.
usage() {
  print_usage >&2
  exit 1
}

# Global options precede the type/command. -h is honored even with no other
# arguments so help is always reachable with a success status.
DRY_RUN=0
NO_TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help | help)
    print_usage
    exit 0
    ;;
  -n | --dry-run)
    DRY_RUN=1
    shift
    ;;
  -T | --no-test)
    NO_TEST=1
    shift
    ;;
  --)
    shift
    break
    ;;
  -*)
    echo "Unknown option: $1" >&2
    usage
    ;;
  *)
    break
    ;;
  esac
done

[ $# -ge 2 ] || usage

TYPE=$1
CMD=$2
shift 2

case "$TYPE" in
httpconf | httpconfs | "http-conf" | "http-confs")
  AVAILABLE_DIR="$ANGIE_ETC/http-conf-available.d"
  ENABLED_DIR="$ANGIE_ETC/http-conf.d"
  KIND="http-conf"
  ;;
mod | mods | module | modules)
  AVAILABLE_DIR="$ANGIE_ETC/modules-available.d"
  ENABLED_DIR="$ANGIE_ETC/modules.d"
  KIND="module"
  ;;
*)
  echo "Unknown type: $TYPE" >&2
  usage
  ;;
esac

ensure_dirs() {
  if [ ! -d "$AVAILABLE_DIR" ]; then
    echo "Missing directory: $AVAILABLE_DIR" >&2
    exit 1
  fi
  if [ ! -d "$ENABLED_DIR" ]; then
    echo "Missing directory: $ENABLED_DIR" >&2
    exit 1
  fi
}

# Fail early with an actionable message instead of a raw ln/rm "Permission
# denied" when the enabled directory (normally under /etc) is not writable.
require_writable_enabled() {
  if [ ! -w "$ENABLED_DIR" ]; then
    echo "No write permission for $ENABLED_DIR (try running as root)" >&2
    exit 1
  fi
}

# Validate the whole configuration once, AFTER a batch of changes is applied.
# Running it per item would spuriously fail on valid intermediate states (e.g.
# a config enabled before the module it needs). On failure it reports but does
# not roll back: a config already broken before this run must not block every
# future operation. Returns non-zero so the caller's exit status reflects it.
# Argument: number of changes actually applied in this run.
run_config_test() {
  changes=$1
  [ "$NO_TEST" -eq 1 ] && return 0
  [ "$DRY_RUN" -eq 1 ] && return 0
  [ "$changes" -gt 0 ] || return 0
  # Resolve and run the test binary under a fixed, trusted PATH so an
  # inherited/hostile PATH cannot redirect '$ANGIE_BIN -t' to an attacker
  # binary (it runs as root in the normal deployment). An absolute ANGIE_BIN
  # bypasses PATH lookup entirely and is honored as-is.
  config_test_path=/usr/sbin:/usr/bin:/sbin:/bin
  if ! PATH="$config_test_path" command -v "$ANGIE_BIN" >/dev/null 2>&1; then
    echo "Note: '$ANGIE_BIN' not found in PATH; skipping config test" >&2
    return 0
  fi

  # Stay quiet on success; show the binary's output only when it fails.
  if test_output=$(PATH="$config_test_path" "$ANGIE_BIN" -t 2>&1); then
    return 0
  fi
  echo "Config test failed ('$ANGIE_BIN -t'); changes left in place:" >&2
  printf '%s\n' "$test_output" >&2
  return 1
}

# A name must be a single path component: reject empty, '.', '..' and anything
# containing a slash so it cannot escape the managed directories.
is_safe_name() {
  case $1 in
  "" | . | ..) return 1 ;;
  */*) return 1 ;;
  *) return 0 ;;
  esac
}

# Resolve name for enabling:
#  - if NAME exists in AVAILABLE_DIR -> use it
#  - else if NAME.conf exists -> use NAME.conf
resolve_name_available() {
  base=$1
  if [ -e "$AVAILABLE_DIR/$base" ]; then
    echo "$base"
    return 0
  fi
  if [ -e "$AVAILABLE_DIR/$base.conf" ]; then
    echo "$base.conf"
    return 0
  fi
  return 1
}

# Resolve name for disabling:
#  - if NAME exists in ENABLED_DIR -> use it
#  - else if NAME.conf exists -> use NAME.conf
# Uses -L as well as -e so a dangling (broken) symlink is still resolvable.
resolve_name_enabled() {
  base=$1
  if [ -e "$ENABLED_DIR/$base" ] || [ -L "$ENABLED_DIR/$base" ]; then
    echo "$base"
    return 0
  fi
  if [ -e "$ENABLED_DIR/$base.conf" ] || [ -L "$ENABLED_DIR/$base.conf" ]; then
    echo "$base.conf"
    return 0
  fi
  return 1
}

do_enable() {
  ensure_dirs
  [ "$DRY_RUN" -eq 1 ] || require_writable_enabled
  [ $# -ge 1 ] || {
    echo "Nothing to enable" >&2
    exit 1
  }

  subdir=${AVAILABLE_DIR##*/}
  rc=0
  changed=0

  for base in "$@"; do
    if ! is_safe_name "$base"; then
      echo "Invalid name: '$base'" >&2
      rc=1
      continue
    fi

    if ! name=$(resolve_name_available "$base"); then
      echo "No such $KIND: '$base' (tried '$base' and '$base.conf' in $AVAILABLE_DIR)" >&2
      rc=1
      continue
    fi

    dst="$ENABLED_DIR/$name"

    # -L catches a dangling symlink that -e would miss; either way it is
    # already present, so report and skip rather than fail in ln.
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      echo "$KIND '$name' already enabled in $ENABLED_DIR" >&2
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] would enable $KIND: $name"
      continue
    fi

    if ln -s "../$subdir/$name" "$dst"; then
      echo "Enabled $KIND: $name"
      changed=$((changed + 1))
    else
      rc=1
    fi
  done

  # Validate once, after the whole batch, not per item (see run_config_test).
  run_config_test "$changed" || rc=1

  [ $rc -eq 0 ] || exit $rc
}

do_disable() {
  ensure_dirs
  [ "$DRY_RUN" -eq 1 ] || require_writable_enabled
  [ $# -ge 1 ] || {
    echo "Nothing to disable" >&2
    exit 1
  }

  rc=0
  changed=0
  for base in "$@"; do
    if ! is_safe_name "$base"; then
      echo "Invalid name: '$base'" >&2
      rc=1
      continue
    fi

    if ! name=$(resolve_name_enabled "$base"); then
      echo "$KIND '$base' is not enabled (tried '$base' and '$base.conf' in $ENABLED_DIR)" >&2
      rc=1
      continue
    fi

    dst="$ENABLED_DIR/$name"

    # This tool only manages symlinks; refuse to delete a real config file
    # that was placed in the enabled directory by other means.
    if [ ! -L "$dst" ]; then
      echo "$KIND '$name' is not a managed symlink, refusing to remove" >&2
      rc=1
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] would disable $KIND: $name"
      continue
    fi

    if rm -f "$dst"; then
      echo "Disabled $KIND: $name"
      changed=$((changed + 1))
    else
      rc=1
    fi
  done

  # Disabling can also break config (a module a config still needs); validate
  # once after the batch, same policy as enable.
  run_config_test "$changed" || rc=1

  [ $rc -eq 0 ] || exit $rc
}

do_list_available() {
  ensure_dirs
  for f in "$AVAILABLE_DIR"/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    printf '%s\n' "${f##*/}"
  done
}

do_list_enabled() {
  ensure_dirs
  for f in "$ENABLED_DIR"/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    printf '%s\n' "${f##*/}"
  done
}

do_list() {
  ensure_dirs
  for f in "$AVAILABLE_DIR"/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    name=${f##*/}
    if [ -e "$ENABLED_DIR/$name" ] || [ -L "$ENABLED_DIR/$name" ]; then
      printf ' [on ] %s\n' "$name"
    else
      printf ' [off] %s\n' "$name"
    fi
  done

  # Second pass: enabled entries with no matching source in AVAILABLE_DIR.
  # These are active in Angie yet invisible in the first pass, so surface
  # them explicitly rather than letting them go unnoticed.
  for f in "$ENABLED_DIR"/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    name=${f##*/}
    if [ ! -e "$AVAILABLE_DIR/$name" ] && [ ! -L "$AVAILABLE_DIR/$name" ]; then
      printf ' [orphan] %s\n' "$name"
    fi
  done
}

case "$CMD" in
enable | en) do_enable "$@" ;;
disable | dis) do_disable "$@" ;;
list | ls) do_list ;;
"ls-available" | "list-available") do_list_available ;;
"ls-enabled" | "list-enabled") do_list_enabled ;;
*)
  echo "Unknown command: $CMD" >&2
  usage
  ;;
esac
