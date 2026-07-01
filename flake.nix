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
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, neovim-nightly-overlay, mistral-vibe, homelab, logseq-view }:
    let
      profileLib = import ./lib/profiles.nix { inherit (nixpkgs) lib; };

      overlays = {
        neovim-nightly = neovim-nightly-overlay.overlays.default;
        mistral-vibe = mistral-vibe.overlays.default;
        logseq-view = final: prev: {
          logseq-view = logseq-view.packages.${final.stdenv.hostPlatform.system}.logseq-view;
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

        # WORKAROUND: proot does not provide dynamic /dev/fd entries for high-numbered
        # file descriptors. patchelf's setup hook uses bash process substitution
        # (done < <(find ...)) which requires /dev/fd/N. Create a wrapper that
        # symlinks the original binary but replaces the hook with a temp-file version.
        # dontPatchELF skips the broken fixup step when building this wrapper itself.
        # Apply only to the droid profile via droid.nix overlays.
        # WORKAROUND: proot-only fix for pipx unpackPhase.
        # GNU coreutils cp uses fchmodat(AT_FDCWD,"",AT_EMPTY_PATH) to set permissions,
        # which proot intercepts and returns ENOENT. The default unpackPhase uses
        # `cp -prd`, triggering this. Override to use tar instead.
        # Apply only to the droid profile via droid.nix overlays.
        pipx-proot-unpack = final: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (_: pyPrev: {
              pipx = pyPrev.pipx.overrideAttrs (_: {
                unpackPhase = ''
                  runHook preUnpack
                  mkdir source
                  tar cf - -C "$src" . | tar xf - -C source
                  chmod -R u+w source
                  sourceRoot="source"
                  runHook postUnpack
                '';
                # installShellCompletion passes /dev/fd/N to the install binary.
                # proot intercepts path syscalls and its /dev/fd only has entries
                # 0-3, so open("/dev/fd/63") → ENOENT. Skip completions entirely.
                postInstall = "";
              });
            })
          ];
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

      # Darwin (macOS system-level) configurations — only for profiles that opt in
      # r-shibuya uses nix-darwin for declarative brew cask management and system settings
      darwinConfigurations."r-shibuya" =
        (import ./profiles/r-shibuya.nix {
          inherit nixpkgs home-manager overlays nix-darwin;
          extraModules = [];
        }).mkDarwinConfiguration;

    in
    {
      inherit homeConfigurations darwinConfigurations;
    };
}
