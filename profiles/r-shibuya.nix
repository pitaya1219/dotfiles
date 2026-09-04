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
    overlays.poetry-no-check
    overlays.fix-neovim-lua-passthru
    overlays.logseq-view
    overlays.nix-claude-code
    overlays.parquet-tools-relax-pandas
    overlays.starship-lld
    overlays.herdr
  ];

  # Shared home-manager modules used by both mkHomeConfiguration and mkDarwinConfiguration
  homeModules = extraModules ++ [
    ({ config, pkgs, lib, ... }: {
      dotfiles.protonPass.caCertFile = "/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem";

      dotfiles.claudeJson.claudeAiMcpEverConnected = [ "claude.ai Asana" "claude.ai GitHub Integration" "claude.ai Slack" ];

      dotfiles.claude-code.model = "opus";

      dotfiles.agent.logseq = {
        url = "http://localhost:12315";
        token = { command = "passage show logseq/http-api/claude-code/token"; };
      };

      # This is the only profile signed in to the work Asana and Gitea, so it is
      # the only one that takes the skills excluded by default in agent.nix.
      dotfiles.agent.skills.exclude = [];

      dotfiles.agent.asana = {
        projectGid = "1208405292637994";
        todoSectionGid = "1209218441201478";
      };

      programs.mtg-minutes = {
        enable = true;
        logseqTokenCommand = "passage show logseq/http-api/claude-code/token";

        # 右Command 単独押しで voice-in をトグルする Karabiner ルールを配置する
        # (置くだけでは効かない。Karabiner の GUI で一度だけ有効化する)。
        # 送出するのは常駐プロセスだけで、ホットキーが叩く --toggle は socket に
        # 書くクライアントなので、ホットキー側にアクセシビリティ許可は要らない。
        voiceIn.karabiner.enable = true;

        # daemon.enable は入れていない。launchd が上げた常駐は責任プロセスが
        # 自分自身になり、ターミナルに与えたアクセシビリティ許可が効かないため。
        # 常駐は端末から `voice-in --daemon` で上げる(iTerm の許可がそのまま効く)。
      };

      programs.browse.enable = true;

      # llama-server on this machine is the only endpoint here — no client
      # exists for ai.pitaya.f5.si under this profile, and this one is a
      # corporate laptop, so nothing leaves it.
      programs.hermes = {
        enable = true;
        default = "local";
        local = {
          enable = true;
          model = "gemma-4-e2b";
        };
      };

      # koi's endpoint, as before. The llama-server this profile starts is
      # right there, but shellm cannot use it until it can be told to stop
      # the model thinking.
      programs.shellm = {
        enable = true;
        endpoint = "pitaya";
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
        ../shared/activations/gapplin.nix
        ./r-shibuya/corp.nix
        ../shared/programs/bare.nix
        ../shared/programs/logseq-view.nix
        ./r-shibuya/logseq-sync.nix
        ./r-shibuya/llama-server.nix
        ../shared/programs/mtg-minutes.nix
        ../shared/programs/browse.nix
        ../shared/programs/obs.nix
        ((import ../lib/taskfile-overrides.nix { inherit lib pkgs; }).forProfile "r-shibuya")
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
