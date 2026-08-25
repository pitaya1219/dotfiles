{ config, pkgs, lib, ... }:

let
  cfg = config.programs.browse;

  browse = pkgs.writeShellApplication {
    name = "browse";
    runtimeInputs = with pkgs; [ fzf gh jq sqlite ];
    # osascript と open は macOS の system path から取る。runtimeInputs は PATH を
    # 置き換えるのではなく前置きするだけなので、両方そのまま解決できる。
    text = lib.optionalString (cfg.browser != null) ''
      BROWSE_BROWSER="''${BROWSE_BROWSER:-${cfg.browser}}"
      export BROWSE_BROWSER
    '' + builtins.readFile ../../tools/browse/browse.sh;
    meta = {
      description = "fzf picker over bookmarks, open browser tabs, history and the GitHub queue";
      mainProgram = "browse";
    };
  };
in
{
  options.programs.browse = {
    enable = lib.mkEnableOption
      "browse, an fzf picker over bookmarks, open tabs, history and the GitHub queue";

    browser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "Google Chrome";
      description = ''
        Application name, used both as the `open -a` target and as the
        AppleScript application whose tabs are listed and raised. null leaves
        the script's own default in place; spelling the default out here as
        well would give it two homes and only one of them would get updated.

        Only "Brave Browser" and "Google Chrome" additionally map to a history
        database; under any other name the history source is simply empty.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ browse ];
  };
}
