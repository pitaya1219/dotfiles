{ config, pkgs, lib, ... }:

let
  cfg = config.programs.shellm;

  shellm = pkgs.rustPlatform.buildRustPackage ({
    pname = "shellm";
    version = "0.1.0";

    src = pkgs.fetchFromGitea {
      domain = "git.pitaya.f5.si";
      owner = "pitaya1219";
      repo = "shellm";
      rev = "f6b01d34c5d9edf65e5a6611f1f6cd19ac77f109";
      hash = "sha256-+JilJx5z15wJqF3kcWght+pdlBihRigd+7zM0mXz6Sc=";
    };

    cargoHash = "sha256-xy0uOm2QMEQUSoposzsF6/Ar51XiaaP+oPO4QvjxRJQ=";

    meta = with lib; {
      description = "LLM-powered shell completion tool";
      homepage = "https://git.pitaya.f5.si/pitaya1219/shellm";
      license = licenses.mit;
      mainProgram = "shellm";
    };
  } // cfg.extraBuildAttrs);

  selected = if cfg.endpoint == "pitaya" then cfg.pitaya else cfg.local;

  # The client is read on the first call rather than at shell startup. passage
  # forks age once per entry, and shellm caches the token it mints against its
  # expiry, so a shell that never presses a keybinding should pay nothing --
  # and most shells never do.
  lazyCredentials = ''
    shellm() {
        if [[ -z "''${SHELLM_CLIENT_ID:-}" ]] && command -v passage &> /dev/null; then
            SHELLM_CLIENT_ID=$(passage show ${cfg.pitaya.passagePrefix}/id 2>/dev/null)
            SHELLM_CLIENT_SECRET=$(passage show ${cfg.pitaya.passagePrefix}/secret 2>/dev/null)
            export SHELLM_CLIENT_ID SHELLM_CLIENT_SECRET
        fi
        command shellm "$@"
    }
  '';
in
{
  options.programs.shellm = {
    enable = lib.mkEnableOption ''
      shellm, wired to the endpoint named by `endpoint` below.

      shellm reads its whole configuration from the environment, so this
      module owns both the package and the SHELLM_* variables. The
      keybindings are shellm's own, printed by `shellm init bash`
    '';

    endpoint = lib.mkOption {
      type = lib.types.enum [ "local" "pitaya" ];
      default = "local";
      description = ''
        Which endpoint below shellm talks to. One rather than two, unlike
        hermes: shellm reads the environment once at shell startup and has no
        `/model` to switch with at runtime.
      '';
    };

    local = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:11434";
        description = ''
          The endpoint's origin. shellm appends `/v1/chat/completions` itself,
          so this stops short of the `/v1` that hermes' baseUrl includes.
        '';
      };

      model = lib.mkOption {
        type = lib.types.str;
        example = "gemma-4-e2b";
        description = ''
          The model id the endpoint reports on /v1/models. For llama-server
          that is its `--alias`, and the GGUF's own name when it was started
          without one.
        '';
      };
    };

    pitaya = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://ai.pitaya.f5.si";
        description = "The homelab endpoint's origin.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "Qwen3.5-0.8B-UD-Q4_K_XL";
        description = ''
          One of koi's router-mode preset names. Defaulted rather than left to
          each profile because which model koi keeps resident is one fact
          about koi, not a per-machine choice.
        '';
      };

      tokenUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://auth.pitaya.f5.si/oauth/v2/token";
        description = ''
          The OAuth 2.0 token endpoint minting the bearer the llm proxy
          checks.
        '';
      };

      passagePrefix = lib.mkOption {
        type = lib.types.str;
        default = "shellm/client";
        description = ''
          The passage entry holding the OAuth client, as a prefix:
          `<prefix>/id` and `<prefix>/secret`.

          Unlike hermes this defaults to one client shared by every profile.
          Splitting it per profile is the better shape, for the same reason it
          is split there -- the issuer's log can then tell the machines apart,
          and one machine can be revoked on its own -- but it needs a client
          created in Zitadel per machine first.
        '';
      };
    };

    timeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = ''
        Seconds shellm waits for a completion. The keybindings block the
        prompt for this long in the worst case, which is what keeps it short.

        A local server needs more than the default: the first request after a
        cold start pays for prompt processing on an unwarmed KV cache, which
        on a laptop runs past five seconds even for a one-line prompt.
      '';
    };

    reasoningEffort = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "none" "low" "medium" "high" ]);
      default = null;
      description = ''
        Sent as the request's `reasoning_effort`, or left out of the request
        entirely when null.

        Set this to "none" against a model that reasons by default, such as
        Gemma 4: shellm reads only `message.content`, so the whole 128-token
        budget goes into `message.reasoning_content` and every answer comes
        back empty.

        Leave it null against a model that does not reason, so that an
        endpoint rejecting the unknown key is never sent it.
      '';
    };

    logPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.cacheHome}/shellm.log";
      description = ''
        Where the keybindings send stderr; `/dev/null` discards it.

        They cannot show it: readline owns the line while they run, so an
        error printed there would corrupt the display. shellm's own default is
        to discard it, which leaves a `::` that did nothing indistinguishable
        from one that could not reach the endpoint -- this is the caller
        deciding to keep it instead.

        Nothing rotates the file, and a keybinding against an endpoint that is
        down writes a line per keypress, so it belongs somewhere disposable.
      '';
    };

    extraBuildAttrs = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Merged into the package's derivation arguments, for a profile that
        cannot build it on the stock ones.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ shellm ];

    programs.bash.sessionVariables = lib.filterAttrs (_: v: v != null) {
      SHELLM_URL = selected.url;
      SHELLM_MODEL = selected.model;
      SHELLM_TIMEOUT = toString cfg.timeout;
      SHELLM_LOG = cfg.logPath;
      SHELLM_REASONING_EFFORT = cfg.reasoningEffort;
      SHELLM_AUTH_TYPE = if cfg.endpoint == "pitaya" then "oauth2" else "none";
      SHELLM_TOKEN_URL = if cfg.endpoint == "pitaya" then cfg.pitaya.tokenUrl else null;
    };

    # initExtra rather than bashrcExtra: home-manager emits the latter above
    # its `[[ $- == *i* ]] || return`, so everything here would also run for
    # `ssh host cmd`, where readline does not exist and the keybindings are
    # dead weight by construction.
    programs.bash.initExtra =
      lib.optionalString (cfg.endpoint == "pitaya") lazyCredentials
      + ''
        eval "$(${lib.getExe shellm} init bash)"
      '';
  };
}
