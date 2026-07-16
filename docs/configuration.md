# Configuration reference

Every knob in tiss, in one place. The quickest tour is on your own
machine: `tiss config` lists each setting with its current
effective value.

## Precedence (highest wins)

```
1. environment variables        set before anything is sourced
2. ~/.config/tiss/config.sh    your file (tiss config edit)
3. overlay tree etc/config.sh  most-specific tree first
4. core defaults
```

The mechanism: every config file assigns through `cfg NAME value`, which
only sets `NAME` when it's empty — so whoever is sourced *first* wins,
and the environment (already set before sourcing) beats every file.
Overlay trees carry team defaults; your file overrides theirs; a shell
export overrides everything for one invocation:

```sh
TISS_LOG_LEVEL=DEBUG tiss ssm get --path /develop
```

## Settings

| Setting | Default | What it controls |
| --- | --- | --- |
| `TISS_AUTO_INSTALL` | `ask` | Missing-tool behavior at passthrough/`@needs` time: `ask` prompts, `always` installs silently, `never` refuses with instructions |
| `TISS_LOG_LEVEL` | `INFO` | stderr verbosity: `ERROR` \| `WARN` \| `INFO` \| `DEBUG` |
| `TISS_ENV` | empty | Active environment profile. Set per-invocation with the `@` prefix (`tiss @prod ssm get ...`) or per-shell; participates in every cacheExec key, so environments never share cache entries |
| `TISS_INSTALL_ALLOW` | empty | Extra tools passthrough may auto-install, beyond the curated built-in set (age, git, jq, rg, terraform, ...). `@needs`-declared tools are always allowed — this gates only commands you type |
| `TISS_PATH` | empty | Overlay tree stack, colon-separated, most specific first. Prefer `tiss pile add` (persists it here for you) |
| `TISS_DATA` | `~/.local/share/tiss/data` | The data store: `saveData`/`readData`/`lsData`, `cacheExec` entries, `db` credentials |
| `TISS_STATE` | `~/.local/state/tiss` | State: `rmAfter` schedules, the `learnExec` history log |
| `TISS_SHIMS` | `~/.local/share/tiss/shims` | Shortcut shim dir ([shortcuts](shortcuts.md)): each shortcut name is a symlink here back to the dispatcher. `tiss init` puts it first on PATH; the dispatcher strips it from child PATHs |
| `TISS_TREES` | `~/.local/share/tiss/trees` | Where tree packages (`tiss +name`) are cloned. `-name` disables without deleting the clone |
| `TISS_TREES_REPO` | tiss's own origin | Distribution repo for short tree-package names — packages live on branches named `tiss/<name>`, versions are tags `tiss/<name>@<ver>`, `@latest` = branch head (forces a fetch) |
| `TISS_CACHE_ENV` | empty | Extra env var names (space-separated) added to `cacheExec` keys, on top of the built-ins (`AWS_PROFILE`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_ACCESS_KEY_ID`, `GOOGLE_CLOUD_PROJECT`, `CLOUDSDK_ACTIVE_CONFIG_NAME`, `KUBECONFIG`) |
| `TISS_NO_CACHE` | `0` | `1` bypasses all `cacheExec` reads *and* writes. Usually set per-invocation by the `--no-cache` flag (which cascades it to child processes) rather than persistently |
| `TISS_CACHE_NOTICE` | `1` | Announce cache hits on stderr (`[CACHE] <cmd> (age 3m, expires in 12m — --refresh reruns)`) so cached data never masquerades as fresh; `0` silences |
| `TISS_RMAFTER_PATHS` | home + tmp locations | Deletion allowlist: `rmAfter` only ever deletes under these colon-separated prefixes, enforced at schedule *and* reap time |
| `TISS_RMAFTER_INTERVAL` | `60` | Max seconds the rmAfter background monitor sleeps between reap checks |
| `TISS_AJL_CACHE_DURATION` | `15m` | How long `tiss ajl` caches read results (`get-*`/`describe-*`/`list-*`; `--params-json` streams are never cached) |
| `TISS_AJL_CACHE_ENCRYPT` | `0` | Encrypt cached ajl results at rest (`1` to enable) |
| `TISS_SSM_CACHE_DURATION` | `1h` | How long `tiss ssm` caches read results (tiss duration grammar) |
| `TISS_SSM_CACHE_ENCRYPT` | `1` | Encrypt cached ssm results at rest (`0` to disable) |

## Env-only settings

These can't live in the config file — they're needed to *find* it (or
are derived):

| Variable | Default | What it is |
| --- | --- | --- |
| `TISS_CONFIG` | `~/.config/tiss` | The config directory itself |
| `TISS_HOME` | auto-detected | The tiss install root (dispatcher resolves its own symlink) |
| `TISS_NAME` | argv[0] | The name tiss was invoked as — set by symlinking/aliasing, not by config |

## Your config file

`~/.config/tiss/config.sh` is seeded from a fully commented template on
install (or on first `tiss config`): every setting documented with
its default, commented out. Uncomment to override:

```sh
tiss config          # list settings + effective values
tiss config edit     # open in $EDITOR (creates if missing)
```

`tiss pile add` also writes to this file (a managed `cfg TISS_PATH`
line); your own lines are preserved.

## Environments

An environment profile is a plain shell file of exports — AWS profile,
region, kube context, whatever defines "prod" for you:

```sh
tiss env edit prod     # creates ~/.config/tiss/env/prod.sh, opens it
tiss @prod ssm get --path /prod/app     # one command in that environment
tiss @prod                              # dev shell inside it (prompt shows the env)
tiss env list|show NAME            # what exists, what loads
```

Profiles layer like everything else: a tree's `etc/env/prod.sh` (team
defaults) loads first, yours loads last and wins. `TISS_ENV` is part of
every cacheExec key, so `@dev` and `@prod` caches never mix. The `@`
prefix in the *suffix* position means versions instead:
`tiss python@3.13 script.py` runs through `mise x` without touching your
global toolchain.

## Per-wrapper settings convention

Wrapper-specific knobs follow the `TISS_<NAMESPACE>_<SETTING>` pattern
(`TISS_SSM_CACHE_DURATION`) and are declared in the wrapper via
`cfg TISS_SSM_CACHE_DURATION 1h` — meaning any layer above can override
them. New wrappers should do the same, and add their settings to
`etc/config.sh.example` — the test suite fails if a `TISS_*` variable is
referenced in code but missing from the template.
