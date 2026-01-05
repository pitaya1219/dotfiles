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

### Commit Message Format
Use Conventional Commits format:
- Prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`, `style:`
- Format: `prefix: Description ending with period.`
- Example: `feat: Add rootless Docker configuration.`
- NEVER include AI tool names (Claude, OpenCode, etc.) in commit messages

## Best Practices

### Code Style
- Keep configurations modular and reusable
- Use meaningful variable and file names
- Document complex Nix expressions with comments
- Maintain platform compatibility (macOS/Linux)

### Testing Changes
1. Test changes locally with `nix run home-manager/master -- switch --flake .#<profile>`
2. Verify no build errors before committing
3. Check that profile-specific overrides work correctly

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
- **AI**: opencode, claude-code, ollama
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
