{ ... }:

{
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    stdlib = ''
      # Use bash for nix shell to prevent sh/dash errors with bash-specific commands
      export NIX_SHELL_SHELL="${BASH:-bash}"
    '';
  };
}
