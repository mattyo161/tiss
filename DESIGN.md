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
   identity? Walk through creating one. `tiss self doctor` reports state
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
with `# @needs`; the dispatcher preflights them before exec (except for --help). Fallback to brew for tools outside mise's registry (e.g. miller).

### jq & jsonl — jq is a hard requirement

Commands emit streaming jsonl by default; jq is the universal joint.

### Helper suite (`lib/`, sourced via `source "$TISS_LIB/init.sh"`)

| Helper | Status | Purpose |
| --- | --- | --- |
| `logInfo/Warn/Error/Debug`, `pipe*`, `tee*` | done | Leveled stderr logging (`TISS_LOG_LEVEL`); pipe* logs stdin lines, tee* logs and passes through |
| `ts`, `utc`, `dur2s`, `ts2js` | done | One time standard everywhere; `dur2s` parses `1w1d5h` |
| `meta`, `metaAll`, `tissHelp` | done | Read `# @` annotations; render `--help` |
| `ensureTool` | done | Lazy install via mise |
| `saveData` / `readData` / `lsData` | done | Named pipe-friendly data store (see "Data store"); `lsData [prefix]` lists entries as jsonl with logical name, gzip/encrypted flags, size, mtime |
| `learnExec` | done | Prefix wrapper: echoes the (secret-sanitized) command to stderr as `[LEARN] ...` and appends to `$TISS_STATE/history.log` — teaches users what scripts actually run. Sanitizer redacts secret-looking flags, `key=value` pairs, AWS access keys; display only, real argv runs untouched |
| `cacheExec` | done | SHA-256 of argv + significant env vars (defaults cover AWS/GCP/kube context; extend via `TISS_CACHE_ENV`) keys a `saveData`-backed cache; `--duration` (default 1h), `--refresh`, `--encrypt`, `--no-gzip`; failing commands are never cached |
| `rmAfter` | done | Deferred deletion (`rmAfter 15s <tmpfile>`): epoch-prefixed symlinks in `$TISS_STATE/rmAfter`. Reaping happens on each rmAfter call plus a self-managing background monitor (pidfile-tracked, sleeps until next deadline capped at `TISS_RMAFTER_INTERVAL`=60s, exits when idle) — no permanent daemon. Deletion allowlist: only paths under home + tmp (or `TISS_RMAFTER_PATHS`) are ever deleted, enforced at schedule AND reap time |
| `bkup` | done | `cp -p` (`-Rp` for dirs) into a sibling `.bkup/` dir, named `<name>.<mtime-ts>` — idempotent for unchanged files (same mtime = same name = skipped); prints backup paths to stdout |
| format conversions | done | `csv2json`/`tsv2json`/`json2csv`/`json2tsv`/`json2md` as mlr façades (jsonl-first); `json2xlsx` is a python leaf via uv + PEP 723 inline deps — bold frozen header, comma number formats, real dates |
| fuzzy date parsing | done | `tiss dt parse`: python leaf (stdlib only), format battery + inference — 2-digit years 00-30→2000s/31-99→1900s, weekday overrides century, missing year resolves nearest-to-now; jsonl out, `--epoch/--iso/--ts` plain modes, stdin line mode |

### Overlay trees & config layering — implemented

A tree is any directory containing `scripts/`, with optional
`etc/config.sh` (defaults) and `lib/init.sh` (helpers) making it a
full-power overlay. `TISS_PATH` lists trees most-specific first; the core
(`$TISS_HOME`) is always last. First tree with a script match wins —
overlays may shadow core commands. Help, `--manifest` and completions
merge all trees (entries tagged with their source tree; shadowed entries
dropped). `tiss self tree add|remove|list` manages the stack, persisted as
`cfg TISS_PATH ...` in `~/.config/tiss/config.sh`; a `TISS_PATH` env var
overrides entirely.

Config layering uses `cfg VAR default...`, which only assigns when the
variable is empty — so whoever is sourced FIRST wins, and the environment
(set before any sourcing) always beats every file. Sourcing order: user
config, then tree configs most-specific first. Tree `lib/init.sh` files
load in REVERSE (least-specific first) so more specific function
definitions override.

## Decision log

