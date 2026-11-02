# frozen_string_literal: true

# Drives the main window, every dialog it opens, every action and every
# accelerator the port claims to have.
#
# Run it:
#   nix develop --command xvfb-run -a ruby test/drive_window.rb
#
# Set DRIVE_SHOTS to keep the screenshots somewhere you can look at them.
#
# Two substitutions keep the run hermetic, and nothing else is stubbed: the
# HTTP session is a script of canned responses (so the real GitHub backend,
# the real fetch loop and the real notification rows are all exercised with no
# network), and the token store keeps its tokens in memory instead of the
# user's secret service.

require 'tmpdir'
require 'fileutils'
require 'json'
require 'time'

# The checks below read the English the port is written in, so the run is
# pinned to the C locale: a machine whose language has a compiled catalogue in
# data/locale would otherwise hand back translated labels.
ENV['LANGUAGE'] = 'C'
ENV['LC_ALL'] = 'C'

scratch = Dir.mktmpdir('forge-sparks-drive')
ENV['XDG_CONFIG_HOME'] = File.join(scratch, 'config')
ENV['XDG_DATA_HOME'] = File.join(scratch, 'data')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'main'
require_relative 'gtk_driver'

def fake_notification(id:, title:, type:, state:, repository:, minutes_ago:)
  Notification.new(
    id:           id,
    type:         type,
    unread:       true,
    updated_at:   (Time.now.utc - (minutes_ago * 60)).iso8601,
    state:        state,
    title:        title,
    repository:   repository,
    url:          "https://example.com/#{id}",
    account_name: 'octocat@github.com',
  )
end

# A session that answers from a script of "METHOD url" => [status, body], so
# the forge backends run without a network. Anything the script does not name
# answers 404, which is how a missing stub shows up as a failed check rather
# than as a request leaving the machine.
class FakeSession
  def initialize(responses)
    @responses = responses
    @requests = []
  end

  attr_reader :requests
  attr_accessor :responses

  def send_and_read(method, url, data: nil, headers: {})
    @requests << { method: method, url: url, data: data, headers: headers }
    @responses.fetch("#{method} #{url}", [404, '']).then do |(status, body)|
      [status, body.is_a?(String) ? body : JSON.generate(body)]
    end
  end

  def read_contents(body) = body.to_s.empty? ? [] : JSON.parse(body)

  def requested?(method, url) = @requests.any? { |request| request[:method] == method && request[:url] == url }
end

# The tokens the account dialog saves and the fetch loop reads back, kept in
# memory so the run never touches the user's keyring.
class MemoryTokens
  def initialize = @tokens = {}
  def store(id, token, label: nil) = @tokens[id] = token
  def lookup(id) = @tokens[id]
  def clear(id) = @tokens.delete(id) || true
end

SUBJECT_URL = 'https://api.github.com/repos/octocat/hello/issues/7'
ISSUE_UPDATED_AT = (Time.now.utc - 180).iso8601

NOTIFICATION_ITEM = {
  'id'         => '1001',
  'unread'     => true,
  'reason'     => 'subscribed',
  'updated_at' => ISSUE_UPDATED_AT,
  'subject'    => {
    'type'  => 'Issue',
    'title' => 'Fix the fetch loop',
    'url'   => SUBJECT_URL,
  },
  'repository' => {
    'full_name' => 'octocat/hello',
    'html_url'  => 'https://github.com/octocat/hello',
    'url'       => 'https://api.github.com/repos/octocat/hello',
  },
}.freeze

OK_RESPONSES = {
  'GET https://api.github.com/user'                         => [200, { 'id' => 42, 'login' => 'octocat' }],
  'GET https://api.github.com/notifications'                => [200, [NOTIFICATION_ITEM]],
  "GET #{SUBJECT_URL}"                                      => [
    200,
    {
      'state'      => 'open',
      'html_url'   => 'https://github.com/octocat/hello/issues/7',
      'updated_at' => ISSUE_UPDATED_AT,
    },
  ],
  'PUT https://api.github.com/notifications'                => [202, ''],
  'PATCH https://api.github.com/notifications/threads/1001' => [205, ''],
}.freeze

