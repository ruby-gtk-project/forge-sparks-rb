# Forge Sparks — upstream component inventory

Upstream: `origin/main` (GJS + blueprint, meson, gjspack bundler).
Port: the `ruby` branch of this repo.

**State of the port (re-surveyed on the current `ruby` HEAD, commit
`18f35e9`).** All 23 upstream components now have a port file. The two gaps
the previous survey found are both closed:

1. **`po/` — ported.** `lib/translation.rb` binds the `forge-sparks` text
   domain and hands out `_`/`n_`/`p_`; `po/` holds the `.pot`, upstream's
   full 26-locale `LINGUAS` set and `po/update-catalogue.sh`, which extracts,
   merges and compiles into `data/locale` (not committed, built by the dev
   shell). `relativeDate`'s plural forms go through `n_`.
2. **Packaging data — ported.** `data/org.rubygtkproject.ForgeSparks.desktop.in`,
   `.metainfo.xml.in` and `.service.in` exist alongside the nine status icons,
   the empty-state illustration and the app icons; the flake installs and
   validates the desktop entry and compiles the 26 catalogues.

No gaps remain at the file/component level. Two commits since the previous
survey (`42e7519` → `df72503` → `18f35e9`) also fixed three defects a drive
script found (account-row activation signal, an async error type that crashed
the process, and a driver re-run bug) and extended the drive script to 207
checks — DRIVE OK, CHECKS OK (70).

**Update (`0bcf2cc`, this round's starting point):** the behaviour gap this
report's "Present: yes" for `lib/util.rb` was once at odds with (see
`.reports/accountability-ensurance.md`'s Finding 1) is closed —
`Util.request_background`/`#set_background_status` now bind the real XDG
background portal over D-Bus, so "Present: yes" for that row is no longer
just file-existence, it is behaviour parity too. The drive script's check
count changed shape to 201 (the autostart steps now exercise a real D-Bus
call, not a file-write stand-in) — still 0 failed.

**Correction, this round:** the behaviour is fixed but `po/forge-sparks.pot`
was never re-extracted to add the three strings `0bcf2cc` put back into
`lib/util.rb`, so the unit is not fully closed — see
`.reports/component-parity.md` (now 22/23 on all four axes, not 23/23) and
`.reports/accountability-ensurance.md` Finding 1. The 207-checks figure
quoted earlier in this document (around commit `18f35e9`) predates the
autostart rewrite and is not the current count; 201 is current and
reproduced, see `.reports/test-parity.md` Finding on the 207-vs-201
discrepancy.

Scan corroborating the reading below (clean `git archive origin/main`,
`component-identification/scripts/component-scan.sh`, re-run for this
survey): 141 rows, 39 distinct widget types, 16 distinct CSS classes, 8
distinct signals, 17 distinct actions. The port's own scan of `lib/`: 116
rows — fewer because the scan counts static declarations and the port's
widgets of the same type collapse into one row per file where upstream's
equivalent is split across a `.js`/`.blp` pair; it is not a gap count (see
the per-file tables below, each already checked against upstream).

Upstream is a two-file-per-component GJS app: each widget class is a `.js`
beside its `.blp`, and the port merges the pair into one `lib/*.rb`. House
shape follows the pilot at `gnome-contacts-rb`: flat `lib/<thing>.rb`, one
upstream source file per file, `# frozen_string_literal: true`, `require
'adwaita'`, a comment naming the upstream file, memoized widget accessors
assembled in `build` with `.tap`.

---

## src/window.js + src/window.blp → `lib/window.rb` — the main window

`Adw.ApplicationWindow`, 500×500 default, 360×200 minimum, title "Forge
Sparks", `notify::visible => _onWindowHide` (sets the portal background status
when hidden). One `Gtk.Stack mainStack` with CSS `main-view` and three pages —
`setup`, `loading`, `notifications` — switched in code.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | `devel` (only when the app id ends in `Devel`) | `notify::visible` → `_onWindowHide` | `hide_on_close` driven by the `hide-on-close` setting |
| `Gtk.Stack` | 3 | `main-view` (mainStack only) | — | mainStack, notificationsStack, markAsReadIcon |
| `Adw.ToolbarView` | 2 | — | — | setup page, notifications page |
| `Adw.HeaderBar` | 2 | — | — | both `show-title: false` |
| `Gtk.MenuButton` | 2 | — | — | `primary: true`, `open-menu-symbolic`, tooltip "Main Menu", `menu-model: menu` |
| `Adw.StatusPage` (`setupPage`) | 1 | — | — | "Welcome to Forge Sparks" / "Add an account to receive notifications from"; `icon_name` set to the app id in code |
| `Gtk.Button` "Add Account…" | 1 | `suggested-action`, `pill` | `clicked` → `_onNewAccount` | opens `AccountDialog(nil)` |
| `Gtk.WindowHandle` | 1 | — | — | loading page |
| `Adw.Spinner` | 2 | — | — | 64×64 loading spinner; 16×16 in the mark-as-read button |
| `Gtk.Button markAsRead` | 1 | `flat` | `clicked` → `markAsReadAll` | `labelled-by: markAsReadLabel`; visible only when the model is non-empty; made insensitive while running |
| `Gtk.Image` | 1 | — | — | `object-select-symbolic`, the `icon` page of `markAsReadIcon` |
| `Gtk.Label markAsReadLabel` | 1 | — | — | "Mark all as Read" |
| `Adw.Banner accountBanner` | 1 | — | — | button-label "Accounts", `action-name: app.accounts`; title set to "Account %s authentication failed!" + "The token may have been revoked or expired."; revealed/unrevealed by `_resolveTokenError` |
| `Adw.Clamp` | 2 | `margin-box` (list page) | — | max 400 on the empty page |
| `Gtk.Picture emptyPicture` | 1 | — | — | `can-shrink`, resource `src/assets/alldone.svg` |
| `Gtk.Label noNotificationsLabel` | 1 | `title-1` | — | "No Notifications to Show", wrapped, centre-justified |
| `Gtk.ScrolledWindow` | 1 | — | — | `hscrollbar-policy: never` |
| `Gtk.ListBox notificationsList` | 1 | `content`, `margin-box` | — | `selection-mode: none`, `valign: start`, `bind_model` over the sorted model |
| `Gtk.Box` | 3 | — | — | loading box, mark-as-read box, empty-state box |

