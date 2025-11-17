{ lib, pkgs }:

{
  # Get secret from passage with runtime evaluation
  # Returns a shell command substitution that will be evaluated at runtime
  # Usage: passage.getRuntimeEval "path/to/secret"
  # Result: "$(passage show 'path/to/secret')" - executed when SSH connects
  getRuntimeEval = path: "$(passage show ${lib.escapeShellArg path})";
}
