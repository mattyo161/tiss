#!/usr/bin/env bash
# @description Guided tmux: pick a session, create, or clean up — no args to remember
# @usage tiss tmux go
# @example tiss tmux go
# @needs tmux
#
# Interactive menu over your sessions. Every action runs through
# learnExec, so the real tmux command is shown each time — the menu
# teaches you the args you never remember.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

if ! { : </dev/tty >/dev/tty; } 2>/dev/null; then
  logError "interactive terminal required (scriptable pieces: $TISS_NAME tmux ls|new|attach|kill)"
  exit 2
fi

while :; do
  sessions=()
  while IFS= read -r s; do
    [ -n "$s" ] && sessions+=("$s")
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)

  {
    echo
    if [ ${#sessions[@]} -eq 0 ]; then
      echo "no tmux sessions yet."
    else
      echo "tmux sessions:"
      i=1
      for s in "${sessions[@]}"; do
        info="$(tmux list-sessions -F '#{session_name}: #{session_windows} windows#{?session_attached, (attached),}' 2>/dev/null | grep "^$s:")"
        printf '  %d) %s\n' "$i" "$info"
        i=$((i + 1))
      done
    fi
    echo "  n) new session    d) delete a session    q) quit"
    printf 'pick: '
  } >/dev/tty

  IFS= read -r choice </dev/tty || exit 0
  case "$choice" in
    q | "") exit 0 ;;
    n)
      printf 'session name (empty = auto): ' >/dev/tty
      IFS= read -r name </dev/tty
      name="${name:-tiss-$(ts)}"
      learnExec tmux new-session -d -s "$name"
      if [ -n "${TMUX:-}" ]; then
        learnExec tmux switch-client -t "$name"
      else
        learnExec tmux attach-session -t "$name"
      fi
      exit 0
      ;;
    d)
      printf 'delete which number? ' >/dev/tty
      IFS= read -r num </dev/tty
      case "$num" in *[!0-9]* | "") logWarn "not a number" ;; *)
        if [ "$num" -ge 1 ] && [ "$num" -le ${#sessions[@]} ]; then
          learnExec tmux kill-session -t "${sessions[$((num - 1))]}"
        else
          logWarn "no session #$num"
        fi
        ;;
      esac
      ;; # loop back to the menu
    *[!0-9]*)
      logWarn "unrecognized choice '$choice'"
      ;;
    *)
      if [ "$choice" -ge 1 ] && [ "$choice" -le ${#sessions[@]} ]; then
        target="${sessions[$((choice - 1))]}"
        if [ -n "${TMUX:-}" ]; then
          learnExec tmux switch-client -t "$target"
        else
          learnExec tmux attach-session -t "$target"
        fi
        exit 0
      fi
      logWarn "no session #$choice"
      ;;
  esac
done