Non-widget behaviour in the same file: `Gtk.SortListModel` + `Gtk.NumericSorter`
over a `Gtk.PropertyExpression` on `timestamp`, descending; the 60-second
`GLib.timeout_add_seconds` polling loop (`subscribe`/`reload`, with `fetching`
and `reFetch` guards); the first-run background-portal request; the
`forge-sparks-error-auth` desktop notification (title + body, default action
`app.activate`, button "Accounts" → `app.accounts`); the `notified` dict
persisted into the `notified` GSettings key; `resolveNotification` and
`markAsReadAll`.

Repeater: `_createNotificationRow` — one `NotificationRow` per sorted model
item, `activatable: true`, `account` set only when more than one account
exists, `activated` → set `progress`/insensitive and fire
`app.open-notification` with `(id, url)`.

Actions referenced: `app.preferences`, `app.accounts`, `win.show-help-overlay`,
`app.about`, `app.quit` (menu), `app.accounts` (banner),
`app.open-notification` (rows).

Also in `window.blp`: the primary `menu menu` — section one with
`_Preferences`, `_Accounts`, `_Keyboard Shortcuts`, "About Forge Sparks";
section two with "Quit". Five items, no `custom:` slots. Port it as a
`Gio::Menu` built in `lib/window.rb`.

Present: **yes**.

## src/gtk/help-overlay.blp → `lib/shortcuts_dialog.rb` — keyboard shortcuts

A standalone declarative object with no backing source file: `ShortcutsWindow
help_overlay { modal: true }`, one `ShortcutsSection` (`section-name:
"shortcuts"`, `max-height: 10`), one `ShortcutsGroup` titled "General", three
`ShortcutsShortcut`s: `F10` "Open menu", `<ctrl>question` "Keyboard shortcuts",
`<ctrl>Q` "Quit". Loaded by `window.js` via `Gtk.Builder.new_from_resource` and
installed with `set_help_overlay`, which is what makes
`win.show-help-overlay` work.

The pilot ports this shape as an `Adwaita::ShortcutsDialog` with
`Adwaita::ShortcutsSection`/`ShortcutsItem` (see
`gnome-contacts-rb/lib/shortcuts_dialog.rb` — items take **positional**
arguments).

Present: **yes**.

## src/application.js → `lib/application.rb` — the application, its actions and About

Not a widget class, but it owns the actions, the accelerators and the About
dialog, so it is its own unit.

