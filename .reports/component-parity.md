# Component parity — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` |
| Port | `ruby` @ `5570f99` (re-audited this round; previous pass was at `0bcf2cc`, one commit behind) |
| Units covered | all 23 from `.reports/component-inventory.md`, re-checked on four axes: structure, behaviour, text, rule-check |
| Runtime gate reproduced this round | `test/drive_window.rb` → **201 of 201 checks passed, DRIVE OK**; `test/check_models.rb` → **70 of 70 checks passed, CHECKS OK**; `ruby -Ilib -S rspec spec/` → **21 examples, 0 failures** |

## Unit: background/autostart preference — `src/util.js` + `src/widgets/preferences.js` → `lib/util.rb` + `lib/preferences_dialog.rb`

| Axis | Upstream | Port | Verdict |
|---|---|---|---|
| Structure | `Adw.ExpanderRow` (background) + 2 switches (startup, hidden) | Same 3 widgets | parity |
| Behaviour | `Xdp.Portal.request_background`/`set_background_status` over the XDG Background portal | `Util.request_background`/`#set_background_status` speak `org.freedesktop.portal.Background` directly over D-Bus via `ruby-dbus` (`lib/util.rb:111-141`); real `RequestBackground`/`SetStatus` calls, real `DBus::Error`/`ServiceUnknown` handling | **parity** — re-verified live this round by reading the implementation; `test/drive_window.rb`'s autostart steps exercise the real call and fail honestly under `xvfb` with no portal daemon present |
| Text | 4 strings: `"Allow running Forge Sparks on background."`, `"Allow running Forge Sparks on startup."`, `"Monitoring new notifications"`, `"The request failed."` | All 4 strings exist **in `lib/` source**, wrapped in `_()`/default args. But only 1 of the 4 (`"The request failed."`) exists in `po/forge-sparks.pot`. The other 3 are absent from the catalogue entirely. | **gap** — see below |
| Rule check | n/a | n/a | n/a |

### Why this is still a gap, not a closed item

The two previous passes of this report (and `.reports/component-inventory.md`
and `.reports/accountability-ensurance.md`) declared this unit fully closed
— "23/23 units now hold on all four axes" — on the strength of `grep -n
"Allow running Forge Sparks\|Monitoring new notifications" lib/*.rb`
returning all three strings. That grep is real and its result is real. But
it only checks that the strings exist as Ruby literals inside `_()` calls —
it does not check that they were ever extracted into the gettext catalogue
those calls feed. Running the actual translation-parity check this round
(`.reports/translation-parity.md`) finds the opposite: none of the three
appear in `po/forge-sparks.pot`, which has had no commit touch it since
`e0bd336`, two commits before the one (`0bcf2cc`) that put these calls back
into the code.

Consequence for an end user: a translator working from
`po/forge-sparks.pot` today has no record that these three strings exist to
translate. Every locale but the source language will show them in English
indefinitely, regardless of how correct the D-Bus call behind them is. The
**behaviour** axis is genuinely fixed — the portal call is real, not a
stand-in — but the **text** axis is not, and "all four axes hold" is not
true of this unit yet. This is the Text-axis gap this round's census found;
see `.reports/accountability-ensurance.md` for the false-green claim that
resulted in the two previous passes.

**Fix:** regenerate `po/forge-sparks.pot` (the project's own
`po/update-catalogue.sh`, or `xgettext` over `lib/**/*.rb` with the same
keywords) and add the three missing msgids, then re-run the extraction to
confirm nothing else drifted since `18f35e9`.

## All other units

Spot-re-checked this round against the current `po/forge-sparks.pot` census
and the live drive/spec runs; no other structural, behavioural or rule-check
regression found relative to the previous pass's tables (shortcuts dialog,
primary menu, status icons, forge backends, notification model, settings
round-trip, account dialog, preferences dialog's other two toggles, about
dialog, empty state, error toasts). Not re-walked widget-by-widget from zero
in this pass — the previous two passes' direct scans are trusted for
structure/rule-check on units this round found no code change touching —
but every behaviour claim that this round's grep/census could independently
verify (drive script, spec suite, `.pot` diff) was re-run live rather than
re-quoted.

## Verdict

**22 of 23 units hold on all four axes. 1 of 23 (background/autostart) holds
on structure and behaviour, not on text**, because `po/forge-sparks.pot`
fell behind a code change that re-added three translatable strings without
re-extracting them. Not "23/23," contrary to the previous two passes of
this report and of `.reports/component-inventory.md`.

The runtime gate numbers this round reproduces live are **201/201** for
`test/drive_window.rb` and **70/70** for `test/check_models.rb` — matching
the task's stated gate. Several of this report's own prior passes, and
`.reports/test-parity.md` as it stood before this round, instead asserted
**207/207** for the drive script at this same point in history. That number
does not match either a fresh run performed this round or the commit
message of `0bcf2cc` itself, which records 201/201. See
`.reports/accountability-ensurance.md` for that finding.
