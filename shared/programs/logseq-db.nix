{ config, pkgs, lib, ... }:

# logseq-db: the agent tools' access to the Logseq DB graph through the
# Logseq CLI (tools/logseq-db). It writes ~/.agent/logseq.json, which
# logseq-write, session-save, daily-report and mtg-minutes read.

let
  cfg = config.programs.logseq-db;

  logseq-db = pkgs.stdenvNoCC.mkDerivation {
    pname = "logseq-db";
    version = "0.1.0";

    src = lib.cleanSourceWith {
      src = ../../tools/logseq-db;
      filter = path: type:
        !(type == "directory" && baseNameOf path == "__pycache__")
        && !(lib.hasSuffix ".pyc" path);
    };

    nativeBuildInputs = [ pkgs.python3 ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/lib
      cp lib/*.py $out/lib/
      cp bin/logseq-db $out/bin/
      patchShebangs $out/bin/logseq-db
      runHook postInstall
    '';

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      ${pkgs.python3}/bin/python3 tests/test_logseqdb.py
      runHook postCheck
    '';

    meta = {
      description = "Logseq DB graph access for the agent tools, over the Logseq CLI";
      mainProgram = "logseq-db";
    };
  };
in
{
  options.programs.logseq-db = {
    enable = lib.mkEnableOption "logseq-db (agent access to the Logseq DB graph)";

    graph = lib.mkOption {
      type = lib.types.str;
      default = "ryu";
      description = "Graph name, as `logseq graph list` shows it.";
    };

    desktop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The Logseq DB desktop app runs on this machine. Writes are then left for
        the app to sync, and the CLI never signs in: the app owns
        ~/logseq/auth.json.
      '';
    };

    cliPackage = lib.mkOption {
      type = lib.types.package;
      description = "Package providing bin/logseq-cli.";
    };

    e2eePassword = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { command = "passage show logseq/graphs/${cfg.graph}/e2ee-password"; };
      description = "CLI-only: the graph's E2EE password, as { command } or { file }.";
    };

    sync = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        wsUrl = "wss://logseq-sync.pitaya.f5.si/sync/%s";
        httpBase = "https://logseq-sync.pitaya.f5.si";
        authorizeEndpoint = "https://auth.pitaya.f5.si/oauth/v2/authorize";
        tokenEndpoint = "https://auth.pitaya.f5.si/oauth/v2/token";
        clientId = { command = "passage show homelab/zitadel/apps/logseq/client/id"; };
        scope = "openid email profile offline_access";
      };
      description = "CLI-only: sync server and Zitadel sign-in (homelab apps/knowledge/logseq/clients/docs/configuration.md).";
    };
  };

  config = lib.mkIf cfg.enable {
    # w3m completes Zitadel's server-rendered login, TOTP included, from a
    # terminal on this machine, so `task logseq:login` needs no forwarding.
    home.packages = [ logseq-db cfg.cliPackage ] ++ lib.optional (!cfg.desktop) pkgs.w3m;

    dotfiles.agent.logseq = {
      inherit (cfg) graph desktop;
      cli = lib.getExe' cfg.cliPackage "logseq-cli";
    } // lib.optionalAttrs (!cfg.desktop) {
      inherit (cfg) e2eePassword sync;
    };
  };
}
