# Shortcuts — muscle-memory names

Some commands live in your fingers: `tfplan`, `saveData`, `ts`. A
shortcut makes any tiss command available under a bare name — a real
executable on your PATH, so it works everywhere a command works:
interactive shells, other scripts, `xargs`, `find -exec`, cron.

```sh
tiss self shortcuts add tfplan tf plan       # tfplan == tiss tf plan
tiss self shortcuts add saveData saveData    # saveData == tiss saveData
tiss self shortcuts add sd saveData          # or shorter still
tfplan -target module.vpc                    # muscle memory restored
```

One-time setup — the same rc line that enables `tiss self cd`:

```sh
eval "$(tiss self init)"     # in ~/.zshrc or ~/.bashrc
```

That puts the shim dir (`TISS_SHIMS`, default `~/.local/share/tiss/shims`)
first on your PATH.

## How it works — symlinks, not generated code

Every shortcut is a symlink in the shim dir pointing back at the tiss
dispatcher. The dispatcher already follows its invocation name
(argv[0]); when that name is a shortcut *and* it was invoked from the
shim dir, it prepends the mapped words and routes normally. Nothing is
generated, so there is nothing to go stale: overlay shadowing, `--help`
(`tfplan --help` is `tiss tf plan --help`), and lazy tool install all
keep working through a shortcut.

Everything else is ordinary routing, so a shortcut can point at a
script, a namespace, a helper's wrapper, or even a passthrough tool.
Flags and args pass straight through, and a leading environment prefix
still loads first: `tfplan @prod -target module.vpc`.

## Why this can never loop

The dispatcher strips the shim dir from PATH before running anything.
Child scripts and passthrough tools only ever see real commands:

- a shortcut named after a real tool (`ts`, `rg`) can't recurse — the
  passthrough exec finds the real binary, never the shim;
- scripts always compose against canonical names (`tiss tf plan`,
  sourced helpers like `saveData`), never your personal shortcuts.

Shortcuts are strictly a human-fingers layer; they never leak
downstream. And only shims multiplex — a symlink to tiss anywhere
*else* stays a plain alias (`ln -s .../bin/tiss /usr/local/bin/x`
behaves exactly as before, even if some tree defines a shortcut `x`).

## Where definitions live

`~/.config/tiss/shortcuts` (yours) and each overlay tree's
`etc/shortcuts`, one `name = command words` per line, `#` comments
allowed:

```
# mine
tfplan = tf plan
sd     = saveData
```

Your file wins, then trees most-specific first — the same precedence as
configuration, so a company tree can ship suggested shortcuts and you
can shadow any of them. `tiss self shortcuts` shows the merged view
with each entry's source and shim health; hand-edits are fine — run
`tiss self shortcuts sync` afterwards to reconcile the shim dir (it
only ever touches symlinks that point at a tiss dispatcher; foreign
files are left alone and reported).

## Collisions

Names you pick shadow real tools *in your interactive shell only* (the
shim dir is first on PATH; downstream it's stripped). `add` warns when
a name shadows something (`'ts' shadows /opt/homebrew/bin/ts`) — that's
usually what you wanted, but now it's a choice, not an accident.
`tiss self doctor` checks that every shortcut has a healthy shim and
that the shim dir is actually on your PATH.