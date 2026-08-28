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
      url = "github:pitaya1219/mistral-vibe-nix";
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
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, neovim-nightly-overlay, mistral-vibe, homelab, logseq-view, nix-claude-code, herdr }:
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

        # WORKAROUND: Disable pipx install checks to avoid test suite failures.
        # The test suite has assertion failures in package specifier formatting.
        # This affects all platforms. Should be removed once upstream fixes are available.
        pipx-no-check = final: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (_: pyPrev: {
              pipx = pyPrev.pipx.overrideAttrs (_: { doInstallCheck = false; });
            })
          ];
        };

        # WORKAROUND: On the current nixpkgs pin (python3.14), poetry's pytest
        # suite has a handful of failing tests (test_executor batch/yanked-package
        # assertions, test_env full-pipe) that abort the derivation build. They are
        # upstream test issues, not a problem with poetry itself, so disable the
        # test suite.
        #
        # Override the top-level `poetry` directly (not via pythonPackagesExtensions):
        # pkgs.poetry builds its unwrapped module through a private `python3.override`
        # package set in its own package.nix, so there is no `python3Packages.poetry`
        # for a python-set extension to hook. pkgs.poetry is a toPythonApplication, so
        # overridePythonAttrs threads to the underlying module; setting the
        # python-level `doCheck = false` makes mk-python-derivation skip the pytest
        # install-check phase (it derives stdenv doInstallCheck from that attr).
        # Should be removed once upstream fixes land on our nixpkgs pin.
        poetry-no-check = final: prev: {
          poetry = prev.poetry.overridePythonAttrs (_: { doCheck = false; });
        };

        # WORKAROUND: nixpkgs bumped pandas past parquet-tools' pinned <3.0.0
        # upper bound, breaking pythonRuntimeDepsCheckHook. parquet-tools already
        # relaxes halo/tabulate/thrift the same way upstream; extend that to pandas.
        # Should be removed once parquet-tools bumps its pandas ceiling upstream.
        parquet-tools-relax-pandas = final: prev: {
          parquet-tools = prev.parquet-tools.overridePythonAttrs (old: {
            pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "pandas" ];
          });
        };

        # WORKAROUND: nixpkgs' bundled ld64 (957.1, via cctools-binutils-darwin
        # 1010.6) crashes with a Trace/BPT trap (SIGTRAP, exit 133) in
        # ld::passes::stubs::Pass::process while linking starship against
        # apple-sdk-14.4 frameworks. Deterministic (crashes at the same binary
        # offset every time) but not reproducible with a minimal synthetic
        # link, so it looks like a real bug in this old ld64 build triggered
        # only by large/complex link jobs. Route around it via lld instead.
        # Should be removed once nixpkgs ships a newer ld64 that fixes this.
        starship-lld = final: prev: {
          starship = prev.starship.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.llvmPackages.bintools ];
            RUSTFLAGS = (old.RUSTFLAGS or "") + " -C link-arg=-fuse-ld=lld";
          });
        };

      };
      
      # Load all profiles automatically
      profiles = profileLib.loadProfiles {
        profilesPath = ./profiles;
        inherit nixpkgs home-manager overlays;
        extraModules = {
          rose = [
            homelab.homeManagerModules.dns-updater
            homelab.homeManagerModules.nextcloud-backup
          ];
        };
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
          extraModules = [];
        }).mkDarwinConfiguration;

    in
    {
      inherit homeConfigurations darwinConfigurations sandboxConfigurations;
    };
}
