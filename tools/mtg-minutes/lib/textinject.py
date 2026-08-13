"""Type an arbitrary string into whatever app has focus (macOS).

Used by voice-in to deliver each finalized utterance.

Why not the clipboard and Cmd+V:
  It works, but dictation finalizes many times while you are still speaking,
  so every utterance would clobber the clipboard. Saving and restoring the
  previous contents still races with anything copied mid-session.
  CGEventKeyboardSetUnicodeString puts the string on the event itself and
  never touches the clipboard.

Why not osascript's `keystroke`:
  System Events maps the string onto key codes, so characters the current
  keyboard layout cannot type - Japanese - come out mangled or dropped.
  A Unicode string on a CGEvent bypasses the layout entirely.

Permissions:
  Posting events needs the TCC "Accessibility" grant.
  CGPreflightPostEventAccess reports whether it is held and
  CGRequestPostEventAccess raises the system dialog. The grant follows the
  responsible process - the terminal, when launched from one - so it is not
  tied to this file's store path and survives a nixpkgs python bump.
  unavailable_reason() returns prose so the caller can say what is wrong.
"""

import time

# UTF-16 code units per event. CGEventKeyboardSetUnicodeString accepts longer
# strings, but some apps drop characters when handed a large one at once.
CHUNK_UTF16 = 16

# Gap between events. Posted back to back, terminals and Electron apps drop some.
INTER_EVENT_SEC = 0.006


class TextInjector:
    """A keyboard that types Unicode strings through CGEvent.

    Quartz is imported on construction. Import failure (no pyobjc) is kept as
    state rather than raised, so voice-in can still run with --no-insert.
    """

    def __init__(self):
        self.error = None
        self._quartz = None
        self._source = None
        try:
            import Quartz
        except ImportError as e:
            self.error = f"pyobjc(Quartz)を読み込めません: {e}"
            return
        self._quartz = Quartz
        # An HIDSystemState source inherits the current hardware state, held
        # modifiers included. We do not want that, so flags are cleared per event.
        self._source = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)

    # -- permission ---------------------------------------------------------
    def request_permission(self):
        """Raise the system dialog. A no-op once the grant is held.

        Returns nothing: the dialog does not grant anything by itself - the
        user has to tick the box in System Settings - so there is nothing
        useful to learn here.
        """
        if self._quartz is None:
            return
        if fn := getattr(self._quartz, "CGRequestPostEventAccess", None):
            fn()

    def unavailable_reason(self):
        """Why events cannot be posted, or None if they can.

        When the grant cannot be determined (no preflight API), carry on
        rather than refuse: posting will show soon enough, and being unable
        to check is not a reason to be unusable.
        """
        if self.error:
            return self.error
        fn = getattr(self._quartz, "CGPreflightPostEventAccess", None)
        if fn and not fn():
            return ("アクセシビリティの許可がありません。"
                    "システム設定 > プライバシーとセキュリティ > アクセシビリティ で許可してください")
        return None

    # -- posting ------------------------------------------------------------
    def send(self, text):
        """Type text. True if it was posted."""
        if self._quartz is None or not text:
            return False
        Q = self._quartz
        first = True
        for part, n in _split_utf16(text, CHUNK_UTF16):
            # The gap only belongs *between* chunks. Sleeping after the last one
            # stalls the reader thread once per utterance for nothing.
            if not first:
                time.sleep(INTER_EVENT_SEC)
            first = False
            # Post key down and key up as a pair; one alone reads as a key
            # being held down.
            for down in (True, False):
                ev = Q.CGEventCreateKeyboardEvent(self._source, 0, down)
                if ev is None:
                    return False
                # With Cmd or Ctrl held at post time the event is taken as a
                # shortcut rather than as text. Always post unmodified.
                Q.CGEventSetFlags(ev, 0)
                Q.CGEventKeyboardSetUnicodeString(ev, n, part)
                Q.CGEventPost(Q.kCGHIDEventTap, ev)
        return True


def _split_utf16(text, limit):
    """Split into (chunk, utf16_length) pairs of at most limit UTF-16 units.

    Accumulates per character so surrogate pairs (emoji) are never split.
    len(str) counts code points, so using it directly would hand
    CGEventKeyboardSetUnicodeString the wrong length. The length is returned
    alongside the chunk to save the caller from re-encoding to recount it.
    """
    part, size = [], 0
    for ch in text:
        w = len(ch.encode("utf-16-le")) // 2
        if size + w > limit and part:
            yield "".join(part), size
            part, size = [], 0
        part.append(ch)
        size += w
    if part:
        yield "".join(part), size
