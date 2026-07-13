#!/usr/bin/env bash
#
# tiss installer — safe to curl | bash, safe to re-run (updates in place):
#
#   curl -fsSL https://raw.githubusercontent.com/mattyo161/tiss/main/install.sh | bash
#
# Installs to $XDG_DATA_HOME/tiss/repo (default ~/.local/share/tiss/repo)
# and symlinks the dispatcher into ~/.local/bin. Pass a name to install
# under a different command name:
#
#   ... | bash -s -- x     # installs as `x`
#
set -euo pipefail

name="${1:-tiss}"
repo_url="https://github.com/mattyo161/tiss.git"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/tiss/repo"
bin_dir="$HOME/.local/bin"

say() { printf '\033[36m[tiss install]\033[0m %s\n' "$*" >&2; }

command -v git >/dev/null 2>&1 || {
  say "git is required — install it first."
  exit 1
}

if [ -d "$dest/.git" ]; then
  say "updating existing install in $dest"
  git -C "$dest" pull --ff-only
else
  say "cloning into $dest"
  mkdir -p "$(dirname "$dest")"
  git clone --depth 1 "$repo_url" "$dest"
fi

mkdir -p "$bin_dir"
ln -sf "$dest/bin/tiss" "$bin_dir/$name"
say "linked: $bin_dir/$name"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    say "NOTE: $bin_dir is not on your PATH — add this to your shell rc:"
    # shellcheck disable=SC2016  # shown literally on purpose
    say '  export PATH="$HOME/.local/bin:$PATH"'
    ;;
esac

say "checking your setup..."
"$bin_dir/$name" self doctor || true

say "done. next steps:"
say "  $name                          # explore the command tree"
say "  eval \"\$($name self completion zsh)\"   # tab completion (~/.zshrc, after compinit)"
