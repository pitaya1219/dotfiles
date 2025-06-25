{ ... }:

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
    
    # Basic environment
    sessionVariables = baseEnv;
    
    # Common shell options
    shellOptions = baseShellOpt;
    
    # Base initialization
    bashrcExtra = baseBashrc;

    shellAliases = baseAliases;
  };
}
