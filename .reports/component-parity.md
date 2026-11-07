# Component parity — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` |
| Port | `ruby` @ `3f45b15` |
| Units with full 4-axis parity | 22 / 23 |

Built on `.reports/component-inventory.md`'s per-file tables (count/CSS/signal
axes already checked there and spot-verified here) plus this audit's own
Step 5 (drive) and text-axis work. 22 of the 23 upstream units hold on all
four axes. One does not.

## Unit: background/autostart preference — `src/util.js` + `src/widgets/preferences.js` → `lib/util.rb` + `lib/preferences_dialog.rb`

| Axis | Upstream | Port | Verdict |
|---|---|---|---|
| Count | `Adw.ExpanderRow` (background), 2 switches (startup, hidden) | Same 3 widgets | parity |
| Style | `show-enable-switch`, `expanded: true` | same | parity |
| **Behaviour** | Toggling asks `Xdp.Portal` (real XDG background portal); grants autostart only if the portal says yes; `setBackgroundStatus` tells the portal what message to show while running | Toggling writes/removes an XDG autostart `.desktop` file; no portal call anywhere | **gap** |
| **Text** | `"Allow running Forge Sparks on background."`, `"Allow running Forge Sparks on startup."`, `"Monitoring new notifications"`, `"The request failed."` | None of the four exist in the port (`lib/`, `po/forge-sparks.pot`); the port's own failure toast uses a different, unported string `"The autostart request failed."` | **gap** |

This is not a cosmetic substitution. In a sandboxed install (Flatpak), upstream
asks the portal and gets an honest allow/deny; the port's autostart-file write
is documented by its own author comment as having "no effect" in that
environment (`lib/util.rb:26`), yet `Util.request_autostart` still reports
`true` on a successful file write regardless of sandbox state —
`Util.sandboxed?` is defined (`lib/util.rb:79`) and never consulted. The port
can therefore tell a sandboxed user their "run in background" toggle
succeeded when it did nothing. The port is not currently packaged as a
Flatpak (no manifest under `data/`), which is why the drive script never
catches this — it drives the port against itself, not against the
sandbox case upstream designed for.

**Row location:** `lib/util.rb:25-28,79-99`, `lib/preferences_dialog.rb:15-20,127-168`.
**Behaviour still owed:** either a real portal binding (`ashpd` is already a
declared dependency, unused — see `.reports/accountability-ensurance.md`) or,
if the autostart-file substitute is kept, the toggle must consult
`Util.sandboxed?` and refuse/warn instead of reporting false success, and the
toast strings must be reconciled with upstream's or recorded as deliberate
and translated independently.

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
