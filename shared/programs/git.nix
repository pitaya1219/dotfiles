{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      credential = {
        helper = "${config.home.homeDirectory}/.config/git/git-credential-protonpass.sh";
      };
      core = {
        hooksPath = "${config.home.homeDirectory}/.config/git/hooks";
      };
    };
  };

  # Accounts provisioned by copying another profile's home directory (e.g. new
  # agent-session accounts) can inherit a legacy ~/.gitconfig with a stale
  # credential.helper from before that profile migrated to this XDG-based
  # config. git reads both ~/.gitconfig and ~/.config/git/config, and
  # credential.helper is multi-valued, so the stale entry runs alongside
  # (not overridden by) the one declared above. Clear it on every activation
  # so the declared helper stays the only one, without touching any other
  # legacy ~/.gitconfig content.
  home.activation.removeStaleGitCredentialHelper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    legacy_gitconfig="${config.home.homeDirectory}/.gitconfig"
    if [ -f "$legacy_gitconfig" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git config --file "$legacy_gitconfig" --unset-all credential.helper 2>/dev/null || true
    fi
  '';

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
    # AI tools
    .aider/
    .aider.*
    .ai-sessions/
  '';

  # Install git credential helper script
  home.file.".config/git/git-credential-protonpass.sh" = {
    source = ./git/git-credential-protonpass.sh;
    executable = true;
  };

  # Install commit-msg hook to prevent AI references in commit messages
  home.file.".config/git/hooks/commit-msg" = {
    source = ./git/hooks/commit-msg;
    executable = true;
  };

  # Install pre-commit hook to prevent commits authored as an AI tool's own
  # identity (Claude, Mistral Vibe, etc.) instead of the human's
  home.file.".config/git/hooks/pre-commit" = {
    source = ./git/hooks/pre-commit;
    executable = true;
  };
}
