# tiss

[![ci](https://github.com/mattyo161/tiss/actions/workflows/ci.yml/badge.svg)](https://github.com/mattyo161/tiss/actions/workflows/ci.yml)

**The Intuitive Scripting System** — one CLI, a tree of scripts, a shared
command language for humans *and* AI agents.

```
tiss git clone <repo>     # runs scripts/git/clone.sh if present...
tiss git push             # ...otherwise passes through to plain `git`
tiss rg TODO              # missing tool? tiss installs it, then runs it
tiss --manifest           # every command, self-described, as jsonl
```

The directory tree *is* the command language: `scripts/git/clone.sh` becomes
`tiss git clone`. Adding a command is creating a file — bash, python,
anything executable. Help, tab completion, and the AI-facing manifest all
derive live from the tree and each script's `# @` annotations.

## What's in the box

| | |
| --- | --- |
| `encrypt` / `decrypt` / `lock` | age-backed encryption; encrypt never prompts (public key only), decrypt unlocks once per session |
| `saveData` / `readData` | named pipe-friendly data store; gzip by default, `--encrypt` optional, atomic writes, extensions self-describe (`name.gz.age`) |
| `learnExec` | run a command while teaching what ran: `[LEARN]` line (secrets redacted) + history log |
| `cacheExec` | content-addressed command cache keyed on argv + env context (`AWS_PROFILE` etc.); `--duration 1h`, never caches failures |
| `rmAfter` | self-destructing files: `rmAfter 15s creds.ini` — background monitor, deletion allowlist |
| `bkup` | instant backups into sibling `.bkup/` dirs, named by mtime, idempotent |
| `csv2json` `tsv2json` `json2csv` `json2tsv` `json2md` | format conversions as miller façades, jsonl-first |
| `json2xlsx` | formatted spreadsheets from json/jsonl (python leaf via uv) |
| `dt parse` | fuzzy date parsing: `tiss dt parse Mon 12/24/28` → 1928, because that's the Monday |
| `tiss doctor` | checks your setup and tells you exactly what to fix |

Plus the sourced helper suite every script gets: `logInfo`/`pipeInfo`/`teeInfo`,
`ts`/`utc`/`dur2s`, and friends. Durations are `1w2d3h4m5s` everywhere
(bare number = minutes); `--no-<flag>` negates any defaulted flag.

## Why

Over years at a previous job I built a universal script CLI that wrapped
terraform, git, aws, databases and more with business context, good
defaults, and hard-won best practices. It made new teammates productive in
days and made complex operations teachable — `learnExec` showed you every
command a script ran. This is that idea rebuilt in the open — and rebuilt
for the age of AI agents, which thrive on exactly the same things humans
do: consistent conventions, discoverable commands, and machine-readable
self-description.

The name honors its ancestor, TIPS (The Intuitive Pagination System), from
my newspaper days. *Intuitive* is the point: the tool should always guide
you to the next step.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/mattyo161/tiss/main/install.sh | bash
```

(or clone + symlink `bin/tiss` yourself — the installer just automates
that plus `tiss self doctor`.)

Tab completion (candidates come live from the tree — new scripts complete
immediately):

```sh
eval "$(tiss self completion zsh)"    # ~/.zshrc, after compinit
eval "$(tiss self completion bash)"   # ~/.bashrc
```

Call it whatever you like — the CLI follows the name of its symlink/alias:

```sh
ln -s "$PWD/tiss/bin/tiss" /usr/local/bin/x
x tiss doctor       # help, completions, everything says `x`
```

Requirements: bash and `jq`. Wrapped tools (age, mlr, rg, ...) install
lazily on first use via [mise](https://mise.jdx.dev) (brew fallback), with
a prompt — set `TISS_AUTO_INSTALL=always|never` to decide once.

## For AI agents

`tiss --manifest` emits one JSON object per command: name, description,
usage, examples, declared tool deps, source path. Conventions are uniform
by design — `# @` annotations, jsonl streams, one duration grammar, one
timestamp form — so an agent that learns one command has learned them all.

## Development

```sh
tiss self test      # dependency-free suite, 174 assertions and counting
```

CI runs shellcheck plus the suite on ubuntu and macos. Design decisions,
conventions, and the roadmap live in [DESIGN.md](DESIGN.md); how to add
commands and the house rules live in [CONTRIBUTING.md](CONTRIBUTING.md).

Company-private script trees layer over the core without forking:
`tiss self tree add ~/work/acme-tiss` (see DESIGN.md "Overlay trees").

## License

[MIT](LICENSE)
