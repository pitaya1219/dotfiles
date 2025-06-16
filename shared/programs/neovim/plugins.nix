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
  ];

  # Profile-specific plugins
  profilePlugins = with pkgs.vimPlugins; {
    r-shibuya = [
      copilot-vim
    ];
    droid = [];
  };

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
  ] ++ buildCustomPlugins ++ (profilePlugins.${config.home.username} or []);


  extraPackages = with pkgs; [
    # Required for coc.nvim
    nodejs
    python3
    
    # Language servers and tools
    nodePackages.typescript-language-server
    nodePackages.eslint
    nodePackages.prettier
    
    # Python tools
    python3Packages.httpx
    python3Packages.requests
    python3Packages.jinja2
  ];
}
