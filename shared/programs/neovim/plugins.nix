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
      sha256 = "04mj4mcrg850lfcc89vikibmmmscnssc74hfl16vjax51s0157jw";
    }
    {
      name = "burgundy";
      owner = "elliothatch";
      repo = "burgundy.vim";
      rev = "master";
      sha256 = "0ni0x8kx25mvgrlza9zvddn78bkv232cdr01cqr9nmp0jblsj86a";
    }
    {
      name = "nvim-colorizer";
      owner = "norcalli";
      repo = "nvim-colorizer.lua";
      rev = "master";
      sha256 = "0v1h9lj68kmx6052zg78v366iibxq78367h7avm97pvp5ksvqcw2";
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
    traces-vim
    
    # Color schemes
    everforest
    nightfox-nvim
    kanagawa-nvim
    kanagawa-paper-nvim
    iceberg-vim
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
    nodePackages.typescript-language-server
    nodePackages.eslint
    nodePackages.prettier
    
    # Nix language server
    nixd
    nixpkgs-fmt
    
  ];
}
