# Agent Guide for tiss

tiss (The Intuitive Scripting System) is a bash CLI where the `scripts/` tree
IS the command language: `scripts/git/clone.sh` becomes `tiss git clone`,
unmatched commands pass through to the real tool (lazy-installed via mise),
and everything streams JSONL. Help, completion, and the AI-facing manifest
derive live from the tree and each script's `# @` annotations.

House rules: see [docs/AI_GUIDE.md](docs/AI_GUIDE.md). This file holds only
what is specific to this repo.

## Commands

```shell
tests/run.sh                        # full suite (tests/test_*.sh); run before every commit
bash tests/test_bkup.sh             # one test file while iterating
mise x shellcheck -- shellcheck bin/tiss lib/*.sh scripts/*.sh scripts/*/*.sh tests/*.sh
bin/tiss doctor                     # setup / conformance check
bin/tiss --manifest                 # every command self-described as jsonl
```

## Map

- `bin/tiss` — the dispatcher: tree routing, passthrough, shim handling.
- `lib/*.sh` — the sourced helper suite every script gets (logInfo/pipeInfo/
  teeInfo, cacheExec, learnExec, encrypt/decrypt, saveData/readData, rmAfter).
- `scripts/<name>/<cmd>.sh` — the command tree; adding a command is creating
  an executable file with `# @` annotations.
- `etc/` — reserved lexicon and package/pile config.
- `tests/` — plain-bash test files + `harness.sh`; `tests/run.sh` sums them.
- `docs/` — user-facing deep dives (routing, pile, shortcuts, wrappers).
- `DESIGN.md` — decision log; `version.txt`/CHANGELOG are release-please
  managed — do not hand-edit.

## Style

Bash with `set -u` discipline; helpers over raw commands (`logInfo "msg"`
not `echo`); every script self-describes via `# @describe` / `# @arg`
annotations; stdout is data (JSONL where applicable), stderr is narration
with the `[LEVEL]` prefix. Match `lib/` idioms before inventing new ones.

## Boundaries

**Always:** run `tests/run.sh` and shellcheck before committing; keep new
commands self-describing (annotations) so manifest/help/completion stay true;
use conventional commits (release-please derives versions from them).

**Ask first:** changes to the reserved lexicon (names that must never be
shadowed by trees); changes to shim/PATH handling in the dispatcher
(recursion and leak guards live there); merging release PRs.

**Never:** hand-edit `version.txt` or `CHANGELOG.md` (release-please owns
them); let `encrypt` prompt for input (public-key only by design); write
secrets or identity into tracked files.

## Verification

Drive the real dispatcher: `bin/tiss <your command>` on a change, plus
`bin/tiss doctor` for conformance and `bin/tiss --manifest | jq` to confirm
annotations parse. For first-run UX changes, replay the empty-machine
experience in a container: mount the repo read-only into `amazonlinux:2023`
and run doctor (recipe in the vault's DevOps snippets).
