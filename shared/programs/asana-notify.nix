{ config, pkgs, lib, ... }:

let
  cfg = config.programs.asana-notify;

  # herdr is the delivery path, not an optional extra: the tool has no other
  # way to reach the user. Pinning the store path rather than leaning on PATH
  # keeps a launchd-started run working, where the profile PATH is whatever
  # launchd was given at login.
  herdr = config.programs.herdr.package;

  asana-notify = pkgs.stdenvNoCC.mkDerivation {
    pname = "asana-notify";
    version = "0.1.0";

    src = lib.cleanSourceWith {
      src = ../../tools/asana-notify;
      filter = path: type:
        !(type == "directory" && baseNameOf path == "__pycache__")
        && !(lib.hasSuffix ".pyc" path);
    };

    nativeBuildInputs = [ pkgs.makeBinaryWrapper pkgs.python3 ];

    dontConfigure = true;
    dontBuild = true;

    # Same layout as mtg-minutes: the executable adds its own ../lib to
    # sys.path, so the shared module goes to $out/lib rather than onto
    # PYTHONPATH, which would follow herdr into every process it spawns.
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib
      cp lib/*.py $out/lib/
      cp bin/asana-notify $out/bin/
      patchShebangs $out/bin/asana-notify
      # makeBinaryWrapper, not makeWrapper: the shell variant forks a bash to
      # set one variable and exec, on every one of the ~288 daily wakes.
      wrapProgram $out/bin/asana-notify \
        --prefix PATH : ${lib.makeBinPath [ herdr ]}

      runHook postInstall
    '';

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      ${pkgs.python3}/bin/python3 tests/test_asananotify.py
      runHook postCheck
    '';

    meta = with lib; {
      description = "Poll Asana and raise herdr toasts for assignments, due dates and comments";
      platforms = platforms.all;
      mainProgram = "asana-notify";
    };
  };
in
{
  options.programs.asana-notify = {
    enable = lib.mkEnableOption "asana-notify (Asana polling notifier over herdr toasts)";

    agent.enable = lib.mkEnableOption ''
      run asana-notify from launchd on a fixed interval. Off by default so
      installing the command does not by itself start polling Asana
    '';
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ asana-notify ];

    # Both of these fail at runtime rather than at switch, and the runtime is a
    # launchd agent whose only symptom is a log nobody is watching.
    assertions = [
      {
        assertion = config.programs.herdr.enable;
        message = "programs.asana-notify needs programs.herdr: notifications are delivered as herdr toasts.";
      }
      {
        assertion = config.dotfiles.agent.asana ? token;
        message = "programs.asana-notify reads its token from ~/.agent/asana.json: set dotfiles.agent.asana.token to a string, { file = ...; } or { command = ...; }.";
      }
    ];

    # StartInterval with a one-shot run rather than KeepAlive with an internal
    # loop (`asana-notify --watch` does exist, for a terminal): this notifier
    # was written to get an always-open Asana tab out of memory, so it would be
    # perverse to replace it with a process that is always resident.
    launchd.agents.asana-notify = lib.mkIf cfg.agent.enable {
      enable = true;
      config = {
        Label = "si.f5.pitaya.asana-notify";
        ProgramArguments = [ "${asana-notify}/bin/asana-notify" ];
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          # The token is fetched by running a command (passage, typically), and
          # launchd hands an agent only /usr/bin:/bin:/usr/sbin:/sbin — where
          # nothing installed through home.packages is visible. Without this the
          # agent resolves an empty token and exits 2 every interval forever.
          # Same list, and same reason, as profiles/r-shibuya/logseq-sync.nix.
          PATH = lib.concatStringsSep ":" [
            "${config.home.homeDirectory}/.nix-profile/bin"
            "/etc/profiles/per-user/${config.home.username}/bin"
            "/run/current-system/sw/bin"
            "/usr/local/bin"
            "/usr/bin"
            "/bin"
            "/usr/sbin"
            "/sbin"
          ];
        };
        # Bounded by Asana's rate limit rather than by local memory: each run is
        # a fresh process that exits, so the cost between polls is zero.
        StartInterval = 300;
        # The first run after a switch only records a baseline, so it costs one
        # request and cannot spam.
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/.local/share/asana-notify.log";
        StandardErrorPath = "${config.home.homeDirectory}/.local/share/asana-notify-error.log";
      };
    };
  };
}
