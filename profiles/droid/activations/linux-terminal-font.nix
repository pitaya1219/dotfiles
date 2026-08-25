{ pkgs, lib, ... }:

let
  font = pkgs.nerd-fonts.daddy-time-mono;
  fontFile = "${font}/share/fonts/truetype/NerdFonts/DaddyTimeMono/DaddyTimeMonoNerdFontMono-Regular.ttf";
  # No space: ttyd's ExecStart -t key=value tokens are split by systemd's own
  # unit-file parser, not a shell, so a value containing a space would need
  # unit-file-specific quoting. Keeping it one word sidesteps that entirely.
  fontFamily = "DaddyTimeMono";
  unitFile = "/etc/systemd/system/ttyd_uds.service";

  # Android's built-in "Linux Terminal" app renders this VM's ttyd page in a
  # host-side WebView, so there's no shared filesystem to drop a plain font
  # file into -- the font has to be base64-embedded into the HTML page ttyd
  # itself serves. This captures ttyd's own default page once (as
  # index.html.orig) and re-injects a @font-face + override into a fresh copy
  # on every activation, so upstream ttyd markup/JS is otherwise untouched.
  #
  # The @font-face alone isn't enough, though: xterm.js paints the actual
  # terminal contents on a <canvas> via `ctx.font = ...rawOptions.fontFamily`,
  # which is plain JS state, not CSS -- no stylesheet rule (however
  # `!important`) can reach it. That JS-side fontFamily is only set by ttyd's
  # own `-t fontFamily=...` client option (sent to the page over its
  # WebSocket control channel at connect time), which the activation script
  # below also patches into ExecStart. The two pieces are complementary: -I's
  # @font-face makes the family name resolve to real glyphs, -t fontFamily
  # makes xterm.js actually ask for that family.
  #
  # ttyd's default rendererType is "webgl": glyphs get rasterized once into a
  # GPU texture atlas, and the atlas isn't invalidated just because a webfont
  # that was still loading at connect time finishes loading moments later --
  # so whichever glyphs got drawn during that race (often: every glyph,
  # measured against whatever fallback font was resolvable at the time) stay
  # wrong for the rest of the session: uniformly-off cell width (wrong glyph
  # metrics baked into the atlas) and tofu for Nerd Font icon codepoints the
  # fallback font never had. Real DOM text elements don't have this problem --
  # browsers already handle "swap in the webfont once it loads" natively for
  # actual text nodes -- so -t rendererType=dom trades a bit of raw scrollback
  # throughput (irrelevant for a single interactive session) for correctness.
  injectFont = pkgs.writeText "linux-terminal-font-inject.py" ''
    import base64, sys

    orig_path, out_path, font_path, family, marker = sys.argv[1:6]
    html = open(orig_path, "r", encoding="utf-8").read()
    with open(font_path, "rb") as f:
        font_b64 = base64.b64encode(f.read()).decode("ascii")

    style = (
        f'<style id="{marker}">'
        f'@font-face{{font-family:"{family}";'
        f'src:url(data:font/ttf;base64,{font_b64}) format("truetype");}}'
        f'.xterm,.xterm *{{font-family:"{family}",monospace!important;}}'
        f'</style>'
    )
    html = html.replace("</head>", style + "</head>", 1) if "</head>" in html else html + style
    open(out_path, "w", encoding="utf-8").write(html)
  '';
in
{
  home.activation.setupLinuxTerminalFont = lib.hm.dag.entryAfter ["writeBoundary"] ''
    (
      # home-manager's activation PATH is minimal and doesn't carry sudo,
      # curl, or systemctl -- confirmed live (see herdr_mirror.nix for the
      # same pitfall with curl/git/bash). sudo/systemctl must stay the real
      # system binaries, so they're called by absolute path; curl is pulled
      # from the nix store instead since --unix-socket doesn't care which
      # build serves it.
      sudo="/usr/bin/sudo"
      systemctl="/usr/bin/systemctl"
      curl="${pkgs.curl}/bin/curl"

      unitFile="${unitFile}"
      if [ ! -e "$unitFile" ]; then
        echo "setupLinuxTerminalFont: $unitFile not found, skipping (not the AVF Linux Terminal VM?)" >&2
        exit 0
      fi

      confDir="$HOME/.config/ttyd"
      origFile="$confDir/index.html.orig"
      outFile="$confDir/index.html"
      newFile="$confDir/index.html.new"
      mkdir -p "$confDir"

      if [ ! -s "$origFile" ]; then
        if grep -q -- "-I $outFile" "$unitFile" 2>/dev/null; then
          echo "setupLinuxTerminalFont: $unitFile already points at $outFile but $origFile is missing; remove -I from the unit and re-run to recapture ttyd's pristine page" >&2
          exit 0
        fi
        if ! "$sudo" -n "$curl" -sf --unix-socket /run/ttyd/ttyd.sock http://localhost/ -o "$origFile"; then
          echo "setupLinuxTerminalFont: could not fetch ttyd's default page (is ttyd_uds.service running?)" >&2
          exit 0
        fi
      fi

      ${pkgs.python3}/bin/python3 "${injectFont}" "$origFile" "$newFile" "${fontFile}" "${fontFamily}" "droid-terminal-font"

      changed=0
      if ! cmp -s "$newFile" "$outFile" 2>/dev/null; then
        mv -f "$newFile" "$outFile"
        changed=1
      else
        rm -f "$newFile"
      fi

      # ttyd reads -I's target once at startup, not per-request, so a content
      # change needs a restart just as much as a freshly-added flag does.
      # -t fontFamily is checked independently of -I: an earlier generation of
      # this activation added -I without it, so gating both on the same "-I
      # present" check would've left fontFamily permanently unpatched.
      if ! grep -q -- "-t fontFamily=${fontFamily}" "$unitFile" 2>/dev/null; then
        "$sudo" -n sed -i "s# -W /usr/bin/setpriv# -t fontFamily=${fontFamily} -W /usr/bin/setpriv#" "$unitFile"
        changed=1
      fi

      if ! grep -q -- "-t rendererType=dom" "$unitFile" 2>/dev/null; then
        "$sudo" -n sed -i "s# -W /usr/bin/setpriv# -t rendererType=dom -W /usr/bin/setpriv#" "$unitFile"
        changed=1
      fi

      if ! grep -q -- "-I $outFile" "$unitFile" 2>/dev/null; then
        "$sudo" -n sed -i "s# -W /usr/bin/setpriv# -I $outFile -W /usr/bin/setpriv#" "$unitFile"
        changed=1
      fi

      if [ "$changed" = 1 ]; then
        "$sudo" -n "$systemctl" daemon-reload
        "$sudo" -n "$systemctl" restart ttyd_uds
      fi
    ) || echo "setupLinuxTerminalFont: failed, continuing" >&2
  '';
}
