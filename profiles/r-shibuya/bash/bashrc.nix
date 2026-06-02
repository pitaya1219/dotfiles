''
export PATH="~/.nix-profile/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$(brew --prefix openssl)/bin:/applications/xcode.app/contents/developer/usr/bin:$PATH"
export ASANA_CLIENT_SECRET="$(passage show asana/client/secret 2>/dev/null)"
''
