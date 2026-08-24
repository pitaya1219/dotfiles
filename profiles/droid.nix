{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-linux";
      overlays = [ overlays.mistral-vibe overlays.mistral-vibe-proot-unpack overlays.fix-neovim-lua-passthru overlays.pipx-no-check overlays.poetry-no-check overlays.pipx-proot-unpack overlays.logseq-view overlays.logseq-view-proot-unpack overlays.vim-plugin-proot-unpack overlays.nix-claude-code overlays.herdr ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        dotfiles.agent.skills.exclude = [ "asana-create-task" "my-review" ];

        dotfiles.agent.logseq = {
          url = { command = "passage show logseq/http-api/host"; };
          token = { command = "passage show logseq/http-api/claude-code/token"; };
        };

        imports = [
          ../shared/programs/bare.nix
          ../shared/programs/logseq-view.nix
          ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "droid")
          ../shared/programs/bash.nix
          ../shared/programs/claude-code.nix
          ../shared/programs/opencode.nix
          ../shared/programs/vibe.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/herdr.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ../shared/activations/huggingface_hub.nix
          ../shared/activations/proton-pass.nix
          ./droid/activations/termux-font.nix
          ./droid/activations/herdr_mirror.nix
          ./droid/packages/shellm.nix
          ./droid/ssh/config.nix
          ./droid/ssh/headscale.nix
          ./droid/tailscale.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "droid")
          ((import ../lib/neovim-overrides.nix { inherit lib; }).forProfile "droid")
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "droid")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        home = {
          username = "droid";
          homeDirectory = "/home/droid";
          stateVersion = "23.11";
          # herdr-mirror plugin config, mirroring dragonfruit (lepetitprince
          # profile) into this sidebar. Not managed by herdr itself, so it's
          # safe to own declaratively — unlike config.toml. Targets the
          # dragonfruit-herdr-mirror SSH alias (profiles/droid/ssh/headscale.nix),
          # not the general-purpose "dragonfruit" one, so this dedicated key
          # stays scoped to herdr-mirror.
          # herdr-mirror deliberately skips any remote workspace made entirely
          # of another herdr-mirror's own streamer panes (src/mirror.rs,
          # "so mutual mirroring can't nest") — so dragonfruit's own mirror of
          # rose/aviateur never surfaces here transitively. droid mirrors
          # rose/aviateur directly instead (see profiles/droid/ssh/headscale.nix
          # for the ProxyJump-through-dragonfruit routing).
          file.".config/herdr-mirror/hosts.toml".text = ''
            [hosts.dragonfruit]
            target = "lepetitprince@dragonfruit-herdr-mirror"
            prefix = "df:lepetitprince"
            # herdr-mirror's own remote-herdr lookup is just
            # `command -v herdr || ~/.local/bin/herdr` over a non-interactive
            # ssh exec, whose PATH never picks up ~/.nix-profile/bin — so
            # without this it can't find dragonfruit's (home-manager-managed)
            # herdr at all. Confirmed against the live host.
            remote_bin = "~/.nix-profile/bin/herdr"

            [hosts.rose]
            target = "rose@rose-herdr-mirror"
            prefix = "df:rose"
            remote_bin = "~/.nix-profile/bin/herdr"
            # rose has its own active sessions (confirmed live: a mirror
            # attach failed with "terminal already has ..." against a real,
            # in-progress agent pane there) — always_control's default (true)
            # is for headless remotes and fights that. false starts read-only
            # and only takes control when you type into the mirror pane.
            always_control = false

            [hosts.aviateur]
            target = "aviateur@aviateur-herdr-mirror"
            prefix = "df:aviateur"
            remote_bin = "~/.nix-profile/bin/herdr"
            always_control = false
          '';
          packages = with pkgs; [
            android-tools
            cloudflared
            gitea-mcp-server
            jq
            llama-cpp
            mistral-vibe
            rclone
          ];
        };
      })
    ];
  };
}
