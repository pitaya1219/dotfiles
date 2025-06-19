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
    nightfox-nvim
    kanagawa-nvim
    kanagawa-paper-nvim
    iceberg-vim
  ] ++ buildCustomPlugins;

  # These tools are added to $PATH only when Neovim is started
  extraPackages = with pkgs; [
    python3
    
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
    
  ];
}
