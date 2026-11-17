{ config, lib, pkgs, ... }:

let
  cfg = config.programs.pi;
  mergedConfig = import ../../lib/merged-config.nix { inherit config lib pkgs; };
  agentDir = "${config.home.homeDirectory}/.pi/agent";
  json = name: value: pkgs.writeText name (builtins.toJSON value);

  pitayaToken = pkgs.writeShellApplication {
    name = "pi-pitaya-token";
    runtimeInputs = with pkgs; [ curl jq passage coreutils ];
    text = ''
      PI_PITAYA_PASSAGE_PREFIX="${cfg.pitaya.passagePrefix}"
      PI_PITAYA_TOKEN_URL="${cfg.pitaya.tokenUrl}"
      export PI_PITAYA_PASSAGE_PREFIX PI_PITAYA_TOKEN_URL
    '' + builtins.readFile ../../tools/pi/pitaya-token.sh;
    meta = {
      description = "Print a cached bearer token for the homelab inference endpoint";
      mainProgram = "pi-pitaya-token";
    };
  };

  free = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };

  providers =
    lib.optionalAttrs cfg.local.enable {
      local = lib.recursiveUpdate {
        name = "Local";
        inherit (cfg.local) baseUrl;
        api = "openai-completions";
        # No local server here checks a key, but pi lists a model only once it
        # can resolve one.
        apiKey = "no-auth-required";
        models = [ (lib.recursiveUpdate {
          id = cfg.local.model;
          inherit (cfg.local) contextWindow;
          cost = free;
        } cfg.local.extraModel) ];
      } cfg.local.extraProvider;
    }
    // lib.optionalAttrs cfg.pitaya.enable {
      pitaya = {
        name = "pitaya";
        inherit (cfg.pitaya) baseUrl;
        api = "openai-completions";
        apiKey = "!${lib.getExe pitayaToken}";
        models = [{
          id = cfg.pitaya.model;
          inherit (cfg.pitaya) contextWindow;
          cost = free;
        }];
      };
    };

  defaultProvider = providers.${cfg.default} or null;
in
{
  options.programs.pi = {
    enable = lib.mkEnableOption ''
      the pi coding agent, wired to the endpoints below.

      models.json and settings.json are merged into rather than linked, so
      what pi writes there itself (/model, /settings) survives a switch
    '';

    default = lib.mkOption {
      type = lib.types.enum [ "local" "pitaya" ];
      description = ''
        The provider pi starts on. The other stays reachable with `/model`.
      '';
    };

    local = {
      enable = lib.mkEnableOption "an OpenAI-compatible server reachable without auth as a provider";

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:11434/v1";
      };

      model = lib.mkOption {
        type = lib.types.str;
        example = "gemma-4-e2b";
        description = "The model id the server reports on /v1/models.";
      };

      contextWindow = lib.mkOption {
        type = lib.types.ints.positive;
        description = ''
          The context the server was started with. pi compacts against this,
          and the server does not report it.
        '';
      };

      extraProvider = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = ''
          Merged over the provider entry in models.json, for the `compat`
          fields pi cannot auto-detect from a localhost URL.
        '';
      };

      extraModel = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = ''
          Merged over the model entry in models.json: `reasoning`,
          `thinkingLevelMap`, `samplingParams` and the like.
        '';
      };
    };

    pitaya = {
      enable = lib.mkEnableOption "koi's endpoint at ai.pitaya.f5.si as a provider";

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ai.pitaya.f5.si/v1";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "Gemma-4";
        description = ''
          One of koi's router-mode preset names, declared in homelab's
          infra/inventory/host_vars/koi/workload.yml.
        '';
      };

      contextWindow = lib.mkOption {
        type = lib.types.ints.positive;
        default = 65536;
        description = "The ctx_size of the `model` preset on koi.";
      };

      tokenUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://auth.pitaya.f5.si/oauth/v2/token";
      };

      passagePrefix = lib.mkOption {
        type = lib.types.str;
        default = "pi/oauth";
        description = ''
          The passage entry holding pi's OAuth client, as a prefix:
          `<prefix>/client-id` and `<prefix>/client-secret`.

          One client for pi on every profile, not one per machine: the
          issuer's log tells pi apart from hermes and shellm, which is all it
          needs to. Revoking it cuts every machine at once.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = defaultProvider != null;
        message = ''programs.pi.default is "${cfg.default}", which is not an enabled provider.'';
      }
    ];

    home.packages = [ pkgs.pi-coding-agent ];

    home.activation.installPiModels = mergedConfig.activation {
      format = "json";
      target = "${agentDir}/models.json";
      generated = "${json "pi-models.json" { inherit providers; }}";
    };

    home.activation.installPiSettings = mergedConfig.activation {
      format = "json";
      target = "${agentDir}/settings.json";
      generated = "${json "pi-settings.json" ({
        defaultProvider = cfg.default;
        defaultModel = if defaultProvider == null then "" else (builtins.head defaultProvider.models).id;
      } // lib.optionalAttrs (cfg.default == "local" && cfg.local.extraModel.reasoning or false) {
        # A small local model spends a minute a turn thinking; raise it per
        # session with shift+tab.
        defaultThinkingLevel = "off";
      })}";
    };
  };
}
