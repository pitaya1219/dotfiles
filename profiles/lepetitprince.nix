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
          ../shared/activations/rootless-docker.nix
          ../shared/activations/proton-pass.nix
          ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "lepetitprince")
          ../shared/programs/bash.nix
          ../shared/programs/bare.nix
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
          ./lepetitprince/ssh/local-mirrors.nix
          ./lepetitprince/activations/herdr_mirror.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "lepetitprince")
          ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "lepetitprince")
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "lepetitprince")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        # Keys allowed to log in as lepetitprince, one passage entry per
        # purpose under ssh/dragonfruit/authorized_keys/<purpose> — this
        # activation OWNS ~/.ssh/authorized_keys fully, so anything
        # currently authorized on dragonfruit but not listed here must be
        # added as its own passage entry BEFORE switching, or that access
        # is revoked on activation.
        dotfiles.passageAuthorizedKeys = [
          {
            purpose = "droid-herdr-mirror";
            passagePath = "ssh/dragonfruit/authorized_keys/droid-herdr-mirror";
          }
        ];

        home = {
          username = "lepetitprince";
          homeDirectory = "/home/lepetitprince";
          stateVersion = "23.11";
          # herdr-mirror plugin config, mirroring rose and aviateur (local
          # accounts on this same machine — reached over localhost, see
          # ./lepetitprince/ssh/local-mirrors.nix) into this sidebar.
          file.".config/herdr-mirror/hosts.toml".text = ''
            [hosts.rose]
            target = "rose@rose-herdr-mirror"
            prefix = "rose"
            remote_bin = "~/.nix-profile/bin/herdr"
            # rose has its own active sessions, and droid *also* mirrors it
            # directly (profiles/droid/ssh/headscale.nix) — always_control's
            # default (true) here meant this mirror held the write-lock
            # permanently, starving droid's mirror of control entirely.
            # false lets both stay read-only until whichever one is actually
            # being typed into promotes.
            always_control = false

            [hosts.aviateur]
            target = "aviateur@aviateur-herdr-mirror"
            prefix = "aviateur"
            remote_bin = "~/.nix-profile/bin/herdr"
            always_control = false
          '';
          packages = with pkgs; [
            gitea-mcp-server
            cloudflared
            rclone
            passt
            mistral-vibe
            tailscale
            go-task
          ];
        };
      })
    ];
  };
}
