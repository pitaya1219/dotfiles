{ config, pkgs, lib, ... }:

{
  options.dotfiles.agent.dailyReport = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    description = "Per-profile config written to ~/.agent/daily-report.json. Set sources to enable/disable data collection per machine.";
  };

  options.dotfiles.agent.logseq = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    description = "Logseq HTTP API connection config written to ~/.agent/logseq.json. url and token each accept a string, { file } or { command }.";
  };

  options.dotfiles.agent.asana = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    description = "Asana target config written to ~/.agent/asana.json ({ projectGid, todoSectionGid }). Consumed by the asana-create-task skill; when unset the skill runs an interactive setup wizard.";
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

    # Generate ~/.agent/logseq.json when config is provided
    home.file.".agent/logseq.json" = lib.mkIf (config.dotfiles.agent.logseq != {}) {
      text = builtins.toJSON config.dotfiles.agent.logseq;
    };

    # Generate ~/.agent/asana.json when config is provided
    home.file.".agent/asana.json" = lib.mkIf (config.dotfiles.agent.asana != {}) {
      text = builtins.toJSON config.dotfiles.agent.asana;
    };
  };
}