# Every widget under one, in tree order — the way to look inside a composite
# row whose suffixes the port does not keep a handle on.
def descendants(widget)
  [].tap do |found|
    child = widget.first_child
    while child
      found << child
      found.concat(descendants(child))
      child = child.next_sibling
    end
  end
end

# GTK keeps an accelerator in the canonical form gtk_accelerator_name prints,
# where <Primary> has become <Control>, so both sides of a comparison go
# through it rather than being matched as the strings they were set with.
def canonical_accels(accels)
  accels.map do |accel|
    Gtk.accelerator_parse(accel).then { |(_ok, key, mods)| Gtk.accelerator_name(key, mods) }
  end
end

session = FakeSession.new(OK_RESPONSES.dup)
Util.instance_variable_set(:@session, session)

tokens = MemoryTokens.new
AccountsManager.instance = AccountsManager.new(settings: Util.settings, tokens: tokens)

application = Application.new

shots = ENV.fetch('DRIVE_SHOTS', File.join(scratch, 'shots'))

# Every button is clicked through its "clicked" signal rather than through
# Gtk::Widget#activate: a Gtk::Button's activate animates the press and only
# emits clicked a tick or two later, which would race every check that looks
# at what the handler did.
GtkDriver.drive(application, shots: shots) do |d, app|
  d.window { app.window }

  d.step('the window comes up on the setup page') do
    d.check('window exists') { !app.window.nil? }
    d.check('no accounts configured') { app.accounts.n_items.zero? }
    d.check('setup page showing') { app.window.main_stack.visible_child_name == 'setup' }
    d.check('welcome title set') { app.window.setup_page.title == 'Welcome to Forge Sparks' }
    d.check('welcome description set') do
      app.window.setup_page.description == 'Add an account to receive notifications from'
    end
    d.check('add button is a pill') { app.window.add_account_button.css_classes.include?('pill') }
    d.check('app icon loaded') { !app.window.setup_page.paintable.nil? }
    d.check('no auth banner yet') { !app.window.account_banner.revealed? }
    d.shot('01-setup')
  end

  # --- The stylesheet ------------------------------------------------------

  d.step('the stylesheet is installed on the display') do
    d.check('a display is present') { !Gdk::Display.default.nil? }
    d.check('light provider built') { !app.style.light_provider.nil? }
    d.check('dark provider built') { !app.style.dark_provider.nil? }
    d.check('margin-box is in the light sheet') { Style::LIGHT.include?('.margin-box') }
    d.check('closed is restyled in the dark sheet') { Style::DARK.include?('.closed') }
    d.check('dark sits above light') { Style::DARK_PRIORITY > Style::LIGHT_PRIORITY }
    d.check('style manager reachable') { !app.style.style_manager.nil? }
    d.check('list box carries margin-box') { app.window.notifications_list.css_classes.include?('margin-box') }
    d.check('main stack carries main-view') { app.window.main_stack.css_classes.include?('main-view') }
    d.check('re-installing is harmless') { !app.style.install.nil? }
  end

  # --- Notifications in the list, from a handed-in list --------------------

  d.step('notifications render in the list') do
    app.window.show_notifications(
      [
        fake_notification(
          id:          'acct-1',
          title:       'Fix the thing',
          type:        'Issue',
          state:       'open',
          repository:  'octocat/hello',
          minutes_ago: 5,
        ),
        fake_notification(
          id:          'acct-2',
          title:       'Merge the other thing',
          type:        'PullRequest',
          state:       'draft',
          repository:  'octocat/world',
          minutes_ago: 1500,
        ),
        fake_notification(
          id:          'acct-3',
          title:       'Release v2',
          type:        'Release',
          state:       nil,
          repository:  'octocat/world',
          minutes_ago: 20_000,
        ),
      ],
    )
  end

  d.step('the list page shows three rows, newest first') do
    d.check('model holds three') { app.window.model.n_items == 3 }
    d.check('notifications page showing') { app.window.main_stack.visible_child_name == 'notifications' }
    d.check('list page showing') { app.window.notifications_stack.visible_child_name == 'list' }
    d.check('mark all as read is visible') { app.window.mark_as_read_button.visible? }
    d.check('newest first') { app.window.model.sorted.first.title == 'Fix the thing' }
    d.check('a row was built') { !app.window.notifications_list.get_row_at_index(0).nil? }
    d.check('three rows were built') { !app.window.notifications_list.get_row_at_index(2).nil? }
    d.shot('02-notifications')
  end

  d.step('icons and dates come from the model') do
    app.window.model.sorted.then do |sorted|
      d.check('issue icon') { sorted[0].icon_name == 'issue-symbolic' }
      d.check('draft merge icon') { sorted[1].icon_name == 'merge-draft-symbolic' }
      d.check('release icon') { sorted[2].icon_name == 'tag-symbolic' }
      d.check('issue icon file exists') { !sorted[0].icon_path.nil? }
      d.check('relative date reads as minutes') { Util.relative_date(sorted[0].date_time) == '5 minutes ago' }
    end
  end

  d.step('the rows render what the model holds') do
    app.window.notifications_list.get_row_at_index(0).then do |row|
      d.check('row is a NotificationRow') { row.is_a?(NotificationRow) }
      d.check('row title label') { row.title_label.label == 'Fix the thing' }
      d.check('row repository label') { row.repository_label.label == 'octocat/hello' }
      d.check('row date label') { row.date_label.label == '5 minutes ago' }
      d.check('row tooltip is the title') { row.tooltip_text == 'Fix the thing' }
      d.check('one account means no account label') { row.account_label.label.empty? }
      d.check('open state colours the icon') { row.icon.css_classes.include?('accent') }
      d.check('row starts on its icon') { row.icon_stack.visible_child_name == 'icon' }
      row.progress = true
      d.check('progress swaps in the spinner') { row.icon_stack.visible_child_name == 'spinner' }
      row.progress = false
      d.check('clearing progress brings the icon back') { row.icon_stack.visible_child_name == 'icon' }
    end

    app.window.notifications_list.get_row_at_index(1).then do |row|
      d.check('a draft is dimmed') { row.icon.css_classes.include?('dim-label') }
    end
  end

  d.step('the empty page comes back when the list is cleared') do
    app.window.show_notifications([])
  end

  d.step('the all-done illustration is showing') do
    d.check('empty page showing') { app.window.notifications_stack.visible_child_name == 'empty' }
    d.check('mark all as read is hidden') { !app.window.mark_as_read_button.visible? }
    d.check('illustration loaded') { !app.window.empty_picture.paintable.nil? }
    d.check('empty label is a title') { app.window.empty_label.css_classes.include?('title-1') }
    d.shot('03-empty')
  end

  # --- The add-account dialog ---------------------------------------------

  d.step('the add account dialog opens from the welcome button') do
    app.window.add_account_button.signal_emit('clicked')
  end

  d.step('the welcome button opened a dialog') do
    d.check('a dialog is up') { !app.window.visible_dialog.nil? }
    d.check('it is titled Add Account') { app.window.visible_dialog.title == 'Add Account' }
    app.window.visible_dialog&.close
  end

  d.step('the account dialog is filled in for a new account') do
    AccountDialog.new(nil, accounts: app.accounts).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @dialog = dialog
    end
  end

  d.step('the account dialog validates as the user types') do
    d.check('forge row is visible for a new account') { @dialog.forge_row.visible? }
    d.check('four forges listed') { @dialog.forge_row.model.n_items == 4 }
    d.check('instance row visible for forgejo') { @dialog.instance_row.visible? }
    d.check('instance defaults to codeberg.org') { @dialog.instance_row.text == 'codeberg.org' }
    d.check('help text is set') { @dialog.help_label.label.include?('access token') }
    d.check('save starts insensitive') { !@dialog.save_button.sensitive? }
    d.check('save is labelled Add') { @dialog.save_button.label == 'Add' }
    d.check('cancel is there') { @dialog.cancel_button.label == 'Cancel' }
    @dialog.access_token_row.text = 'a-token'
  end

  d.step('a token makes the dialog saveable') do
    d.check('save is now sensitive') { @dialog.save_button.sensitive? }
    d.check('remove group hidden while adding') { !@dialog.remove_group.visible? }
    d.shot('04-account-dialog', @dialog.child)
    @dialog.forge_row.selected = 1
  end

  d.step('choosing Gitea swaps the help text and the instance') do
    d.check('instance now gitea.com') { @dialog.instance_row.text == 'gitea.com' }
    d.check('help text names the gitea scopes') { @dialog.help_label.label.include?('write:notification') }
    @dialog.forge_row.selected = 2
  end

  d.step('choosing GitHub swaps the help text and the instance') do
    d.check('instance now github.com') { @dialog.instance_row.text == 'github.com' }
    d.check('help text mentions classic tokens') { @dialog.help_label.label.include?('classic') }
    d.shot('05-account-dialog-github', @dialog.child)
    @dialog.forge_row.selected = 3
  end

  d.step('choosing GitLab swaps the help text and the instance') do
    d.check('instance now gitlab.com') { @dialog.instance_row.text == 'gitlab.com' }
    d.check('help text names the api scope') { @dialog.help_label.label.include?('read_api') }
  end

  d.step('an unparseable instance url is refused') do
    @dialog.instance_row.text = 'ex ample.com'
    d.check('the entry is marked') { @dialog.instance_row.css_classes.include?('error') }
    d.check('save went insensitive') { !@dialog.save_button.sensitive? }
    d.shot('06-account-dialog-error', @dialog.child)
  end

  d.step('an empty instance url is unfinished, not invalid') do
    @dialog.instance_row.text = ''
    d.check('the mark is gone') { !@dialog.instance_row.css_classes.include?('error') }
    d.check('save is still insensitive') { !@dialog.save_button.sensitive? }
    @dialog.instance_row.text = 'gitlab.com'
    d.check('a good url makes it saveable again') { @dialog.save_button.sensitive? }
    @dialog.close
  end

  # --- Preferences ---------------------------------------------------------

  d.step('the preferences dialog opens') do
    PreferencesDialog.new(settings: Util.settings).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @prefs = dialog
    end
  end

  d.step('the preferences reflect the settings') do
    d.check('background row titled') { @prefs.background_row.title == 'Keep Running in Background' }
    d.check('background expansion follows hide-on-close') do
      @prefs.background_row.enable_expansion? == Util.settings['hide-on-close']
    end
    d.check('startup row titled') { @prefs.startup_row.title == 'Run on Startup' }
    d.check('hidden row titled') { @prefs.hidden_row.title == 'Start Hidden' }
    d.check('startup switch off') { !@prefs.startup_switch.active? }
    d.check('start hidden row insensitive') { !@prefs.hidden_row.sensitive? }
    @prefs.startup_switch.active = true
  end

  d.step('turning on autostart writes the desktop file') do
    d.check('autostart saved') { Util.settings['autostart'] == true }
    d.check('desktop file written') { File.exist?(Util.autostart_file) }
    d.check('start hidden row now sensitive') { @prefs.hidden_row.sensitive? }
    d.shot('07-preferences', @prefs.child)
    @prefs.hidden_switch.active = true
  end

  d.step('start hidden adds the flag to the autostart command') do
    d.check('autostart-hidden saved') { Util.settings['autostart-hidden'] == true }
    d.check('the desktop file carries --hidden') { File.read(Util.autostart_file).include?('--hidden') }
    @prefs.hidden_switch.active = false
    @prefs.startup_switch.active = false
  end

  d.step('turning it off removes the desktop file') do
    d.check('autostart cleared') { Util.settings['autostart'] == false }
    d.check('desktop file gone') { !File.exist?(Util.autostart_file) }
    @prefs.background_row.enable_expansion = false
  end

  d.step('the background switch writes hide-on-close through to the window') do
    d.check('hide-on-close cleared') { Util.settings['hide-on-close'] == false }
    @prefs.background_row.enable_expansion = true
    d.check('hide-on-close set again') { Util.settings['hide-on-close'] == true }
    @prefs.close
  end

  # --- The accounts dialog, empty -----------------------------------------

  d.step('the accounts dialog opens') do
    AccountsDialog.new(accounts: app.accounts).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @accounts_dialog = dialog
    end
  end

  d.step('the accounts dialog shows its empty page') do
    d.check('empty page showing') { @accounts_dialog.accounts_stack.visible_child_name == 'empty' }
    d.check('empty page titled') { @accounts_dialog.empty_page.title == 'No Accounts' }
    d.check('add button is labelled') { @accounts_dialog.add_button_content.label == 'Add…' }
    d.shot('08-accounts', @accounts_dialog.child)
    @accounts_dialog.add_button.signal_emit('clicked')
  end

  # A dialog presented on top of another one is hosted by the window both of
  # them sit in, so the one on top is the window's visible dialog.
  d.step('the accounts dialog add button opens the account dialog') do
    d.check('a dialog is up over the accounts dialog') { !app.window.visible_dialog.nil? }
    d.check('it is titled Add Account') { app.window.visible_dialog.title == 'Add Account' }
    app.window.visible_dialog&.close
  end

  d.step('the accounts dialog closes') do
    @accounts_dialog.close
  end

  # --- The shortcuts dialog ------------------------------------------------

  d.step('the shortcuts dialog opens from its window action') do
    app.window.activate_action('show-help-overlay', nil)
  end

  d.step('the shortcuts dialog lists the three shortcuts') do
    d.check('a dialog is up') { !app.window.visible_dialog.nil? }
    d.check('it is a shortcuts dialog') { app.window.visible_dialog.is_a?(Adwaita::ShortcutsDialog) }
    d.check('it is titled Keyboard Shortcuts') { app.window.visible_dialog.title == 'Keyboard Shortcuts' }
    d.check('one General section') { ShortcutsDialog::SECTIONS.keys == ['General'] }
    d.check('three shortcuts listed') { ShortcutsDialog::SECTIONS['General'].length == 3 }
    d.check('F10 opens the menu') { ShortcutsDialog::SECTIONS['General'].include?(['Open menu', 'F10']) }
    d.shot('09-shortcuts')
    app.window.visible_dialog&.close
  end

  # --- The primary menu ----------------------------------------------------

  d.step('the primary menu is the one upstream builds') do
    d.check('two sections') { app.window.primary_menu.n_items == 2 }
    d.check('menu button carries the menu') { !app.window.menu_button.menu_model.nil? }
    d.check('menu button is primary') { app.window.menu_button.primary? }
    d.check('menu button is tooltipped') { app.window.menu_button.tooltip_text == 'Main Menu' }
    d.check('setup page has its own menu button') { !app.window.setup_menu_button.menu_model.nil? }
    app.window.activate_action('open-primary-menu', nil)
  end

  d.step('F10 popped the menu open') do
    d.check('the menu button is active') { app.window.menu_button.active? }
    d.shot('10-primary-menu')
    app.window.menu_button.popdown
  end

  # --- The about dialog ----------------------------------------------------

  d.step('the about dialog opens from the app action') do
    app.app.activate_action('about', nil)
  end

  d.step('the about dialog names the app') do
    d.check('a dialog is up') { !app.window.visible_dialog.nil? }
    d.check('about names the app') { app.about_dialog.application_name == 'Forge Sparks' }
    d.check('about carries a version') { !app.about_dialog.version.to_s.empty? }
    d.check('about carries the comments') { app.about_dialog.comments == 'Get Git forges notifications' }
    d.check('about carries the copyright') { app.about_dialog.copyright.include?('Rafael Mardojai CM') }
    d.shot('11-about')
    app.window.visible_dialog&.close
  end

  # --- Reload, and the loading page ---------------------------------------

  d.step('reloading shows the spinner') do
    app.window.reload
    d.check('loading page showing') { app.window.main_stack.visible_child_name == 'loading' }
    d.shot('12-loading')
  end

  # --- An account, and the real fetch loop --------------------------------

  d.step('an account is saved') do
    @account_id = app.accounts.save_account(
      forge:    'github',
      url:      'github.com',
      user_id:  42,
      username: 'octocat',
      token:    'a-token',
    )
  end

  d.step('the account is in the model, the settings and the token store') do
    d.check('one account') { app.accounts.n_items == 1 }
    d.check('not multiple') { !app.accounts.multiple? }
    d.check('saved in the settings') { Util.settings['accounts'] == [@account_id] }
    d.check('display name is username@url') do
      app.accounts.get_account_by_id(@account_id).display_name == 'octocat@github.com'
    end
    d.check('token stored') { app.accounts.get_account_token(@account_id) == 'a-token' }
    d.check('forge saved') { app.accounts.get_account_setting(@account_id, 'forge') == 'github' }
  end

  d.step('wait for the fetch the new account kicked off') { nil }

  d.step('the fetched notification is on screen') do
    d.check('the backend asked for the notifications') do
      session.requested?('GET', 'https://api.github.com/notifications')
    end
    d.check('the subject was looked up') { session.requested?('GET', SUBJECT_URL) }
    d.check('one notification in the model') { app.window.model.n_items == 1 }
    d.check('notifications page showing') { app.window.main_stack.visible_child_name == 'notifications' }
    d.check('list page showing') { app.window.notifications_stack.visible_child_name == 'list' }
    d.check('the id carries the account') { app.window.model.sorted.first.id == "#{@account_id}-1001" }
    d.check('the url carries the referrer') do
      app.window.model.sorted.first.url.include?('notification_referrer_id=')
    end
    app.window.notifications_list.get_row_at_index(0).then do |row|
      d.check('the row shows the fetched title') { row.title_label.label == 'Fix the fetch loop' }
      d.check('the row shows the repository') { row.repository_label.label == 'octocat/hello' }
      # The stub timestamp is three minutes before the run starts, so how many
      # minutes the formatter rounds to depends on how long the run took to
      # reach this step: the shape of the string is what is being checked.
      d.check('the row shows a relative date') { row.date_label.label.match?(/\A\d+ minutes ago\z/) }
    end
    d.shot('13-fetched')
  end

  d.step('activating a row opens it and shows progress') do
    app.window.notifications_list.get_row_at_index(0).then do |row|
      row.activate
      d.check('the row went into progress') { row.progress? }
      d.check('the row went insensitive') { !row.sensitive? }
    end
  end

  d.step('marking everything as read empties the list') do
    app.window.mark_as_read_button.signal_emit('clicked')
    d.check('the button went insensitive') { !app.window.mark_as_read_button.sensitive? }
    d.check('the spinner is showing') { app.window.mark_as_read_icon.visible_child_name == 'spinner' }
  end

  d.step('the mark-all-read request went out and the list emptied') do
    d.check('the forge was asked') { session.requested?('PUT', 'https://api.github.com/notifications') }
    d.check('the model is empty') { app.window.model.n_items.zero? }
    d.check('the empty page is back') { app.window.notifications_stack.visible_child_name == 'empty' }
    d.check('the button is sensitive again') { app.window.mark_as_read_button.sensitive? }
    d.check('the icon is back') { app.window.mark_as_read_icon.visible_child_name == 'icon' }
    d.check('the list is sensitive again') { app.window.notifications_list.sensitive? }
  end

  d.step('a reload brings the notification back') do
    app.window.reload
  end

  d.step('wait for the refetch') { nil }

  d.step('mark-read is fired for the one notification') do
    d.check('the notification is back') { app.window.model.n_items == 1 }
    app.app.activate_action('mark-read', GLib::Variant.new("#{@account_id}-1001"))
  end

  d.step('wait for the mark-read request') { nil }

  d.step('the marked notification was dropped from the list') do
    d.check('the thread was patched') do
      session.requested?('PATCH', 'https://api.github.com/notifications/threads/1001')
    end
    d.check('the model dropped it') { app.window.model.n_items.zero? }
    d.check('the empty page is showing') { app.window.notifications_stack.visible_child_name == 'empty' }
  end

  # --- The accounts dialog, populated -------------------------------------

  d.step('the accounts dialog opens with an account') do
    AccountsDialog.new(accounts: app.accounts).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @accounts_dialog = dialog
    end
  end

  d.step('the accounts dialog lists the account') do
    d.check('accounts page showing') { @accounts_dialog.accounts_stack.visible_child_name == 'accounts' }
    @accounts_dialog.accounts_list.get_row_at_index(0).then do |row|
      d.check('a row was built') { !row.nil? }
      d.check('the row is titled with the display name') { row.title == 'octocat@github.com' }
      d.check('the row is activatable') { row.activatable? }
      d.check('the row carries a chevron') do
        descendants(row).any? { |widget| widget.is_a?(Gtk::Image) && widget.icon_name == 'go-next-symbolic' }
      end
      d.check('the error icon is hidden while the token works') do
        descendants(row).select { |widget| widget.is_a?(Gtk::Image) && widget.icon_name == 'dialog-error-symbolic' }
                        .none?(&:visible?)
      end
    end
    d.shot('14-accounts-populated', @accounts_dialog.child)
  end

  # --- The auth-failure state ---------------------------------------------

  d.step('the token stops working') do
    session.responses = OK_RESPONSES.merge('GET https://api.github.com/notifications' => [401, ''])
    app.window.reload
  end

  d.step('wait for the failing fetch') { nil }

  d.step('the banner says the account stopped authenticating') do
    d.check('the banner is revealed') { app.window.account_banner.revealed? }
    d.check('the banner names the account') do
      app.window.account_banner.title.include?('Account octocat@github.com authentication failed!')
    end
    d.check('the banner explains why') { app.window.account_banner.title.include?('revoked or expired') }
    d.check('the banner offers the accounts dialog') { app.window.account_banner.action_name == 'app.accounts' }
    d.check('the banner button is labelled') { app.window.account_banner.button_label == 'Accounts' }
    d.check('the account is marked as failing') { app.accounts.get_account_by_id(@account_id).auth_failed? }
    d.check('the open accounts dialog shows the error icon') do
      @accounts_dialog.accounts_list.get_row_at_index(0).then do |row|
        descendants(row).select { |widget| widget.is_a?(Gtk::Image) && widget.icon_name == 'dialog-error-symbolic' }
                        .any?(&:visible?)
      end
    end
    d.shot('15-auth-failed')
  end

  d.step('the token starts working again') do
    session.responses = OK_RESPONSES.dup
    app.window.reload
  end

  d.step('wait for the recovering fetch') { nil }

  d.step('the banner goes away once the account authenticates') do
    d.check('the banner is hidden') { !app.window.account_banner.revealed? }
    d.check('the account is no longer marked') { !app.accounts.get_account_by_id(@account_id).auth_failed? }
    d.check('the error icon is hidden again') do
      @accounts_dialog.accounts_list.get_row_at_index(0).then do |row|
        descendants(row).select { |widget| widget.is_a?(Gtk::Image) && widget.icon_name == 'dialog-error-symbolic' }
                        .none?(&:visible?)
      end
    end
    d.check('the notification came back') { app.window.model.n_items == 1 }
  end

  # --- Editing the account -------------------------------------------------

  d.step('the edit dialog opens by activating the account row') do
    @accounts_dialog.accounts_list.get_row_at_index(0).activate
  end

  d.step('wait for the saved token to load') { nil }

  d.step('the edit dialog is filled in from the saved account') do
    app.window.visible_dialog.then do |dialog|
      d.check('a dialog is up') { !dialog.nil? }
      d.check('it is titled Edit Account') { dialog.title == 'Edit Account' }
    end
    app.window.visible_dialog&.close
  end

  d.step('the edit dialog is driven directly') do
    AccountDialog.new(
      app.accounts.get_account_by_id(@account_id),
      accounts: app.accounts,
      on_saved: -> { app.window.reload },
    ).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @edit = dialog
    end
  end

  d.step('wait for the token lookup') { nil }

  d.step('the edit dialog shows the saved account') do
    d.check('editing') { @edit.editing? }
    d.check('forge row is hidden while editing') { !@edit.forge_row.visible? }
    d.check('remove group is visible while editing') { @edit.remove_group.visible? }
    d.check('save is labelled Save') { @edit.save_button.label == 'Save' }
    d.check('the subtitle is the display name') { @edit.title_widget.subtitle == 'octocat@github.com' }
    d.check('the instance is prefilled') { @edit.instance_row.text == 'github.com' }
    d.check('the saved token was loaded') { @edit.access_token_row.text == 'a-token' }
    d.check('nothing changed, so save is insensitive') { !@edit.save_button.sensitive? }
    d.check('remove is destructive') { @edit.remove_button.css_classes.include?('destructive-action') }
    d.shot('16-edit-account', @edit.child)
  end

  d.step('changing the token makes the edit saveable') do
    @edit.access_token_row.text = 'a-new-token'
    d.check('save is sensitive') { @edit.save_button.sensitive? }
    @edit.instance_row.text = 'ex ample.com'
    d.check('a bad url marks the entry') { @edit.instance_row.css_classes.include?('error') }
    d.check('a bad url blocks saving') { !@edit.save_button.sensitive? }
    @edit.instance_row.text = 'github.com'
    d.check('a good url unblocks it') { @edit.save_button.sensitive? }
    @edit.save_button.signal_emit('clicked')
  end

  d.step('wait for the save request') { nil }

  d.step('the edited token was written back') do
    d.check('the new token is in the store') { app.accounts.get_account_token(@account_id) == 'a-new-token' }
    d.check('the username came from the forge') do
      app.accounts.get_account_by_id(@account_id).username == 'octocat'
    end
    d.check('the user id came from the forge') { app.accounts.get_account_by_id(@account_id).user_id == 42 }
    d.check('the dialog closed itself') { app.window.visible_dialog.title == 'Accounts' }
  end

  # --- Removing the account ------------------------------------------------

  d.step('the remove button is pressed') do
    AccountDialog.new(
      app.accounts.get_account_by_id(@account_id),
      accounts: app.accounts,
      on_saved: -> { app.window.reload },
    ).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @remove_dialog = dialog
    end
  end

  d.step('wait for the dialog to settle') { nil }

  d.step('removing the account empties everything') do
    @remove_dialog.remove_button.signal_emit('clicked')
  end

  d.step('wait for the removal') { nil }

  d.step('the account is gone') do
    d.check('no accounts left') { app.accounts.n_items.zero? }
    d.check('the settings forgot it') { Util.settings['accounts'].empty? }
    d.check('the token is gone') { app.accounts.get_account_token(@account_id).nil? }
    d.check('the accounts dialog is empty again') do
      @accounts_dialog.accounts_stack.visible_child_name == 'empty'
    end
    d.check('the banner is down') { !app.window.account_banner.revealed? }
    d.shot('17-removed')
    @accounts_dialog.close
  end

  # --- Actions and accelerators -------------------------------------------

  d.step('the app still has its actions and accelerators') do
    Application::ACTIONS.each_key do |name|
      d.check("app.#{name} exists") { !app.app.lookup_action(name).nil? }
    end
    Application::ACCELS.each do |action, accels|
      d.check("#{action} is bound to #{accels.join(', ')}") do
        canonical_accels(app.app.get_accels_for_action(action)) == canonical_accels(accels)
      end
    end
    d.check('win.show-help-overlay exists') { !app.window.lookup_action('show-help-overlay').nil? }
    d.check('win.open-primary-menu exists') { !app.window.lookup_action('open-primary-menu').nil? }
  end

  d.step('every dialog action opens its dialog once') do
    app.app.activate_action('preferences', nil)
    app.app.activate_action('preferences', nil)
  end

  d.step('the preferences dialog is a singleton') do
    d.check('one preferences dialog is up') { app.window.visible_dialog.is_a?(Adwaita::PreferencesDialog) }
    app.window.visible_dialog&.close
  end

  d.step('the accounts action opens the accounts dialog') do
    app.app.activate_action('accounts', nil)
    app.app.activate_action('accounts', nil)
  end

  d.step('the accounts dialog is a singleton') do
    d.check('a dialog is up') { !app.window.visible_dialog.nil? }
    d.check('it is titled Accounts') { app.window.visible_dialog.title == 'Accounts' }
    app.window.visible_dialog&.close
  end

  d.step('the remaining actions run') do
    app.app.activate_action('reload', nil)
    app.app.activate_action('activate', nil)
    app.app.activate_action(
      'open-notification',
      GLib::Variant.new(['nothing', 'https://example.com/nothing']),
    )
    d.check('the window survived') { !app.window.nil? }
    d.check('the window is still presented') { app.window.visible? }
  end

  # --- Settings, and closing ----------------------------------------------

  d.step('the window settings round-trip') do
    Util.settings.remember(app.window)
    d.check('window size saved') { Util.settings['window-size'].length == 2 }
    d.check('settings file written') { File.exist?(Util.settings.location) }
    d.check('settings survive a reload from disk') do
      Settings.new(path: Util.settings.location)['accounts'].empty?
    end
    d.check('first-run was recorded') { Util.settings['first-run'] == true }
    d.check('the notified dict is a hash') { Util.settings['notified'].is_a?(Hash) }
  end

  d.step('app.close closes the window') do
    app.app.activate_action('close', nil)
  end

  d.step('the window went away') do
    d.check('the window is not visible') { !app.window.visible? }
  end

  d.step('app.quit quits the app') do
    d.check('quit action is there') { !app.app.lookup_action('quit').nil? }
    app.app.activate_action('quit', nil)
  end
end

FileUtils.remove_entry(scratch)
