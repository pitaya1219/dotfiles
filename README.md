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
