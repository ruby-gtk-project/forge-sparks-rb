# Forge Sparks — upstream component inventory

Upstream: `origin/main` (GJS + blueprint, meson, gjspack bundler).
Port: the `ruby` branch of this repo.

**State of the port: nothing is ported yet.** `lib/` holds only the kettle-jem
scaffold — `lib/forge_sparks.rb`, `lib/forge/sparks/rb/version.rb` and
`lib/forge_sparks/application.rb`, the generated "The Ruby port has not been
written yet." status page. Every row below is therefore `present: no`; the
scaffold is noted where it occupies the eventual path.

Scan corroborating the reading below (clean export of `origin/main`,
`component-identification/scripts/component-scan.sh`): 141 rows, 36 distinct
widget types, 20 distinct CSS classes, 9 distinct signals, 18 distinct actions.
The port side scans to the scaffold's 5 widgets and no CSS, signals or actions.

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

Present: **no**.

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

Present: **no**.

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

Present: **no** (scaffold stub only).

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

Present: **no**.

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

Present: **no**.

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

Present: **no**.

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

Present: **no**.

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

Present: **no**.

## src/model/notificationsList.js → `lib/notifications_list.rb` — the notifications model

`Gio.ListModel` implementation over an array of `Notification`: `clear`,
`append`, `getByID`, `removeByID`, with `items_changed` emissions. The window's
stack-page switching and the visibility of the mark-all-read button hang off
its `items-changed`.

Present: **no**.

## src/model/account.js → `lib/account.rb` — one account

`GObject.Object` with properties `display-name` (derived, `username@url`), `id`,
`forge`, `url`, `username`, `user-id`, `auth-failed`; `notify::url` and
`notify::username` re-notify `display-name`. `display-name` feeds the accounts
list row and the auth-failure banner, `auth-failed` the row's error icon.

Present: **no**.

## src/model/accountsManager.js → `lib/accounts_manager.rb` — accounts store

