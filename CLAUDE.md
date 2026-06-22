# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`angie-ctl.sh` is a single-file POSIX `sh` helper that enables/disables Angie
HTTP configs and modules by managing symlinks — the a2enconf/a2enmod pattern
ported from Apache to Angie. There is no build step, no dependencies beyond a
POSIX shell, and the whole program lives in `angie-ctl.sh`.

## Architecture

The script maps a *type* argument to a pair of directories and then dispatches
a *command* against them:

- `httpconf` → available `$ANGIE_ETC/http-conf-available.d`, enabled `$ANGIE_ETC/http-conf.d`
- `mod` → available `$ANGIE_ETC/modules-available.d`, enabled `$ANGIE_ETC/modules.d`

`$ANGIE_ETC` (default `/etc/angie`) is the base path; the code also reads
`ANGIE_BIN` (config-test binary) and `ANGIE_RELOAD_CMD` (reload command).
Enabling creates a *relative* symlink (`ln -s "../$subdir/$name"`) from the
enabled dir into the available dir so the link survives the tree being moved;
disabling removes that symlink. Names resolve with or without a `.conf` suffix
via `resolve_name_available` / `resolve_name_enabled` (tries the bare name
first, then `name.conf`). Listing (`ls`) walks the available dir and marks each
entry `[on ]`/`[off]`, then a second pass marks enabled entries with no source
as `[orphan]`.

Commands: `en`/`dis` (mutate), `status` (report `[on ]`/`[off]`, exit 0 only if
all enabled), `prune` (remove all orphan symlinks), `ls`/`ls-available`/
`ls-enabled`. Global options precede the type/command: `-n`/`--dry-run`,
`-T`/`--no-test`, `-r`/`--reload`, `--rollback`. The mutating commands
(`en`/`dis`/`prune`) share a tail, `finalize_batch`: run the config test once,
then either reload (`run_reload`, on success) or, with `--rollback`, undo this
run via `do_rollback` (driven by the `UNDO_KIND`/`UNDO_LIST` records each
command builds). `--rollback` with `--no-test` is rejected up front.

Both type and command accept aliases (e.g. `mod`/`module`/`modules`,
`en`/`enable`, `dis`/`disable`, `ls`/`list`, `status`/`stat`). The dispatch
happens in two `case` blocks: type → directory selection near the top, command
→ action at the bottom.

## Conventions

- Keep it POSIX `sh`-compatible — no bashisms (the shebang is `#!/bin/sh`).
- Indentation is 2-space, LF, UTF-8, final newline (enforced by `.editorconfig`).
- Errors go to stderr; functions accumulate a non-zero `rc` across multiple
  names and `exit $rc` at the end so one bad name doesn't abort the batch.

## Safety invariants

The script is meant to manage only symlinks inside the two managed dirs. Two
guards enforce that and must be preserved:

- `is_safe_name` rejects empty / `.` / `..` / any name containing `/`, called
  at the top of every `do_enable`/`do_disable` loop iteration. This blocks
  path traversal (e.g. `dis ../something` deleting files outside the tree).
- `do_disable` removes a target only after `[ -L "$dst" ]` confirms it is a
  symlink, so a real config placed by hand in the enabled dir is never deleted.

`ANGIE_ETC` is validated at startup to be an absolute path with no `..` or `//`
segments, so it cannot redirect operations outside the intended tree when the
tool is wrapped (sudo/CI) and the value comes from a less-trusted caller.
List/resolve checks use `[ -e ... ] || [ -L ... ]` so dangling symlinks stay
visible and removable.

The deployment model assumes the managed dirs are root-owned and not
group/world-writable; the `[ -L "$dst" ]` guard and `is_safe_name` are not a
substitute for that (a TOCTOU race is only reachable if those dirs are
attacker-writable).

## Config test

