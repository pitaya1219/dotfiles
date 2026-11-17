{ config, pkgs, lib, ... }:

let
  # Two local servers because one model cannot do both jobs. Editor completion
  # goes through llama-server's /infill, which needs the GGUF to declare
  # fim_pre / fim_suf / fim_mid token ids; gemma-4-E4B-it is a general chat
  # model and carries none, so /infill answers 501 "Infill is not supported by
  # this model". Nor can this 16GB machine hold both at once, so llama-use
  # below unloads one agent before loading the other, and only the chat one
  # comes up at login -- it is what pi, shellm and llama.vim's instruction
  # feature talk to.
  litert-lm = pkgs.callPackage ./litert-lm.nix { };

  # The model id clients send and /v1/models reports: litert-lm serves its
  # registry under the names models were imported as.
  chatModel = "gemma-4-e4b-gpu";

  litertConfig = pkgs.writeText "litert-lm-config.json" (builtins.toJSON {
    models.${chatModel} = {
      # Only with a -gpu file like the one below. The plain .litertlm runs on
      # gpu too, but duplicates and drops tokens there ("TheThe", `herdr`
      # sent as `dr`): E2B's botched 4 of 6 tool calls that cpu got right,
      # its -gpu file 0. The -gpu files ship no drafter, so
      # speculative_decoding has nothing to act on.
      backend = "gpu";

      # `litert-lm describe` reports 8192 for this file, but serve allocates
      # and accepts whatever this says; 32k prompts were checked, and E4B
      # still followed instructions there where E2B stopped past 16k. The KV cache
      # is allocated for the whole window when the engine loads.
      max_num_tokens = 32768;
    };
  });

  # `serve` only answers for models already in ~/.litert-lm/models, so the
  # first start pulls the weights before it listens -- like `-hf` below,
  # nothing multi-GB passes through the Nix store. Until the download ends
  # the port is closed; `tail -f` the log.
  litert-serve = pkgs.writeShellApplication {
    name = "litert-lm-serve";
    runtimeInputs = [ litert-lm ];
    text = ''
      if [ ! -f "$HOME/.litert-lm/models/${chatModel}/model.litertlm" ]; then
        litert-lm import \
          --from-huggingface-repo litert-community/gemma-4-E4B-it-litert-lm \
          gemma-4-E4B-it-gpu.litertlm ${chatModel}
      fi
      exec litert-lm serve --config ${litertConfig} "$@"
    '';
  };

  chat = {
    label = "dev.litert-lm.server";
    logName = "litert-lm-server";

    # Ollama's port. Nothing here speaks the Ollama protocol, but koi already
    # serves its llama-server on 11434 (homelab's llama_model_server_port), so
    # keeping it means the two endpoints differ only by host. shared/programs/
    # bare.nix does put ollama on this profile, so `ollama serve` would collide
    # — whichever binds first wins and the other exits.
    port = 11434;

    # litert-lm serve has no /health.
    readyPath = "/v1/models";

    program = [ "${litert-serve}/bin/litert-lm-serve" ];
    args = [ ];
  };

  fim = {
    label = "cpp.llama.server.fim";
    logName = "llama-fim-server";

    # llama.vim's own default endpoint, and what the preset below picks.
    port = 8012;

    readyPath = "/health";

    program = [ "${pkgs.llama-cpp}/bin/llama-server" "--n-gpu-layers" "999" ];

    args = [
      # llama.cpp's preset for editor completion. It pulls
      # ggml-org/Qwen2.5-Coder-3B-Q8_0-GGUF (3.29GB, base rather than instruct
      # — the FIM tokens are what matter, not chat ability) and sets
      # --batch-size and --ubatch-size 1024, --ctx-size 0 (the model's own 32k)
      # and --cache-reuse 256, so an unchanged prefix is not reprocessed on
      # every keystroke.
      #
      # A replacement has to be a model llama.cpp can recognise FIM tokens in:
      # src/llama-vocab.cpp matches the Qwen, Granite, DeepSeek, CodeLlama,
      # GLM-4.5 and Falcon spellings and nothing else, so one using Mistral's
      # [PREFIX]/[SUFFIX]/[MIDDLE] answers 501 the same way gemma does.
      "--fim-qwen-3b-default"
    ];
  };

  logDir = "${config.home.homeDirectory}/.local/share";

  readyUrl = server: "http://127.0.0.1:${toString server.port}${server.readyPath}";

  # `-hf` pulls weights into LLAMA_CACHE on first start, so nothing here copies
  # multi-GB files through the Nix store or an activation script. A first run
  # therefore serves nothing until the download finishes; `tail -f` the log.
  mkAgent = { label, logName, port, program, args, runAtLoad, keepAlive, ... }: {
    enable = true;
    config = {
      Label = label;
      ProgramArguments = program ++ [
        "--host" "127.0.0.1"
        "--port" (toString port)
      ] ++ args;
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        LLAMA_CACHE = "${config.home.homeDirectory}/.cache/llama.cpp";
      };
      RunAtLoad = runAtLoad;
      KeepAlive = keepAlive;
      StandardOutPath = "${logDir}/${logName}.log";
      StandardErrorPath = "${logDir}/${logName}-error.log";
    };
  };

  llama-use = pkgs.writeShellApplication {
    name = "llama-use";
    runtimeInputs = with pkgs; [ curl gnugrep coreutils ];
    # launchctl comes from the macOS system path, which runtimeInputs prepends
    # to rather than replaces.
    text = ''
      CHAT_LABEL="${chat.label}"
      CHAT_READY_URL="${readyUrl chat}"
      FIM_LABEL="${fim.label}"
      FIM_READY_URL="${readyUrl fim}"
      export CHAT_LABEL CHAT_READY_URL FIM_LABEL FIM_READY_URL
    '' + builtins.readFile ../../tools/llama-use/llama-use.sh;
    meta = {
      description = "Load exactly one of the local model servers and wait for it to answer";
      mainProgram = "llama-use";
    };
  };
in
{
  home.packages = [ pkgs.llama-cpp litert-lm llama-use ];

  launchd.agents.litert-lm-server = mkAgent (chat // {
    runAtLoad = true;
    keepAlive = true;
  });

  # Neither flag is set, so this one comes up only when llama-use asks for it.
  # KeepAlive would defeat that by starting it at login alongside the other.
  launchd.agents.llama-fim-server = mkAgent (fim // {
    runAtLoad = false;
    keepAlive = false;
  });
}
