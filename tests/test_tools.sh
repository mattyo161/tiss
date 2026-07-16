#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031  # literal $ in emitted rc code; env changes deliberately subshell-scoped
# Tests for tool bootstrap: mise as a first-class citizen, in-process
# activation via mise shims, brew guidance, and the rc emission.
. "$(dirname "$0")/harness.sh"

export TISS_CONFIG="$TISS_TEST_TMP/config"
export XDG_DATA_HOME="$TISS_TEST_TMP/xdg"

# --- never-mode hints lead somewhere ------------------------------------------
rc=0
out="$(TISS_AUTO_INSTALL=never PATH=/usr/bin:/bin ensureTool mise 2>&1)" || rc=$?
assertEq "missing mise fails under never" 127 "$rc"
assertMatch "mise hint is the bootstrap one-liner" 'curl https://mise.run \| sh' "$out"

# --- fake mise: install lands behind shims, tiss activates them in-process ------
mkdir -p "$TISS_TEST_TMP/fakebin"
cat >"$TISS_TEST_TMP/fakebin/mise" <<'EOF'
#!/usr/bin/env bash
# fake mise: `use -g name@ver` drops an executable into the shims dir,
# like real mise does for a shell that hasn't activated it. Packages
# named offreg* simulate a registry miss.
if [ "$1" = "use" ] && [ "$2" = "-g" ]; then
  name="${3%%@*}"
  case "$name" in offreg*) exit 1 ;; esac
  shims="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
  mkdir -p "$shims"
  printf '#!/usr/bin/env bash\necho "%s-runs"\n' "$name" >"$shims/$name"
  chmod +x "$shims/$name"
fi
EOF
chmod +x "$TISS_TEST_TMP/fakebin/mise"

out="$(
  export PATH="$TISS_TEST_TMP/fakebin:/usr/bin:/bin"
  export TISS_AUTO_INSTALL=always
  ensureTool newtool >/dev/null 2>&1 || exit 1
  command -v newtool >/dev/null 2>&1 || exit 1
  newtool
)"
assertEq "mise-installed tool works in-process via shims" "newtool-runs" "$out"

# --- registry miss falls to brew; a failing brew reports both misses -------------
cat >"$TISS_TEST_TMP/fakebin/brew" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TISS_TEST_TMP/fakebin/brew"
rc=0
out="$(
  export PATH="$TISS_TEST_TMP/fakebin:/usr/bin:/bin"
  export TISS_AUTO_INSTALL=always
  ensureTool offregtool 2>&1
)" || rc=$?
assertEq "registry miss + brew failure exits 127" 127 "$rc"
assertMatch "failure names both installers" 'mise registry miss, brew failed' "$out"

# --- tiss install: the explicit front door -----------------------------------------
assertMatch "install with no args shows help" 'usage: tiss install' "$("$TISS_BIN" install 2>&1)"
assertMatch "already-installed tools short-circuit" 'already installed: jq' \
  "$(TISS_LOG_LEVEL=INFO "$TISS_BIN" install jq 2>&1)"
out="$(
  export PATH="$TISS_TEST_TMP/fakebin:/usr/bin:/bin"
  "$TISS_BIN" install freshtool >/dev/null 2>&1 || exit 1
  echo installed-ok
)"
assertEq "install works without a prompt (explicit consent)" "installed-ok" "$out"
assertFileExists "and the tool landed behind mise" "$XDG_DATA_HOME/mise/shims/freshtool"
assertMatch "the real install(1) survives behind --" 'usage: install' \
  "$("$TISS_BIN" -- install 2>&1 || true)"

# --- self init emits the activation story ----------------------------------------
emit="$("$TISS_BIN" self init 2>/dev/null)"
assertMatch "init puts ~/.local/bin on PATH" 'HOME/.local/bin' "$emit"
assertMatch "init activates mise for zsh" 'mise activate zsh' "$emit"
assertMatch "init activates mise for bash" 'mise activate bash' "$emit"
assertMatch "init respects an existing activation" 'MISE_SHELL' "$emit"
assertMatch "init probes the brew locations" '/home/linuxbrew/.linuxbrew/bin/brew' "$emit"
assertMatch "init activates found brew via shellenv" 'shellenv' "$emit"
assertExit "emission is valid bash" 0 bash -n /dev/stdin <<<"$emit"
assertExit "emission evals cleanly in bash" 0 bash -c "eval \"\$emit\"" bash
onpath="$(bash -c "eval \"\$1\"; case \":\$PATH:\" in *\":\$HOME/.local/bin:\"*) echo on ;; *) echo off ;; esac" bash "$emit")"
assertEq "eval'd emission adds ~/.local/bin" "on" "$onpath"

finish
