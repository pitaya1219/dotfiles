# CLAUDE.md - Dotfiles Repository Analysis

## Repository Overview

This is a multi-profile dotfiles configuration repository that uses Nix Home Manager for declarative system configuration management. The repository is designed to support multiple user profiles and platforms (macOS and Linux) with a modular architecture.

## Architecture

### Core Components

1. **Nix Flake Configuration** (`flake.nix`)
   - Uses Nix Home Manager for declarative configuration
   - Supports multiple profiles and platforms
   - Currently configured for:
     - `r-shibuya` profile (aarch64-darwin/macOS)
     - `droid` profile (aarch64-linux/Android Termux)

2. **Task Runner** (`Taskfile.yml`)
   - Uses Task (taskfile.dev) as build/setup tool
   - Provides installation and setup automation
   - Cross-platform OS detection (UNAME_S, UNAME_M)

3. **Modular Configuration Structure**
   - `shared/base.nix`: Common packages and settings
   - `profiles/`: User/device-specific configurations
   - `tasks/`: Automation scripts for setup and maintenance

### Directory Structure

```
/Users/r-shibuya/dotfiles/
├── flake.nix              # Main Nix flake configuration
├── flake.lock             # Locked dependency versions
├── Taskfile.yml           # Main task runner configuration
├── shared/
│   └── base.nix           # Shared configuration (git, vim, claude-code)
├── profiles/
│   ├── r-shibuya.nix      # macOS profile (includes jq)
│   └── droid.nix          # Linux/Android profile (includes htop, tree)
└── tasks/
    ├── install.yml        # Dependency installation tasks
    ├── setup.yml          # Setup orchestration
    ├── nix.yml            # Nix-specific tasks
    └── setup/
        └── nix.yml        # Nix setup implementation
```

## Key Features

### Multi-Profile Support
- **r-shibuya profile**: macOS development environment
  - User: r-shibuya (r-shibuya@tokyo-gas.co.jp)
  - Additional packages: jq
  - Target: `/Users/r-shibuya`

- **droid profile**: Linux/Android Termux environment
  - User: pitaya1219 (runningryuya@gmail.com)
  - Additional packages: htop, tree
  - Target: `/home/pitaya1219`

### Package Management
- **Base packages** (all profiles): git, vim, claude-code
- **Profile-specific packages**: Customized per environment
- **Unfree packages**: claude-code is explicitly allowed

### Automation Tasks

#### Installation Tasks (`task install`)
- Git installation (brew on macOS, apt on Linux)
- Dropbear SSH installation
- Nix package manager installation
- Dependency verification

#### Setup Tasks (`task setup:nix`)
- Nix flakes configuration
- Home Manager profile selection and deployment
- Interactive profile selection during setup

## Common Commands

### Initial Setup
```bash
# 1. Install Task runner
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# 2. Install dependencies
task install

# 3. Setup Nix configuration
task setup:nix
```

### Maintenance Commands
```bash
# List all available tasks
task

# Check dependency status
task install:check-deps

# Switch Home Manager configuration
nix run home-manager/master -- switch --flake .#<profile-name>
```

## Configuration Management

### Nix Home Manager
- State version: 23.11
- Uses nixos-unstable channel
- Home Manager follows nixpkgs input
- Platform-specific home directory detection

### Git Configuration
- Automatically configured per profile
- User name and email set from flake configuration
- No additional git-specific modules currently

### Package Sources
- Primary: nixpkgs (NixOS/nixpkgs/nixos-unstable)
- Home Manager: nix-community/home-manager

## Development Workflow

1. **Profile Creation**: Add new `.nix` files to `profiles/` directory
2. **Package Management**: Edit `shared/base.nix` for common packages, profile-specific files for unique needs
3. **Task Automation**: Extend `tasks/` directory for new automation needs
4. **Platform Support**: OS detection and conditional logic in task files

## Current Status (Git)
- Working branch: `work`
- Modified files: `shared/base.nix`, `tasks/setup/nix.yml`
- Untracked: `tasks/nix.yml`
- Recent commits focus on README updates and task reorganization

## Dependencies

### External Tools
- Task runner (taskfile.dev)
- Nix package manager
- Git version control
- Dropbear SSH (Linux environments)

### Nix Inputs
- nixpkgs: NixOS package collection
- home-manager: Declarative user environment management

## Notes for Development

- The repository uses a modular approach for easy maintenance
- Cross-platform compatibility is built-in through OS detection
- Profile switching is interactive during setup
- All paths use absolute references in Nix configurations
- Task files provide verbose output for troubleshooting