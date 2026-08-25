{ config, pkgs, lib, ... }:

{
  programs.herdr = {
    enable = true;
    # herdrdev/herdr tracked at master (see the flake input), not the version
    # nixpkgs/home-manager bundles: herdr-mirror needs the preview-only
    # terminal-session-stream API (2026-06-30+).
    package = pkgs.herdr;
    settings = {
      # Onboarding asks for the theme and notification choices this file
      # already makes, and it cannot persist an answer: config.toml is a
      # read-only symlink into the Nix store.
      onboarding = false;

      update = {
        # Nix owns the binary, so `herdr update` cannot write over it and the
        # background check would only ever nag. Bump the flake input instead.
        version_check = false;
      };

      ui = {
        # Order the sidebar by which agent needs attention rather than by
        # workspace, so a blocked agent surfaces without scanning the list.
        agent_panel_sort = "priority";

        # In-app toasts rather than the OS notification service: they render
        # the same wherever the TUI is attached, including over SSH. Being away
        # from the terminal is already covered by scripts/rocketchat-notify.sh.
        toast.delivery = "herdr";

        # $session is not a built-in token. It carries the agent's own session
        # id (first 8 chars) and is fed by scripts/agent-session-tab-pointer.py
        # from the Claude Code and Vibe hooks — with no reporter running, the
        # token renders empty.
        sidebar.agents.rows = [
          [ "state_icon" "workspace" "tab" ]
          [ "agent" "$session" ]
        ];
      };

      keys = {
        # Unbound by default. Jumps straight to the nth sidebar row, which is
        # the counterpart to prefix+o (jump to the pane a notification came
        # from) when the agent you want is not the one that just fired.
        focus_agent = "prefix+alt+1..9";

        # herdr-mirror plugin (github:nikok6/herdr-mirror, ~/.config/herdr-mirror/hosts.toml):
        # folds remote hosts' herdr sessions into this sidebar as <host>:<name>
        # mirror workspaces.
        command = [
          { key = "prefix+shift+m"; type = "plugin_action"; command = "mirror.start"; description = "Mirror: start"; }
          { key = "prefix+shift+s"; type = "plugin_action"; command = "mirror.pause"; description = "Mirror: pause"; }
          { key = "prefix+shift+b"; type = "plugin_action"; command = "mirror.restore"; description = "Mirror: restore"; }
          { key = "prefix+alt+d"; type = "plugin_action"; command = "mirror.teardown"; description = "Mirror: tear down"; }
          { key = "prefix+alt+n"; type = "plugin_action"; command = "mirror.remote-new-workspace"; description = "Mirror: new remote workspace"; }
          { key = "prefix+alt+c"; type = "plugin_action"; command = "mirror.remote-new-tab"; description = "Mirror: new remote tab"; }
          { key = "prefix+alt+v"; type = "plugin_action"; command = "mirror.remote-split-right"; description = "Mirror: split remote right"; }
          { key = "prefix+alt+minus"; type = "plugin_action"; command = "mirror.remote-split-down"; description = "Mirror: split remote down"; }
        ];
      };

      experimental = {
        # Prefix chords are swallowed while a Japanese IME is composing.
        # macOS/Windows only; a no-op on the Linux profiles.
        switch_ascii_input_source_in_prefix = true;
      };
    };
  };
}
