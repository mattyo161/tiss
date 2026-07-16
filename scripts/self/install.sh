#!/usr/bin/env bash
# @description Install tools by name — mise first, brew fallback, custom installers
# @usage tiss install TOOL[@VERSION] [TOOL...]
# @example tiss install duckdb
# @example tiss install python@3.13 jq rg
#
# The explicit front door to what passthrough does lazily. Typing
# `install` IS the consent, so there is no extra prompt and no
# allowlist gate (the gate exists to stop typos becoming install
# prompts — an explicit install is unambiguous). TOOL@VERSION pins via
# mise (`mise use -g`). The classic file-copying install(1) stays
# reachable behind the escape: tiss -- install
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help | "")
    tissHelp "$0"
    exit 0
    ;;
esac

rc=0
for spec in "$@"; do
  case "$spec" in
    *@?*)
      # Versioned: pin globally via mise (bootstrapping mise if needed).
      TISS_AUTO_INSTALL=always ensureTool mise || {
        rc=127
        continue
      }
      if mise use -g "$spec" >/dev/null 2>&1; then
        logInfo "installed (pinned): $spec"
      else
        logError "mise could not install '$spec'"
        rc=127
      fi
      ;;
    *)
      if command -v "$spec" >/dev/null 2>&1; then
        logInfo "already installed: $spec ($(command -v "$spec"))"
        continue
      fi
      TISS_AUTO_INSTALL=always ensureTool "$spec" || rc=127
      ;;
  esac
done
exit "$rc"
