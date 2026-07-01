{ nixpkgs, home-manager, overlays, extraModules ? [], nix-darwin ? null }:

let
  lib = nixpkgs.lib;
  system = "aarch64-darwin";
  netskopeCA = "/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem";

  nixpkgsConfig = {
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "claude-code"
      "specs.nvim"
      "copilot.vim"
    ];
    packageOverrides = pkgs: {
      neovim-unwrapped = pkgs.neovim-unwrapped.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
        checkPhase = "echo 'Tests skipped on macOS'";
      });
    };
  };

  darwinOverlays = [
    overlays.neovim-nightly
    overlays.mistral-vibe
    overlays.pipx-no-check
    overlays.fix-neovim-lua-passthru
    overlays.logseq-view
  ];

  # Shared home-manager modules used by both mkHomeConfiguration and mkDarwinConfiguration
  homeModules = [
    ({ config, pkgs, lib, ... }: {
      dotfiles.protonPass.caCertFile = "/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem";

      dotfiles.claudeJson.claudeAiMcpEverConnected = [ "claude.ai Asana" "claude.ai GitHub Integration" "claude.ai Slack" ];

      dotfiles.agent.logseq = {
        url = "http://localhost:12315";
        token = { command = "passage show logseq/http-api/claude-code/token"; };
      };

      dotfiles.agent.asana = {
        projectGid = "1208405292637994";
        todoSectionGid = "1209218441201478";
      };

      programs.mtg-minutes = {
        enable = true;
        logseqTokenCommand = "passage show logseq/http-api/claude-code/token";
      };

      programs.obs-noise-cancel = {
        enable = true;
        configSourceDir = ./r-shibuya/obs;
      };

      dotfiles.agent.dailyReport = {
        sources = {
          github = { user = "pitaya1219"; };
          slack = { user_id = "U05BARN5R98"; user_name = "r-shibuya"; };
          asana = true;
          logseq = true;
          sessions = { dir = "~/agent-sessions"; };
        };
        output = { logseq = true; };
      };

      imports = [
        ../shared/activations/proton-pass.nix
        ./r-shibuya/corp.nix
        ../shared/programs/bare.nix
        ../shared/programs/logseq-view.nix
        ./r-shibuya/logseq-sync.nix
        ../shared/programs/mtg-minutes.nix
        ../shared/programs/obs.nix
        ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "r-shibuya")
        ../shared/programs/bash.nix
        ../shared/programs/claude-code.nix
        ../shared/programs/opencode.nix
        ../shared/programs/git.nix
        ../shared/programs/neovim.nix
        ../shared/programs/tmux.nix
        ../shared/programs/starship.nix
        ../shared/programs/readline.nix
        ./r-shibuya/ssh/config.nix
        ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "r-shibuya")
        ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "r-shibuya")
        ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "r-shibuya")
      ];

      home = {
        username = "r-shibuya";
        homeDirectory = "/Users/r-shibuya";
        stateVersion = "23.11";
        packages = with pkgs; [
          cloudflared
          docker
          docker-credential-helpers
          beamPackages.elixir
          elixir-ls
          gitea-mcp-server
          jq
          mistral-vibe
          rclone
          tailscale
          xlsx2csv
          colordiff
          coreutils
          gh
          ghostscript
          go-task
          joplin
          nmap
          parallel
          parquet-tools
          potrace
          pstree
          scrcpy
          watch
          wireguard-tools
        ];
        file.".config/tmux/override.conf".source = ./r-shibuya/tmux/override.conf;
      };
    })
  ];
in
{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      inherit system;
      overlays = darwinOverlays;
    };
    modules = homeModules ++ [
      { nixpkgs.config = nixpkgsConfig; }
    ];
  };

  mkDarwinConfiguration = if nix-darwin == null then null else nix-darwin.lib.darwinSystem {
    inherit system;
    specialArgs = { inherit nixpkgsConfig netskopeCA; };
    modules = [
      home-manager.darwinModules.home-manager
      ({ pkgs, lib, ... }: {
        nixpkgs.overlays = darwinOverlays;

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          users.r-shibuya.imports = homeModules;
        };
      })
      ./r-shibuya/darwin.nix
    ];
  };
}
