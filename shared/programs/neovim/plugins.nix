{ pkgs, lib, config, ... }:

let
  # Define custom plugins that aren't in nixpkgs
  customPlugins = [
    {
      name = "aquarium-vim";
      owner = "FrenzyExists";
      repo = "aquarium-vim";
      rev = "d5c4816717e5136278a9148bd19268fcaf514fe9";
      sha256 = "00cs7l7k62z7f1ms363n7szvnrr0dm5z4fg83rhszh6llfdk6121";
    }
    {
      name = "base2tone-nvim";
      owner = "atelierbram";
      repo = "Base2Tone-nvim";
      rev = "c32c1d3dfdc8fb6e91cbf6078c078d6c3eaaa673";
      sha256 = "1wn2dgwicqn8y0sgw2fsbs750xxwnxg68a6j18aj8yhhpq2dkhsx";
    }
    {
      name = "evangelion";
      owner = "xero";
      repo = "evangelion.nvim";
      rev = "08cf52a0931a81bf5b64c93b744e136b5edb6d85";
      sha256 = "0afa1alxf8my6k564sqmzykwk8aqb6n37wa5w3aqdlxs6y2hrsnm";
    }
    {
      name = "burgundy";
      owner = "elliothatch";
      repo = "burgundy.vim";
      rev = "5b6d30c8e2459e2ae650598b0c87c5d550e6a335";
      sha256 = "sha256-o+PwsCbIwIv9beO61KpNpjQxjpAmKpvGTGyrXJYp5h8=";
    }
    {
      name = "nvim-colorizer";
      owner = "norcalli";
      repo = "nvim-colorizer.lua";
      rev = "master";
      sha256 = "0v1h9lj68kmx6052zg78v366iibxq78367h7avm97pvp5ksvqcw2";
    }
    {
      name = "spaceduck";
      owner = "spaceduck-theme";
      repo = "nvim";
      rev = "master";
      sha256 = "1n3jbbpqr4k6fa4hdj1q372rkacn9v7isx9bvafdbhrqvx8j66g7";
    }
    {
      name = "oldworld-nvim";
      owner = "dgox16";
      repo = "oldworld.nvim";
      rev = "main";
      sha256 = "sha256-yO5XKSMwDu0/QYnoMbxWs+h0tfjftAYJYPrKO2XYfNQ=";
    }
  ];


  # Build custom plugins using loop
  buildCustomPlugins = map (plugin: pkgs.vimUtils.buildVimPlugin {
    name = plugin.name;
    src = pkgs.fetchFromGitHub {
      owner = plugin.owner;
      repo = plugin.repo;
      rev = plugin.rev;
      sha256 = plugin.sha256;
    };
  }) customPlugins;
in
{
  plugins = with pkgs.vimPlugins; [
    # Core plugins
    coc-nvim

    # Language support
    vim-markdown
    vim-toml

    # Development tools
    ollama-nvim

    # UI enhancements
    nvim-notify
    nui-nvim
    noice-nvim
    traces-vim
    lualine-nvim
    (nvim-treesitter.withPlugins (parsers: with parsers; [
      lua nix python javascript typescript bash json yaml toml markdown
    ]))
    nvim-treesitter-context
    specs-nvim
    
    # Color schemes
    everforest
    miasma-nvim
    nightfox-nvim
    kanagawa-nvim
    kanagawa-paper-nvim
    iceberg-vim
    melange-nvim
    lush-nvim
    zenbones-nvim
  ] ++ buildCustomPlugins;

  # These tools are added to $PATH only when Neovim is started
  extraPackages = with pkgs; [
    ripgrep

    # Python packages for neovim
    (python3.withPackages (ps: with ps; [
      msgpack
      # Python packages for Neovim
      pynvim
      # Python packages for vim-ollama
      httpx
      requests
      jinja2
    ]))
    

    nodejs
    # Language servers and tools
    typescript-language-server
    eslint
    prettier
    
    # Nix language server
    nixd
    nixpkgs-fmt
    
  ];
}
