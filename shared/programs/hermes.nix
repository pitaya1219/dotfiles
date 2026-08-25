{ config, pkgs, lib, ... }:

let
  cfg = config.programs.hermes;

  pitayaToken = pkgs.writeShellApplication {
    name = "hermes-pitaya-token";
    runtimeInputs = with pkgs; [ curl passage ];
    text = ''
      HERMES_PITAYA_PASSAGE_PREFIX="${cfg.pitaya.passagePrefix}"
      HERMES_PITAYA_TOKEN_URL="${cfg.pitaya.tokenUrl}"
      export HERMES_PITAYA_PASSAGE_PREFIX HERMES_PITAYA_TOKEN_URL
    '' + builtins.readFile ../../tools/hermes/pitaya-token.sh;
    meta = {
      description = "Mint a client-credentials bearer token for the homelab inference endpoint";
      mainProgram = "hermes-pitaya-token";
    };
  };

  # Each entry becomes both a named provider (which is what can carry a
  # credential) and a model alias of the same name (which is what `/model`
  # completes on).
  endpoints =
    lib.optionalAttrs cfg.local.enable {
      ${cfg.local.name} = {
        inherit (cfg.local) model;
        provider = {
          base_url = cfg.local.baseUrl;
          api_mode = "chat_completions";
          # llama-server started without --api-key takes any bearer, but the
          # OpenAI client underneath hermes will not send a request with no
          # key at all, so the field has to hold something.
          api_key = "no-auth-required";
        };
      };
    }
    // lib.optionalAttrs cfg.pitaya.enable {
      ${cfg.pitaya.name} = {
        inherit (cfg.pitaya) model;
        provider = {
          base_url = cfg.pitaya.baseUrl;
          api_mode = "chat_completions";
          key_cmd = lib.getExe pitayaToken;
          # koi serves this in router mode: asking for a preset that is not
          # the resident one swaps the loaded model first, which is a
          # multi-GB read before the first token comes back.
          request_timeout_seconds = 600;
        };
      };
    };

  defaultEndpoint = endpoints.${cfg.default} or null;
in
{
  options.programs.hermes = {
    enable = lib.mkEnableOption ''
      Hermes Agent, wired to the inference endpoints below.

      This owns only the endpoint half of config.yaml. Activation deep-merges
      into the file rather than replacing it, so everything `hermes config
      set` and the TUI's settings panes write stays where they put it
    '';

    default = lib.mkOption {
      type = lib.types.str;
      description = ''
        Which endpoint hermes starts on, named by its `name` below. The other
        one stays reachable in a running session with `/model <name>`, and for
        a single run with `hermes --model <name>`.
      '';
    };

    local = {
      enable = lib.mkEnableOption "an OpenAI-compatible server on this machine as an endpoint";

      name = lib.mkOption {
        type = lib.types.str;
        default = "local";
        description = "The name this endpoint answers to at the `/model` prompt.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        description = ''
          The model id the server reports on /v1/models. For llama-server that
          is its `--alias`, and the GGUF's own name when it was started
          without one.
        '';
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:11434/v1";
        description = "The endpoint's OpenAI-compatible base URL.";
      };
    };

    pitaya = {
      enable = lib.mkEnableOption "the homelab endpoint behind ai.pitaya.f5.si (koi) as an endpoint";

      name = lib.mkOption {
        type = lib.types.str;
        default = "pitaya";
        description = "The name this endpoint answers to at the `/model` prompt.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        example = "Gemma-4";
        description = ''
          One of koi's router-mode preset names — those are the model ids this
          endpoint lists. They are declared in homelab's
          infra/inventory/host_vars/koi/workload.yml.

          Pick a preset whose ctx_size is at least 65536. Hermes refuses a
          model reporting under 64,000 tokens of context outright, and koi has
          presets on both sides of that line.
        '';
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ai.pitaya.f5.si/v1";
        description = "The endpoint's OpenAI-compatible base URL.";
      };

      tokenUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://auth.pitaya.f5.si/oauth/v2/token";
        description = "The OAuth 2.0 token endpoint minting the bearer the llm proxy checks.";
      };

      passagePrefix = lib.mkOption {
        type = lib.types.str;
        example = "hermes/client/lepetitprince";
        description = ''
          The passage entry holding this profile's OAuth client, as a prefix:
          `<prefix>/id` and `<prefix>/secret`.

          One client per profile rather than one shared client. The store
          reaches every machine through Proton Pass, so a shared client would
          make every profile's traffic indistinguishable in the issuer's log,
          and revoking one machine would revoke all of them.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = endpoints != { };
        message = "programs.hermes needs an endpoint: set local.enable or pitaya.enable.";
      }
      {
        assertion = defaultEndpoint != null;
        message =
          ''programs.hermes.default is "${cfg.default}", which is not an enabled endpoint''
          + " (enabled: ${lib.concatStringsSep ", " (lib.attrNames endpoints)}).";
      }
    ];

    home.packages = lib.optional cfg.pitaya.enable pitayaToken;

    programs.hermes-agent.enable = true;

    services.hermes-agent = {
      # The gateway and the backend both stay off (their own defaults). This
      # is on for the activation alone — it is what writes config.yaml, and
      # the settings below never reach disk without it.
      enable = true;

      settings = {
        model = {
          default = if defaultEndpoint == null then "" else defaultEndpoint.model;
          provider = cfg.default;
        };

        # Named providers, not `provider: custom`: custom takes a base_url but
        # has nowhere to hang a key_cmd, and the homelab endpoint needs one
        # minted per request.
        providers = lib.mapAttrs (_: endpoint: endpoint.provider) endpoints;

        model_aliases = lib.mapAttrs (name: endpoint: {
          inherit (endpoint) model;
          provider = name;
        }) endpoints;
      };
    };
  };
}