| Component | Detail |
|---|---|
| `Adw.Application` | application id = package name; `Adw.AboutDialog` on `app.about` |
| Actions (`Gio.SimpleAction`) | `activate`, `about`, `preferences`, `accounts`, `quit`, `close`, `open-notification` (param `as`), `mark-read` (param `s`), `reload` — 9 app actions |
| Accelerators | `app.quit`=`<Primary>q`, `app.close`=`<Primary>w`, `app.preferences`=`<Primary>comma`, `app.accounts`=`<Primary><Shift>a`, `app.reload`=`<Primary>r`, `win.open-primary-menu`=`F10`, `win.show-help-overlay`=`<Primary>question` |
| `Adw.AboutDialog` | developers ["Rafael Mardojai CM"], `translator_credits` (translated), application name from `GLib.get_application_name`, comments "Get Git forges notifications", application icon = app id, version, copyright "Copyright 2022 Rafael Mardojai CM", `Gtk.License.MIT_X11` |
| Dialog singletons | `_showPrefs` / `_showAccounts` keep one instance each, cleared on `closed` |
| `Gtk.UriLauncher` | `_openNotification` launches the URL, then marks the notification read on success; parent is nil when the window hides on close |
| `_markAsRead` | resolves the notification named by the `mark-read` target |
| CLI | `--version` / `-v`, `--hidden` / `-h` via `handle_local_options`; `--hidden` starts the window invisible and calls `_onWindowHide` |

Occupying the path today: the generated `lib/forge_sparks/application.rb`
scaffold (status page, five widgets). It must be replaced, and the mapping
flattened to `lib/application.rb` beside its siblings, with
`lib/forge_sparks.rb` requiring it.

Present: **yes** — `lib/application.rb` (307 lines); the generated
`lib/forge_sparks/application.rb` scaffold is gone and `lib/forge_sparks.rb`
is a four-line requirer.

## src/widgets/accountDialog.js + .blp → `lib/account_dialog.rb` — add/edit an account

`Adw.Dialog`, title "Add Account" → "Edit Account" when the `editing` property
is set, `content-width: 360`, `follows-content-size`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` | 1 | — | `notify::editing` → `_onEditing` | title and save label swap in edit mode |
| `Adw.ToolbarView` | 1 | — | — | |
| `Adw.HeaderBar` | 1 | — | — | both title-button sets hidden |
| `Adw.WindowTitle titleWidget` | 1 | — | — | title bound to the dialog title; subtitle = account display name when editing |
| `Gtk.Button cancelBtn` | 1 | — | `clicked` → `_onCancel` | "Cancel" |
| `Gtk.Button saveBtn` | 1 | `suggested-action` | `clicked` → `_onSave` | "Add" / "Save"; `sensitive: false` until validation passes |
| `Adw.ToastOverlay toasts` | 1 | — | — | hosts "Invalid instance url.", "Couldn’t authenticate the account", "The access token doesn’t have the needed scopes", "Unexpected error when creating the account", "Unexpected error removing the account" |
| `Adw.PreferencesPage page` | 1 | — | — | made insensitive while a request is in flight |
| `Adw.PreferencesGroup` | 2 | — | — | second one visible only when `editing` |
| `Adw.ComboRow forge` | 1 | — | `notify::selected` → `_onForgeChanged` | "Forge"; hidden when editing; `Gtk.StringList` of the four forges' `prettyName` |
| `Adw.EntryRow instance` | 1 | `error` (added/removed dynamically on URL validation) | `notify::text` → `_onEntryChanged`, `_onInstanceChanged` | "Instance URL"; visible only when the forge allows instances; prefilled with the forge default unless the user typed |
| `Adw.PasswordEntryRow accessToken` | 1 | — | `notify::text` → `_onEntryChanged` | "Access Token" |
| `Gtk.Label accessTokenHelp` | 1 | — | — | markup, wrapped, `xalign: 0`; per-forge `tokenText` |
| `Gtk.Button removeAccount` | 1 | `destructive-action`, `pill` | `clicked` → `_onRemoveAccount` | "Remove Account"; edit mode only |

Behaviour: URL normalisation (forces `https://`, `GLib.Uri.parse` with
`RELAXED`, strips a leading `www.`), the save-button sensitivity rules for both
the create and the edit path, token load from the secret store when editing,
and firing `app.reload` after add/update/remove.

Present: **yes**.

