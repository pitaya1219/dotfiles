''
export PATH="~/.nix-profile/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$(brew --prefix openssl)/bin:/applications/xcode.app/contents/developer/usr/bin:$PATH"
export ASANA_CLIENT_ID="$(passage show asana/client/id 2>/dev/null)"
''
