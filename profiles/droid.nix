{ nixpkgs, home-manager, overlays, extraModules ? [] }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-linux";
      overlays = [ overlays.mistral-vibe overlays.fix-neovim-lua-passthru overlays.pipx-no-check overlays.poetry-no-check overlays.logseq-view overlays.nix-claude-code overlays.herdr ];
    };
    modules = extraModules ++ [
      ({ config, pkgs, lib, ... }: {
        # This Debian base doesn't ship en_US.UTF-8 pre-generated (only
        # C/C.UTF-8/POSIX), so LANG=en_US.UTF-8 (shared/programs/bash/env.nix)
        # fails setlocale() without this — home-manager builds the archive
        # into the Nix store and points LOCALE_ARCHIVE at it, no root needed.
        i18n.glibcLocales = pkgs.glibcLocales.override {
          allLocales = false;
          locales = [ "en_US.UTF-8/UTF-8" ];
        };

        # Both endpoints, switched with `/model local` and `/model pitaya`.
        # Local is the default: this machine leaves the network often enough
        # that the endpoint which keeps working offline is the better one to
        # land on. Nothing here starts that server, deliberately — on this
        # profile it comes from a separate app rather than from nix, so
        # `local` answers only while that app is running.
        programs.hermes = {
          enable = true;
          default = "local";
          local = {
            enable = true;
            model = "gemma-4-e2b";
          };
          pitaya = {
            enable = true;
            model = "Gemma-4";
            passagePrefix = "hermes/client/droid";
          };
        };

        # koi's endpoint, as before.
        programs.shellm = {
          enable = true;
          endpoint = "pitaya";

          # Android OOM workaround: single-threaded Rust build to prevent
          # SIGKILL from Android's LMK during parallel cargo compilation.
          # Independent of proot -- Android's memory pressure applies to the
          # native VM too.
          extraBuildAttrs.env = {
            CARGO_BUILD_JOBS = "1";
            RUSTFLAGS = "-C codegen-units=1";
          };
        };

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
          ../shared/programs/hermes.nix
          ../shared/programs/shellm.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/herdr.nix
          ../shared/programs/agent-open.nix
          ../shared/programs/herdr-run.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ../shared/activations/huggingface_hub.nix
          ../shared/activations/proton-pass.nix
          ./droid/activations/linux-terminal-font.nix
          ./droid/activations/herdr_mirror.nix
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
