# Dotfiles Repository - Agent Guidelines

## Project Overview

This is a multi-profile dotfiles repository using Nix Home Manager for declarative system configuration. It supports multiple user profiles across macOS and Linux platforms with automatic profile discovery.

## Architecture

### Core Technologies
- **Nix Flakes**: Declarative package and configuration management
- **Home Manager**: User environment management
- **Task**: Task runner for automation (taskfile.dev)
- **Neovim**: Primary code editor with LSP integration

### Directory Structure
- `flake.nix`: Main Nix flake with automatic profile discovery
- `lib/`: Shared Nix libraries and utilities
- `profiles/`: User-specific configurations (auto-discovered)
- `shared/`: Shared configurations across all profiles
  - `programs/`: Program configurations (bash, neovim, git, etc.)
  - `activations/`: Activation scripts for setup tasks
- `tasks/`: Task runner configuration files
- `scripts/`: Utility shell scripts

## Coding Patterns

### Nix Configuration
- Use absolute paths for file references
- Profile-specific overrides in `profiles/<name>/`
- Shared base configuration in `shared/programs/`
- Package management centralized in `shared/programs/bare.nix`
- Unfree packages managed via `shared/programs/unfree.nix`

### Profile System
- Profiles auto-discovered from `profiles/*.nix`
- Each profile defines platform, home directory, and user-specific packages
- Profile extensions use library functions from `lib/` directory
- Pattern: `((import ../lib/<extension>.nix { inherit lib; }).forProfile "<name>")`

### File Organization
- Base configurations: `shared/programs/<tool>.nix`
- Profile overrides: `profiles/<profile>/<tool>/`
- Extension libraries: `lib/<tool>-extension.nix`

## Tools and MCP Servers

### Available MCP Tools
When working with Gitea repositories, use the `gitea` MCP tools for repository operations, issue management, and Git operations.

**Gitea User Attribution:**
- Claude Code operations are attributed to `claude-bot` user (uses `GITEA_CLAUDE_BOT_TOKEN`)
- OpenCode operations are attributed to `ai-bot` user (uses `GITEA_AI_BOT_TOKEN`)
- Both require `GITEA_HOST` environment variable

### Development Tools
- **AI Coding**: OpenCode (primary), Claude Code
- **Language Servers**: TypeScript, ESLint, Prettier, nixd
- **Version Control**: Git with proton-pass credential helper
- **Shell**: Bash with extensive customization
- **Editor**: Neovim with CoC.nvim and nightly builds

## Common Tasks

### Adding Packages
1. Global packages: Add to `shared/programs/bare.nix`
2. Profile-specific packages: Add to `profiles/<profile>.nix` under `home.packages`
3. Unfree packages: Add to allowlist in `shared/programs/unfree.nix`

### Creating a New Profile
1. Create `profiles/<name>.nix` with profile configuration
2. Create `profiles/<name>/` directory for overrides if needed
3. Profile will be auto-discovered by the flake system
4. No manual flake.nix editing required

### Running Tasks
- List tasks: `task`
- Install dependencies: `task install`
- Setup Nix: `task setup:nix`
- Clean Nix store: `task nix:clean`

## Git Workflow

Commit message rules are not repository-specific and live in
`shared/programs/agent/conventions.md`, which every agent loads as user-level
instructions from `~/.agent/conventions.md`.

## Best Practices

### Code Style
- Keep configurations modular and reusable
- Use meaningful variable and file names
- Document complex Nix expressions with comments
- Maintain platform compatibility (macOS/Linux)

### Testing Changes

Exercise a change with `task nix:sandbox`, which activates the checkout against
a throwaway home directory instead of the real one. README's *Sandbox
activation* covers running it and what it leaves alone; this section is about
deciding whether a change you are making escapes it. Prefer the sandbox over
switching the real profile: a broken change costs a `task nix:sandbox:clean`
rather than a rollback.

The sandbox works by moving `$HOME` and nothing else. So the question to ask of
any module being added or changed is: **does it reach something that moving
`$HOME` does not move?** Four kinds do.

#### 1. Hands work to a service manager

launchd agents and systemd user units are addressed by unit name against the
live session, so a sandbox activation would take over the real ones.
`sandboxModule` in `flake.nix` switches both subsystems off wholesale. Keep it
that way: clearing a category is what stops it becoming a registry with an
entry per module.

Do not trust the option that reads like the off switch. `launchd.enable = false`
looks like it disables agents and does not: it only feeds an assertion, while
the activation that runs `launchctl bootstrap` against `gui/$UID` is wired to
`launchd.agents`. `systemd.user.enable` does gate both its units and its reload
step.

#### 2. Absolute paths not derived from `config.home.homeDirectory`

`/etc/profiles/per-user/<user>/bin/...`, `/run/current-system/...`,
`/Library/...`. These keep pointing at what is already deployed, so the sandbox
silently exercises the old copy.

