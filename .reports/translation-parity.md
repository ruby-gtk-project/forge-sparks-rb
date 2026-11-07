# Translation parity — forge-sparks

| | |
|---|---|
| Upstream | `main` @ `3df28d2` |
| Port | `ruby` @ `3f45b15` |
| Upstream msgids | 56 |
| Ported, byte-identical | 52 |
| Gaps | 4 |
| Extra (not a gap, recorded) | 4 |
| Locales | 26 / 26, same set (`po/LINGUAS` diff is empty after sort — order differed, content did not) |

Census: `git show origin/main:po/com.mardojai.ForgeSparks.pot` vs
`po/forge-sparks.pot`, `msgid` lines extracted and diffed as sorted sets
(`comm -23` / `comm -13`). 56 unique msgids on each side; 52 are identical.

## Gaps — in upstream, not in the port

| Upstream msgid | Source | Why it's missing |
|---|---|---|
| `"Allow running Forge Sparks on background."` | `src/util.js:58` | Belongs to the XDG background-portal request the port never calls — see `.reports/component-parity.md` |
| `"Allow running Forge Sparks on startup."` | `src/util.js:59` | same |
| `"Monitoring new notifications"` | `src/util.js:82` | `setBackgroundStatus`'s default message to the portal; no portal call exists to pass it to |
| `"The request failed."` | `src/widgets/preferences.js:66` | The failure toast on a denied portal request. The port has a toast at the same site (`lib/preferences_dialog.rb:167`) but with a **different** msgid, `"The autostart request failed."` — not a move, a reword (see below) |

These are not independent string losses; they are the one missing component
(the background portal) losing its four strings together. Closing the
component-parity gap closes this one too.

## Extra — in the port, not upstream (not a parity failure, recorded per the skill's rule)

| Port msgid | Source | Note |
|---|---|---|
| `"Keyboard Shortcuts"` | `lib/shortcuts_dialog.rb:35`, dialog title | Upstream's `ShortcutsWindow` sets no title; the port invented one for `Adwaita::ShortcutsDialog`. Harmless but will render in English for every one of the 26 catalogues until someone translates it, since no translator has ever seen this string. |
| `"Print version information and exit"` | `lib/application.rb:116` | Upstream's identical-text CLI option description (`src/application.js:39`) is **not** wrapped in `_()` upstream — it is a bare string handed to `GLib.OptionEntry`, never extracted into upstream's `.pot`. The port marked it translatable; upstream never did. |
| `"Start hidden"` | `lib/application.rb:125` | Same situation as above, `src/application.js:48`. |
| `"Could not read the saved access token"` | `lib/account_dialog.rb:243` | No upstream string at this call site at all — appears to be new error handling the port added (good), with a self-authored, never-translated message. |
| `"The autostart request failed."` | `lib/preferences_dialog.rb:167` | The reworded replacement for upstream's `"The request failed."` at the same UI position — same slot, different bytes, so it is **both** an extra and the other half of the gap row above. Do not treat adding this string as having closed that gap; the two are different sentences with different translations in all 26 catalogues. |

## What did carry over cleanly

- All 26 `po/LINGUAS` locales, verified as a set (not just a count).
- The primary menu's four mnemonic items (`_Preferences`, `_Accounts`,
  `_Keyboard Shortcuts`, `About Forge Sparks`) and the banner's `Accounts`
  button label — byte-identical, spot-checked against `src/window.blp`.
- The shortcuts dialog's three `C_("shortcut window", …)` entries, including
  the pgettext context — spot-checked against `src/gtk/help-overlay.blp`.
- Forge backend help text, relative-date plural forms (`n_`), account/forge
  strings — not individually re-diffed msgid-by-msgid beyond the set
  comparison above, but none of these appeared on either side of the `comm`
  diff, so they match.

## Rule followed

Per the skill, the port's bytes are never treated as correct over upstream's:
the `"The autostart request failed."` / `"The request failed."` pair is
recorded as a gap (upstream's string missing) plus an extra (the port's
replacement), not quietly accepted because the port's version also makes
grammatical sense.
