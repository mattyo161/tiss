# Writing commands

A command is an executable file in a tree's `scripts/` directory. The
path is the name: `scripts/ssm/get.sh` → `tiss ssm get`. No
registration, no build step — save, `chmod +x`, done.

## The skeleton

```bash
#!/usr/bin/env bash
# @description One line: shows in help, completions, and --manifest
# @usage tiss ssm get (--name N | --path P) [--duration 1h]
# @example tiss ssm get --path /develop | jq -r .Name
# @needs aws jq
set -euo pipefail
source "$TISS_LIB/init.sh"

# ... parse args (below), do the work
```

- **`# @` annotations** are the single source of truth. The dispatcher
  parses them for `--help`, namespace listings, and the jsonl manifest
  that AI agents read. `@needs` tools are auto-installed before the
  script runs.
- **`source "$TISS_LIB/init.sh"`** loads the whole helper suite —
  `logInfo`, `learnExec`, `cacheExec`, `saveData`, `dur2s`, `cfg`, plus
  any overlay-tree helpers and layered config.
- Python works identically — annotations are just `#` comments. Stdlib
  only: plain `#!/usr/bin/env python3`. Third-party deps: uv + PEP 723
  inline metadata (see `scripts/json2xlsx.py`).

## Arg parsing: the house pattern

One loop, one `case`, order-independent:

```bash
mode="" dur="1h" refresh="" extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)          # ALWAYS first: the help triad
      tissHelp "$0"; exit 0 ;;
    --name)  mode=name; value="${2:?--name needs a value}"; shift ;;
    --refresh) refresh=1 ;;
    --no-cache) cache=0 ;;       # --no-X negates any defaulted --X
    *) extra+=("$1") ;;          # or: logError "unknown: $1"; exit 2
  esac
  shift
done
```

Rules the pattern encodes:

1. **Any order.** Because every arg goes through the same loop,
   `--path /p --duration 1d` and `--duration 1d --path /p` are
   identical. Never require a fixed position for flags.
2. **The help triad**: `-h`, `--help`, and bare `help` as the first
   token all print help. (`tiss help <command>` works too — the
   dispatcher handles that form.)
3. **`--no-<flag>` negates** any flag that defaults on. `--gzip` /
   `--no-gzip`, `--encrypt` / `--no-encrypt`.
4. **Value flags** use `"${2:?--flag needs a value}"` + `shift` — free
   error message, no silent empty values.
5. **Unknown args**: choose deliberately. *Wrappers* collect them and
   pass through to the wrapped tool (`extra+=("$1")`) so the native
   surface stays available. *Standalone commands* reject them
   (`logError` + exit 2). Never silently drop.
6. **Durations** are always the tiss grammar: `1w2d3h4m5s`, bare number
   = minutes. Parse with `dur2s`, don't invent formats.

## Output discipline

- **Data to stdout, logs to stderr.** Always. Someone will pipe you.
- **jsonl for structured output** — one JSON object per line, so
  results chain into `jq`, `saveData`, `json2csv`, `json2xlsx`.
- Narrate side-effecting steps with **`learnExec`** — users see
  `[LEARN] aws s3 ...` (secrets redacted) and learn the tool through
  the wrapper.
- Exit codes: 0 ok, 1 runtime failure, 2 usage error, 126 found-but-
  unusable, 127 missing tool.

## Test it

Add a `tests/test_<name>.sh` (copy an existing one — the harness gives
you isolated state and assert helpers). Wrap external tools with a shim
script on PATH so the test proves *your* plumbing, not AWS's uptime.
Run `tiss self test` before pushing; CI runs it on ubuntu + macos.
