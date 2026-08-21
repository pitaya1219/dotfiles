''
export PATH="~/.nix-profile/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$(brew --prefix openssl)/bin:/applications/xcode.app/contents/developer/usr/bin:$PATH"

# Rancher Desktop 同梱の rdctl / kubectl / nerdctl 等。末尾に足すのは、同居する
# docker が nix 管理の docker を隠さないようにするため。
export PATH="$PATH:$HOME/.rd/bin"
''