| Date | Decision |
| --- | --- |
| 2026-07-14 | `self cd` can't chdir the parent shell — `tiss self init` emits an argv[0]-aware wrapper function (same emit pattern as completions) that intercepts `self cd` into a real pushd. dns/tmux/self-dev commands all learnExec-narrated; `tmux go` proves the interactive-guide pattern |
| 2026-07-14 | `tiss self shell` is the dev REPL: interactive bash with all helpers + overlay libs loaded, cwd = TISS_HOME, `tiss>` prompt (argv[0]-aware), own history file in TISS_STATE, rcfile self-destructs via rmAfter. Also scriptable: `printf 'dur2s 1w\nexit\n' \| tiss self shell` |
| 2026-07-14 | Namespace + help flag shows tiss namespace help (`tiss self --help` was falling through to passthrough and offering to install 'self'); other flags still pass through natively |
| 2026-07-14 | Passthrough installs gated by allowlist (curated built-ins + TISS_INSTALL_ALLOW): a typo must never become an install prompt. @needs-declared tools bypass the gate — the declaring script is the trust anchor |
| 2026-07-14 | Configuration is self-documenting and self-enforcing: etc/config.sh.example is the settings registry (fully commented cfg lines = defaults), seeded to ~/.config/tiss/config.sh on install, parsed by `tiss self config` for effective values, and a test fails when code references a TISS_* var missing from the template. TISS_DATA/TISS_STATE became config-settable (dispatcher defaults now apply after config loads) |
| 2026-07-14 | cacheExec cache control: `--no-cache` (bypass, cascades to nested calls via prefix-env TISS_NO_CACHE=1 — child-only, never mutates the caller) and `--recache` (invalidate FIRST, gone even on failure) vs `--refresh` (replace on success only). The boolean trio is scavenged from ANYWHERE in argv so wrappers passing "$@" inherit uniform cache control; value flags (--duration) stay prefix-only (collision risk); literal `--` stops scavenging (docker build --no-cache). Key derivation extracted to `tissCacheKey` |
| 2026-07-14 | `_self.*` namespace handlers: deepest wins, exact scripts beat it, bare namespace still shows help; replaces the ssm passthrough alias with intent-routing (reads cached via cacheExec --encrypt, writes narrated via learnExec, writes NEVER cached) |
| 2026-07-14 | Annotations parse from `#` and `//` comment styles; polyglot examples shipped for python/ruby/node/typescript/go (go via the `//usr/bin/env go run` polyglot line, ts via node type stripping) |
| 2026-07-14 | doctor scans all trees for non-executable scripts (the near-miss trap, caught at checkup time too) |
| 2026-07-14 | Near-miss detection: a would-match file that isn't executable errors with the chmod fix (exit 126) or warns-and-proceeds when a real binary exists — silent invisibility was the #1 new-user trap (Matt hit it) |
| 2026-07-14 | `help` is a first-class word: `tiss help <cmd>` prefix form (dispatcher) and bare `help` as first arg to any script (help triad `-h\|--help\|help`) |
| 2026-07-14 | Passthrough aliases may be multi-word (`ssm` -> `aws ssm`), so wrapper namespaces keep the whole underlying tool reachable |
| 2026-07-14 | Docs live in docs/ (getting-started, how-routing-works, writing-commands, cookbook-wrappers); `ssm get` is the canonical wrapper example |
| 2026-07-13 | Meta-commands live under `self` (`tiss self doctor|test|tree|completion`), rustup-style: top-level names stay free for passthrough tools (`tree`, `test` are real binaries), no `tiss tiss` stutter, reads clean through aliases (`x self doctor`). Renamed from the original `tiss` namespace pre-adoption, no compat path |
| 2026-07-13 | Overlay system: TISS_PATH most-specific-first, overlay wins, full-power trees (scripts+config+libs); `cfg` first-wins semantics make env > user > specific > core; managed via `tiss self tree` |
| 2026-07-13 | No TISS_ENV environment concept yet — AWS_PROFILE-style env vars already carry context and cacheExec keys on them; revisit when a wrapper needs it |
| 2026-07-14 | REVISITED (Matt requested): TISS_ENV environments via profile files (tree etc/env/<name>.sh loads first, user ~/.config/tiss/env/<name>.sh wins) — plain exports, not cfg. `tiss @<name> <cmd>` loads one per invocation; bare `tiss @<name>` = dev shell inside it; TISS_ENV joins the cacheExec key defaults so environments never share caches. Suffix `@` means versions: `tiss python@3.13` -> mise x (allowlist-gated) |
| 2026-07-14 | Dev shell grew `help` (command tree + loaded helpers) and a starship prompt (etc/starship.toml, env shown in yellow) with plain-PS1 fallback |
| 2026-07-13 | Wrapper library launches with git, db (encrypted-creds pattern), terraform (hard plan-file discipline, no force flag) — aws deferred |
| 2026-07-13 | Distribution: semver tags + curl-able install.sh + CONTRIBUTING; brew tap deferred until the interface settles |
| 2026-07-12 | Name: **tiss**; repo `mattyo161/tiss`, public from day one |
| 2026-07-13 | Name re-evaluated against `tise` (The Intuitive Scripting *Engine*) and rejected: Tise is Norway's largest resale marketplace (2.5M users, acquired by eBay in 2025) — an owned software brand with hopeless SEO; pronunciation is ambiguous (tice/teez/tee-seh); and "Engine" undersells the system (conventions + helpers + scripts, not just the dispatcher). The dispatcher may informally be called "the tiss engine" |
| 2026-07-12 | Invocation name user-chosen via symlink/alias; dispatcher argv[0]-aware |
| 2026-07-12 | Thin bash dispatcher + polyglot leaf scripts |
| 2026-07-12 | Metadata as `# @` comment annotations -> `--help` + `--manifest` jsonl |
| 2026-07-12 | Encryption: age with tiss-managed identity + per-session unlock (ssh-agent can't decrypt) |
| 2026-07-12 | Compression before encryption, always |
| 2026-07-12 | Lazy tool install delegated to mise |
| 2026-07-12 | rmAfter: state in `$TISS_STATE` (default `~/.local/state/tiss`), files only (never recurses); reap on rmAfter execution + pidfile-tracked monitor that retires when idle (not on every dispatch) |
| 2026-07-13 | rmAfter deletion allowlist (home + tmp default, `TISS_RMAFTER_PATHS` to customize), enforced at schedule and reap time — planted symlinks are dropped, never followed |
| 2026-07-13 | Shell completions: live from the tree via `--complete`/`--complete-zsh`, emitted by `tiss self completion <bash\|zsh>`, argv[0]-aware |
| 2026-07-12 | Data store: `$TISS_DATA` (default `~/.local/share/tiss/data`), one file per name, tmp+atomic rename, `/`-namespaced names |
| 2026-07-13 | Dispatcher preflights `# @needs` deps before exec; `--help` NEVER installs anything (asking about a command must be free) |
| 2026-07-13 | `ensureTool`: mise first, brew fallback for packages outside mise's registry (found via miller); one name-mapping function serves both |
| 2026-07-13 | Polyglot leaf convention: stdlib-only python leaves use plain `#!/usr/bin/env python3`; leaves needing third-party packages use uv + PEP 723 inline deps (`json2xlsx`). `# @` annotations work unchanged in python comments |
| 2026-07-13 | `dt` is a namespace (`tiss dt parse`), leaving room for `dt fmt`, `dt add`, ... |
| 2026-07-13 | Tests: dependency-free bash harness (no bats), isolated `TISS_DATA`/`TISS_STATE` per file, `tiss self test` runner; CI = shellcheck + suite on ubuntu & macos |
| 2026-07-13 | Portability probing order: GNU syntax first, BSD fallback (GNU `stat -f` silently prints filesystem info instead of erroring — CI caught it) |

## Open questions

- Cache eviction: stale cacheExec entries linger until overwritten —
  a `tiss self gc` sweep may be worth adding.
- Manifest schema versioning; `env`/side-effect annotations.
- Distribution: git clone + symlink today; brew tap / installer later.
- Reaper via launchd/systemd user units: would survive reboots (schedules
  currently wait for the next rmAfter call after a reboot). Must stay a
  *user* unit — the reaper needs the user's own permissions to clean up
  the files it created.
