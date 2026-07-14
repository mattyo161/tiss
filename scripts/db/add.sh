#!/usr/bin/env bash
# @description Register a database connection (credentials encrypted at rest)
# @usage tiss db add <name> [--plain] [--stdin]
# @example tiss db add staging
#
# Prompts for host/port/user/password and stores them in mysql
# defaults-file format via saveData --encrypt --no-gzip — so the password
# never sits on disk in plaintext, and `db connect`/`db query` feed it to
# mysql through a process substitution, never a real file.
#
# --stdin reads a ready-made [client] ini from stdin instead of prompting
# (scripted setup). --plain skips encryption — loudly discouraged, exists
# for environments without an age identity.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

name=""
plain=0
from_stdin=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    --plain) plain=1 ;;
    --stdin) from_stdin=1 ;;
    -*)
      logError "unknown argument: $1"
      exit 2
      ;;
    *) name="$1" ;;
  esac
  shift
done
[ -n "$name" ] || {
  logError "usage: $TISS_NAME db add <name>"
  exit 2
}

if [ "$from_stdin" = 1 ]; then
  ini="$(cat)"
else
  { : </dev/tty; } 2>/dev/null || {
    logError "interactive terminal required (or use --stdin)"
    exit 2
  }
  printf 'host: ' >/dev/tty && IFS= read -r host </dev/tty
  printf 'port [3306]: ' >/dev/tty && IFS= read -r port </dev/tty
  printf 'user: ' >/dev/tty && IFS= read -r user </dev/tty
  printf 'password: ' >/dev/tty && IFS= read -rs pass </dev/tty && echo >/dev/tty
  printf 'database (optional): ' >/dev/tty && IFS= read -r dbname </dev/tty
  ini="[client]
host=$host
port=${port:-3306}
user=$user
password=$pass"
  [ -n "$dbname" ] && ini="$ini
database=$dbname"
fi

if [ "$plain" = 1 ]; then
  logWarn "storing '$name' UNENCRYPTED (--plain) — anyone with file access can read the password"
  printf '%s\n' "$ini" | saveData --no-gzip "db/$name"
else
  printf '%s\n' "$ini" | saveData --encrypt --no-gzip "db/$name"
fi
logInfo "saved connection 'db/$name'. try: $TISS_NAME db connect $name"
