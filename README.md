# tiss

**The Intuitive Scripting System** — one CLI, a tree of scripts, a shared
command language for humans *and* AI agents.

```
tiss git clone <repo>     # runs scripts/git/clone.sh if present...
tiss git push             # ...otherwise passes through to plain `git`
tiss rg TODO              # missing tool? tiss installs it, then runs it
echo secret | tiss encrypt > s.age   # security built in from day one
tiss --manifest           # every command, self-described, as jsonl
```

The directory tree *is* the command language: `scripts/git/clone.sh` becomes
`tiss git clone`. Adding a command is creating a file. Everything else —
help, discovery, the AI-facing manifest — derives from the tree and each
script's `# @` annotations.

## Why

Over years at a previous job I built a universal script CLI that wrapped
terraform, git, aws, databases and more with business context, good
defaults, and hard-won best practices. It made new teammates productive in
days and made complex operations teachable (`learnExec` showed you every
command a script ran). This is that idea rebuilt in the open — and rebuilt
for the age of AI agents, which thrive on exactly the same things humans
do: consistent conventions, discoverable commands, and machine-readable
self-description.

The name honors its ancestor, TIPS (The Intuitive Pagination System), from
my newspaper days. *Intuitive* is the point: the tool should always guide
you to the next step.

## Install

```sh
git clone https://github.com/mattyo161/tiss.git
ln -s "$PWD/tiss/bin/tiss" /usr/local/bin/tiss
tiss tiss doctor    # checks your setup and tells you what (if anything) to fix
```

Call it whatever you like — the CLI follows the name of its symlink/alias:

```sh
ln -s "$PWD/tiss/bin/tiss" /usr/local/bin/x
x tiss doctor       # help output says `x`, not `tiss`
```

Requirements: bash, `jq` (auto-installed on first need via
[mise](https://mise.jdx.dev), as are all wrapped tools).

## Status

Early. The skeleton is real and working — dispatcher, metadata/manifest,
lazy tool install, encryption (`encrypt`/`decrypt`/`lock`), logging and
time helpers. The full design, roadmap and decision log live in
[DESIGN.md](DESIGN.md).

## License

[MIT](LICENSE)
