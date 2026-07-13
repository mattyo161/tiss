# tiss — Design

**tiss** (The Intuitive Scripting System) is a directory-routed universal
script CLI: a single entry point that turns a tree of scripts into a
discoverable, composable command language shared by humans and AI agents.

It is the open-source successor to a system built and battle-tested over
years at a previous job, and heir to an older naming tradition (TIPS — The
Intuitive Pagination System, from the newspaper era). *Intuitive* is the
load-bearing word: every design decision below should make the tool guide
its user — human or AI — toward the right next step and toward best
practices, without requiring them to read this document first.

## Principles

1. **The directory tree is the command language.** `tiss git clone` runs
   `scripts/git/clone.sh`. Adding a command is creating a file; no
   registration, no build step.
2. **Wrap, don't reinvent.** Prefer existing unix tools (`age`, `jq`, `rg`,
   `jc`, `mlr`, ...) wrapped with business context and good defaults.
3. **AI-legibility is a first-class goal.** Every command self-describes in a
   machine-readable way (`--manifest`); conventions are consistent enough
   that an agent can predict them. Humans and AI share one vocabulary.
4. **Guide, never strand.** Missing tool? Offer to install it. No encryption
   identity? Walk through creating one. `tiss tiss doctor` reports state
   with hints, not just failures.
5. **Pipes are the composition model.** Commands stream jsonl by default so
   everything chains through `jq` and friends.

## Architecture

```
bin/tiss          the dispatcher (bash, portable to macOS's bash 3.2)
lib/              helper suite, sourced by every script via init.sh
scripts/          the command tree — the file path IS the command path
~/.config/tiss/   per-user config, encryption identity   (TISS_CONFIG)
```

### Invocation name is user-chosen

Nobody is forced to type `tiss`. Symlink or alias the dispatcher under any
name (`ln -s .../bin/tiss /usr/local/bin/x`) and all help/usage output
follows that name (argv[0]-aware). The dispatcher resolves symlinks
portably (BSD readlink safe) to locate its real tree. This leaves the door
open to busybox-style multiplexing later (a symlink name mapping into a
namespace, e.g. `tf` -> `tiss terraform`).

### Command resolution

For `tiss a b c ...`, most specific wins:

1. **Exact script** — first executable matching `scripts/a` or `scripts/a.*`
   (descending one directory level per token). Extension is irrelevant to
   the caller: leaf scripts are polyglot (bash, python, anything
   executable).
2. **Namespace landing** — `tiss git` with `scripts/git/` and no further
   match shows that namespace's commands.
3. **Passthrough** — otherwise behave as if the tool were called natively:
   `tiss git push` with no `git/push.*` script execs `git push`. Missing
   tools are lazy-installed first (see below).

Flags (`-*`) never route; they belong to the matched script.

### Metadata annotations

Every script self-describes in `# @key value` header comments — single
source of truth, parsed by the dispatcher for `--help`, namespace listings,
and `--manifest`:

```bash
# @description Clone a repo with our defaults
# @usage tiss git clone <repo>
# @example tiss git clone git@github.com:user/repo
# @needs git
```

`tiss --manifest` emits one JSON object per command (jsonl) — the AI-facing
contract. Planned keys beyond the current ones: `env` (variables that
affect output, feeding cacheExec), `type: passthrough` entries for wrapped
tools, side-effect/danger markers.

### Conventions

- **camelCase = sourced helper function** (`saveData`, `logInfo`,
  `cacheExec`); **path = script**. The contrast is intentional signal.
- **`--no-<flag>` negates `--<flag>`** anywhere flags have defaults
  (`--gzip` / `--no-gzip`).
- **Durations** are `<n>w <n>d <n>h <n>m <n>s` combined freely (`1w1d5h`);
  a bare number means minutes. One format everywhere (`--duration`,
  `rmAfter`, `utc`).
- **File extensions encode the write pipeline**: `name.jsonl.gz.age` was
  json-lines, gzipped, then encrypted. Read right-to-left to unwind. Files
  self-describe; readers need no flags.
- **Logs to stderr, data to stdout.** Always. Pipelines stay clean.

## Core subsystems

### Encryption (`tiss encrypt` / `tiss decrypt` / `tiss lock`) — implemented

