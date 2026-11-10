#!/bin/bash
# Builds asb from this checkout and installs the Claude Code sandbox setup:
#   ~/.local/bin/asb, ~/.local/bin/claude-sb, ~/.local/bin/claude-sb-check
# and adds `alias claude=claude-sb` to ~/.zshrc. Run it outside the sandbox, which
# can't write ~/.local/bin. Needs Go (brew install go).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.local/bin"

if [ -n "${ASB_SANDBOX:-}" ]; then
  echo "install.sh: run it outside the sandbox (in a shell where \$ASB_SANDBOX is unset)" >&2
  exit 1
fi
command -v go >/dev/null || { echo "install.sh: Go is missing (brew install go)" >&2; exit 1; }
[ -x "$bin/claude" ] || echo "install.sh: note: $bin/claude not found; install Claude Code with its native installer" >&2

mkdir -p "$bin"
(cd "$here/../src/asb" && go build -o "$bin/asb" ./cmd/asb)
install -m 755 "$here/claude-sb" "$bin/claude-sb"
install -m 755 "$here/check-sandbox.sh" "$bin/claude-sb-check"
echo "Installed $bin/asb, $bin/claude-sb and $bin/claude-sb-check"

line='alias claude="$HOME/.local/bin/claude-sb"'
if ! grep -qxF "$line" "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# Claude Code runs inside amazing-sandbox (asb native); `\\claude` runs it without.\n%s\n' "$line" >>"$HOME/.zshrc"
  echo "Added the claude alias to ~/.zshrc; it applies to shells started from now on (or run: exec zsh)"
fi
echo "Then check the sandbox from inside Claude with:  ! sh ~/.local/bin/claude-sb-check"
