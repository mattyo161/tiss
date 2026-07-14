# Getting started

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/mattyo161/tiss/main/install.sh | bash
tiss self doctor      # tells you what, if anything, to fix
```

Tab completion (live from the tree — new commands complete instantly):

```sh
eval "$(tiss self completion zsh)"    # ~/.zshrc, after compinit
```

Prefer a different name? `bash -s -- x` at install time (or symlink
`bin/tiss` yourself as anything) — help, completions, and every message
follow the name you chose.

## Ten minutes of highlights

```sh
tiss                             # the command tree, with descriptions
tiss help git                    # what the git namespace offers

# passthrough: any tool, args untouched, installed on first use
tiss rg TODO
tiss pstree -p $$

# the data store: gzip by default, atomic, self-describing names
docker ps --format json | tiss saveData docker/ps
tiss readData docker/ps | jq .Names
tiss lsData                      # what's saved, as jsonl

# encryption: set up once, then it's just a pipe
echo "s3cret" | tiss encrypt > note.age        # never prompts
tiss decrypt < note.age                        # passphrase once/session

# self-destructing files
tiss rmAfter 5m /tmp/scratch.txt

# the exec wrappers
tiss learnExec aws s3 ls         # see exactly what runs, secrets redacted
tiss cacheExec --duration 1h aws ec2 describe-instances   # instant repeats

# conversions + dates
tiss csv2json data.csv | tiss json2xlsx report.xlsx
tiss dt parse Mon 12/24/28       # → 1928 (that's the Monday)
```

## Your first command

```sh
mkdir -p ~/my-tiss/scripts
cat > ~/my-tiss/scripts/hello.sh <<'EOF'
#!/usr/bin/env bash
# @description My first tiss command
# @usage tiss hello [name]
# @example tiss hello world
set -euo pipefail
source "$TISS_LIB/init.sh"
case "${1:-}" in -h | --help | help) tissHelp "$0"; exit 0 ;; esac
logInfo "about to greet"
echo "hello, ${1:-there}"
EOF
chmod +x ~/my-tiss/scripts/hello.sh     # ← REQUIRED: routing only sees executables
tiss self tree add ~/my-tiss

tiss hello world                         # runs
tiss hello help                          # self-documents
tiss --manifest | jq 'select(.command=="hello")'   # visible to AI agents
```

Two rules that trip everyone once:

1. **`chmod +x`** — a non-executable script is invisible (tiss will
   point this out rather than fail silently, but save yourself the trip).
2. **File or directory, not both** — `scripts/foo.sh` shadows the whole
   `scripts/foo/` namespace.

## Where to next

- [How routing works](how-routing-works.md) — the full decision logic
  and the troubleshooting checklist
- [Writing commands](writing-commands.md) — annotations, the arg-parsing
  pattern, output discipline
- [Cookbook: wrapping tools](cookbook-wrappers.md) — build
  `tiss ssm get` and learn every wrapper pattern
- [DESIGN.md](../DESIGN.md) — the principles and the decision log
