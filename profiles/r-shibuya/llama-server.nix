{ config, pkgs, lib, ... }:

let
  # QAT over the plain quant of the same tier: gemma-4-E2B-it-qat-UD-Q4_K_XL is
  # 2.62GB against gemma-4-E2B-it-UD-Q4_K_XL's 3.18GB, and quantization-aware
  # training is what the 4-bit weights were trained for rather than rounded
  # into — so it is the smaller file and the better one at once. Q2 is the only
  # tier below it that saves anything worth having (2.19GB) and the drop is not
  # worth 0.4GB.
  #
  # `-hf` pulls the file into LLAMA_CACHE on first start, so nothing here
  # copies multi-GB weights through the Nix store or an activation script.
  # First launch after a fresh checkout therefore serves nothing until the
  # download finishes; `tail -f` the log below to watch it.
  model = "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL";

  # The name /v1/models reports, and so the one programs.hermes.local.model has
  # to match. Pinned with --alias because the default is the GGUF's own
  # general.name, which changes with the quant.
  alias = "gemma-4-e2b";

  # Hermes refuses a model reporting under 64,000 tokens of context, so 65536
  # is the floor, not a preference. Gemma 4 E2B tops out at 131072, and its
  # sliding_window of 512 keeps the KV cache for a window this size small.
  contextSize = 65536;

  # Ollama's port. Nothing here speaks the Ollama protocol, but koi already
  # serves its llama-server on 11434 (homelab's llama_model_server_port), so
  # keeping it means the two endpoints differ only by host. shared/programs/
  # bare.nix does put ollama on this profile, so `ollama serve` would collide
  # — whichever binds first wins and the other exits.
  port = 11434;

  logDir = "${config.home.homeDirectory}/.local/share";
in
{
  home.packages = [ pkgs.llama-cpp ];

  launchd.agents.llama-server = {
    enable = true;
    config = {
      Label = "cpp.llama.server";
      ProgramArguments = [
        "${pkgs.llama-cpp}/bin/llama-server"
        "--host" "127.0.0.1"
        "--port" (toString port)
        "-hf" model
        "--alias" alias
        "--ctx-size" (toString contextSize)
        "--n-gpu-layers" "999"
        # unsloth ships chat-template fixes inside the GGUF, and their README
        # is explicit that llama.cpp only picks them up under --jinja. Tool
        # calling rides on the same template, which an agent needs.
        "--jinja"
      ];
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        LLAMA_CACHE = "${config.home.homeDirectory}/.cache/llama.cpp";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${logDir}/llama-server.log";
      StandardErrorPath = "${logDir}/llama-server-error.log";
    };
  };
}
