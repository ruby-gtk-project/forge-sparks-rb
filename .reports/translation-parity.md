# Translation parity — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` |
| Port | `ruby` @ `5570f99` (re-audited this round; previous pass of this file was at `e0bd336`, two commits behind) |
| Upstream msgids | 56 (unique `msgid` lines from `git show origin/main:po/com.mardojai.ForgeSparks.pot`, excluding the empty header) |
| Ported, present in `po/forge-sparks.pot` | 54 |
| Gaps | 3 |
| Extra (not a gap, recorded) | 4 |
| Locales | 26 / 26, same set as `po/LINGUAS` (order differs, content doesn't) |

Census re-run fresh this round, not reused from the previous pass:
`git show origin/main:po/com.mardojai.ForgeSparks.pot` vs the current
`po/forge-sparks.pot`, `msgid` lines extracted and diffed as sorted sets
(`comm -23` / `comm -13`).

## Gaps — in upstream, not in the port's `.pot` (3)

| Upstream msgid | Source | Why it's missing |
|---|---|---|
| `"Allow running Forge Sparks on background."` | `src/util.js:58` | Used live in `lib/util.rb:112` but never added to `po/forge-sparks.pot` |
| `"Allow running Forge Sparks on startup."` | `src/util.js:59` | Used live in `lib/util.rb:112` but never added to `po/forge-sparks.pot` |
| `"Monitoring new notifications"` | `src/util.js:82` | Used live in `lib/util.rb:137` but never added to `po/forge-sparks.pot` |

**This is a regression this round's census catches that the previous pass of
this report could not have, because the previous pass predates the code
change that introduced it.** At `e0bd336` these three strings genuinely had
no call site anywhere in `lib/`, so their absence from the `.pot` was at
least consistent with the code. Commit `0bcf2cc` ("Bind the real XDG
background portal over D-Bus, write real specs") put all three strings back
into `lib/util.rb`, wrapped in `_()`, as part of wiring the real D-Bus
portal call — but did not regenerate or hand-edit `po/forge-sparks.pot` to
add them. Verified directly:

```
$ git log --oneline -- po/forge-sparks.pot
e0bd336 Fix the background-portal toast text and the sandboxed autostart lie
18f35e9 Port the translation catalogue and the packaging data
```

`po/forge-sparks.pot` has had no commit touch it since `e0bd336` — two
commits and one translation-affecting code change ago. `grep -n "Allow
running\|Monitoring new notifications" po/forge-sparks.pot` returns nothing;
the same grep against `lib/util.rb` returns the three call sites. A string
wrapped in `_()` that was never extracted into the `.pot` will render in
English in all 26 locale catalogues forever, regardless of how correct the
code behind it is — `_()` only marks a string translatable, it does not
retroactively add it to the catalogue translators work from. This is a live
gap in the Text axis today, not a historical one.

`"The request failed."` is **not** on this list: that one upstream string
(`src/widgets/preferences.js:66`) was correctly restored into
`po/forge-sparks.pot` by `e0bd336` and remains there, confirmed by this
round's census. Only the three strings that re-entered the code *after*
`e0bd336` are missing.

## Extra — in the port, not upstream (not a parity failure, recorded per the skill's rule)

| Port msgid | Source | Note |
|---|---|---|
| `"Keyboard Shortcuts"` | `lib/shortcuts_dialog.rb:35`, dialog title | Upstream's `ShortcutsWindow` sets no title; the port invented one for `Adwaita::ShortcutsDialog`. Will render in English in every one of the 26 catalogues until translated, since no translator has seen it. |
| `"Print version information and exit"` | `lib/application.rb:116` | Upstream's identical-text CLI option description (`src/application.js:39`) is **not** wrapped in `_()` upstream — a bare string to `GLib.OptionEntry`, never in upstream's `.pot`. The port marked it translatable; upstream never did. |
| `"Start hidden"` | `lib/application.rb:125` | Same situation, `src/application.js:48`. |
| `"Could not read the saved access token"` | `lib/account_dialog.rb:243` | No upstream string at this call site — new error handling the port added, with a self-authored, never-translated message. |

## What did carry over cleanly

- All 26 `po/LINGUAS` locales, verified as a set.
- The primary menu's four mnemonic items and the banner's `Accounts` button
  label — byte-identical, spot-checked against `src/window.blp`.
- The shortcuts dialog's three `C_("shortcut window", …)` entries, including
  the pgettext context — spot-checked against `src/gtk/help-overlay.blp`.
- `"The request failed."` fires on the background row
  (`lib/preferences_dialog.rb:144`) and `"The autostart request failed."` —
  upstream's own string for the other two toggles
  (`src/widgets/preferences.js:109,146`) — fires on those two
  (`lib/preferences_dialog.rb:161,174`). Both are upstream's own bytes at
  the right call sites.
- Forge backend help text, relative-date plural forms (`n_`), account/forge
  strings — none appeared on either side of the `comm` diff beyond what is
  listed above, so they match.

## Rule followed

Per the skill, the port's `.pot` is never treated as correct over a fresh
census: this round re-ran the set comparison from current files rather than
trusting the previous pass's "3 gaps, down from 4" table, which is what
surfaced that the gap count is still 3 but for a materially different
reason — a catalogue that fell behind the code it is supposed to track,
not a behaviour that was never built. See `.reports/component-parity.md` for
the behaviour-level consequence and `.reports/accountability-ensurance.md`
for the false-green claim this produced in other reports.
