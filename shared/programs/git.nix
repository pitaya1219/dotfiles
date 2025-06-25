{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
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
  '';
}
