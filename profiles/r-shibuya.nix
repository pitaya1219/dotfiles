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
            oauth = {
              clientId = "1215309192573242";
              callbackPort = 8080;
            };
          };
        };

        # Inject Asana client secret into the Claude Code Keychain blob.
        # This is the same location `claude mcp add --client-secret` writes to,
        # so Claude Code finds the secret without any ~/.claude.json modification.
        home.activation.asanaKeychain = lib.hm.dag.entryAfter ["writeBoundary"] ''
          _secret="$("$HOME/.nix-profile/bin/passage" show asana/client/secret 2>/dev/null || true)"
          if [ -n "$_secret" ]; then
            _current="$(security find-generic-password \
              -s "Claude Code-credentials" -a "$USER" -w 2>/dev/null || echo '{}')"
            _key="$(echo "$_current" | ${pkgs.jq}/bin/jq -r \
              '(.mcpOAuthClientConfig // {}) | keys[] | select(startswith("asana|"))' \
              2>/dev/null | head -1)"
            _key="''${_key:-asana|71ef7e5a38eea4f1}"
            _new="$(echo "$_current" | ${pkgs.jq}/bin/jq \
              --arg k "$_key" --arg s "$_secret" \
              '.mcpOAuthClientConfig[$k].clientSecret = $s')"
            security add-generic-password -U \
              -s "Claude Code-credentials" \
              -l "Claude Code-credentials" \
              -a "$USER" \
              -w "$_new" 2>/dev/null || true
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
