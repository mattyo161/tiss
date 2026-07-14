# Contributing to tiss

Start with [docs/writing-commands.md](docs/writing-commands.md) and
[docs/how-routing-works.md](docs/how-routing-works.md). The whole design
fits in [DESIGN.md](DESIGN.md) — principles, subsystem
docs, and a decision log explaining every judgment call. Read it first;
it's the fastest way to write code that fits.

## Adding a command

Create an executable file in `scripts/` — the path IS the command:

```bash
# scripts/aws/whoami.sh  ->  tiss aws whoami
#!/usr/bin/env bash
# @description One-line summary (shows in help, completions, --manifest)
# @usage tiss aws whoami
# @example tiss aws whoami | jq .Account
# @needs aws
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help) tissHelp "$0"; exit 0 ;;
esac

# your logic — helpers like logInfo, learnExec, cacheExec, saveData are loaded
```

`chmod +x` it. Done — help, completion, and the manifest pick it up live.
Python leaves work the same way (stdlib: plain `python3` shebang;
third-party deps: uv + PEP 723 inline metadata — see
`scripts/json2xlsx.py`).

## House conventions (enforced by review)

- **`# @` annotations** on every script: `@description`, `@usage`,
  `@example` (repeatable), `@needs` (space-separated tools — the
  dispatcher auto-installs them, except for `--help`).
- **camelCase = sourced helper function**, path = command. Don't "fix" it.
- **`--no-<flag>` negates any defaulted flag** (`--gzip`/`--no-gzip`).
- **Durations** are `1w2d3h4m5s`; bare number = minutes. Use `dur2s`.
- **Logs to stderr** (`logInfo`...), **data to stdout**. jsonl for
  structured output.
- **Wrap unix tools, don't reinvent** — and narrate multi-step work with
  `learnExec` so scripts teach.
- **bash 3.2 compatible** (macOS ships it): no associative arrays, no
  `${var,,}`, no mapfile. GNU-vs-BSD: probe GNU syntax first (BSD errors
  cleanly; GNU sometimes doesn't — see the decision log).

## Development loop

```sh
tiss self test        # dependency-free suite; add tests with your change
mise x shellcheck -- shellcheck bin/tiss lib/*.sh scripts/*.sh scripts/*/*.sh tests/*.sh
```

Both run in CI (ubuntu + macos). PRs need green CI and test coverage for
new behavior — the suite is the contract.

## Company/private scripts

Don't PR company-specific wrappers into the core — that's what overlay
trees are for (`tiss self tree add ~/work/acme-tiss`, see DESIGN.md).
Core wrappers encode *generic* best practice.

## Commits & releases

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org)
(CI enforces it): `feat: ...`, `fix: ...`, `docs:`/`test:`/`chore:`/...,
with `!` or a `BREAKING CHANGE:` footer for majors. Releases are
automated by release-please: merging its release PR bumps `version.txt`,
updates `CHANGELOG.md`, tags, and publishes the GitHub release —
`feat` bumps minor, `fix` bumps patch, breaking bumps major. Check the
installed version any time with `tiss --version`.

## Decisions

Non-obvious judgment calls get a row in DESIGN.md's decision log — date,
decision, why. If your PR makes one, log it.
