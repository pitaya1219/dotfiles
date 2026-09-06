{ config, pkgs, ... }:

let
  # pasta (rootless Docker's net driver, see ../../shared/activations/rootless-docker.nix)
  # only relays a published port's data for connections that arrive via the
  # host's real loopback; a connection whose packets arrive via tailscale0
  # and get kernel-forwarded to a host-owned LAN address (as *.internal
  # traffic does -- see core/gateway/headscale/config/config.yaml's
  # extra_records in the homelab repo) completes its TCP handshake but never
  # gets its data relayed into the container. RootlessKit's alternative
  # "builtin" port driver would sidestep this, but it refuses to run under
  # net=pasta at all ("network pasta requires port driver none or implicit"),
  # and net=pasta itself is required for containers to reach real LAN peers
  # (see AGENTS.md's pasta-vs-slirp4netns entry).
  #
  # Nor can Caddy's own publish just target the LAN IP directly instead of
  # 0.0.0.0: pasta's implicit port driver only accepts 0.0.0.0 or 127.0.0.1
  # as a bind address -- a specific non-loopback host IP fails outright with
  # "cannot assign requested address" (confirmed empirically). Worse, pasta
  # claims the OS-level wildcard bind for whatever host port a container
  # publishes to regardless of which host IP is named in the publish spec
  # (confirmed empirically: even a "127.0.0.1:80:80" publish left `ss`
  # showing `*:80` LISTEN) -- so nothing else can bind port 80 at all while
  # Caddy publishes to it, on any address. Caddy therefore publishes to host
  # port 8080 instead (see core/gateway/headscale/docker-compose.yml in the
  # homelab repo), freeing port 80 entirely for this relay, which answers on
  # both host-facing addresses (LAN and tailscale) and makes its own, wholly
  # separate loopback connection into Caddy's 8080 -- not subject to pasta's
  # relay limitation. This also means plain LAN-direct *.internal traffic
  # now flows through this relay too, not just tailscale traffic.
  #
  # Also listens on 127.0.0.1: dragonfruit's own Ansible-managed /etc/hosts
  # override (infra/roles/, "internal_hosts_override") points *.internal at
  # 127.0.0.1 for the host's own local access, which broke the same way
  # once Caddy stopped holding port 80 there.
  relayScript = pkgs.writeText "internal-relay.py" ''
    import asyncio

    LISTEN_ADDRS = ["192.168.10.2", "100.64.0.2", "127.0.0.1"]
    LISTEN_PORT = 80
    TARGET_ADDR = "127.0.0.1"
    TARGET_PORT = 8080


    async def pipe(reader, writer):
        try:
            while True:
                data = await reader.read(65536)
                if not data:
                    break
                writer.write(data)
                await writer.drain()
        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            writer.close()


    async def handle(client_reader, client_writer):
        try:
            target_reader, target_writer = await asyncio.open_connection(TARGET_ADDR, TARGET_PORT)
        except OSError:
            client_writer.close()
            return
        await asyncio.gather(
            pipe(client_reader, target_writer),
            pipe(target_reader, client_writer),
        )


    async def main():
        servers = [
            await asyncio.start_server(handle, addr, LISTEN_PORT)
            for addr in LISTEN_ADDRS
        ]
        async with asyncio.TaskGroup() as tg:
            for server in servers:
                tg.create_task(server.serve_forever())


    asyncio.run(main())
  '';
in
{
  systemd.user.services.internal-relay = {
    Unit = {
      Description = "Relay LAN/tailscale *.internal traffic to Caddy's loopback-published port";
      After = [ "tailscale-up.service" ];
      Requires = [ "tailscale-up.service" ];
    };
    Service = {
      ExecStart = "${pkgs.python3}/bin/python3 ${relayScript}";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