Engine: [age](https://age-encryption.org). tiss generates its own age
identity at first use (guided, once per machine), protected by a
user-chosen passphrase:

- `~/.config/tiss/age/recipients.txt` — public key. Encryption uses only
  this: **encrypt never prompts**, safe in pipelines and cron.
- `~/.config/tiss/age/identity.age` — the private identity, passphrase-
  encrypted.

Decryption unlocks the identity **once per session** (passphrase prompt),
caching the unlocked identity in a 0700 per-user tmp dir; `tiss lock`
forgets it. This is deliberate: ssh-agent cannot decrypt (the agent
protocol only signs), so tiss provides its own session-unlock rather than
pretending otherwise. Compression always happens *before* encryption
(encrypted bytes don't compress).

### Data store (`saveData` / `readData`) — implemented

Named pipe-friendly storage: `... | saveData name` writes stdin to the
data dir (`$TISS_DATA`, default `~/.local/share/tiss/data`);
`readData name | ...` streams it back.

- Writes stream to a tmp file next to the target and are renamed
  atomically on completion — readers never see partial data.
- `--gzip` on by default; `--encrypt` chains the encryption subsystem
  (public-key only, so saving never prompts; reading unlocks per session).
- Extensions record the pipeline (`name.gz.age`), and `readData` unwinds
  them right-to-left automatically — no flags on the read side.
- **One file per name**: a successful save removes variants written with
  different options; if a crashed save ever leaves duplicates, newest wins.
- Names may contain `/` for namespacing (`aws/params`); absolute paths and
  `..` are rejected.
- Implemented as lib functions (`lib/data.sh`) so scripts call them
  in-process, with thin `scripts/saveData.sh` / `readData.sh` wrappers so
  they are also commands (`tiss saveData ...`) and appear in `--manifest`.

### Tool wrapping & lazy install — implemented (v1)

`ensureTool <name>` checks PATH and otherwise installs via **mise**
(version-pinned, cross-platform, no sudo — and bootstrappable itself).
`TISS_AUTO_INSTALL=ask|always|never` controls prompting. A small mapping
handles command-vs-package names (`rg` -> `ripgrep`). Scripts declare deps
with `# @needs`, enabling preflight.

### jq & jsonl — jq is a hard requirement

Commands emit streaming jsonl by default; jq is the universal joint.

### Helper suite (`lib/`, sourced via `source "$TISS_LIB/init.sh"`)

| Helper | Status | Purpose |
| --- | --- | --- |
| `logInfo/Warn/Error/Debug`, `pipe*`, `tee*` | done | Leveled stderr logging (`TISS_LOG_LEVEL`); pipe* logs stdin lines, tee* logs and passes through |
| `ts`, `utc`, `dur2s`, `ts2js` | done | One time standard everywhere; `dur2s` parses `1w1d5h` |
| `meta`, `metaAll`, `tissHelp` | done | Read `# @` annotations; render `--help` |
| `ensureTool` | done | Lazy install via mise |
| `saveData` / `readData` | done | Named pipe-friendly data store (see "Data store") |
| `learnExec` | done | Prefix wrapper: echoes the (secret-sanitized) command to stderr as `[LEARN] ...` and appends to `$TISS_STATE/history.log` — teaches users what scripts actually run. Sanitizer redacts secret-looking flags, `key=value` pairs, AWS access keys; display only, real argv runs untouched |
| `cacheExec` | done | SHA-256 of argv + significant env vars (defaults cover AWS/GCP/kube context; extend via `TISS_CACHE_ENV`) keys a `saveData`-backed cache; `--duration` (default 1h), `--refresh`, `--encrypt`, `--no-gzip`; failing commands are never cached |
| `rmAfter` | done | Deferred deletion (`rmAfter 15s <tmpfile>`): epoch-prefixed symlinks in `$TISS_STATE/rmAfter`. Reaping happens on each rmAfter call plus a self-managing background monitor (pidfile-tracked, sleeps until next deadline capped at `TISS_RMAFTER_INTERVAL`=60s, exits when idle) — no permanent daemon. Deletion allowlist: only paths under home + tmp (or `TISS_RMAFTER_PATHS`) are ever deleted, enforced at schedule AND reap time |
| `bkup` | done | `cp -p` (`-Rp` for dirs) into a sibling `.bkup/` dir, named `<name>.<mtime-ts>` — idempotent for unchanged files (same mtime = same name = skipped); prints backup paths to stdout |
| fuzzy date parsing | planned | Multi-format parse with century/year inference — real logic, likely a python leaf, same conventions replicated per-language |
| format conversions | planned | `csv2json`, `json2csv`, `md` tables, xlsx-with-formatting — thin façades over `jc`, `miller`, a python leaf for xlsx |

## Decision log

| Date | Decision |
| --- | --- |
| 2026-07-12 | Name: **tiss**; repo `mattyo161/tiss`, public from day one |
| 2026-07-12 | Invocation name user-chosen via symlink/alias; dispatcher argv[0]-aware |
| 2026-07-12 | Thin bash dispatcher + polyglot leaf scripts |
| 2026-07-12 | Metadata as `# @` comment annotations -> `--help` + `--manifest` jsonl |
| 2026-07-12 | Encryption: age with tiss-managed identity + per-session unlock (ssh-agent can't decrypt) |
| 2026-07-12 | Compression before encryption, always |
| 2026-07-12 | Lazy tool install delegated to mise |
| 2026-07-12 | rmAfter: state in `$TISS_STATE` (default `~/.local/state/tiss`), files only (never recurses); reap on rmAfter execution + pidfile-tracked monitor that retires when idle (not on every dispatch) |
| 2026-07-13 | rmAfter deletion allowlist (home + tmp default, `TISS_RMAFTER_PATHS` to customize), enforced at schedule and reap time — planted symlinks are dropped, never followed |
| 2026-07-13 | Shell completions: live from the tree via `--complete`/`--complete-zsh`, emitted by `tiss tiss completion <bash\|zsh>`, argv[0]-aware |
| 2026-07-12 | Data store: `$TISS_DATA` (default `~/.local/share/tiss/data`), one file per name, tmp+atomic rename, `/`-namespaced names |

## Open questions

- Cache eviction: stale cacheExec entries linger until overwritten —
  a `tiss tiss gc` sweep may be worth adding.
- Config & environments: where business context lives (per-user vs
  per-repo vs per-env), and how open-source core separates from
  company-private script trees (overlay search path? `TISS_PATH`?).
- Manifest schema versioning; `env`/side-effect annotations.
- Distribution: git clone + symlink today; brew tap / installer later.
- Reaper via launchd/systemd user units: would survive reboots (schedules
  currently wait for the next rmAfter call after a reboot). Must stay a
  *user* unit — the reaper needs the user's own permissions to clean up
  the files it created.
