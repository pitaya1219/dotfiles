{
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-R";
    LANG = "en_US.UTF-8";
    LC_LANGUAGE = "en_US.UTF-8";
    TZ = "Asia/Tokyo";
    # ~ doesn't expand inside double quotes — only $HOME does, even quoted.
    PATH = "$HOME/dotfiles/scripts:$HOME/.nix-profile/bin:$HOME/.local/bin:$PATH";
    PYTHONDONTWRITEBYTECODE = 1;
    WINDMILL_LOGSEQ_MCP_URL = "$(passage show homelab/windmill/mcp/logseq/url)";
    WINDMILL_DUFS_MCP_URL = "$(passage show homelab/windmill/mcp/dufs/url)";
}
