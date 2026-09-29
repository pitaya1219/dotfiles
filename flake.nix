{
  description = "Multi-profile dotfiles configuration with Nix Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mistral-vibe = {
      url = "git+https://git.pitaya.f5.si/pitaya1219/mistral-vibe-nix.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    homelab.url = "git+https://git.pitaya.f5.si/pitaya1219/homelab.git?ref=main";
    logseq-view = {
      url = "git+https://git.pitaya.f5.si/pitaya1219/logseq-view.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-claude-code = {
      url = "github:ryoppippi/nix-claude-code";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Tracks master rather than a release tag: home-manager's bundled herdr
    # lags behind, and the herdr-mirror plugin needs a preview build
    # (2026-06-30 or newer) for its terminal-session-stream API.
    herdr = {
      url = "github:herdrdev/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, neovim-nightly-overlay, mistral-vibe, homelab, logseq-view, nix-claude-code, herdr, hermes-agent }:
    let
      profileLib = import ./lib/profiles.nix { inherit (nixpkgs) lib; };

      overlays = {
        neovim-nightly = neovim-nightly-overlay.overlays.default;
        mistral-vibe = mistral-vibe.overlays.default;
        nix-claude-code = nix-claude-code.overlays.default;
        logseq-view = final: prev: {
          logseq-view = logseq-view.packages.${final.stdenv.hostPlatform.system}.logseq-view;
        };

        herdr = final: prev: {
          herdr = herdr.packages.${final.stdenv.hostPlatform.system}.default;
        };

        # mistral-vibe overlay modifies neovim-unwrapped and drops the lua passthru
        # that neovim's wrapper.nix needs. Restore it with luajit (what nixpkgs
        # neovim is built against). Apply after mistral-vibe in the overlay list.
        fix-neovim-lua-passthru = final: prev: {
          neovim-unwrapped = prev.neovim-unwrapped // { lua = final.luajit; };
          # wrapper.nix reads lua from whatever package is passed as neovim-unwrapped.
          # When programs.neovim.package = pkgs.neovim (the wrapped package), home-manager
          # calls wrapNeovimUnstable pkgs.neovim {...} and wrapper.nix does neovim-unwrapped.lua.
          # pkgs.neovim doesn't expose lua in passthru, so we add it here.
          neovim = prev.neovim // { lua = final.luajit; };
        };

      };
      
      # hermes-agent ships its own home-manager module, and its default package
      # is this flake's own build rather than one re-instantiated against our
      # nixpkgs — so the module has to come from the input directly. There is
      # nothing for an overlay to carry.
      hermesModules = [ hermes-agent.homeManagerModules.default ];

      profileExtraModules = {
        rose = [
          homelab.homeManagerModules.dns-updater
          homelab.homeManagerModules.nextcloud-backup
          homelab.homeManagerModules.budget-book-backup
          homelab.homeManagerModules.gitea-backup
          homelab.homeManagerModules.identity-backup
          homelab.homeManagerModules.tuwunel-backup
          homelab.homeManagerModules.dufs-backup
          homelab.homeManagerModules.grist-backup
          homelab.homeManagerModules.windmill-backup
        ];
        r-shibuya = hermesModules;
        droid = hermesModules;
        lepetitprince = hermesModules;
      };

      # Load all profiles automatically
      profiles = profileLib.loadProfiles {
        profilesPath = ./profiles;
        inherit nixpkgs home-manager overlays;
        extraModules = profileExtraModules;
      };

      # Generate home configurations from profiles
      homeConfigurations = builtins.mapAttrs
        (name: profile: profile.mkHomeConfiguration)
        profiles;

      # Activating against a throwaway home directory is how a change gets
      # exercised end to end without putting the real one at risk. The target
      # directory comes from $DOTFILES_SANDBOX_HOME rather than a fixed path so
      # each sandbox can live wherever the caller is working; reading it means
      # these outputs only evaluate under --impure.
      sandboxHome =
        let dir = builtins.getEnv "DOTFILES_SANDBOX_HOME";
        in if dir == "" then
          throw "DOTFILES_SANDBOX_HOME is unset. Set it to the sandbox home directory and pass --impure."
        else dir;

      # A home-manager activation writes under $HOME apart from what it hands to
      # a service manager, which addresses units by name and so reaches the live
      # session however HOME is set. Switching those subsystems off wholesale is
      # what keeps this from becoming a list with an entry per module.
      #
      # launchd needs the agent set cleared rather than `launchd.enable = false`:
      # that option only feeds an assertion, leaving the activation that runs
      # `launchctl bootstrap` against gui/$UID wired to `launchd.agents`.
      # `systemd.user.enable` does gate both its units and its reload step.
      sandboxModule = { lib, ... }: {
        home.homeDirectory = lib.mkForce sandboxHome;
        launchd.agents = lib.mkForce { };
        systemd.user.enable = lib.mkForce false;
      };

      sandboxConfigurations = builtins.mapAttrs
        (_: configuration: configuration.extendModules { modules = [ sandboxModule ]; })
        homeConfigurations;

      # Darwin (macOS system-level) configurations — only for profiles that opt in
      # r-shibuya uses nix-darwin for declarative brew cask management and system settings
      darwinConfigurations."r-shibuya" =
        (import ./profiles/r-shibuya.nix {
          inherit nixpkgs home-manager overlays nix-darwin;
          extraModules = profileExtraModules.r-shibuya;
        }).mkDarwinConfiguration;

    in
    {
      inherit homeConfigurations darwinConfigurations sandboxConfigurations;
    };
}
