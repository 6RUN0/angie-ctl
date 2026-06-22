# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

A Russian translation of this file is maintained at [CHANGELOG.ru.md](CHANGELOG.ru.md).

## [Unreleased]

## [0.1.0] - 2026-06-22

### Added

- `-V`/`--version` option: print the tool version and exit.
- `status` command: report `[on ]`/`[off]` per name, exiting `0` only when every
  queried name is enabled, so callers can gate on it.
- `prune` command: remove every orphaned enabled symlink (active but with no source
  in the available directory).
- `ls` now marks enabled entries with no source as `[orphan]` in a second pass.
- `-r`/`--reload` option: run `ANGIE_RELOAD_CMD` (default `$ANGIE_BIN -s reload`)
  after a successful batch.
- `--rollback` option: undo exactly this run's changes when the post-batch config
  test fails (cannot be combined with `--no-test`).
- `-n`/`--dry-run` and `-T`/`--no-test` options.
- Configuration test: run `$ANGIE_BIN -t` once after a successful `en`/`dis`/`prune`
  batch (skipped under `--dry-run`/`--no-test`, or if the binary is absent).
- Project tooling: `Makefile`, hermetic `test.sh` suite, container integration test
  `test-container.sh`, and GitHub Actions CI.

### Changed

- The configuration test and reload resolve and run under a fixed, trusted `PATH`
  (`SAFE_PATH`, `/usr/sbin:/usr/bin:/sbin:/bin`) so an inherited/hostile `PATH`
  cannot redirect them; an absolute `ANGIE_BIN` bypasses the lookup.
- A failed configuration test now leaves changes in place by default with an
  actionable message; `--rollback` opts into undoing them instead.
- `do_rollback` reads its undo log from a here-document rather than a pipe, so it
  runs in the current shell, counts failed undo steps, and reports an incomplete
  rollback via `finalize_batch`.

### Fixed

- Resolve a contradiction in the failure output: under `--rollback` the run no longer
  prints "changes left in place" immediately before reporting the rollback.
- Omit an empty `readlink` target from the undo log (with a warning) instead of
  recording an entry that rollback cannot recreate.

### Security

- `is_safe_name` rejects empty, `.`, `..`, and any name containing a slash, blocking
  path traversal; it now also rejects tab and newline so a name can never corrupt the
  rollback undo log.
- `ANGIE_ETC` is validated at startup to be an absolute path with no `..` or `//`
  segments.
- `do_disable`/`do_prune` remove a target only after confirming it is a symlink, so a
  real config placed by hand is never deleted.

### Documentation

- Document the `ANGIE_RELOAD_CMD` trust boundary: it is executed as a word-split
  command line with the process's privileges, so it must be set by a trusted operator
  and not forwarded from a less-trusted caller (drop it via sudo `env_delete` when
  wrapping). `SAFE_PATH` only protects the lookup of the command's first word.

[Unreleased]: https://github.com/6RUN0/angie-ctl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/6RUN0/angie-ctl/releases/tag/v0.1.0
