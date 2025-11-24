{ nixpkgs, home-manager, overlays }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-linux";
      overlays = [ overlays.neovim-nightly ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        imports = [
          ../shared/programs/bare.nix
          ../shared/programs/bash.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ../shared/activations/huggingface_hub.nix
          ./droid/ssh/config.nix
          ./droid/rclone/config.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "droid")
          ((import ../lib/neovim-extension.nix { inherit lib; }).forProfile "droid")
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "droid")
          (import ../shared/programs/unfree.nix { additionalPackages = []; })
        ];

        home = {
          username = "droid";
          homeDirectory = "/home/droid";
          stateVersion = "23.11";
          packages = with pkgs; [
            jq
            rclone
            android-tools
            cloudflared
            llama-cpp
          ];
        };
      })
    ];
  };
}
