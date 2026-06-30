{ lib, pkgs, ... }:

{
  forProfile = profileName:
    let
      # Base Taskfile configuration as Nix attrset
      baseTaskfile = import ../shared/programs/taskfile-default.nix;
      
      # Profile-specific Taskfile partial path
      profilePartialPath = ../profiles/${profileName}/taskfile-part.nix;
      
      # Import profile partial if exists
      profileTaskfile = if builtins.pathExists profilePartialPath then
        import profilePartialPath
      else
        {};
      
      # Merge includes: base includes + profile includes
      mergedIncludes = baseTaskfile.includes // (profileTaskfile.includes or {});
      
      # Use base tasks (profile doesn't override tasks)
      mergedTasks = baseTaskfile.tasks;
      
      # Generate includes section as YAML lines
      includesLines = builtins.map (name:
        let config = mergedIncludes.${name};
        in
        "  ${name}:\n" +
        "    taskfile: ${config.taskfile}\n" +
        "    dir: ${config.dir}"
      ) (builtins.attrNames mergedIncludes);
      
      # Generate tasks section as YAML lines
      tasksLines = builtins.map (name:
        let task = mergedTasks.${name};
        in
        "  ${name}:\n" +
        "    cmds:\n" +
        (lib.concatStringsSep "\n" (builtins.map (cmd: "      - ${cmd}") task.cmds)) + "\n" +
        "    silent: ${if task.silent then "true" else "false"}"
      ) (builtins.attrNames mergedTasks);
      
      # Generate final Taskfile.yml content
      yamlContent = ''
version: ${builtins.toString baseTaskfile.version}

includes:
${lib.concatStringsSep "\n" includesLines}

tasks:
${lib.concatStringsSep "\n" tasksLines}
'';
    in
    {
      home.file = {
        "Taskfile.yml" = {
          source = pkgs.writeText "Taskfile.yml" yamlContent;
        };
      };
    };
}
