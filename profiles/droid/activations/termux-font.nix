{ pkgs, lib, ... }:

let
  font = pkgs.nerd-fonts.daddy-time-mono;
  fontFile = "${font}/share/fonts/truetype/NerdFonts/DaddyTimeMono/DaddyTimeMonoNerdFontMono-Regular.ttf";
in
{
  home.activation.setupTermuxFont = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.termux"
    cp -f "${fontFile}" "$HOME/.termux/font.ttf"
  '';
}
