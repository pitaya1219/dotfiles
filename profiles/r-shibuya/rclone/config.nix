{ config, pkgs, lib, ... }:

let
  profileName = config.home.username;

  # Wrapper script that creates config at runtime with secrets from passage
  rcloneWrapper = ''
    #!/usr/bin/env bash

    # Create temporary config with secrets from passage
    TEMP_CONFIG=$(mktemp)
    trap "rm -f $TEMP_CONFIG" EXIT

    # Get secrets from passage
    TOKEN="$(passage show rclone/pcloud/${profileName}/token)"
    PASSWORD="$(passage show rclone/crypt/${profileName}/password)"
    PASSWORD2="$(passage show rclone/crypt/${profileName}/password2)"

    # Obscure passwords
    OBSCURED_PASS="$(${pkgs.rclone}/bin/rclone obscure "$PASSWORD")"
    OBSCURED_PASS2="$(${pkgs.rclone}/bin/rclone obscure "$PASSWORD2")"

    # Generate config with secrets
    cat > "$TEMP_CONFIG" <<EOF
    [pcloud]
    type = pcloud
    hostname = eapi.pcloud.com
    token = $TOKEN

    [pcloud-crypt]
    type = crypt
    remote = pcloud:
    password = $OBSCURED_PASS
    password2 = $OBSCURED_PASS2
    filename_encryption = standard
    directory_name_encryption = true
    EOF

    exec ${pkgs.rclone}/bin/rclone --config "$TEMP_CONFIG" "$@"
  '';
in
{
  # Wrapper script with secrets from passage
  home.file.".local/bin/rclone-secure" = {
    text = rcloneWrapper;
    executable = true;
  };
}