This is a limit to know rather than a bug to fix. `shared/programs/mtg-minutes.nix`
names `voice-in` through the nix-darwin per-user profile deliberately, because a
store path baked into `karabiner.json` dangles after the next switch. A change to
a script reached that way cannot be verified in the sandbox at all: switch for
real, or drive the script directly.

Referencing repository scripts as
`${config.home.homeDirectory}/dotfiles/scripts/...` is the opposite case, and
the reason to prefer it: the sandbox rewrites that path onto the checkout under
test, so edits take effect there with no rebuild.

#### 3. Writes outside `$HOME` from an activation script

`shared/activations/gapplin.nix` installs through `mas`,
`shared/activations/proton-pass.nix` pipes a vendor installer into bash. No
option clears these as a category, so if one starts doing something a sandbox
must not repeat, force that block empty with
`home.activation.<name> = lib.mkForce ""`.

#### 4. Binds a unix socket under `$HOME`

The sandbox home path plus the socket's own path has to fit `sun_path`, which is
why `nix:sandbox` relocates a deep `SANDBOX_HOME` under `/tmp` rather than
binding beneath it (README: *Path length*). Adding another socket-binding
program eats into that budget, and the ceiling in `tasks/nix.yml` has to move
with it.

#### Confirming a neutralization took

Build the sandbox activation package and read what survived, rather than
trusting that setting the option was enough:

```bash
DOTFILES_SANDBOX_HOME=/tmp/sbx nix build --impure \
  ".#sandboxConfigurations.<profile>.activationPackage" -o /tmp/sbx-result

grep -n 'checkPathEq HOME' /tmp/sbx-result/activate   # must name the sandbox
ls -A /tmp/sbx-result/LaunchAgents                    # must be empty
grep -n '<token the module introduces>' /tmp/sbx-result/activate
```

Grep for the specific thing the module adds -- the plist `Label`, the `defaults`
domain, the socket path. A generic sweep for absolute paths is not worth
running: `activate` legitimately names `/bin/launchctl`, `/usr/bin/security`,
`/opt/homebrew/bin` and more, and matches inside `"$HOME/Library/..."` come back
looking like escapes, so the noise buries the signal.

`setupLaunchAgents` keeps its `launchctl bootstrap` call in the generated script
even when the agent set is empty; it iterates the `LaunchAgents` directory, so
nothing runs. Emptiness of that directory is the check, not absence of the word
`launchctl`.

The `launchd.enable` trap above was found exactly this way: the option was set,
and the plists were still sitting in `LaunchAgents`.

### File Management
- NEVER edit generated files in `~/.config/`
- Always edit source files in this repository
- Use symlinks via Home Manager for configuration files
- Keep sensitive data out of the repository (use environment variables)

## Dependencies

### Required Tools
- Nix package manager
- Task runner (taskfile.dev)
- Git
- Home Manager

### Key Packages
- **Base**: gnused, tree, curl, ripgrep, age, passage, direnv, pipx, poetry
- **AI**: opencode, claude-code, hermes-agent, ollama
- **Development**: nodejs, sqlite, duckdb, openssh
- **Fonts**: daddy-time-mono, shure-tech-mono (Nerd Fonts)

## Platform-Specific Notes

### macOS (aarch64-darwin)
- Uses Homebrew for some dependencies
- Apple Silicon native packages
- Profile example: r-shibuya

### Linux (x86_64-linux, aarch64-linux)
- Uses apt/pacman for system dependencies
- Profile examples: lepetitprince, rose, aviateur, droid

## Troubleshooting

### pasta vs slirp4netns rootless Docker published ports

pasta is documented upstream as only relaying published-port traffic that
arrives via the host's real loopback (bridged in via `--host-lo-to-ns-lo`);
traffic arriving on any other host interface is believed to complete the
TCP handshake but never get its data relayed. This is a real upstream
caveat, but a leftover docker network with an overly broad subnet can
produce the exact same symptom (LAN clients failing to reach a published
port) under both pasta and slirp4netns alike, since it's a routing
collision, not a driver limitation.

**Before suspecting pasta itself:** check `docker network ls` for a
stopped/leftover network with a suspiciously broad subnet, and `ip route
get <dest>` from inside the rootless sandbox netns to see what's actually
being selected.

**When testing published-port reachability:** a host curling its own LAN
IP doesn't exercise this at all -- the kernel routes that internally as
loopback regardless of driver. Test from a genuinely separate network
namespace (another container on its own bridge, another physical host).

### Common Issues
- Build failures: Check flake.lock is up to date
- Profile not found: Verify profile file exists in `profiles/`
- Permission errors: Ensure proper file permissions on scripts
- Unfree package errors: Add package to unfree allowlist

### Debug Commands
```bash
# Check Nix flake
nix flake check

# Show flake outputs
nix flake show

# List available profiles
nix flake show | grep homeConfigurations
```
