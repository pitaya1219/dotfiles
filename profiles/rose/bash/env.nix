rec {
 XDG_RUNTIME_DIR = "/run/user/\${UID}";
 DOCKER_HOST = "unix:///\${XDG_RUNTIME_DIR}/docker.sock";
 DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/\$(id -u)/bus";
 DOCKER_IPTABLES_PATH = "/usr/sbin/iptables";
}
