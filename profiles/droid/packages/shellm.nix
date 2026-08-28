{ ... }:
{
  # Android OOM workaround: single-threaded Rust build to prevent SIGKILL
  # from Android's LMK during parallel cargo compilation. Independent of
  # proot -- Android's memory pressure applies to the native VM too.
  local.shellm.extraBuildAttrs = {
    env = {
      CARGO_BUILD_JOBS = "1";
      RUSTFLAGS = "-C codegen-units=1";
    };
  };
}
