{ ... }:
{
  # Android/proot OOM workaround: single-threaded Rust build to prevent
  # SIGKILL from Android's LMK during parallel cargo compilation.
  local.shellm.extraBuildAttrs = {
    env = {
      CARGO_BUILD_JOBS = "1";
      RUSTFLAGS = "-C codegen-units=1";
    };
  };
}
