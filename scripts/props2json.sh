#!/usr/bin/env bash
# @description Convert KEY=value props lines (env/.env style) to one JSON object
# @usage ... | tiss props2json
# @example tiss env | tiss props2json | jq -r .TISS_DATA
# @example grep -v '^#' .env | tiss props2json
# @needs jq
#
# Splits on the FIRST '=' only (values may contain '='). Lines that
# don't look like KEY=value (comments, blanks) are skipped silently.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

jq -Rcn 'reduce inputs as $line ({};
  if ($line | test("^[A-Za-z_][A-Za-z0-9_]*=")) then
    . + { ($line | sub("=.*$"; "")): ($line | sub("^[^=]*="; "")) }
  else . end)'
