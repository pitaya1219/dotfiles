{ pkgs, lib, config, ... }:

let
  # llama.vim builds its instruction requests as fixed dicts with no hook for
  # extra fields, and llama#inst_send cannot be redefined from a config file
  # because it reaches into that script's own s: state. Gemma 4 reasons unless
  # the request says otherwise, and the only server-side lever, --reasoning
  # off, is global and cannot be overridden by a request asking for thinking
  # back — hermes would pay for neovim's latency. So the plugin carries a
  # params_inst dict merged into both request bodies, set in
  # neovim/plugin/10_llama.lua.
  #
  # Not upstreamed. Drop this once pkgs.vimPlugins.llama-vim carries any hook
  # for extra instruction request fields; the patch is against the v0.1.0 tag
  # nixpkgs builds, so a version bump that moves those lines fails the build
  # rather than silently dropping the field.
  llama-vim = pkgs.vimPlugins.llama-vim.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./llama-vim-params-inst.patch ];
  });
in
{
  # Profile-specific plugins for r-shibuya
  plugins = [
    llama-vim
    pkgs.vimPlugins.vim-elixir
  ];

  # Profile-specific extra packages
  extraPackages = with pkgs; [
    # Add any r-shibuya specific packages here
  ];

}
