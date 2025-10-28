{ config, pkgs, lib, ... }:

let
  path = lib.makeBinPath [
    pkgs.shadow # newuidmap/newgidmap
    pkgs.curl
    pkgs.iptables
    pkgs.kmod
    pkgs.getopt
    pkgs.gnutar
    pkgs.gzip
    pkgs.coreutils
  ];
in
{
  home.activation.installRootlessDocker = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export BIN="$HOME/.local/bin"
    export DOCKER_BIN="$HOME/.local/bin"
    export PATH="${path}:$HOME/.local/bin:$PATH"
    echo "Installing to: $BIN"
    if ! command -v docker &> /dev/null; then
      echo "Installing rootless-docker via install script..."
      curl -fsSL https://get.docker.com/rootless | sh -s -- --force
    else
      echo "rootless-docker is already installed"
    fi
  '';

  home.activation.installDockerCompose = lib.hm.dag.entryAfter ["installRootlessDocker"] ''
    export PATH="${path}:$HOME/.local/bin:$PATH"
    if ! docker compose &>/dev/null; then
      echo "Installing docker-compose via install script..."
      test -d $HOME/.docker/cli-plugins ||
        mkdir -p $HOME/.docker/cli-plugins
      curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
        -o $HOME/.docker/cli-plugins/docker-compose
      chmod +x $HOME/.docker/cli-plugins/docker-compose
    else
      echo "docker-compose is already installed"
    fi
  '';
}
