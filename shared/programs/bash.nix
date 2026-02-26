{ lib, ... }:

let
  baseAliases = import ./bash/aliases.nix;
  baseShellOpt = import ./bash/shell_options.nix;
  baseBashrc = import ./bash/bashrc.nix;
  baseEnv = import ./bash/env.nix;
in
{
  programs.bash = {
    enable = true;
    
    # History configuration
    historySize = 10000;
    historyFileSize = 20000;
    historyControl = [ "ignoredups" ];
    
    # Basic environment with default value for SHELLM_MODEL
    sessionVariables = baseEnv // {
      SHELLM_MODEL = lib.mkDefault "qwen2.5-coder-1.5b-Q4_K_M";
    };
    
    # Common shell options
    shellOptions = baseShellOpt;
    
    # Base initialization
    bashrcExtra = baseBashrc;

    shellAliases = baseAliases;
  };
}
