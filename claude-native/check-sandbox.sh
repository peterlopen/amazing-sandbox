#!/bin/sh
# Checks the sandbox from inside Claude:  ! sh ~/.local/bin/claude-sb-check
# Write checks open files for appending without writing anything; test files are removed again.
# Optional: CHECK_SSH_HOST=<host> shows which agent socket ssh would use for that host.

W="${CLAUDE_SB_WORKSPACE:-$HOME/projects}"
fails=0

# w <allowed|denied> <label> <path>: expected write result
w() {
  if (: >>"$3") 2>/dev/null; then got=allowed; else got=denied; fi
  report "$1" "$got" "write $2"
}
# r <allowed|denied> <label> <path>: expected read result
r() {
  if head -c1 "$3" >/dev/null 2>&1; then got=allowed; else got=denied; fi
  report "$1" "$got" "read  $2"
}
report() {
  if [ "$1" = "$2" ]; then echo "ok    $3: $2"; else echo "FAIL  $3: $2 (expected $1)"; fails=$((fails + 1)); fi
}

if [ -z "${ASB_SANDBOX:-}" ]; then
  # Outside the sandbox the write checks would really create files
  echo "This shell is NOT sandboxed (ASB_SANDBOX is unset). Run it inside Claude:  ! sh ~/.local/bin/claude-sb-check" >&2
  exit 1
fi
echo "ASB_SANDBOX=$ASB_SANDBOX"

repo=
for g in "$W"/*/.git; do
  if [ -d "$g" ]; then repo=${g%/.git}; break; fi
done

w allowed "workspace file" "$W/.claude-sb-probe"; rm -f "$W/.claude-sb-probe"
if [ -n "$repo" ]; then
  w denied "<repo>/.git/hooks" "$repo/.git/hooks/.claude-sb-probe"; rm -f "$repo/.git/hooks/.claude-sb-probe" 2>/dev/null
  w denied "<repo>/.git/config" "$repo/.git/config"
  w denied "<repo>/.idea" "$repo/.idea/.claude-sb-probe"; rm -f "$repo/.idea/.claude-sb-probe" 2>/dev/null
  w allowed "<repo>/.git (other files)" "$repo/.git/.claude-sb-probe"; rm -f "$repo/.git/.claude-sb-probe"
fi
w denied "home folder" "$HOME/.claude-sb-probe"
w denied "~/.zshrc" "$HOME/.zshrc"
w denied "~/.local/bin" "$HOME/.local/bin/.claude-sb-probe"
w denied "~/.local/share/claude" "$HOME/.local/share/claude/.claude-sb-probe"
w denied "~/.config/git/config" "$HOME/.config/git/config"
w denied "~/.claude/settings.json" "$HOME/.claude/settings.json"
w allowed "~/.claude.json" "$HOME/.claude.json"
w denied "~/Library/LaunchAgents" "$HOME/Library/LaunchAgents/claude-sb-probe.plist"
for d in "$HOME"/Library/Keychains/*/; do
  [ -d "$d" ] && w denied "data-protection keychain" "${d}.claude-sb-probe"
done
[ -d "$HOME/.m2" ] && w denied "~/.m2/settings.xml" "$HOME/.m2/settings.xml"
[ -d "$HOME/.m2/repository" ] && { w allowed "~/.m2/repository" "$HOME/.m2/repository/.claude-sb-probe"; rm -f "$HOME/.m2/repository/.claude-sb-probe"; }
[ -d "$HOME/.kube/cache" ] && { w allowed "~/.kube/cache" "$HOME/.kube/cache/.claude-sb-probe"; rm -f "$HOME/.kube/cache/.claude-sb-probe"; }
[ -d "$HOME/Documents" ] && r denied "~/Documents" "$(ls -d "$HOME"/Documents/* 2>/dev/null | head -1)"
[ -f "$HOME/.zsh_history" ] && r denied "~/.zsh_history" "$HOME/.zsh_history"
[ -f "$HOME/.ssh/config" ] && r allowed "~/.ssh/config" "$HOME/.ssh/config"

echo "--- tools"
command -v java >/dev/null && java -version 2>&1 | head -1
command -v mvn >/dev/null && mvn -v 2>&1 | grep -E '^(Apache Maven|Java version)'
command -v docker >/dev/null && docker version --format 'docker server {{.Server.Version}}' 2>&1 | tail -1
[ -n "$repo" ] && git -C "$repo" status -sb 2>&1 | head -1
[ -n "${CHECK_SSH_HOST:-}" ] && ssh -G "$CHECK_SSH_HOST" 2>&1 | grep -i '^identityagent '
if command -v kubectl >/dev/null && { [ -n "${KUBECONFIG:-}" ] || [ -f "$HOME/.kube/config" ]; }; then
  /usr/bin/perl -e 'alarm 30; exec @ARGV' kubectl get --raw /version --request-timeout=15s 2>&1 | grep -E 'gitVersion|error|Error' | head -2
fi
ps -p $$ >/dev/null 2>&1 && echo "note  ps runs (expected: blocked, it is setuid)" || echo "ok    ps blocked (setuid; pgrep works)"
open -g -a Finder >/dev/null 2>&1 && echo "FAIL  open can launch apps" || echo "ok    open blocked"

echo "--- $fails unexpected result(s)"
