{ config, pkgs, lib, ... }:

{
  programs.herdr = {
    enable = true;
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
      };

      experimental = {
        # Prefix chords are swallowed while a Japanese IME is composing.
        # macOS/Windows only; a no-op on the Linux profiles.
        switch_ascii_input_source_in_prefix = true;
      };
    };
  };
}
