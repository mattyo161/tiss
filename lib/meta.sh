# shellcheck shell=bash
#
# tiss metadata helpers — read the `# @key value` annotations that every
# tiss script carries in its header (see DESIGN.md "Metadata"):
#
#   # @description One-line summary shown in help and --manifest
#   # @usage       tiss git clone <repo>
#   # @example     tiss git clone git@github.com:user/repo
#   # @needs       git
#
meta() { # meta <file> <key> -> first value (empty if none)
  # Both comment styles: `# @key` (sh/py/rb) and `// @key` (js/ts/go).
  sed -n -e "s|^# @$2[[:space:]]*||p" -e "s|^// @$2[[:space:]]*||p" "$1" | head -n 1
}

metaAll() { # metaAll <file> <key> -> all values, one per line
  sed -n -e "s|^# @$2[[:space:]]*||p" -e "s|^// @$2[[:space:]]*||p" "$1"
}

tissHelp() { # tissHelp <script> — render a script's annotations as --help text
  local f="$1" line
  echo "usage: $(meta "$f" usage)"
  echo
  meta "$f" description
  local examples
  examples="$(metaAll "$f" example)"
  if [ -n "$examples" ]; then
    echo
    echo "examples:"
    printf '%s\n' "$examples" | while IFS= read -r line; do
      printf '  %s\n' "$line"
    done
  fi
}
