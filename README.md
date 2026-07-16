# devops — a tiss tree

The production-grade terraform toolkit, as an installable tree:

    tiss +devops                 # install + enable (branch tree/devops)
    tiss tf plan                 # fmt + self-correcting init, icon summary, offer to apply
    tiss tf apply                # apply the latest SAVED plan (never re-plans)
    tiss tf report --format md   # report from saved artifacts, terraform not needed

Settings (this tree's `etc/config.sh`, override in your config or env):
`TISS_TF_AUTO_APPLY` (ask|always|never), `TISS_TF_MODULE_GREP` (root-module
marker for `--all` sweeps), `TISS_TF_PLAN_TTL` (plan-file self-destruct).

Without this tree, `tiss tf ...` passes through to plain `terraform`.
Suggested shortcuts in `etc/shortcuts` (tfplan, tfapply, ...). Tests run
via `tiss test` when the tree is enabled. Version pins: `tiss +devops@vX`.
