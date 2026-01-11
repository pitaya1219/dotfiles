{
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-R";
    LANG = "en_US.UTF-8";
    LC_LANGUAGE = "en_US.UTF-8";
    PATH = "~/.nix-profile/bin:~/.local/bin:$PATH";
    PYTHONDONTWRITEBYTECODE = 1;

    # shellm - LLM-powered shell completion
    SHELLM_URL = "https://ai.pitaya.f5.si";
    SHELLM_MODEL = "qwen2.5-coder-1.5b-Q4_K_M";
    SHELLM_AUTH_TYPE = "oauth2";
    SHELLM_TOKEN_URL = "https://auth.pitaya.f5.si/oauth/v2/token";
}
