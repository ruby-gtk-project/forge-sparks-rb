# Component parity — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` |
| Port | `ruby` @ `e0bd336` (re-audited; previous pass was at `3f45b15`) |
| Units with full 4-axis parity | 22 / 23 |

Built on `.reports/component-inventory.md`'s per-file tables (count/CSS/signal
axes already checked there and spot-verified here) plus this audit's own
Step 5 (drive) and text-axis work. 22 of the 23 upstream units hold on all
four axes. One does not — unchanged from the previous pass's bottom line,
though the shape of what's wrong with that one unit has changed: commit
`e0bd336` ("Fix the background-portal toast text and the sandboxed autostart
lie") landed since and fixed two of the four sub-findings below. It did not,
and by its own commit message could not, close the unit itself.

## Unit: background/autostart preference — `src/util.js` + `src/widgets/preferences.js` → `lib/util.rb` + `lib/preferences_dialog.rb`

| Axis | Upstream | Port | Verdict |
|---|---|---|---|
| Count | `Adw.ExpanderRow` (background), 2 switches (startup, hidden) | Same 3 widgets | parity |
| Style | `show-enable-switch`, `expanded: true` | same | parity |
| **Behaviour** | Toggling asks `Xdp.Portal` (real XDG background portal); grants autostart only if the portal says yes; `setBackgroundStatus` tells the portal what message to show while running | Toggling writes/removes an XDG autostart `.desktop` file; no portal call anywhere, because `ashpd` 0.1.1 (the gem this fork's policy requires) has no `Background` portal binding at all, verified live this audit via `Ashpd.constants` | **gap, but now honestly bounded** — see below |
| **Text** | `"Allow running Forge Sparks on background."`, `"Allow running Forge Sparks on startup."`, `"Monitoring new notifications"`, `"The request failed."` | 1 of 4 restored (`"The request failed."`, `lib/preferences_dialog.rb:148`); the other 3 still don't exist anywhere in `lib/` or `po/forge-sparks.pot` | **gap, reduced from 4 strings to 3** |

**What changed since the previous pass (`3f45b15`):** commit `e0bd336`
("Fix the background-portal toast text and the sandboxed autostart lie")
fixed two distinct sub-bugs this report previously called out:

1. **The false-success report is gone.** `Util.sandboxed?` is now consulted
   by `Util.request_autostart` (`lib/util.rb:103-108`): a request made while
   sandboxed now refuses up front and warns, rather than reporting a no-op
   autostart-file write as a granted request. Re-read live this audit —
   confirmed.
2. **The toast-string reword is gone.** `"The request failed."` is restored
   verbatim for the background row (`lib/preferences_dialog.rb:148`), and
   `"The autostart request failed."` is now used *only* for the two
   autostart-specific toggles (`lib/preferences_dialog.rb:161,174`), matching
   upstream's `src/widgets/preferences.js:73,109,146` exactly — both the
   message and which of the three toggles each one belongs to.

**What did not change, and is not fixable by a comment or a flag:** the
background permission request and the "Monitoring new notifications"
status message are portal-only behaviour with no non-portal substitute
upstream defines, and `ashpd` 0.1.1 cannot bind that portal (confirmed live:
`Ashpd.constants` has no `Background`). So three upstream strings and the
one behaviour that would carry them still have no port, not because of an
undocumented lie this time, but because the dependency the fork committed to
cannot do the job. That is still a parity gap — the unit is still 22/23, not
23/23 — but it is no longer a case of the report believing something false;
it is a case of a real, currently-unresolvable hole, which is a different
finding to act on (swap or extend the binding gem, or hand-roll the D-Bus
call) than "wire up the gem that's already there."

**Row location:** `lib/util.rb:15-33,83-119`, `lib/preferences_dialog.rb:15-30,136-196`.
**Behaviour still owed:** a background-portal binding this gem doesn't
provide — either a different/newer `ashpd` release, a different gem, or a
hand-rolled D-Bus call to `org.freedesktop.portal.Background` — to carry the
three remaining strings and the real allow/deny semantics. Until then, this
is an accurate, bounded gap rather than a lie about one; it is still not
parity.

## The other 22 units

Window, shortcuts dialog, application/actions/About, account dialog, accounts
dialog, accounts manager, forge backends (×4), notification model,
notification row, notifications list, preferences dialog's own
startup/hidden rows (as distinct from the background-portal call above),
settings, style, main entry point, translation module: count, CSS, signal and
text axes hold under both a static read of the per-file tables and this
audit's live drive (`test/drive_window.rb`, 207/207 checks; `test/check_models.rb`,
70/70 checks — both re-run during this audit, not taken on faith).

Screenshot step confirms rendering for the units the driver shoots
(`09-shortcuts.png`, `10-primary-menu.png`, `11-about.png`, etc. under the
driver's `shots` dir) — not re-captured in this pass since the driver's own
checks against those widgets already passed live.

## Verdict

**Not clean.** One unit (background/autostart) fails the behaviour and text
axes. 22/23 is not 23/23; nothing in `PORTING.md` or the existing inventory
is authority to call it done, and the inventory's own "No gaps remain at the
file/component level" line (top of `.reports/component-inventory.md`) is
contradicted by this finding — flagged again in
`.reports/accountability-ensurance.md`.
