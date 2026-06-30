{ pkgs, lib, config, ... }:

let
  # Define custom plugins that aren't in nixpkgs
  customPlugins = [
    {
      name = "aquarium-vim";
      owner = "FrenzyExists";
      repo = "aquarium-vim";
      rev = "develop";
      sha256 = "0rc3cmba2bfrjcffpc1f2a9y2yx167a39l1lxpxpvapsilkxnb2d";
    }
    {
      name = "base2tone-nvim";
      owner = "atelierbram";
      repo = "Base2Tone-nvim";
      rev = "main";
      sha256 = "1wn2dgwicqn8y0sgw2fsbs750xxwnxg68a6j18aj8yhhpq2dkhsx";
    }
    {
      name = "evangelion";
      owner = "xero";
      repo = "evangelion.nvim";
      rev = "main";
      sha256 = "0afa1alxf8my6k564sqmzykwk8aqb6n37wa5w3aqdlxs6y2hrsnm";
    }
    {
      name = "burgundy";
      owner = "elliothatch";
      repo = "burgundy.vim";
      rev = "master";
      sha256 = "07z656b5ravc9k39nai6j2732d569nmd9fp3dpyqph684sqg1qx3";
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
