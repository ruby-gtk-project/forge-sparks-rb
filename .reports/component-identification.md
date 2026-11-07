# Component identification — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` (GJS + Blueprint) |
| Port | `ruby` @ `e0bd336` (re-audited; previous pass was at `3f45b15`) |

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

**The port builds no portal component.** `lib/util.rb:15-33` and
`lib/preferences_dialog.rb:15-30` both carry a comment stating upstream's
portal behaviour is replaced: "keep running in the background" is the
window's own hide-on-close, and "run on startup" writes an XDG autostart
`.desktop` file instead of asking `Xdp.Portal`. Since the previous pass of
this audit (`3f45b15`), commit `e0bd336` rewrote this comment and the claim
it makes changed from false to verified-true: it now says `ashpd` 0.1.1 (the
gemspec dependency) was checked live — `Ashpd.constants` on the installed
gem returns only `Account, Camera, OpenUri, Screenshot, Settings, Trash,
VERSION`, no `Background` — and cites that as the reason the gem is not
required anywhere in `lib/`. This audit reran that exact check
(`nix develop --command ruby -e "require 'ashpd'; puts Ashpd.constants.sort"`)
and confirms it: the gem genuinely cannot bind the background portal. The
dependency is still declared in the gemspec and still never `require`d in
`lib/` — a dead dependency, not a false claim about one — see
`.reports/accountability-ensurance.md` for whether that residue is worth
removing.

`Util.sandboxed?` (`lib/util.rb:83`, checks `/.flatpak-info`) was dead code
with no caller as of `3f45b15`. `e0bd336` wired it in:
`Util.request_autostart` (`lib/util.rb:103-108`) now refuses outright and
warns when `sandboxed?` is true, instead of reporting a no-op file write as
a granted request. That specific finding from the previous pass is closed.

What remains unported, regardless of the ashpd finding above: upstream's
`requestBackground`'s two permission-reason strings and `setBackgroundStatus`'s
status message have no equivalent call site in the port at all, because the
substitute mechanism (hide-on-close + an autostart file) never asks for
background permission or reports a running-in-background status to
anything. That is a real, still-open behavioural gap, tracked in
`.reports/component-parity.md` and `.reports/translation-parity.md` — it
did not close when the dead-code and false-comment issues did.

## Rule check

Per `component-identification` Step 4, enums/constants (`Util::APP_ID`,
`SECTIONS` keys) are not counted as widgets above; they are cited only where
they carry translatable text, per this skill's text-axis guidance.
