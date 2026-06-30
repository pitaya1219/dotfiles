{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-darwin";
      overlays = [ overlays.neovim-nightly overlays.mistral-vibe overlays.pipx-no-check ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        dotfiles.claudeJson.claudeAiMcpEverConnected = [ "claude.ai Asana" "claude.ai GitHub Integration" "claude.ai Slack" ];

        dotfiles.agent.logseq = {
          url = "http://localhost:12315";
          token = { command = "passage show logseq/http-api/claude-code/token"; };
        };

        programs.mtg-minutes = {
          enable = true;
          logseqTokenCommand = "passage show logseq/http-api/claude-code/token";
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
          ../shared/programs/bare.nix
          ../shared/programs/logseq-view.nix
          ../shared/programs/mtg-minutes.nix
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
          (import ../shared/programs/unfree.nix { additionalPackages = [ "copilot.vim" ]; })
        ];

        # WORKAROUND: Force package overrides at nixpkgs.config level for macOS
        # This ensures ALL evaluations use the modified packages
        nixpkgs.config.packageOverrides = pkgs: {
          neovim-unwrapped = pkgs.neovim-unwrapped.overrideAttrs (old: {
            doCheck = false;
            doInstallCheck = false;
            checkPhase = "echo 'Tests skipped on macOS'";
          });
        };

        home = {
          username = "r-shibuya";
          homeDirectory = "/Users/r-shibuya";
          stateVersion = "23.11";
          packages = with pkgs; [
            cloudflared
            docker
            docker-credential-helpers
            elixir
            elixir-ls
            gitea-mcp-server
            jq
            mistral-vibe
            rclone
            tailscale
            xlsx2csv
          ];
          file.".config/tmux/override.conf".source = ./r-shibuya/tmux/override.conf;
        };
      })
    ];
  };
}
