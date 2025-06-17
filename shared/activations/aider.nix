{ config, pkgs, lib, ... }:

{
  home.activation.installAiderChat = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v aider &> /dev/null; then
      echo "Installing aider-chat via pipx..."
      ${pkgs.pipx}/bin/pipx install aider-chat
    else
      echo "aider-chat is already installed"
    fi
  '';
}
