# Translation parity — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` |
| Port | `ruby` @ `2e0c16d` (re-audited this round; previous pass of this file was at `180f802`) |
| Upstream msgids | 56 (unique `msgid` lines from `git show origin/main:po/com.mardojai.ForgeSparks.pot`, excluding the empty header) |
| Ported, present in `po/forge-sparks.pot` | 56 (of 56 upstream; `.pot` has 60 total, 4 are port-only, see Extra) |
| Gaps | 0 |
| Extra (not a gap, recorded) | 4 |
| Locales | 26 / 26, same set as `po/LINGUAS` (order differs, content doesn't) |

Census re-run fresh this round, not reused from the previous pass:
`git show origin/main:po/com.mardojai.ForgeSparks.pot` vs the current
`po/forge-sparks.pot`, `msgid` lines extracted and diffed as sorted sets
(`comm -23` / `comm -13`).

## Gaps — closed this round (previously 3)

The previous pass of this report found three upstream msgids used live in
`lib/util.rb` since `0bcf2cc` ("Bind the real XDG background portal over
D-Bus, write real specs") but never extracted into `po/forge-sparks.pot`,
because the commit that put the `_()` calls back in did not run
`po/update-catalogue.sh`:

| Upstream msgid | Source | Port call site |
|---|---|---|
| `"Allow running Forge Sparks on background."` | `src/util.js:58` | `lib/util.rb:112` |
| `"Allow running Forge Sparks on startup."` | `src/util.js:59` | `lib/util.rb:112` |
| `"Monitoring new notifications"` | `src/util.js:82` | `lib/util.rb:137` |

Fixed this round by running `nix develop --command po/update-catalogue.sh`
(commit `180f802`), which re-extracts `po/forge-sparks.pot` from the files
listed in `po/POTFILES` and re-merges every locale in `po/LINGUAS` against
it. `grep -n "Allow running\|Monitoring new notifications"
po/forge-sparks.pot` now returns all three msgids (lines 222, 226, 230), and
the `comm -23` diff against upstream's `.pot` that previously returned these
three lines now returns nothing — the gap is 0. No locale's `.po` gained a
translated string from this (`msgmerge` only merges existing translations
against new msgids), so these three still render in English pending actual
translation work, but they are now present in the catalogue translators
work from, which is the axis this report measures.

`"The request failed."` was already correct, confirmed again this round:
that one upstream string (`src/widgets/preferences.js:66`) was restored into
`po/forge-sparks.pot` by `e0bd336` and remains there.

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

## Re-verification this round

Re-ran the full `comm -23`/`comm -13` census fresh against current HEAD
(not reused): 0 gaps, same 4 extras as the previous pass, same 56/56
upstream msgids present. No `po/` commit landed between `180f802` and
`2e0c16d` (those two commits only touched `.reports/`), so an identical
result confirms the previous pass's number rather than merely repeating it.

## Rule followed

Per the skill, the port's `.pot` is never treated as correct over a fresh
census: this round re-ran the set comparison from current files rather than
trusting the previous pass's "3 gaps, down from 4" table, which is what
surfaced that the gap count is still 3 but for a materially different
reason — a catalogue that fell behind the code it is supposed to track,
not a behaviour that was never built. See `.reports/component-parity.md` for
the behaviour-level consequence and `.reports/accountability-ensurance.md`
for the false-green claim this produced in other reports.
