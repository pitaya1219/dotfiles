{ nixpkgs, home-manager, overlays }:

{
  mkHomeConfiguration = home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-darwin";
      overlays = [ overlays.neovim-nightly ];
    };
    modules = [
      ({ config, pkgs, lib, ... }: {
        imports = [
          ../shared/activations/aider.nix
          ../shared/programs/bare.nix
          ../shared/programs/bash.nix
          ../shared/programs/git.nix
          ../shared/programs/neovim.nix
          ../shared/programs/tmux.nix
          ../shared/programs/starship.nix
          ../shared/programs/readline.nix
          ((import ../lib/bash-extension.nix { inherit lib; }).forProfile "r-shibuya")
          ((import ../lib/neovim-extension.nix { inherit lib; }).forProfile "r-shibuya")
          ((import ../lib/starship-extension.nix { inherit lib pkgs; }).forProfile "r-shibuya")
          (import ../shared/programs/unfree.nix { additionalPackages = [ "copilot.vim" ]; })
        ];

        home = {
          username = "r-shibuya";
          homeDirectory = "/Users/r-shibuya";
          stateVersion = "23.11";
          packages = with pkgs; [
            jq
            docker
            docker-credential-helpers
          ];
          file.".config/tmux/override.conf".source = ./r-shibuya/tmux/override.conf;
        };
      })
    ];
  };
}
