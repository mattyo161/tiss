# devops — a tiss tree

Install: `tiss +devops` (from the distribution repo, branch `tree/devops`).
Layout: `scripts/` is the command language (`scripts/foo/bar.sh` = `tiss foo bar`);
optional `etc/config.sh` (defaults), `etc/shortcuts` (suggestions),
`lib/init.sh` (helpers), `tests/` (run by `tiss test` when enabled).
Version by tagging: `git tag 'tree/devops@v0.1.0'` — users pin with `tiss +devops@v0.1.0`.
