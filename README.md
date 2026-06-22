# angie-ctl

A simple script for managing Angie HTTP configurations and modules, similar to a2enconf/a2enmod for Apache.
It allows you to enable, disable, and list available/enabled configs and modules via symlinks.

## Features

- Enable/disable HTTP configs and modules by name
- List available and enabled configs/modules
- Rejects unsafe names (path traversal) and refuses to delete non-symlink files

## Usage

```text
./angie-ctl.sh [-n|--dry-run] [-T|--no-test] {httpconf|mod} {en|dis|ls|ls-available|ls-enabled} [name ...]
```

Options (give each separately; `-nT` is not split into `-n -T`):

- `-n`, `--dry-run` — show what `en`/`dis` would change without modifying anything
- `-T`, `--no-test` — skip the `angie -t` config test that otherwise runs after `en`/`dis`
- `-h`, `--help`, `help` — show help and exit

Environment:

- `ANGIE_ETC` — config root (default `/etc/angie`; must be an absolute path with no `..` segments)
- `ANGIE_BIN` — binary used for the config test (default `angie`). The test runs
  under a fixed `PATH` (`/usr/sbin:/usr/bin:/sbin:/bin`); use an absolute path to
  run a binary outside those locations. Treat `ANGIE_BIN`/`PATH` as trust-sensitive
  if the tool is wrapped by sudo or CI.

### Examples

Enable a config:

```sh
./angie-ctl.sh httpconf en drupal
./angie-ctl.sh httpconf en drupal.conf
```

Disable a config:

```sh
./angie-ctl.sh httpconf dis drupal
```

Enable a module:

```sh
./angie-ctl.sh mod en geoip
```

Disable a module:

```sh
./angie-ctl.sh mod dis geoip
```

List enabled configs/modules:

```sh
./angie-ctl.sh httpconf ls
./angie-ctl.sh mod ls
```

List all available configs/modules:

```sh
./angie-ctl.sh httpconf ls-available
./angie-ctl.sh mod ls-available
```

List all enabled configs/modules:

```sh
./angie-ctl.sh httpconf ls-enabled
./angie-ctl.sh mod ls-enabled
```

## Directories

- Available configs: `/etc/angie/http-conf-available.d`
- Enabled configs: `/etc/angie/http-conf.d`
- Available modules: `/etc/angie/modules-available.d`
- Enabled modules: `/etc/angie/modules.d`

The config root defaults to `/etc/angie` and can be overridden with the
`ANGIE_ETC` environment variable (must be an absolute path).

## Requirements

- POSIX `sh`
- Sufficient permissions to create/remove symlinks in Angie config directories

## Notes

- Names can be specified with or without the `.conf` extension
- Names must be a single path component; values containing `/` (or `.`/`..`) are rejected
- `dis` only removes symlinks — a real file placed in the enabled directory is never deleted
- Broken (dangling) symlinks are still listed and can be disabled
- `ls` marks an enabled entry with no source in the available directory as `[orphan]`

## Config test

After a successful `en`/`dis` batch, the script runs `angie -t` **once** (not
per item — a config may be enabled before the module it depends on, which would
make a per-item test fail on a valid intermediate state). On success it stays
quiet; on failure it prints the `angie -t` output, exits non-zero, and leaves
the changes in place (it does not roll back — a config that was already broken
before the run must not block every future operation). Skip the test with
`--no-test`, or point `ANGIE_BIN` at a specific binary. If `ANGIE_BIN` is not
found in `PATH`, the test is skipped with a notice.

## Development

Common tasks are wired through the `Makefile`:

```sh
make check          # shellcheck + hermetic tests (the CI gate)
make test           # run the hermetic test suite only
make test-container # integration test against real angie -t (needs Docker)
make check-all      # check + test-container
make lint           # shellcheck the shell scripts
make lint-md        # lint Markdown docs (rumdl)
make spell          # spell-check sources (typos)
make install        # install as angie-ctl into PREFIX/bin (honors DESTDIR)
```

`./test.sh` runs a self-contained suite against a throwaway `ANGIE_ETC` tree (no
root, no Angie install, no network; `angie -t` is stubbed). `./test-container.sh`
additionally drives a **real** `angie -t` inside the official Angie image to
verify the enable-by-symlink mechanism produces a config Angie accepts; it
self-skips when Docker or the image is unavailable.
