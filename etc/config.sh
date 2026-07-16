# shellcheck shell=bash
# devops tree defaults (cfg = only-if-unset, so user config wins).

## What happens after tf plan finds changes: ask (y/N prompt) | always
## (auto-apply) | never (plan/report only)
cfg TISS_TF_AUTO_APPLY ask

## What marks a directory as a root module for --all sweeps (grep pattern
## over *.tf files; the original rule was 'backend "s3"')
cfg TISS_TF_MODULE_GREP 'backend "'

## How long saved .tfplan files live before self-destructing (0 = keep
## forever). The .json/.log/run.json artifacts always stay, for reports.
cfg TISS_TF_PLAN_TTL 1d