`run_config_test` runs `$ANGIE_BIN -t` (default `angie`) **once after a batch**
of `en`/`dis`/`prune`, never per item: a config may be enabled before the module
it needs, so a per-item test would fail on a valid intermediate state. It runs
only when a change was actually applied (`changed > 0`), is skipped under
`--dry-run` / `--no-test`, and is skipped with a notice if `$ANGIE_BIN` is absent
(which is why `test.sh` is hermetic). The test resolves and runs `$ANGIE_BIN`
under a fixed `PATH` (`SAFE_PATH`, `/usr/sbin:/usr/bin:/sbin:/bin`) so an
inherited/hostile `PATH` cannot redirect it to an attacker binary; an absolute
`ANGIE_BIN` bypasses the lookup and is honored as-is (this is what `test.sh`
relies on for its stub). On failure it reports and exits non-zero. Success is
quiet (the binary's output is shown only on failure). `test.sh` exercises this
with a stub `angie` of controllable exit code.

By **default** a failed test leaves the changes in place — a config already
broken before the run must not block every future operation. `--rollback` opts
into undoing exactly this run's changes instead (`do_rollback`: `rm` for the
symlinks `do_enable` created, `ln -s` from the captured `readlink` target for
those `do_disable`/`do_prune` removed). The undo log is the newline-separated
`UNDO_LIST`; this assumes config names contain no newline, which holds for real
Angie configs and is the reason names stay single path components. `--reload`
runs `ANGIE_RELOAD_CMD` (default `$ANGIE_BIN -s reload`) under `SAFE_PATH` after
a successful batch; a failed test prevents the reload, and a rollback never
reloads (state is already back to the prior, loaded config). In `--dry-run`,
the mutating commands count intended changes so the preview can show the reload
step, while `run_config_test` still no-ops on the dry-run guard.

History note: commit `4cc3903 "remove config test"` had earlier removed an
`angie -t` step; it was reintroduced with the batch-once semantics above. Keep
the two READMEs in sync (`README.ru.md` is the Russian translation of
`README.md`).

## Commands

The `Makefile` is the entry point (`make help` lists targets):

- `make check` — the CI gate: `shellcheck -s sh` on the scripts, then `./test.sh`.
- `make lint` / `make test` — the two halves of `check` individually.
- `make test-container` / `make check-all` — the container integration test
  (real `angie -t`), alone or appended to `check`.
- `make lint-md` (rumdl) / `make spell` (typos) — doc/spelling checks; both are
  configured to pass (`.rumdl.toml` disables MD013 line-length).
- `make install` / `make uninstall` — install `angie-ctl.sh` as `angie-ctl` into
  `PREFIX/bin` (default `/usr/local`); honors `DESTDIR` and `PREFIX` for packaging.

Optional-tool targets degrade gracefully (skip with a notice) if the tool is
absent, so `make check` only hard-requires `shellcheck`.

CI is `.github/workflows/ci.yml`: a `check` job (`make check`) and a
non-blocking (`continue-on-error`) `container` job that pulls the Angie image
and runs `make test-container`. Keep it clean under `actionlint` and `zizmor`
(actions pinned to a commit SHA, `persist-credentials: false`, `permissions:
contents: read`).

## Testing

Two tiers:

- `./test.sh` — hermetic POSIX suite (TAP-ish). Builds a throwaway `ANGIE_ETC`
  tree in a temp dir and drives the real script; no root, no Angie binary, no
  network. The config-test path is covered with a stub `angie` of controllable
  exit code. This is the default gate (`make check`); add cases here.
- `./test-container.sh` — integration test against a **real** `angie -t` inside
  the official image (`docker.angie.software/angie:latest`). It writes an
  a2enconf-style layout into `/etc/angie` with a main config that includes the
  managed dir, then asserts that enabling a valid config passes and a broken one
  fails. This is what the stub cannot prove: that the symlink-into-included-dir
  mechanism yields a config Angie actually parses. Opt-in (`make test-container`)
  and self-skipping (exit 0) when Docker or the image is absent, so `make check`
  stays Docker-free.

For one-off manual checks, point `ANGIE_ETC` at a temp tree the same way:

```sh
ANGIE_ETC=/tmp/angie-test ./angie-ctl.sh httpconf ls
```
