# The pile — overlay trees and packages

Vocabulary first, because it carries the whole model: **leaves** (command
scripts) make **trees** (overlays); trees stack into the **pile**, and the
top wins. tiss routes every command through the pile — the first tree
that has it, wins — with the core always at the bottom. A **package** is
a tree distributed via git.

```sh
tiss +devops tf plan     # install if missing → enable → run. One gesture.
tiss -devops             # disable (the clone stays on disk)
tiss pile                # the stack, top first; disabled packages hinted
tiss pile resolve devops # exactly where would this name fetch from? (jsonl)
```

## The spec grammar

| You type | Repo | Ref checked out |
| --- | --- | --- |
| `+devops` | distribution repo (`TISS_TREES_REPO`, default: the repo *your tiss* was cloned from) | branch `tiss/devops` |
| `+devops@v0.5.6` | same | tag `tiss/devops@v0.5.6` |
| `+devops@stable` | same | tag `tiss/devops@stable` (a tag the maintainer moves) |
| `+devops@latest` | same | branch head — always fetches |
| `+acme/tiss-devops` | `github.com/acme/tiss-devops` | default branch (whole repo = the tree) |
| `+git@host:x.git@prod` | that URL | any ref: branch, tag, sha |

Bare `+name` with the clone already present touches **no network**; only
an explicit `@version` fetches. The version rule in one sentence:
`@<ver>` resolves to the ref `<tracked-branch>@<ver>`, falling back to
`<ver>` literally; `@latest` is the tracked branch's head.

## Where the mapping lives — in the clone, not a registry

There is no mapping file to drift out of sync. A package's identity is
its clone under `TISS_TREES` (`~/.local/share/tiss/trees/<name>`): git
`origin` remembers the repo, a `tiss.track` git-config entry remembers
the tracked branch. Enabled = present in the persisted `TISS_PATH` line.
Custom mappings just write those:

```sh
tiss pile add prod --repo git@github.com:acme/tiss_packages.git --branch env/prod
tiss +prod@v0.8.5        # → tag env/prod@v0.8.5 on acme's repo
tiss pile list --json    # every tree: kind, enabled, source, track, ref
```

Aliases stay slash-free (they're also the clone dir and what you type);
branches are free-form via `--branch`.

## Authoring a package

```sh
tiss pile new devops --push    # skeleton + branch tiss/devops, published
```

The scaffold is a tree shell: `scripts/` (the command language),
`etc/config.sh` (defaults via `cfg` — user config still wins),
`etc/shortcuts` (suggestions), optional `lib/init.sh` (helpers, loaded
automatically when the tree is enabled) and `tests/` (run by `tiss test`
alongside core's — source the core harness via `$TISS_HOME`, then put
your own tree on `TISS_PATH`). Version by tagging:
`git tag 'tiss/devops@v0.2.0'`.

## The acme stories

**A company devops tree.** Acme scaffolds, customizes, and pushes
`tiss/devops` to `acme/tiss_packages`. Engineers set one line — `cfg
TISS_TREES_REPO "git@github.com:acme/tiss_packages.git"` — and
`tiss +devops` means *acme's* devops from then on. One repo carries many
packages (`tiss/devops`, `tiss/data`, `tiss/oncall`).

**A full fork (supply-chain isolation).** Acme forks tiss, curates what
merges from upstream, and points installs at the fork. With zero extra
configuration, `tiss pull` updates from the fork and every short package
name resolves against the fork too — nothing on an engineer's machine
fetches from upstream unless someone explicitly names a foreign
`owner/repo`. The review gate for core *and* packages is exactly the
fork boundary. The reserved lexicon completes the contract: no tree,
however it arrived, can shadow `pull`, `doctor`, or any other word tiss
answers for itself.

## Trust, spelled out

- The lexicon resolves from core only, before the pile walk; `doctor`
  warns if any tree ships a reserved name.
- `pile resolve <spec>` answers "where does this fetch from?" before or
  after install — pipe `pile list --json` through `jq` for audits.
- `-name` never deletes; clones are yours to inspect at `TISS_TREES`.
