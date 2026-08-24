{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ overlays.neovim-nightly overlays.mistral-vibe overlays.pipx-no-check overlays.poetry-no-check overlays.logseq-view overlays.nix-claude-code overlays.herdr ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        dotfiles.agent.skills.exclude = [ "asana-create-task" "my-review" ];

        dotfiles.agent.logseq = {
          url = { command = "passage show logseq/http-api/host"; };
          token = { command = "passage show logseq/http-api/claude-code/token"; };
        };

        imports = [
          ../lib/passage-secrets.nix
          ../shared/activations/proton-pass.nix
          ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "aviateur")
          ../shared/programs/bash.nix
          ../shared/programs/bare.nix
          ../shared/programs/logseq-view.nix
          ../shared/programs/claude-code.nix
          ../shared/programs/opencode.nix
          ../shared/programs/vibe.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/herdr.nix
          ../shared/programs/agent-resume.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "aviateur")
          ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "aviateur")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        # Keys allowed to log in as aviateur, one passage entry per purpose —
        # this activation OWNS ~/.ssh/authorized_keys fully, so anything
        # currently authorized on aviateur but not listed here must be added
        # as its own passage entry BEFORE switching, or that access is
        # revoked on activation.
        dotfiles.passageAuthorizedKeys = [
          {
            purpose = "lepetitprince-herdr-mirror";
            passagePath = "ssh/aviateur/authorized_keys/lepetitprince-herdr-mirror";
          }
          {
            purpose = "droid-herdr-mirror";
            passagePath = "ssh/aviateur/authorized_keys/droid-herdr-mirror";
          }
        ];

        home = {
          username = "aviateur";
          homeDirectory = "/home/aviateur";
          stateVersion = "23.11";
          packages = with pkgs; [
            gitea-mcp-server
            mistral-vibe
            rclone
          ];
        };
      })
    ];
  };
}
