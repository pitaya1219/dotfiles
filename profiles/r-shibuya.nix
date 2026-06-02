{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-darwin";
      overlays = [ overlays.neovim-nightly overlays.mistral-vibe overlays.pipx-no-check ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        dotfiles.claude-code.mcpServers = {
          asana = {
            type = "http";
            url = "https://mcp.asana.com/v2/mcp";
            oauth.callbackPort = 8080;
          };
        };

        # Inject Asana OAuth credentials from env vars (defined in env.nix via passage).
        home.activation.asanaCredentials = lib.hm.dag.entryAfter ["claudeJson"] ''
          claude_json="$HOME/.claude.json"
          if [ -f "$claude_json" ]; then
            _asana_id="''${ASANA_CLIENT_ID:-$(passage show asana/client/id 2>/dev/null)}"
            _asana_secret="''${ASANA_CLIENT_SECRET:-$(passage show asana/client/secret 2>/dev/null)}"
            tmp=$(mktemp)
            ${pkgs.jq}/bin/jq \
              --arg id "$_asana_id" \
              --arg secret "$_asana_secret" \
              '.mcpServers.asana.oauth.clientId = $id | .mcpServers.asana.oauth.clientSecret = $secret' \
              "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
          fi
        '';

        imports = [
          ../shared/activations/proton-pass.nix
          ../shared/programs/bare.nix
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
          ./r-shibuya/rclone/config.nix
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
            xlsx2csv
          ];
          file.".config/tmux/override.conf".source = ./r-shibuya/tmux/override.conf;
        };
      })
    ];
  };
}
