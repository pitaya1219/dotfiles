# dotfiles

⚙️ Dotfiles collection including shell configs, editor settings, and development tools setup.

## Getting started

### 1. Install task command

Task is a task runner/build tool that aims to be simpler and easier to use than GNU Make.  
We use it to manage the dotfiles setup process before transitioning to Nix.
  

```bash
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
```

### 2. Run install task 

```bash
task install
```

### 3. Run setup task to begin using nix

```bash
task setup:nix
```

## Sandbox activation

`task nix:sandbox` activates the current checkout against a throwaway home
directory instead of the real one, so a change can be exercised end to end
before it is deployed.

```bash
task nix:sandbox                                    # /tmp/dotfiles-sandbox
task nix:sandbox SANDBOX_HOME=$PWD/sandbox PROFILE=rose
task nix:sandbox:shell                              # re-enter without re-activating
task nix:sandbox:clean
```

It builds `sandboxConfigurations.<profile>` -- the profile's own module list
with `home.homeDirectory` pointed at the sandbox -- runs the real activation
script with `HOME` set to match, and drops you into a login shell there;
leaving the shell returns you where you were, and `nix:sandbox:shell` opens
another one later without redoing the activation. `$HOME/dotfiles` inside the
sandbox is a symlink back to the checkout, so the scripts that configurations
reference through that path are the ones being edited rather than the deployed
copies.

### Which paths follow the sandbox

| How the path is written | In the sandbox |
| --- | --- |
| `${pkgs.foo}/bin/foo` | the same store path as production |
| `${config.home.homeDirectory}/...` | rewritten to the sandbox home |
| `~/...` or `$HOME/...` resolved at runtime | rewritten to the sandbox home |
| `/etc/profiles/per-user/<user>/bin/...` | **not** rewritten |

The last row is the one to watch. Naming a binary through the nix-darwin
per-user profile keeps it pointing at whatever is already installed, so a
sandbox run exercises the deployed copy of a script and not the new one.

### What it leaves alone

- Service manager registrations. launchd agents and systemd user units are
  addressed by unit name against the live session, which no `HOME` override
  redirects, so both subsystems are switched off for a sandbox.
- The nix-darwin system layer (`/etc`, `/Library/LaunchDaemons`,
  `/run/current-system`) is out of scope. Reach for
  `nix build .#darwinConfigurations.<profile>.system` and
  `nix store diff-closures` there instead.
- Files that home-manager does not manage are simply absent. `~/.gitconfig`
  carries the git identity by hand, for one, so git inside the sandbox has none.
- The inherited environment, beyond the variables that would aim the sandbox at
  live state. `PATH` still carries real-home entries, so a `command -v` probe
  inside an activation script can find the deployed install and report a step as
  already done.

### herdr

herdr runs inside the sandbox and reaches a server of its own: it derives its
socket from `$HOME`, and `nix:sandbox` clears `HERDR_SOCKET_PATH` so an inherited
value cannot point it back at the live one. `herdr status server` inside the
sandbox reports the sandbox socket while the real server keeps running, and the
two `session list` outputs share nothing.

Prefer the default session for this. `herdr --session <name>` moves the socket
down to `.config/herdr/sessions/<name>/herdr.sock`, spending another
`/sessions/<name>` worth of the budget below.

### Path length

Unix socket paths cap at 104 bytes on macOS and several configurations bind
sockets under `$HOME/.config`, herdr alone spending 25 of them on
`.config/herdr/herdr.sock`. A `SANDBOX_HOME` deep enough to exhaust that budget
would fail during activation with a `sun_path` error naming neither the sandbox
nor the length, so the task does not let it get that far: past its ceiling, the
sandbox is created as `/tmp/sbx-<checksum of the requested path>` and
`SANDBOX_HOME` becomes a symlink to it.

That is what makes an agent session directory a usable `SANDBOX_HOME` despite
being 76 characters deep on its own:

```console
$ task nix:sandbox SANDBOX_HOME=$PWD/sandbox
/Users/r-shibuya/agent-sessions/session-<id>/sandbox is too deep to hold a unix socket.
The sandbox lives at /tmp/sbx-1787187797 and is linked from there.
```

The checksum is of the requested path, so the same caller reaches the same
directory on every run and two callers never collide. `nix:sandbox:shell` and
`nix:sandbox:clean` resolve it the same way -- pass them the `SANDBOX_HOME` you
asked for, not the `/tmp` path -- and `clean` removes the symlink along with the
sandbox.

## Environment Variables

### Gitea MCP Configuration

The Gitea MCP server requires the following environment variables:

```bash
# Gitea host URL
export GITEA_HOST="https://git.example.com"

# Claude Code uses claude-bot user
export GITEA_CLAUDE_BOT_TOKEN="your-claude-bot-token"

# OpenCode uses ai-bot user
export GITEA_AI_BOT_TOKEN="your-ai-bot-token"
```

**Note**: Each AI tool uses a different Gitea user token for proper attribution of automated changes.