## src/widgets/accountsDialog.js + .blp → `lib/accounts_dialog.rb` — the accounts list

`Adw.Dialog` "Accounts", `content-width: 360`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` | 1 | — | — | |
| `Adw.ToolbarView` + `Adw.HeaderBar` | 1 + 1 | — | — | |
| `Gtk.Button` + `Adw.ButtonContent` | 1 + 1 | `flat` | `clicked` → `_onOpenAddAccount` | "Add…", `list-add-symbolic`; presents `AccountDialog(nil)` |
| `Gtk.ScrolledWindow` | 1 | — | — | propagates natural width and height |
| `Adw.Clamp` | 1 | `margin-box` | — | |
| `Gtk.Stack accountsStack` | 1 | — | — | `vhomogeneous: false`; `empty` / `accounts`, switched on `items-changed` |
| `Adw.StatusPage` | 1 | `compact` | — | "No Accounts" / "Add an account to receive notifications from" |
| `Gtk.ListBox accountsList` | 1 | `content` | — | `selection-mode: none`, `valign: start`, `bind_model` over the accounts manager |

Repeater — `_createAccountRow`, one per saved account, built in source, not in
the blueprint: `Adw.ActionRow` (`activatable: true`, title bound to
`display-name` with `SYNC_CREATE`), suffix `Gtk.Image dialog-error-symbolic`
with CSS `error` and tooltip "Account authentication failed!" bound to
`auth-failed`, suffix `Gtk.Image go-next-symbolic`, `activated` → present
`AccountDialog(account)`.

Present: **yes**.

## src/widgets/preferences.js + .blp → `lib/preferences_dialog.rb` — preferences

`Adw.PreferencesDialog`, one page, one group.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.PreferencesDialog` | 1 | — | — | hosts toasts "The request failed.", "The autostart request failed." |
| `Adw.PreferencesPage` / `Adw.PreferencesGroup` | 1 / 1 | — | — | |
| `Adw.ExpanderRow background` | 1 | — | `notify::enable-expansion` → `_onBackgroundChanged` | "Keep Running in Background", `show-enable-switch`, `expanded: true`; bound to `hide-on-close` |
| `Adw.ActionRow` | 2 | — | — | "Run on Startup" and "Start Hidden"; second `sensitive: bind startup.active`; each `activatable-widget` is its switch |
| `Gtk.Switch startup` | 1 | — | `notify::active` → `_onStartupChanged` | `autostart` setting |
| `Gtk.Switch hidden` | 1 | — | `notify::active` → `_onStartupHiddenChanged` | `autostart-hidden` setting |

All three handlers go through the XDG background portal and write back the
value the portal actually granted (with `freeze_notify`/`thaw_notify` around
the switch), toasting on failure; the background toggle also updates the live
window's `hide_on_close`.

Present: **yes**.

## src/widgets/notificationRow.js + .blp → `lib/notification_row.rb` — one notification row

