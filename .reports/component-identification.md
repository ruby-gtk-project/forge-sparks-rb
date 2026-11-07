# Component identification — forge-sparks

| | |
|---|---|
| Upstream | `origin/main` @ `3df28d2` (GJS + Blueprint) |
| Port | `ruby` @ `5570f99` (re-audited; previous pass was at `e0bd336`, two commits behind) |

This document re-verifies `.reports/component-inventory.md`'s per-file
widget/CSS/signal/action tables against upstream source rather than
re-deriving the inventory from zero, and records what has changed in the
two commits (`0bcf2cc`, `5570f99`) landed since the previous pass of this
file.

## Confirmed present, 1:1, by direct scan

- **Status icons** — upstream `src/icons/*.svg` (9 files) all exist at
  `data/icons/*.svg` with identical basenames, wired from
  `lib/notification.rb:13`.
- **`po/LINGUAS`** — same 26-locale set as upstream (order differs only).
- **Primary menu** — `Gio::Menu` in `lib/window.rb`, 5 items across 2
  sections, matching `window.blp`'s `menu menu`.
- **Shortcuts dialog** — `lib/shortcuts_dialog.rb`'s `SECTIONS` reproduces
  upstream's 3 `C_("shortcut window", …)` items byte-for-byte including the
  pgettext context.
- **Background/autostart preference widgets** — `Adw.ExpanderRow` +
  2 switches in both upstream (`src/widgets/preferences.js`) and the port
  (`lib/preferences_dialog.rb`); same structural shape, confirmed again
  this round.

## What changed since the previous pass: the background portal is now a real D-Bus component

The previous pass of this document found that upstream's background-portal
component (`src/util.js`'s `requestBackground`/`setBackgroundStatus`,
backed by `Xdp.Portal`) had **no port at all** — the port's substitute was
hide-on-close plus an XDG autostart `.desktop` file, with `ashpd` 0.1.1 (the
gemspec's declared binding) confirmed live to lack a `Background` portal
interface (`Ashpd.constants` has no `Background`).

Commit `0bcf2cc` ("Bind the real XDG background portal over D-Bus, write
real specs"), landed since, replaces that substitute. `lib/util.rb:111-180`
now talks to `org.freedesktop.portal.Background` directly over D-Bus via
`ruby-dbus` (`DBus::SessionBus.instance`, `RequestBackground`/`SetStatus`
method calls with real `DBus::Error`/`ServiceUnknown` handling), and
`ashpd` is gone from the gemspec entirely (`grep -rn ashpd *.gemspec`
confirms it only in comments, no `add_dependency` line). This audit
re-read the implementation this round: it is a genuine binding, not a
second substitute dressed differently — `test/drive_window.rb`'s autostart
steps now exercise the real D-Bus call and fail honestly
(`DBus::Error`/`ServiceUnknown`) under `xvfb` with no portal daemon present,
rather than asserting a filesystem side effect.

**This closes the behavioural gap this report previously tracked.** It
does **not** close the component fully: see the finding below.

## New finding this round: the component's text did not travel with its behaviour

`lib/util.rb:112` and `:137` now contain, as live `_()`-wrapped Ruby
literals, upstream's three background-portal strings
(`"Allow running Forge Sparks on background."`,
`"Allow running Forge Sparks on startup."`, `"Monitoring new
notifications"`). But `po/forge-sparks.pot` has had no commit touch it
since `e0bd336` — two commits before `0bcf2cc` put these strings back into
the code — and a direct `grep` against the current `.pot` confirms none of
the three are in it. `_()` marking a string translatable does not add it to
the catalogue; that requires re-running extraction, which did not happen
here. This is a real gap in the component's Text axis, open right now, not
a historical one — see `.reports/translation-parity.md` and
`.reports/component-parity.md` for the full account, and
`.reports/accountability-ensurance.md` for the false-green claim ("23/23 on
all four axes") this produced in two other reports that checked the code
but not the catalogue.

`Util.sandboxed?` (checks `/.flatpak-info`) remains wired into
`Util.request_background`/`Util.request_autostart`'s sandboxed-refusal path,
confirmed unchanged this round.

## Rule check

Per `component-identification` Step 4, enums/constants (`Util::APP_ID`,
`SECTIONS` keys) are not counted as widgets above; they are cited only
where they carry translatable text, per this skill's text-axis guidance.
This round's finding above is exactly that axis — a case where the widget
tree and behaviour axes closed but the text axis, checked against the
actual `.pot` rather than the source files, did not.
