# Translation parity — forge-sparks

| | |
|---|---|
| Upstream | `main` @ `3df28d2` |
| Port | `ruby` @ `e0bd336` (re-audited; previous pass was at `3f45b15`) |
| Upstream msgids | 68 (unique `msgid` lines, excluding the empty header entry) |
| Ported, byte-identical | 65 |
| Gaps | 3 (was 4 at the previous pass) |
| Extra (not a gap, recorded) | 4 |
| Locales | 26 / 26, same set (`po/LINGUAS` diff is empty after sort — order differed, content did not) |

Census re-run this round: `git show origin/main:po/com.mardojai.ForgeSparks.pot`
vs current `po/forge-sparks.pot`, `msgid` lines extracted and diffed as
sorted sets (`comm -23` / `comm -13`). Commit `e0bd336` (since the previous
pass) changed this count: it restored one upstream msgid verbatim and
corrected which of the two "request failed" toasts fires for which toggle,
closing one of the four previous gaps.

## Gaps — in upstream, not in the port (3, down from 4)

| Upstream msgid | Source | Why it's missing |
|---|---|---|
| `"Allow running Forge Sparks on background."` | `src/util.js:58` | Belongs to the XDG background-portal permission request the port never calls — see `.reports/component-parity.md` |
| `"Allow running Forge Sparks on startup."` | `src/util.js:59` | same |
| `"Monitoring new notifications"` | `src/util.js:82` | `setBackgroundStatus`'s default message to the portal; no portal call exists to pass it to |

These three are not independent string losses; they are the one still-missing
behaviour (the background-portal permission request and status message) losing
its three strings together — see `.reports/component-parity.md` for why
`ashpd` 0.1.1 cannot close this.

## Closed since the previous pass

`"The request failed."` (`src/widgets/preferences.js:66`) was gap #4 in the
previous report, alongside the finding that the port's toast at that call
site used a different string, `"The autostart request failed."`, for all
three toggles. Commit `e0bd336` fixed both halves: `"The request failed."`
is now in `po/forge-sparks.pot` and fires on the background row
(`lib/preferences_dialog.rb:148`), and `"The autostart request failed."` —
upstream's own string for the *other* two toggles
(`src/widgets/preferences.js:109,146`) — now fires only on those two
(`lib/preferences_dialog.rb:161,174`). Re-verified this round: both msgids
are present in the current `.pot`, and reading the call sites confirms each
fires where upstream's does.

## Extra — in the port, not upstream (not a parity failure, recorded per the skill's rule)

| Port msgid | Source | Note |
|---|---|---|
| `"Keyboard Shortcuts"` | `lib/shortcuts_dialog.rb:35`, dialog title | Upstream's `ShortcutsWindow` sets no title; the port invented one for `Adwaita::ShortcutsDialog`. Harmless but will render in English for every one of the 26 catalogues until someone translates it, since no translator has ever seen this string. |
| `"Print version information and exit"` | `lib/application.rb:116` | Upstream's identical-text CLI option description (`src/application.js:39`) is **not** wrapped in `_()` upstream — it is a bare string handed to `GLib.OptionEntry`, never extracted into upstream's `.pot`. The port marked it translatable; upstream never did. |
| `"Start hidden"` | `lib/application.rb:125` | Same situation as above, `src/application.js:48`. |
| `"Could not read the saved access token"` | `lib/account_dialog.rb:243` | No upstream string at this call site at all — appears to be new error handling the port added (good), with a self-authored, never-translated message. |

Note: `"The autostart request failed."` (`lib/preferences_dialog.rb:161,174`)
was listed here as an extra/reword in the previous pass of this report. It is
**not** extra: it is upstream's own string
(`src/widgets/preferences.js:109,146`), present in both this round's census
sets, so it belongs in neither the gap table nor this one. Corrected below
under "What changed since the previous pass."

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

## What changed since the previous pass

The previous pass of this report treated `"The autostart request failed."`
and `"The request failed."` as a reword pair: one upstream string
(`"The request failed."`) missing, replaced in the port by a different
sentence used for all three toggles. That was correct at the time (`3f45b15`)
but is wrong now: `e0bd336` split the port's single reused string back into
upstream's original two, each at the toggle it belongs to. Both strings are
now upstream's own bytes, at the right call sites — not a gap, not an extra,
just carried over correctly. The gap count drops from 4 to 3 and the extra
table loses the row that was standing in for it.

## Rule followed

Per the skill, the port's bytes are never treated as correct over upstream's
without checking: this round's set comparison was re-run from current files
rather than reusing the previous pass's table, which is what caught that one
row needed removing rather than merely re-stating.
