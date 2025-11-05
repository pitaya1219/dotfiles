{ config, pkgs, lib, ... }:

{
  home.activation.installHuggingFaceHub = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v huggingface-hub &> /dev/null; then
      echo "Installing huggingface_hub via pipx..."
      ${pkgs.pipx}/bin/pipx install -f huggingface_hub[cli]
    else
      echo "huggingface_hub is already installed"
    fi
  '';
}
