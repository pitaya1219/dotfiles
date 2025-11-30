{ config, pkgs, lib, ... }:

let
  profileName = config.home.username;
  rcloneBin = "${pkgs.rclone}/bin/rclone";

  # Read script template and substitute variables
  scriptTemplate = builtins.readFile ../../../scripts/rclone-secure.sh.template;
  rcloneWrapper = builtins.replaceStrings
    ["__PROFILE_NAME__" "__RCLONE_BIN__"]
    [profileName rcloneBin]
    scriptTemplate;
in
{
  # Wrapper script with secrets from passage
  home.file.".local/bin/rclone-secure" = {
    text = rcloneWrapper;
    executable = true;
  };
}
