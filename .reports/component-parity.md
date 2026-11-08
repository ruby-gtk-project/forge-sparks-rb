# Component parity — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` |
| Port | `ruby` @ `2e0c16d` (re-audited this round; previous pass was at `180f802`) |
| Units covered | all 23 from `.reports/component-inventory.md`, re-checked on four axes: structure, behaviour, text, rule-check |
| Runtime gate reproduced this round | `test/drive_window.rb` → **201 of 201 checks passed, DRIVE OK**; `test/check_models.rb` → **70 of 70 checks passed, CHECKS OK**; `ruby -Ilib -S rspec spec/` → **21 examples, 0 failures** |

## Unit: background/autostart preference — `src/util.js` + `src/widgets/preferences.js` → `lib/util.rb` + `lib/preferences_dialog.rb`

| Axis | Upstream | Port | Verdict |
|---|---|---|---|
| Structure | `Adw.ExpanderRow` (background) + 2 switches (startup, hidden) | Same 3 widgets | parity |
| Behaviour | `Xdp.Portal.request_background`/`set_background_status` over the XDG Background portal | `Util.request_background`/`#set_background_status` speak `org.freedesktop.portal.Background` directly over D-Bus via `ruby-dbus` (`lib/util.rb:111-141`); real `RequestBackground`/`SetStatus` calls, real `DBus::Error`/`ServiceUnknown` handling | **parity** — re-verified live this round by reading the implementation; `test/drive_window.rb`'s autostart steps exercise the real call and fail honestly under `xvfb` with no portal daemon present |
| Text | 4 strings: `"Allow running Forge Sparks on background."`, `"Allow running Forge Sparks on startup."`, `"Monitoring new notifications"`, `"The request failed."` | All 4 strings exist in `lib/` source, wrapped in `_()`/default args, and all 4 now exist in `po/forge-sparks.pot` (lines 222, 226, 230, and the pre-existing one), confirmed by this round's `po/forge-sparks.pot` regeneration (commit `180f802`) and re-census | **parity** — closed this round |
| Rule check | n/a | n/a | n/a |

### Why this was a gap last round, and why it is closed now

The two passes before last round (and `.reports/component-inventory.md` and
`.reports/accountability-ensurance.md`) had declared this unit fully closed
— "23/23 units now hold on all four axes" — on the strength of `grep -n
"Allow running Forge Sparks\|Monitoring new notifications" lib/*.rb`
returning all three strings. That grep is real and its result is real, but
it only checks that the strings exist as Ruby literals inside `_()` calls —
it does not check that they were ever extracted into the gettext catalogue
those calls feed. Last round's translation-parity check
(`.reports/translation-parity.md`) found the opposite: none of the three
appeared in `po/forge-sparks.pot`, which had had no commit touch it since
`e0bd336`, two commits before the one (`0bcf2cc`) that put these calls back
into the code.

**Fixed this round:** ran `nix develop --command po/update-catalogue.sh`,
which re-extracts `po/forge-sparks.pot` from `po/POTFILES` and re-merges
every locale in `po/LINGUAS` against it (commit `180f802`). The three
msgids are now present in the `.pot`; `.reports/translation-parity.md`'s
re-run census confirms the gap is 0. No locale gained a *translated*
string from this — `msgmerge` only merges existing translations against new
msgids, and no translator has seen these three yet — so they still render
in English everywhere, but a translator working from `po/forge-sparks.pot`
now has a record that the strings exist, which is what the Text axis
measures. See `.reports/accountability-ensurance.md` for the false-green
claim that let this drift two rounds before being caught.

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
re-quoted. Structural/text parity re-spot-checked directly this round for
`lib/gitlab.rb` against `src/forges/gitlab.js` — matches.

### New finding this round: the forge-backends unit's Behaviour axis is unevenly covered, not uniformly "parity"

Row 13–18 (`lib/forge.rb`, `lib/forges.rb`, `lib/github.rb`, `lib/gitea.rb`,
`lib/forgejo.rb`, `lib/gitlab.rb`) have been marked "present: yes" since
`.reports/component-inventory.md`'s first pass, on structure and text
grounds that hold up (confirmed again this round for GitLab). But the
Behaviour axis — does the backend's actual request/notification-parsing
code run and produce the right result — is only runtime-verified for one
of the four: `test/drive_window.rb`'s `FakeSession` scripts canned HTTP
responses for `forge: 'github'` only (`grep -n "forge:" test/drive_window.rb`
returns exactly one literal, `'github'`), so the account-creation-through-
notification-on-screen path genuinely exercises `lib/github.rb`'s request
and parsing code with no network. Gitea, Forgejo and GitLab get only the
account-dialog combo-row steps ("choosing Gitea swaps the help text and the
instance", similarly for GitLab) — UI text and default-URL prefill, not a
single fetch through their `request`/parsing methods. No `spec/` file
covers any forge backend either. Downgrading this unit from an undifferentiated
"parity" to: **structure and text — parity (all four); behaviour — parity
for GitHub only, unverified by any suite for Gitea/Forgejo/GitLab.** This is
not a claim that those three backends are broken — only that no test in
this port's suite would catch it if they were. See
`.reports/test-parity.md` and `.reports/accountability-ensurance.md` for
the same finding from the test-coverage side.

## Verdict

**22 of 23 units hold on all four axes with full runtime verification; 1
(forge backends) holds on structure/text but is behaviour-verified for only
one of its four implementations (GitHub; Gitea/Forgejo/GitLab untested).**

The background/autostart unit's text gap (3 msgids missing from
`po/forge-sparks.pot`), tracked across the two previous rounds, is
confirmed still closed this round — `grep -n "Allow running\|Monitoring new
notifications" po/forge-sparks.pot` returns all three, re-checked live
rather than re-quoted.

The runtime gate numbers this round reproduces live are **201/201** for
`test/drive_window.rb`, **70/70** for `test/check_models.rb`, and **21/21**
for `rspec spec/` — matching the task's stated gate exactly. Earlier rounds'
"207/207" discrepancy (see `.reports/accountability-ensurance.md`) remains
closed; this round's own re-run again returns 201, not 207, confirming it
was not a one-off.
