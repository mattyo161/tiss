# shellcheck shell=bash
#
# tiss logging helpers — bash has no real logging story, so this is it.
#
#   logError / logWarn / logInfo / logDebug   log a message to stderr
#   pipeError / pipeInfo / ...                log each stdin line
#   teeError / teeInfo / ...                  log each stdin line AND pass it through
#
# Levels are filtered by TISS_LOG_LEVEL (ERROR|WARN|INFO|DEBUG, default INFO).
# Output goes to stderr so it never pollutes a pipeline; colors only when
# stderr is a terminal.
#
_tissLevelNum() {
  case "$1" in
    ERROR) echo 0 ;;
    WARN) echo 1 ;;
    INFO) echo 2 ;;
    DEBUG) echo 3 ;;
    *) echo 2 ;;
  esac
}

_tissLog() { # _tissLog <LEVEL> <message...>
  local level="$1"
  shift
  [ "$(_tissLevelNum "$level")" -le "$(_tissLevelNum "${TISS_LOG_LEVEL:-INFO}")" ] || return 0
  local color="" reset=""
  if [ -t 2 ]; then
    reset=$'\033[0m'
    case "$level" in
      ERROR) color=$'\033[31m' ;;
      WARN) color=$'\033[33m' ;;
      INFO) color=$'\033[36m' ;;
      DEBUG) color=$'\033[2m' ;;
    esac
  fi
  printf '%s%s [%s]%s %s\n' "$color" "$(ts)" "$level" "$reset" "$*" >&2
}

logError() { _tissLog ERROR "$@"; }
logWarn() { _tissLog WARN "$@"; }
logInfo() { _tissLog INFO "$@"; }
logDebug() { _tissLog DEBUG "$@"; }

_tissPipe() { # _tissPipe <LEVEL> <passthrough:0|1>
  local line
  while IFS= read -r line; do
    _tissLog "$1" "$line"
    [ "$2" = 1 ] && printf '%s\n' "$line"
  done
  return 0
}

pipeError() { _tissPipe ERROR 0; }
pipeWarn() { _tissPipe WARN 0; }
pipeInfo() { _tissPipe INFO 0; }
pipeDebug() { _tissPipe DEBUG 0; }

teeError() { _tissPipe ERROR 1; }
teeWarn() { _tissPipe WARN 1; }
teeInfo() { _tissPipe INFO 1; }
teeDebug() { _tissPipe DEBUG 1; }
