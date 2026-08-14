{ config, pkgs, lib, ... }:

let
  skillsDir = ./agent/skills;

  # One skill is one directory directly under skills/; loose files are not skills.
  availableSkills = lib.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));

  skills = config.dotfiles.agent.skills;

  # A null include means every skill is a candidate. exclude runs after include,
  # so a name listed in both ends up not installed.
  selectedSkills = lib.subtractLists skills.exclude
    (lib.filter (name: skills.include == null || lib.elem name skills.include) availableSkills);

  # A name that matches nothing would silently mean "that skill is missing", which
  # is exactly how a typo or a rename hides, so fail the switch instead.
  unknownSkills = lib.subtractLists availableSkills
    (lib.optionals (skills.include != null) skills.include ++ skills.exclude);

  skillFiles = lib.listToAttrs (map (name: lib.nameValuePair ".agent/skills/${name}" {
    source = skillsDir + "/${name}";
    recursive = true;
  }) selectedSkills);
in
{
  options.dotfiles.agent.skills.include = lib.mkOption {
    type = lib.types.nullOr (lib.types.listOf lib.types.str);
    default = null;
    example = [ "daily-report" "session-save" ];
    description = "Whitelist of skill directory names under shared/programs/agent/skills to install into ~/.agent/skills. null (the default) selects every skill. exclude is applied afterwards either way.";
  };

  options.dotfiles.agent.skills.exclude = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    example = [ "my-review" ];
    description = "Blacklist of skill directory names to keep out of ~/.agent/skills. Applied after include, so a name listed in both is excluded.";
  };

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
    assertions = [
      {
        assertion = unknownSkills == [];
        message = "dotfiles.agent.skills: unknown skill name(s): ${lib.concatStringsSep ", " unknownSkills}. Available: ${lib.concatStringsSep ", " availableSkills}.";
      }
    ];

    # Install agent directories (shared between all AI tools).
    # Skills are linked one directory at a time rather than as a single
    # ~/.agent/skills entry: managing that directory itself would sweep up the
    # skills dropped in there by hand outside of Nix.
    home.file = skillFiles // {
      ".agent/commands" = {
        source = ./agent/commands;
        recursive = true;
      };

      ".agent/secret_guard" = {
        source = ./agent/secret_guard;
        recursive = true;
      };

      # Cross-agent, cross-repository conventions. Each agent reaches this file
      # its own way (see claude-code.nix, vibe.nix, opencode.nix); this is the
      # only copy.
      ".agent/conventions.md".source = ./agent/conventions.md;

      # Generate ~/.agent/daily-report.json when config is provided
      ".agent/daily-report.json" = lib.mkIf (config.dotfiles.agent.dailyReport != {}) {
        text = builtins.toJSON config.dotfiles.agent.dailyReport;
      };

      # Generate ~/.agent/logseq.json when config is provided
      ".agent/logseq.json" = lib.mkIf (config.dotfiles.agent.logseq != {}) {
        text = builtins.toJSON config.dotfiles.agent.logseq;
      };

      # Generate ~/.agent/asana.json when config is provided
      ".agent/asana.json" = lib.mkIf (config.dotfiles.agent.asana != {}) {
        text = builtins.toJSON config.dotfiles.agent.asana;
      };
    };
  };
}
