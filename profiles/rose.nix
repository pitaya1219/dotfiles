{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ overlays.typescript-language-server-pnpm-hash overlays.neovim-nightly overlays.mistral-vibe overlays.logseq-view overlays.logseq-cli overlays.nix-claude-code overlays.herdr ];
    };
    modules = extraModules ++ [
      ({ config, pkgs, lib, ... }: {
        # koi's endpoint. This host runs no model of its own.
        programs.shellm = {
          enable = true;
          endpoint = "pitaya";
        };

        programs.logseq-db = {
          enable = true;
          cliPackage = pkgs.logseq-cli;
        };

        # u/Ryu/loki_query as its own MCP connection, carrying a token scoped
        # (Account settings > Tokens > Generate MCP URL > Limit token
        # permissions) to just that script's path -- distinct from the broad
        # `windmill` connection in shared/programs/mcp-servers.nix. rose-only,
        # unlike logseq/dufs (also in the personal workspace, but shared
        # across profiles in shared/programs/mcp-servers.nix).
        dotfiles.httpMcpServers.loki = {
          url = "\${WINDMILL_LOKI_MCP_URL}";
        };

        imports = [
          ../shared/programs/logseq-db.nix
          ../lib/passage-secrets.nix
          ../shared/activations/huggingface_hub.nix
          ../shared/activations/rootless-docker.nix
          ../shared/activations/proton-pass.nix
          ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "rose")
          ../shared/programs/bash.nix
          ../shared/programs/bare.nix
          ../shared/programs/shellm.nix
          ../shared/programs/logseq-view.nix
          ../shared/programs/rust.nix
          ../shared/programs/claude-code.nix
          ../shared/programs/opencode.nix
          ../shared/programs/vibe.nix
          ../shared/programs/direnv.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/herdr.nix
          ../shared/programs/agent-open.nix
          ../shared/programs/herdr-run.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ../shared/programs/nix.nix
          ../shared/programs/attic-cache.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "rose")
          ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "rose")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
          ./rose/tailscale.nix
          ./rose/internal-relay.nix
          ./rose/hermes-backup.nix
          ./rose/disk-cleanup-check.nix
        ];

        # Keys allowed to log in as rose, one passage entry per purpose —
        # this activation OWNS ~/.ssh/authorized_keys fully, so anything
        # currently authorized on rose but not listed here must be added as
        # its own passage entry BEFORE switching, or that access is revoked
        # on activation.
        dotfiles.passageAuthorizedKeys = [
          {
            purpose = "lepetitprince-herdr-mirror";
            passagePath = "ssh/rose/authorized_keys/lepetitprince-herdr-mirror";
          }
          {
            purpose = "droid-herdr-mirror";
            passagePath = "ssh/rose/authorized_keys/droid-herdr-mirror";
          }
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

        services.budget-book-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            dumpDir = "/media/backup/budget-book";
            keep = 5;
            encrypted = true;
            parentDir = "backup";
            encryptSubdir = "budget-book";
            interval = "3d";
            onBootDelay = "9h";
          };
        };

        services.gitea-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            dumpDir = "/media/backup/gitea";
            keep = 5;
            encrypted = true;
            parentDir = "backup";
            encryptSubdir = "gitea";
            onCalendar = "*-*-* 02:00:00";
            onBootDelay = "3h";
          };
        };

        services.logseq-sync-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            dumpDir = "/media/backup/logseq-sync";
            keep = 5;
            encrypted = true;
            parentDir = "backup";
            encryptSubdir = "logseq-sync";
            onCalendar = "*-*-* 04:30:00";
            onBootDelay = "5h 30min";
          };
        };

        services.logseq-sync-checksum = {
          enable = true;
          homelabRoot = "/home/rose/homelab";
        };

        services.identity-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            dumpDir = "/media/backup/identity";
            keep = 5;
            encrypted = true;
            parentDir = "backup";
            encryptSubdir = "identity";
            onCalendar = "*-*-* 02:30:00";
            onBootDelay = "3h 30min";
          };
        };

        services.tuwunel-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            sourceDir = "/home/rose/homelab/apps/communication/tuwunel/data";
            distDir = "/media/backup/tuwunel/";
            parentDir = "backup";
            encryptSubdir = "tuwunel";
            encrypted = true;
            onCalendar = "*-*-* 01:30:00";
            onBootDelay = "2h";
          };
        };

        services.dufs-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            sourceDir = "/home/rose/homelab/apps/storage/dufs/data";
            distDir = "/media/backup/dufs/";
            parentDir = "backup";
            encryptSubdir = "dufs";
            encrypted = true;
            onCalendar = "*-*-* 03:00:00";
            onBootDelay = "4h";
          };
        };

        services.grist-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            # data/app is a symlink (-> /media/ssd/app/grist/app); rclone
            # won't follow it without --copy-links, so point at the real
            # path directly instead.
            sourceDir = "/media/ssd/app/grist/app";
            distDir = "/media/backup/grist/";
            parentDir = "backup";
            encryptSubdir = "grist";
            encrypted = true;
            onCalendar = "*-*-* 03:30:00";
            onBootDelay = "4h 30min";
          };
        };

        services.windmill-backup = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            dumpDir = "/media/backup/windmill";
            keep = 5;
            encrypted = true;
            parentDir = "backup";
            encryptSubdir = "windmill";
            onCalendar = "*-*-* 04:00:00";
            onBootDelay = "5h";
          };
        };

        services.dtrack-scan = {
          main = {
            enable = true;
            homelabRoot = "/home/rose/homelab";
            onCalendar = "Fri *-*-* 05:30:00";
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
