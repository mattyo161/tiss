# How routing works

There is no mapping file and no master list. **The directory tree is the
registry.** When you type `tiss a b c`, the dispatcher walks real
directories and picks the first thing that matches. This page is the
complete decision logic — and the checklist for "why didn't my command
run?"

## The search space: trees

Commands are looked up across a stack of *trees*, most specific first:

```
1. overlay trees, in TISS_PATH order    (tiss self tree list)
2. the core                             ($TISS_HOME, always last)
```

A tree is any directory containing `scripts/`. Register one with
`tiss self tree add <dir>`; inspect the stack and shadowing with
`tiss self tree list`.

## The walk

For `tiss a b c`, each tree is tried in order. Within a tree, one token
is consumed per step:

1. **Script match** — an *executable* file `scripts/a` or `scripts/a.*`
   (any extension: `.sh`, `.py`, anything with a shebang). If found, it
   runs with the remaining args (`b c`). **First match wins — the walk
   stops.**
2. **Namespace descent** — a directory `scripts/a/`: descend, repeat
   with the next token.
3. **Namespace handler** — if the token matches nothing but some level
   of the walk had a `_self.*` file, the *deepest* one runs with all the
   remaining args. `scripts/ssm/_self.sh` makes `tiss ssm <anything>`
   yours, while `scripts/ssm/get.sh` still owns `tiss ssm get` exactly.
   (A `_self` at the tree root would catch every unmatched command —
   powerful; use deliberately.)
4. **Neither** — this tree is done; try the next tree.

If a script matched, its `# @needs` tools are installed first (never for
`--help`), then it's exec'd. If no tree matched anything:

5. **Namespace landing** — the tokens name a directory in some tree
   (`tiss git` with `scripts/git/` existing): show that namespace's
   merged help.
6. **Passthrough** — behave as if the command were called natively:
   `tiss git push` execs `git push`. Missing tools are lazy-installed
   (mise, then brew). Some names are aliased first (`tf` → `terraform`)
   for pure name mapping; anything needing logic belongs in a `_self`
   handler instead.

## Precedence rules worth knowing

- **Executable files only.** A script without `chmod +x` is invisible to
  routing. tiss detects this near-miss rather than failing silently: if
  no real binary exists either, you get an error with the exact
  `chmod +x` command (exit 126); if a binary exists, you get a warning
  and the passthrough proceeds.
- **A file beats a directory at the same level.** If both
  `scripts/ssm.sh` and `scripts/ssm/` exist, the file wins and the whole
  `ssm/` namespace is shadowed. Want both a default action *and*
  subcommands? Use a directory with a `_self.*` handler inside it —
  that's the supported shape.
- **Bare namespace = help, not the handler.** `tiss ssm` shows the
  namespace's commands (with the handler described in the footer);
  `tiss ssm anything` reaches the handler.
- **First tree wins.** An overlay's `git/clone.sh` shadows the core's.
  `tiss self tree list` shows shadow counts; `--manifest` tags every
  command with its source tree.
- **Flags never route.** The walk stops at the first `-something`; that
  arg and everything after belong to whatever matched so far.
- **One implementation per command.** `clone.sh` and `clone.py` in the
  same directory are a collision; the first glob match wins. Don't.

## "My script doesn't run" checklist

1. **Is it executable?** `chmod +x scripts/ssm/get.sh` — the #1 cause.
   (`tiss ssm get` will now tell you this itself.)
2. **Is it in a registered tree?** `tiss self tree list` — a script tree
   sitting outside `TISS_PATH` and the core is invisible.
3. **Is it shadowed?** A same-named file in a more specific tree, or a
   sibling file shadowing your directory (`ssm.sh` vs `ssm/`).
4. **Did a flag stop the walk early?** `tiss -v ssm get` never routes to
   `ssm/get.sh` — flags belong to what matched before them.
5. **Confirm what tiss sees:** `tiss --manifest | jq 'select(.command | startswith("ssm"))'`
   — if your command isn't in the manifest, routing can't find it either.

## Getting help, three ways

```
tiss ssm get --help     # classic
tiss ssm get help       # bare `help` as the first arg to any command
tiss help ssm get       # help as a prefix — also works for namespaces
```
