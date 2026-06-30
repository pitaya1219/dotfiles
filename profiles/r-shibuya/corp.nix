{ config, pkgs, lib, ... }:

{
  # Set NODE_EXTRA_CA_CERTS at login so Electron apps (Joplin, VS Code, etc.)
  # trust the Netskope CA. launchctl setenv propagates the env var to all
  # processes spawned by this user's launchd session after this agent runs.
  launchd.agents.node-extra-ca-certs = {
    enable = true;
    config = {
      Label = "com.local.node-extra-ca-certs";
      ProgramArguments = [
        "/bin/launchctl" "setenv"
        "NODE_EXTRA_CA_CERTS"
        "/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"
      ];
      RunAtLoad = true;
    };
  };
}
