# Claude Code in asb native mode (macOS)

This fork runs [Claude Code](https://code.claude.com/docs/en/overview) inside asb's native
macOS sandbox (`sandbox-exec`), with the tools a JVM / Node / kubectl / Docker workflow needs.
It adds a few asb changes and a wrapper, `claude-sb`, that starts Claude with the right mounts.

## What the sandbox allows

- **Writable:** the workspace (`~/projects` by default, `CLAUDE_SB_WORKSPACE` to change it), `~/.m2/repository`,
  `~/.kube/cache`, `~/.docker/buildx`, `~/.claude` and `~/.claude.json`, the login keychain, temp dirs
  and the caches asb allows (`~/Library/Caches`, `~/.cache`, `~/.npm`, `~/.local`).
- **Never writable,** even inside those: `.git/hooks`, `.git/config` and `.idea` anywhere in the workspace;
  `~/.local/bin`; Claude's binaries; `~/.config`; `~/.claude/settings.json`; the data-protection keychain.
  These are the places where a change would run code outside the sandbox later: on your next
  git command, in your shell or editor, or in the next Claude session.
- **Read-only:** `~/.m2`, `~/.mavenrc`, `~/.kube`, `~/.gitconfig`, `~/.ssh/config`, `~/.ssh/known_hosts`,
  `~/.ssh/*.pub`, `~/.docker`, `~/.testcontainers.properties`, `~/Library`, `/usr`, `/sbin`.
  Other files in your home folder can't be read (Documents, Downloads, shell history, private keys).
- **Network:** fully open. That includes the web, ssh through an agent socket (for example 1Password),
  localhost services and the Docker socket.
- **Blocked by macOS sandbox rules:** opening apps or URLs (`open`), Apple Events to other apps,
  setuid programs (`sudo`, `ps`), and typing into the terminal (`TIOCSTI`).

## Changes to asb

All in native macOS mode:

- New flags `--deny-write <path>`, `--deny-write-regex <regex>` and `--deny-read <path>`. They are
  appended last, and `sandbox-exec` applies the last matching rule, so they win over every allow rule.
- `exec` stops parsing flags at the binary, so `asb exec claude -r` passes `-r` to Claude instead of
  taking it as asb's `--read-only`.
- Fixes needed for Claude Code:
  - Terminal control (raw mode, window size) works on any terminal. Before, it worked only on
    `/dev/ttys000`, so elsewhere Claude found no terminal and stopped with "Input must be provided…".
    `TIOCSTI` stays denied.
  - The terminal is passed to the program directly instead of through a pipe. Behind a pipe, Claude
    again found no terminal.
  - Output is passed through also when stdin is not a terminal (`echo … | claude -p` printed nothing).
  - Claude can save `~/.claude.json`: it writes through `~/.claude.json.lock` and `~/.claude.json.tmp.*`.
  - `/usr/libexec/java_home` (behind `/usr/bin/java`) works: it needs the `kern.grade_cputype` sysctl.

## Install on a Mac

Prerequisites: Claude Code from its native installer (`~/.local/bin/claude`), Homebrew, Go (`brew install go`).

```sh
git clone https://github.com/<you>/amazing-sandbox ~/src/amazing-sandbox
~/src/amazing-sandbox/claude-native/install.sh
```

`install.sh` builds asb and installs `~/.local/bin/asb`, `~/.local/bin/claude-sb` and
`~/.local/bin/claude-sb-check`, and adds `alias claude="$HOME/.local/bin/claude-sb"` to `~/.zshrc`.
Run it outside the sandbox, then open a new shell, start `claude` in the workspace and check the result:

```
! sh ~/.local/bin/claude-sb-check
```

Every line should start with `ok`. Set `KUBECONFIG` or `CHECK_SSH_HOST` first to include kubectl and ssh.

Recommended: in Docker Desktop, go to Settings → Resources → File sharing and replace `/Users` with
your workspace. Keep `/private`, `/tmp` and `/var/folders`. Otherwise anything that can reach the
Docker socket can bind-mount your home folder and write to it, which undoes the rules above.

## Using it

- `claude update` runs outside the sandbox, since the sandbox can't write Claude's install.
  Auto-update is off inside.
- `\claude` starts Claude without the sandbox.
- kubelogin can't open a browser from inside. When it needs a new login, run one kubectl command in a
  normal shell; the token it saves in the keychain then works inside too.
- Blocked by design:
  - git commands that write `.git/config`, such as setting an upstream, `submodule update --init` or
    `git clone` into the workspace;
  - edits to `.idea`;
  - settings changes that Claude would save to `settings.json`. Edit that file yourself.
- To see what the sandbox denied, run this in a normal shell (plain `log` is a zsh builtin):
  `/usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "deny("'`.
  To allow more, add `--mount-ro` or `--mount-rw` lines to `claude-sb` and run `install.sh` again.

## What stays open

- Anything the sandbox can read could be sent out over the open network.
- Some writes are used outside the sandbox later: jars in `~/.m2/repository`, tracked files in your
  repositories, and tool caches (for example Playwright or Puppeteer browsers and the npx cache).
- Containers can still write to the folders Docker Desktop shares.
- `~/.claude` (memory, plugins and their hooks) is writable. That matters only when you start Claude
  without the sandbox.
