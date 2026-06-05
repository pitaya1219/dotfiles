{ config, pkgs, lib, ... }:

{
  options.dotfiles.agent.dailyReport = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    description = "Per-profile config written to ~/.agent/daily-report.json. Set sources to enable/disable data collection per machine.";
  };

  config = {
    # Install agent directories (shared between all AI tools)
    home.file.".agent/commands" = {
      source = ./agent/commands;
      recursive = true;
    };

    home.file.".agent/skills" = {
      source = ./agent/skills;
      recursive = true;
    };

    # Generate ~/.agent/daily-report.json when config is provided
    home.file.".agent/daily-report.json" = lib.mkIf (config.dotfiles.agent.dailyReport != {}) {
      text = builtins.toJSON config.dotfiles.agent.dailyReport;
    };
  };
}
