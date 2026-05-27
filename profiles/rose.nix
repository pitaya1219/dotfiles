{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ overlays.neovim-nightly overlays.mistral-vibe ];
    };
    modules = extraModules ++ [
      ({ config, pkgs, lib, ... }: {
        imports = [
          ../shared/activations/huggingface_hub.nix
          ../shared/activations/rootless-docker.nix
          ../shared/activations/proton-pass.nix
          ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "rose")
          ../shared/programs/bash.nix
          ../shared/programs/bare.nix
          ../shared/programs/rust.nix
          ../shared/programs/claude-code.nix
          ../shared/programs/opencode.nix
          ../shared/programs/vibe.nix
          ../shared/programs/direnv.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "rose")
          ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "rose")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
          ./rose/tailscale.nix
        ];

        services.dns-updater.enable = true;

        services.nextcloud-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            sourceDir = "/home/rose/homelab/apps/storage/nextcloud/nextcloud/data/";
            distDir = "/media/backup/nextcloud/";
            remote = "";
            exclude = "**/piwigo/**,appdata_*/**,**/.ocdata/**,.htaccess,**trashbin**,**/files_versions/**,nextcloud.log,**/Talk/**";
            backupRemovedFile = true;
            verbose = true;
            encrypted = false;
            onCalendar = "Fri *-*-* 22:00:00";
            onBootDelay = "6h";
          };
          pcloud-encrypted = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            parentDir = "backup";
            encryptSubdir = "nextcloud";
            sourceDir = "/media/backup/nextcloud";
            backupRemovedFile = false;
            verbose = true;
            encrypted = true;
            onCalendar = "Mon *-*-* 22:00:00";
            onBootDelay = "12h";
          };
        };

        home = {
          username = "rose";
          homeDirectory = "/home/rose";
          stateVersion = "23.11";
          packages = with pkgs; [
            gitea-mcp-server
            mistral-vibe
            passt
            tea
            rclone
          ];
        };
      })
    ];
  };
}
