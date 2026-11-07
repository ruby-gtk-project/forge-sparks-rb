# Component identification — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` (GJS + Blueprint) |
| Port | `ruby` @ `3f45b15` |

This document records what Step 1 of the `component-identification` skill
found, scoped to re-verifying the existing `.reports/component-inventory.md`
(written by an earlier pass) rather than re-deriving it from zero — that file's
per-file widget/CSS/signal/action tables were spot-checked against upstream
source during this audit and are accurate as inventory. This document adds
what that inventory under-reports: components whose *behaviour*, not their
widget tree, differs from upstream, and one dependency that is declared but
never identified as a component owner at all.

## Confirmed present, 1:1, by direct scan (not merely by file existing)

- **Status icons** — upstream `src/icons/*.svg` (9 files: commit, discussion,
  issue, issue-done, merge, merge-denied, merge-draft, merge-merged, tag) all
  exist at `data/icons/*.svg` with identical basenames, and
  `lib/notification.rb:13` resolves them from that path — not just copied,
  wired.
- **`po/LINGUAS`** — same 26-locale set as upstream, order differs only
  (cosmetic, not a gap).
- **Primary menu** — `Gio::Menu` built in `lib/window.rb`, 5 items across 2
  sections, matching `window.blp`'s `menu menu`.
- **Shortcuts dialog** — `lib/shortcuts_dialog.rb`'s `SECTIONS` reproduces
  upstream's 3 `C_("shortcut window", …)` items byte-for-byte including the
  pgettext context (verified against `git show origin/main:src/gtk/help-overlay.blp`).

## New component found during this audit: the XDG background portal (missing)

Upstream's `src/util.js` (`requestBackground`, `setBackgroundStatus`) and
`src/widgets/preferences.js` (`_onBackgroundChanged`) together are one
component: the "keep running in the background" / "run on startup" toggle,
backed by `Xdp.Portal` (libportal), with its own 4 user-facing strings:

- `"Allow running Forge Sparks on background."`
- `"Allow running Forge Sparks on startup."`
- `"Monitoring new notifications"`
- `"The request failed."`

**The port builds no portal component.** `lib/util.rb:25-28` and
`lib/preferences_dialog.rb:15-20` both carry a comment stating upstream's
portal behaviour is replaced by writing an XDG autostart `.desktop` file
instead ("There is no portal binding for Ruby"), and
`lib/preferences_dialog.rb:167` raises a toast on failure with the msgid
`"The autostart request failed."` — a different string, a different
mechanism, no `Xdp.Portal` object anywhere in `lib/`.

This claim ("no portal binding for Ruby") is itself false: the gemspec
declares `ashpd` (`forge-sparks-rb.gemspec:110`), which **is** a Ruby binding
to the XDG Desktop Portal D-Bus API, added by the commit
"Wire in the gemspec's missing runtime dependencies and ashpd". `grep -rn
"ashpd\|Ashpd" lib/` returns nothing — the dependency is declared and never
required or called. See `.reports/accountability-ensurance.md`.

`Util.sandboxed?` (`lib/util.rb:79`, checks `/.flatpak-info`) is defined and
never called from anywhere in `lib/` or `test/` — dead code left over from
reasoning about the portal substitution, with no caller to act on its answer.

## Rule check

Per `component-identification` Step 4, enums/constants (`Util::APP_ID`,
`SECTIONS` keys) are not counted as widgets above; they are cited only where
they carry translatable text, per this skill's text-axis guidance.