Singleton `Gio.ListModel` of `Account`s backed by the `accounts` GSettings key
plus one `<app-id>.account` child schema per account (settings-bound `forge`,
`url`, `username`, `user-id`), with access tokens in libsecret under a
`Secret.Schema` keyed by `id`. API the UI depends on: `getAccounts`,
`saveAccount`, `updateAccount`, `removeAccount`, `getAccountToken`,
`isMultiple` (the row's account label only appears when true).

Present: **no**.

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

Present: **no**.

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

Present: **no** (all six).

## src/main.js + src/com.mardojai.ForgeSparks → `lib/main.rb` (+ existing `exe/forge-sparks`)

Entry point: sets the application name "Forge Sparks", promisifies Soup and
Secret, instantiates the application and runs it. `exe/forge-sparks` already
exists on `ruby` but launches the scaffold.

Present: **no**.

## data/com.mardojai.ForgeSparks.gschema.xml → `lib/settings.rb`

Main schema keys: `first-run` (b), `hide-on-close` (b), `autostart` (b),
`autostart-hidden` (b), `window-size` (ai, `[780, 480]`), `accounts` (as),
`notified` (a{ss}). Child schema `<app-id>.account`: `forge` (`'github'`),
`url` (`'github.com'`), `username`, `user-id`. Note `window-size` is declared
but never read upstream — the window uses the blueprint's 500×500.

Present: **no**.

## src/style.css + src/style-dark.css → `lib/style.rb`

Three rules in total: `.margin-box { margin: 24px 12px }`, `.closed { color:
@purple_3 }` and, in the dark sheet, `.closed { color: @purple_1 }`. The port
needs a `Gtk::CssProvider` pair selected by `Adwaita::StyleManager#dark?`.
`margin-box` is used by `window.blp` and `accountsDialog.blp`; `closed` by
`notificationRow.js`. No dead and no undefined classes.

Present: **no**.

## Assets — `data/` in the port

Nine status icons (`commit`, `discussion`, `issue`, `issue-done`,
`merge`, `merge-denied`, `merge-draft`, `merge-merged`, `tag` — all
`-symbolic.svg`, installed renamed `<app-id>-*` into
`icons/hicolor/scalable/status`), `src/assets/alldone.svg` (the empty-state
picture) and the app icons in `data/`. The desktop file and metainfo carry the
user-visible name "Forge Sparks" and summary "Get Git forges notifications".

Present: **no**.

## po/ — translations

23 locales (`ar ca cs de es et fa fi fr hi hr ia it ka kk nb_NO nl pt pt_BR ru
sv ta tr uk vi zh_Hans` per `po/LINGUAS`) plus
`com.mardojai.ForgeSparks.pot`. `po/POTFILES` lists 26 files; every `.blp` and
every `.js` holding a translated string is in it. The port needs the same
catalogue reachable and `ngettext` for `relativeDate`'s plural forms.

Present: **no**.

---

## Summary

| # | Upstream | Port path | Kind | Present |
|---:|---|---|---|:-:|
| 1 | `src/window.js` + `src/window.blp` | `lib/window.rb` | window (3-page stack, primary menu, banner, empty state) | no |
| 2 | `src/gtk/help-overlay.blp` | `lib/shortcuts_dialog.rb` | keyboard shortcuts window | no |
| 3 | `src/application.js` | `lib/application.rb` | application, 9 actions, 7 accels, About dialog | no (scaffold stub) |
| 4 | `src/widgets/accountDialog.js` + `.blp` | `lib/account_dialog.rb` | dialog (add/edit account, toasts) | no |
| 5 | `src/widgets/accountsDialog.js` + `.blp` | `lib/accounts_dialog.rb` | dialog (accounts list, empty state, row repeater) | no |
| 6 | `src/widgets/preferences.js` + `.blp` | `lib/preferences_dialog.rb` | preferences dialog | no |
| 7 | `src/widgets/notificationRow.js` + `.blp` | `lib/notification_row.rb` | list row | no |
| 8 | `src/model/notification.js` | `lib/notification.rb` | model + desktop notification + icon map | no |
| 9 | `src/model/notificationsList.js` | `lib/notifications_list.rb` | list model | no |
| 10 | `src/model/account.js` | `lib/account.rb` | model | no |
| 11 | `src/model/accountsManager.js` | `lib/accounts_manager.rb` | settings/secret-backed list model | no |
| 12 | `src/util.js` | `lib/util.rb` | settings, Soup session, portal, relative dates | no |
| 13 | `src/forges/forge.js` | `lib/forge.rb` | backend base class | no |
| 14 | `src/forges/index.js` | `lib/forges.rb` | forge registry, `extractID` | no |
| 15 | `src/forges/github.js` | `lib/github.rb` | backend + token help text | no |
| 16 | `src/forges/gitea.js` | `lib/gitea.rb` | backend + token help text | no |
| 17 | `src/forges/forgejo.js` | `lib/forgejo.rb` | backend + token help text | no |
| 18 | `src/forges/gitlab.js` | `lib/gitlab.rb` | backend + token help text | no |
| 19 | `src/main.js` + `src/com.mardojai.ForgeSparks` | `lib/main.rb` | entry point, CLI options | no |
| 20 | `data/com.mardojai.ForgeSparks.gschema.xml` | `lib/settings.rb` | GSettings schema | no |
| 21 | `src/style.css` + `src/style-dark.css` | `lib/style.rb` | CSS provider (light/dark) | no |
| 22 | `src/icons/*.svg`, `src/assets/alldone.svg` | `data/` | assets (9 status icons + illustration) | no |
| 23 | `po/` (23 locales + pot) | `po/` | translation catalogue | no |

Seven of these are widget units (1–7); the remaining sixteen are the models,
backends, settings, styling, assets and translations they need.
