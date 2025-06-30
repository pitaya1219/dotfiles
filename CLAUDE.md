# CLAUDE.md - Dotfiles Repository Analysis

## Repository Overview

This is a sophisticated multi-profile dotfiles configuration repository that uses Nix Home Manager for declarative system configuration management. The repository features automatic profile discovery, modular architecture, and cross-platform support for macOS and Linux environments.

## Architecture

### Core Components

1. **Nix Flake Configuration** (`flake.nix`)
   - Uses Home Manager with nixos-unstable channel
   - Automatic profile discovery via custom library (`lib/profiles.nix`)
   - Neovim nightly overlay integration
   - Supports multiple profiles and platforms

2. **Profile Discovery System** (`lib/profiles.nix`)
   - Automatically discovers profiles from `profiles/*.nix`
   - Handles platform-specific home directory detection
   - Merges base configuration with profile-specific overrides

3. **Task Runner** (`Taskfile.yml`)
   - Cross-platform automation using Task (taskfile.dev)
   - OS detection (UNAME_S, UNAME_M) for conditional logic
   - Hierarchical task organization

### Directory Structure

```
/Users/r-shibuya/dotfiles/
├── flake.nix                    # Main Nix flake with auto-discovery
├── flake.lock                   # Locked dependency versions
├── Taskfile.yml                 # Main task runner configuration
├── lib/
│   └── profiles.nix             # Profile discovery utilities
├── profiles/
│   ├── r-shibuya.nix           # macOS profile
│   ├── r-shibuya/              # Profile-specific overrides
│   │   └── neovim/
│   │       ├── after/plugin/    # Profile neovim plugins
│   │       ├── coc-settings.json # CoC configuration
│   │       └── plugins.nix      # Plugin definitions
│   ├── droid.nix               # Linux/Android profile
│   └── droid/                  # Profile overrides
├── shared/
│   ├── activations/
│   │   └── aider.nix           # Automated aider-chat setup
│   └── programs/
│       ├── bare.nix            # Base packages
│       ├── neovim.nix          # Advanced neovim config
│       ├── neovim/             # Shared neovim files
│       └── unfree.nix          # Unfree package management
└── tasks/
    ├── install.yml             # Dependency installation
    ├── setup.yml               # Setup orchestration
    ├── nix.yml                 # Nix utilities
    └── setup/
        ├── nix.yml             # Nix setup implementation
        └── ollama.yml          # Interactive Ollama setup
```

## Profile Configurations

### r-shibuya Profile (macOS Development)
- **Platform**: aarch64-darwin (Apple Silicon)
- **Home**: `/Users/r-shibuya`
- **Packages**: jq (additional)
- **Neovim**: copilot-vim integration
- **Unfree**: copilot.vim allowed

### droid Profile (Linux/Android Termux)
- **Platform**: aarch64-linux (ARM64)
- **Home**: `/home/droid`
- **Packages**: jq (additional)
- **Neovim**: Base configuration only

## Package Management

### Base Packages (`shared/programs/bare.nix`)
- Core tools: tree, curl, expect, sqlite, git, pipx
- AI tools: claude-code, ollama
- Development: Language servers (TypeScript, ESLint, Prettier, nixd)

### Neovim Configuration
- **Multi-layer system**: Base + profile-specific plugins
- **Automatic merging**: Combines configurations seamlessly
- **Language servers**: Full LSP integration
- **Custom plugins**: GitHub-sourced with hash verification
- **Nightly builds**: Via neovim-nightly-overlay

### Unfree Package Management
- Centralized allowlist system (`shared/programs/unfree.nix`)
- Profile-specific additions supported
- Currently allows: claude-code, copilot.vim

## Automation System

### Installation Tasks (`task install`)
- Git installation (brew/apt based on OS)
- Dropbear SSH setup
- Nix package manager installation
- Dependency verification

### Setup Tasks (`task setup`)
- Interactive Nix configuration (`task setup:nix`)
- Ollama model setup with rich UI (`task setup:ollama`)
- Automatic profile detection and selection

### Utility Tasks
- Nix store cleanup (`task nix:clean`)
- GitHub hash fetching (`task nix:github-hash`)
- Dependency status checking

## Key Commands

### Initial Setup
```bash
# Install Task runner
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Install dependencies
task install

# Interactive setup with profile selection
task setup:nix
```

### Maintenance
```bash
# List available tasks
task

# Check dependencies
task install:check-deps

# Clean Nix store
task nix:clean

# Setup Ollama models
task setup:ollama

# Manual profile switch
nix run home-manager/master -- switch --flake .#<profile>
```

## Advanced Features

### Automatic Profile Discovery
- Profiles automatically loaded from `profiles/*.nix`
- No manual flake.nix editing required for new profiles
- Platform-specific home directory detection

### Layered Configuration
- Base configuration in `shared/`
- Profile-specific overrides in `profiles/<name>/`
- Automatic merging of neovim configurations

### Cross-Platform Support
- OS detection in task automation
- Platform-specific package installation
- Conditional configuration based on system type

## Dependencies

### External Tools
- Nix package manager
- Task runner (taskfile.dev)
- Git version control
- Home Manager

### Nix Inputs
- nixpkgs: NixOS/nixpkgs (nixos-unstable)
- home-manager: nix-community/home-manager
- neovim-nightly-overlay: nix-community/neovim-nightly-overlay

### Development Tools
- AI: Claude Code, GitHub Copilot, Ollama, aider-chat
- Languages: TypeScript/ESLint/Prettier LSPs, nixd
- Shell: ripgrep, tree, curl, jq

## Git Status
- Working branch: `work`
- Status: Clean, ahead of origin by 7 commits
- Recent focus: Profile management restructuring with automatic discovery

## Notes

- Repository uses automatic profile discovery for easy maintenance
- Sophisticated neovim configuration with multi-layer plugin system
- Cross-platform compatibility built into automation
- All configurations use absolute paths for reliability
- Unfree packages centrally managed with profile-specific additions
- Interactive setup process with rich UI feedback

## Git Commit Preferences

- NEVER include Claude-related content in commit messages
- Use simple, descriptive commit messages
- Start commit messages with capital letter
- End commit messages with period
- Format: "Capitalize first word and end with period."