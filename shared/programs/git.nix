{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    extraConfig = {
      credential = {
        helper = "${config.home.homeDirectory}/.config/git/git-credential-protonpass.sh";
      };
    };
  };

  home.file.".config/git/ignore".text = ''
    # OS generated files
    .DS_Store
    .DS_Store?
    *.sw*
    .env
    .env.local
    .env.development.local
    .env.test.local
    .env.production.local
    # Python
    __pycache__/
    venv/
    # Aider
    .aider/
    .aider.*
  '';

  # Install git credential helper script
  home.file.".config/git/git-credential-protonpass.sh" = {
    source = ./git/git-credential-protonpass.sh;
    executable = true;
  };
}
