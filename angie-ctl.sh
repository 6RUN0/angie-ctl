#!/bin/sh

# Simple a2enconf/a2enmod-like helper for Angie
# Works with:
#   /etc/angie/http-conf-available.d  -> http-conf.d
#   /etc/angie/modules-available.d    -> modules.d

: "${ANGIE_ETC:=/etc/angie}"
: "${ANGIE_BIN:=angie}"
: "${ANGIE_CONF:=$ANGIE_ETC/angie.conf}"

usage() {
  cat >&2 <<EOF
Usage:
  $0 {httpconf|mod} {en|dis|ls|ls-available|ls-enabled} [name ...]

Examples:
  $0 httpconf en drupal # resolves drupal or drupal.conf
  $0 httpconf en drupal.conf
  $0 httpconf dis drupal
  $0 mod en geoip
  $0 mod dis geoip
  $0 httpconf ls
  $0 mod ls
EOF
  exit 1
}

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

config_test() {
  if ! test_log=$("$ANGIE_BIN" -t -c "$ANGIE_CONF" 2>&1); then
    echo "Angie config test failed (angie -t)" >&2
    echo "$test_log" >&2
    exit 1
  fi
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
resolve_name_enabled() {
  base=$1
  if [ -e "$ENABLED_DIR/$base" ]; then
    echo "$base"
    return 0
  fi
  if [ -e "$ENABLED_DIR/$base.conf" ]; then
    echo "$base.conf"
    return 0
  fi
  return 1
}

do_enable() {
  ensure_dirs
  [ $# -ge 1 ] || {
    echo "Nothing to enable" >&2
    exit 1
  }

  subdir=${AVAILABLE_DIR##*/}
  rc=0

  for base in "$@"; do
    if ! name=$(resolve_name_available "$base"); then
      echo "No such $KIND: '$base' (tried '$base' and '$base.conf' in $AVAILABLE_DIR)" >&2
      rc=1
      continue
    fi

    dst="$ENABLED_DIR/$name"

    if [ -e "$dst" ]; then
      echo "$KIND '$name' already enabled in $ENABLED_DIR" >&2
      continue
    fi

    ln -s "../$subdir/$name" "$dst" || rc=1
    echo "Enabled $KIND: $name"
  done

  [ $rc -eq 0 ] || exit $rc

  config_test
}

do_disable() {
  ensure_dirs
  [ $# -ge 1 ] || {
    echo "Nothing to disable" >&2
    exit 1
  }

  rc=0
  for base in "$@"; do
    if ! name=$(resolve_name_enabled "$base"); then
      echo "$KIND '$base' is not enabled (tried '$base' and '$base.conf' in $ENABLED_DIR)" >&2
      rc=1
      continue
    fi

    dst="$ENABLED_DIR/$name"

    rm -f "$dst" || rc=1
    echo "Disabled $KIND: $name"
  done

  [ $rc -eq 0 ] || exit $rc

  config_test
}

do_list_available() {
  ensure_dirs
  for f in "$AVAILABLE_DIR"/*; do
    [ -e "$f" ] || continue
    printf '%s\n' "${f##*/}"
  done
}

do_list_enabled() {
  ensure_dirs
  for f in "$ENABLED_DIR"/*; do
    [ -e "$f" ] || continue
    printf '%s\n' "${f##*/}"
  done
}

do_list() {
  ensure_dirs
  for f in "$AVAILABLE_DIR"/*; do
    [ -e "$f" ] || continue
    name=${f##*/}
    if [ -e "$ENABLED_DIR/$name" ]; then
      printf ' [on ] %s\n' "$name"
    else
      printf ' [off] %s\n' "$name"
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
