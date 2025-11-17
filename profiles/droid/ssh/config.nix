{ config, pkgs, lib, ... }:

let
  profileName = config.home.username;
  passage = import ../../../lib/passage.nix { inherit lib pkgs; };

  clientId = passage.getRuntimeEval "cloudflared/ssh.pitaya.f5.si/${profileName}/client_id";
  secret = passage.getRuntimeEval "cloudflared/ssh.pitaya.f5.si/${profileName}/secret";

  # SSH config template that uses cloudflared with credentials from passage
  sshConfig = ''
    # Cloudflared SSH Proxy Configuration for ${profileName}
    Host ssh.pitaya.f5.si
      ProxyCommand cloudflared access ssh --hostname %h --id ${clientId} --secret ${secret}
      Port 1771
  '';
in
{
  home.file.".ssh/config.d/cloudflared".text = sshConfig;

  # Ensure SSH config includes the cloudflared config
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.d/cloudflared" ];
  };
}
