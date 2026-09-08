{ config, pkgs, lib, ... }:

let
  # Two llama-servers because one model cannot do both jobs. Editor completion
  # goes through llama-server's /infill, which needs the GGUF to declare
  # fim_pre / fim_suf / fim_mid token ids; gemma-4-E2B-it is a general chat
  # model and carries none, so /infill answers 501 "Infill is not supported by
  # this model". Nor can this 16GB machine hold both at once, so llama-use
  # below unloads one agent before loading the other, and only the chat one
  # comes up at login -- it is what hermes, shellm and llama.vim's instruction
  # feature talk to.
  chat = {
    label = "cpp.llama.server";
    logName = "llama-server";

    # Ollama's port. Nothing here speaks the Ollama protocol, but koi already
    # serves its llama-server on 11434 (homelab's llama_model_server_port), so
    # keeping it means the two endpoints differ only by host. shared/programs/
    # bare.nix does put ollama on this profile, so `ollama serve` would collide
    # — whichever binds first wins and the other exits.
    port = 11434;

    args = [
      # QAT over the plain quant of the same tier: gemma-4-E2B-it-qat-UD-Q4_K_XL
      # is 2.62GB against gemma-4-E2B-it-UD-Q4_K_XL's 3.18GB, and
      # quantization-aware training is what the 4-bit weights were trained for
      # rather than rounded into — so it is the smaller file and the better one
      # at once. Q2 is the only tier below it that saves anything worth having
      # (2.19GB) and the drop is not worth 0.4GB.
      "-hf" "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL"

      # The name /v1/models reports, and so the one programs.hermes.local.model
      # has to match. Pinned because the default is the GGUF's own general.name,
      # which changes with the quant.
      "--alias" "gemma-4-e2b"

      # Hermes refuses a model reporting under 64,000 tokens of context, so
      # 65536 is the floor, not a preference. Gemma 4 E2B tops out at 131072,
      # and its sliding_window of 512 keeps the KV cache for a window this size
      # small.
      "--ctx-size" "65536"

      # unsloth ships chat-template fixes inside the GGUF, and their README is
      # explicit that llama.cpp only picks them up under --jinja. Tool calling
      # rides on the same template, which an agent needs.
      "--jinja"
    ];
  };

  fim = {
    label = "cpp.llama.server.fim";
    logName = "llama-fim-server";

    # llama.vim's own default endpoint, and what the preset below picks.
    port = 8012;

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

  # `-hf` pulls weights into LLAMA_CACHE on first start, so nothing here copies
  # multi-GB files through the Nix store or an activation script. A first run
  # therefore serves nothing until the download finishes; `tail -f` the log.
  mkAgent = { label, logName, port, args, runAtLoad, keepAlive }: {
    enable = true;
    config = {
      Label = label;
      ProgramArguments = [
        "${pkgs.llama-cpp}/bin/llama-server"
        "--host" "127.0.0.1"
        "--port" (toString port)
        "--n-gpu-layers" "999"
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
      CHAT_PORT="${toString chat.port}"
      FIM_LABEL="${fim.label}"
      FIM_PORT="${toString fim.port}"
      export CHAT_LABEL CHAT_PORT FIM_LABEL FIM_PORT
    '' + builtins.readFile ../../tools/llama-use/llama-use.sh;
    meta = {
      description = "Load exactly one of the local llama-servers and wait for it to answer";
      mainProgram = "llama-use";
    };
  };
in
{
  home.packages = [ pkgs.llama-cpp llama-use ];

  launchd.agents.llama-server = mkAgent (chat // {
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