`Gtk.ListBoxRow` subclass (deliberately not an `Adw.ActionRow` — it needs its
own layout), `tooltip-text` bound to `title`, `notify::parent` → `_onParent`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.ListBoxRow` | 1 | — | `notify::parent`; emits its own `activated` | re-emits the parent list box's `row-activated` for itself |
| `Gtk.Box` | 2 | `header` (outer) | — | outer horizontal, inner vertical |
| `Gtk.Stack iconStack` | 1 | — | — | `icon` / `spinner`, switched by the `progress` property |
| `Gtk.Image icon` | 1 | one of `accent` (open/opened), `closed` (closed), `dim-label` (draft), `error` (denied) — chosen from `state` at construction | — | `icon-name` bound to the row property |
| `Adw.Spinner` | 1 | — | — | 16×16 |
| `Gtk.CenterBox` | 2 | — | — | title/date line, repo/account line |
| `Gtk.Label` | 4 | `caption` + `dim-label` on date, repo and account | — | title (ellipsize end), date, repo (ellipsize end), account (ellipsize start, `halign: end`) |

Properties to reproduce: `title`, `date`, `repo`, `account`, `state`,
`icon-name`, `progress`, plus the `activated` signal.

Present: **yes**.

## src/model/notification.js → `lib/notification.rb` — a notification, and its desktop notification

Not a widget, but it builds the user-visible desktop notification and chooses
the row icon, so it is a component boundary.

- `Gio.Notification`: title = notification title, body = repository, themed
  icon `<app-id>-<icon>`, default action `app.open-notification` with
  `(id, url)`, button "Mark as Read" → `app.mark-read(id)`, and — only when the
  window is hidden — button "Show Forge Sparks" → `app.activate`.
- Icon mapping over `type` × `state`: Issue → `issue-symbolic` /
  `issue-done-symbolic` (closed); Pull/PullRequest/MergeRequest →
  `merge-symbolic` / `merge-merged-symbolic` (closed) / `merge-draft-symbolic`
  (draft) / `merge-denied-symbolic` (denied); Discussion →
  `discussion-symbolic`; Release → `tag-symbolic`; Commit →
  `commit-symbolic`; default `preferences-system-details-symbolic`.
- Properties: `id`, `type`, `unread`, `updated-at`, `timestamp` (read-only,
  from `dateTime`), `state`, `title`, `repository`, `url`, `account-name`.

Present: **yes**.

## src/model/notificationsList.js → `lib/notifications_list.rb` — the notifications model

`Gio.ListModel` implementation over an array of `Notification`: `clear`,
`append`, `getByID`, `removeByID`, with `items_changed` emissions. The window's
stack-page switching and the visibility of the mark-all-read button hang off
its `items-changed`.

Present: **yes**.

## src/model/account.js → `lib/account.rb` — one account

`GObject.Object` with properties `display-name` (derived, `username@url`), `id`,
`forge`, `url`, `username`, `user-id`, `auth-failed`; `notify::url` and
`notify::username` re-notify `display-name`. `display-name` feeds the accounts
list row and the auth-failure banner, `auth-failed` the row's error icon.

Present: **yes**.

## src/model/accountsManager.js → `lib/accounts_manager.rb` — accounts store

Singleton `Gio.ListModel` of `Account`s backed by the `accounts` GSettings key
plus one `<app-id>.account` child schema per account (settings-bound `forge`,
`url`, `username`, `user-id`), with access tokens in libsecret under a
`Secret.Schema` keyed by `id`. API the UI depends on: `getAccounts`,
`saveAccount`, `updateAccount`, `removeAccount`, `getAccountToken`,
`isMultiple` (the row's account label only appears when true).

Present: **yes**.

## src/util.js → `lib/util.rb` — settings, session, portal, relative dates

- `settings` — `Gio.Settings` for the app id at `/com/mardojai/ForgeSparks/`.
- `session` — one `Soup.Session`, user agent `Forge Sparks v<version>`.
- `portal` — `Xdp.Portal`; `requestBackground(window, autostart, hidden)` with
  the user-visible reasons "Allow running Forge Sparks on background." /
  "Allow running Forge Sparks on startup." and the `forge-sparks [--hidden]`
  command; `setBackgroundStatus` with "Monitoring new notifications".
- `relativeDate` — the row's date string: "now", `%d minute(s) ago`,
  `%d hour(s) ago`, "yesterday"/`%d days ago`, `%d week(s) ago`, then
  `on %b %d` / `on %d %b, %Y`. Plural forms, so it needs ngettext in the port.

Present: **yes, as of this survey.** `settings`, `session` and `relativeDate`
were already ported and are now verified by `spec/util_spec.rb` (added this
round — the previous "yes" here was not backed by any test). `portal` was
the real gap the previous two surveys found and the fix two commits ago
(e0bd336) did not close: it reworded a toast and fixed a sandboxing lie, but
left the file with *no* call to any background portal at all, hide-on-close
and an XDG autostart `.desktop` file standing in for it. This survey's `ruby`
HEAD replaces that substitute: `Util.request_background` and
`Util.set_background_status` speak to `org.freedesktop.portal.Background`
directly over D-Bus through `ruby-dbus` (swapped in for `ashpd` 0.1.1, whose
`Ashpd.constants` has no `Background` — verified live again this round), and
`lib/preferences_dialog.rb`, `lib/window.rb#first_run` and
`lib/window.rb#on_window_hide` all call through it instead of the file
write. The three upstream strings this unit owns ("Allow running Forge
Sparks on background.", "...on startup.", "Monitoring new notifications")
were already present in the port's source; what was missing, and is now
wired in, is the real call that makes them reachable and the real allow/deny
result driving the preferences switches. Checked live this round, with no
portal daemon running under `xvfb-run`: the request fails honestly
(`DBus::Error::ServiceUnknown`, caught and reported as "The request
failed."/"The autostart request failed.") rather than reporting a grant
nothing gave — see `test/drive_window.rb`'s preferences steps.

## src/forges/*.js → `lib/forge.rb`, `lib/forges.rb`, `lib/github.rb`, `lib/gitea.rb`, `lib/forgejo.rb`, `lib/gitlab.rb`

Backends, but they carry user-facing strings and drive the UI: each forge's
`prettyName` populates the forge combo row ("Forgejo", "Gitea", "GitHub",
"GitLab"), its `allowInstances` and `defaultURL` decide whether the instance
row shows and what it prefills (`codeberg.org`, `gitea.com`, `github.com`,
`gitlab.com`), and its `tokenText` is the markup in the token help label
(per-forge, two paragraphs each, naming the required scopes). The
`FailedForgeAuth` / `FailedTokenScopes` throws are what the dialog's error
toasts and the window's auth banner render. `index.js` also holds `extractID`.

- `src/forges/forge.js` → `lib/forge.rb` — base class, HTTP helpers, `formatID`, `buildURI`.
- `src/forges/index.js` → `lib/forges.rb` — the `FORGES` map and `extractID`.
- `src/forges/github.js` → `lib/github.rb`
- `src/forges/gitea.js` → `lib/gitea.rb`
- `src/forges/forgejo.js` → `lib/forgejo.rb`
- `src/forges/gitlab.js` → `lib/gitlab.rb`

Present: **yes** (all six): `lib/forge.rb`, `lib/forges.rb`, `lib/github.rb`,
`lib/gitea.rb`, `lib/forgejo.rb`, `lib/gitlab.rb`.

## src/main.js + src/com.mardojai.ForgeSparks → `lib/main.rb` (+ existing `exe/forge-sparks`)

Entry point: sets the application name "Forge Sparks", promisifies Soup and
Secret, instantiates the application and runs it. `exe/forge-sparks` already
exists on `ruby` but launches the scaffold.

Present: **yes**.

## data/com.mardojai.ForgeSparks.gschema.xml → `lib/settings.rb`

Main schema keys: `first-run` (b), `hide-on-close` (b), `autostart` (b),
`autostart-hidden` (b), `window-size` (ai, `[780, 480]`), `accounts` (as),
`notified` (a{ss}). Child schema `<app-id>.account`: `forge` (`'github'`),
`url` (`'github.com'`), `username`, `user-id`. Note `window-size` is declared
but never read upstream — the window uses the blueprint's 500×500.

Present: **yes**, as `lib/settings.rb` — the same key set, backed by a JSON
file under the user config dir rather than a GSettings schema, so no
`.gschema.xml` is installed by the port.

## src/style.css + src/style-dark.css → `lib/style.rb`

Three rules in total: `.margin-box { margin: 24px 12px }`, `.closed { color:
@purple_3 }` and, in the dark sheet, `.closed { color: @purple_1 }`. The port
needs a `Gtk::CssProvider` pair selected by `Adwaita::StyleManager#dark?`.
`margin-box` is used by `window.blp` and `accountsDialog.blp`; `closed` by
`notificationRow.js`. No dead and no undefined classes.

Present: **yes** — `lib/style.rb` carries both sheets as strings and swaps the
dark provider on `Adwaita::StyleManager#dark?`.

## Assets — `data/` in the port

Nine status icons (`commit`, `discussion`, `issue`, `issue-done`,
`merge`, `merge-denied`, `merge-draft`, `merge-merged`, `tag` — all
`-symbolic.svg`, installed renamed `<app-id>-*` into
`icons/hicolor/scalable/status`), `src/assets/alldone.svg` (the empty-state
picture) and the app icons in `data/`. The desktop file and metainfo carry the
user-visible name "Forge Sparks" and summary "Get Git forges notifications".

Present: **yes** — `data/icons/*-symbolic.svg` (all nine), `data/alldone.svg`,
`data/forge-sparks.svg`/`-symbolic.svg`, plus
`data/org.rubygtkproject.ForgeSparks.desktop.in`, `.metainfo.xml.in` and
`.service.in`, each named after this port's app id and finished by the
install step (translations merged with `msgfmt --desktop`/`--xml`, `@bindir@`
pointed at the installed launcher).

## po/ — translations

26 locales (`ar ca cs de es et fa fi fr hi hr ia it ka kk nb_NO nl pt pt_BR ru
sv ta tr uk vi zh_Hans` per `po/LINGUAS`) plus
`com.mardojai.ForgeSparks.pot`. `po/POTFILES` lists 26 files; every `.blp` and
every `.js` holding a translated string is in it. The port needs the same
catalogue reachable and `ngettext` for `relativeDate`'s plural forms.

Present: **yes**. `po/` carries the port's own `forge-sparks.pot`, upstream's
same 26 `LINGUAS` locales (merged against the new template — most land at 59
of 64 messages; the five extra are strings this port added), `POTFILES` and
`update-catalogue.sh`. `lib/translation.rb` binds the `forge-sparks` domain
and `lib/util.rb`'s relative dates go through `n_`, matching upstream's
`ngettext`.

---

## Summary

| # | Upstream | Port path | Kind | Present |
|---:|---|---|---|:-:|
| 1 | `src/window.js` + `src/window.blp` | `lib/window.rb` | window (3-page stack, primary menu, banner, empty state) | yes |
| 2 | `src/gtk/help-overlay.blp` | `lib/shortcuts_dialog.rb` | keyboard shortcuts dialog | yes |
| 3 | `src/application.js` | `lib/application.rb` | application, 9 actions, 7 accels, About dialog | yes |
| 4 | `src/widgets/accountDialog.js` + `.blp` | `lib/account_dialog.rb` | dialog (add/edit account, toasts) | yes |
| 5 | `src/widgets/accountsDialog.js` + `.blp` | `lib/accounts_dialog.rb` | dialog (accounts list, empty state, row repeater) | yes |
| 6 | `src/widgets/preferences.js` + `.blp` | `lib/preferences_dialog.rb` | preferences dialog | yes |
| 7 | `src/widgets/notificationRow.js` + `.blp` | `lib/notification_row.rb` | list row | yes |
| 8 | `src/model/notification.js` | `lib/notification.rb` | model + desktop notification + icon map | yes |
| 9 | `src/model/notificationsList.js` | `lib/notifications_list.rb` | list model | yes |
| 10 | `src/model/account.js` | `lib/account.rb` | model | yes |
| 11 | `src/model/accountsManager.js` | `lib/accounts_manager.rb` | settings/secret-backed list model | yes |
| 12 | `src/util.js` | `lib/util.rb` | settings, HTTP session, portal, relative dates | yes, as of this survey — see the per-unit note above |
| 13 | `src/forges/forge.js` | `lib/forge.rb` | backend base class | yes |
| 14 | `src/forges/index.js` | `lib/forges.rb` | forge registry, `extractID` | yes |
| 15 | `src/forges/github.js` | `lib/github.rb` | backend + token help text | yes |
| 16 | `src/forges/gitea.js` | `lib/gitea.rb` | backend + token help text | yes |
| 17 | `src/forges/forgejo.js` | `lib/forgejo.rb` | backend + token help text | yes |
| 18 | `src/forges/gitlab.js` | `lib/gitlab.rb` | backend + token help text | yes |
| 19 | `src/main.js` + `src/com.mardojai.ForgeSparks` | `lib/main.rb` | entry point, CLI options | yes |
| 20 | `data/com.mardojai.ForgeSparks.gschema.xml` | `lib/settings.rb` | settings store (JSON, same key set) | yes |
| 21 | `src/style.css` + `src/style-dark.css` | `lib/style.rb` | CSS provider (light/dark) | yes |
| 22 | `src/icons/*.svg`, `src/assets/alldone.svg`, `data/*.desktop.in.in`, metainfo | `data/` | assets + packaging data | yes |
| 23 | `po/` (26 locales + pot) | `po/` | translation catalogue | yes |

Seven of these are widget units (1–7); the remaining sixteen are the models,
backends, settings, styling, assets and translations they need. All 23 now
have a port file, and as of this survey row 12 (`src/util.js` →
`lib/util.rb`) also has the real background-portal call its two previous
surveys found missing, not just the file. That closes the one behavioural
gap this inventory tracked across its last two revisions; the previous "23
of 23 are done" / "No gaps remain" / "Nothing identified by this survey
remains unported" lines in this section stood through a fix commit
(e0bd336) that touched this exact unit without closing it, which is the
kind of stale "yes" this file should not carry again. `spec/util_spec.rb`
and `spec/settings_spec.rb`, both added this round, are this port's first
`*_spec.rb` files — `spec/` previously held only `spec_helper.rb` and
`README.md`, so `rake spec` ran zero examples regardless of what this
inventory claimed about the code it would have exercised.
