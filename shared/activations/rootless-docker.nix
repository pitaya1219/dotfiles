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

  home.activation.overrideConfigure = lib.hm.dag.entryAfter ["installRootlessDocker"] ''
    cat > ~/.config/systemd/user/docker.service.d/override.conf <<EOF
[Service]
Environment="PATH=$HOME/.nix-profile/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
  '';

  home.activation.configureIpv6 = lib.hm.dag.entryAfter ["installRootlessDocker"] ''
    mkdir -p ~/.config/systemd/user/docker.service.d
    # pasta reflects the host's own routing table into the container
    # instead of NATing behind a synthetic subnet, so a rootless container
    # can reach *other* real LAN devices directly (e.g. gateway's nginx
    # proxying to koi's llama.cpp at 192.168.10.3). slirp4netns's synthetic
    # 10.0.2.0/24 NAT has no equivalent -- it special-cases exactly one
    # address (10.0.2.2, "the host itself") and cannot reach any other LAN
    # peer at all. RootlessKit also hard-rejects `--net=pasta` paired with
    # `--port-driver=builtin` ("requires port driver 'none' or 'implicit'"),
    # so there is no combination that gets both properties at once.
    #
    # See AGENTS.md's "pasta vs slirp4netns rootless Docker published
    # ports" entry before switching this back over a published-port
    # complaint.
    cat > ~/.config/systemd/user/docker.service.d/pasta.conf <<EOF
[Service]
Environment="DOCKERD_ROOTLESS_ROOTLESSKIT_NET=pasta"
Environment="DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS=--ipv6"
Environment="DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER=implicit"
EOF
    mkdir -p ~/.config/docker
    cat > ~/.config/docker/daemon.json <<EOF
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/64",
  "ip6tables": true
}
EOF

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
