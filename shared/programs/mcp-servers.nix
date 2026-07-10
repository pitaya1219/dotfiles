{ config, lib, ... }:

{
  options.dotfiles.httpMcpServers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        url = lib.mkOption {
          type = lib.types.str;
          description = "Remote MCP endpoint URL. May itself carry an auth token as a query param (e.g. Windmill's issued MCP URLs do) — treat it like a secret.";
        };
      };
    });
    default = {};
    description = ''
      Remote HTTP MCP servers shared across agent CLIs (Claude Code, Mistral Vibe).
      Each client's own module (claude-code.nix, vibe.nix) translates these into
      its native config format.
    '';
  };

  # url is a literal ${VAR} placeholder, not the resolved value:
  # - Claude Code expands it itself at connect time (reads its own process env).
  # - Vibe's config.toml has no runtime env expansion for `url`, so vibe.nix
  #   resolves this placeholder via envsubst during `home-manager switch`
  #   instead (baking in the URL, token and all — same secret, just resolved
  #   at a different time).
  config.dotfiles.httpMcpServers.windmill = {
    url = "\${WINDMILL_MCP_URL}";
  };
}
