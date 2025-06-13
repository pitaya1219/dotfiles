{ config, pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  home.packages = with pkgs; [
    curl
    expect        # for using unbuffer
    sqlite
    vim
    git
    pipx          # for installing python made tool into global
    claude-code
  ];

  # Set PATH installing tools via pipx instead
  home.sessionVariables = {
    PATH = "$HOME/.local/bin:$PATH";
  };

  home.activation.installAiderChat = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v aider &> /dev/null; then
      ${pkgs.pipx}/bin/pipx install aider-chat
    fi
  '';

}
